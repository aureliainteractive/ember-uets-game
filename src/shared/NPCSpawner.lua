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
--     maxStartDelay = 12,        -- optional, seconds — spread NPC starts over this window
--     offsetRadius  = 2.5,       -- optional, studs — max random XZ offset per NPC
--   })
--
--   require(game.ReplicatedStorage.Shared.NPCSpawner).despawn("MiguelRua", "EarthquakeSimulation")
--
-- Dependencies:
--   ReplicatedStorage.NPC_Template        — NPC Model with Humanoid + NPCWaypointFollower script
--   Workspace.NPC_Waypoints.<B>.<E>       — Waypoint parts (read by the follower, not here)
--   Workspace.NPC_Spawns.<BuildingName>   — BaseParts used as spawn positions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local NPCFollowerController = require(script.Parent:WaitForChild("NPCFollowerController"))
local NPCWaypointFollower = require(script.Parent:WaitForChild("Modules"):WaitForChild("NPCWaypointFollower"))

-- ─── CONFIG ─────────────────────────────────────────────────────────────

local BATCH_SIZE = 8
local BATCH_INTERVAL = 0.15
local NPC_FOLDER_NAME = "SpawnedNPCs"
local SPAWNS_FOLDER = "NPC_Spawns"
local NPCS_FOLDER_NAME = "NPCs"
local NPC_COLLISION_GROUP = "NPCs"

local FORMAL_MEN_PANTS_ID = "rbxassetid://11801108237"
local DIARY_PANTS_ID = "rbxassetid://140366176953306"
local FORMAL_WOMEN_STOCKINGS_ID = "rbxassetid://14993018644"
local SKIRT_ACCESSORY_NAME = "BlueSkirt"

local WOMAN_GLASSES_NAME = "WomanGlasses"
local MAN_GLASSES_NAME = "ManGlasses"

local TORSO_COLOR = Color3.fromRGB(27, 42, 53)

local SKIN_TONES = {
	{ color = Color3.fromRGB(235, 200, 170), weight = 30 },
	{ color = Color3.fromRGB(220, 180, 145), weight = 25 },
	{ color = Color3.fromRGB(200, 155, 120), weight = 20 },
	{ color = Color3.fromRGB(170, 125, 90), weight = 15 },
	{ color = Color3.fromRGB(135, 95, 65), weight = 10 },
}

-- 🎬 Animaciones por género
local PACKS_BY_GENDER = {
	Men = {
		{
			idle = { "rbxassetid://507766666", "rbxassetid://507766951" },
			walk = "rbxassetid://507777826",
			run = "rbxassetid://507767714",
			jump = "rbxassetid://507765000",
			fall = "rbxassetid://507767968",
			climb = "rbxassetid://507765644",
			swim = "rbxassetid://507784897",
			swimidle = "rbxassetid://507785072",
		},
	},

	Women = {
		{
			idle = { "rbxassetid://619511648", "rbxassetid://619511648" },
			walk = "rbxassetid://619512767",
			run = "rbxassetid://619512565",
			jump = "rbxassetid://619511974",
			fall = "rbxassetid://619511969",
			climb = "rbxassetid://619511968",
			swim = "rbxassetid://619512450",
			swimidle = "rbxassetid://619512228",
		},
	},
}

-- ─── STATE ──────────────────────────────────────────────────────────────

local activeGroups = {}
local NPCSpawner = {}
local rng = Random.new()
local npcsRoot = ReplicatedStorage:WaitForChild(NPCS_FOLDER_NAME)
local collisionGroupReady = false

-- ─── HELPERS ─────────────────────────────────────────────────────────────

local function ensureNpcCollisionGroup()
	if collisionGroupReady then return end
	collisionGroupReady = true

	pcall(function()
		PhysicsService:RegisterCollisionGroup(NPC_COLLISION_GROUP)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(NPC_COLLISION_GROUP, NPC_COLLISION_GROUP, false)
	end)
end

