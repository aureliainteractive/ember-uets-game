-- NPCWaypointFollower (ModuleScript)
-- Location : ReplicatedStorage.Shared.Modules.NPCWaypointFollower
-- Purpose  : Centralized module for NPC waypoint pathing logic.
--
-- Key changes vs previous version
-- ────────────────────────────────
-- • getRouteNodesForWaypoint no longer constrains the target node to the NPC's
--   starting floor.  The A* in NodeGraph resolves the path naturally across
--   floors via Floor1u2 staircase folders.
-- • resolveWaypointFloor has been removed.  The active floor is now derived
--   from whichever node the NPC currently occupies (NodeGraph.getPathFloor).
-- • Transit waypoints now do a final precise step to the actual waypoint
--   position after graph traversal, so NPCs land exactly on their targets.
-- • segmentFloor for door detection is derived from the node being traversed;
--   staircase nodes (isTransitionNode = true) skip floor-based door filtering
--   so doors at staircase landings are not accidentally excluded.

local NPCWaypointFollower = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local Logger    = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))
local NodeGraph = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("NodeGraph"))

-- ─── Constants ────────────────────────────────────────────────────────────────

local ARRIVE_RADIUS    = 2.5   -- studs: "close enough" to a node / waypoint
local MOVETO_TIMEOUT   = 12    -- seconds before giving up on a single MoveTo call
local TICK_RATE        = 0.1   -- seconds between movement checks

local WALK_ANIM_R6  = "rbxassetid://180426354"
local WALK_ANIM_R15 = "rbxassetid://507777826"
local WALK_SPEED_THRESHOLD = 0.1

-- Door interaction
local DOOR_DETECTION_RADIUS      = 16
local DOOR_TRIGGER_DISTANCE      = 12
local DOOR_DEBOUNCE_TIME         = 1.5
local DOOR_SEGMENT_HEIGHT_TOLERANCE = 8

-- Crowd / anti-clumping
local AUTO_OFFSET_RADIUS          = 2.25
local STUCK_TIME_BEFORE_NUDGE     = 1.0
local STUCK_MOVEMENT_EPSILON      = 0.05
local STUCK_NUDGE_RADIUS          = 2.0

local PATHFINDING_TIMEOUT         = 6

-- ─── Global door cache ────────────────────────────────────────────────────────

local doorCache = {}
local doorCacheLastUpdate  = 0
local DOOR_CACHE_UPDATE_INTERVAL = 5

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
	if not floorName then return true end  -- nil = don't filter
	local doorFloor = doorModel and doorModel:GetAttribute("FloorName") or nil
	if not doorFloor then doorFloor = getDoorFloorName(doorModel) end
	return not doorFloor or doorFloor == floorName
end

local function normalizeName(value)
	return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

local function findChildAgnostic(parent, targetName)
	if not parent or not targetName then return nil end
	local exact = parent:FindFirstChild(targetName)
	if exact then return exact end
	local needle = normalizeName(targetName)
	for _, child in ipairs(parent:GetChildren()) do
		if normalizeName(child.Name) == needle then return child end
	end
	return nil
end

