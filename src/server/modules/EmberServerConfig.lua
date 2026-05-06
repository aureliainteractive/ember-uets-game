-- EmberServerConfig
-- Shared server-side configuration for the external EMBER REST API.

local EmberServerConfig = {
	API_BASE_URL = "https://api.aureliainteractive.me",

	-- Roblox does not support WebSocket clients, so movement is read through
	-- REST polling against GET /state.
	MOVEMENT_POLL_INTERVAL = 0.18,
	MOVEMENT_STATE_STALE_SECONDS = 0.75,
	MOVEMENT_REMOTE_EVENT = "EmberMovementUpdate",
}

return EmberServerConfig