local function configureNpcPhysics(npc)
	ensureNpcCollisionGroup()

	for _, descendant in ipairs(npc:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = NPC_COLLISION_GROUP
			descendant.Anchored = false
			descendant:SetNetworkOwner(nil)
		end
	end
end

local function getWeightedSkinTone()
	local total = 0
	for _, e in ipairs(SKIN_TONES) do
		total += e.weight
	end
	local roll = math.random(1, total)
	local acc = 0
	for _, e in ipairs(SKIN_TONES) do
		acc += e.weight
		if roll <= acc then
			return e.color
		end
	end
	return SKIN_TONES[1].color
end

local function varyColor(color)
	local v = 5
	return Color3.fromRGB(
		math.clamp(color.R * 255 + math.random(-v, v), 0, 255),
		math.clamp(color.G * 255 + math.random(-v, v), 0, 255),
		math.clamp(color.B * 255 + math.random(-v, v), 0, 255)
	)
end

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
	local h = clone:FindFirstChildOfClass("Humanoid")
	if h then
		h:AddAccessory(accessory:Clone())
	end
end

local function applyUniformAppearance(clone, gender, isFormal)
	local pants = clone:FindFirstChildOfClass("Pants")
	if not pants then
		return
	end

	if isFormal then
		pants.PantsTemplate = (gender == "Women") and FORMAL_WOMEN_STOCKINGS_ID or FORMAL_MEN_PANTS_ID
	else
		pants.PantsTemplate = DIARY_PANTS_ID
	end
end

local function applyBodyColors(clone)
	local bc = clone:FindFirstChildOfClass("BodyColors")
	if not bc then
		return
	end

	local tone = varyColor(getWeightedSkinTone())

	bc.HeadColor3 = tone
	bc.LeftArmColor3 = tone
	bc.RightArmColor3 = tone
	bc.LeftLegColor3 = tone
	bc.RightLegColor3 = tone
	bc.TorsoColor3 = TORSO_COLOR
end

-- 🎬 Animaciones
local function applyAnimationPack(npc, pack)
	local animate = npc:FindFirstChild("Animate")
	if not animate or not pack then
		return
	end

	if animate:FindFirstChild("walk") then
		animate.walk.WalkAnim.AnimationId = pack.walk
	end
	if animate:FindFirstChild("run") then
		animate.run.RunAnim.AnimationId = pack.run
	end
	if animate:FindFirstChild("jump") then
		animate.jump.JumpAnim.AnimationId = pack.jump
	end
	if animate:FindFirstChild("fall") then
		animate.fall.FallAnim.AnimationId = pack.fall
	end
	if animate:FindFirstChild("climb") then
		animate.climb.ClimbAnim.AnimationId = pack.climb
	end
	if animate:FindFirstChild("swim") then
		animate.swim.Swim.AnimationId = pack.swim
	end
	if animate:FindFirstChild("swimidle") then
		animate.swimidle.SwimIdle.AnimationId = pack.swimidle
	end

	if animate:FindFirstChild("idle") then
		local idle = animate.idle
		if idle:FindFirstChild("Animation1") then
			idle.Animation1.AnimationId = pack.idle[1]
		end
		if idle:FindFirstChild("Animation2") then
			idle.Animation2.AnimationId = pack.idle[2]
		end
	end
end

-- 🎭 FACE CONTROLS

local function getFaceControls(npc)
	local head = npc:FindFirstChild("Head")
	if not head then
		return nil
	end
	return head:FindFirstChild("FaceControls")
end

local function applyFace(face, data)
	for prop, value in pairs(data) do
		if face[prop] ~= nil then
			face[prop] = value
		end
	end
end

local EMOTIONS = {

	Neutral = function(face)
		applyFace(face, {
			JawDrop = 0,
			LipsTogether = 1,
		})
	end,

	Nervous = function(face)
		applyFace(face, {
			LeftEyeUpperLidRaiser = 0.4,
			RightEyeUpperLidRaiser = 0.4,
			JawDrop = 0.2,
			LipPresser = 0.3,
		})
	end,

	Panic = function(face)
		applyFace(face, {
			LeftEyeUpperLidRaiser = 1,
			RightEyeUpperLidRaiser = 1,
			LeftInnerBrowRaiser = 1,
			RightInnerBrowRaiser = 1,
			JawDrop = 0.7,
		})
	end,

	Stress = function(face)
		applyFace(face, {
			LeftBrowLowerer = 0.6,
			RightBrowLowerer = 0.6,
			LipPresser = 0.7,
		})
	end,

	Determined = function(face)
		applyFace(face, {
			LipPresser = 0.8,
			JawDrop = 0,
		})
	end,
}

local EMOTION_LIST = { "Neutral", "Nervous", "Panic", "Stress", "Determined" }

local function applyRandomEmotion(npc)
	local face = getFaceControls(npc)
	if not face then
		return
	end

	local emotion = EMOTIONS[EMOTION_LIST[rng:NextInteger(1, #EMOTION_LIST)]]
	if emotion then
		emotion(face)
	end

	-- micro movimiento de ojos
	task.spawn(function()
		while npc.Parent and face do
			face.EyesLookLeft = rng:NextNumber(0, 0.5)
			face.EyesLookRight = rng:NextNumber(0, 0.5)
			face.EyesLookUp = rng:NextNumber(0, 0.3)
			face.EyesLookDown = rng:NextNumber(0, 0.3)
			task.wait(rng:NextNumber(1, 3))
		end
	end)
end

-- ─── NPC BUILDER ─────────────────────────────────────────────────────────

local function buildRandomNPC()
	local gender = (rng:NextNumber() < 0.5) and "Men" or "Women"
	local folder = npcsRoot:FindFirstChild(gender)
	if not folder then
		return nil
	end

	local bodys = folder:FindFirstChild("Bodys")
	local hairs = folder:FindFirstChild("Hairs")
	local accs = folder:FindFirstChild("Accesories")
	if not (bodys and hairs and accs) then
		return nil
	end

	local bodyTemplate = pickRandomChild(bodys)
	if not (bodyTemplate and bodyTemplate:IsA("Model")) then
		return nil
	end

	local clone = bodyTemplate:Clone()

	for _, p in ipairs(clone:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
		end
	end

	local genderPacks = PACKS_BY_GENDER[gender]
	if genderPacks and #genderPacks > 0 then
		applyAnimationPack(clone, genderPacks[rng:NextInteger(1, #genderPacks)])
	end

	applyRandomEmotion(clone)

	tryAddAccessory(clone, pickRandomChild(hairs))

	local glassesName = (gender == "Women") and WOMAN_GLASSES_NAME or MAN_GLASSES_NAME
	local glasses = accs:FindFirstChild(glassesName)
	if glasses and rng:NextNumber() < 0.35 then
		tryAddAccessory(clone, glasses)
	end

	local isFormal = rng:NextNumber() < 0.5
	applyUniformAppearance(clone, gender, isFormal)
	applyBodyColors(clone)

	local skirt = accs:FindFirstChild(SKIRT_ACCESSORY_NAME)
	if gender == "Women" and isFormal and skirt then
		tryAddAccessory(clone, skirt)
	end

	return clone
end

-- ─── SPAWN SYSTEM ────────────────────────────────────────────────────────

local function randomOffset(radius)
	if not radius or radius <= 0 then
		return Vector3.zero
	end
	local angle = rng:NextNumber(0, math.pi * 2)
	local dist = rng:NextNumber(0, radius)
	return Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

local function normalizeName(value)
	return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function findChildAgnostic(parent, targetName)
	if not parent or not targetName then
		return nil
	end

	local exact = parent:FindFirstChild(targetName)
	if exact then
		return exact
	end

	local needle = normalizeName(targetName)
	for _, child in ipairs(parent:GetChildren()) do
		if normalizeName(child.Name) == needle then
			return child
		end
	end

	return nil
end

local function getSpawnPoints(buildingName)
	local root = workspace:FindFirstChild(SPAWNS_FOLDER)
	if not root then
		return { { part = nil, floorName = nil, cframe = CFrame.new(0, 5, 0) } }
	end

	local folder = findChildAgnostic(root, buildingName)
	if not folder then
		return { { part = nil, floorName = nil, cframe = CFrame.new(0, 5, 0) } }
	end

	local pts = {}
	for _, floorFolder in ipairs(folder:GetChildren()) do
		if floorFolder:IsA("Folder") or floorFolder:IsA("Model") then
			for _, descendant in ipairs(floorFolder:GetDescendants()) do
				if descendant:IsA("BasePart") then
					table.insert(pts, {
						part = descendant,
						floorName = floorFolder.Name,
						cframe = descendant.CFrame,
					})
				end
			end
		end
	end

	if #pts == 0 then
		table.insert(pts, { part = nil, floorName = nil, cframe = CFrame.new(0, 5, 0) })
	end

	return pts
end

local function getOrCreateGroup(key)
	local root = workspace:FindFirstChild(NPC_FOLDER_NAME)
	if not root then
		root = Instance.new("Folder", workspace)
		root.Name = NPC_FOLDER_NAME
	end

	local g = root:FindFirstChild(key)
	if not g then
		g = Instance.new("Folder", root)
		g.Name = key
	end

	return g
end

-- ─── API ─────────────────────────────────────────────────────────────────

function NPCSpawner.spawn(config)
	local building = config.buildingName
	local event = config.eventType
	local count = config.count or 100
	local speed = config.walkSpeed or 10
	local delayMax = config.maxStartDelay or 12
	local radius = config.offsetRadius or 2.5

	local key = building .. "_" .. event
	if activeGroups[key] then
		return
	end

	local spawns = getSpawnPoints(building)
	local group = getOrCreateGroup(key)
	activeGroups[key] = group

	task.spawn(function()
		if config.prewarmRoutes ~= false then
			NPCWaypointFollower.prewarmRoutes(building, event, spawns, {
				logProgress = config.prewarmLogProgress ~= false,
				spawnRoutes = config.prewarmSpawnRoutes ~= false,
				nodeRoutes = config.prewarmNodeRoutes ~= false,
				firstWaypointRoutes = config.prewarmFirstWaypointRoutes ~= false,
				waypointRoutes = config.prewarmWaypointRoutes ~= false,
			})
		end

		local spawned = 0

		while spawned < count do
			if not activeGroups[key] then
				return
			end

			for i = 1, BATCH_SIZE do
				if spawned >= count then
					break
				end
				spawned += 1

				local npc = buildRandomNPC()
				if not npc then
					continue
				end
				local baseName = npc.Name
				local debugId = string.format("%s-%04d", key, spawned)
				npc.Name = string.format("%s_%04d", baseName, spawned)
				npc:SetAttribute("NPCDebugId", debugId)

				local sp = spawns[rng:NextInteger(1, #spawns)]
				local cf = sp.cframe or (sp.part and sp.part.CFrame) or CFrame.new(0, 5, 0)

				npc:PivotTo(cf + randomOffset(radius))

				npc:SetAttribute("BuildingName", building)
				if sp.floorName then
					npc:SetAttribute("FloorName", sp.floorName)
				end
				if sp.part then
					npc:SetAttribute("SpawnPointKey", sp.part:GetFullName())
				end
				npc:SetAttribute("EventType", event)
				npc:SetAttribute("StartDelay", rng:NextNumber(0, delayMax))
				npc:SetAttribute("PathingStarted", false)

				local h = npc:FindFirstChildOfClass("Humanoid")
				if h then
					h.WalkSpeed = speed
					h.AutoRotate = true
					h.PlatformStand = false
					h.Sit = false
					h.DisplayName = npc.Name
				end

				npc.Parent = group
				configureNpcPhysics(npc)
				local rootPart = npc:FindFirstChild("HumanoidRootPart")
				if rootPart and rootPart:IsA("BasePart") then
					rootPart:SetNetworkOwner(nil)
				end
				NPCFollowerController.activate(npc)
			end

			task.wait(BATCH_INTERVAL)
		end
	end)
end

function NPCSpawner.despawn(building, event)
	local key = building .. "_" .. event
	local g = activeGroups[key]
	if not g then
		return
	end

	activeGroups[key] = nil

	task.spawn(function()
		for _, npc in ipairs(g:GetChildren()) do
			npc:Destroy()
		end
		g:Destroy()
	end)
end

function NPCSpawner.getCount(building, event)
	local g = activeGroups[building .. "_" .. event]
	return g and #g:GetChildren() or 0
end

return NPCSpawner
