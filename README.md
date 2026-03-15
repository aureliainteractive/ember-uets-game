# EMBER — Emergency Behavior & Response Simulator

> An educational virtual reality simulator for emergency preparedness in academic environments.

---

## Research-Only Notice

This repository is provided for **research and documentation purposes only**.

- It is **not expected to be fully recreatable** as a standalone project from source alone.
- Core place-file assets, scene data, and project-specific Roblox instances are not tracked here.
- The code is preserved to support academic review, system analysis, and reference implementation study.

---

## Overview

EMBER is an immersive emergency preparedness simulator built on the Roblox platform. It was developed as a thesis project with the goal of improving emergency response knowledge and behavior in educational settings through guided, interactive simulations.

The simulator places participants inside a virtual representation of a real building (a school or university campus) and walks them through standardized emergency protocols in a safe, repeatable, and measurable environment.

The project also accompanies a low-cost physical VR cabin prototype with haptic feedback, designed to heighten immersion without requiring expensive commercial VR hardware.

---

## Educational Motivation

Traditional emergency drills are infrequent, disruptive to normal school activities, and difficult to evaluate objectively. EMBER addresses these limitations by providing:

- **On-demand simulations** that can be run at any time without disrupting the physical environment.
- **Objective performance scoring** based on how quickly and correctly each protocol step is completed.
- **Repeatable scenarios** with configurable difficulty levels so participants can practice and improve.
- **Safe exposure** to stressful scenarios (fire, earthquake, armed threat) that cannot be safely replicated in a real drill.

---

## Key Features

- **Fire Simulation** — Procedural fire propagation with smoke effects; participants locate the fire origin, activate the alarm, evacuate the building, and reach the external assembly point.
- **Earthquake Simulation** — Physics-driven object drops (tiles, TVs, pillars, ceiling lights); participants shelter in place, then evacuate; aftershock sequences are triggered dynamically.
- **Armed Groups Simulation (Code Red)** — Participants follow a lockdown protocol: activate a panic alert, shelter in a safe room, verify identity with authorities, and evacuate.
- **Explore Mode** — A free-roam mode for familiarizing participants with the building layout before starting a timed simulation.
- **Difficulty Levels** — Easy, Medium, and Hard, each adjusting durations, intensities, and object counts.
- **Performance Scoring** — Step-by-step time tracking with a final grade (Excellent / Good / Regular / Needs Improvement).
- **VR Support** — Camera shake is adapted for VR headsets to avoid motion sickness; door interaction uses VR hand raycasting.
- **Dynamic Lighting** — A real-time day/night cycle and a power mode system (Normal / Blackout / Force On) that controls all lights, neon surfaces, and glass transparency.
- **Procedural HUD** — Animated heads-up display with simulation progress, countdown timer, score, and objectives.
- **Dialog System** — A priority-queued, typewriter-style notification system for in-simulation instructions.

---

## Technologies Used

| Technology | Role |
|---|---|
| **Roblox Studio** | Game engine and place editor |
| **Luau** | Scripting language (Lua 5.1 superset used by Roblox) |
| **Rojo 7.7.0-rc.1** | File-system sync tool between VS Code and Roblox Studio |
| **Aftman** | Cross-platform toolchain manager for Rojo |
| **NexusVR Character Model** | VR character controller and hand input (referenced from ReplicatedStorage) |

---

## Repository Structure

```
ember-uets/
├── aftman.toml                  # Aftman toolchain config (Rojo version)
├── default.project.json         # Rojo project mapping
├── src/
│   ├── client/                  # LocalScripts (run on each player's client)
│   │   ├── CameraShakeHandler.client.lua
│   │   ├── DialogHandler.client.lua
│   │   ├── HUDHandler.client.lua
│   │   ├── LoadingContainerLoader.client.lua
│   │   └── VRDoorInteractor.client.lua
│   ├── server/                  # Scripts (run on the Roblox server only)
│   │   ├── CycleController.server.lua
│   │   ├── GlobalLightingController.server.lua
│   │   └── SimulationController.server.lua
│   └── shared/                  # ModuleScripts (accessible by both sides)
│       └── (no files currently tracked in this repo)
└── README.md
```

### Rojo Mapping

The `default.project.json` file tells Rojo where each folder maps inside the Roblox DataModel:

| File-system path | Roblox location |
|---|---|
| `src/client/` | `StarterPlayer > StarterPlayerScripts > Client` |
| `src/server/` | `ServerScriptService > Server` |
| `src/shared/` | `ReplicatedStorage > Shared` |

---

## Development Setup (Reference Only)

The following setup reflects the original development workflow, but complete reproduction is not guaranteed from this repository alone.

### Prerequisites

- [Roblox Studio](https://create.roblox.com/landing) installed
- [Aftman](https://github.com/LPGhatguy/aftman) installed
- A code editor (VS Code recommended)

### Steps

1. **Install tools via Aftman**

   ```bash
   aftman install
   ```

   This reads `aftman.toml` and installs Rojo 7.7.0-rc.1.

2. **Build the place file**

   ```bash
   rojo build -o "ember-uets.rbxlx"
   ```

3. **Open in Roblox Studio**

   Open the generated `ember-uets.rbxlx` file in Roblox Studio.

4. **Start the Rojo sync server**

   ```bash
   rojo serve
   ```

5. **Connect from Roblox Studio**

   In Roblox Studio, install the [Rojo plugin](https://create.roblox.com/marketplace) and click **Connect** to sync live file changes from your editor into Studio.

---

## Notes on Assets

This repository contains **only scripts**. The following assets are embedded inside the Roblox place file (`ember-uets.rbxlx`) and are **not tracked in this repository**:

- 3D building models and maps
- UI layouts and ScreenGui instances (`HUD_VR`, `LoadingContainer`)
- Sound assets (fire alarm, earthquake alarm, explore music, radio beep)
- NPC models (`Atacant NPC`, firefighter NPCs)
- ReplicatedStorage instances (`CameraShakeEvent`, `ShowDialog`, `ControllerUI_HUD`, `SimulationStartBindable`, `HighlightTemplate`, etc.)
- Workspace folder structure (`Waypoints`, `Refugees`, `Spawnpoints`, `AtacantsSpawns`, `FireWaypoints`)

Any developer cloning this repository will need access to the full Roblox place file to run the project.

---

## Academic Context

EMBER was developed as a thesis project exploring the use of low-cost virtual reality to improve emergency preparedness in educational institutions. The physical component of the project includes a custom-built VR cabin prototype with haptic feedback actuators that are controlled via an external HTTP API called from the Roblox server during simulations.

The simulation scoring system is designed to provide measurable, objective data on participant performance, supporting the academic hypothesis that VR-based drills can be as effective as — or more effective than — traditional physical drills.

---

## License

This project is a thesis prototype. Licensing terms are defined by the academic institution under which it was developed.