-- EarthquakeSimulation
-- Purpose: Earthquake drill flow with object drops, refuge protocol, and aftershocks.
-- Dependencies: DialogService, NavigationUtils, ScoringSystem

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogService = require(script.Parent.DialogService)
local NavigationUtils = require(script.Parent.NavigationUtils)
local ResultsSystem = require(script.Parent.ResultsSystem)
local KioskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig"))
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local RNG = Random.new()

local MIN_VOLUME_QUAKE = 0.15
local SCAN_YIELD_EVERY = 2000
local MIN_STRUCTURAL_VOLUME = 1.2
local MAX_STRUCTURAL_VOLUME = 220
local MAX_PART_DIMENSION = 28
local MAX_UNANCHOR_ASSEMBLY_MASS = 900

local PILLAR_COLOR = Color3.fromRGB(181, 125, 93)
local STUCCO_TILE_SIZE = Vector3.new(3.288, 0.038, 3.288)
local TV_SIZE = Vector3.new(10.17, 5.751, 0.052)
local SIZE_EPSILON = 0.02

local EarthquakeSimulation = {}

local function approx(a, b, eps)
	return math.abs(a - b) <= (eps or 0.01)
end

local function approxVec3(v, target, eps)
	return approx(v.X, target.X, eps) and approx(v.Y, target.Y, eps) and approx(v.Z, target.Z, eps)
end

local function getVolume(part)
	local s = part.Size
	return s.X * s.Y * s.Z
end

local function sortByVolumeDesc(parts)
	table.sort(parts, function(a, b)
		return getVolume(a) > getVolume(b)
	end)
	return parts
end

local function isValidPart(obj)
	if not obj or not obj:IsA("BasePart") then
		return false
	end
	if not obj.Parent then
		return false
	end
	if obj.Transparency >= 1 then
		return false
	end
	if obj.Name == "Baseplate" or obj.Name == "Terrain" then
		return false
	end
	if obj.Locked then
		return false
	end
	return true
end

local function isStructuralCandidate(part)
	if not isValidPart(part) then
		return false
	end
	if not part.Anchored then
		return false
	end
	local volume = getVolume(part)
	if volume < MIN_STRUCTURAL_VOLUME or volume > MAX_STRUCTURAL_VOLUME then
		return false
	end
	if math.max(part.Size.X, part.Size.Y, part.Size.Z) > MAX_PART_DIMENSION then
		return false
	end
	if part.Name:match("^Waypoint") or part.Name:match("^Refuge") then
		return false
	end
	return true
end

local function canUnanchorPart(part)
	if not isValidPart(part) then
		return false
	end
	if not part.Anchored then
		return false
	end
	if math.max(part.Size.X, part.Size.Y, part.Size.Z) > MAX_PART_DIMENSION then
		return false
	end
	if part.AssemblyMass > MAX_UNANCHOR_ASSEMBLY_MASS then
		return false
	end
	return true
end

local function getBuildingModel(locationName)
	local building = workspace:FindFirstChild(locationName)
	if not building then
		Logger.warn("System", string.format("Building model not found in workspace: %s", locationName))
	end
	return building
end

-- Collects candidate earthquake objects from a building.
function EarthquakeSimulation.collectEarthquakeCandidates(building)
	local tiles, tvs, pillars, lightModels, structural = {}, {}, {}, {}, {}
	local excludedFromStructural = {}
	local count = 0
	for _, obj in ipairs(building:GetDescendants()) do
		count += 1
		if count % SCAN_YIELD_EVERY == 0 then
			task.wait()
		end

		if obj:IsA("Model") and (obj.Name:match("^Ceiling Light%d+$") or obj.Name:match("^Roof with Light%d+$")) then
			table.insert(lightModels, obj)
		end

		if isValidPart(obj) and getVolume(obj) >= MIN_VOLUME_QUAKE then
			if obj:IsA("UnionOperation") and approxVec3(obj.Size, STUCCO_TILE_SIZE, SIZE_EPSILON) then
				table.insert(tiles, obj)
				excludedFromStructural[obj] = true
			elseif approxVec3(obj.Size, TV_SIZE, SIZE_EPSILON) then
				table.insert(tvs, obj)
				excludedFromStructural[obj] = true
			elseif obj.Color == PILLAR_COLOR then
				table.insert(pillars, obj)
				excludedFromStructural[obj] = true
			end
		end

		if obj:IsA("BasePart") and isStructuralCandidate(obj) and not excludedFromStructural[obj] then
			table.insert(structural, obj)
		end
	end
	return {
		tiles = tiles,
		tvs = tvs,
		pillars = pillars,
		lightModels = lightModels,
		structural = structural,
	}
