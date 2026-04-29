-- ResultsSystem
-- Purpose: Computes final simulation results and fires them
--          to the client results screen via ShowResults RemoteEvent.
-- Dependencies: NavigationUtils, ReplicatedStorage.ShowResults

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local NavigationUtils = require(script.Parent.NavigationUtils)
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local showResultsEvent = ReplicatedStorage:WaitForChild("ShowResults")
local returnToLobbyEvent = ReplicatedStorage:WaitForChild("ReturnToLobby")

local ResultsSystem = {}

--- CONSTANTS ---

local POINTS_PER_STEP = {
	PERFECT = 1000, -- time <= maxTime * 0.50
	EXCELLENT = 800, -- time <= maxTime * 0.70
	COMPLETED = 600, -- time <= maxTime * 1.00
	LATE = 400, -- time <= maxTime * 1.30
	VERY_LATE = 200, -- time >  maxTime * 1.30
}

-- Rank thresholds are expressed as a ratio of points earned
-- vs maximum possible points (stepCount * 1000).
-- This makes ranks work correctly for both 3-step and 4-step sims.
local RANKS = {
	{ min = 0.90, rank = "S" },
	{ min = 0.80, rank = "A+" },
	{ min = 0.70, rank = "A" },
	{ min = 0.60, rank = "B+" },
	{ min = 0.50, rank = "B" },
	{ min = 0.40, rank = "C+" },
	{ min = 0.30, rank = "C" },
	{ min = 0.00, rank = "D" },
}

--- PURE FUNCTIONS ---

-- Returns points earned for a single step.
local function stepPoints(time, maxTime)
	if time <= maxTime * 0.50 then
		return POINTS_PER_STEP.PERFECT
	elseif time <= maxTime * 0.70 then
		return POINTS_PER_STEP.EXCELLENT
	elseif time <= maxTime * 1.00 then
		return POINTS_PER_STEP.COMPLETED
	elseif time <= maxTime * 1.30 then
		return POINTS_PER_STEP.LATE
	else
		return POINTS_PER_STEP.VERY_LATE
	end
end

-- Returns rank string for a points ratio (0.0 – 1.0).
local function getRank(ratio)
	for _, entry in ipairs(RANKS) do
		if ratio >= entry.min then
			return entry.rank
		end
	end
	return "D"
end

-- Returns precision % (clamped 0–100).
-- Formula: (totalBudget / totalUsed) * 100, max 100.
-- Faster than budget = 100%. Slower = proportionally lower.
local function getPrecision(waypointTimes, maxTimes)
	local totalUsed = 0
	local totalBudget = 0
	for i, t in ipairs(waypointTimes) do
		totalUsed += t
		totalBudget += (maxTimes[i] or 0)
	end
	if totalUsed <= 0 then
		return 100
	end
	return math.clamp(math.floor((totalBudget / totalUsed) * 100), 0, 100)
end

-- Returns count of steps where time > maxTime * 1.5.
local function getCriticalErrors(waypointTimes, maxTimes)
	local count = 0
	for i, t in ipairs(waypointTimes) do
		if t > (maxTimes[i] or 0) * 1.5 then
			count += 1
		end
	end
	return count
end

-- Formats seconds as MM:SS string.
local function formatTime(seconds)
	local s = math.floor(seconds)
	return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

--- COMPUTE ---

-- Builds the full results payload table from a session.
-- Returns nil with a warn if session data is incomplete.
function ResultsSystem.compute(session, simType, locationName, difficulty)
	if not session or not session.waypointTimes or #session.waypointTimes == 0 then
		Logger.warn("System", "Results payload computation skipped due to incomplete session")
		return nil
	end

	local times = session.waypointTimes
	local maxTimes = session.maxTimes
	local names = session.stepNames
	local stepCount = #names

	-- Per-step points
	local stepResults = {}
	local totalPoints = 0
	for i = 1, stepCount do
		local t = times[i] or (maxTimes[i] * 1.5)
		local pts = stepPoints(t, maxTimes[i])
		totalPoints += pts
		stepResults[i] = {
			name = names[i],
			time = t,
			points = pts,
			done = (times[i] ~= nil),
		}
	end

	local maxPoints = stepCount * 1000
	local ratio = totalPoints / maxPoints

	-- Total elapsed time
	local totalElapsed = 0
	for _, t in ipairs(times) do
		totalElapsed += t
	end

	return {
		simType = simType,
		locationName = locationName,
		difficulty = difficulty,
		totalPoints = totalPoints,
		rank = getRank(ratio),
		totalTime = formatTime(totalElapsed),
		objectivesDone = #times,
		objectivesTotal = stepCount,
		precision = getPrecision(times, maxTimes),
		criticalErrors = getCriticalErrors(times, maxTimes),
		stepResults = stepResults,
	}
end

--- SHOW ---

-- Computes results and fires them to the client results screen.
-- Replaces ScoringSystem.showFinalResults.
-- Lobby return is client-triggered via ReturnToLobby.
function ResultsSystem.show(player, session, simType, locationName, difficulty, mainLobbySpawn)
	local payload = ResultsSystem.compute(session, simType, locationName, difficulty)

	if not payload then
		Logger.warn("System", "Results computation failed for player " .. tostring(player.Name))
		NavigationUtils.teleportPlayer(player, mainLobbySpawn)
		return
	end

	task.wait(2)

	pcall(function()
		showResultsEvent:FireClient(player, payload)
	end)

	Logger.info(
		"System",
		string.format("Results delivered: %s | %s | %d pts | rank %s", player.Name, simType, payload.totalPoints, payload.rank)
	)
end

-- Note: teleport to lobby is now triggered by the client
-- when the player clicks Menú principal on the results screen.
-- The server exposes this via a separate RemoteEvent: ReturnToLobby.

--- REMOTE EVENTS ---

returnToLobbyEvent.OnServerEvent:Connect(function(player)
	local mainLobbySpawn = workspace:WaitForChild("Spawnpoints"):WaitForChild("MainLobby")
	NavigationUtils.teleportPlayer(player, mainLobbySpawn)
	Logger.info("System", string.format("Player returned to lobby: %s", player.Name))
end)

return ResultsSystem
