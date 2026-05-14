-- EmberMovementService
-- Polls ember-server REST state and broadcasts cabina movement to Roblox clients.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.EmberServerConfig)
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local EmberMovementService = {}

local VALID_DIRECTIONS = {
	idle = true,
	forward = true,
	backward = true,
	left = true,
	right = true,
}

local currentMovement = "idle"
local lastMovementAt = 0
local lastPollAt = 0
local pollRunning = false
local lastLoggedMovement = nil
local movementEvent = nil

local function stateUrl()
	return Config.API_BASE_URL .. "/state"
end

local function getMovementEvent()
	if movementEvent then
		return movementEvent
	end

	local existing = ReplicatedStorage:FindFirstChild(Config.MOVEMENT_REMOTE_EVENT)
	if existing and existing:IsA("RemoteEvent") then
		movementEvent = existing
		return movementEvent
	end

	movementEvent = Instance.new("RemoteEvent")
	movementEvent.Name = Config.MOVEMENT_REMOTE_EVENT
	movementEvent.Parent = ReplicatedStorage
	return movementEvent
end

local function broadcastMovement(direction)
	getMovementEvent():FireAllClients(direction, Config.MOVEMENT_STATE_STALE_SECONDS)
end

local function setMovement(direction)
	if not VALID_DIRECTIONS[direction] then
		return
	end

	currentMovement = direction
	lastMovementAt = os.clock()

	if direction ~= lastLoggedMovement then
		lastLoggedMovement = direction
		Logger.info("Movement", "EMBER movement -> " .. string.upper(direction))
	end

	broadcastMovement(direction)
end

local function pollOnce()
	local response = HttpService:GetAsync(stateUrl(), false)
	local decoded = HttpService:JSONDecode(response)
	local movement = decoded and decoded.movement

	if type(movement) == "string" then
		setMovement(movement)
	end
end

local function is502Error(err)
	local message = tostring(err)
	return string.find(message, "502", 1, true) ~= nil
end

local function pollLoop()
	while pollRunning do
		local now = os.clock()
		if now - lastPollAt >= Config.MOVEMENT_POLL_INTERVAL then
			lastPollAt = now
			local ok, err = pcall(pollOnce)
			if not ok then
				if currentMovement ~= "idle" then
					setMovement("idle")
				end
				if not is502Error(err) then
					Logger.warn("Movement", "EMBER movement poll failed: " .. tostring(err))
				end
				task.wait(0.8)
			end
		end

		task.wait(0.02)
	end
end

function EmberMovementService.start()
	if pollRunning then
		return
	end

	pollRunning = true
	lastMovementAt = os.clock()
	lastPollAt = 0

	getMovementEvent()
	task.spawn(pollLoop)
	Logger.info("Movement", "EMBER movement service started: " .. stateUrl())
end

function EmberMovementService.stop()
	pollRunning = false
	currentMovement = "idle"
	lastMovementAt = os.clock()
	broadcastMovement("idle")
end

function EmberMovementService.getMovement()
	return currentMovement
end

return EmberMovementService
