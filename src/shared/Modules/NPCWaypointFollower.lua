-- NPCWaypointFollower (ModuleScript)
-- Location : ReplicatedStorage.Shared.Modules.NPCWaypointFollower
-- Purpose  : Centralized module for NPC waypoint pathing logic.
--
-- Usage    : local NPCWaypointFollower = require(path.to.this.module)
--            NPCWaypointFollower.start(npcModel)

local NPCWaypointFollower = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))
local NodeGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("NodeGraph"))

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
local DOOR_SEGMENT_HEIGHT_TOLERANCE = 8 -- studs: ignore doors that are not on the same vertical band as the movement segment

-- Crowd/anti-clumping constants
local AUTO_OFFSET_RADIUS = 2.25 -- studs: fallback per-NPC lateral spread when no PositionOffset is provided
local STUCK_TIME_BEFORE_NUDGE = 1.0 -- seconds standing almost still before re-path nudge
local STUCK_MOVEMENT_EPSILON = 0.05 -- studs per tick considered "not moving"
local STUCK_NUDGE_RADIUS = 2.0 -- studs: temporary nudge radius to break local congestion

-- ─── Global door cache (built once, updated on structure changes) ──────────────

local doorCache = {}
local doorCacheLastUpdate = 0
local DOOR_CACHE_UPDATE_INTERVAL = 5 -- seconds: rescan doors every 5 seconds

local function getDoorFloorName(doorModel)
	local current = doorModel
	while current do
		if current.Parent and current.Parent.Name == "Doors" then
			return current.Name
		end
		current = current.Parent
	end

	return doorModel and doorModel:GetAttribute("FloorName") or nil
end

