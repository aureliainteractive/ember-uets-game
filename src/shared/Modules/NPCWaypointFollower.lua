-- NPCWaypointFollower (ModuleScript)
-- Location : ReplicatedStorage.Shared.Modules.NPCWaypointFollower
-- Purpose  : Centralized module for NPC waypoint pathing logic.
--
-- Usage    : local NPCWaypointFollower = require(path.to.this.module)
--            NPCWaypointFollower.start(npcModel)

local NPCWaypointFollower = {}

-- ─── Constants ────────────────────────────────────────────────────────────────

local ARRIVE_RADIUS = 2.5 -- studs: "close enough" to a waypoint node
local MOVETO_TIMEOUT = 12 -- seconds before giving up on a waypoint and skipping
local TICK_RATE = 0.1 -- seconds between movement checks

-- Walk animation IDs (public Roblox default animations — no ownership required)
local WALK_ANIM_R6 = "rbxassetid://180426354"
local WALK_ANIM_R15 = "rbxassetid://507777826"

local WALK_SPEED_THRESHOLD = 0.1
local START_EVENT_NAME = "StartPathing"

-- Door interaction constants
local DOOR_DETECTION_RADIUS = 16 -- studs: scan nearby doors with extra margin
local DOOR_TRIGGER_DISTANCE = 12 -- studs: trigger opening before NPC gets stuck at frame
local DOOR_DEBOUNCE_TIME = 1.5 -- seconds: prevent door spam from same NPC

-- ─── Global door cache (built once, updated on structure changes) ──────────────

local doorCache = {}
local doorCacheLastUpdate = 0
local DOOR_CACHE_UPDATE_INTERVAL = 5 -- seconds: rescan doors every 5 seconds

