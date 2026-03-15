-- ScoringSystem
-- Purpose: Score calculation, grading, and final results presentation.
-- Dependencies: DialogService, NavigationUtils

local DialogService = require(script.Parent.DialogService)
local NavigationUtils = require(script.Parent.NavigationUtils)

local spawnpointsFolder = workspace:WaitForChild("Spawnpoints")
local mainLobbySpawn = spawnpointsFolder:WaitForChild("MainLobby")

local ScoringSystem = {}

-- Calculates average score from step times against max times.
function ScoringSystem.calculateScore(times, maxTimes)
	local total = 0
	for i, t in ipairs(times) do
		local max = maxTimes[i]
		if t <= max * 0.7 then
			total += 100
		elseif t <= max then
			total += 85
		elseif t <= max * 1.3 then
			total += 70
		else
			total += 50
		end
	end
	return math.floor(total / #times)
end

-- Returns grade text for a numeric score.
function ScoringSystem.getGrade(score)
	if score >= 90 then
		return "EXCELENTE"
	elseif score >= 75 then
		return "BUENO"
	elseif score >= 60 then
		return "REGULAR"
	end
	return "NECESITA MEJORAR"
end

-- Shows final results dialog sequence and returns player to lobby.
function ScoringSystem.showFinalResults(player, simData, simType)
	if not simData.waypointTimes or #simData.waypointTimes == 0 then
		warn(string.format("[SimController] Sin tiempos registrados para mostrar resultados (%s).", player.Name))
		NavigationUtils.teleportPlayer(player, mainLobbySpawn)
		return
	end

	local score = ScoringSystem.calculateScore(simData.waypointTimes, simData.maxTimes)
	local grade = ScoringSystem.getGrade(score)

	task.wait(2)
	DialogService.send(player, "Result", "RESULTADOS DEL SIMULACRO — " .. simType)
	task.wait(1)
	DialogService.send(player, "Result", string.format("Calificacion: %s  |  Puntaje: %d/100", grade, score))
	task.wait(1)

	local totalElapsed = 0
	for i, t in ipairs(simData.waypointTimes) do
		totalElapsed += t
		local stepName = (simData.stepNames and simData.stepNames[i]) or ("Paso " .. i)
		local status = (t <= simData.maxTimes[i]) and "Completado" or "Excedido"
		DialogService.send(player, "Result", string.format("%s: %.1fs — %s", stepName, t, status))
		task.wait(0.5)
	end

	task.wait(1)
	DialogService.send(player, "Result", string.format("Tiempo total: %.1fs", totalElapsed))
	task.wait(3)

	NavigationUtils.teleportPlayer(player, mainLobbySpawn)
	DialogService.send(player, "Info", "Ha regresado al lobby principal.")
end

return ScoringSystem