local function rebuildDoorCache()
	doorCache = {}

	local function ensureDoorPathProxy(doorModel)
		if not doorModel or not doorModel:IsA("Model") then return end
		local proxy = doorModel:FindFirstChild("DoorPathfindingProxy")
		if proxy and not proxy:IsA("BasePart") then
			proxy:Destroy()
			proxy = nil
		end

		if not proxy then
			proxy = Instance.new("Part")
			proxy.Name = "DoorPathfindingProxy"
			proxy.Anchored = true
			proxy.CanCollide = false
			proxy.CanQuery = true
			proxy.CanTouch = false
			proxy.Transparency = 1
			proxy.Parent = doorModel

			local modifier = Instance.new("PathfindingModifier")
			modifier.PassThrough = true
			modifier.Parent = proxy
		end

		local ok, cf = pcall(function() return doorModel:GetPivot() end)
		local size = doorModel:GetExtentsSize()
		if ok and cf then
			proxy.CFrame = cf
		end
		if size then
			local minSize = Vector3.new(2, 3, 2)
			local padded = size + Vector3.new(2, 2, 2)
			proxy.Size = Vector3.new(
				math.max(minSize.X, padded.X),
				math.max(minSize.Y, padded.Y),
				math.max(minSize.Z, padded.Z)
			)
		end
	end

	local function findDoorContainer(candidateModel)
		if not candidateModel or not candidateModel:IsA("Model") then return nil end
		local nested = candidateModel:FindFirstChild("DoorModel", true)
		if nested and nested:IsA("Model") then return nested end
		for _, m in ipairs(candidateModel:GetDescendants()) do
			if m:IsA("RemoteEvent") and m.Name == "ToggleDoor" then
				local mm = m
				while mm and not mm:IsA("Model") do mm = mm.Parent end
				if mm then return mm end
			end
		end
		return candidateModel
	end

	local seen = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant.GetAttribute and descendant:GetAttribute("DoorType") ~= nil then
			local modelAncestor = descendant
			while modelAncestor and not modelAncestor:IsA("Model") do
				modelAncestor = modelAncestor.Parent
			end
			local container = modelAncestor and findDoorContainer(modelAncestor) or nil
			if container and not seen[container] then
				container:SetAttribute("FloorName", getDoorFloorName(container))
				ensureDoorPathProxy(container)
				table.insert(doorCache, container)
				seen[container] = true
			end
		end
		if descendant:IsA("Model") and descendant.Name == "DoorModel" then
			local container = findDoorContainer(descendant)
			if container and not seen[container] then
				container:SetAttribute("FloorName", getDoorFloorName(container))
				ensureDoorPathProxy(container)
				table.insert(doorCache, container)
				seen[container] = true
			end
		end
		if descendant:IsA("RemoteEvent") and descendant.Name == "ToggleDoor" then
			local mm = descendant
			while mm and not mm:IsA("Model") do mm = mm.Parent end
			if mm and not seen[mm] then
				mm:SetAttribute("FloorName", getDoorFloorName(mm))
				ensureDoorPathProxy(mm)
				table.insert(doorCache, mm)
				seen[mm] = true
			end
		end
	end

	doorCacheLastUpdate = tick()
	Logger.debug("NPC", string.format("Door cache rebuilt with %d entries", #doorCache))
end

task.delay(0.5, rebuildDoorCache)
task.delay(1.5, function() if #doorCache == 0 then rebuildDoorCache() end end)
task.delay(4.0, function() if #doorCache == 0 then rebuildDoorCache() end end)

workspace.DescendantAdded:Connect(function(descendant)
	local shouldMark = false
	if descendant.GetAttribute and descendant:GetAttribute("DoorType") ~= nil then shouldMark = true end
	if descendant:IsA("Model") and descendant.Name == "DoorModel" then shouldMark = true end
	if descendant:IsA("RemoteEvent") and descendant.Name == "ToggleDoor" then shouldMark = true end
	if shouldMark then doorCacheLastUpdate = 0 end
end)

-- ─── Main Start Function ──────────────────────────────────────────────────────

function NPCWaypointFollower.start(npcModel)
	if not npcModel or not npcModel:IsA("Model") then
		Logger.warn("NPC", "start() expects a Model instance")
		return
	end

	local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
	local rootPart = npcModel:FindFirstChild("HumanoidRootPart")
	local started  = false

	if not humanoid or not rootPart then
		Logger.warn("NPC", "Missing Humanoid or HumanoidRootPart in " .. npcModel.Name)
		return
	end

	local doorDebounces = {}

	if #doorCache == 0 then rebuildDoorCache() end

	-- ─── Animation ────────────────────────────────────────────────────────────

	local function setupWalkAnimation()
		local animateScript = npcModel:FindFirstChild("Animate")
		if animateScript and animateScript:IsA("Script") and animateScript.Enabled then return nil end

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

		walkTrack.Looped   = true
		walkTrack.Priority = Enum.AnimationPriority.Movement

		task.spawn(function()
			while humanoid and humanoid.Parent do
				if humanoid.Health <= 0 then break end
				local velocity       = rootPart.AssemblyLinearVelocity
				local horizontalSpeed = math.sqrt(velocity.X ^ 2 + velocity.Z ^ 2)
				local movingThreshold = math.max(WALK_SPEED_THRESHOLD, humanoid.WalkSpeed * 0.25)
				if horizontalSpeed >= movingThreshold then
					if not walkTrack.IsPlaying then walkTrack:Play(0.15) end
				else
					if walkTrack.IsPlaying then walkTrack:Stop(0.15) end
				end
				task.wait(0.1)
			end
		end)

		humanoid.Died:Connect(function()
			if walkTrack.IsPlaying then walkTrack:Stop(0.1) end
		end)

		return walkTrack
	end

	-- ─── Door interaction ─────────────────────────────────────────────────────

	local function getDoorOpenState(doorModel)
		if not doorModel then return nil end
		local function checkBool(attr)
			local v = doorModel:GetAttribute(attr)
			if type(v) == "boolean" then return v end
			return nil
		end
		local isOpen = checkBool("IsOpen") or checkBool("Open") or checkBool("Opened")
		if isOpen ~= nil then return isOpen end
		local state = doorModel:GetAttribute("State")
		if type(state) == "string" then
			local s = state:lower()
			if s == "open" or s == "opened" then return true end
			if s == "closed" then return false end
		end
		return nil
	end

	-- Try to open the single closest eligible door within range.
	-- `floorName = nil` skips floor filtering (used for staircase segments).
	local function tryOpenNearbyDoors(floorName)
		if humanoid.Health <= 0 then return end
		local npcPos = rootPart.Position

		if tick() - doorCacheLastUpdate > DOOR_CACHE_UPDATE_INTERVAL then rebuildDoorCache() end

		local closestDoor      = nil
		local closestDistance  = math.huge
		local closestEvent     = nil

		for _, doorModel in ipairs(doorCache) do
			if not doorModel or not doorModel.Parent then continue end

			local ok, pivot = pcall(function() return doorModel:GetPivot() end)
			local doorPos   = ok and pivot and pivot.Position or nil
			if not doorPos then continue end

			local distance = (doorPos - npcPos).Magnitude
			if distance > DOOR_DETECTION_RADIUS then continue end
			if getDoorOpenState(doorModel) == true then continue end
			if not doorMatchesFloor(doorModel, floorName) then continue end

			if not doorDebounces[doorModel] then doorDebounces[doorModel] = {} end
			if doorDebounces[doorModel].openedByNpc then continue end

			local lastTriggered = doorDebounces[doorModel].lastTriggeredTime or 0
			if tick() - lastTriggered < DOOR_DEBOUNCE_TIME then continue end

			local openEvent = doorModel:FindFirstChild("OpenDoorEvent", true)
			if not openEvent or not openEvent:IsA("BindableEvent") then continue end

			if distance < closestDistance then
				closestDoor     = doorModel
				closestDistance = distance
				closestEvent    = openEvent
			end
		end

		if closestDoor and closestEvent and closestDistance <= DOOR_TRIGGER_DISTANCE then
			doorDebounces[closestDoor].lastTriggeredTime = tick()
			doorDebounces[closestDoor].openedByNpc = true
			Logger.debug("NPC", string.format(
				"%s requested door open: %s (%.0f studs)",
				npcModel.Name, closestDoor.Name, closestDistance
			))
			closestEvent:Fire()
		end
	end

	local function segmentDistanceToPoint(segStart, segEnd, point)
		local seg    = segEnd - segStart
		local lenSq  = seg:Dot(seg)
		if lenSq <= 0.0001 then return (point - segStart).Magnitude end
		local t = math.max(0, math.min(1, (point - segStart):Dot(seg) / lenSq))
		return (point - (segStart + seg * t)).Magnitude
	end

	local function tryOpenDoorsOnSegment(segStart, segEnd, floorName)
		if humanoid.Health <= 0 then return end
		if tick() - doorCacheLastUpdate > DOOR_CACHE_UPDATE_INTERVAL then rebuildDoorCache() end

		local segMidY    = (segStart.Y + segEnd.Y) * 0.5
		local bestDoor   = nil
		local bestEvent  = nil
		local bestDist   = math.huge

		for _, doorModel in ipairs(doorCache) do
			if not doorModel or not doorModel.Parent then continue end

			local ok, pivot = pcall(function() return doorModel:GetPivot() end)
			local doorPos   = ok and pivot and pivot.Position or nil
			if not doorPos then continue end

			if not doorMatchesFloor(doorModel, floorName) then continue end
			if math.abs(doorPos.Y - segMidY) > DOOR_SEGMENT_HEIGHT_TOLERANCE then continue end

			local dist = segmentDistanceToPoint(segStart, segEnd, doorPos)
			if dist > DOOR_DETECTION_RADIUS then continue end
			if getDoorOpenState(doorModel) == true then continue end

			if not doorDebounces[doorModel] then doorDebounces[doorModel] = {} end
			if doorDebounces[doorModel].openedByNpc then continue end

			local lastTriggered = doorDebounces[doorModel].lastTriggeredTime or 0
			if tick() - lastTriggered < DOOR_DEBOUNCE_TIME then continue end

			local openEvent = doorModel:FindFirstChild("OpenDoorEvent", true)
			if not openEvent or not openEvent:IsA("BindableEvent") then continue end

			if dist < bestDist then
				bestDoor  = doorModel
				bestEvent = openEvent
				bestDist  = dist
			end
		end

		if bestDoor and bestEvent and bestDist <= DOOR_TRIGGER_DISTANCE then
			doorDebounces[bestDoor].lastTriggeredTime = tick()
			doorDebounces[bestDoor].openedByNpc = true
			Logger.debug("NPC", string.format(
				"%s requested door open on segment: %s", npcModel.Name, bestDoor.Name
			))
			bestEvent:Fire()
		end
	end

	-- ─── Waypoint collection ──────────────────────────────────────────────────

	local function resolveWaypointsRoot()
		local preferred = workspace:FindFirstChild("NPC_Waypoints")
		if preferred then return preferred end
		local legacy = workspace:FindFirstChild("Waypoints")
		if legacy then Logger.warn("NPC", "Using legacy waypoint root Workspace.Waypoints") return legacy end
		Logger.warn("NPC", "No waypoint root found (NPC_Waypoints or Waypoints)")
		return nil
	end

	local function parseWaypointIndex(name)
		return tonumber(name:match("^Waypoint[_%-]?(%d+)$")) or tonumber(name:match("^WP(%d+)$"))
	end

	local function resolveWaypointFloorName(waypointPart)
		if not waypointPart then return nil end
		local current = waypointPart
		while current do
			local attr = current:GetAttribute("FloorName")
			if type(attr) == "string" and attr ~= "" then
				return attr
			end
			local n = current.Name
			local num = n:match("^[Ff]loor(%d+)$")
			if num then
				return "Floor" .. num
			end
			current = current.Parent
		end
		return nil
	end

	local function collectWaypoints(buildingName, eventType)
		local root = resolveWaypointsRoot()
		if not root then return {} end

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
					local floorName = resolveWaypointFloorName(descendant)
					table.insert(list, { index = n, part = descendant, floorName = floorName })
				end
			end
		end

		table.sort(list, function(a, b) return a.index < b.index end)

		if #list == 0 then
			Logger.warn("NPC", string.format(
				"No waypoint parts in %s/%s — expected Waypoint1, Waypoint2 …",
				buildingName, eventType
			))
		end

		return list
	end

	-- ─── Movement ─────────────────────────────────────────────────────────────

	local function moveTo(targetPos, offset, segmentStart, segmentEnd, floorName, debugLabel)
		local effectiveOffset = offset or Vector3.zero
		local goal    = targetPos + effectiveOffset
		local reached = false

		local stagnantTime = 0
		local lastPos      = rootPart.Position
		local nudgePhase   = (math.abs(rootPart.Position.X * 0.73 + rootPart.Position.Z * 1.37) % 1) * (math.pi * 2)

		local conn = humanoid.MoveToFinished:Connect(function(didReach)
			if didReach then reached = true end
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

			-- Door detection: use segment when available, otherwise proximity scan
			if segmentStart and segmentEnd then
				tryOpenDoorsOnSegment(segmentStart, segmentEnd, floorName)
			else
				tryOpenNearbyDoors(floorName)
			end

			task.wait(TICK_RATE)
			elapsed += TICK_RATE
		end

		conn:Disconnect()
		humanoid:MoveTo(goal)
		if debugLabel then
			Logger.debug("NPC", string.format(
				"%s: MoveTo timeout (%s) goal=(%.1f, %.1f, %.1f)",
				npcModel.Name, debugLabel, goal.X, goal.Y, goal.Z
			))
		end
		return false
	end

	local function moveUsingPathfinding(targetPos, offset, floorName)
		local effectiveOffset = offset or Vector3.zero
		local goal = targetPos + effectiveOffset
		local deadline = tick() + PATHFINDING_TIMEOUT
		local startPos = rootPart.Position

		Logger.debug("NPC", string.format(
			"%s: pathfinding from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f)",
			npcModel.Name, startPos.X, startPos.Y, startPos.Z, goal.X, goal.Y, goal.Z
		))

		while tick() < deadline do
			if humanoid.Health <= 0 or not npcModel.Parent then return false end

			local path = PathfindingService:CreatePath()
			local ok, err = pcall(function()
				path:ComputeAsync(rootPart.Position, goal)
			end)
			if not ok or path.Status ~= Enum.PathStatus.Success then
				Logger.debug("NPC", string.format(
					"%s: pathfinding failed (%s) status=%s; falling back to direct move",
					npcModel.Name, tostring(err), tostring(path.Status)
				))
				return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "path-fallback")
			end

			local waypoints = path:GetWaypoints()
			if #waypoints == 0 then
				Logger.debug("NPC", string.format(
					"%s: path computed but returned 0 waypoints; falling back to direct move",
					npcModel.Name
				))
				return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "path-empty")
			end

			Logger.debug("NPC", string.format(
				"%s: path ok with %d waypoints (status=%s)",
				npcModel.Name, #waypoints, tostring(path.Status)
			))

			local nextWaypointIndex = 2
			local blockedAhead = false
			local blockedConn = path.Blocked:Connect(function(blockedIndex)
				if blockedIndex >= nextWaypointIndex then
					blockedAhead = true
				end
			end)

			local prevPos = rootPart.Position
			while nextWaypointIndex <= #waypoints do
				if humanoid.Health <= 0 or not npcModel.Parent then
					blockedConn:Disconnect()
					return false
				end
				if blockedAhead then break end

				local wp = waypoints[nextWaypointIndex]
				if wp.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				local isLast = (nextWaypointIndex == #waypoints)
				local wpOffset = isLast and offset or nil
				local okMove = moveTo(wp.Position, wpOffset, prevPos, wp.Position, floorName, "path-segment")
				if not okMove then
					Logger.debug("NPC", string.format(
						"%s: moveTo waypoint %d failed; pos=(%.1f, %.1f, %.1f)",
						npcModel.Name, nextWaypointIndex, wp.Position.X, wp.Position.Y, wp.Position.Z
					))
				end
				prevPos = wp.Position
				nextWaypointIndex += 1
			end

			blockedConn:Disconnect()
			if not blockedAhead then
				return true
			end
		end

		return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "path-timeout")
	end

	-- ─── Pathfinding helpers ──────────────────────────────────────────────────

	-- Returns (path, targetNode) where path is an ordered list of node BaseParts.
	-- The target node is the nearest node to the waypoint in ANY floor — the A*
	-- in NodeGraph handles floor transitions via Floor1u2 staircase nodes.
	local function getRouteToPosition(currentNode, targetPos, buildingName, waypointFloor)
		local targetNode
		if waypointFloor then
			targetNode = NodeGraph.getNearestNodeOnFloor(targetPos, buildingName, waypointFloor)
		else
			targetNode = NodeGraph.getNearestNode(targetPos, buildingName)
		end
		if not targetNode then return nil, nil end

		local path = nil
		if currentNode then
			path = NodeGraph.findPathBetweenNodes(currentNode, targetNode, buildingName)
		end

		if not path or #path == 0 then
			path = { targetNode }
		end

		return path, targetNode
	end

	-- ─── Waypoint behaviour handlers ─────────────────────────────────────────

	local function handleHold(wp, offset, floorName)
		moveUsingPathfinding(wp.Position, offset, floorName)
		if humanoid.Health <= 0 then return end
		local holdDuration = wp:GetAttribute("HoldDuration") or 3
		local held = 0
		while held < holdDuration do
			humanoid:MoveTo(wp.Position + (offset or Vector3.zero))
			local step = math.min(1, holdDuration - held)
			task.wait(step)
			held += step
		end
	end

	local function handleFinish(wp, offset, floorName)
		moveUsingPathfinding(wp.Position, offset, floorName)
		task.spawn(function()
			local finalPos = wp.Position + (offset or Vector3.zero)
			while npcModel.Parent and humanoid.Health > 0 do
				humanoid:MoveTo(finalPos)
				task.wait(1)
			end
		end)
		return false  -- signals run() to stop iterating
	end

	-- ─── Main runner ──────────────────────────────────────────────────────────

	local function run()
		local buildingName  = npcModel:GetAttribute("BuildingName")
		local eventType     = npcModel:GetAttribute("EventType")
		local startDelay    = npcModel:GetAttribute("StartDelay") or 0
		local rawOffset     = npcModel:GetAttribute("PositionOffset")
		local preferFloor   = npcModel:GetAttribute("FloorName")

		if not buildingName or not eventType then
			Logger.warn("NPC", "Missing BuildingName or EventType on " .. npcModel.Name)
			return
		end

		-- Per-NPC lateral spread (prevents clumping on waypoints)
		local offset
		if rawOffset then
			offset = rawOffset
		else
			local seedA = math.abs(math.sin(rootPart.Position.X * 12.9898 + rootPart.Position.Z * 78.233) * 43758.5453)
			local seedB = math.abs(math.sin(rootPart.Position.X * 39.3467 + rootPart.Position.Z * 11.1351) * 96321.4242)
			local a     = seedA - math.floor(seedA)
			local b     = seedB - math.floor(seedB)
			local angle  = a * math.pi * 2
			local radius = AUTO_OFFSET_RADIUS * (0.35 + 0.65 * b)
			offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
		end

		if startDelay > 0 then task.wait(startDelay) end

		local waypoints = collectWaypoints(buildingName, eventType)
		if #waypoints == 0 then return end

		-- Seed currentNode from the NPC's starting floor
		local currentNode = NodeGraph.getNearestNodeOnFloor(rootPart.Position, buildingName, preferFloor)
		if not currentNode then
			currentNode = NodeGraph.getNearestNode(rootPart.Position, buildingName)
		end

		-- First leg: pathfind from spawn to the initial node
		if currentNode and (rootPart.Position - currentNode.Position).Magnitude > ARRIVE_RADIUS then
			moveUsingPathfinding(currentNode.Position, offset, preferFloor)
		end

		-- ── Waypoint loop ───────────────────────────────────────────────────────

		for _, entry in ipairs(waypoints) do
			if not npcModel.Parent then return end
			if humanoid.Health <= 0 then return end

			local wp     = entry.part
			local wpType = wp:GetAttribute("WaypointType") or "Transit"
			local wpFloor = entry.floorName

			-- Resolve path from currentNode to the nearest node to this waypoint.
			-- No floor constraint on the target — the graph routes across floors
			-- automatically through Floor1u2 staircase nodes.
			local path, targetNode = getRouteToPosition(currentNode, wp.Position, buildingName, wpFloor)

			-- Walk the node path
			if path and #path > 0 then
				for i, nodeInst in ipairs(path) do
					if not npcModel.Parent or humanoid.Health <= 0 then return end

					local segStart = (i == 1) and rootPart.Position or path[i - 1].Position

					-- Floor for door detection: nil on staircase nodes so all
					-- nearby doors are considered (stairs can have doors too)
					local segFloor
					if NodeGraph.isTransitionNode(nodeInst, buildingName) then
						segFloor = nil
					else
						segFloor = NodeGraph.getPathFloor(nodeInst, buildingName) or preferFloor
					end

					moveTo(nodeInst.Position, offset, segStart, nodeInst.Position, segFloor)
				end
			else
				-- No graph path: move directly (last-resort fallback)
				Logger.warn("NPC", string.format(
					"%s: no graph path to %s — falling back to direct movement",
					npcModel.Name, wp.Name
				))
				moveTo(wp.Position, offset, rootPart.Position, wp.Position, preferFloor)
			end

			-- Derive the floor at the end of this segment
			local arrivalFloor = wpFloor
				or (targetNode and NodeGraph.getPathFloor(targetNode, buildingName))
				or preferFloor

			-- Waypoint-specific behaviour after graph traversal
			if wpType == "Hold" then
				handleHold(wp, offset, arrivalFloor)
			elseif wpType == "Finish" then
				if handleFinish(wp, offset, arrivalFloor) == false then return end
			else
				-- Transit (default): do a final precise step to the waypoint position.
				-- The node path brings NPCs close; this step lands them exactly on target.
				moveUsingPathfinding(wp.Position, offset, arrivalFloor)
			end

			-- Advance currentNode for the next iteration
			if targetNode then
				currentNode = targetNode
			else
				-- Re-anchor to nearest node from current position
				currentNode = NodeGraph.getNearestNodeOnFloor(rootPart.Position, buildingName, arrivalFloor)
					or NodeGraph.getNearestNode(rootPart.Position, buildingName)
			end
		end
	end

	-- ─── Kickoff ──────────────────────────────────────────────────────────────

	if started then return end
	started = true
	npcModel:SetAttribute("PathingStarted", true)

	setupWalkAnimation()
	task.spawn(run)
end

-- Allow manual cache rebuild from the Command Bar:
-- require(game.ReplicatedStorage.Shared.Modules.NPCWaypointFollower).rebuildDoorCache()
NPCWaypointFollower.rebuildDoorCache = rebuildDoorCache

return NPCWaypointFollower