-- FireSimulation
-- Purpose: Fire drill flow, procedural fire behavior, and firefighter visibility control.
-- Dependencies: DialogService, NavigationUtils, ActuatorService, ScoringSystem, KioskConfig

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DialogService = require(script.Parent.DialogService)
local NavigationUtils = require(script.Parent.NavigationUtils)
local ActuatorService = require(script.Parent.ActuatorService)
local ResultsSystem = require(script.Parent.ResultsSystem)
local KioskConfig   = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig"))

local RNG = Random.new()

local IGNORED_PART_NAMES = {
	["Baseplate"] = true,
	["Terrain"]   = true,
}

local MIN_VOLUME_FIRE = 0.05
local SCAN_YIELD_EVERY = 2000
local SMOKE_COLOR = Color3.fromRGB(117, 117, 117)

-- ========================= PARTICLE CONFIG (EDIT HERE) =========================
-- Folder path in ReplicatedStorage that contains your 2 presets.
-- Example structure:
-- ReplicatedStorage
--   Particles
--     Fire
--       FireSmall (3 ParticleEmitters)
--       FireLarge (4 ParticleEmitters)
local PARTICLE_PRESETS_ROOT = { "Particles", "Fire" }

-- Names of each preset object inside PARTICLE_PRESETS_ROOT.
local PARTICLE_PRESET_SMALL_NAME = "FireSmall"
local PARTICLE_PRESET_LARGE_NAME = "FireLarge"

-- Your emitters should define an attribute to classify type:
-- EffectType = "Fire"  or  EffectType = "Smoke"
local PARTICLE_EFFECT_TYPE_ATTRIBUTE = "EffectType"

-- Base relation requested:
-- Fire rate = 10, Smoke rate = 40 (x4 over fire).
local FIRE_BASE_RATE = 10
local SMOKE_TO_FIRE_RATE_RATIO = 4

-- Rate scaling based on computed fire size.
local RATE_REFERENCE_FIRE_SIZE = 10
local RATE_MIN_MULTIPLIER = 0.35
local RATE_MAX_MULTIPLIER = 3.0

-- Part volume threshold to pick small vs large preset.
local LARGE_PART_MIN_VOLUME = 10

-- Prefix used by runtime-generated ParticleEmitters for cleanup.
local DYNAMIC_PARTICLE_PREFIX = "DynamicFX_"
-- ======================= END PARTICLE CONFIG (EDIT HERE) =======================

local FIREFIGHTERS_FOLDER = workspace:WaitForChild("FireWaypoints"):WaitForChild("Firefighters")
local FIREFIGHTER_HIDDEN_OFFSET = Vector3.new(0, -100, 0)

local firefightersData = {}
local firefightersInitialized = false
local particleRootCache
local particleRootResolved = false
local particlePresetWarnings = {}

local FireSimulation = {}

local function getBuildingModel(locationName)
	local building = workspace:FindFirstChild(locationName)
	if not building then
		warn(string.format("[SimController] Edificio '%s' no encontrado en workspace.", locationName))
	end
	return building
end

-- Returns the volume of a BasePart.
function FireSimulation.getVolume(part)
	local s = part.Size
	return s.X * s.Y * s.Z
end

-- Returns whether an object is a valid candidate part for fire effects.
function FireSimulation.isValidPart(obj)
	if not obj or not obj:IsA("BasePart") then return false end
	if not obj.Parent then return false end
	if obj.Transparency >= 1 then return false end
	if IGNORED_PART_NAMES[obj.Name] then return false end
	if obj.Locked then return false end
	return true
end

-- Collects all valid building parts that can participate in fire spread.
function FireSimulation.collectBuildingParts(building)
	local parts = {}
	local count = 0
	for _, obj in ipairs(building:GetDescendants()) do
		count += 1
		if count % SCAN_YIELD_EVERY == 0 then task.wait() end
		if FireSimulation.isValidPart(obj) and FireSimulation.getVolume(obj) >= MIN_VOLUME_FIRE then
			table.insert(parts, obj)
		end
	end
	return parts
end

