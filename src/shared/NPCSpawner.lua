-- NPCSpawner
-- Location : ServerScriptService
-- Purpose  : Clone and activate up to 2500 NPCs from ReplicatedStorage,
--            distributing them across spawn points and staggering their start
--            so the server doesn't spike on a single frame.
--
-- Usage (fire from any server script or BindableEvent):
--   require(game.ReplicatedStorage.Shared.NPCSpawner).spawn({
--     buildingName  = "MiguelRua",
--     eventType     = "EarthquakeSimulation",
--     count         = 20,
--     walkSpeed     = 10,        -- optional, default 10
--     maxStartDelay = 8,         -- optional, seconds — spread NPC starts over this window
--     offsetRadius  = 2.5,       -- optional, studs — max random XZ offset per NPC
--   })
--
--   require(game.ReplicatedStorage.Shared.NPCSpawner).despawn("MiguelRua", "EarthquakeSimulation")
--
-- Dependencies:
--   ReplicatedStorage.NPC_Template        — NPC Model with Humanoid + NPCWaypointFollower script
--   Workspace.NPC_Waypoints.<B>.<E>       — Waypoint parts (read by the follower, not here)
--   Workspace.NPC_Spawns.<BuildingName>   — BaseParts used as spawn positions

-- FormalMenPantsId = 11801108252
-- DiaryPantsId = 140366176953306
-- SkirtAccesoryName = "BlueSkirt"
-- FormalWomenStockingsId = 14993018644
-- WomanGlassesName = "WomanGlasses"
-- ManGlassesName = "ManGlasses"

-- ─── Services ─────────────────────────────────────────────────────────────────

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService         = game:GetService("RunService")
local NPCFollowerController = require(script.Parent:WaitForChild("NPCFollowerController"))

-- ─── Configuration ────────────────────────────────────────────────────────────

local BATCH_SIZE        = 25    -- NPCs cloned per batch tick (keeps frame time low)
local BATCH_INTERVAL    = 0.05  -- seconds between batches (~500 NPCs/sec at these settings)
local NPC_FOLDER_NAME   = "SpawnedNPCs"   -- Workspace folder that holds active NPCs
local TEMPLATE_NAME     = "NPC_Template"  -- Name of the Model in ReplicatedStorage
local SPAWNS_FOLDER     = "NPC_Spawns"    -- Workspace folder with spawn BaseParts per building
local NPCS_FOLDER_NAME  = "NPCs"

local FORMAL_MEN_PANTS_ID = "rbxassetid://11801108252"
local DIARY_PANTS_ID = "rbxassetid://140366176953306"
local FORMAL_WOMEN_STOCKINGS_ID = "rbxassetid://14993018644"
local SKIRT_ACCESSORY_NAME = "BlueSkirt"
local WOMAN_GLASSES_NAME = "WomanGlasses"
local MAN_GLASSES_NAME = "ManGlasses"

local TORSO_COLOR = Color3.fromRGB(27, 42, 53)
local SKIN_TONES = {
	Color3.fromRGB(255, 204, 153),
	Color3.fromRGB(240, 184, 146),
	Color3.fromRGB(224, 172, 105),
	Color3.fromRGB(198, 134, 66),
	Color3.fromRGB(141, 85, 36),
}

-- ─── State ────────────────────────────────────────────────────────────────────

-- Tracks active NPC groups so despawn() knows what to remove.
-- Key: "BuildingName_EventType" → Folder reference
local activeGroups = {}

local NPCSpawner = {}

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local rng = Random.new()

local npcsRoot = ReplicatedStorage:WaitForChild(NPCS_FOLDER_NAME)

