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
| `HUDUpdate` | Server → Client | Push live timer, score, and objective states to the HUD |
| `KioskShowConfirmation` | Server → Client | Show or hide the kiosk ConfirmationUI screen with selection payload |
| `ShowResults` | Server → Client | Send the completed results payload to the results screen |
| `ToggleDoor` *(per door)* | Client → Server | Request a door toggle from a VR hand interaction |
| `KioskConfirm` | Client → Server | Player confirms the kiosk selection |
| `KioskCancel` | Client → Server | Player cancels the kiosk selection |
| `ReturnToLobby` | Client → Server | Player requests teleport back to the main lobby from the results screen |

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

All authoritative logic runs on the server. Five scripts handle distinct concerns, supported by a `modules/` folder of reusable ModuleScripts.

### 4.1 SimulationController (`src/server/SimulationController.server.lua`)

The central dispatcher for all simulation types. After a major refactor, most logic has been moved into dedicated modules under `src/server/modules/`. The controller itself is now a thin coordinator.

**Responsibilities:**
- Requires all simulation and service modules at startup.
- Listens to `SimulationStartBindable` and dispatches to the correct simulation module.
- Maintains `activeSimulations` (prevents duplicate concurrent simulations per location).
- Maintains `playerSimulationData` (per-player state: step times, connections, seed parts).
- Handles `HighlightPartBindable`, `FinishedTaskBindable`, and `PhysicalActuatorBindable` events.
- Cleans up all state on player disconnect.
- Builds and passes the `services` and `state` context tables to each simulation module call.

**Key internal tables:**
```
activeSimulations    -- { "SimType_Location" → true }
playerSimulationData -- { userId → { waypointTimes, lastWaypointTime, maxTimes, ... } }
```

**Simulation entry point:**
```
SimulationStartBindable.Event
  └── (player, eventType, locationName, difficultyStr)
        ├── FireSimulation        → FireSimulation.start()
        ├── EarthquakeSimulation  → EarthquakeSimulation.start()
        ├── ArmedGroupsSimulation → ArmedGroupsSimulation.start()
        └── ExploreSimulation     → startExploreSimulation() (inline)
```

**Context tables passed to simulation modules:**
```
services = {
  setPowerMode, canStartSimulation, setSimulationActive,
  playIntercomSound, HUDService, controllerHUDEvent, hudUpdateEvent,
  mainLobbySpawn, FIRE_ALARM_SOUND_ID, EARTHQUAKE_ALARM_SOUND_ID,
  SIMULATION_GLOBAL_TIMEOUT
}
state = {
  playerSimulationData
}
```

### 4.2 KioskController (`src/server/KioskController.server.lua`)

Manages the physical in-world kiosk for simulation selection and launch.

**Responsibilities:**
- Detects player proximity via a `Hitbox` part `Touched`/`TouchEnded` events.
- Runs a sequential coroutine-based flow on the kiosk `SurfaceGui`:
  1. Mode selection (`ModeSelector` frame).
  2. Location selection (`LocationSelector` frame).
  3. Difficulty selection (`DiffSelector` frame).
  4. Confirmation step: sends `KioskShowConfirmation` to the player's client, waits for `KioskConfirm` or `KioskCancel`.
- On confirmation, fires `SimulationStartBindable` with `(player, mode, location, difficulty)`.
- Creates `KioskShowConfirmation`, `KioskConfirm`, and `KioskCancel` RemoteEvents in `ReplicatedStorage` at startup if they do not already exist.
- Resets kiosk UI and state when the player leaves the hitbox or disconnects.
- Reads display names from `KioskConfig` (`ReplicatedStorage.Shared.KioskConfig`).

**Place file dependencies:** `workspace.Menu` model with `MenuScreen` (Part with `SurfaceGui`) and `Hitbox` (Part).

### 4.3 GlobalLightingController (`src/server/GlobalLightingController.server.lua`)

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

### 4.4 CycleController (`src/server/CycleController.server.lua`)

Drives the in-game day/night cycle.

