# EMBER — Architecture Overview

This document describes the internal architecture of the EMBER simulator: how the codebase is organized, how scripts communicate, and where the core logic lives.

---

## 1. Execution Model

EMBER follows the standard Roblox client-server architecture.

| Domain | Scripts run on | Roblox container | Folder in repo |
|---|---|---|---|
| **Server** | Roblox server only | `ServerScriptService` | `src/server/` |
| **Client** | Each player's machine | `StarterPlayerScripts` | `src/client/` |
| **Shared** | Accessible from both | `ReplicatedStorage` | `src/shared/` *(empty in repo)* |

The server is authoritative over all simulation state. Clients only handle rendering, UI, and input.

---

## 2. Rojo Project Structure

Rojo maps the file system to the Roblox DataModel using `default.project.json`:

```json
{
  "ReplicatedStorage > Shared"        ← src/shared/
  "ServerScriptService > Server"      ← src/server/
  "StarterPlayer > StarterPlayerScripts > Client" ← src/client/
}
```

All `*.server.lua` files become `Script` instances.  
All `*.client.lua` files become `LocalScript` instances.  
Files in `src/shared/` would become `ModuleScript` instances.

---

## 3. Inter-Script Communication

Scripts on different sides cannot call each other directly. EMBER uses the following Roblox communication primitives, all pre-created inside `ReplicatedStorage`:

### RemoteEvents (Server ↔ Client, fire-and-forget)

| Event name | Direction | Purpose |
|---|---|---|
| `ShowDialog` | Server → Client | Send a notification message to a player's dialog system |
| `CameraShakeEvent` | Server → Client | Trigger a camera shake effect with duration and scale |
| `ControllerUI_HUD` | Server → Client | Show or hide the simulation HUD |
| `ToggleDoor` *(per door)* | Client → Server | Request a door toggle from a VR hand interaction |

### BindableEvents (Server → Server, same-side signaling)

| Event name | Purpose |
|---|---|
| `SimulationStartBindable` | External UI/trigger fires this to start a simulation |
| `HighlightPartBindable` | Request a highlight effect on a BasePart |
| `FinishedTaskBindable` | Mark a task as completed for a player |
| `PhysicalActuatorBindable` | Send a command to a physical haptic actuator via HTTP |
| `PowerControl` *(optional)* | Fire to change the global `PowerMode` attribute |

---

## 4. Server-Side Architecture

All authoritative logic runs on the server. Three scripts handle distinct concerns.

### 4.1 SimulationController (`src/server/SimulationController.server.lua`)

The largest and most complex script in the project. It is the central coordinator for all simulation types.

**Responsibilities:**
- Listens to `SimulationStartBindable` and dispatches to the correct simulation function.
- Maintains `activeSimulations` (prevents duplicate concurrent simulations per location).
- Maintains `playerSimulationData` (per-player state: step times, connections, seed parts).
- Manages teleportation to spawn points and waypoint detection.
- Runs procedural fire propagation (`spreadFire`) and earthquake object drops (`applyEarthquakeDrops`).
- Controls firefighter NPC visibility.
- Spawns and destroys antagonist NPCs for the armed groups scenario.
- Calls the external haptic actuator API via `HttpService:PostAsync`.
- Fires dialog messages and camera shake events to the client.
- Calculates and displays final scoring results.
- Cleans up all state on player disconnect.

**Key internal tables:**
```
activeSimulations    -- { "SimType_Location" → true }
playerSimulationData -- { userId → { waypointTimes, lastWaypointTime, maxTimes, ... } }
firefightersData     -- { HumanoidRootPart → { OriginalCFrame, OriginalAnchored } }
```

**Simulation entry point:**
```
SimulationStartBindable.Event
  └── (player, eventType, locationName, difficultyStr)
        ├── FireSimulation        → startFireSimulation()
        ├── EarthquakeSimulation  → startEarthquakeSimulation()
        ├── ArmedGroupsSimulation → startArmedGroupsSimulation()
        └── ExploreSimulation     → startExploreSimulation()
```

