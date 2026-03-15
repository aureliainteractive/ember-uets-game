# EMBER — Systems Reference

This document describes each major system in the EMBER simulator, its purpose, the scripts that implement it, and how it interacts with other systems.

---

## System Index

1. [Simulation Controller](#1-simulation-controller)
2. [Fire Simulation System](#2-fire-simulation-system)
3. [Earthquake Simulation System](#3-earthquake-simulation-system)
4. [Armed Groups Simulation System](#4-armed-groups-simulation-system)
5. [Explore Mode](#5-explore-mode)
6. [Scoring and Results System](#6-scoring-and-results-system)
7. [Waypoint and Refuge Detection System](#7-waypoint-and-refuge-detection-system)
8. [Dialog Notification System](#8-dialog-notification-system)
9. [HUD System](#9-hud-system)
10. [Camera Shake System](#10-camera-shake-system)
11. [Global Lighting System](#11-global-lighting-system)
12. [Day/Night Cycle System](#12-daynight-cycle-system)
13. [VR Door Interaction System](#13-vr-door-interaction-system)
14. [Loading Screen System](#14-loading-screen-system)
15. [Firefighter NPC Manager](#15-firefighter-npc-manager)
16. [Physical Actuator Integration](#16-physical-actuator-integration)

---

## 1. Simulation Controller

**Purpose:** Central coordinator and entry point for all simulation types. Manages the full lifecycle of each simulation from start to cleanup.

**Script:** `src/server/SimulationController.server.lua`

**Responsibilities:**
- Listens to `SimulationStartBindable` (BindableEvent) and dispatches to the correct simulation handler based on `eventType`.
- Prevents duplicate concurrent simulations for the same type and location using `activeSimulations`.
- Stores per-player simulation state in `playerSimulationData` (step times, connections, seed references, completion flags).
- Provides shared utilities used by all simulation types: teleportation, waypoint setup, dialog dispatch, power mode changes, and highlight management.
- Cleans up all state when a player disconnects mid-simulation.
- Enforces a global 5-minute safety timeout on any simulation.

**Input event:**
```
SimulationStartBindable:Fire(player, eventType, locationName, difficultyStr)
```

**Interacts with:**
- Dialog Notification System (via `ShowDialog` RemoteEvent)
- HUD System (via `ControllerUI_HUD` RemoteEvent)
- Camera Shake System (via `CameraShakeEvent` RemoteEvent)
- Global Lighting System (via `Lighting:SetAttribute("PowerMode", ...)`)
- Scoring and Results System (calls `showFinalResults`)
- Waypoint and Refuge Detection System (calls `setupWaypointDetection`, `setupRefugeDetection`)
- Firefighter NPC Manager (calls `showFirefighters`, `hideFirefighters`)
- Physical Actuator Integration (via `PhysicalActuatorBindable`)

---

## 2. Fire Simulation System

**Purpose:** Simulates a fire emergency scenario inside a building. Guides the player through a 4-step evacuation protocol while procedural fire spreads through the building.

**Script:** `src/server/SimulationController.server.lua` — function `startFireSimulation()`

**Protocol steps:**
1. Locate the fire origin (proximity detection within 40 studs).
2. Activate the fire alarm (reach Waypoint2).
3. Evacuate the building (reach Waypoint3).
4. Reach the external assembly point (reach Waypoint4).

**Difficulty parameters:**

| Level | Fire duration | Heater activation delay |
|---|---|---|
| Easy (1) | 55 s | 35 s |
| Medium (2) | 70 s | 25 s |
| Hard (3) | 90 s | 18 s |

**Procedural fire subsystem:**

- `collectBuildingParts()` — Scans the building model and returns all valid `BasePart` instances above a minimum volume threshold. Yields every 2000 objects to prevent server freezes.
- `pickFireOrigin()` — Samples 80 random parts and selects the one with the greatest volume as the fire seed.
- `spreadFire()` — Runs in a `task.spawn` coroutine. Each wave picks a random active "front" part and ignites nearby parts within the spread radius. Older burning parts are extinguished when the total exceeds `maxTotal` to manage performance.
- `ignite()` / `extinguish()` — Add or remove `Fire` and `Smoke` instances with size and heat scaled to difficulty.

**Fire effect parameters by difficulty:**

| Level | Spread radius | Parts/wave | Wave interval | Max burning |
|---|---|---|---|---|
| Easy | 18 studs | 6 | 4.0 s | 100 |
| Medium | 26 studs | 10 | 3.0 s | 150 |
| Hard | 35 studs | 14 | 2.0 s | 200 |

**Interacts with:** Simulation Controller, Global Lighting System, Firefighter NPC Manager, Waypoint Detection System, Dialog System, Camera Shake System, Physical Actuator Integration, Scoring System.

---

## 3. Earthquake Simulation System

**Purpose:** Simulates a seismic event. Players shelter in place, then evacuate. Physics-based object drops and camera shake create immersive stress.

**Script:** `src/server/SimulationController.server.lua` — function `startEarthquakeSimulation()`

**Protocol steps:**
1. Shelter in place at a designated refuge point.
2. Evacuate the building (reach Waypoint2).
3. Reach the external safe zone (Waypoint3).

**Difficulty parameters:**

| Level | Shake duration | Shake scale | Pre-alert time |
|---|---|---|---|
| Easy (1) | 10 s | 3.0 | 6 s |
| Medium (2) | 15 s | 5.0 | 5 s |
| Hard (3) | 20 s | 7.0 | 4 s |

**Procedural drop subsystem:**

- `collectEarthquakeCandidates()` — Scans the building and classifies objects into four categories: stucco tiles (`UnionOperation`, exact size match), televisions (`BasePart`, exact size match), pillars (identified by `Color3`), and ceiling light models (identified by name pattern).
- `applyEarthquakeDrops()` — Uses a Fisher-Yates shuffle to randomly select objects from each category. Calls `unanchorAndKick()` on each, which unanchors the part and applies a randomized upward impulse scaled to part mass.
- `restoreEarthquakeDrops()` — Re-anchors all affected parts and resets their `CFrame` and assembly velocity to the saved original state.

**Objects dropped by difficulty:**

| Category | Easy | Medium | Hard |
|---|---|---|---|
| Stucco tiles | 320 | 420 | 560 |
| TVs | 10 | 18 | 28 |
| Pillars | 12 | 22 | 35 |
| Ceiling lights | 58 | 80 | 105 |

**Aftershock subsystem (`triggerAftershocks`):**
- Fires 2–5 additional camera shake events at regular intervals after the main event.
- Each aftershock has a randomized duration (2–4 s) and scale (1.0–2.5).

**Interacts with:** Simulation Controller, Global Lighting System, Refuge Detection System, Camera Shake System, Dialog System, Scoring System.

---

## 4. Armed Groups Simulation System

**Purpose:** Simulates a Code Red (armed intruder) emergency protocol. Players follow a lockdown and evacuation sequence while antagonist NPCs are present in the building.

**Script:** `src/server/SimulationController.server.lua` — function `startArmedGroupsSimulation()`

**Protocol steps:**
1. Activate the institutional alert (reach Waypoint1 — panic button).
2. Shelter in a designated safe room (reach a Refuge point).
3. Proceed to the authority verification point (reach Waypoint3).
4. Evacuate to the external assembly point (reach Waypoint4).

**Difficulty parameters:**

| Level | NPC count | Pre-alert time |
|---|---|---|
| Easy (1) | 2 NPCs | 7 s |
| Medium (2) | 4 NPCs | 5 s |
| Hard (3) | 6 NPCs | 4 s |

**NPC spawning:**
- Retrieves `BasePart`, `Model`, or `Attachment` children from `AtacantsSpawns/<locationName>/`.
- Shuffles spawn points using Fisher-Yates, then clones the `Atacant NPC` from `ReplicatedStorage` for each NPC and pivots it to the spawn CFrame.
- All spawned NPCs are destroyed when the simulation ends (success or death).

**Death detection:**
- Connects to `Humanoid.Died` on the player's character at simulation start.
- If triggered, calls `endArmedGroupsByDeath()`, which cleans up NPCs, resets state, and teleports the player back to the lobby with a penalty dialog.

**Interacts with:** Simulation Controller, Global Lighting System, Refuge Detection System, Waypoint Detection System, Dialog System, Scoring System.

---

## 5. Explore Mode

**Purpose:** Allows players to freely roam a building location before attempting a timed simulation, familiarizing themselves with exit routes and layout.

**Script:** `src/server/SimulationController.server.lua` — function `startExploreSimulation()`

**Behavior:**
- Teleports the player to the `FireSimulation` spawn (reuses same spawn points).
- Plays background music on the `Intercom/AudioPlayer` (looped).
- Shows the HUD.
- Does not start waypoint detection, scoring, or a timer.

**Interacts with:** Simulation Controller, HUD System, Dialog System.

---

## 6. Scoring and Results System

**Purpose:** Measures player performance at each step of a simulation and presents a final grade.

**Script:** `src/server/SimulationController.server.lua` — functions `calculateScore()`, `showFinalResults()`

**Mechanism:**
- Each simulation records elapsed time per step in `simData.waypointTimes`.
- `maxTimes` array defines the target time for each step (set per simulation type).
- `calculateScore()` maps each step's time-to-max ratio to a point value:

| Time vs. max | Points |
|---|---|
| ≤ 70% of max | 100 (Excellent) |
| ≤ 100% of max | 85 (Good) |
| ≤ 130% of max | 70 (Regular) |
| > 130% of max | 50 (Insufficient) |

- The final score is the average across all steps (0–100).

**Grade thresholds:**

| Score | Grade |
|---|---|
| ≥ 90 | EXCELENTE |
| ≥ 75 | BUENO |
| ≥ 60 | REGULAR |
| < 60 | NECESITA MEJORAR |

**Results delivery:**
- Sends multiple `Result`-type dialog messages (header, grade, per-step breakdown, total time).
- Teleports the player to `Spawnpoints/MainLobby` after a short delay.

**Interacts with:** Dialog System, Simulation Controller.

---

## 7. Waypoint and Refuge Detection System

**Purpose:** Detects when a player physically reaches a required location during a simulation step.

**Script:** `src/server/SimulationController.server.lua` — functions `setupWaypointDetection()`, `setupRefugeDetection()`, `getWaypoint()`, `getRefuges()`

**Waypoint detection:**
- Connects a `Touched` event on the target `BasePart`.
- Validates that the touching part belongs to the player's `Character` and has a `Humanoid`.
- Auto-disconnects after the first valid touch and calls the provided callback.

**Refuge detection:**
- Connects `Touched` on all refuge parts simultaneously.
- A shared `reached` flag prevents double-firing.
- All connections are disconnected once any refuge is touched.

**Highlight integration:**
- `highlightPart()` / `highlightRefuges()` clone a `HighlightTemplate` from `ReplicatedStorage` onto the target part and set its `Transparency` to 0 (or reverse to hide it).

**Workspace folder convention:**
```
Waypoints/<locationName>/<simType>/Waypoint1, Waypoint2, ...
Refugees/<locationName>/<simType>/Refuge1, Refuge2, ...
```

**Interacts with:** All simulation systems, Simulation Controller.

---

## 8. Dialog Notification System

**Purpose:** Displays prioritized, animated in-world notification messages to the player during simulations.

**Script:** `src/client/DialogHandler.client.lua`

**Architecture:** Single `DialogSystem` Lua table with methods (lightweight OOP).

**Features:**
- **Priority queue** (max 6 items). Inserting an `Error`-priority message clears all pending messages instantly.
- **Duplicate suppression:** identical messages within 2 seconds are silently dropped.
- **Typewriter animation:** text is revealed character-by-character at 22 chars/second.
- **Slide animation:** the dialog container slides in from below (Back easing) and out when done.
- **Dynamic display time:** calculated from message length (`#text / CharsPerSecond`), clamped between 2 and 7 seconds.
- **Icon system:** icon image is set from `ICON_MAP` by type key (`Info`, `Warning`, `Success`, `Error`, `Result`).
- **Radio beep:** plays a sound when a message appears.

**Priority levels:**
| Type | Priority |
|---|---|
| Info, Success, Result | 1 (low) |
| Warning | 2 |
| Error | 3 (clears queue) |

**Trigger:** `ShowDialog` RemoteEvent (fired from server).

**UI dependencies:** `HUD_VR > SistemaEmberInfo` with child `LabelTexto`, `Icon`, `RadioBeep`.

**Interacts with:** Simulation Controller (server fires events), HUD System (shares the same ScreenGui).

---

## 9. HUD System

**Purpose:** Displays the simulation heads-up display: active simulation indicator, countdown timer, score, and objectives panel.

**Script:** `src/client/HUDHandler.client.lua`

**Features:**
- Responds to `ControllerUI_HUD` RemoteEvent with `"Show"` or `"Hide"` action strings.
- Animates four UI panels with TweenService (Back easing): each panel has a defined `SHOW_POSITIONS` and `HIDE_POSITIONS` entry.
- Also tweens an `Overlay` image transparency between 0.44 (visible) and 1.0 (hidden).
- Initializes hidden on script load.

**UI panels managed:**
| Panel | Purpose |
|---|---|
| `SimProgreso` | Active simulation indicator |
| `TiempoRestante` | Countdown timer (updated externally) |
| `Puntuacion` | Score display (updated externally) |
| `ProgresoActual` | Objectives checklist (Obj1–Obj4) |

**Interacts with:** Simulation Controller (server sends Show/Hide), Dialog System (same ScreenGui).

---

## 10. Camera Shake System

**Purpose:** Applies procedural camera shake on the client in response to in-game events (earthquakes, explosions, aftershocks).

**Script:** `src/client/CameraShakeHandler.client.lua`

**Features:**
- Triggered by `CameraShakeEvent` RemoteEvent with `(duration, scale)` parameters.
- Automatically detects VR mode via `VRService.VREnabled` and uses the appropriate implementation:

**Non-VR shake:**
- Runs on `RunService.RenderStepped`.
- Composites three sine/cosine waves at different frequencies for an organic feel.
- Applies an offset to `camera.CFrame` (position Y + rotation X).
- Only modifies the camera if `CameraType == Custom`.
- Fade-in: first 15% of duration. Fade-out: last 20% of duration. Easing: cubic in-out.

**VR shake (`shakeVR`):**
- Uses `Humanoid.CameraOffset` instead of direct CFrame modification.
- Amplitude is capped at ×0.5 of the normal intensity to prevent motion sickness.
- Resets `CameraOffset` to `Vector3.zero` when complete.
- Compatible with the NexusVR Character Model framework.

**Cleanup:** Shake connections are disconnected and state is reset on `player.CharacterAdded`.

**Interacts with:** Simulation Controller (server fires events), VR Door Interactor (shares VR detection concern).

---

## 11. Global Lighting System

**Purpose:** Manages all dynamic lighting, neon surfaces, and glass transparency across the entire map based on time of day and the current power mode.

**Script:** `src/server/GlobalLightingController.server.lua`

**Power modes** (stored as `Lighting` attribute `PowerMode`):

| Mode | Effect |
|---|---|
| `NORMAL` | Lights follow day/night cycle |
| `BLACKOUT` | All non-emergency lights off instantly; emergency lights on |
| `FORCE_ON` | All lights on regardless of time |

**Object categories managed:**
- **Lights** (`PointLight`, `SurfaceLight`, `SpotLight`): brightness and color tweened on transition; instant on blackout.
- **Neon parts** (`Material == Neon` or tagged `Emergency`): material swapped between `Neon` and `SmoothPlastic`.
- **Glass parts** (`Material == Glass`): transparency tweened between day (0.6) and night (0.8) values.

**Emergency behavior:**
- Parts tagged with `CollectionService` tag `"Emergency"` or attribute `Emergency = true` are inverted: they turn **on** during `BLACKOUT` and follow normal rules otherwise.

**Performance optimizations:**
- Full scene cache built once at startup (`buildCache`). New descendants are added via `workspace.DescendantAdded`.
- Cache is cleaned of destroyed instances before each apply cycle.
- A `lastAppliedKey` dirty flag (`"MODE|D/N"`) prevents redundant updates.
- Transparency changes smaller than `TRANSPARENCY_EPSILON` (0.01) are skipped.

**Interacts with:** Day/Night Cycle System (reads `Lighting.ClockTime`), Simulation Controller (which sets `PowerMode`).

---

## 12. Day/Night Cycle System

**Purpose:** Drives a real-time day/night cycle by continuously advancing `Lighting.ClockTime`.

**Script:** `src/server/CycleController.server.lua`

**Behavior:**
- Default cycle: 24 game hours complete in 30 real seconds (`DAY_LENGTH_SECONDS`).
- Runs on `RunService.Heartbeat` for smooth per-frame advancement.
- When `PowerMode == "BLACKOUT"`: freezes clock at `ClockTime = 0` (midnight) and sets `Atmosphere.Density = 0.6` for a foggy blackout look.
- When returning to normal: atmosphere density resets to 0.

**Interacts with:** Global Lighting System (which reads `ClockTime` to decide day/night state).

---

## 13. VR Door Interaction System

**Purpose:** Allows VR players to interact with doors by pointing their physical hand controllers and pressing a trigger button.

**Script:** `src/client/VRDoorInteractor.client.lua`

**Mechanism:**
1. Listens for `ButtonR2` (right trigger) or `ButtonL2` (left trigger) via `UserInputService.InputBegan`.
2. Retrieves the current VR hand CFrame from `NexusVRCharacterModel`'s `VRInputService` singleton.
3. Transforms the hand CFrame from head-relative space to world space using the camera's render CFrame.
4. Fires a `Workspace:Raycast()` from the hand position along its look vector, up to 2 studs.
5. Walks up the instance hierarchy of the hit object looking for a `RemoteEvent` named `ToggleDoor`.
6. If found, fires `ToggleDoor:FireServer()` to request the door toggle on the server.

**Dependencies:**
- `NexusVRCharacterModel` module in `ReplicatedStorage` (not in this repository).
- A `ToggleDoor` RemoteEvent child on any interactive door assembly in the workspace.

**Interacts with:** Server-side door scripts (not in this repository), VR character model framework.

---

## 14. Loading Screen System

**Purpose:** Plays a branded intro animation when a player first joins the experience.

**Script:** `src/client/LoadingContainerLoader.client.lua`

**Timeline:**

| Time | Event |
|---|---|
| 0.0 s | Wait for `game:IsLoaded()` + 0.5 s buffer |
| 0.0–2.2 s | Title and subtitle text fade in |
| 2.2–3.2 s | Hold |
| 3.2–4.7 s | Title and subtitle fade out |
| 4.7–8.2 s | Logo group fades in (3.5 s) |
| 8.2–11.2 s | Logo group fades out (3.0 s) |
| 11.2–12.1 s | Black panel fades out (0.895 s) |
| 12.1 s | ScreenGui disabled |

**UI dependencies:** `LoadingContainer` ScreenGui with children `Logos` (Frame with `GroupTransparency`), `BLK` (black overlay Frame with `title` and `subtitle` TextLabels).

**Interacts with:** No other systems. Runs once and exits.

---

## 15. Firefighter NPC Manager

**Purpose:** Keeps firefighter NPCs hidden below the map when no fire simulation is active, and restores them when one begins.

**Script:** `src/server/SimulationController.server.lua` — functions `initializeFirefighters()`, `hideFirefighters()`, `showFirefighters()`

**Mechanism:**
- On first call to `initializeFirefighters()`, scans `FireWaypoints/Firefighters/` for all `HumanoidRootPart` BaseParts and saves their original `CFrame` and `Anchored` state.
- `hideFirefighters()` — anchors each HRP and moves it 100 studs below its original position. Zeroes all velocity.
- `showFirefighters()` — restores each HRP to its original CFrame and anchored state.
- Firefighters are hidden at server startup and shown only during active fire simulations.

**Interacts with:** Fire Simulation System.

---

## 16. Physical Actuator Integration

**Purpose:** Sends commands to external hardware (haptic feedback actuators in the physical VR cabin) via an HTTP API.

**Script:** `src/server/SimulationController.server.lua` — `PhysicalActuatorBindable` handler

**Trigger:** `PhysicalActuatorBindable:Fire(player, actuatorName, value, duration, callback)`

**Behavior:**
- Constructs a JSON payload: `{ actuator, value, duration, player: userId, timestamp }`.
- Posts to `{API_URL}/actuator` with a Bearer token authorization header using `HttpService:PostAsync`.
- Uses `pcall` to catch network errors. On failure, logs a warning and calls `callback(false, "Error de conexion...")`.
- On success, calls `callback(true, result)`.

**Current usage in simulations:**
- Fire Simulation: activates a heater actuator (`<locationName>_Heater`) after a configurable delay, for the duration of the fire.

**Interacts with:** Fire Simulation System (the only current caller). Designed to be called from any simulation via the BindableEvent interface.