end

-- Gets representative part from a model.
function EarthquakeSimulation.getRepresentativePart(model)
	if not model or not model:IsA("Model") then
		return nil
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	local best, bestVol = nil, -1
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local v = getVolume(d)
			if v > bestVol then
				bestVol = v
				best = d
			end
		end
	end
	return best
end

-- Unanchors and impulses a part based on difficulty.
function EarthquakeSimulation.unanchorAndKick(part, difficulty)
	if not part or not part.Parent then
		return nil
	end
	if not part:IsA("BasePart") or not canUnanchorPart(part) then
		return nil
	end

	local state = { part = part, Anchored = true, CFrame = part.CFrame }
	part.Anchored = false

	local strength = (difficulty == 1 and 40) or (difficulty == 2 and 75) or 120
	pcall(function()
		part:ApplyImpulse(
			Vector3.new(RNG:NextNumber(-1, 1), RNG:NextNumber(0.5, 1), RNG:NextNumber(-1, 1)).Unit
				* strength
				* part.AssemblyMass
		)
	end)

	return state
end

-- Applies earthquake drop effects and returns original states.
function EarthquakeSimulation.applyEarthquakeDrops(building, difficulty)
	local c = EarthquakeSimulation.collectEarthquakeCandidates(building)

	local tilesToDrop = (difficulty == 1 and 8) or (difficulty == 2 and 12) or 16
	local tvsToDrop = (difficulty == 1 and 4) or (difficulty == 2 and 6) or 9
	local pillarsToDrop = (difficulty == 1 and 4) or (difficulty == 2 and 7) or 10
	local lightsToDrop = (difficulty == 1 and 12) or (difficulty == 2 and 18) or 24
	local cascadeBudget = (difficulty == 1 and 12) or (difficulty == 2 and 20) or 30
	local cascadePerPillar = (difficulty == 1 and 2) or (difficulty == 2 and 3) or 4
	local cascadeRadius = (difficulty == 1 and 10) or (difficulty == 2 and 14) or 18
	local maxTotalDrops = (difficulty == 1 and 30) or (difficulty == 2 and 45) or 60

	local originals = {}
	local dropped = {}

	local function rememberState(state)
		if not state then
			return
		end
		if dropped[state.part] then
			return
		end
		if #originals >= maxTotalDrops then
			return
		end
		dropped[state.part] = true
		table.insert(originals, state)
	end

	local function desiredCount(list, minimum, ratio)
		if #list == 0 then
			return 0
		end
		local scaled = math.floor(#list * ratio)
		return math.min(#list, math.max(minimum, scaled))
	end

	local function pickRandom(list, amount)
		local picked = {}
		if #list == 0 then
			return picked
		end
		amount = math.min(amount, #list)
		local idx = {}
		for i = 1, #list do
			idx[i] = i
		end
		for i = #idx, 2, -1 do
			local j = RNG:NextInteger(1, i)
			idx[i], idx[j] = idx[j], idx[i]
		end
		for i = 1, amount do
			table.insert(picked, list[idx[i]])
		end
		return picked
	end

	local function pickLargestRandom(list, amount, poolRatio)
		if #list == 0 or amount <= 0 then
			return {}
		end
		local sorted = table.clone(list)
		sortByVolumeDesc(sorted)
		local poolSize = math.max(amount, math.floor(#sorted * (poolRatio or 0.35)))
		poolSize = math.min(poolSize, #sorted)
		local pool = {}
		for i = 1, poolSize do
			table.insert(pool, sorted[i])
		end
		return pickRandom(pool, amount)
	end

	local function kick(list, amount, preferLarge)
		if #originals >= maxTotalDrops then
			return
		end
		amount = math.max(0, math.min(amount, maxTotalDrops - #originals))
		if amount <= 0 then
			return
		end
		local picked = preferLarge and pickLargestRandom(list, amount, 0.4) or pickRandom(list, amount)
		for _, obj in ipairs(picked) do
			local state = EarthquakeSimulation.unanchorAndKick(obj, difficulty)
			rememberState(state)
		end
	end

	local function collapseAdjacentAround(part, amount, radius)
		if amount <= 0 or radius <= 0 then
			return 0
		end
		if #originals >= maxTotalDrops then
			return 0
		end
		amount = math.max(0, math.min(amount, maxTotalDrops - #originals))
		if amount <= 0 then
			return 0
		end
		local nearby = {}
		for _, candidate in ipairs(c.structural) do
			if not dropped[candidate] and candidate.Parent and candidate.Anchored then
				if (candidate.Position - part.Position).Magnitude <= radius then
					table.insert(nearby, candidate)
				end
			end
		end
		sortByVolumeDesc(nearby)

		local collapsed = 0
		for _, candidate in ipairs(pickLargestRandom(nearby, amount, 0.5)) do
			local state = EarthquakeSimulation.unanchorAndKick(candidate, difficulty)
			if state and not dropped[state.part] then
				rememberState(state)
				collapsed += 1
			end
		end
		return collapsed
	end

	kick(c.tiles, desiredCount(c.tiles, tilesToDrop, 0.15), false)
	kick(c.tvs, desiredCount(c.tvs, tvsToDrop, 0.9), true)

	local droppedPillars = pickLargestRandom(c.pillars, desiredCount(c.pillars, pillarsToDrop, 0.9), 0.5)
	for _, pillar in ipairs(droppedPillars) do
		local state = EarthquakeSimulation.unanchorAndKick(pillar, difficulty)
		rememberState(state)
		if cascadeBudget > 0 then
			local collapsed = collapseAdjacentAround(pillar, cascadePerPillar, cascadeRadius)
			cascadeBudget -= collapsed
		end
	end

	if cascadeBudget > 0 then
		kick(c.structural, math.min(cascadeBudget, desiredCount(c.structural, 0, 0.2)), true)
	end

	for _, m in ipairs(pickRandom(c.lightModels, desiredCount(c.lightModels, lightsToDrop, 0.8))) do
		local p = EarthquakeSimulation.getRepresentativePart(m)
		if p then
			local state = EarthquakeSimulation.unanchorAndKick(p, difficulty)
			rememberState(state)
		end
	end

	return originals
end

-- Restores dropped earthquake objects to original states.
function EarthquakeSimulation.restoreEarthquakeDrops(originalStates)
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

-- Triggers repeated aftershock camera shakes and warnings.
function EarthquakeSimulation.triggerAftershocks(player, count, interval)
	task.spawn(function()
		for i = 1, count do
			task.wait(interval)
			local duration = math.random(2, 4)
			local scale = math.random() * 1.5 + 1.0

			DialogService.send(
				player,
				"Warning",
				string.format("Replique sismica #%d detectada. Mantengase en posicion.", i)
			)

			pcall(function()
				local ev = ReplicatedStorage:FindFirstChild("CameraShakeEvent")
				if ev then
					ev:FireClient(player, duration, scale)
				end
			end)
		end
		DialogService.send(player, "Info", "Las replicas han cesado. Permanezca en la zona segura.")
	end)
end

-- Starts an earthquake simulation for a player at a location and difficulty.
function EarthquakeSimulation.start(player, locationName, difficulty, services, state)
	local params = {
		[1] = { duration = 10, shakeScale = 3.0, prepTime = 6 },
		[2] = { duration = 15, shakeScale = 5.0, prepTime = 5 },
		[3] = { duration = 20, shakeScale = 7.0, prepTime = 4 },
	}
	local p = params[math.clamp(difficulty, 1, 3)]

	local building = getBuildingModel(locationName)
	if not building then
		DialogService.send(player, "Error", "No se pudo cargar la ubicacion del ejercicio.")
		return
	end
	if not services.canStartSimulation("Earthquake", locationName) then
		DialogService.send(player, "Error", "Ya hay un simulacro de sismo activo en esta ubicacion.")
		return
	end

	services.setSimulationActive("Earthquake", locationName, true)
	services.setPowerMode("BLACKOUT")
	NavigationUtils.teleportToSpawn(player, "EarthquakeSimulation", locationName)

	local refuges = NavigationUtils.getRefuges(locationName, "EarthquakeSimulation")

	local steps = KioskConfig.getSteps("EarthquakeSimulation")
	state.playerSimulationData[player.UserId] = {
		startTime = tick(),
		waypointTimes = {},
		lastWaypointTime = tick(),
		maxTimes = steps.maxTimes,
		stepNames = steps.stepNames,
		connections = {},
	}

	local session = state.playerSimulationData[player.UserId]
	Logger.info("System", string.format("Earthquake simulation started for %s at %s (difficulty %d)", player.Name, locationName, difficulty))
	services.HUDService.startTicker(player, session, services)

	local function recordStep()
		local now = tick()
		table.insert(session.waypointTimes, now - session.lastWaypointTime)
		session.lastWaypointTime = now
	end

	DialogService.send(player, "Warning", "ALERTA SISMICA — Se ha detectado actividad sismica en la zona.")
	task.wait(2)
	DialogService.send(player, "Info", "Mantenga la calma. Prepare para seguir el protocolo de sismo.")
	task.wait(p.prepTime)

	local originalStates = {}
	task.spawn(function()
		originalStates = EarthquakeSimulation.applyEarthquakeDrops(building, difficulty)
	end)

	services.playIntercomSound(services.EARTHQUAKE_ALARM_SOUND_ID)
	DialogService.send(player, "Warning", "MOVIMIENTO SISMICO EN CURSO.")
	task.wait(1)

	pcall(function()
		local ev = ReplicatedStorage:FindFirstChild("CameraShakeEvent")
		if ev then
			ev:FireClient(player, p.duration, p.shakeScale)
		end
	end)

	services.controllerHUDEvent:FireClient(player, "Show")
	NavigationUtils.highlightRefuges(refuges, true)
	DialogService.send(player, "Warning", "PASO 1: AGACHESE, CUBRASE Y AGÁRRESE.")
	task.wait(1)
	DialogService.send(player, "Info", "Ubiquese bajo un escritorio o estructura resistente. Proteja cabeza y cuello.")

	NavigationUtils.setupRefugeDetection(player, refuges, function()
		recordStep()
		NavigationUtils.highlightRefuges(refuges, false)
		DialogService.send(player, "Success", "Posicion de proteccion adoptada correctamente.")
		task.wait(1)
		DialogService.send(player, "Info", "Mantenga la posicion hasta que cese el movimiento.")

		task.wait(p.duration)

		DialogService.send(player, "Info", "El movimiento principal ha cesado.")
		task.wait(1)
		EarthquakeSimulation.triggerAftershocks(player, 2, 12)

		task.wait(2)
		local wp2 = NavigationUtils.getWaypoint(locationName, "EarthquakeSimulation", 2)
		if not wp2 then
			Logger.warn("System", "EarthquakeSimulation Waypoint2 is missing")
			services.setSimulationActive("Earthquake", locationName, false)
			services.setPowerMode("NORMAL")
			services.controllerHUDEvent:FireClient(player, "Hide")
			services.HUDService.stopTicker(player)
			state.playerSimulationData[player.UserId] = nil
			return
		end

		NavigationUtils.highlightPart(wp2, true)
		DialogService.send(player, "Warning", "PASO 2: Evacue el edificio de forma ordenada.")
		task.wait(1)
		DialogService.send(player, "Info", "Use escaleras. No use ascensores. Atienda replicas.")

		task.wait(3)
		EarthquakeSimulation.triggerAftershocks(player, 3, 8)

		NavigationUtils.setupWaypointDetection(player, wp2, 2, function()
			recordStep()
			NavigationUtils.highlightPart(wp2, false)
			DialogService.send(player, "Success", "Salida del edificio alcanzada.")
			task.wait(2)

			local wp3 = NavigationUtils.getWaypoint(locationName, "EarthquakeSimulation", 3)
			if not wp3 then
				Logger.warn("System", "EarthquakeSimulation Waypoint3 is missing")
				services.setSimulationActive("Earthquake", locationName, false)
				services.setPowerMode("NORMAL")
				services.controllerHUDEvent:FireClient(player, "Hide")
				services.HUDService.stopTicker(player)
				state.playerSimulationData[player.UserId] = nil
				return
			end

			NavigationUtils.highlightPart(wp3, true)
			DialogService.send(player, "Warning", "PASO 3: Dirijase a la zona segura externa.")
			task.wait(1)
			DialogService.send(player, "Info", "Alejese de edificios, postes y cables. Busque un area abierta.")

			NavigationUtils.setupWaypointDetection(player, wp3, 3, function()
				recordStep()
				NavigationUtils.highlightPart(wp3, false)
				DialogService.send(player, "Success", "Zona segura alcanzada. Simulacro completado.")
				task.wait(1)
				DialogService.send(player, "Info", "Permanezca en la zona hasta recibir nueva instruccion.")
				task.wait(3)

				EarthquakeSimulation.restoreEarthquakeDrops(originalStates)
				services.setSimulationActive("Earthquake", locationName, false)
				services.setPowerMode("NORMAL")
				services.controllerHUDEvent:FireClient(player, "Hide")
				ResultsSystem.show(
					player,
					session,
					"EarthquakeSimulation",
					locationName,
					difficulty,
					services.mainLobbySpawn
				)
				services.HUDService.stopTicker(player)
				state.playerSimulationData[player.UserId] = nil
			end)
		end)
	end)
end

return EarthquakeSimulation