### 4.2 GlobalLightingController (`src/server/GlobalLightingController.server.lua`)

Manages all dynamic lighting across the entire map.

**Responsibilities:**
- Caches all `PointLight`, `SurfaceLight`, `SpotLight`, `Neon` parts, and `Glass` parts at startup.
- Reacts to the `PowerMode` attribute on the `Lighting` service (values: `NORMAL`, `BLACKOUT`, `FORCE_ON`).
- On each state change, updates light brightness/color, material (Neon ↔ SmoothPlastic), and glass transparency using TweenService for smooth transitions.
- Supports an `Emergency` tag/attribute on individual instances, which inverts their behavior during a blackout (emergency lights turn *on* when power goes *off*).
- Polls every 2 seconds as a safety net for missed changes.

**State key:**
```
lastAppliedKey = "NORMAL|D"  -- mode + day/night flag
```
Changes are only applied when the key actually changes, preventing redundant updates.

### 4.3 CycleController (`src/server/CycleController.server.lua`)

Drives the in-game day/night cycle.

**Responsibilities:**
- Increments `Lighting.ClockTime` every heartbeat based on `DAY_LENGTH_SECONDS` (default: 30 real seconds = 24 game hours).
- Freezes the clock at midnight (`ClockTime = 0`) when `PowerMode == "BLACKOUT"` and resets atmosphere density.

---

## 5. Client-Side Architecture

Each LocalScript runs independently on the player's machine and reacts to server events or local input.

### 5.1 DialogHandler (`src/client/DialogHandler.client.lua`)

A self-contained dialog notification system.

**Design pattern:** Object-with-methods table (`DialogSystem`), acting as a lightweight class.

**Key behaviors:**
- Maintains a priority queue (max 6 items). Error-priority messages clear the queue.
- Duplicate suppression: identical messages within a 2-second window are dropped.
- Each message animates in (slide up with Back easing), plays a typewriter text effect, waits for a calculated display time, then animates out.
- Icon is set from a local `ICON_MAP` table keyed by type string (`Info`, `Warning`, `Success`, `Error`, `Result`).

### 5.2 HUDHandler (`src/client/HUDHandler.client.lua`)

Controls the visibility of the simulation HUD elements.

**Key behaviors:**
- Listens to `ControllerUI_HUD` RemoteEvent for `"Show"` or `"Hide"` actions.
- Animates four UI panels (simulation status, time remaining, score, objectives) using TweenService with per-element SHOW/HIDE position tables.
- Also tweens an overlay image transparency.

### 5.3 CameraShakeHandler (`src/client/CameraShakeHandler.client.lua`)

Applies procedural camera shake on the client.

**Key behaviors:**
- Listens to `CameraShakeEvent` RemoteEvent.
- Detects VR via `VRService.VREnabled` and chooses a different shake implementation:
  - **Non-VR:** Directly offsets `camera.CFrame` using a multi-frequency sine wave composite.
  - **VR:** Uses `Humanoid.CameraOffset` with reduced intensity to avoid motion sickness. Compatible with NexusVR framework conventions.
- Both implementations use an ease-in/ease-out cubic envelope over the shake duration.

### 5.4 VRDoorInteractor (`src/client/VRDoorInteractor.client.lua`)

Handles door interaction in VR using hand raycasting.

**Key behaviors:**
- Reads VR hand CFrames from `NexusVRCharacterModel`'s `VRInputService` singleton.
- On `ButtonR2` or `ButtonL2` gamepad input, fires a raycast from the corresponding hand up to 2 studs forward.
- Walks up the instance hierarchy of the hit result looking for a `ToggleDoor` RemoteEvent.
- If found, fires the event to the server.

### 5.5 LoadingContainerLoader (`src/client/LoadingContainerLoader.client.lua`)

Plays the intro/loading sequence when a player first joins.

**Key behaviors:**
- Waits for `game:IsLoaded()`.
- Runs a scripted tween timeline: title/subtitle fade in → pause → fade out → logo fade in → logo fade out → black screen fade → hide GUI.
- All steps are sequential and time-coded.

