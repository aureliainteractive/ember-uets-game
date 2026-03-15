-- ArmedGroupsSimulation
-- Purpose: Armed-groups drill flow including confinement, checkpoints, and evacuation.
-- Dependencies: DialogService, NavigationUtils, ScoringSystem

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogService = require(script.Parent.DialogService)
local NavigationUtils = require(script.Parent.NavigationUtils)
local ScoringSystem = require(script.Parent.ScoringSystem)

local atacantNPC = ReplicatedStorage:WaitForChild("Atacant NPC")
local AtacantsSpawns = workspace:WaitForChild("AtacantsSpawns")

local RNG = Random.new()

local ArmedGroupsSimulation = {}

local function endArmedGroupsByDeath(player, locationName, spawnedNPCs, services, state)
	if not player or not player.Parent then return end
	local session = state.playerSimulationData[player.UserId]
	if not session then return end

	DialogService.send(player, "Error", "SIMULACRO FINALIZADO — El participante fue neutralizado.")
	task.wait(2)

	for _, npc in ipairs(spawnedNPCs or {}) do
		if npc and npc.Parent then npc:Destroy() end
	end

	state.playerSimulationData[player.UserId] = nil
	services.setPowerMode("NORMAL")
	services.setSimulationActive("ArmedGroups", locationName, false)

	task.wait(1)
	NavigationUtils.teleportPlayer(player, services.mainLobbySpawn)
	DialogService.send(player, "Info", "Ha regresado al lobby principal.")
end

