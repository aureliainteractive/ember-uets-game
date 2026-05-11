-- GameConstants
-- Purpose: Centralized configuration for all game parameters, balance settings, and UI timings.
-- Location: ReplicatedStorage.Shared.GameConstants
--
-- This module consolidates all hardcoded values (magic numbers) scattered throughout
-- the codebase into a single, maintainable source of truth.
--
-- Usage:
--   local Constants = require(ReplicatedStorage.Shared.GameConstants)
--   local fireParams = Constants.SIMULATIONS.FIRE
--   local speed = Constants.ANIMATION.HUD_ANIMATION_DURATION

local GameConstants = {}

-- =============================================================================
-- SIMULATION: Difficulty Parameters
-- =============================================================================
GameConstants.SIMULATIONS = {
	FIRE = {
		EASY = {
			duration = 55,          -- How long before fire sim times out (seconds)
			heaterDelay = 35,       -- Delay before heater activates
			spreadRadius = 18,      -- Distance fire spreads (studs)
			partsPerWave = 6,       -- Parts to ignite per wave
			waveInterval = 4.0,     -- Time between waves (seconds)
			maxBurning = 100,       -- Max simultaneous burning parts
			fireSize = 2.85,        -- Fire effect size multiplier
			heat = 20,              -- Fire heat value
			smokeSizeMult = 1.0,    -- Smoke size multiplier
			smokeRise = 8,          -- Smoke rise velocity
		},
		MEDIUM = {
			duration = 70,
			heaterDelay = 25,
			spreadRadius = 26,
			partsPerWave = 10,
			waveInterval = 3.0,
			maxBurning = 150,
			fireSize = 3.05,
			heat = 30,
			smokeSizeMult = 1.2,
			smokeRise = 6,
		},
		HARD = {
			duration = 90,
			heaterDelay = 18,
			spreadRadius = 35,
			partsPerWave = 14,
			waveInterval = 2.0,
			maxBurning = 200,
			fireSize = 5.25,
			heat = 40,
			smokeSizeMult = 1.4,
			smokeRise = 4,
		},
	},
	
	EARTHQUAKE = {
		EASY = {
			duration = 10,          -- Shake duration (seconds)
			scale = 3.0,            -- Camera shake intensity
			preAlertTime = 6,       -- Time before shake starts (seconds)
			stuccoTiles = 320,      -- Objects to drop
			tvs = 10,
			pillars = 12,
			ceilingLights = 58,
		},
		MEDIUM = {
			duration = 15,
			scale = 5.0,
			preAlertTime = 5,
			stuccoTiles = 420,
			tvs = 18,
			pillars = 22,
			ceilingLights = 80,
		},
		HARD = {
			duration = 20,
			scale = 7.0,
			preAlertTime = 4,
			stuccoTiles = 560,
			tvs = 28,
			pillars = 35,
			ceilingLights = 105,
		},
	},
	
	ARMED_GROUPS = {
		EASY = {
			duration = 180,         -- Total simulation time
			preparationTime = 7,    -- Time before NPCs spawn
			npcCount = 2,           -- Number of threat NPCs
		},
		MEDIUM = {
			duration = 240,
			preparationTime = 5,
			npcCount = 4,
		},
		HARD = {
			duration = 300,
			preparationTime = 4,
			npcCount = 6,
		},
	},
}

-- =============================================================================
-- ANIMATION: Timing for UI Transitions and Effects
-- =============================================================================
GameConstants.ANIMATION = {
	-- HUD animations (HUDHandler.client.lua)
	HUD_ANIMATION_DURATION = 0.42,          -- Tween duration for HUD elements
	HUD_STAGGER_STEP = 0.045,               -- Delay between staggered elements
	HUD_EASING_STYLE = Enum.EasingStyle.Quint,
	HUD_EASING_DIRECTION_IN = Enum.EasingDirection.Out,
	HUD_EASING_DIRECTION_OUT = Enum.EasingDirection.In,
	
	-- Dialog animations (DialogHandler.client.lua)
	DIALOG_TYPE_SPEED = 0.02,               -- Delay per character during typewriter
	DIALOG_DISPLAY_BASE_TIME = 2.0,         -- Base display time (multiplied by text length)
	DIALOG_PAUSE_BETWEEN = 0.5,             -- Pause between consecutive dialogs
	DIALOG_FADE_IN_TIME = 0.35,             -- Fade in transition
	DIALOG_FADE_OUT_TIME = 0.35,            -- Fade out transition
	DIALOG_BOUNCE_SCALE = 0.8,              -- Icon scale on entry (0.8 → 1.1 → 1.0)
	DIALOG_BOUNCE_TIME = 0.4,               -- Icon bounce animation duration
	
	-- Camera shake (CameraShakeHandler.client.lua)
	CAMERA_SHAKE_EASE_IN = Enum.EasingStyle.Quad,
	CAMERA_SHAKE_EASE_OUT = Enum.EasingStyle.Quad,
	
	-- Results screen (ResultsScreenHandler.client.lua)
	RESULTS_COUNTER_DURATION = 1.5,         -- Time to count from 0 to final
	RESULTS_BADGE_ENTRY_TIME = 0.4,         -- Badge animation time
	RESULTS_BADGE_SCALE_RANGE = { 0.5, 1.2, 1.0 }, -- Entry scale sequence
	RESULTS_PROGRESS_BAR_TIME = 0.5,        -- Per-step bar animation
	
	-- Global lighting (GlobalLightingController.server.lua)
	LIGHT_TWEEN_TIME = 0.35,
	GLASS_TWEEN_TIME = 0.35,
}

