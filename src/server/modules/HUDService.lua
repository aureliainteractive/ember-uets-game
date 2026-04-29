-- HUDService
-- Purpose: Server-side ticker that pushes live HUD data
--          (timer, score, objective states) to the client.
-- Dependencies: ScoringSystem

local ScoringSystem = require(script.Parent.ScoringSystem)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))
local activeTickers = {} -- keyed by player.UserId

local HUDService = {}

-- Starts or restarts a per-player HUD ticker loop.
function HUDService.startTicker(player, session, services)
	if not player or not player.Parent then
		Logger.warn("UI", "HUD ticker start rejected due to invalid player")
		return
	end

	if
		not session
		or session.startTime == nil
		or session.waypointTimes == nil
		or session.maxTimes == nil
		or session.stepNames == nil
	then
		Logger.warn("UI", "HUD ticker start rejected due to invalid session data")
		return
	end

	if not services or services.SIMULATION_GLOBAL_TIMEOUT == nil or services.hudUpdateEvent == nil then
		Logger.warn("UI", "HUD ticker start rejected due to invalid services payload")
		return
	end

	HUDService.stopTicker(player)

	activeTickers[player.UserId] = true

	task.spawn(function()
		while activeTickers[player.UserId] and player.Parent do
			local timeLeft = math.max(0, math.floor(services.SIMULATION_GLOBAL_TIMEOUT - (tick() - session.startTime)))

			local score = 100
			if #session.waypointTimes > 0 then
				score = ScoringSystem.calculateScore(session.waypointTimes, session.maxTimes)
			end

			local completedSteps = #session.waypointTimes

			pcall(function()
				services.hudUpdateEvent:FireClient(player, timeLeft, score, completedSteps, session.stepNames)
			end)

			if timeLeft <= 0 then
				break
			end
			task.wait(1)
		end
		activeTickers[player.UserId] = nil
	end)
end

-- Signals the ticker loop for this player to exit.
function HUDService.stopTicker(player)
	activeTickers[player.UserId] = nil
end

return HUDService