-- Starts an armed-groups simulation for a player at a location and difficulty.
function ArmedGroupsSimulation.start(player, locationName, difficulty, services, state)
	local npcCounts = { [1] = 2, [2] = 4, [3] = 6 }
	local prepTimes = { [1] = 7, [2] = 5, [3] = 4 }

	if not services.canStartSimulation("ArmedGroups", locationName) then
		DialogService.send(player, "Error", "Ya hay un simulacro activo en esta ubicacion.")
		return
	end
	services.setSimulationActive("ArmedGroups", locationName, true)

	local npcCount = npcCounts[math.clamp(difficulty, 1, 3)]
	local prepTime = prepTimes[math.clamp(difficulty, 1, 3)]

	local spawnFolder = AtacantsSpawns:FindFirstChild(locationName)
	if not spawnFolder then
		DialogService.send(player, "Error", "No se pudo cargar la ubicacion del ejercicio.")
		services.setSimulationActive("ArmedGroups", locationName, false)
		return
	end

	services.controllerHUDEvent:FireClient(player, "Show")
	NavigationUtils.teleportToSpawn(player, "ArmedGroupsSimulation", locationName)
	services.setPowerMode("BLACKOUT")

	local refuges = NavigationUtils.getRefuges(locationName, "ArmedGroupsSimulation")

	state.playerSimulationData[player.UserId] = {
		waypointTimes = {},
		lastWaypointTime = tick(),
		maxTimes = { 10, 20, 15, 18 },
		stepNames = { "Alerta", "Confinamiento", "Verificacion", "Evacuacion" },
		connections = {},
	}

	local session = state.playerSimulationData[player.UserId]
	print(string.format("[SimController] Grupos armados iniciado: %s — %s — Dificultad %d", player.Name, locationName, difficulty))

	local function recordStep()
		local now = tick()
		table.insert(session.waypointTimes, now - session.lastWaypointTime)
		session.lastWaypointTime = now
	end

	local spawns = {}
	for _, v in pairs(spawnFolder:GetChildren()) do
		if v:IsA("BasePart") or v:IsA("Model") or v:IsA("Attachment") then
			table.insert(spawns, v)
		end
	end

	if #spawns == 0 then
		DialogService.send(player, "Error", "No hay puntos de aparicion configurados para esta ubicacion.")
		services.setPowerMode("NORMAL")
		services.setSimulationActive("ArmedGroups", locationName, false)
		return
	end

	npcCount = math.min(npcCount, #spawns)
	for i = #spawns, 2, -1 do
		local j = RNG:NextInteger(1, i)
		spawns[i], spawns[j] = spawns[j], spawns[i]
	end

	local spawnedNPCs = {}

	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Once(function()
		if state.playerSimulationData[player.UserId] then
			endArmedGroupsByDeath(player, locationName, spawnedNPCs, services, state)
		end
	end)

	DialogService.send(player, "Warning", "CODIGO ROJO — Se ha confirmado presencia de personas no autorizadas con comportamiento hostil.")
	task.wait(2)
	DialogService.send(player, "Info", "Active el protocolo de confinamiento. Mantenga la calma absoluta.")
	task.wait(2)
	DialogService.send(player, "Info", "Evite ruidos. Silencie su celular. No salga a menos que se lo indiquen.")
	task.wait(prepTime)

	for i = 1, npcCount do
		local sp = spawns[i]
		if sp then
			local clone = atacantNPC:Clone()
			local cf = sp:IsA("BasePart") and sp.CFrame
				or sp:IsA("Attachment") and sp.WorldCFrame
				or sp:GetPivot()
			if clone:IsA("Model") then
				clone:PivotTo(cf)
			elseif clone:IsA("BasePart") then
				clone.CFrame = cf
			end
			clone.Parent = workspace
			table.insert(spawnedNPCs, clone)
		end
	end

	DialogService.send(player, "Warning", "Amenaza confirmada en las instalaciones. Siga el protocolo.")
	task.wait(2)

	local wp1 = NavigationUtils.getWaypoint(locationName, "ArmedGroupsSimulation", 1)
	if not wp1 then
		warn("[SimController] Grupos armados: Waypoint1 no encontrado.")
		services.setPowerMode("NORMAL")
		services.setSimulationActive("ArmedGroups", locationName, false)
		state.playerSimulationData[player.UserId] = nil
		return
	end

	NavigationUtils.highlightPart(wp1, true)
	DialogService.send(player, "Warning", "PASO 1: Active la alerta institucional en el punto senalado.")
	task.wait(1)
	DialogService.send(player, "Info", "Presione el boton de panico o sistema de alertas de emergencia.")

	NavigationUtils.setupWaypointDetection(player, wp1, 1, function()
		recordStep()
		NavigationUtils.highlightPart(wp1, false)
		DialogService.send(player, "Success", "Alerta activada. Personal y autoridades han sido notificados.")
		task.wait(2)

		NavigationUtils.highlightRefuges(refuges, true)
		DialogService.send(player, "Warning", "PASO 2: CONFINAMIENTO — Ubiquese en el espacio seguro senalado.")
		task.wait(1)
		DialogService.send(player, "Info", "Cierre con llave. Apague las luces. Silencio absoluto.")

		NavigationUtils.setupRefugeDetection(player, refuges, function()
			recordStep()
			NavigationUtils.highlightRefuges(refuges, false)
			DialogService.send(player, "Success", "Posicion de confinamiento establecida.")
			task.wait(2)
			DialogService.send(player, "Info", "Alejese de puertas y ventanas. No salga hasta recibir autorizacion.")
			task.wait(8)

			local wp3 = NavigationUtils.getWaypoint(locationName, "ArmedGroupsSimulation", 3)
			if not wp3 then
				warn("[SimController] Grupos armados: Waypoint3 no encontrado.")
				services.setPowerMode("NORMAL")
				services.setSimulationActive("ArmedGroups", locationName, false)
				services.controllerHUDEvent:FireClient(player, "Hide")
				state.playerSimulationData[player.UserId] = nil
				return
			end

			NavigationUtils.highlightPart(wp3, true)
			DialogService.send(player, "Info", "PASO 3: Las autoridades han llegado. Dirijase al punto de verificacion.")
			task.wait(1)
			DialogService.send(player, "Info", "Mantengase con las manos visibles. Identifiquese si se lo solicitan.")

			NavigationUtils.setupWaypointDetection(player, wp3, 3, function()
				recordStep()
				NavigationUtils.highlightPart(wp3, false)
				DialogService.send(player, "Success", "Identidad verificada por el personal autorizado.")
				task.wait(2)

				local wp4 = NavigationUtils.getWaypoint(locationName, "ArmedGroupsSimulation", 4)
				if not wp4 then
					warn("[SimController] Grupos armados: Waypoint4 no encontrado.")
					services.setPowerMode("NORMAL")
					services.setSimulationActive("ArmedGroups", locationName, false)
					services.controllerHUDEvent:FireClient(player, "Hide")
					state.playerSimulationData[player.UserId] = nil
					return
				end

				NavigationUtils.highlightPart(wp4, true)
				DialogService.send(player, "Warning", "PASO 4: Evacuese de forma ordenada al punto de reunion externo.")
				task.wait(1)
				DialogService.send(player, "Info", "Siga las instrucciones del personal de seguridad.")

				NavigationUtils.setupWaypointDetection(player, wp4, 4, function()
					recordStep()
					NavigationUtils.highlightPart(wp4, false)
					DialogService.send(player, "Success", "Punto de reunion alcanzado. La amenaza ha sido neutralizada.")
					task.wait(2)

					for _, npc in pairs(spawnedNPCs) do
						if npc and npc.Parent then npc:Destroy() end
					end
					services.setPowerMode("NORMAL")
					services.controllerHUDEvent:FireClient(player, "Hide")
					ScoringSystem.showFinalResults(player, session, "Grupos Armados")
					state.playerSimulationData[player.UserId] = nil
				end)
			end)
		end)
	end)
end

return ArmedGroupsSimulation