local function doorMatchesFloor(doorModel, floorName)
	if not floorName then
		return true
	end

	local doorFloor = doorModel and doorModel:GetAttribute("FloorName") or nil
	if not doorFloor then
		doorFloor = getDoorFloorName(doorModel)
	end

	return not doorFloor or doorFloor == floorName
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
					container:SetAttribute("FloorName", getDoorFloorName(container))
				table.insert(doorCache, container)
				seen[container] = true
			end
		end

		-- Also include any Model explicitly named DoorModel
		if descendant:IsA("Model") and descendant.Name == "DoorModel" then
			local container = findDoorContainer(descendant)
			if container and not seen[container] then
					container:SetAttribute("FloorName", getDoorFloorName(container))
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
					mm:SetAttribute("FloorName", getDoorFloorName(mm))
				table.insert(doorCache, mm)
				seen[mm] = true
			end
		end

	end

	doorCacheLastUpdate = tick()
	Logger.debug("NPC", string.format("Door cache rebuilt with %d entries", #doorCache))
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
		Logger.warn("NPC", "start() expects a Model instance")
		return
	end

	-- Bootstrap
	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local rootPart = npcModel:FindFirstChild("HumanoidRootPart")
	local started = false

	if not humanoid or not rootPart then
		Logger.warn("NPC", "Missing Humanoid or HumanoidRootPart in " .. npcModel.Name)
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

	local function getDoorOpenState(doorModel)
		if not doorModel then
			return nil
		end

		local isOpen = doorModel:GetAttribute("IsOpen")
		if type(isOpen) == "boolean" then
			return isOpen
		end

		local open = doorModel:GetAttribute("Open")
		if type(open) == "boolean" then
			return open
		end

		local opened = doorModel:GetAttribute("Opened")
		if type(opened) == "boolean" then
			return opened
		end

		local state = doorModel:GetAttribute("State")
		if type(state) == "string" then
			local s = string.lower(state)
			if s == "open" or s == "opened" then
				return true
			end
			if s == "closed" then
				return false
			end
		end

		return nil
	end

	local function tryOpenNearbyDoors(floorName)
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

			local openState = getDoorOpenState(doorModel)
			if openState == true then
				continue
			end

			if not doorMatchesFloor(doorModel, floorName) then
				continue
			end

			-- Check debounce
			if not doorDebounces[doorModel] then
				doorDebounces[doorModel] = {}
			end
			if doorDebounces[doorModel].openedByNpc then
				continue
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
			doorDebounces[closestDoor].openedByNpc = true
			Logger.debug(
				"NPC",
				string.format("%s requested door open: %s (distance %d)", npcModel.Name, closestDoor.Name, math.floor(closestDistance))
			)
			closestOpenDoorEvent:Fire()
		end
	end

	local function segmentDistanceToPoint(segmentStart, segmentEnd, point)
		local segment = segmentEnd - segmentStart
		local segmentLengthSquared = segment:Dot(segment)
		if segmentLengthSquared <= 0.0001 then
			return (point - segmentStart).Magnitude
		end

		local t = math.max(0, math.min(1, (point - segmentStart):Dot(segment) / segmentLengthSquared))
		local closest = segmentStart + segment * t
		return (point - closest).Magnitude, closest
	end

	local function tryOpenDoorsOnSegment(segmentStart, segmentEnd, floorName)
		if humanoid.Health <= 0 then
			return
		end

		if tick() - doorCacheLastUpdate > DOOR_CACHE_UPDATE_INTERVAL then
			rebuildDoorCache()
		end

		local bestDoor = nil
		local bestDoorEvent = nil
		local bestDoorDistance = math.huge
		local segmentMidY = (segmentStart.Y + segmentEnd.Y) * 0.5

		for _, doorModel in ipairs(doorCache) do
			if not doorModel or not doorModel.Parent then
				continue
			end

			local ok, pivot = pcall(function()
				return doorModel:GetPivot()
			end)
			local doorPos = ok and pivot and pivot.Position or nil
			if not doorPos then
				continue
			end

			if not doorMatchesFloor(doorModel, floorName) then
				continue
			end

			-- Only consider doors that are in the same vertical band as the path segment.
			if math.abs(doorPos.Y - segmentMidY) > DOOR_SEGMENT_HEIGHT_TOLERANCE then
				continue
			end

			local distanceToSegment = segmentDistanceToPoint(segmentStart, segmentEnd, doorPos)
			if distanceToSegment > DOOR_DETECTION_RADIUS then
				continue
			end

			if not doorDebounces[doorModel] then
				doorDebounces[doorModel] = {}
			end
			if doorDebounces[doorModel].openedByNpc then
				continue
			end

			local openState = getDoorOpenState(doorModel)
			if openState == true then
				continue
			end

			local lastTriggered = doorDebounces[doorModel].lastTriggeredTime or 0
			if tick() - lastTriggered < DOOR_DEBOUNCE_TIME then
				continue
			end

			local openDoorEvent = doorModel:FindFirstChild("OpenDoorEvent", true)
			if not openDoorEvent or not openDoorEvent:IsA("BindableEvent") then
				continue
			end

			if distanceToSegment < bestDoorDistance then
				bestDoor = doorModel
				bestDoorEvent = openDoorEvent
				bestDoorDistance = distanceToSegment
			end
		end

		if bestDoor and bestDoorEvent and bestDoorDistance <= DOOR_TRIGGER_DISTANCE then
			doorDebounces[bestDoor].lastTriggeredTime = tick()
			doorDebounces[bestDoor].openedByNpc = true
			Logger.debug("NPC", string.format("%s requested door open on segment: %s", npcModel.Name, bestDoor.Name))
			bestDoorEvent:Fire()
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
			Logger.warn("NPC", "Using legacy waypoint root Workspace.Waypoints")
			return legacy
		end

		Logger.warn("NPC", "No waypoint root found (NPC_Waypoints or Waypoints)")
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

		local buildingFolder = findChildAgnostic(root, buildingName)
		if not buildingFolder then
			Logger.warn("NPC", "Waypoint building folder not found: " .. tostring(buildingName))
			return {}
		end

		local eventFolder = findChildAgnostic(buildingFolder, eventType)
		if not eventFolder then
			Logger.warn("NPC", "Waypoint event folder not found: " .. tostring(eventType))
			return {}
		end

		local list = {}
		for _, descendant in ipairs(eventFolder:GetDescendants()) do
			if descendant:IsA("BasePart") then
				local n = parseWaypointIndex(descendant.Name)
				if n then
					table.insert(list, { index = n, part = descendant })
				end
			end
		end

		table.sort(list, function(a, b)
			return a.index < b.index
		end)

		if #list == 0 then
			Logger.warn(
				"NPC",
				string.format(
					"No waypoint parts found in %s/%s; expected names like Waypoint1, Waypoint2",
					buildingName,
					eventType
				)
			)
		end

		return list
	end

	-- ─── Movement ─────────────────────────────────────────────────────────────────

	local function moveTo(targetPos, offset, segmentStart, segmentEnd, segmentFloor)
		local effectiveOffset = offset or Vector3.zero
		local goal = targetPos + effectiveOffset
		local reached = false
		local stagnantTime = 0
		local lastPos = rootPart.Position

		-- Stable phase per NPC so each one nudges in a different direction when stuck.
		local nudgePhase = (math.abs(rootPart.Position.X * 0.73 + rootPart.Position.Z * 1.37) % 1) * (math.pi * 2)

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

			-- Anti-clumping: if this NPC is nearly static for some time, re-issue MoveTo with
			-- a small lateral nudge so congested groups can keep flowing.
			local moved = (rootPart.Position - lastPos).Magnitude
			if moved <= STUCK_MOVEMENT_EPSILON then
				stagnantTime += TICK_RATE
			else
				stagnantTime = 0
			end
			lastPos = rootPart.Position

			if stagnantTime >= STUCK_TIME_BEFORE_NUDGE then
				local phase = nudgePhase + elapsed * 2
				local nudge = Vector3.new(math.cos(phase), 0, math.sin(phase)) * STUCK_NUDGE_RADIUS
				goal = targetPos + effectiveOffset + nudge
				humanoid:MoveTo(goal)
				stagnantTime = 0
			end

			-- Check for doors only if they sit on the path segment between the current node and the next node.
			if segmentStart and segmentEnd then
				tryOpenDoorsOnSegment(segmentStart, segmentEnd, segmentFloor)
			else
				tryOpenNearbyDoors(segmentFloor)
			end

			task.wait(TICK_RATE)
			elapsed += TICK_RATE
		end

		conn:Disconnect()
		-- Timed out — nudge the goal once more and move on.
		humanoid:MoveTo(goal)
		return false
	end

	local function getRouteNodesForWaypoint(currentNode, waypointPos, buildingName, floorName)
		local sameFloorTarget = floorName and NodeGraph.getNearestNodeOnFloor(waypointPos, buildingName, floorName)
		local targetNode = sameFloorTarget or NodeGraph.getNearestNode(waypointPos, buildingName, floorName)
		if not targetNode then
			return nil, nil
		end

		local path = nil
		if currentNode then
			path = NodeGraph.findPathBetweenNodes(currentNode, targetNode, buildingName)
		end

		if not path or #path == 0 then
			path = { targetNode }
		end

		return path, targetNode
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

	local function resolveWaypointFloor(wp, fallbackFloor)
		local current = wp and wp.Parent
		while current do
			local floorNum = current.Name:match("^Floor(%d+)$")
			if floorNum then
				return "Floor" .. floorNum
			end
			current = current.Parent
		end

		return fallbackFloor
	end

	-- ─── Runner ───────────────────────────────────────────────────────────────────

	local function run()
		local buildingName = npcModel:GetAttribute("BuildingName")
		local eventType = npcModel:GetAttribute("EventType")
		local startDelay = npcModel:GetAttribute("StartDelay") or 0
		local rawOffset = npcModel:GetAttribute("PositionOffset")

		if not buildingName or not eventType then
			Logger.warn("NPC", "Missing BuildingName or EventType on " .. npcModel.Name)
			return
		end

		local offset
		if rawOffset then
			offset = rawOffset
		else
			-- Fallback spread so NPCs don't stack on tiny waypoints when PositionOffset isn't set.
			local seedA = math.abs(math.sin(rootPart.Position.X * 12.9898 + rootPart.Position.Z * 78.233) * 43758.5453)
			local seedB = math.abs(math.sin(rootPart.Position.X * 39.3467 + rootPart.Position.Z * 11.1351) * 96321.4242)
			local a = seedA - math.floor(seedA)
			local b = seedB - math.floor(seedB)
			local angle = a * math.pi * 2
			local radius = AUTO_OFFSET_RADIUS * (0.35 + (0.65 * b))
			offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		end

		if startDelay > 0 then
			task.wait(startDelay)
		end

		local waypoints = collectWaypoints(buildingName, eventType)

		if #waypoints == 0 then
			return
		end

		-- Start from nearest node to NPC
		local preferFloor = npcModel:GetAttribute("FloorName")
		local currentNode = NodeGraph.getNearestNodeOnFloor(rootPart.Position, buildingName, preferFloor)
		if not currentNode then
			currentNode = NodeGraph.getNearestNode(rootPart.Position, buildingName, preferFloor)
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
			local waypointFloor = resolveWaypointFloor(wp, preferFloor)

			local path, targetNode = getRouteNodesForWaypoint(currentNode, wp.Position, buildingName, waypointFloor)
			local usedNodeTraversal = path and #path > 0

			if path and #path > 0 then
				for i, nodeInst in ipairs(path) do
					if not npcModel.Parent or humanoid.Health <= 0 then
						return
					end

					local segmentStart = nil
					if i == 1 then
						segmentStart = rootPart.Position
					elseif path[i - 1] then
						segmentStart = path[i - 1].Position
					end

					local segmentFloor = NodeGraph.getPathFloor(nodeInst, buildingName) or waypointFloor or preferFloor
					moveTo(nodeInst.Position, offset, segmentStart, nodeInst.Position, segmentFloor)
				end
			else
				moveTo(wp.Position, offset, rootPart.Position, wp.Position, waypointFloor or preferFloor)
			end

			-- After traversing nodes, perform the waypoint-specific behavior
			if wpType == "Transit" then
				-- Transit is node-driven only. If there is no node path, skip direct waypoint movement.
				if not usedNodeTraversal then
					Logger.warn("NPC", string.format("Skipping direct Transit for %s: no node route to %s", npcModel.Name, wp.Name))
				end
			elseif wpType == "Hold" then
				handleHold(wp, offset)
			elseif wpType == "Finish" then
				if handleFinish(wp, offset) == false then
					return
				end
			else
				Logger.warn("NPC", "Unknown WaypointType " .. tostring(wpType) .. "; using Transit behavior")
				handleTransit(wp, offset)
			end

			-- Update currentNode to be the last reached targetNode (if available)
			if targetNode then
				currentNode = targetNode
			else
				-- if we couldn't resolve a node, attempt to re-resolve from the NPC position
				currentNode = NodeGraph.getNearestNodeOnFloor(rootPart.Position, buildingName, preferFloor) or NodeGraph.getNearestNode(rootPart.Position, buildingName, preferFloor)
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