-- =============================================================================
-- NETWORK: Communication Settings
-- =============================================================================
GameConstants.NETWORK = {
	HUD_UPDATE_INTERVAL = 1,                -- Seconds between HUD updates
	HUD_UPDATE_MAX_INTERVAL = 2,            -- Max interval for batched updates
	SIMULATION_GLOBAL_TIMEOUT = 300,        -- Global timeout for any simulation (5 minutes)
	LOADING_READY_TIMEOUT = 15,             -- Time to wait for loading phase
	MAX_RETRIES = 3,                        -- Retry attempts for network calls
	
	-- RemoteEvent names
	REMOTE_EVENTS = {
		SHOW_DIALOG = "ShowDialog",
		CAMERA_SHAKE = "CameraShakeEvent",
		CONTROLLER_UI_HUD = "ControllerUI_HUD",
		HUD_UPDATE = "HUDUpdate",
		KIOSK_CONFIRMATION = "KioskShowConfirmation",
		SHOW_RESULTS = "ShowResults",
		TOGGLE_DOOR = "ToggleDoor",
		KIOSK_CONFIRM = "KioskConfirm",
		KIOSK_CANCEL = "KioskCancel",
		RETURN_TO_LOBBY = "ReturnToLobby",
		SIMULATION_LOADING_READY = "SimulationLoadingReady",
	},
	
	-- BindableEvent names
	BINDABLE_EVENTS = {
		SIMULATION_START = "SimulationStartBindable",
		HIGHLIGHT_PART = "HighlightPartBindable",
		FINISHED_TASK = "FinishedTaskBindable",
		PHYSICAL_ACTUATOR = "PhysicalActuatorBindable",
		POWER_CONTROL = "PowerControl",
		RESET_ALL_DOORS = "ResetAllDoorsFunction",
	},
}

-- =============================================================================
-- LIGHTING: Day/Night Cycle and Lighting Settings
-- =============================================================================
GameConstants.LIGHTING = {
	NIGHT_START = 18.0,                     -- Clock time when night begins (0-24)
	NIGHT_END = 6.0,                        -- Clock time when night ends (0-24)
	
	DAY_LIGHT_BRIGHTNESS = 0.25,
	DAY_LIGHT_COLOR = Color3.fromRGB(255, 255, 255),
	
	NIGHT_LIGHT_BRIGHTNESS = 0.5,
	NIGHT_LIGHT_COLOR = Color3.fromRGB(200, 200, 200),
	
	DAY_GLASS_TRANSPARENCY = 0.6,
	NIGHT_GLASS_TRANSPARENCY = 0.8,
	
	OFF_MATERIAL = Enum.Material.SmoothPlastic,
	ON_MATERIAL = Enum.Material.Neon,
	
	TRANSPARENCY_EPSILON = 0.01,
	
	-- Power modes: NORMAL (day/night cycle), BLACKOUT (all off except emergency), FORCE_ON (all on)
	VALID_MODES = {
		NORMAL = true,
		BLACKOUT = true,
		FORCE_ON = true,
	},
}

-- =============================================================================
-- AUDIO: Sound IDs and Volume Settings
-- =============================================================================
GameConstants.AUDIO = {
	FIRE_ALARM_SOUND_ID = "18682406265",
	EARTHQUAKE_ALARM_SOUND_ID = "138221067",
	INTERCOM_AMBIENT_SOUND_ID = "106924095504453",
	
	-- Optional dialog sound effects
	DIALOG_CHAR_SOUND_ENABLED = false,     -- Whether to play sound on each character
	DIALOG_ALERT_SOUND_ID = nil,           -- Alert sound for warnings
	DIALOG_SUCCESS_SOUND_ID = nil,         -- Success sound for completions
	
	INTERCOM_VOLUME = 0.6,
}

