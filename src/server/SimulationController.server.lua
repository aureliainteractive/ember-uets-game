--[[
    SimulationController — ServerScriptService
    Versión: 2.2

    Controlador central de simulacros de emergencia. Gestiona el flujo completo
    de cada tipo de simulación: incendio, sismo y grupos armados. También maneja
    la detección de waypoints, refugios, efectos visuales procedurales (fuego,
    física) y el sistema de calificación al finalizar.

    Tipos de simulación disponibles:
        - FireSimulation       : Propagación de incendio, evacuación por fases.
        - EarthquakeSimulation : Caída de objetos, refugio, evacuación y réplicas.
        - ArmedGroupsSimulation: Protocolo Código Rojo, confinamiento y verificación.
        - ExploreSimulation    : Modo libre para reconocer la ubicación.

    Requisitos en workspace / ReplicatedStorage:
        ReplicatedStorage:
            SimulationStartBindable, HighlightPartBindable, FinishedTaskBindable,
            PhysicalActuatorBindable, ShowDialog (RemoteEvent), HighlightTemplate,
            Atacant NPC
        workspace:
            AtacantsSpawns/<ubicación>/<BaseParts de spawn>
            FireWaypoints/Firefighters/<NPCs con HumanoidRootPart>
            Spawnpoints/<ubicación>/<tipo>/<BaseParts>
            Spawnpoints/MainLobby
            Waypoints/<ubicación>/<tipo>/Waypoint1..N
            Refugees/<ubicación>/<tipo>/Refuge1..N
            Intercom/AudioPlayer
            <nombre de edificio como hijo directo de workspace>

    Tipos de diálogo usados (icono → uso):
        "Info"    : Instrucciones informativas o estado del ejercicio.
        "Warning" : Alerta activa que requiere acción inmediata del jugador.
        "Success" : Confirmación de paso completado correctamente.
        "Error"   : Fallo de sistema o simulación finalizada por penalización.
        "Result"  : Encabezados y datos del resumen final de calificación.
                    >> Necesita un icono de "tablero/estadísticas" en el cliente.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local Lighting          = game:GetService("Lighting")

-- Eventos de comunicación
local simulationStartBindable  = ReplicatedStorage:WaitForChild("SimulationStartBindable")
local highlightPartBindable    = ReplicatedStorage:WaitForChild("HighlightPartBindable")
local finishedTaskBindable     = ReplicatedStorage:WaitForChild("FinishedTaskBindable")
local physicalActuatorBindable = ReplicatedStorage:WaitForChild("PhysicalActuatorBindable")
local showDialogEvent          = ReplicatedStorage:WaitForChild("ShowDialog")
local controllerHUDEvent 	   = ReplicatedStorage:WaitForChild("ControllerUI_HUD")

-- Referencias de ReplicatedStorage
local atacantNPC        = ReplicatedStorage:WaitForChild("Atacant NPC")
local highlightTemplate = ReplicatedStorage:WaitForChild("HighlightTemplate")

-- Carpetas de workspace
local AtacantsSpawns  = workspace:WaitForChild("AtacantsSpawns")
local spawnpointsFolder = workspace:WaitForChild("Spawnpoints")
local waypointsFolder   = workspace:WaitForChild("Waypoints")
local refugeesFolder    = workspace:WaitForChild("Refugees")
local mainLobbySpawn    = spawnpointsFolder:WaitForChild("MainLobby")

-- Audio
local audioPlayer = workspace.Intercom.AudioPlayer
local FIRE_ALARM_SOUND_ID      = "18682406265"
local EARTHQUAKE_ALARM_SOUND_ID = "138221067"

-- API externa (actuadores físicos)
local API_URL = "https://myurlhere.com/api"
local API_KEY = "REPLACE_WITH_KEY"

-- Estado global de simulaciones
local activeSimulations    = {}  -- clave: "Tipo_Ubicacion" → true
local playerSimulationData = {}  -- clave: userId → tabla con datos de la simulación activa

-- =============================================================================
-- CONFIGURACION GLOBAL
-- =============================================================================

local RNG = Random.new()

-- Piezas ignoradas al escanear edificios
local IGNORED_PART_NAMES = {
	["Baseplate"] = true,
	["Terrain"]   = true,
}

-- Volumen mínimo para participar en efectos
local MIN_VOLUME_FIRE  = 0.05
local MIN_VOLUME_QUAKE = 0.15

-- Cada cuántos objetos ceder el hilo al escanear un edificio (evita freeze)
local SCAN_YIELD_EVERY = 2000

-- Parámetros visuales de incendio
local SMOKE_COLOR = Color3.fromRGB(117, 117, 117)

-- Identificadores de objetos en el edificio para el sismo
local PILLAR_COLOR     = Color3.fromRGB(181, 125, 93)
local STUCCO_TILE_SIZE = Vector3.new(3.288, 0.038, 3.288)
local TV_SIZE          = Vector3.new(10.17, 5.751, 0.052)
local SIZE_EPSILON     = 0.02  -- tolerancia para comparar tamaños float

-- Tiempo máximo global de cualquier simulación antes del timeout de seguridad
local SIMULATION_GLOBAL_TIMEOUT = 300  -- segundos

-- =============================================================================
-- UTILIDADES GENERALES
-- =============================================================================

local function approx(a, b, eps)
	return math.abs(a - b) <= (eps or 0.01)
end

local function approxVec3(v, target, eps)
	return approx(v.X, target.X, eps)
		and approx(v.Y, target.Y, eps)
		and approx(v.Z, target.Z, eps)
end

local function getVolume(part)
	local s = part.Size
	return s.X * s.Y * s.Z
end

local function startExploreMusic()
	if not audioPlayer then return end

	audioPlayer:Stop()
	audioPlayer.SoundId = "rbxassetid://106924095504453"
	audioPlayer.Looped = true
	audioPlayer.Volume = 0.6
	audioPlayer:Play()
end

local function stopIntercom()
	if audioPlayer then
		audioPlayer:Stop()
		audioPlayer.TimePosition = 0
	end
end

-- Devuelve true si la pieza es candidata válida para efectos de simulación
local function isValidPart(obj)
	if not obj or not obj:IsA("BasePart") then return false end
	if not obj.Parent then return false end
	if obj.Transparency >= 1 then return false end
	if IGNORED_PART_NAMES[obj.Name] then return false end
	if obj.Locked then return false end
	return true
end

-- Cambia el modo de iluminación global definido como atributo en Lighting
local function setPowerMode(mode)
	if Lighting:GetAttribute("PowerMode") ~= nil then
		Lighting:SetAttribute("PowerMode", mode)
		print(string.format("[SimController] PowerMode -> %s", mode))
	else
		warn("[SimController] El atributo 'PowerMode' no existe en Lighting.")
	end
end

-- Envía un mensaje de diálogo al cliente del jugador de forma segura
local function dialog(player, icon, text)
	if player and player:IsA("Player") and player.Parent then
		pcall(function()
			showDialogEvent:FireClient(player, icon, text)
		end)
	end
end

-- Reproduce un sonido desde el inicio en el AudioPlayer del intercom
local function playIntercomSound(soundId)
	if not audioPlayer then return end

	audioPlayer:Stop()
	audioPlayer.SoundId = "rbxassetid://" .. soundId
	audioPlayer.TimePosition = 0
	audioPlayer:Play()
end

-- Verifica si hay una simulación activa del tipo y ubicación dados
local function canStartSimulation(simType, locationName)
	return not activeSimulations[simType .. "_" .. locationName]
end

local function setSimulationActive(simType, locationName, active)
	activeSimulations[simType .. "_" .. locationName] = active or nil
end

-- =============================================================================
-- UTILIDADES DE WAYPOINTS, REFUGIOS Y HIGHLIGHTS
-- =============================================================================

-- Obtiene un waypoint numerado de la carpeta Waypoints/<ubicación>/<tipo>/
local function getWaypoint(locationName, simType, number)
	local locationFolder = waypointsFolder:FindFirstChild(locationName)
	if not locationFolder then
		warn(string.format("[SimController] Waypoints: ubicacion '%s' no encontrada.", locationName))
		return nil
	end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then
		warn(string.format("[SimController] Waypoints: tipo '%s' no encontrado en '%s'.", simType, locationName))
		return nil
	end
	local wp = simFolder:FindFirstChild("Waypoint" .. number)
	if not wp or not wp:IsA("BasePart") then
		warn(string.format("[SimController] Waypoints: Waypoint%d no encontrado.", number))
		return nil
	end
	return wp
end

-- Obtiene todos los refugios de la carpeta Refugees/<ubicación>/<tipo>/
local function getRefuges(locationName, simType)
	local locationFolder = refugeesFolder:FindFirstChild(locationName)
	if not locationFolder then
		warn(string.format("[SimController] Refugees: ubicacion '%s' no encontrada.", locationName))
		return {}
	end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then
		warn(string.format("[SimController] Refugees: tipo '%s' no encontrado en '%s'.", simType, locationName))
		return {}
	end
	local refuges = {}
	for _, v in pairs(simFolder:GetChildren()) do
		if v:IsA("BasePart") and v.Name:match("Refuge%d+") then
			table.insert(refuges, v)
		end
	end
	return refuges
end

-- Activa o desactiva el highlight visual sobre una BasePart
local function highlightPart(part, enable)
	if not part or not part:IsA("BasePart") then return end
	if enable then
		if not part:FindFirstChild(highlightTemplate.Name) then
			local clone = highlightTemplate:Clone()
			clone.Parent = part
		end
		part.Transparency = 0
	else
		local existing = part:FindFirstChild(highlightTemplate.Name)
		part.Transparency = 1
		if existing then existing:Destroy() end
	end
end

-- Aplica o quita highlight en una lista de refugios
local function highlightRefuges(refuges, enable)
	for _, refuge in pairs(refuges) do
		highlightPart(refuge, enable)
	end
end

-- =============================================================================
-- UTILIDADES DE TELEPORTE
-- =============================================================================

-- Teleporta al jugador a una BasePart destino (con offset vertical para evitar colisión)
local function teleportPlayer(player, targetPart)
	if not player or not player.Character then return false end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if hrp and targetPart then
		hrp.CFrame = targetPart.CFrame + Vector3.new(0, 3, 0)
		return true
	end
	return false
end

-- Teleporta al jugador a un spawn aleatorio del tipo de simulación en la ubicación dada
local function teleportToSpawn(player, simType, locationName)
	local locationFolder = spawnpointsFolder:FindFirstChild(locationName)
	if not locationFolder then
		warn(string.format("[SimController] Spawnpoints: ubicacion '%s' no encontrada.", locationName))
		return false
	end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then
		warn(string.format("[SimController] Spawnpoints: tipo '%s' no encontrado en '%s'.", simType, locationName))
		return false
	end
	local points = {}
	for _, v in pairs(simFolder:GetChildren()) do
		if v:IsA("BasePart") then table.insert(points, v) end
	end
	if #points == 0 then
		warn(string.format("[SimController] Spawnpoints: sin puntos en '%s/%s'.", locationName, simType))
		return false
	end
	return teleportPlayer(player, points[math.random(1, #points)])
end

-- Teleporta al jugador al spawn más cercano al origen indicado.
-- Si originPart no es válido, usa un spawn aleatorio como respaldo.
local function teleportToClosestSpawn(player, simType, locationName, originPart)
	if not originPart or not originPart:IsA("BasePart") then
		warn("[SimController] Spawn más cercano: origin inválido. Usando spawn aleatorio.")
		return teleportToSpawn(player, simType, locationName)
	end
	local locationFolder = spawnpointsFolder:FindFirstChild(locationName)
	if not locationFolder then return false end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then return false end

	local points = {}
	for _, v in pairs(simFolder:GetChildren()) do
		if v:IsA("BasePart") then table.insert(points, v) end
	end
	if #points == 0 then return false end

	local closest = points[1]
	local closestDist = (closest.Position - originPart.Position).Magnitude
	for i = 2, #points do
		local d = (points[i].Position - originPart.Position).Magnitude
		if d < closestDist then
			closestDist = d
			closest = points[i]
		end
	end

	print(string.format("[SimController] Spawn seleccionado a %.1f studs del origen del fuego.", closestDist))
	return teleportPlayer(player, closest)
end

-- =============================================================================
-- SISTEMA DE DETECCION DE WAYPOINTS Y REFUGIOS
-- =============================================================================

-- Conecta el evento Touched de un waypoint y llama a onTouch cuando el jugador lo pisa.
-- Desconecta automáticamente al primer toque válido.
local function setupWaypointDetection(player, waypoint, waypointNumber, onTouch)
	if not waypoint then return end
	local connection
	connection = waypoint.Touched:Connect(function(hit)
		if hit.Parent == player.Character then
			local humanoid = hit.Parent:FindFirstChild("Humanoid")
			if humanoid then
				connection:Disconnect()
				if onTouch then onTouch(waypointNumber) end
			end
		end
	end)
	return connection
end

-- Conecta el evento Touched en todos los refugios. Al pisar cualquiera de ellos,
-- desconecta todos y llama a onRefugeReached con el refugio tocado.
local function setupRefugeDetection(player, refuges, onRefugeReached)
	if not refuges or #refuges == 0 then return {} end
	local connections = {}
	local reached = false
	for _, refuge in pairs(refuges) do
		local conn
		conn = refuge.Touched:Connect(function(hit)
			if not reached and hit.Parent == player.Character then
				local humanoid = hit.Parent:FindFirstChild("Humanoid")
				if humanoid then
					reached = true
					for _, c in pairs(connections) do c:Disconnect() end
					if onRefugeReached then onRefugeReached(refuge) end
				end
			end
		end)
		table.insert(connections, conn)
	end
	return connections
end

-- =============================================================================
-- SISTEMA DE CALIFICACION Y RESULTADOS
-- =============================================================================

--[[
    Calcula el puntaje promedio basado en los tiempos de cada paso contra sus tiempos máximos:
        <= 70% del máximo  : 100 puntos (excelente)
        <= 100% del máximo : 85 puntos  (bueno)
        <= 130% del máximo : 70 puntos  (regular)
        > 130% del máximo  : 50 puntos  (insuficiente)
--]]
local function calculateScore(times, maxTimes)
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

-- Muestra el resumen de resultados al jugador y lo regresa al lobby
local function showFinalResults(player, simData, simType)
	if not simData.waypointTimes or #simData.waypointTimes == 0 then
		warn(string.format("[SimController] Sin tiempos registrados para mostrar resultados (%s).", player.Name))
		teleportPlayer(player, mainLobbySpawn)
		return
	end

	local score = calculateScore(simData.waypointTimes, simData.maxTimes)

	local grade
	if score >= 90 then
		grade = "EXCELENTE"
	elseif score >= 75 then
		grade = "BUENO"
	elseif score >= 60 then
		grade = "REGULAR"
	else
		grade = "NECESITA MEJORAR"
	end

	task.wait(2)
	dialog(player, "Result", "RESULTADOS DEL SIMULACRO — " .. simType)
	task.wait(1)
	dialog(player, "Result", string.format("Calificacion: %s  |  Puntaje: %d/100", grade, score))
	task.wait(1)

	local totalElapsed = 0
	for i, t in ipairs(simData.waypointTimes) do
		totalElapsed += t
		local stepName = (simData.stepNames and simData.stepNames[i]) or ("Paso " .. i)
		local status = (t <= simData.maxTimes[i]) and "Completado" or "Excedido"
		dialog(player, "Result", string.format("%s: %.1fs — %s", stepName, t, status))
		task.wait(0.5)
	end

	task.wait(1)
	dialog(player, "Result", string.format("Tiempo total: %.1fs", totalElapsed))
	task.wait(3)

	teleportPlayer(player, mainLobbySpawn)
	dialog(player, "Info", "Ha regresado al lobby principal.")
end

-- =============================================================================
-- CONTROL DE BOMBEROS (FireWaypoints/Firefighters)
-- Los NPCs de bomberos permanecen ocultos bajo el mapa cuando no hay simulación
-- de incendio activa, y se restauran a su posición original al iniciarla.
-- =============================================================================

local FIREFIGHTERS_FOLDER = workspace:WaitForChild("FireWaypoints"):WaitForChild("Firefighters")
local FIREFIGHTER_HIDDEN_OFFSET = Vector3.new(0, -100, 0)

local firefightersData      = {}
local firefightersInitialized = false

local function initializeFirefighters()
	if firefightersInitialized then return end
	for _, d in ipairs(FIREFIGHTERS_FOLDER:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "HumanoidRootPart" then
			firefightersData[d] = {
				OriginalCFrame   = d.CFrame,
				OriginalAnchored = d.Anchored,
			}
		end
	end
	firefightersInitialized = true
end

local function hideFirefighters()
	initializeFirefighters()
	for hrp, data in pairs(firefightersData) do
		if hrp and hrp.Parent then
			hrp.Anchored = true
			hrp.CFrame = data.OriginalCFrame + FIREFIGHTER_HIDDEN_OFFSET
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function showFirefighters()
	initializeFirefighters()
	for hrp, data in pairs(firefightersData) do
		if hrp and hrp.Parent then
			hrp.CFrame = data.OriginalCFrame
			hrp.Anchored = data.OriginalAnchored
		end
	end
end

-- Ocultar bomberos al iniciar el servidor
hideFirefighters()

-- =============================================================================
-- SISTEMA DE INCENDIO PROCEDURAL
-- =============================================================================

local function getBuildingModel(locationName)
	local building = workspace:FindFirstChild(locationName)
	if not building then
		warn(string.format("[SimController] Edificio '%s' no encontrado en workspace.", locationName))
	end
	return building
end

-- Recolecta todas las BaseParts válidas del edificio que puedan participar en el fuego
local function collectBuildingParts(building)
	local parts = {}
	local count = 0
	for _, obj in ipairs(building:GetDescendants()) do
		count += 1
		if count % SCAN_YIELD_EVERY == 0 then task.wait() end
		if isValidPart(obj) and getVolume(obj) >= MIN_VOLUME_FIRE then
			table.insert(parts, obj)
		end
	end
	return parts
end

local function fireSize(part, difficulty)
	local avg = (part.Size.X + part.Size.Y + part.Size.Z) / 3
	local mult = (difficulty == 1 and 2.85) or (difficulty == 2 and 3.05) or 5.25
	return math.clamp(avg * mult, 2, 30)
end

local function fireHeat(difficulty)
	return (difficulty == 1 and 20) or (difficulty == 2 and 30) or 40
end

local function smokeParams(part, difficulty)
	local avg = (part.Size.X + part.Size.Y + part.Size.Z) / 3
	local sizeMult = (difficulty == 1 and 1.0) or (difficulty == 2 and 1.2) or 1.4
	local rise     = (difficulty == 1 and 8)   or (difficulty == 2 and 6)   or 4
	return math.clamp(avg * sizeMult, 3, 25), rise
end

-- Agrega o actualiza Fire y Smoke en una pieza
local function ignite(part, difficulty)
	if not part or not part.Parent then return end

	local fire = part:FindFirstChildOfClass("Fire") or Instance.new("Fire")
	fire.Name    = "DynamicFire"
	fire.Enabled = true
	fire.Heat    = fireHeat(difficulty)
	fire.Size    = fireSize(part, difficulty)
	fire.Parent  = part

	local smoke = part:FindFirstChildOfClass("Smoke") or Instance.new("Smoke")
	smoke.Name          = "DynamicSmoke"
	smoke.Enabled       = true
	smoke.Color         = SMOKE_COLOR
	smoke.Size, smoke.RiseVelocity = smokeParams(part, difficulty)
	smoke.Parent = part
end

-- Elimina los efectos de fuego y humo de una pieza
local function extinguish(part)
	if not part or not part.Parent then return end
	local fire = part:FindFirstChild("DynamicFire")
	if fire then fire.Enabled = false; fire:Destroy() end
	local smoke = part:FindFirstChild("DynamicSmoke")
	if smoke then smoke.Enabled = false; smoke:Destroy() end
end

-- Selecciona la pieza de mayor volumen entre 80 intentos aleatorios como origen del fuego
local function pickFireOrigin(parts)
	local best, bestVol = nil, -math.huge
	for _ = 1, 80 do
		local p = parts[RNG:NextInteger(1, #parts)]
		if p and p.Parent then
			local v = getVolume(p)
			if v > bestVol then bestVol = v; best = p end
		end
	end
	return best or parts[RNG:NextInteger(1, #parts)]
end

--[[
    Propaga el fuego de forma procedural desde seedPart durante durationSeconds.
    En cada oleada selecciona un frente activo y prende piezas cercanas dentro
    del radio de propagación. Limita el total de piezas ardiendo para preservar
    rendimiento. Devuelve la lista de piezas afectadas para poder apagarlas luego.
--]]
local function spreadFire(parts, difficulty, durationSeconds, seedPart)
	if #parts == 0 then return {} end

	local burnedSet  = {}  -- hash para evitar duplicados
	local burningList = {} -- lista ordenada del frente activo

	local spreadRadius  = (difficulty == 1 and 18)  or (difficulty == 2 and 26)  or 35
	local maxPerWave    = (difficulty == 1 and 6)   or (difficulty == 2 and 10)  or 14
	local waveInterval  = (difficulty == 1 and 4.0) or (difficulty == 2 and 3.0) or 2.0
	local maxTotal      = (difficulty == 1 and 100) or (difficulty == 2 and 150) or 200

	local endTime = tick() + durationSeconds
	local seed = seedPart or pickFireOrigin(parts)

	if seed then
		ignite(seed, difficulty)
		burnedSet[seed] = true
		table.insert(burningList, seed)
	end

	local function findCandidates(origin, limit)
		local candidates = {}
		if not origin or not origin.Parent then return candidates end
		local samples = math.min(500, #parts)
		for _ = 1, samples do
			local p = parts[RNG:NextInteger(1, #parts)]
			if p and p.Parent and not burnedSet[p] then
				if (p.Position - origin.Position).Magnitude <= spreadRadius
					and getVolume(p) >= MIN_VOLUME_FIRE then
					table.insert(candidates, p)
					if #candidates >= limit then break end
				end
			end
		end
		return candidates
	end

	while tick() < endTime do
		task.wait(waveInterval)
		if #burningList == 0 then break end

		local front = burningList[RNG:NextInteger(1, #burningList)]
		if not front or not front.Parent then
			-- Limpiar entradas obsoletas
			for i = #burningList, 1, -1 do
				if not burningList[i] or not burningList[i].Parent then
					table.remove(burningList, i)
				end
			end
			continue
		end

		for _, p in ipairs(findCandidates(front, maxPerWave)) do
			if p and p.Parent and not burnedSet[p] then
				ignite(p, difficulty)
				burnedSet[p] = true
				table.insert(burningList, p)
			end
		end

		-- Apagar piezas antiguas si se supera el límite total
		if #burningList > maxTotal then
			local excess = #burningList - maxTotal
			for _ = 1, excess do
				local old = table.remove(burningList, 1)
				if old and old.Parent then extinguish(old) end
			end
		end
	end

	local affected = {}
	for p in pairs(burnedSet) do table.insert(affected, p) end
	return affected
end

-- =============================================================================
-- SISTEMA DE SISMO PROCEDURAL
-- =============================================================================

--[[
    Recolecta los objetos del edificio que participarán en el efecto sísmico:
        - tiles      : Baldosas de estuco (UnionOperation de tamaño exacto)
        - tvs        : Televisores (BasePart de tamaño exacto)
        - pillars    : Pilares identificados por color
        - lightModels: Modelos de luminarias de techo (por nombre de patrón)
--]]
local function collectEarthquakeCandidates(building)
	local tiles, tvs, pillars, lightModels = {}, {}, {}, {}
	local count = 0
	for _, obj in ipairs(building:GetDescendants()) do
		count += 1
		if count % SCAN_YIELD_EVERY == 0 then task.wait() end

		if obj:IsA("Model")
			and (obj.Name:match("^Ceiling Light%d+$") or obj.Name:match("^Roof with Light%d+$")) then
			table.insert(lightModels, obj)
		end

		if isValidPart(obj) and getVolume(obj) >= MIN_VOLUME_QUAKE then
			if obj:IsA("UnionOperation") and approxVec3(obj.Size, STUCCO_TILE_SIZE, SIZE_EPSILON) then
				table.insert(tiles, obj)
			elseif approxVec3(obj.Size, TV_SIZE, SIZE_EPSILON) then
				table.insert(tvs, obj)
			elseif obj.Color == PILLAR_COLOR then
				table.insert(pillars, obj)
			end
		end
	end
	return { tiles = tiles, tvs = tvs, pillars = pillars, lightModels = lightModels }
end

-- Obtiene la BasePart más grande de un Model (PrimaryPart si existe, sino la de mayor volumen)
local function getRepresentativePart(model)
	if not model or not model:IsA("Model") then return nil end
	if model.PrimaryPart then return model.PrimaryPart end
	local best, bestVol = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = getVolume(d)
			if v > bestVol then bestVol = v; best = d end
		end
	end
	return best
end

-- Desancla una pieza y le aplica un impulso aleatorio hacia arriba.
-- Devuelve el estado original para poder restaurarlo luego.
local function unanchorAndKick(part, difficulty)
	if not part or not part.Parent then return nil end
	if not part:IsA("BasePart") or not part.Anchored then return nil end

	local state = { part = part, Anchored = true, CFrame = part.CFrame }
	part.Anchored = false

	local strength = (difficulty == 1 and 40) or (difficulty == 2 and 75) or 120
	pcall(function()
		part:ApplyImpulse(
			Vector3.new(
				RNG:NextNumber(-1, 1),
				RNG:NextNumber(0.5, 1),
				RNG:NextNumber(-1, 1)
			).Unit * strength * part.AssemblyMass
		)
	end)

	return state
end

-- Aplica el efecto de derrumbe parcial del edificio según dificultad.
-- Devuelve la lista de estados originales para restaurar al finalizar.
local function applyEarthquakeDrops(building, difficulty)
	local c = collectEarthquakeCandidates(building)

	local tilesToDrop   = (difficulty == 1 and 320) or (difficulty == 2 and 420) or 560
	local tvsToDrop     = (difficulty == 1 and 10)  or (difficulty == 2 and 18)  or 28
	local pillarsToDrop = (difficulty == 1 and 12)  or (difficulty == 2 and 22)  or 35
	local lightsToDrop  = (difficulty == 1 and 58)  or (difficulty == 2 and 80)  or 105

	local originals = {}

	-- Mezcla aleatoria Fisher-Yates para seleccionar sin repetir
	local function pickRandom(list, amount)
		local picked = {}
		if #list == 0 then return picked end
		amount = math.min(amount, #list)
		local idx = {}
		for i = 1, #list do idx[i] = i end
		for i = #idx, 2, -1 do
			local j = RNG:NextInteger(1, i)
			idx[i], idx[j] = idx[j], idx[i]
		end
		for i = 1, amount do table.insert(picked, list[idx[i]]) end
		return picked
	end

	local function kick(list, amount)
		for _, obj in ipairs(pickRandom(list, amount)) do
			local state = unanchorAndKick(obj, difficulty)
			if state then table.insert(originals, state) end
		end
	end

	kick(c.tiles, tilesToDrop)
	kick(c.tvs, tvsToDrop)
	kick(c.pillars, pillarsToDrop)

	for _, m in ipairs(pickRandom(c.lightModels, lightsToDrop)) do
		local p = getRepresentativePart(m)
		if p then
			local state = unanchorAndKick(p, difficulty)
			if state then table.insert(originals, state) end
		end
	end

	return originals
end

-- Restaura todas las piezas a su posición y estado anclado originales
local function restoreEarthquakeDrops(originalStates)
	for _, state in ipairs(originalStates) do
		local p = state.part
		if p and p.Parent then
			p.CFrame = state.CFrame
			p.Anchored = state.Anchored
			p.AssemblyLinearVelocity = Vector3.zero
			p.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- =============================================================================
-- EVENTOS BINDABLE (FinishedTask, HighlightPart, PhysicalActuator)
-- =============================================================================

finishedTaskBindable.Event:Connect(function(player, taskName, callback)
	if not player or not player.Parent then
		if callback then callback(false, "Jugador invalido") end
		return
	end
	local tasks = (player:GetAttribute("TasksCompleted") or 0) + 1
	player:SetAttribute("TasksCompleted", tasks)
	if callback then callback(true, tasks) end
end)

highlightPartBindable.Event:Connect(function(player, part, enable, callback)
	if not player or not player.Parent then
		if callback then callback(false, "Jugador invalido") end
		return
	end
	if not part or not part:IsA("BasePart") or not part.Parent then
		if callback then callback(false, "Parte invalida") end
		return
	end

	if enable then
		if part:FindFirstChild(highlightTemplate.Name) then
			if callback then callback(true) end
			return
		end
		highlightTemplate:Clone().Parent = part
		if callback then callback(true) end
	else
		local existing = part:FindFirstChild(highlightTemplate.Name)
		if existing then
			existing:Destroy()
			if callback then callback(true) end
		else
			if callback then callback(false) end
		end
	end
end)

physicalActuatorBindable.Event:Connect(function(player, actuatorName, value, duration, callback)
	if not player or not player.Parent then
		if callback then callback(false, "Jugador invalido") end
		return
	end
	if not actuatorName or value == nil then
		if callback then callback(false, "Parametros invalidos") end
		return
	end

	local payload = {
		actuator  = actuatorName,
		value     = tostring(value),
		duration  = tonumber(duration) or 0,
		player    = player.UserId,
		timestamp = os.time(),
	}

	local ok, result = pcall(function()
		return HttpService:PostAsync(
			API_URL .. "/actuator",
			HttpService:JSONEncode(payload),
			Enum.HttpContentType.ApplicationJson,
			false,
			{ ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. API_KEY }
		)
	end)

	if not ok then
		warn(string.format("[SimController] Error al contactar actuador '%s': %s", actuatorName, tostring(result)))
		if callback then callback(false, "Error de conexion con el actuador") end
		return
	end

	if callback then callback(true, result) end
end)

-- =============================================================================
-- SIMULACRO: EXPLORACIÓN (modo libre para reconocimiento del espacio)
-- =============================================================================

local function startExploreSimulation(player, locationName, _difficulty)
	setSimulationActive("Explore", locationName, true)
	teleportToSpawn(player, "FireSimulation", locationName)
	controllerHUDEvent:FireClient(player, "Show")
	print(string.format("[SimController] Exploración iniciada: %s — %s", player.Name, locationName))
end

-- =============================================================================
-- SIMULACRO: INCENDIO
--[[
    Protocolo de 4 pasos:
        1. Localizar el origen del fuego (por proximidad).
        2. Activar la alarma de incendio (waypoint 2).
        3. Evacuar el edificio (waypoint 3).
        4. Llegar al punto de encuentro (waypoint 4).

    Características:
        - El origen del fuego se elige proceduralmente y se señala visualmente.
        - El jugador aparece en el spawn más cercano al origen.
        - El fuego se propaga de forma autónoma mientras dura el ejercicio.
        - Los bomberos se muestran al activar la simulación y se ocultan al terminar.
        - Un timeout global de 5 minutos finaliza el ejercicio si no se completa.
--]]
-- =============================================================================

local function startFireSimulation(player, locationName, difficulty)
	local params = {
		[1] = { duration = 55, heaterDelay = 35 },
		[2] = { duration = 70, heaterDelay = 25 },
		[3] = { duration = 90, heaterDelay = 18 },
	}
	local p = params[math.clamp(difficulty, 1, 3)]

	local building = getBuildingModel(locationName)
	if not building then
		dialog(player, "Error", "No se pudo cargar la ubicacion del ejercicio.")
		return
	end
	if not canStartSimulation("Fire", locationName) then
		dialog(player, "Error", "Ya hay un simulacro de incendio activo en esta ubicacion.")
		return
	end

	setSimulationActive("Fire", locationName, true)
	setPowerMode("BLACKOUT")
	controllerHUDEvent:FireClient(player, "Show")

	local buildingParts = collectBuildingParts(building)
	local seedPart = pickFireOrigin(buildingParts)

	if not seedPart then
		warn(string.format("[SimController] Incendio: no se pudo determinar origen en '%s'.", locationName))
		setSimulationActive("Fire", locationName, false)
		setPowerMode("NORMAL")
		dialog(player, "Error", "No se pudo iniciar el simulacro. Intente nuevamente.")
		return
	end

	local teleported = teleportToClosestSpawn(player, "FireSimulation", locationName, seedPart)
	if not teleported then
		setSimulationActive("Fire", locationName, false)
		setPowerMode("NORMAL")
		dialog(player, "Error", "No se pudo ubicar al participante. Intente nuevamente.")
		return
	end

	playerSimulationData[player.UserId] = {
		startTime        = tick(),
		waypointTimes    = {},
		lastWaypointTime = tick(),
		maxTimes         = { 15, 10, 20, 15 },
		stepNames        = { "Deteccion", "Alarma", "Evacuacion", "Punto de encuentro" },
		connections      = {},
		seedPart         = seedPart,
		simulationEnded  = false,
	}

	local simData = playerSimulationData[player.UserId]
	print(string.format("[SimController] Incendio iniciado: %s — %s — Dificultad %d", player.Name, locationName, difficulty))

	local function recordStep()
		local now = tick()
		table.insert(simData.waypointTimes, now - simData.lastWaypointTime)
		simData.lastWaypointTime = now
	end

	local affectedParts = {}

	local function cleanup()
		if simData.simulationEnded then return end
		simData.simulationEnded = true
		for _, part in ipairs(affectedParts) do extinguish(part) end
		hideFirefighters()
		setSimulationActive("Fire", locationName, false)
		setPowerMode("NORMAL")
		playerSimulationData[player.UserId] = nil
	end

	-- Iniciar propagación del fuego en paralelo
	task.spawn(function()
		affectedParts = spreadFire(buildingParts, difficulty, p.duration, seedPart)
	end)

	task.wait(0.5)
	showFirefighters()

	-- Señalar el origen del fuego
	if seedPart and seedPart.Parent then
		highlightPart(seedPart, true)
	end

	dialog(player, "Warning", "SIMULACRO DE INCENDIO — Se ha reportado un foco de fuego en las instalaciones.")
	task.wait(2)
	dialog(player, "Warning", "El origen del fuego ha sido identificado y senalado. Localicelo.")

	-- PASO 1: Localizar el origen (por proximidad de 40 studs)
	dialog(player, "Info", "PASO 1: Acerquese al origen del fuego senalado para identificarlo.")

	local originDetected = false

	task.spawn(function()
		while not originDetected and not simData.simulationEnded do
			task.wait(0.5)
			if simData.simulationEnded then break end

			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and seedPart and seedPart.Parent then
					if (hrp.Position - seedPart.Position).Magnitude <= 40 then
						originDetected = true
						recordStep()
						highlightPart(seedPart, false)

						dialog(player, "Success", "Origen del fuego identificado correctamente.")
						task.wait(1)

						-- PASO 2: Activar alarma
						local wp2 = getWaypoint(locationName, "FireSimulation", 2)
						if not wp2 then
							warn("[SimController] Incendio: Waypoint2 no encontrado.")
							cleanup()
							return
						end

						highlightPart(wp2, true)
						dialog(player, "Warning", "PASO 2: Dirijase al punto senalado y active la alarma de incendio.")

						setupWaypointDetection(player, wp2, 2, function()
							recordStep()
							highlightPart(wp2, false)
							playIntercomSound(FIRE_ALARM_SOUND_ID)
							dialog(player, "Success", "Alarma de incendio activada. Personal notificado.")
							task.wait(1)

							-- PASO 3: Evacuación
							local wp3 = getWaypoint(locationName, "FireSimulation", 3)
							if not wp3 then
								warn("[SimController] Incendio: Waypoint3 no encontrado.")
								cleanup()
								return
							end

							highlightPart(wp3, true)
							dialog(player, "Warning", "PASO 3: Evacue el edificio de inmediato. Camine rapido, no corra.")
							task.wait(1)
							dialog(player, "Info", "Use las salidas de emergencia. Mantengase alejado del fuego.")

							setupWaypointDetection(player, wp3, 3, function()
								recordStep()
								highlightPart(wp3, false)
								dialog(player, "Success", "Salida de emergencia alcanzada.")
								task.wait(1)

								-- PASO 4: Punto de encuentro
								local wp4 = getWaypoint(locationName, "FireSimulation", 4)
								if not wp4 then
									warn("[SimController] Incendio: Waypoint4 no encontrado.")
									cleanup()
									return
								end

								highlightPart(wp4, true)
								dialog(player, "Warning", "PASO 4: Dirijase al punto de encuentro externo.")
								task.wait(1)
								dialog(player, "Info", "Permanezca ahi hasta nueva instruccion. No reingrese al edificio.")

								setupWaypointDetection(player, wp4, 4, function()
									recordStep()
									highlightPart(wp4, false)
									dialog(player, "Success", "Punto de encuentro alcanzado. Simulacro completado.")
									task.wait(2)
									cleanup()
									showFinalResults(player, simData, "Incendio")
								end)
							end)
						end)
					end
				end
			end
		end
	end)

	-- Activar calefactor físico después del delay configurado
	task.delay(p.heaterDelay, function()
		if playerSimulationData[player.UserId] then
			physicalActuatorBindable:Fire(player, locationName .. "_Heater", true, p.duration)
		end
	end)

	-- Timeout global de seguridad
	task.delay(SIMULATION_GLOBAL_TIMEOUT, function()
		if playerSimulationData[player.UserId] then
			warn(string.format("[SimController] Incendio: timeout de %ds alcanzado para %s.", SIMULATION_GLOBAL_TIMEOUT, player.Name))
			cleanup()
			dialog(player, "Warning", "El simulacro ha finalizado por tiempo limite.")
			teleportPlayer(player, mainLobbySpawn)
		end
	end)
	controllerHUDEvent:FireClient(player, "Hide")
end

-- =============================================================================
-- SIMULACRO: SISMO — RÉPLICAS
-- Genera N réplicas con vibración de cámara a intervalos regulares.
-- =============================================================================

local function triggerAftershocks(player, count, interval)
	task.spawn(function()
		for i = 1, count do
			task.wait(interval)
			local duration = math.random(2, 4)
			local scale    = math.random() * 1.5 + 1.0

			dialog(player, "Warning", string.format("Replique sismica #%d detectada. Mantengase en posicion.", i))

			pcall(function()
				local ev = ReplicatedStorage:FindFirstChild("CameraShakeEvent")
				if ev then ev:FireClient(player, duration, scale) end
			end)
		end
		dialog(player, "Info", "Las replicas han cesado. Permanezca en la zona segura.")
	end)
end

-- =============================================================================
-- SIMULACRO: SISMO
--[[
    Protocolo de 3 pasos:
        1. Refugiarse: agacharse, cubrirse y agarrarse en un punto de refugio.
        2. Evacuar el edificio al cesar el movimiento (waypoint 2).
        3. Llegar a la zona segura externa (waypoint 3).

    Características:
        - Se simula la caída de objetos del edificio (baldosas, TVs, pilares, luminarias).
        - La cámara del jugador vibra durante el sismo principal y en las réplicas.
        - Los objetos caídos se restauran al finalizar el ejercicio.
--]]
-- =============================================================================

local function startEarthquakeSimulation(player, locationName, difficulty)
	local params = {
		[1] = { duration = 10, shakeScale = 3.0, prepTime = 6 },
		[2] = { duration = 15, shakeScale = 5.0, prepTime = 5 },
		[3] = { duration = 20, shakeScale = 7.0, prepTime = 4 },
	}
	local p = params[math.clamp(difficulty, 1, 3)]

	local building = getBuildingModel(locationName)
	if not building then
		dialog(player, "Error", "No se pudo cargar la ubicacion del ejercicio.")
		return
	end
	if not canStartSimulation("Earthquake", locationName) then
		dialog(player, "Error", "Ya hay un simulacro de sismo activo en esta ubicacion.")
		return
	end
	
	controllerHUDEvent:FireClient(player, "Show")
	setSimulationActive("Earthquake", locationName, true)
	setPowerMode("BLACKOUT")
	teleportToSpawn(player, "EarthquakeSimulation", locationName)

	local refuges = getRefuges(locationName, "EarthquakeSimulation")

	playerSimulationData[player.UserId] = {
		waypointTimes    = {},
		lastWaypointTime = tick(),
		maxTimes         = { 12, 18, 15 },
		stepNames        = { "Refugiarse", "Evacuacion", "Zona segura" },
		connections      = {},
	}

	local simData = playerSimulationData[player.UserId]
	print(string.format("[SimController] Sismo iniciado: %s — %s — Dificultad %d", player.Name, locationName, difficulty))

	local function recordStep()
		local now = tick()
		table.insert(simData.waypointTimes, now - simData.lastWaypointTime)
		simData.lastWaypointTime = now
	end

	-- Fase de alerta previa al sismo
	dialog(player, "Warning", "ALERTA SISMICA — Se ha detectado actividad sismica en la zona.")
	task.wait(2)
	dialog(player, "Info", "Mantenga la calma. Prepare para seguir el protocolo de sismo.")
	task.wait(p.prepTime)

	-- Aplicar caída de objetos en paralelo
	local originalStates = {}
	task.spawn(function()
		originalStates = applyEarthquakeDrops(building, difficulty)
	end)

	playIntercomSound(EARTHQUAKE_ALARM_SOUND_ID)
	dialog(player, "Warning", "MOVIMIENTO SISMICO EN CURSO.")
	task.wait(1)

	pcall(function()
		local ev = ReplicatedStorage:FindFirstChild("CameraShakeEvent")
		if ev then ev:FireClient(player, p.duration, p.shakeScale) end
	end)

	-- PASO 1: Refugiarse
	highlightRefuges(refuges, true)
	dialog(player, "Warning", "PASO 1: AGACHESE, CUBRASE Y AGÁRRESE.")
	task.wait(1)
	dialog(player, "Info", "Ubiquese bajo un escritorio o estructura resistente. Proteja cabeza y cuello.")

	setupRefugeDetection(player, refuges, function()
		recordStep()
		highlightRefuges(refuges, false)
		dialog(player, "Success", "Posicion de proteccion adoptada correctamente.")
		task.wait(1)
		dialog(player, "Info", "Mantenga la posicion hasta que cese el movimiento.")

		task.wait(p.duration)

		dialog(player, "Info", "El movimiento principal ha cesado.")
		task.wait(1)
		triggerAftershocks(player, 2, 12)

		-- PASO 2: Evacuación
		task.wait(2)
		local wp2 = getWaypoint(locationName, "EarthquakeSimulation", 2)
		if not wp2 then
			warn("[SimController] Sismo: Waypoint2 no encontrado.")
			setSimulationActive("Earthquake", locationName, false)
			setPowerMode("NORMAL")
			playerSimulationData[player.UserId] = nil
			return
		end

		highlightPart(wp2, true)
		dialog(player, "Warning", "PASO 2: Evacue el edificio de forma ordenada.")
		task.wait(1)
		dialog(player, "Info", "Use escaleras. No use ascensores. Atienda replicas.")

		task.wait(3)
		triggerAftershocks(player, 3, 8)

		setupWaypointDetection(player, wp2, 2, function()
			recordStep()
			highlightPart(wp2, false)
			dialog(player, "Success", "Salida del edificio alcanzada.")
			task.wait(2)

			-- PASO 3: Zona segura
			local wp3 = getWaypoint(locationName, "EarthquakeSimulation", 3)
			if not wp3 then
				warn("[SimController] Sismo: Waypoint3 no encontrado.")
				setSimulationActive("Earthquake", locationName, false)
				setPowerMode("NORMAL")
				playerSimulationData[player.UserId] = nil
				return
			end

			highlightPart(wp3, true)
			dialog(player, "Warning", "PASO 3: Dirijase a la zona segura externa.")
			task.wait(1)
			dialog(player, "Info", "Alejese de edificios, postes y cables. Busque un area abierta.")

			setupWaypointDetection(player, wp3, 3, function()
				recordStep()
				highlightPart(wp3, false)
				dialog(player, "Success", "Zona segura alcanzada. Simulacro completado.")
				task.wait(1)
				dialog(player, "Info", "Permanezca en la zona hasta recibir nueva instruccion.")
				task.wait(3)

				restoreEarthquakeDrops(originalStates)
				setSimulationActive("Earthquake", locationName, false)
				setPowerMode("NORMAL")
				showFinalResults(player, simData, "Sismo")
				playerSimulationData[player.UserId] = nil
			end)
		end)
	end)
	controllerHUDEvent:FireClient(player, "Hide")
end

-- =============================================================================
-- SIMULACRO: GRUPOS ARMADOS
--[[
    Protocolo de 4 pasos (Código Rojo):
        1. Activar la alerta institucional (waypoint 1 — botón de pánico).
        2. Confinarse en un punto de refugio seguro.
        3. Dirigirse al punto de verificación cuando lleguen las autoridades (waypoint 3).
        4. Evacuar al punto de reunión externo (waypoint 4).

    Características:
        - NPCs antagonistas se spawnan en puntos aleatorios de la ubicación.
        - Si el jugador es eliminado, el ejercicio termina con penalización.
        - Los NPCs se destruyen al finalizar el ejercicio.
--]]
-- =============================================================================

local function endArmedGroupsByDeath(player, locationName, spawnedNPCs)
	if not player or not player.Parent then return end
	local simData = playerSimulationData[player.UserId]
	if not simData then return end

	dialog(player, "Error", "SIMULACRO FINALIZADO — El participante fue neutralizado.")
	task.wait(2)

	for _, npc in ipairs(spawnedNPCs or {}) do
		if npc and npc.Parent then npc:Destroy() end
	end

	playerSimulationData[player.UserId] = nil
	setPowerMode("NORMAL")
	setSimulationActive("ArmedGroups", locationName, false)

	task.wait(1)
	teleportPlayer(player, mainLobbySpawn)
	dialog(player, "Info", "Ha regresado al lobby principal.")
end

local function startArmedGroupsSimulation(player, locationName, difficulty)
	local npcCounts = { [1] = 2, [2] = 4, [3] = 6 }
	local prepTimes = { [1] = 7, [2] = 5, [3] = 4 }

	if not canStartSimulation("ArmedGroups", locationName) then
		dialog(player, "Error", "Ya hay un simulacro activo en esta ubicacion.")
		return
	end
	setSimulationActive("ArmedGroups", locationName, true)

	local npcCount = npcCounts[math.clamp(difficulty, 1, 3)]
	local prepTime = prepTimes[math.clamp(difficulty, 1, 3)]

	local spawnFolder = AtacantsSpawns:FindFirstChild(locationName)
	if not spawnFolder then
		dialog(player, "Error", "No se pudo cargar la ubicacion del ejercicio.")
		setSimulationActive("ArmedGroups", locationName, false)
		return
	end

	controllerHUDEvent:FireClient(player, "Show")
	teleportToSpawn(player, "ArmedGroupsSimulation", locationName)
	setPowerMode("BLACKOUT")

	local refuges = getRefuges(locationName, "ArmedGroupsSimulation")

	playerSimulationData[player.UserId] = {
		waypointTimes    = {},
		lastWaypointTime = tick(),
		maxTimes         = { 10, 20, 15, 18 },
		stepNames        = { "Alerta", "Confinamiento", "Verificacion", "Evacuacion" },
		connections      = {},
	}

	local simData = playerSimulationData[player.UserId]
	print(string.format("[SimController] Grupos armados iniciado: %s — %s — Dificultad %d", player.Name, locationName, difficulty))

	local function recordStep()
		local now = tick()
		table.insert(simData.waypointTimes, now - simData.lastWaypointTime)
		simData.lastWaypointTime = now
	end

	-- Recolectar puntos de spawn de NPCs
	local spawns = {}
	for _, v in pairs(spawnFolder:GetChildren()) do
		if v:IsA("BasePart") or v:IsA("Model") or v:IsA("Attachment") then
			table.insert(spawns, v)
		end
	end

	if #spawns == 0 then
		dialog(player, "Error", "No hay puntos de aparicion configurados para esta ubicacion.")
		setPowerMode("NORMAL")
		setSimulationActive("ArmedGroups", locationName, false)
		return
	end

	-- Mezcla aleatoria de puntos de spawn
	npcCount = math.min(npcCount, #spawns)
	for i = #spawns, 2, -1 do
		local j = RNG:NextInteger(1, i)
		spawns[i], spawns[j] = spawns[j], spawns[i]
	end

	local spawnedNPCs = {}

	-- Detectar muerte del jugador durante la simulación
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid  = character:WaitForChild("Humanoid")
	humanoid.Died:Once(function()
		if playerSimulationData[player.UserId] then
			endArmedGroupsByDeath(player, locationName, spawnedNPCs)
		end
	end)

	-- Fase de alerta inicial
	dialog(player, "Warning", "CODIGO ROJO — Se ha confirmado presencia de personas no autorizadas con comportamiento hostil.")
	task.wait(2)
	dialog(player, "Info", "Active el protocolo de confinamiento. Mantenga la calma absoluta.")
	task.wait(2)
	dialog(player, "Info", "Evite ruidos. Silencie su celular. No salga a menos que se lo indiquen.")
	task.wait(prepTime)

	-- Spawnar NPCs antagonistas
	for i = 1, npcCount do
		local sp = spawns[i]
		if sp then
			local clone = atacantNPC:Clone()
			local cf = sp:IsA("BasePart")   and sp.CFrame
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

	dialog(player, "Warning", "Amenaza confirmada en las instalaciones. Siga el protocolo.")
	task.wait(2)

	-- PASO 1: Activar alerta
	local wp1 = getWaypoint(locationName, "ArmedGroupsSimulation", 1)
	if not wp1 then
		warn("[SimController] Grupos armados: Waypoint1 no encontrado.")
		setPowerMode("NORMAL")
		setSimulationActive("ArmedGroups", locationName, false)
		playerSimulationData[player.UserId] = nil
		return
	end

	highlightPart(wp1, true)
	dialog(player, "Warning", "PASO 1: Active la alerta institucional en el punto senalado.")
	task.wait(1)
	dialog(player, "Info", "Presione el boton de panico o sistema de alertas de emergencia.")

	setupWaypointDetection(player, wp1, 1, function()
		recordStep()
		highlightPart(wp1, false)
		dialog(player, "Success", "Alerta activada. Personal y autoridades han sido notificados.")
		task.wait(2)

		-- PASO 2: Confinamiento
		highlightRefuges(refuges, true)
		dialog(player, "Warning", "PASO 2: CONFINAMIENTO — Ubiquese en el espacio seguro senalado.")
		task.wait(1)
		dialog(player, "Info", "Cierre con llave. Apague las luces. Silencio absoluto.")

		setupRefugeDetection(player, refuges, function()
			recordStep()
			highlightRefuges(refuges, false)
			dialog(player, "Success", "Posicion de confinamiento establecida.")
			task.wait(2)
			dialog(player, "Info", "Alejese de puertas y ventanas. No salga hasta recibir autorizacion.")
			task.wait(8)

			-- PASO 3: Verificación por autoridades
			local wp3 = getWaypoint(locationName, "ArmedGroupsSimulation", 3)
			if not wp3 then
				warn("[SimController] Grupos armados: Waypoint3 no encontrado.")
				setPowerMode("NORMAL")
				setSimulationActive("ArmedGroups", locationName, false)
				playerSimulationData[player.UserId] = nil
				return
			end

			highlightPart(wp3, true)
			dialog(player, "Info", "PASO 3: Las autoridades han llegado. Dirijase al punto de verificacion.")
			task.wait(1)
			dialog(player, "Info", "Mantengase con las manos visibles. Identifiquese si se lo solicitan.")

			setupWaypointDetection(player, wp3, 3, function()
				recordStep()
				highlightPart(wp3, false)
				dialog(player, "Success", "Identidad verificada por el personal autorizado.")
				task.wait(2)

				-- PASO 4: Evacuación
				local wp4 = getWaypoint(locationName, "ArmedGroupsSimulation", 4)
				if not wp4 then
					warn("[SimController] Grupos armados: Waypoint4 no encontrado.")
					setPowerMode("NORMAL")
					setSimulationActive("ArmedGroups", locationName, false)
					playerSimulationData[player.UserId] = nil
					return
				end

				highlightPart(wp4, true)
				dialog(player, "Warning", "PASO 4: Evacuese de forma ordenada al punto de reunion externo.")
				task.wait(1)
				dialog(player, "Info", "Siga las instrucciones del personal de seguridad.")

				setupWaypointDetection(player, wp4, 4, function()
					recordStep()
					highlightPart(wp4, false)
					dialog(player, "Success", "Punto de reunion alcanzado. La amenaza ha sido neutralizada.")
					task.wait(2)

					for _, npc in pairs(spawnedNPCs) do
						if npc and npc.Parent then npc:Destroy() end
					end
					setPowerMode("NORMAL")
					showFinalResults(player, simData, "Grupos Armados")
					playerSimulationData[player.UserId] = nil
				end)
			end)
		end)
	end)
	controllerHUDEvent:FireClient(player, "Hide")
end

-- =============================================================================
-- LIMPIEZA AL DESCONECTAR UN JUGADOR
-- =============================================================================

game.Players.PlayerRemoving:Connect(function(player)
	local simData = playerSimulationData[player.UserId]
	if not simData then return end

	if simData.seedPart and simData.seedPart.Parent then
		highlightPart(simData.seedPart, false)
	end
	if simData.connections then
		for _, conn in pairs(simData.connections) do
			if conn and conn.Connected then conn:Disconnect() end
		end
	end
	if simData.simulationEnded ~= nil then
		simData.simulationEnded = true
	end

	playerSimulationData[player.UserId] = nil
	print(string.format("[SimController] Datos de simulacion limpiados: %s.", player.Name))
end)

-- =============================================================================
-- ENTRADA PRINCIPAL — SimulationStartBindable
-- =============================================================================

local DIFFICULTY_MAP = { Easy = 1, Medium = 2, Hard = 3 }

simulationStartBindable.Event:Connect(function(player, eventType, locationName, difficultyStr)
	if not player or not player.Parent then
		warn("[SimController] Solicitud de simulacro con jugador invalido.")
		return
	end
	if type(eventType) ~= "string" or type(locationName) ~= "string" or locationName == "" then
		dialog(player, "Error", "Parametros de simulacro invalidos.")
		return
	end

	local difficulty = DIFFICULTY_MAP[difficultyStr]
	if not difficulty then
		dialog(player, "Error", "Nivel de dificultad desconocido: " .. tostring(difficultyStr))
		return
	end

	print(string.format("[SimController] Solicitud: %s | %s | %s | %s", eventType, locationName, difficultyStr, player.Name))

	-- Detener música del intercom si no es modo exploración
	if eventType ~= "ExploreSimulation" then
		stopIntercom()
	end
	
	
	
	if eventType == "FireSimulation" then
		startFireSimulation(player, locationName, difficulty)
	elseif eventType == "EarthquakeSimulation" then
		startEarthquakeSimulation(player, locationName, difficulty)
	elseif eventType == "ArmedGroupsSimulation" then
		startArmedGroupsSimulation(player, locationName, difficulty)
	elseif eventType == "ExploreSimulation" then
		startExploreMusic()
		startExploreSimulation(player, locationName, difficulty)
	else
		dialog(player, "Error", "Tipo de simulacro no reconocido: " .. tostring(eventType))
	end
end)

-- =============================================================================
-- INICIALIZACION
-- =============================================================================

setPowerMode("NORMAL")
print("[SimController] Sistema inicializado correctamente. Version 2.2.")