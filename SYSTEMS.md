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
17. [Door System](#17-door-system)
18. [Kiosk System](#18-kiosk-system)
19. [Confirmation UI System](#19-confirmation-ui-system)
20. [Results Screen System](#20-results-screen-system)
21. [HUD Ticker (HUDService)](#21-hud-ticker-hudservice)
22. [Kiosk Configuration (KioskConfig)](#22-kiosk-configuration-kioskconfig)

---

## 1. Simulation Controller

**Purpose:** Central coordinator and entry point for all simulation types. Dispatches to per-simulation modules and manages shared server state.

**Script:** `src/server/SimulationController.server.lua`

**Responsibilities:**
- Requires simulation modules (`FireSimulation`, `EarthquakeSimulation`, `ArmedGroupsSimulation`) and service modules at startup.
- Listens to `SimulationStartBindable` (BindableEvent) and dispatches to the correct simulation module based on `eventType`.
- Prevents duplicate concurrent simulations for the same type and location using `activeSimulations`.
- Stores per-player simulation state in `playerSimulationData` (step times, connections, seed references, completion flags).
- Builds and passes `services` and `state` context tables into each simulation module call.
- Handles `HighlightPartBindable`, `FinishedTaskBindable`, and `PhysicalActuatorBindable` BindableEvents.
- Cleans up all state when a player disconnects mid-simulation.
- Each simulation module independently enforces a global 5-minute safety timeout.

**Input event:**
```
SimulationStartBindable:Fire(player, eventType, locationName, difficultyStr)
```

**Interacts with:**
- Dialog Notification System (via `DialogService`)
- HUD System (via `ControllerUI_HUD` RemoteEvent and `HUDService` ticker)
- Camera Shake System (via `CameraShakeEvent` RemoteEvent)
- Global Lighting System (via `Lighting:SetAttribute("PowerMode", ...)`)
- Scoring and Results System (`ResultsSystem.show()`)
- Waypoint and Refuge Detection System (`NavigationUtils`)
- Firefighter NPC Manager (`FireSimulation.hideFirefighters`, `FireSimulation.showFirefighters`)
- Physical Actuator Integration (`ActuatorService`)
- Physical Actuator Integration (via `PhysicalActuatorBindable`)

---

## 2. Fire Simulation System

**Purpose:** Simulates a fire emergency scenario inside a building. Guides the player through a 4-step evacuation protocol while procedural fire spreads through the building.

**Script:** `src/server/modules/FireSimulation.lua` — function `FireSimulation.start()`

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

**Script:** `src/server/modules/EarthquakeSimulation.lua` — function `EarthquakeSimulation.start()`

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

**Script:** `src/server/modules/ArmedGroupsSimulation.lua` — function `ArmedGroupsSimulation.start()`

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

**Script:** `src/server/SimulationController.server.lua` — function `startExploreSimulation()` (inline, not in a separate module)

**Behavior:**
- Teleports the player to the `FireSimulation` spawn (reuses same spawn points).
- Plays background music on the `Intercom/AudioPlayer` (looped).
- Shows the HUD.
- Does not start waypoint detection, scoring, or a timer.

**Interacts with:** Simulation Controller, HUD System, Dialog System.

---

## 6. Scoring and Results System

**Purpose:** Measures player performance at each step of a simulation, computes a rank, and presents detailed results on a dedicated screen.

**Scripts:**
- `src/server/modules/ScoringSystem.lua` — legacy score helpers (used by `HUDService` for the live score display).
- `src/server/modules/ResultsSystem.lua` — authoritative results computation and delivery (fires `ShowResults` RemoteEvent).
- `src/client/ResultsScreenHandler.client.lua` — receives and displays the results payload on the client.

**ScoringSystem (live score, used by HUDService):**
- `calculateScore(times, maxTimes)` — returns an average 0–100 score, mapping each step's time-to-max ratio:

| Time vs. max | Points |
|---|---|
| ≤ 70% of max | 100 |
| ≤ 100% of max | 85 |
| ≤ 130% of max | 70 |
| > 130% of max | 50 |

- `getGrade(score)` — maps score to legacy grade string (EXCELENTE / BUENO / REGULAR / NECESITA MEJORAR).

**ResultsSystem (end-of-simulation):**
- Each step earns points from a finer-grained scale:

| Time vs. max | Points |
|---|---|
| ≤ 50% of max | 1000 (Perfect) |
| ≤ 70% of max | 800 (Excellent) |
| ≤ 100% of max | 600 (Completed) |
| ≤ 130% of max | 400 (Late) |
| > 130% of max | 200 (Very Late) |

- The rank is assigned based on total points earned as a ratio of the maximum possible (`stepCount × 1000`):

| Ratio | Rank |
|---|---|
| ≥ 90% | S |
| ≥ 80% | A+ |
| ≥ 70% | A |
| ≥ 60% | B+ |
| ≥ 50% | B |
| ≥ 40% | C+ |
| ≥ 30% | C |
| < 30% | D |

- Additional metrics computed: `precision` (total budget / total used × 100%), `criticalErrors` (steps where time > 1.5× max), `totalTime` (MM:SS), `objectivesDone` / `objectivesTotal`.

**Results delivery:**
- `ResultsSystem.show()` fires `ShowResults:FireClient(player, payload)` after a 2-second delay.
- `ResultsScreenHandler` receives the payload, populates the results screen, and animates it in.
- The player clicks the return button, which fires `ReturnToLobby:FireServer()`.
- `ResultsSystem` handles `ReturnToLobby` and teleports the player to `Spawnpoints/MainLobby`.

**Interacts with:** HUD Ticker (ScoringSystem), Dialog System (ScoringSystem legacy path), Results Screen System, Simulation Controller.

---

## 7. Waypoint and Refuge Detection System

**Purpose:** Detects when a player physically reaches a required location during a simulation step.

**Script:** `src/server/modules/NavigationUtils.lua` — functions `setupWaypointDetection()`, `setupRefugeDetection()`, `getWaypoint()`, `getRefuges()`

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
- Responds to `HUDUpdate` RemoteEvent: receives `(timeLeft, score, completedSteps, stepNames)` pushed once per second by the server-side `HUDService` ticker and updates the live display.
- Animates four UI panels with TweenService (Back easing): each panel has a defined `SHOW_POSITIONS` and `HIDE_POSITIONS` entry.
- Also tweens an `Overlay` image transparency between 0.44 (visible) and 1.0 (hidden).
- Initializes hidden on script load.

**UI panels managed:**
| Panel | Purpose |
|---|---|
| `SimProgreso` | Active simulation indicator |
| `TiempoRestante` | Countdown timer (live-updated via `HUDUpdate`) |
| `Puntuacion` | Score display (live-updated via `HUDUpdate`) |
| `ProgresoActual` | Objectives checklist (Obj1–Obj4, live-updated via `HUDUpdate`) |

**Interacts with:** Simulation Controller (Show/Hide), HUD Ticker — `HUDService` (live data), Dialog System (same ScreenGui).

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

**Script:** `src/server/modules/FireSimulation.lua` — functions `FireSimulation.initializeFirefighters()`, `FireSimulation.hideFirefighters()`, `FireSimulation.showFirefighters()`

**Mechanism:**
- On first call to `initializeFirefighters()`, scans `FireWaypoints/Firefighters/` for all `HumanoidRootPart` BaseParts and saves their original `CFrame` and `Anchored` state.
- `hideFirefighters()` — anchors each HRP and moves it 100 studs below its original position. Zeroes all velocity.
- `showFirefighters()` — restores each HRP to its original CFrame and anchored state.
- Firefighters are hidden at server startup (called from `SimulationController`) and shown only during active fire simulations.

**Interacts with:** Fire Simulation System.

---

## 16. Physical Actuator Integration

**Purpose:** Sends commands to external hardware (haptic feedback actuators in the physical VR cabin) via an HTTP API.

**Scripts:**
- `src/server/modules/ActuatorService.lua` — sends the HTTP request.
- `src/server/modules/ActuatorConfig.lua` — stores `API_URL` and `API_KEY`.
- `src/server/SimulationController.server.lua` — `PhysicalActuatorBindable` handler (routes external calls to `ActuatorService.fire()`).

**Trigger:** `PhysicalActuatorBindable:Fire(player, actuatorName, value, duration, callback)`

**Behavior:**
- Constructs a JSON payload: `{ actuator, value, duration, player: userId, timestamp }`.
- Posts to `{API_URL}/actuator` with a Bearer token authorization header using `HttpService:PostAsync`.
- Uses `pcall` to catch network errors. On failure, logs a warning and calls `callback(false, "Error de conexion...")`.
- On success, calls `callback(true, result)`.

**Current usage in simulations:**
- Fire Simulation: activates a heater actuator (`<locationName>_Heater`) after a configurable delay, for the duration of the fire.

**Security note:** `ActuatorConfig.lua` contains placeholder values. Do not commit real credentials. Consider fetching from DataStore or a secure BindableFunction resolver for production use.

**Interacts with:** Fire Simulation System (the only current caller). Designed to be called from any simulation via the BindableEvent interface.

---

## 17. Door System

**Purpose:** Centralized management of all interactive doors.

**Key scripts:**
- `src/server/DoorSystem.server.lua`
- `src/server/modules/doors/HingeDoor.lua`
- `src/server/modules/doors/SlidingDoor.lua`

**Configuration:**
- Stored as Attributes on each door `Model`.
- Hinge attributes: `DoorType`, `OpenAngle`, `OpenTime`, `Cooldown`.
- Sliding attributes: `DoorType`, `SlideDistance`, `SlideTime`, `SlideDirection`, `Cooldown`.

**Client interaction:**
- `VRDoorInteractor.client.lua` fires `ToggleDoor:FireServer()`.
- Server receives this through each door model's `ToggleDoor` `RemoteEvent`.

**Door types:**
- **Hinge** — CFrame rotation around the `Hinge` part.
- **Sliding** — Positional offset driven by `SlidePivot`.

**How it interacts with other systems:**
- Independent from simulation modules and scoring flow.
- Uses the same existing `ToggleDoor` contract and does not modify client-side VR interaction logic.

---

## 18. Kiosk System

**Purpose:** Physical in-world kiosk that guides a player through simulation mode, location, and difficulty selection before launching a simulation.

**Script:** `src/server/KioskController.server.lua`

**Mechanism:**
1. A player steps onto the `Hitbox` part near the kiosk. A "Start" button appears on the kiosk `SurfaceGui`.
2. The player clicks Start — `startConfig()` coroutine begins:
   - `ModeSelector` frame shown → player selects a simulation type button.
   - `LocationSelector` frame shown → player selects a location button.
   - `DiffSelector` frame shown → player selects a difficulty button.
   - `confInfoFrame` is populated with display names from `KioskConfig` and shown on the kiosk surface.
   - `KioskShowConfirmation:FireClient(player, { mode, location, diff })` is sent to the player.
   - Controller waits for `KioskConfirm` or `KioskCancel` from the client.
3. On confirm: fires `SimulationStartBindable:Fire(player, mode, location, diff)`.
4. On cancel: resets UI, lets the player retry.
5. On player leaving the hitbox or disconnecting: `resetKiosk()` clears all state and hides the `ConfirmationUI` on the player's screen.

**State variables:** `currentPlayer`, `configInProgress`, `mode`, `diff`, `loc` — all reset to nil on every reset.

**RemoteEvents created at startup (if not already present):** `KioskShowConfirmation`, `KioskConfirm`, `KioskCancel`.

**Place file dependencies:**
- `workspace.Menu` → Model containing `MenuScreen` (Part with `SurfaceGui`) and `Hitbox` (BasePart).
- `SurfaceGui` children: `StartConfig`, `ModeSelector`, `LocationSelector`, `DiffSelector`, `BLK` (with `WaitingLabel` and `infoLabel`), `ConfirmationLabels`, `ConfirmationInfo` (with `modeLabel`, `diffLabel`, `locationLabel`).

**Interacts with:** Confirmation UI System (fires `KioskShowConfirmation`), Simulation Controller (fires `SimulationStartBindable`), KioskConfig (display names).

---

## 19. Confirmation UI System

**Purpose:** Shows a ScreenGui overlay on the player's screen summarising their kiosk selection (mode, location, difficulty, step objectives) and collecting their final confirm action.

**Script:** `src/client/ConfirmationUIHandler.client.lua`

**Mechanism:**
- Listens to `KioskShowConfirmation` RemoteEvent. A non-nil payload triggers `showUI()`; nil triggers `hideUI()`.
- `populate(mode)` reads `KioskConfig.getSteps(mode).stepNamesDetailed` and fills `Objective1`–`Objective4` labels.
- Three UI elements (`Panel`, `Controles`, `btnConfirm`) animate in with a staggered Quint slide-up effect (0.05 s between each).
- On hide, elements animate out in reverse order with a faster Quint slide-down effect.
- A `transitionToken` integer prevents stale tween callbacks from interfering with rapid show/hide transitions.
- On confirm button press: `hideUI()` + `KioskConfirm:FireServer()`.

**UI dependencies:** `ConfirmationUI` ScreenGui (in StarterGui) with `Panel > Objectives > Objective1..4`, `Controles`, `Confirmar`.

**RemoteEvent dependencies:** `KioskShowConfirmation` (S→C), `KioskConfirm` (C→S).

**Shared module dependency:** `ReplicatedStorage.Shared.KioskConfig`.

**Interacts with:** Kiosk System (server fires events), KioskConfig.

---

## 20. Results Screen System

**Purpose:** Displays a detailed breakdown of simulation performance (rank, points, per-step times, precision, critical errors) after a simulation ends.

**Scripts:**
- `src/server/modules/ResultsSystem.lua` — computes and fires the payload.
- `src/client/ResultsScreenHandler.client.lua` — receives and displays the payload.

**Server side (`ResultsSystem`):**
- `compute(session, simType, locationName, difficulty)` — builds a results payload table from session data:
  - Per-step points using `stepPoints()` (1000/800/600/400/200 scale).
  - Rank from total points ratio (S/A+/A/B+/B/C+/C/D).
  - `precision` % = `totalBudget / totalUsed × 100`, clamped 0–100.
  - `criticalErrors` = count of steps where time > 1.5× maxTime.
  - `totalTime` formatted as `MM:SS`.
- `show(player, session, simType, locationName, difficulty, mainLobbySpawn)` — calls `compute()` and fires `ShowResults:FireClient(player, payload)` after a 2-second delay.
- Handles `ReturnToLobby:OnServerEvent` → teleports the player to `MainLobby`.

**Client side (`ResultsScreenHandler`):**
- Receives `ShowResults`. Validates payload is a table.
- Populates: `LabelHeader`, `LabelRank` (with colour from rank), `RankContainer` image (green/yellow/red band), `LabelPoints`, `LabelTime`, `LabelPrecision`, `LabelErrors`, `LabelObjectives`.
- Populates per-step rows (`Step1..4`) with name, time, and points.
- Animates `Container` in from below with Quint tween; step rows fade in with a stagger (0.04 s each).
- `BtnReturn` fires `ReturnToLobby:FireServer()` and hides the screen.

**Rank band images:**
| Band | Asset ID |
|---|---|
| GREEN | `rbxassetid://140721936487947` |
| YELLOW | `rbxassetid://119407907574369` |
| RED | `rbxassetid://88357135721128` |

**UI dependencies:** `ResultsScreen` ScreenGui with `Container > LabelHeader`, `LabelRank`, `LabelPoints`, `LabelTime`, `LabelPrecision`, `LabelErrors`, `LabelObjectives`, `RankContainer`, `Steps/Step1..4 > LabelName/LabelTime/LabelPoints`, `BtnReturn`.

**Interacts with:** ResultsSystem (server sends event), Simulation Controller (indirectly, via session data), KioskConfig (difficulty display name).

---

## 21. HUD Ticker (HUDService)

**Purpose:** Pushes live simulation data (countdown timer, current score, objectives progress) to the player's HUD once per second during an active simulation.

**Script:** `src/server/modules/HUDService.lua`

**Mechanism:**
- `startTicker(player, session, services)` — validates preconditions (player, session fields, services fields) and spawns a `task.spawn` loop.
- Every second, computes:
  - `timeLeft` — `SIMULATION_GLOBAL_TIMEOUT − elapsed`, floored to integer.
  - `score` — calls `ScoringSystem.calculateScore(session.waypointTimes, session.maxTimes)`; returns 100 if no steps recorded yet.
  - `completedSteps` — `#session.waypointTimes`.
- Fires `services.hudUpdateEvent:FireClient(player, timeLeft, score, completedSteps, session.stepNames)`.
- Loop exits when `timeLeft ≤ 0` or the player leaves.
- `stopTicker(player)` — sets the ticker flag to nil, causing the loop to exit on its next iteration.

**Session fields required:** `startTime`, `waypointTimes`, `maxTimes`, `stepNames`.

**Services fields required:** `SIMULATION_GLOBAL_TIMEOUT`, `hudUpdateEvent`.

**Interacts with:** HUD System (client receives `HUDUpdate`), ScoringSystem (calls `calculateScore`), Simulation Controller (holds the `services` table).

---

## 22. Kiosk Configuration (KioskConfig)

**Purpose:** Single authoritative source of truth for all kiosk-driven simulation configuration, shared between server scripts and the client ConfirmationUI.

**Script:** `src/shared/KioskConfig.lua` (available at `ReplicatedStorage.Shared.KioskConfig`)

**Contents:**

- **`MODES`** — array of mode entries:
  ```
  { name = "FireSimulation", display = "Simulacro de Incendio", description = "..." }
  ```
- **`DIFFICULTIES`** — array of difficulty entries:
  ```
  { name = "Easy", display = "Fácil", level = 1, description = "..." }
  ```
- **`SIMULATION_STEPS`** — keyed by simulation type name:
  ```
  FireSimulation = {
    stepNames         = { "Deteccion", "Alarma", "Evacuacion", "Punto de encuentro" },
    stepNamesDetailed = { "Localizar e identificar ...", ... },
    maxTimes          = { 15, 10, 20, 15 },
    description       = "4 pasos: ..."
  }
  ```

**Step max times:**
| Simulation | Step 1 | Step 2 | Step 3 | Step 4 |
|---|---|---|---|---|
| FireSimulation | 15 s | 10 s | 20 s | 15 s |
| EarthquakeSimulation | 12 s | 18 s | 15 s | — |
| ArmedGroupsSimulation | 10 s | 20 s | 15 s | 18 s |

**Lookup helpers:**
| Function | Returns |
|---|---|
| `getModeData(name)` | Full mode entry for a name key |
| `getDifficultyData(name)` | Full difficulty entry for a name key |
| `getDifficultyByLevel(level)` | Full difficulty entry for a numeric level |
| `getSteps(simType)` | Steps table (safe: returns empty table if unknown) |
| `getModeDisplay(name)` | Human-readable mode name (falls back to raw key) |
| `getDifficultyDisplay(name)` | Human-readable difficulty name (falls back to raw key) |

**Used by:** `KioskController` (display names), `ConfirmationUIHandler` (detailed step labels), `FireSimulation`, `EarthquakeSimulation`, `ArmedGroupsSimulation` (step names and max times).