-- =============================================================================
-- NPC: Navigation and AI Settings
-- =============================================================================
GameConstants.NPC = {
	BATCH_SIZE = 25,                        -- NPCs spawned per batch
	BATCH_INTERVAL = 0.05,                  -- Time between batches
	
	-- Pathfinding
	ARRIVE_RADIUS = 2.5,                    -- Distance considered "arrived" at waypoint
	MOVETO_TIMEOUT = 12,                    -- Timeout per MoveTo call
	TICK_RATE = 0.1,                        -- Movement check frequency
	
	-- Door interaction
	DOOR_DETECTION_RADIUS = 16,
	DOOR_TRIGGER_DISTANCE = 12,
	DOOR_DEBOUNCE_TIME = 1.5,
	
	-- Anti-clumping
	AUTO_OFFSET_RADIUS = 2.25,
	STUCK_TIME_BEFORE_NUDGE = 1.0,
	STUCK_MOVEMENT_EPSILON = 0.05,
	STUCK_NUDGE_RADIUS = 2.0,
	
	-- Pathfinding constraints
	NEIGHBOR_RADIUS = 12,                   -- Same-floor connection radius
	STAIR_RADIUS = 22,                      -- Cross-floor connection radius
	
	-- VR Door interaction
	VR_DOOR_MAX_DISTANCE = 2,               -- Max raycast distance for VR door interaction
}

-- =============================================================================
-- FIRE_SIMULATION: Fire Spread Parameters
-- =============================================================================
GameConstants.FIRE_SIMULATION = {
	MIN_VOLUME_FIRE = 0.05,                 -- Minimum part volume to be flamable
	SCAN_YIELD_EVERY = 2000,                -- Yield count during building scan
	SMOKE_COLOR = Color3.fromRGB(117, 117, 117),
	
	-- Particle effect configuration
	PARTICLE_PRESETS_ROOT = { "Particles", "Fire" },
	PARTICLE_PRESET_SMALL_NAME = "FireSmall",
	PARTICLE_PRESET_LARGE_NAME = "FireLarge",
	PARTICLE_EFFECT_TYPE_ATTRIBUTE = "EffectType",
	
	-- Particle rates (base)
	FIRE_BASE_RATE = 10,
	SMOKE_TO_FIRE_RATE_RATIO = 4,
	
	-- Rate scaling
	RATE_REFERENCE_FIRE_SIZE = 10,
	RATE_MIN_MULTIPLIER = 0.35,
	RATE_MAX_MULTIPLIER = 3.0,
	
	-- Part classification
	LARGE_PART_MIN_VOLUME = 10,             -- Volume threshold for large vs small preset
	
	DYNAMIC_PARTICLE_PREFIX = "DynamicFX_",
	IGNORED_PART_NAMES = {
		Baseplate = true,
		Terrain = true,
	},
}

-- =============================================================================
-- EARTHQUAKE_SIMULATION: Object Drop Parameters
-- =============================================================================
GameConstants.EARTHQUAKE_SIMULATION = {
	MIN_VOLUME_QUAKE = 0.15,
	SCAN_YIELD_EVERY = 2000,
	MIN_STRUCTURAL_VOLUME = 1.2,
	MAX_STRUCTURAL_VOLUME = 220,
	MAX_PART_DIMENSION = 28,
	MAX_UNANCHOR_ASSEMBLY_MASS = 900,
	
	-- Object identification
	PILLAR_COLOR = Color3.fromRGB(181, 125, 93),
	STUCCO_TILE_SIZE = Vector3.new(3.288, 0.038, 3.288),
	TV_SIZE = Vector3.new(10.17, 5.751, 0.052),
	SIZE_EPSILON = 0.02,
	
	-- Aftershock configuration
	AFTERSHOCK_COUNT_MIN = 2,
	AFTERSHOCK_COUNT_MAX = 5,
	AFTERSHOCK_DURATION_MIN = 2,
	AFTERSHOCK_DURATION_MAX = 4,
	AFTERSHOCK_SCALE_MIN = 1.0,
	AFTERSHOCK_SCALE_MAX = 2.5,
}

-- =============================================================================
-- UI_ASSETS: Image IDs for HUD, Dialog, and Results Screen
-- =============================================================================
GameConstants.UI_ASSETS = {
	-- HUD objective icons
	OBJECTIVE_INCOMPLETE = "rbxassetid://139565534034394",
	OBJECTIVE_IN_PROGRESS = "rbxassetid://75916766300891",
	OBJECTIVE_COMPLETE = "rbxassetid://94228531190693",
	
	-- Dialog icons (populated from local ICON_MAP in DialogHandler)
	-- These should match the icon images used in dialog system
	DIALOG_ICON_INFO = "rbxassetid://...",          -- Replace with actual ID
	DIALOG_ICON_WARNING = "rbxassetid://...",       -- Replace with actual ID
	DIALOG_ICON_ERROR = "rbxassetid://...",         -- Replace with actual ID
	DIALOG_ICON_SUCCESS = "rbxassetid://...",       -- Replace with actual ID
	DIALOG_ICON_RESULT = "rbxassetid://...",        -- Replace with actual ID
	
	-- Results screen rank band images
	RANK_BAND_S = "rbxassetid://...",               -- Green
	RANK_BAND_A = "rbxassetid://...",               -- Blue
	RANK_BAND_B = "rbxassetid://...",               -- Yellow
	RANK_BAND_C = "rbxassetid://...",               -- Orange
	RANK_BAND_D = "rbxassetid://...",               -- Red
}

