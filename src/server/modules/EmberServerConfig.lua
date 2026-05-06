-- EmberServerConfig
-- Shared server-side configuration for the external EMBER REST API.

local EmberServerConfig = {
	API_BASE_URL = "https://api.aureliainteractive.me",

	-- Roblox does not support WebSocket clients, so movement is read through
	-- REST polling against GET /state.
	MOVEMENT_POLL_INTERVAL = 0.18,
	MOVEMENT_STATE_STALE_SECONDS = 0.75,
	MOVEMENT_REMOTE_EVENT = "EmberMovementUpdate",

	ROBLOX_MODE_TO_EMBER_MODE = {
		FireSimulation = "FireSimulation",
		EarthquakeSimulation = "EarthquakeSimulation",
		ArmedGroupsSimulation = "ArmedGroupsSimulation",
		ExploreSimulation = "ExplorationSimulation",
	},

	ROBLOX_DIFFICULTY_TO_EMBER_DIFFICULTY = {
		[1] = "Basico",
		[2] = "Medio",
		[3] = "Critico",
	},

	EARTHQUAKE_MOTOR_BY_DIFFICULTY = {
		[1] = { speed = 55 },
		[2] = { speed = 75 },
		[3] = { speed = 100 },
	},
}

return EmberServerConfig
