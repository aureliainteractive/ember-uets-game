local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local modules = script.Parent:WaitForChild("modules")
local DialogService = require(modules:WaitForChild("DialogService"))
local NavigationUtils = require(modules:WaitForChild("NavigationUtils"))
local EmberSimulationService = require(modules:WaitForChild("EmberSimulationService"))
local HUDService = require(modules:WaitForChild("HUDService"))
local FireSimulation = require(modules:WaitForChild("FireSimulation"))
local EarthquakeSimulation = require(modules:WaitForChild("EarthquakeSimulation"))
local ArmedGroupsSimulation = require(modules:WaitForChild("ArmedGroupsSimulation"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local simulationStartBindable = ReplicatedStorage:WaitForChild("SimulationStartBindable")
local highlightPartBindable = ReplicatedStorage:WaitForChild("HighlightPartBindable")
local finishedTaskBindable = ReplicatedStorage:WaitForChild("FinishedTaskBindable")
local physicalActuatorBindable = ReplicatedStorage:FindFirstChild("PhysicalActuatorBindable")
local controllerHUDEvent = ReplicatedStorage:WaitForChild("ControllerUI_HUD")
local hudUpdateEvent = ReplicatedStorage:WaitForChild("HUDUpdate")

-- All RemoteEvents should be created in-place in Studio ReplicatedStorage
-- to avoid replication race conditions
local simulationLoadingReadyEvent = ReplicatedStorage:WaitForChild("SimulationLoadingReady")

local spawnpointsFolder = workspace:WaitForChild("Spawnpoints")
local mainLobbySpawn = spawnpointsFolder:WaitForChild("MainLobby")
local audioPlayer = workspace.Intercom.AudioPlayer
local FIRE_ALARM_SOUND_ID = "18682406265"
local EARTHQUAKE_ALARM_SOUND_ID = "138221067"
local SIMULATION_GLOBAL_TIMEOUT = 300
local LOADING_READY_TIMEOUT = 15

local activeSimulations = {}
local playerSimulationData = {}
local pendingSimulationStarts = {}

local function canStartSimulation(simType, locationName)
	return not activeSimulations[simType .. "_" .. locationName]
end

local function setSimulationActive(simType, locationName, active)
	activeSimulations[simType .. "_" .. locationName] = active or nil
end

local function getActiveSimulationKey(eventType)
	if eventType == "FireSimulation" then
		return "Fire"
	elseif eventType == "EarthquakeSimulation" then
		return "Earthquake"
	elseif eventType == "ArmedGroupsSimulation" then
		return "ArmedGroups"
	elseif eventType == "ExploreSimulation" then
		return "Explore"
	end

	return nil
end

local function setPowerMode(mode)
	if Lighting:GetAttribute("PowerMode") ~= nil then
		Lighting:SetAttribute("PowerMode", mode)
		Logger.info("System", string.format("PowerMode updated to %s", mode))
	else
		Logger.warn("System", "Lighting.PowerMode attribute is missing")
	end
end

local function playIntercomSound(soundId)
	if not audioPlayer then
		return
	end
	audioPlayer:Stop()
	audioPlayer.Asset = "rbxassetid://" .. soundId
	audioPlayer.TimePosition = 0
	audioPlayer:Play()
end

local function stopIntercom()
	if audioPlayer then
		audioPlayer:Stop()
		audioPlayer.TimePosition = 0
	end
end

local function startExploreSimulation(player, locationName, _difficulty)
	-- === Validate input parameters ===
	if not player or not player.Parent then
		Logger.warn("System", "startExploreSimulation: Invalid player")
		return
	end
	if not locationName or locationName == "" then
		Logger.warn("System", "startExploreSimulation: Empty location name")
		return
	end

	setSimulationActive("Explore", locationName, true)
	
	local teleported = NavigationUtils.teleportToSpawn(player, "FireSimulation", locationName)
	if not teleported then
		Logger.warn("System", "startExploreSimulation: Failed to teleport player to " .. locationName)
		setSimulationActive("Explore", locationName, false)
		return
	end

	controllerHUDEvent:FireClient(player, "Show")
	if audioPlayer then
		audioPlayer:Stop()
		audioPlayer.Asset = "rbxassetid://106924095504453"
		audioPlayer.Looped = true
		audioPlayer.Volume = 0.6
		audioPlayer:Play()
	end
	Logger.info("System", string.format("Explore simulation started for %s at %s", player.Name, locationName))
end

local function stopExternalSimulation(player)
	local ok, err = EmberSimulationService.stop(player)
	if not ok and player and player.Parent then
		DialogService.send(player, "Warning", "No se pudo notificar el fin de simulacro a EMBER Server.")
		Logger.warn("Network", "simulation_stop notification failed: " .. tostring(err))
	end
	return ok
end

finishedTaskBindable.Event:Connect(function(player, taskName, callback)
	if not player or not player.Parent then
		if callback then
			callback(false, "Jugador invalido")
		end
		return
	end
	local tasks = (player:GetAttribute("TasksCompleted") or 0) + 1
	player:SetAttribute("TasksCompleted", tasks)
	if callback then
		callback(true, tasks)
	end
end)

highlightPartBindable.Event:Connect(function(player, part, enable, callback)
	if not player or not player.Parent then
		if callback then
			callback(false, "Jugador invalido")
		end
		return
	end
	if not part or not part:IsA("BasePart") or not part.Parent then
		if callback then
			callback(false, "Parte invalida")
		end
		return
	end
	if enable then
		NavigationUtils.highlightPart(part, true)
		if callback then
			callback(true)
		end
		return
	end
	local existing = part:FindFirstChild(ReplicatedStorage:WaitForChild("HighlightTemplate").Name)
	NavigationUtils.highlightPart(part, false)
	if callback then
		callback(existing ~= nil)
	end
end)

if physicalActuatorBindable and physicalActuatorBindable:IsA("BindableEvent") then
	physicalActuatorBindable.Event:Connect(function(_player, actuatorName, _value, _duration, callback)
		Logger.warn(
			"Network",
			string.format("Legacy actuator command ignored: %s. Actuators are controlled by ember-server.", tostring(actuatorName))
		)
		if callback then
			callback(false, "Actuadores ahora son controlados por ember-server")
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	local simData = playerSimulationData[player.UserId]
	if not simData then
		return
	end
	if simData.seedPart and simData.seedPart.Parent then
		NavigationUtils.highlightPart(simData.seedPart, false)
	end
	if simData.connections then
		for _, conn in pairs(simData.connections) do
			if conn and conn.Connected then
				conn:Disconnect()
			end
		end
	end
	if simData.simulationEnded ~= nil then
		simData.simulationEnded = true
	end
	stopExternalSimulation(player)
	playerSimulationData[player.UserId] = nil
	pendingSimulationStarts[player.UserId] = nil
	Logger.debug("System", string.format("Simulation state cleared for %s", player.Name))
end)

local DIFFICULTY_MAP = { Easy = 1, Medium = 2, Hard = 3 }

local function startSimulationNow(player, eventType, locationName, difficulty)
	if not player or not player.Parent then
		Logger.warn("System", "Start request skipped due to invalid player")
		return
	end

	-- Reset all doors to closed state for simulation startup
	local resetDoorsFunction = ReplicatedStorage:FindFirstChild("ResetAllDoorsFunction")
	if resetDoorsFunction and resetDoorsFunction:IsA("BindableFunction") then
		local ok, err = pcall(function()
			resetDoorsFunction:Invoke()
		end)
		if not ok then
			Logger.warn("Door", "Failed to reset doors: " .. tostring(err))
		end
	end

	if eventType ~= "ExploreSimulation" then
		stopIntercom()
	end

	local activeKey = getActiveSimulationKey(eventType)
	if activeKey and not canStartSimulation(activeKey, locationName) then
		DialogService.send(player, "Error", "Ya hay un simulacro activo en esta ubicacion.")
		return
	end

	if eventType ~= "ExploreSimulation" then
		local externalStarted, externalErr = EmberSimulationService.start(player, eventType, difficulty)
		if not externalStarted then
			DialogService.send(player, "Error", "No se pudo iniciar el simulacro en EMBER Server.")
			Logger.warn("Network", "simulation_start notification failed: " .. tostring(externalErr))
			return
		end
	end

	local services = {
		setPowerMode = setPowerMode,
		canStartSimulation = canStartSimulation,
		setSimulationActive = setSimulationActive,
		playIntercomSound = playIntercomSound,
		HUDService = HUDService,
		controllerHUDEvent = controllerHUDEvent,
		hudUpdateEvent = hudUpdateEvent,
		mainLobbySpawn = mainLobbySpawn,
		FIRE_ALARM_SOUND_ID = FIRE_ALARM_SOUND_ID,
		EARTHQUAKE_ALARM_SOUND_ID = EARTHQUAKE_ALARM_SOUND_ID,
		SIMULATION_GLOBAL_TIMEOUT = SIMULATION_GLOBAL_TIMEOUT,
		stopExternalSimulation = stopExternalSimulation,
		startEarthquakeMotor = EmberSimulationService.startEarthquakeMotor,
	}
	local state = {
		playerSimulationData = playerSimulationData,
	}

	local ok, err = pcall(function()
		if eventType == "FireSimulation" then
			FireSimulation.start(player, locationName, difficulty, services, state)
		elseif eventType == "EarthquakeSimulation" then
			EarthquakeSimulation.start(player, locationName, difficulty, services, state)
		elseif eventType == "ArmedGroupsSimulation" then
			ArmedGroupsSimulation.start(player, locationName, difficulty, services, state)
		elseif eventType == "ExploreSimulation" then
			startExploreSimulation(player, locationName, difficulty)
		else
			DialogService.send(player, "Error", "Tipo de simulacro no reconocido: " .. tostring(eventType))
		end
	end)

	if not ok then
		stopExternalSimulation(player)
		Logger.error("System", "Simulation start crashed: " .. tostring(err))
		DialogService.send(player, "Error", "El simulacro fallo al iniciar. EMBER Server fue restaurado.")
	end
end

simulationLoadingReadyEvent.OnServerEvent:Connect(function(player)
	local pending = pendingSimulationStarts[player.UserId]
	if not pending then
		return
	end
	if pending.player ~= player or not player.Parent then
		pendingSimulationStarts[player.UserId] = nil
		return
	end

	pendingSimulationStarts[player.UserId] = nil
	Logger.info("System", string.format("Loading ready received for %s", player.Name))
	startSimulationNow(player, pending.eventType, pending.locationName, pending.difficulty)
end)

simulationStartBindable.Event:Connect(function(player, eventType, locationName, difficultyStr)
	if not player or not player.Parent then
		Logger.warn("System", "Simulation request rejected due to invalid player")
		return
	end
	if type(eventType) ~= "string" or type(locationName) ~= "string" or locationName == "" then
		DialogService.send(player, "Error", "Parametros de simulacro invalidos.")
		return
	end
	local difficulty = DIFFICULTY_MAP[difficultyStr]
	if not difficulty then
		DialogService.send(player, "Error", "Nivel de dificultad desconocido: " .. tostring(difficultyStr))
		return
	end
	Logger.info(
		"System",
		string.format(
			"Simulation requested: %s | %s | %s | %s",
			eventType,
			locationName,
			difficultyStr,
			player.Name
		)
	)

	local request = {
		player = player,
		eventType = eventType,
		locationName = locationName,
		difficulty = difficulty,
	}
	pendingSimulationStarts[player.UserId] = request

	task.delay(LOADING_READY_TIMEOUT, function()
		local pending = pendingSimulationStarts[player.UserId]
		if pending ~= request then
			return
		end
		pendingSimulationStarts[player.UserId] = nil
		if player and player.Parent then
			Logger.warn("System", string.format("Loading ready timeout reached for %s", player.Name))
			startSimulationNow(player, eventType, locationName, difficulty)
		end
	end)
end)

setPowerMode("NORMAL")
FireSimulation.hideFirefighters()
Logger.info("System", "SimulationController initialized")