-- =============================================================================
-- DAY_CYCLE: Time and Environment Settings
-- =============================================================================
GameConstants.DAY_CYCLE = {
	DAY_LENGTH_SECONDS = 30,                -- How long a complete day cycle takes (real seconds)
	BLACKOUT_NIGHT_TIME = 0,                -- Clock time forced during blackout (midnight)
	ATMOSPHERE_DENSITY_NORMAL = 0,          -- Normal atmosphere density
	ATMOSPHERE_DENSITY_BLACKOUT = 0.6,      -- Density during blackout
}

-- =============================================================================
-- SCORING: Points and Ranking System
-- =============================================================================
GameConstants.SCORING = {
	-- Score calculation thresholds (old system, kept for reference)
	SCORE_THRESHOLDS = {
		{ max = 0.7, points = 100 },
		{ max = 1.0, points = 85 },
		{ max = 1.3, points = 70 },
		{ max = math.huge, points = 50 },
	},
	
	-- New points-based system (Results screen)
	POINTS_PER_STEP = {
		PERFECT = 1000,     -- time <= maxTime * 0.50
		EXCELLENT = 800,    -- time <= maxTime * 0.70
		COMPLETED = 600,    -- time <= maxTime * 1.00
		LATE = 400,         -- time <= maxTime * 1.30
		VERY_LATE = 200,    -- time > maxTime * 1.30
	},
	
	-- Rank thresholds (expressed as ratio of points earned vs maximum)
	RANKS = {
		{ min = 0.90, rank = "S" },
		{ min = 0.80, rank = "A+" },
		{ min = 0.70, rank = "A" },
		{ min = 0.60, rank = "B+" },
		{ min = 0.50, rank = "B" },
		{ min = 0.40, rank = "C+" },
		{ min = 0.30, rank = "C" },
		{ min = 0.00, rank = "D" },
	},
	
	-- Grade text (old system)
	GRADE_EXCELLENT = "EXCELENTE",
	GRADE_GOOD = "BUENO",
	GRADE_REGULAR = "REGULAR",
	GRADE_NEEDS_IMPROVEMENT = "NECESITA MEJORAR",
	GRADE_THRESHOLDS = {
		excellent = 90,
		good = 75,
		regular = 60,
	},
}

-- =============================================================================
-- HELPER: Utility function to get difficulty tier (1, 2, or 3 based on string)
-- =============================================================================
function GameConstants.getDifficultyTier(difficultyString)
	if difficultyString == "Easy" or difficultyString == "EASY" or difficultyString == 1 then
		return 1
	elseif difficultyString == "Medium" or difficultyString == "MEDIUM" or difficultyString == 2 then
		return 2
	elseif difficultyString == "Hard" or difficultyString == "HARD" or difficultyString == 3 then
		return 3
	end
	return 1 -- Default to Easy
end

-- =============================================================================
-- HELPER: Get simulation parameters by type and difficulty
-- =============================================================================
function GameConstants.getSimulationParams(simType, difficulty)
	if simType == "FireSimulation" then
		if difficulty == 1 then return GameConstants.SIMULATIONS.FIRE.EASY end
		if difficulty == 2 then return GameConstants.SIMULATIONS.FIRE.MEDIUM end
		if difficulty == 3 then return GameConstants.SIMULATIONS.FIRE.HARD end
	elseif simType == "EarthquakeSimulation" then
		if difficulty == 1 then return GameConstants.SIMULATIONS.EARTHQUAKE.EASY end
		if difficulty == 2 then return GameConstants.SIMULATIONS.EARTHQUAKE.MEDIUM end
		if difficulty == 3 then return GameConstants.SIMULATIONS.EARTHQUAKE.HARD end
	elseif simType == "ArmedGroupsSimulation" then
		if difficulty == 1 then return GameConstants.SIMULATIONS.ARMED_GROUPS.EASY end
		if difficulty == 2 then return GameConstants.SIMULATIONS.ARMED_GROUPS.MEDIUM end
		if difficulty == 3 then return GameConstants.SIMULATIONS.ARMED_GROUPS.HARD end
	end
	return nil
end

return GameConstants