**Responsibilities:**
- Increments `Lighting.ClockTime` every heartbeat based on `DAY_LENGTH_SECONDS` (default: 30 real seconds = 24 game hours).
- Freezes the clock at midnight (`ClockTime = 0`) when `PowerMode == "BLACKOUT"` and resets atmosphere density.

### 4.5 DoorSystem (`src/server/DoorSystem.server.lua`)

Centralized server coordinator for all interactive doors.

**Responsibilities:**
- Scans `workspace` for `Model` instances with a `DoorType` attribute.
- Initializes each door via modular handlers based on `DoorType`.
- Supports runtime door models via `workspace.DescendantAdded` initialization.
- Leaves client interaction contract unchanged (`ToggleDoor` RemoteEvent is still fired by `VRDoorInteractor`).

**Door modules:**
- `src/server/modules/doors/HingeDoor.lua` — Hinge doors (CFrame rotation around `Hinge`).
- `src/server/modules/doors/SlidingDoor.lua` — Sliding doors (positional offset from `SlidePivot`).

### 4.6 Server Modules (`src/server/modules/`)

Reusable ModuleScripts required by the server scripts above.

| Module | Purpose |
|---|---|
| `ActuatorConfig` | Holds `API_URL` and `API_KEY` for the physical actuator HTTP API |
| `ActuatorService` | Fires actuator commands via `HttpService:PostAsync` with callback |
| `DialogService` | Safe wrapper for `ShowDialog:FireClient` with player validation |
| `HUDService` | Per-player ticker loop that pushes live timer/score/objectives via `HUDUpdate` |
| `NavigationUtils` | Teleport, waypoint lookup, refuge lookup, highlight, and touch detection helpers |
| `ScoringSystem` | `calculateScore()`, `getGrade()`, and legacy `showFinalResults()` (dialog-based) |
| `ResultsSystem` | Computes rank payload and fires it to the client via `ShowResults` RemoteEvent; also handles `ReturnToLobby` |
| `FireSimulation` | Complete fire drill flow, procedural fire spread, and firefighter NPC management |
| `EarthquakeSimulation` | Complete earthquake drill flow, physics drops, and aftershock sequences |
| `ArmedGroupsSimulation` | Complete armed-groups drill flow including NPC spawning and death detection |

---

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
- Listens to `HUDUpdate` RemoteEvent to receive live timer, score, and objective state updates pushed by `HUDService`.
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

### 5.4 ConfirmationUIHandler (`src/client/ConfirmationUIHandler.client.lua`)

Displays a summary of the player's kiosk selection and collects the final confirm action before starting a simulation.

**Key behaviors:**
- Listens to `KioskShowConfirmation` RemoteEvent from the server. Payload is `{ mode, location, diff }` to show, or `nil` to hide.
- Reads step names from `KioskConfig.getSteps(mode).stepNamesDetailed` to populate `Objective1`–`Objective4` labels.
- Animates three UI elements (`Panel`, `Controles`, `btnConfirm`) in with a staggered Quint slide-up effect.
- On confirm button press, fires `KioskConfirm:FireServer()` and hides the UI.

**UI dependencies:** `ConfirmationUI` ScreenGui (in `StarterGui`) with `Panel > Objectives`, `Controles`, and `Confirmar` children.

**RemoteEvent dependencies:** `KioskShowConfirmation` (S→C), `KioskConfirm` (C→S).

**Shared module dependency:** `ReplicatedStorage.Shared.KioskConfig`.

### 5.5 ResultsScreenHandler (`src/client/ResultsScreenHandler.client.lua`)

Displays the detailed simulation results screen after a simulation ends.

**Key behaviors:**
- Listens to `ShowResults` RemoteEvent. Payload is a table computed by `ResultsSystem.compute()`.
- Populates rank label (`LabelRank`) with colour-coded rank text, rank band image (`RankContainer`), points, time, precision %, critical errors, and objective counts.
- Populates per-step rows (`Steps/Step1`–`Step4`): each row shows step name, elapsed time, and points.
- Animates the `Container` frame in from below with a Quint slide-up; step rows fade in with a stagger.
- `BtnReturn` fires `ReturnToLobby:FireServer()` which triggers server-side teleport back to the main lobby.

