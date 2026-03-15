local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local modules = script:WaitForChild("modules")
local DialogService = require(modules:WaitForChild("DialogService"))
local NavigationUtils = require(modules:WaitForChild("NavigationUtils"))
local ScoringSystem = require(modules:WaitForChild("ScoringSystem"))
local ActuatorService = require(modules:WaitForChild("ActuatorService"))
local FireSimulation = require(modules:WaitForChild("FireSimulation"))
local EarthquakeSimulation = require(modules:WaitForChild("EarthquakeSimulation"))
local ArmedGroupsSimulation = require(modules:WaitForChild("ArmedGroupsSimulation"))

local simulationStartBindable = ReplicatedStorage:WaitForChild("SimulationStartBindable")
local highlightPartBindable = ReplicatedStorage:WaitForChild("HighlightPartBindable")
local finishedTaskBindable = ReplicatedStorage:WaitForChild("FinishedTaskBindable")
local physicalActuatorBindable = ReplicatedStorage:WaitForChild("PhysicalActuatorBindable")
local controllerHUDEvent = ReplicatedStorage:WaitForChild("ControllerUI_HUD")

local spawnpointsFolder = workspace:WaitForChild("Spawnpoints")
local mainLobbySpawn = spawnpointsFolder:WaitForChild("MainLobby")
local audioPlayer = workspace.Intercom.AudioPlayer
local FIRE_ALARM_SOUND_ID = "18682406265"
local EARTHQUAKE_ALARM_SOUND_ID = "138221067"
local SIMULATION_GLOBAL_TIMEOUT = 300

local activeSimulations = {}
local playerSimulationData = {}

local function canStartSimulation(simType, locationName)
	return not activeSimulations[simType .. "_" .. locationName]
end

local function setSimulationActive(simType, locationName, active)
	activeSimulations[simType .. "_" .. locationName] = active or nil
end

local function setPowerMode(mode)
	if Lighting:GetAttribute("PowerMode") ~= nil then
		Lighting:SetAttribute("PowerMode", mode)
		print(string.format("[SimController] PowerMode -> %s", mode))
	else
		warn("[SimController] El atributo 'PowerMode' no existe en Lighting.")
	end
end

local function playIntercomSound(soundId)
	if not audioPlayer then return end
	audioPlayer:Stop(); audioPlayer.SoundId = "rbxassetid://" .. soundId; audioPlayer.TimePosition = 0; audioPlayer:Play()
end

local function stopIntercom()
	if audioPlayer then audioPlayer:Stop(); audioPlayer.TimePosition = 0 end
end

local function startExploreSimulation(player, locationName, _difficulty)
	setSimulationActive("Explore", locationName, true)
	NavigationUtils.teleportToSpawn(player, "FireSimulation", locationName)
	controllerHUDEvent:FireClient(player, "Show")
	if audioPlayer then audioPlayer:Stop(); audioPlayer.SoundId = "rbxassetid://106924095504453"; audioPlayer.Looped = true; audioPlayer.Volume = 0.6; audioPlayer:Play() end
	print(string.format("[SimController] Exploración iniciada: %s — %s", player.Name, locationName))
end

finishedTaskBindable.Event:Connect(function(player, taskName, callback)
	if not player or not player.Parent then if callback then callback(false, "Jugador invalido") end; return end
	local tasks = (player:GetAttribute("TasksCompleted") or 0) + 1
	player:SetAttribute("TasksCompleted", tasks)
	if callback then callback(true, tasks) end
end)

highlightPartBindable.Event:Connect(function(player, part, enable, callback)
	if not player or not player.Parent then if callback then callback(false, "Jugador invalido") end; return end
	if not part or not part:IsA("BasePart") or not part.Parent then if callback then callback(false, "Parte invalida") end; return end
	if enable then NavigationUtils.highlightPart(part, true); if callback then callback(true) end; return end
	local existing = part:FindFirstChild(ReplicatedStorage:WaitForChild("HighlightTemplate").Name)
	NavigationUtils.highlightPart(part, false)
	if callback then callback(existing ~= nil) end
end)

physicalActuatorBindable.Event:Connect(function(player, actuatorName, value, duration, callback)
	ActuatorService.fire(player, actuatorName, value, duration, callback)
end)

game.Players.PlayerRemoving:Connect(function(player)
	local simData = playerSimulationData[player.UserId]
	if not simData then return end
	if simData.seedPart and simData.seedPart.Parent then NavigationUtils.highlightPart(simData.seedPart, false) end
	if simData.connections then for _, conn in pairs(simData.connections) do if conn and conn.Connected then conn:Disconnect() end end end
	if simData.simulationEnded ~= nil then simData.simulationEnded = true end
	playerSimulationData[player.UserId] = nil
	print(string.format("[SimController] Datos de simulacion limpiados: %s.", player.Name))
end)

local DIFFICULTY_MAP = { Easy = 1, Medium = 2, Hard = 3 }

simulationStartBindable.Event:Connect(function(player, eventType, locationName, difficultyStr)
	if not player or not player.Parent then warn("[SimController] Solicitud de simulacro con jugador invalido."); return end
	if type(eventType) ~= "string" or type(locationName) ~= "string" or locationName == "" then DialogService.send(player, "Error", "Parametros de simulacro invalidos."); return end
	local difficulty = DIFFICULTY_MAP[difficultyStr]
	if not difficulty then DialogService.send(player, "Error", "Nivel de dificultad desconocido: " .. tostring(difficultyStr)); return end
	print(string.format("[SimController] Solicitud: %s | %s | %s | %s", eventType, locationName, difficultyStr, player.Name))
	if eventType ~= "ExploreSimulation" then stopIntercom() end
	local ctx = { canStartSimulation = canStartSimulation, setSimulationActive = setSimulationActive, setPowerMode = setPowerMode, playIntercomSound = playIntercomSound, controllerHUDEvent = controllerHUDEvent, playerSimulationData = playerSimulationData, SIMULATION_GLOBAL_TIMEOUT = SIMULATION_GLOBAL_TIMEOUT, mainLobbySpawn = mainLobbySpawn, FIRE_ALARM_SOUND_ID = FIRE_ALARM_SOUND_ID, EARTHQUAKE_ALARM_SOUND_ID = EARTHQUAKE_ALARM_SOUND_ID }
	if eventType == "FireSimulation" then FireSimulation.start(player, locationName, difficulty, ctx)
	elseif eventType == "EarthquakeSimulation" then EarthquakeSimulation.start(player, locationName, difficulty, ctx)
	elseif eventType == "ArmedGroupsSimulation" then ArmedGroupsSimulation.start(player, locationName, difficulty, ctx)
	elseif eventType == "ExploreSimulation" then startExploreSimulation(player, locationName, difficulty)
	else DialogService.send(player, "Error", "Tipo de simulacro no reconocido: " .. tostring(eventType)) end
end)

setPowerMode("NORMAL")
FireSimulation.hideFirefighters()
print("[SimController] Sistema inicializado correctamente. Version 2.2.")
