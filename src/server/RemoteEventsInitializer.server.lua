-- RemoteEventsInitializer.server.lua
-- Purpose: Create all required RemoteEvents at startup to avoid race conditions
-- This runs EARLY in server startup to ensure events are replicated before client scripts run
-- Note: This is separate from SimulationController so events are created even if SimulationController is disabled

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = pcall(function() return require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger")) end)

local function createRemoteEventIfMissing(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		if Logger and type(Logger) == "table" and Logger.info then
			Logger.info("System", "RemoteEvent already exists: " .. name)
		end
		return existing
	end
	
	local remoteEvent = Instance.new("RemoteEvent")
	remoteEvent.Name = name
	remoteEvent.Parent = ReplicatedStorage
	
	if Logger and type(Logger) == "table" and Logger.info then
		Logger.info("System", "Created RemoteEvent: " .. name)
	end
	return remoteEvent
end

-- Critical remote events that must exist before client scripts run
local criticalEvents = {
	"SimulationLoadingReady",
	"SimulationLoadingEvent",
	"ControllerUI_HUD",
	"HUDUpdate",
	"ShowDialog",
	"ShowResults",
	"KioskShowConfirmation",
	"KioskConfirm",
}

for _, eventName in ipairs(criticalEvents) do
	createRemoteEventIfMissing(eventName)
end

if Logger and type(Logger) == "table" and Logger.info then
	Logger.info("System", "RemoteEventsInitializer: All critical remote events created")
end