**Rank bands and colours:**
| Rank | Band | Colour |
|---|---|---|
| S, A+, A | GREEN | `rgb(80, 200, 80)` |
| B+, B, C+ | YELLOW | `rgb(240, 200, 60)` |
| C, D | RED | `rgb(220, 70, 70)` |

**UI dependencies:** `ResultsScreen` ScreenGui with `Container > LabelHeader`, `LabelRank`, `LabelPoints`, `LabelTime`, `LabelPrecision`, `LabelErrors`, `LabelObjectives`, `RankContainer`, `Steps/Step1..4`, `BtnReturn`.

**RemoteEvent dependencies:** `ShowResults` (S→C), `ReturnToLobby` (C→S).

### 5.6 VRDoorInteractor (`src/client/VRDoorInteractor.client.lua`)

Handles door interaction in VR using hand raycasting.

**Key behaviors:**
- Reads VR hand CFrames from `NexusVRCharacterModel`'s `VRInputService` singleton.
- On `ButtonR2` or `ButtonL2` gamepad input, fires a raycast from the corresponding hand up to 2 studs forward.
- Walks up the instance hierarchy of the hit result looking for a `ToggleDoor` RemoteEvent.
- If found, fires the event to the server.

### 5.7 LoadingContainerLoader (`src/client/LoadingContainerLoader.client.lua`)

Plays the intro/loading sequence when a player first joins.

**Key behaviors:**
- Waits for `game:IsLoaded()`.
- Runs a scripted tween timeline: title/subtitle fade in → pause → fade out → logo fade in → logo fade out → black screen fade → hide GUI.
- All steps are sequential and time-coded.

---

## 6. Shared Modules (`src/shared/`)

### 6.1 KioskConfig (`src/shared/KioskConfig.lua`)

The single source of truth for all kiosk-driven simulation configuration. Located at `ReplicatedStorage.Shared.KioskConfig` so it is accessible from both server and client scripts.

**Contents:**
- `MODES` — list of simulation mode entries with `name`, `display`, and `description` fields.
- `DIFFICULTIES` — list of difficulty entries with `name`, `display`, `level` (1/2/3), and `description` fields.
- `SIMULATION_STEPS` — per-simulation-type tables containing `stepNames` (short, used in HUD), `stepNamesDetailed` (used in ConfirmationUI), `maxTimes` (seconds per step, used by `ScoringSystem`), and a `description` string.

**Lookup helpers:** `getModeData`, `getDifficultyData`, `getDifficultyByLevel`, `getSteps`, `getModeDisplay`, `getDifficultyDisplay`.

**Used by:** `KioskController` (display names), `ConfirmationUIHandler` (step details), `FireSimulation` / `EarthquakeSimulation` / `ArmedGroupsSimulation` (step names and max times).

---

## 7. Data Flow: Starting a Simulation via the Kiosk

The following shows a typical flow when a player uses the kiosk to start a Fire Simulation:

```
[Player steps on Hitbox — KioskController — Server]
  ├── Shows "Start" button on SurfaceGui
  ├── Player clicks Start → startConfig() coroutine begins
  │     ├── ModeSelector frame shown  → player picks "FireSimulation"
  │     ├── LocationSelector shown    → player picks "BuildingA"
  │     ├── DiffSelector shown        → player picks "Medium"
  │     └── Fires KioskShowConfirmation:FireClient(player, { mode, location, diff })
  │           └── ConfirmationUIHandler populates objectives from KioskConfig
  │                 and shows ConfirmationUI with stagger animation
  ├── Player clicks Confirmar → KioskConfirm:FireServer()
  │     └── KioskController receives confirm, fires SimulationStartBindable
  │
[SimulationController — Server]
  ├── Validates player, type, location, difficulty
  ├── Calls FireSimulation.start(player, locationName, difficulty, services, state)
  │
[FireSimulation module — Server]
  ├── Sets activeSimulations["Fire_BuildingA"] = true
  ├── Sets PowerMode = "BLACKOUT"
  │     └── GlobalLightingController reacts, kills all non-emergency lights
  ├── Collects building parts, picks fire origin (seedPart)
  ├── Teleports player to nearest spawn
  ├── Creates session in playerSimulationData, starts HUDService ticker
  │     └── HUDService pushes HUDUpdate every second → HUDHandler updates live timer/score
  ├── Fires ControllerUI_HUD:FireClient(player, "Show")
  │     └── HUDHandler animates HUD panels in
  ├── Fires ShowDialog:FireClient(player, "Warning", "...")
  │     └── DialogHandler queues and displays the message
  ├── Fires CameraShakeEvent:FireClient(player, duration, scale)
  │     └── CameraShakeHandler applies shake
  ├── Runs spreadFire() in a parallel task.spawn
  ├── Sets up proximity detection for step 1, then waypoint detection for steps 2–4
  └── On final waypoint reached:
        ├── cleanup() — extinguishes fire, hides firefighters, resets PowerMode
        ├── Fires ControllerUI_HUD:FireClient(player, "Hide")
        │     └── HUDHandler animates HUD panels out
        └── ResultsSystem.show() — computes payload, fires ShowResults:FireClient(player, payload)
              └── ResultsScreenHandler populates and animates the results screen
                    └── Player clicks Menú principal → ReturnToLobby:FireServer()
                          └── ResultsSystem handler teleports player to MainLobby
```

---

## 8. Design Patterns

| Pattern | Where used |
|---|---|
| **Server-authoritative state** | All simulation logic, scoring, and world changes run on the server |
| **Event-driven coordination** | BindableEvents and RemoteEvents decouple systems |
| **Modular simulation architecture** | Each simulation type is a separate module under `src/server/modules/`, receiving `services` and `state` context tables |
| **Procedural generation** | Fire spread and earthquake object selection are randomized at runtime |
| **Caching + dirty-flag** | `GlobalLightingController` caches scene objects and uses `lastAppliedKey` to skip redundant updates |
| **Lightweight OOP (table as object)** | `DialogSystem` in `DialogHandler` uses a Lua table with methods |
| **Parallel tasks** | `task.spawn` is used for fire propagation, aftershock sequences, and dialog processing without blocking the main coroutine |
| **Global timeout safety net** | Each simulation module uses `task.delay(SIMULATION_GLOBAL_TIMEOUT, ...)` to force-end any simulation that exceeds 5 minutes |
| **Client-triggered lobby return** | Results are pushed to the client via `ShowResults`; the player explicitly triggers return via `ReturnToLobby`, keeping server logic stateless for that step |
| **Shared config module** | `KioskConfig` (in `src/shared/`) is the single source of truth for step names, max times, and display strings, used by both server modules and client scripts |

---

## 9. External Integration

The server makes outbound HTTP calls to a physical actuator API:

```
POST https://myurlhere.com/api/actuator
Headers: Authorization: Bearer <API_KEY>
Body: { actuator, value, duration, player, timestamp }
```

This is triggered by direct calls to `ActuatorService.fire()` from within simulation modules (e.g. `FireSimulation` activates a heater actuator after a configurable delay). It is also callable from external scripts via the `PhysicalActuatorBindable` BindableEvent. The call is wrapped in `pcall` to prevent simulation crashes on network failure.

The API URL and key are stored in `src/server/modules/ActuatorConfig.lua`. **Do not commit real credentials.** Replace the placeholder values before deployment or use a secure resolver pattern.

---

## 10. Workspace Dependencies

The scripts assume the following folder and object hierarchy exists in the Roblox place (not in this repository):

```
workspace/
├── <LocationName>              ← Building model (e.g. "BuildingA")
├── AtacantsSpawns/
│   └── <LocationName>/         ← BaseParts/Models/Attachments for NPC spawns
├── FireWaypoints/
│   └── Firefighters/           ← NPC models with HumanoidRootPart
├── Menu/                       ← Kiosk model
│   ├── MenuScreen/             ← Part containing a SurfaceGui
│   └── Hitbox                  ← BasePart for proximity detection
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