-- Computes fire size based on part size and difficulty.
function FireSimulation.fireSize(part, difficulty)
	local avg = (part.Size.X + part.Size.Y + part.Size.Z) / 3
	local mult = (difficulty == 1 and 2.85) or (difficulty == 2 and 3.05) or 5.25
	return math.clamp(avg * mult, 2, 30)
end

-- Computes fire heat based on difficulty.
function FireSimulation.fireHeat(difficulty)
	return (difficulty == 1 and 20) or (difficulty == 2 and 30) or 40
end

-- Computes smoke size and rise velocity based on part and difficulty.
function FireSimulation.smokeParams(part, difficulty)
	local avg = (part.Size.X + part.Size.Y + part.Size.Z) / 3
	local sizeMult = (difficulty == 1 and 1.0) or (difficulty == 2 and 1.2) or 1.4
	local rise = (difficulty == 1 and 8) or (difficulty == 2 and 6) or 4
	return math.clamp(avg * sizeMult, 3, 25), rise
end

local function resolveParticleRoot()
	if particleRootResolved then return particleRootCache end
	particleRootResolved = true

	local node = ReplicatedStorage
	for _, childName in ipairs(PARTICLE_PRESETS_ROOT) do
		node = node:FindFirstChild(childName)
		if not node then
			warn("[FireSimulation] Particle presets root not found. Check PARTICLE_PRESETS_ROOT.")
			particleRootCache = nil
			return nil
		end
	end

	particleRootCache = node
	return particleRootCache
end

local function getPresetForPart(part)
	local root = resolveParticleRoot()
	if not root then return nil end

	local isLarge = FireSimulation.getVolume(part) >= LARGE_PART_MIN_VOLUME
	local presetName = isLarge and PARTICLE_PRESET_LARGE_NAME or PARTICLE_PRESET_SMALL_NAME
	local preset = root:FindFirstChild(presetName)

	if not preset and not particlePresetWarnings[presetName] then
		particlePresetWarnings[presetName] = true
		warn(string.format("[FireSimulation] Particle preset '%s' not found under configured root.", presetName))
	end

	return preset
end

local function computeScaledRates(part, difficulty)
	local fireSize = FireSimulation.fireSize(part, difficulty)
	local multiplier = math.clamp(
		fireSize / RATE_REFERENCE_FIRE_SIZE,
		RATE_MIN_MULTIPLIER,
		RATE_MAX_MULTIPLIER
	)

	local fireRate = FIRE_BASE_RATE * multiplier
	local smokeRate = fireRate * SMOKE_TO_FIRE_RATE_RATIO
	return fireRate, smokeRate
end

local function applyCustomParticles(part, difficulty)
	local preset = getPresetForPart(part)
	if not preset then return false end

	local fireRate, smokeRate = computeScaledRates(part, difficulty)
	local foundEmitterTemplate = false

	for _, obj in ipairs(preset:GetDescendants()) do
		if obj:IsA("ParticleEmitter") then
			foundEmitterTemplate = true
			local emitterName = DYNAMIC_PARTICLE_PREFIX .. obj.Name
			local emitter = part:FindFirstChild(emitterName)
			if not (emitter and emitter:IsA("ParticleEmitter")) then
				emitter = obj:Clone()
				emitter.Name = emitterName
				emitter.Parent = part
			end

			emitter.Enabled = true
			local effectType = string.lower(tostring(emitter:GetAttribute(PARTICLE_EFFECT_TYPE_ATTRIBUTE) or ""))
			if effectType == "smoke" then
				emitter.Rate = smokeRate
			elseif effectType == "fire" then
				emitter.Rate = fireRate
			else
				-- If no EffectType is defined, default to fire behavior.
				emitter.Rate = fireRate
			end
		end
	end

	if not foundEmitterTemplate then
		warn("[FireSimulation] Selected preset has no ParticleEmitters.")
		return false
	end

	return true
end

