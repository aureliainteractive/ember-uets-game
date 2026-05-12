-- SimulationBase
-- Purpose: Unified base class for Fire, Earthquake, and ArmedGroups simulations.
-- Reduces code duplication by abstracting common lifecycle patterns:
--   1. Precondition validation
--   2. Simulation state management (active/inactive)
--   3. Session tracking
--   4. Player teleportation
--   5. HUD ticker management
--   6. Error handling and cleanup
--
-- Usage Pattern:
--   local base = SimulationBase.new("FireSimulation")
--   base:validateSetup(player, locationName, services)
--   base:activateSimulation(player, locationName, services, sessionData, onSimulationLogic)
--
-- Concrete simulators override:
--   - getSimulationType() → "Fire" | "Earthquake" | "ArmedGroups"
--   - onStart() → simulation-specific setup
--   - onCleanup() → simulation-specific cleanup

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DialogService = require(script.Parent.DialogService)
local NavigationUtils = require(script.Parent.NavigationUtils)
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))
local GameConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConstants"))

local SimulationBase = {}
SimulationBase.__index = SimulationBase

-- =============================================================================
-- Constructor
-- =============================================================================

function SimulationBase.new(displayName)
	local self = setmetatable({}, SimulationBase)
	self.displayName = displayName or "Simulation"
	return self
end

-- =============================================================================
-- Lifecycle: Setup and Validation
-- =============================================================================

-- Validate all preconditions before starting simulation
-- Returns: true if valid, false if error (error already logged)
function SimulationBase:validateSetup(player, locationName, services)
	-- Validate player
	if not player or not player.Parent then
		DialogService.send(player, "Error", "Error: Jugador inválido.")
		Logger.warn("System", self.displayName .. " setup rejected: invalid player")
		return false
	end

	-- Validate location
	if not locationName or locationName == "" then
		DialogService.send(player, "Error", "Error: Ubicación no especificada.")
		Logger.warn("System", self.displayName .. " setup rejected: invalid location")
		return false
	end

	-- Validate services
	if not services then
		DialogService.send(player, "Error", "Error: Servicios no disponibles.")
		Logger.warn("System", self.displayName .. " setup rejected: invalid services")
		return false
	end

	return true
end

-- Check if simulation already running at location
-- Returns: true if can proceed, false if already active
function SimulationBase:checkLocationAvailable(locationName, services)
	local simType = self:getSimulationType()
	
	if not services.canStartSimulation(simType, locationName) then
		Logger.warn("System", simType .. " at " .. locationName .. " already active")
		return false
	end

	return true
end

-- =============================================================================
-- Lifecycle: Activation and Cleanup
-- =============================================================================

-- Universal simulation startup wrapper
-- Handles: validation, session setup, teleport, HUD, error handling
-- Then calls onStart() for simulation-specific logic
function SimulationBase:activateSimulation(player, locationName, difficulty, services, state, onStart)
	local simType = self:getSimulationType()

	-- === VALIDATE ===
	if not self:validateSetup(player, locationName, services) then
		services.stopExternalSimulation(player)
		return
	end

	if not self:checkLocationAvailable(locationName, services) then
		DialogService.send(player, "Error", "Ya hay un simulacro activo en esta ubicacion.")
		services.stopExternalSimulation(player)
		return
	end

	-- === ACTIVATE ===
	services.setSimulationActive(simType, locationName, true)
	services.setPowerMode("BLACKOUT")

	-- === TELEPORT ===
	local teleported = NavigationUtils.teleportToSpawn(player, simType, locationName)
	if not teleported then
		Logger.warn("System", "Failed to teleport player to " .. simType .. " at " .. locationName)
		DialogService.send(player, "Error", "No se pudo ubicar al participante. Intente nuevamente.")
		services.setSimulationActive(simType, locationName, false)
		services.setPowerMode("NORMAL")
		services.stopExternalSimulation(player)
		return
	end

	-- === SESSION SETUP ===
	local steps = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig")).getSteps(simType)
	local session = {
		startTime = tick(),
		waypointTimes = {},
		lastWaypointTime = tick(),
		maxTimes = steps.maxTimes,
		stepNames = steps.stepNames,
		connections = {},
		simulationType = simType,
		locationName = locationName,
		difficulty = difficulty,
		simulationEnded = false,
	}
	state.playerSimulationData[player.UserId] = session

	-- === CHARACTER CLEANUP ===
	local function onCharacterRemoved()
		if session then
			session.simulationEnded = true
		end
	end
	local characterRemovedConn = player.CharacterRemoving:Connect(onCharacterRemoved)
	table.insert(session.connections, characterRemovedConn)

	-- === HUD TICKER ===
	services.HUDService.startTicker(player, session, services)

	Logger.info("System", string.format("%s started for %s at %s (difficulty %d)", 
		simType, player.Name, locationName, difficulty))

	-- === SIMULATION-SPECIFIC LOGIC ===
	if onStart then
		onStart(player, session, services)
	end

	-- === CLEANUP ON END ===
	local function cleanup()
		if not session or session.simulationEnded then
			return  -- Already cleaned up
		end
		session.simulationEnded = true

		if services and services.setSimulationActive then services.setSimulationActive(simType, locationName, false) end
		if services and services.setPowerMode then services.setPowerMode("NORMAL") end
		if services and services.HUDService and services.HUDService.stopTicker then services.HUDService.stopTicker(player) end
		if services and services.controllerHUDEvent then
			pcall(function() services.controllerHUDEvent:FireClient(player, "Hide") end)
		end
		
		-- Disconnect all session connections
		if session.connections then
			for _, conn in ipairs(session.connections) do
				if conn and type(conn.Disconnect) == "function" then
					pcall(function() conn:Disconnect() end)
				end
			end
		end

		state.playerSimulationData[player.UserId] = nil
		Logger.info("System", simType .. " cleanup completed for " .. (player.Name or "unknown"))
	end

	-- Store cleanup function in session for external access
	session.cleanup = cleanup
end

-- =============================================================================
-- Virtual Methods (Override in subclasses)
-- =============================================================================

function SimulationBase:getSimulationType()
	error("SimulationBase:getSimulationType() must be overridden")
end

-- =============================================================================
-- Utility: Common Helper Functions
-- =============================================================================

-- Get simulation parameters for this type and difficulty
function SimulationBase:getParams(difficulty)
	local simType = self:getSimulationType()
	return GameConstants.getSimulationParams(simType, difficulty)
end

-- Helper: Record a step completion time
function SimulationBase:recordStep(session)
	local now = tick()
	table.insert(session.waypointTimes, now - session.lastWaypointTime)
	session.lastWaypointTime = now
end

-- Helper: Common error recovery pattern
function SimulationBase:handleError(player, session, services, errorMsg, details)
	Logger.warn("System", string.format("%s error: %s (%s)", 
		session.simulationType, errorMsg, details or "no details"))
	DialogService.send(player, "Error", errorMsg)
	if session.cleanup then
		session.cleanup()
	end
	services.stopExternalSimulation(player)
end

return SimulationBase