local function rebuildDoorCache()
	doorCache = {}

	-- Helper: given a Model (or ancestor), find the actual door container we should operate on.
	local function findDoorContainer(candidateModel)
		if not candidateModel or not candidateModel:IsA("Model") then
			return nil
		end

		-- Prefer a nested Model named DoorModel
		local nested = candidateModel:FindFirstChild("DoorModel", true)
		if nested and nested:IsA("Model") then
			return nested
		end

		-- Prefer a model (including candidate) that contains a ToggleDoor RemoteEvent
		for _, m in ipairs(candidateModel:GetDescendants()) do
			if m:IsA("RemoteEvent") and m.Name == "ToggleDoor" then
				-- climb to the nearest Model ancestor of that RemoteEvent
				local mm = m
				while mm and not mm:IsA("Model") do
					mm = mm.Parent
				end
				if mm then
					return mm
				end
			end
		end

		-- If none of the above, prefer the candidateModel itself.
		return candidateModel
	end

	local seen = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		-- If a descendant has the DoorType attribute, look at its model ancestor
		if descendant.GetAttribute and descendant:GetAttribute("DoorType") ~= nil then
			local modelAncestor = descendant
			while modelAncestor and not modelAncestor:IsA("Model") do
				modelAncestor = modelAncestor.Parent
			end
			local rootModel = modelAncestor or (descendant:IsA("Model") and descendant) or nil
			local container = rootModel and findDoorContainer(rootModel) or nil
			if container and not seen[container] then
				table.insert(doorCache, container)
				seen[container] = true
			end
		end

		-- Also include any Model explicitly named DoorModel
		if descendant:IsA("Model") and descendant.Name == "DoorModel" then
			local container = findDoorContainer(descendant)
			if container and not seen[container] then
				table.insert(doorCache, container)
				seen[container] = true
			end
		end

		-- Also include models that directly contain a ToggleDoor RemoteEvent (top-level models)
		if descendant:IsA("RemoteEvent") and descendant.Name == "ToggleDoor" then
			local mm = descendant
			while mm and not mm:IsA("Model") do
				mm = mm.Parent
			end
			if mm and not seen[mm] then
				table.insert(doorCache, mm)
				seen[mm] = true
			end
		end
	end

	doorCacheLastUpdate = tick()
	print("[NPCWaypointFollower] Door cache rebuilt with " .. #doorCache .. " doors")
end

-- Build cache on first load (slightly delayed to allow initial setup)
task.delay(0.5, rebuildDoorCache)
-- Additional retries shortly after startup to handle ordering where doors
-- are created after this module loads (helps avoid empty initial cache).
task.delay(1.5, function()
	if #doorCache == 0 then
		rebuildDoorCache()
	end
end)
task.delay(4.0, function()
	if #doorCache == 0 then
		rebuildDoorCache()
	end
end)

-- Update cache when new models added (mark for rebuild)
workspace.DescendantAdded:Connect(function(descendant)
	local shouldMark = false
	if descendant.GetAttribute and descendant:GetAttribute("DoorType") ~= nil then
		shouldMark = true
	end
	if descendant:IsA("Model") and descendant.Name == "DoorModel" then
		shouldMark = true
	end
	if descendant:IsA("RemoteEvent") and descendant.Name == "ToggleDoor" then
		shouldMark = true
	end
	if shouldMark then
		doorCacheLastUpdate = 0
	end
end)

-- ─── Main Start Function ──────────────────────────────────────────────────────

function NPCWaypointFollower.start(npcModel)
	if not npcModel or not npcModel:IsA("Model") then
		warn("[NPCWaypointFollower] start() expects a Model.")
		return
	end

	-- Bootstrap
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local rootPart = npcModel:FindFirstChild("HumanoidRootPart")
	local started = false

	if not humanoid or not rootPart then
		warn("[NPCWaypointFollower] Missing Humanoid or HumanoidRootPart in: " .. npcModel.Name)
		return
	end

	-- Local state for this NPC
	local doorDebounces = {}

	-- Ensure door cache exists when the first NPC starts (helps startup ordering)
	if #doorCache == 0 then
		rebuildDoorCache()
	end

	-- ─── Animation setup ─────────────────────────────────────────────────────
	--
	-- On the server, LocalScript Animate scripts NEVER run.
	-- Only skip if a proper server Script named "Animate" is present and enabled —
	-- that means whoever built the template already handles animation server-side.
	-- In all other cases (no script, or LocalScript), we take over here.

	local function setupWalkAnimation()
		local animateScript = npcModel:FindFirstChild("Animate")
		if animateScript and animateScript:IsA("Script") and animateScript.Enabled then
			return nil
		end

		local animator = humanoid:WaitForChild("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = humanoid
		end

		local animId = (humanoid.RigType == Enum.HumanoidRigType.R15) and WALK_ANIM_R15 or WALK_ANIM_R6

		local animation = Instance.new("Animation")
		animation.AnimationId = animId

		local walkTrack = animator:LoadAnimation(animation)
		animation:Destroy()

		walkTrack.Looped = true
		walkTrack.Priority = Enum.AnimationPriority.Movement

		task.spawn(function()
			while humanoid and humanoid.Parent do
				if humanoid.Health <= 0 then
					break
				end

				-- MoveDirection is unreliable on the server for NPCs.
				-- Compare actual horizontal speed against a fraction of WalkSpeed.
				local velocity = rootPart.AssemblyLinearVelocity
				local horizontalSpeed = math.sqrt((velocity.X * velocity.X) + (velocity.Z * velocity.Z))
				local movingThreshold = math.max(WALK_SPEED_THRESHOLD, humanoid.WalkSpeed * 0.25)
				local moving = horizontalSpeed >= movingThreshold

				if moving then
					if not walkTrack.IsPlaying then
						walkTrack:Play(0.15)
					end
				else
					if walkTrack.IsPlaying then
						walkTrack:Stop(0.15)
					end
				end

				task.wait(0.1)
			end
		end)

		humanoid.Died:Connect(function()
			if walkTrack.IsPlaying then
				walkTrack:Stop(0.1)
			end
		end)

		return walkTrack
	end

	-- ─── Door interaction system ──────────────────────────────────────────────────
	--
	-- Allows NPCs to automatically open doors when nearby.
	-- Tracks door debounces per NPC to avoid spam.

	local function tryOpenNearbyDoors()
		if humanoid.Health <= 0 then
			return
		end

		local npcPos = rootPart.Position

		-- Update cache if needed (every 5 seconds)
		if tick() - doorCacheLastUpdate > DOOR_CACHE_UPDATE_INTERVAL then
			rebuildDoorCache()
		end

		local closestDoor = nil
		local closestDistance = math.huge
		local closestOpenDoorEvent = nil

		-- Iterate through cached doors only (no workspace scan!)
		for _, doorModel in ipairs(doorCache) do
			-- Safety check: door still exists and is a valid model
			if not doorModel or not doorModel.Parent then
				continue
			end

			-- Get the position of the door model from its pivot.
			-- This is more reliable than relying on PrimaryPart/first BasePart.
			local ok, pivot = pcall(function()
				return doorModel:GetPivot()
			end)
			local doorPos = ok and pivot and pivot.Position or nil

			if not doorPos then
				continue
			end

			local distance = (doorPos - npcPos).Magnitude

			-- Only process doors within detection range
			if distance > DOOR_DETECTION_RADIUS then
				continue
			end

			-- Check if door is not already open
			local isOpen = doorModel:GetAttribute("IsOpen") or false
			if isOpen then
				continue
			end

			-- Check debounce
			if not doorDebounces[doorModel] then
				doorDebounces[doorModel] = {}
			end

			local lastTriggered = doorDebounces[doorModel].lastTriggeredTime or 0
			local timeSinceLastTrigger = tick() - lastTriggered

			if timeSinceLastTrigger < DOOR_DEBOUNCE_TIME then
				continue
			end

			local openDoorEvent = doorModel:FindFirstChild("OpenDoorEvent", true)
			if not openDoorEvent then
				continue
			end

			if not openDoorEvent:IsA("BindableEvent") then
				continue
			end

			if distance < closestDistance then
				closestDoor = doorModel
				closestDistance = distance
				closestOpenDoorEvent = openDoorEvent
			end
		end

		if closestDoor and closestOpenDoorEvent and closestDistance <= DOOR_TRIGGER_DISTANCE then
			if not doorDebounces[closestDoor] then
				doorDebounces[closestDoor] = {}
			end
			doorDebounces[closestDoor].lastTriggeredTime = tick()
			print("[NPCWaypointFollower] " .. npcModel.Name .. " opening door: " .. closestDoor.Name .. " (distance: " .. tostring(math.floor(closestDistance)) .. ")")
			closestOpenDoorEvent:Fire()
		end
	end

	-- ─── Waypoint collection ──────────────────────────────────────────────────────

	local function resolveWaypointsRoot()
		local preferred = workspace:FindFirstChild("NPC_Waypoints")
		if preferred then
			return preferred
		end

		local legacy = workspace:FindFirstChild("Waypoints")
		if legacy then
			warn("[NPCWaypointFollower] Using legacy root Workspace.Waypoints (NPC_Waypoints not found).")
			return legacy
		end

		warn("[NPCWaypointFollower] Neither Workspace.NPC_Waypoints nor Workspace.Waypoints exists.")
		return nil
	end

	local function parseWaypointIndex(name)
		return tonumber(name:match("^Waypoint[_%-]?(%d+)$")) or tonumber(name:match("^WP(%d+)$"))
	end

	local function collectWaypoints(buildingName, eventType)
		local root = resolveWaypointsRoot()
		if not root then
			return {}
		end

		local buildingFolder = root:FindFirstChild(buildingName)
		if not buildingFolder then
			warn("[NPCWaypointFollower] Building folder not found: " .. tostring(buildingName))
			return {}
		end

		local eventFolder = buildingFolder:FindFirstChild(eventType)
		if not eventFolder then
			warn("[NPCWaypointFollower] Event folder not found: " .. tostring(eventType))
			return {}
		end

		local list = {}
		for _, child in ipairs(eventFolder:GetChildren()) do
			if child:IsA("BasePart") then
				local n = parseWaypointIndex(child.Name)
				if n then
					table.insert(list, { index = n, part = child })
				end
			end
		end

		table.sort(list, function(a, b)
			return a.index < b.index
		end)

		if #list == 0 then
			warn(
				string.format(
					"[NPCWaypointFollower] No waypoint parts found in '%s/%s'. Expected names like Waypoint1, Waypoint2...",
					buildingName,
					eventType
				)
			)
		end

		return list
	end

	-- ─── Movement ─────────────────────────────────────────────────────────────────

	local function moveTo(targetPos, offset)
		local goal = targetPos + (offset or Vector3.zero)
		local reached = false

		local conn = humanoid.MoveToFinished:Connect(function(didReach)
			if didReach then
				reached = true
			end
		end)

		humanoid:MoveTo(goal)

		local elapsed = 0
		while elapsed < MOVETO_TIMEOUT do
			if humanoid.Health <= 0 then
				conn:Disconnect()
				return false
			end
			if reached or (rootPart.Position - goal).Magnitude <= ARRIVE_RADIUS then
				conn:Disconnect()
				return true
			end

			-- Check for nearby doors during movement
			tryOpenNearbyDoors()

			task.wait(TICK_RATE)
			elapsed += TICK_RATE
		end

		conn:Disconnect()
		-- Timed out — nudge the goal once more and move on.
		humanoid:MoveTo(goal)
		return false
	end

	-- ─── Waypoint handlers ────────────────────────────────────────────────────────

	local function handleTransit(wp, offset)
		moveTo(wp.Position, offset)
	end

	local function handleHold(wp, offset)
		moveTo(wp.Position, offset)
		if humanoid.Health > 0 then
			local holdDuration = wp:GetAttribute("HoldDuration") or 3
			local held = 0
			while held < holdDuration do
				humanoid:MoveTo(wp.Position + (offset or Vector3.zero))
				local step = math.min(1, holdDuration - held)
				task.wait(step)
				held += step
			end
		end
	end

	local function handleFinish(wp, offset)
		moveTo(wp.Position, offset)
		-- Keep refreshing MoveTo so the NPC doesn't drift after reaching the final point.
		task.spawn(function()
			local finalPos = wp.Position + (offset or Vector3.zero)
			while npcModel.Parent and humanoid.Health > 0 do
				humanoid:MoveTo(finalPos)
				task.wait(1)
			end
		end)
		return false -- signals run() to stop iterating
	end

	-- ─── Runner ───────────────────────────────────────────────────────────────────

	local function run()
		local buildingName = npcModel:GetAttribute("BuildingName")
		local eventType = npcModel:GetAttribute("EventType")
		local startDelay = npcModel:GetAttribute("StartDelay") or 0
		local rawOffset = npcModel:GetAttribute("PositionOffset")

		if not buildingName or not eventType then
			warn("[NPCWaypointFollower] BuildingName or EventType missing on: " .. npcModel.Name)
			return
		end

		local offset = rawOffset or Vector3.zero

		if startDelay > 0 then
			task.wait(startDelay)
		end

		local waypoints = collectWaypoints(buildingName, eventType)

		if #waypoints == 0 then
			return
		end

		for _, entry in ipairs(waypoints) do
			if not npcModel.Parent then
				return
			end
			if humanoid.Health <= 0 then
				return
			end

			local wp = entry.part

			local wpType = wp:GetAttribute("WaypointType") or "Transit"

			if wpType == "Transit" then
				handleTransit(wp, offset)
			elseif wpType == "Hold" then
				handleHold(wp, offset)
			elseif wpType == "Finish" then
				if handleFinish(wp, offset) == false then
					return
				end
			else
				warn("[NPCWaypointFollower] Unknown WaypointType '" .. tostring(wpType) .. "' — treating as Transit.")
				handleTransit(wp, offset)
			end
		end
	end

	-- ─── Start execution ──────────────────────────────────────────────────────────

	if started then
		return
	end
	started = true
	npcModel:SetAttribute("PathingStarted", true)

	-- Set up animations BEFORE the first MoveTo so the Running event
	-- is already connected when movement begins.
	setupWalkAnimation()

	task.spawn(run)
end

-- Allow manual rebuild from the Command Bar for debugging: 
-- local m = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("NPCWaypointFollower")); m.rebuildDoorCache()
NPCWaypointFollower.rebuildDoorCache = rebuildDoorCache

return NPCWaypointFollower