local function pickRandomChild(folder)
	local children = folder:GetChildren()
	if #children == 0 then
		return nil
	end
	return children[rng:NextInteger(1, #children)]
end

local function tryAddAccessory(clone, accessory)
	if not accessory or not accessory:IsA("Accessory") then
		return
	end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local accessoryClone = accessory:Clone()
	humanoid:AddAccessory(accessoryClone)
end

local function applyUniformAppearance(clone, genderFolderName, isFormal)
	local pants = clone:FindFirstChild("Clothing")
	if pants and pants:IsA("Pants") then
		if isFormal then
			pants.PantsTemplate = (genderFolderName == "Women") and FORMAL_WOMEN_STOCKINGS_ID or FORMAL_MEN_PANTS_ID
		else
			pants.PantsTemplate = DIARY_PANTS_ID
		end
	end
end

local function applyBodyColors(clone)
	local bodyColors = clone:FindFirstChild("Body Colors")
	if not (bodyColors and bodyColors:IsA("BodyColors")) then
		return
	end

	local skinTone = SKIN_TONES[rng:NextInteger(1, #SKIN_TONES)]
	bodyColors.HeadColor3 = skinTone
	bodyColors.LeftArmColor3 = skinTone
	bodyColors.RightArmColor3 = skinTone
	bodyColors.LeftLegColor3 = skinTone
	bodyColors.RightLegColor3 = skinTone
	bodyColors.TorsoColor3 = TORSO_COLOR
end

local function buildRandomNPC()
	local genderFolderName = (rng:NextNumber() < 0.5) and "Men" or "Women"
	local genderFolder = npcsRoot:FindFirstChild(genderFolderName)
	if not genderFolder then
		return nil
	end

	local bodysFolder = genderFolder:FindFirstChild("Bodys")
	local hairsFolder = genderFolder:FindFirstChild("Hairs")
	local accessoriesFolder = genderFolder:FindFirstChild("Accesories")
	if not (bodysFolder and hairsFolder and accessoriesFolder) then
		return nil
	end

	local bodyTemplate = pickRandomChild(bodysFolder)
	local hairTemplate = pickRandomChild(hairsFolder)
	if not (bodyTemplate and bodyTemplate:IsA("Model")) then
		return nil
	end

	local clone = bodyTemplate:Clone()
	local isFormal = rng:NextNumber() < 0.5
	local glassesName = (genderFolderName == "Women") and WOMAN_GLASSES_NAME or MAN_GLASSES_NAME
	local glassesTemplate = accessoriesFolder:FindFirstChild(glassesName)
	local skirtTemplate = accessoriesFolder:FindFirstChild(SKIRT_ACCESSORY_NAME)

	if hairTemplate and hairTemplate:IsA("Accessory") then
		tryAddAccessory(clone, hairTemplate)
	end

	if glassesTemplate and glassesTemplate:IsA("Accessory") and rng:NextNumber() < 0.35 then
		tryAddAccessory(clone, glassesTemplate)
	end

	if genderFolderName == "Women" and isFormal and skirtTemplate and skirtTemplate:IsA("Accessory") then
		tryAddAccessory(clone, skirtTemplate)
	end

	applyUniformAppearance(clone, genderFolderName, isFormal)
	applyBodyColors(clone)
	return clone
end

-- Returns a random unit offset clamped to a horizontal radius.
local function randomOffset(radius)
	if not radius or radius <= 0 then return Vector3.zero end
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist  = rng:NextNumber(0, radius)
	return Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

-- Collects all BasePart spawn points for a building.
-- Falls back to the world origin (with a warning) if none are found.
local function getSpawnPoints(buildingName)
	local spawnsRoot = workspace:FindFirstChild(SPAWNS_FOLDER)
	if not spawnsRoot then
		warn("[NPCSpawner] Workspace." .. SPAWNS_FOLDER .. " not found. NPCs will spawn at origin.")
		return { CFrame = CFrame.new(0, 5, 0) }  -- dummy fallback
	end
	local buildingFolder = spawnsRoot:FindFirstChild(buildingName)
	if not buildingFolder then
		warn("[NPCSpawner] No spawn folder for building: " .. buildingName)
		return { CFrame = CFrame.new(0, 5, 0) }
	end
	local points = {}
	for _, v in ipairs(buildingFolder:GetDescendants()) do
		if v:IsA("BasePart") then
			table.insert(points, v)
		end
	end
	if #points == 0 then
		warn("[NPCSpawner] Spawn folder for '" .. buildingName .. "' has no BaseParts.")
		table.insert(points, { CFrame = CFrame.new(0, 5, 0) })
	end
	return points
end

-- Returns (or creates) the workspace container for a group's NPCs.
local function getOrCreateGroup(groupKey)
	local container = workspace:FindFirstChild(NPC_FOLDER_NAME)
	if not container then
		container = Instance.new("Folder")
		container.Name = NPC_FOLDER_NAME
		container.Parent = workspace
	end
	local group = container:FindFirstChild(groupKey)
	if not group then
		group = Instance.new("Folder")
		group.Name = groupKey
		group.Parent = container
	end
	return group
end

-- ─── Public API ───────────────────────────────────────────────────────────────

-- Spawns `count` NPCs for the given building/event combination.
-- config = { buildingName, eventType, count, walkSpeed?, maxStartDelay?, offsetRadius? }
function NPCSpawner.spawn(config)
	assert(type(config) == "table", "[NPCSpawner] spawn() expects a config table.")
	assert(config.buildingName, "[NPCSpawner] buildingName is required.")
	assert(config.eventType,    "[NPCSpawner] eventType is required.")

	local buildingName  = config.buildingName
	local eventType     = config.eventType
	local count         = config.count         or 100
	local walkSpeed     = config.walkSpeed      or 10
	local maxStartDelay = config.maxStartDelay  or 8
	local offsetRadius  = config.offsetRadius   or 2.5

	local groupKey = buildingName .. "_" .. eventType

	-- Prevent duplicate spawns for the same group.
	if activeGroups[groupKey] then
		warn("[NPCSpawner] Group '" .. groupKey .. "' is already active. Despawn first.")
		return
	end

	local template = ReplicatedStorage:FindFirstChild(TEMPLATE_NAME)
	if not template then
		warn("[NPCSpawner] ReplicatedStorage." .. TEMPLATE_NAME .. " not found. Using ReplicatedStorage.NPCs only.")
	end

	local spawnPoints = getSpawnPoints(buildingName)
	local group       = getOrCreateGroup(groupKey)
	activeGroups[groupKey] = group

	print(string.format(
		"[NPCSpawner] Spawning %d NPCs — %s / %s | batch=%d every %.2fs",
		count, buildingName, eventType, BATCH_SIZE, BATCH_INTERVAL
	))

	-- Spawn in batches on a separate thread so the caller doesn't block.
	task.spawn(function()
		local spawned = 0

		while spawned < count do
			-- Check group wasn't despawned mid-spawn.
			if not activeGroups[groupKey] then
				print("[NPCSpawner] Spawn cancelled mid-batch for: " .. groupKey)
				return
			end

			-- Clone a batch.
			for i = 1, BATCH_SIZE do
				if spawned >= count then break end
				spawned += 1

				local clone = buildRandomNPC()
				if not clone and template then
					clone = template:Clone()
				end
				if not clone then
					warn("[NPCSpawner] Could not build random NPC and no fallback template exists.")
					continue
				end
				clone.Name = buildingName .. "_NPC_" .. spawned

				-- Pick a random spawn point from the pool.
				local spawnPart = spawnPoints[rng:NextInteger(1, #spawnPoints)]
				local spawnCF   = spawnPart:IsA("BasePart") and spawnPart.CFrame
				               or spawnPart.CFrame  -- fallback dummy

				-- Place NPC at spawn position with a small random offset.
				local spawnOffset = randomOffset(offsetRadius)
				clone:PivotTo(spawnCF + Vector3.new(spawnOffset.X, 0, spawnOffset.Z))

				-- Set attributes the follower script reads.
				clone:SetAttribute("BuildingName",   buildingName)
				clone:SetAttribute("EventType",      eventType)
				clone:SetAttribute("StartDelay",     rng:NextNumber(0, maxStartDelay))
				clone:SetAttribute("PositionOffset", randomOffset(offsetRadius))
				clone:SetAttribute("PathingStarted", false)

				local h = clone:FindFirstChildOfClass("Humanoid")
				if h then h.WalkSpeed = walkSpeed end

				clone.Parent = group
				NPCFollowerController.activate(clone)
			end

			task.wait(BATCH_INTERVAL)
		end

		print(string.format("[NPCSpawner] Done spawning %d NPCs for %s.", spawned, groupKey))
	end)
end

-- Removes all NPCs for a given building/event combination.
function NPCSpawner.despawn(buildingName, eventType)
	local groupKey = buildingName .. "_" .. eventType
	local group = activeGroups[groupKey]
	if not group then
		warn("[NPCSpawner] No active group found for: " .. groupKey)
		return
	end

	-- Remove from tracking first so any in-flight spawn task stops.
	activeGroups[groupKey] = nil

	-- Destroy in batches to avoid a single-frame spike on 2500 Destroys.
	local children = group:GetChildren()
	local removed  = 0

	task.spawn(function()
		for i, npc in ipairs(children) do
			if npc and npc.Parent then
				npc:Destroy()
				removed += 1
			end
			if i % BATCH_SIZE == 0 then
				task.wait(BATCH_INTERVAL)
			end
		end
		if group and group.Parent then group:Destroy() end
		print(string.format("[NPCSpawner] Despawned %d NPCs for %s.", removed, groupKey))
	end)
end

-- Returns the number of currently active NPCs for a group (useful for debugging).
function NPCSpawner.getCount(buildingName, eventType)
	local groupKey = buildingName .. "_" .. eventType
	local group = activeGroups[groupKey]
	if not group then return 0 end
	return #group:GetChildren()
end

-- ─── Return module ────────────────────────────────────────────────────────────

return NPCSpawner