-- Adds or updates fire and smoke effects on a part.
function FireSimulation.ignite(part, difficulty)
	if not part or not part.Parent then return end

	-- Try custom particle presets first (small/large).
	if applyCustomParticles(part, difficulty) then
		return
	end

	local fire = part:FindFirstChildOfClass("Fire") or Instance.new("Fire")
	fire.Name = "DynamicFire"
	fire.Enabled = true
	fire.Heat = FireSimulation.fireHeat(difficulty)
	fire.Size = FireSimulation.fireSize(part, difficulty)
	fire.Parent = part

	local smoke = part:FindFirstChildOfClass("Smoke") or Instance.new("Smoke")
	smoke.Name = "DynamicSmoke"
	smoke.Enabled = true
	smoke.Color = SMOKE_COLOR
	smoke.Size, smoke.RiseVelocity = FireSimulation.smokeParams(part, difficulty)
	smoke.Parent = part
end

-- Removes fire and smoke effects from a part.
function FireSimulation.extinguish(part)
	if not part or not part.Parent then return end
	for _, obj in ipairs(part:GetChildren()) do
		if obj:IsA("ParticleEmitter") and string.sub(obj.Name, 1, #DYNAMIC_PARTICLE_PREFIX) == DYNAMIC_PARTICLE_PREFIX then
			obj.Enabled = false
			obj:Destroy()
		end
	end
	local fire = part:FindFirstChild("DynamicFire")
	if fire then fire.Enabled = false; fire:Destroy() end
	local smoke = part:FindFirstChild("DynamicSmoke")
	if smoke then smoke.Enabled = false; smoke:Destroy() end
end

-- Selects fire origin as the largest by volume among random samples.
function FireSimulation.pickFireOrigin(parts)
	local best, bestVol = nil, -math.huge
	for _ = 1, 80 do
		local p = parts[RNG:NextInteger(1, #parts)]
		if p and p.Parent then
			local v = FireSimulation.getVolume(p)
			if v > bestVol then bestVol = v; best = p end
		end
	end
	return best or parts[RNG:NextInteger(1, #parts)]
end

-- Spreads procedural fire from a seed part for a duration and returns affected parts.
function FireSimulation.spreadFire(parts, difficulty, durationSeconds, seedPart)
	if #parts == 0 then return {} end

	local burnedSet = {}
	local burningList = {}

	local spreadRadius = (difficulty == 1 and 18) or (difficulty == 2 and 26) or 35
	local maxPerWave = (difficulty == 1 and 6) or (difficulty == 2 and 10) or 14
	local waveInterval = (difficulty == 1 and 4.0) or (difficulty == 2 and 3.0) or 2.0
	local maxTotal = (difficulty == 1 and 100) or (difficulty == 2 and 150) or 200

	local endTime = tick() + durationSeconds
	local seed = seedPart or FireSimulation.pickFireOrigin(parts)

	if seed then
		FireSimulation.ignite(seed, difficulty)
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
					and FireSimulation.getVolume(p) >= MIN_VOLUME_FIRE then
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
			for i = #burningList, 1, -1 do
				if not burningList[i] or not burningList[i].Parent then
					table.remove(burningList, i)
				end
			end
			continue
		end

		for _, p in ipairs(findCandidates(front, maxPerWave)) do
			if p and p.Parent and not burnedSet[p] then
				FireSimulation.ignite(p, difficulty)
				burnedSet[p] = true
				table.insert(burningList, p)
			end
		end

		if #burningList > maxTotal then
			local excess = #burningList - maxTotal
			for _ = 1, excess do
				local old = table.remove(burningList, 1)
				if old and old.Parent then FireSimulation.extinguish(old) end
			end
		end
	end

	local affected = {}
	for p in pairs(burnedSet) do table.insert(affected, p) end
	return affected
end

-- Initializes firefighter root part original states.
function FireSimulation.initializeFirefighters()
	if firefightersInitialized then return end
	for _, d in ipairs(FIREFIGHTERS_FOLDER:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "HumanoidRootPart" then
			firefightersData[d] = {
				OriginalCFrame = d.CFrame,
				OriginalAnchored = d.Anchored,
			}
		end
	end
	firefightersInitialized = true
end

-- Moves firefighters below map and anchors them.
function FireSimulation.hideFirefighters()
	FireSimulation.initializeFirefighters()
	for hrp, data in pairs(firefightersData) do
		if hrp and hrp.Parent then
			hrp.Anchored = true
			hrp.CFrame = data.OriginalCFrame + FIREFIGHTER_HIDDEN_OFFSET
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

-- Restores firefighters to original position and anchored state.
function FireSimulation.showFirefighters()
	FireSimulation.initializeFirefighters()
	for hrp, data in pairs(firefightersData) do
		if hrp and hrp.Parent then
			hrp.CFrame = data.OriginalCFrame
			hrp.Anchored = data.OriginalAnchored
		end
	end
end

-- Starts a fire simulation for a player at a location and difficulty.
function FireSimulation.start(player, locationName, difficulty, services, state)
	local params = {
		[1] = { duration = 55, heaterDelay = 35 },
		[2] = { duration = 70, heaterDelay = 25 },
		[3] = { duration = 90, heaterDelay = 18 },
	}
	local p = params[math.clamp(difficulty, 1, 3)]

	local building = getBuildingModel(locationName)
	if not building then
		DialogService.send(player, "Error", "No se pudo cargar la ubicacion del ejercicio.")
		return
	end
	if not services.canStartSimulation("Fire", locationName) then
		DialogService.send(player, "Error", "Ya hay un simulacro de incendio activo en esta ubicacion.")
		return
	end

	services.setSimulationActive("Fire", locationName, true)
	services.setPowerMode("BLACKOUT")

	local buildingParts = FireSimulation.collectBuildingParts(building)
	local seedPart = FireSimulation.pickFireOrigin(buildingParts)

	if not seedPart then
		warn(string.format("[SimController] Incendio: no se pudo determinar origen en '%s'.", locationName))
		services.setSimulationActive("Fire", locationName, false)
		services.setPowerMode("NORMAL")
		DialogService.send(player, "Error", "No se pudo iniciar el simulacro. Intente nuevamente.")
		return
	end

	local teleported = NavigationUtils.teleportToClosestSpawn(player, "FireSimulation", locationName, seedPart)
	if not teleported then
		services.setSimulationActive("Fire", locationName, false)
		services.setPowerMode("NORMAL")
		DialogService.send(player, "Error", "No se pudo ubicar al participante. Intente nuevamente.")
		return
	end

	local steps = KioskConfig.getSteps("FireSimulation")
	state.playerSimulationData[player.UserId] = {
		startTime = tick(),
		waypointTimes = {},
		lastWaypointTime = tick(),
		maxTimes = steps.maxTimes,
		stepNames = steps.stepNames,
		connections = {},
		seedPart = seedPart,
		simulationEnded = false,
	}

	local session = state.playerSimulationData[player.UserId]
	player.CharacterRemoving:Connect(function()
		if session then session.simulationEnded = true end
	end)
	print(string.format("[SimController] Incendio iniciado: %s — %s — Dificultad %d", player.Name, locationName, difficulty))
	services.HUDService.startTicker(player, session, services)

	local function recordStep()
		local now = tick()
		table.insert(session.waypointTimes, now - session.lastWaypointTime)
		session.lastWaypointTime = now
	end

	local affectedParts = {}

	local function cleanup()
		if session.simulationEnded then return end
		session.simulationEnded = true
		for _, part in ipairs(affectedParts) do FireSimulation.extinguish(part) end
		FireSimulation.hideFirefighters()
		services.setSimulationActive("Fire", locationName, false)
		services.setPowerMode("NORMAL")
		services.HUDService.stopTicker(player)
		state.playerSimulationData[player.UserId] = nil
	end

	task.spawn(function()
		affectedParts = FireSimulation.spreadFire(buildingParts, difficulty, p.duration, seedPart)
	end)

	task.wait(0.5)
	FireSimulation.showFirefighters()

	if seedPart and seedPart.Parent then
		NavigationUtils.highlightPart(seedPart, true)
	end

	DialogService.send(player, "Warning", "SIMULACRO DE INCENDIO — Se ha reportado un foco de fuego en las instalaciones.")
	task.wait(2)
	DialogService.send(player, "Warning", "El origen del fuego ha sido identificado y senalado. Localicelo.")

	services.controllerHUDEvent:FireClient(player, "Show")
	DialogService.send(player, "Info", "PASO 1: Acerquese al origen del fuego senalado para identificarlo.")

	local originDetected = false

	task.spawn(function()
		while not originDetected and not session.simulationEnded do
			task.wait(0.5)
			if not player.Parent then
				break
			end
			if session.simulationEnded then break end

			if player.Character then
				local hrp = player.Character:FindFirstChild("HumanoidRootPart")
				if hrp and seedPart and seedPart.Parent then
					if (hrp.Position - seedPart.Position).Magnitude <= 40 then
						originDetected = true
						recordStep()
						NavigationUtils.highlightPart(seedPart, false)

						DialogService.send(player, "Success", "Origen del fuego identificado correctamente.")
						task.wait(1)

						local wp2 = NavigationUtils.getWaypoint(locationName, "FireSimulation", 2)
						if not wp2 then
							warn("[SimController] Incendio: Waypoint2 no encontrado.")
							cleanup()
							return
						end

						NavigationUtils.highlightPart(wp2, true)
						DialogService.send(player, "Warning", "PASO 2: Dirijase al punto senalado y active la alarma de incendio.")

						NavigationUtils.setupWaypointDetection(player, wp2, 2, function()
							recordStep()
							NavigationUtils.highlightPart(wp2, false)
							services.playIntercomSound(services.FIRE_ALARM_SOUND_ID)
							DialogService.send(player, "Success", "Alarma de incendio activada. Personal notificado.")
							task.wait(1)

							local wp3 = NavigationUtils.getWaypoint(locationName, "FireSimulation", 3)
							if not wp3 then
								warn("[SimController] Incendio: Waypoint3 no encontrado.")
								cleanup()
								return
							end

							NavigationUtils.highlightPart(wp3, true)
							DialogService.send(player, "Warning", "PASO 3: Evacue el edificio de inmediato. Camine rapido, no corra.")
							task.wait(1)
							DialogService.send(player, "Info", "Use las salidas de emergencia. Mantengase alejado del fuego.")

							NavigationUtils.setupWaypointDetection(player, wp3, 3, function()
								recordStep()
								NavigationUtils.highlightPart(wp3, false)
								DialogService.send(player, "Success", "Salida de emergencia alcanzada.")
								task.wait(1)

								local wp4 = NavigationUtils.getWaypoint(locationName, "FireSimulation", 4)
								if not wp4 then
									warn("[SimController] Incendio: Waypoint4 no encontrado.")
									cleanup()
									return
								end

								NavigationUtils.highlightPart(wp4, true)
								DialogService.send(player, "Warning", "PASO 4: Dirijase al punto de encuentro externo.")
								task.wait(1)
								DialogService.send(player, "Info", "Permanezca ahi hasta nueva instruccion. No reingrese al edificio.")

								NavigationUtils.setupWaypointDetection(player, wp4, 4, function()
									recordStep()
									NavigationUtils.highlightPart(wp4, false)
									DialogService.send(player, "Success", "Punto de encuentro alcanzado. Simulacro completado.")
									task.wait(2)
									cleanup()
									services.controllerHUDEvent:FireClient(player, "Hide")
									ResultsSystem.show(player, session, "FireSimulation",
										locationName, difficulty, services.mainLobbySpawn)
								end)
							end)
						end)
					end
				end
			end
		end
	end)

	task.delay(p.heaterDelay, function()
		if state.playerSimulationData[player.UserId] then
			ActuatorService.fire(player, locationName .. "_Heater", true, p.duration)
		end
	end)

	task.delay(services.SIMULATION_GLOBAL_TIMEOUT, function()
		if state.playerSimulationData[player.UserId] then
			warn(string.format("[SimController] Incendio: timeout de %ds alcanzado para %s.", services.SIMULATION_GLOBAL_TIMEOUT, player.Name))
			cleanup()
			DialogService.send(player, "Warning", "El simulacro ha finalizado por tiempo limite.")
			NavigationUtils.teleportPlayer(player, services.mainLobbySpawn)
		end
	end)
end

return FireSimulation