---

## 6. Data Flow: Starting a Simulation

The following shows a typical flow when a player starts a Fire Simulation:

```
[External UI / Trigger]
  └── Fires SimulationStartBindable
        with (player, "FireSimulation", "BuildingA", "Medium")

[SimulationController — Server]
  ├── Validates player, type, location, difficulty
  ├── Sets activeSimulations["Fire_BuildingA"] = true
  ├── Sets PowerMode = "BLACKOUT"
  │     └── GlobalLightingController reacts, kills all non-emergency lights
  ├── Collects building parts, picks fire origin
  ├── Teleports player to nearest spawn
  ├── Fires ControllerUI_HUD:FireClient(player, "Show")
  │     └── HUDHandler animates HUD panels in
  ├── Fires ShowDialog:FireClient(player, "Warning", "...")
  │     └── DialogHandler queues and displays the message
  ├── Fires CameraShakeEvent:FireClient(player, duration, scale)
  │     └── CameraShakeHandler applies shake
  ├── Runs spreadFire() in a parallel task.spawn
  ├── Sets up waypoint touch detection (steps 1–4)
  └── On final waypoint reached:
        ├── cleanup() — extinguishes fire, restores NPCs, resets PowerMode
        ├── showFinalResults() — sends Result dialogs, teleports to lobby
        └── Fires ControllerUI_HUD:FireClient(player, "Hide")
              └── HUDHandler animates HUD panels out
```

---

## 7. Design Patterns

| Pattern | Where used |
|---|---|
| **Server-authoritative state** | All simulation logic, scoring, and world changes run on the server |
| **Event-driven coordination** | BindableEvents and RemoteEvents decouple systems |
| **Procedural generation** | Fire spread and earthquake object selection are randomized at runtime |
| **Caching + dirty-flag** | `GlobalLightingController` caches scene objects and uses `lastAppliedKey` to skip redundant updates |
| **Lightweight OOP (table as object)** | `DialogSystem` in `DialogHandler` uses a Lua table with methods |
| **Parallel tasks** | `task.spawn` is used for fire propagation, aftershock sequences, and dialog processing without blocking the main coroutine |
| **Global timeout safety net** | `SimulationController` uses `task.delay(SIMULATION_GLOBAL_TIMEOUT, ...)` to force-end any simulation that exceeds 5 minutes |

---

## 8. External Integration

The server makes outbound HTTP calls to a physical actuator API:

```
POST https://myurlhere.com/api/actuator
Headers: Authorization: Bearer <API_KEY>
Body: { actuator, value, duration, player, timestamp }
```

This is triggered via `PhysicalActuatorBindable` and used to control the haptic feedback hardware in the physical VR cabin prototype. The call is wrapped in `pcall` to prevent simulation crashes on network failure.

---

## 9. Workspace Dependencies

The scripts assume the following folder and object hierarchy exists in the Roblox place (not in this repository):

```
workspace/
├── <LocationName>              ← Building model (e.g. "BuildingA")
├── AtacantsSpawns/
│   └── <LocationName>/         ← BaseParts for NPC spawns
├── FireWaypoints/
│   └── Firefighters/           ← NPC models with HumanoidRootPart
├── Spawnpoints/
│   ├── MainLobby               ← Single BasePart
│   └── <LocationName>/
│       ├── FireSimulation/
│       ├── EarthquakeSimulation/
│       └── ArmedGroupsSimulation/
├── Waypoints/
│   └── <LocationName>/
│       ├── FireSimulation/Waypoint1..N
│       ├── EarthquakeSimulation/Waypoint1..N
│       └── ArmedGroupsSimulation/Waypoint1..N
├── Refugees/
│   └── <LocationName>/
│       ├── EarthquakeSimulation/Refuge1..N
│       └── ArmedGroupsSimulation/Refuge1..N
└── Intercom/
    └── AudioPlayer             ← Sound instance
```