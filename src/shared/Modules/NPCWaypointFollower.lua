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
-- • NPCs now follow the route contract:
--   Spawn -> first node via PathfindingService, node chain via MoveTo,
--   nearest node -> first waypoint via PathfindingService, remaining waypoints
--   via MoveTo.
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
local MOVETO_TIMEOUT   = 20    -- max seconds before giving up on a single MoveTo call
local TICK_RATE        = 0.1   -- seconds between movement checks

local WALK_ANIM_R6  = "rbxassetid://180426354"
local WALK_ANIM_R15 = "rbxassetid://507777826"
local WALK_SPEED_THRESHOLD = 0.1

-- Door interaction
local DOOR_DETECTION_RADIUS      = 10
local DOOR_TRIGGER_DISTANCE      = 6
local DOOR_DEBOUNCE_TIME         = 1.5
local DOOR_SEGMENT_HEIGHT_TOLERANCE = 8
local DOOR_ROUTE_SEARCH_RADIUS   = 18

-- Crowd / anti-clumping
local AUTO_OFFSET_RADIUS          = 2.25
local STUCK_TIME_BEFORE_NUDGE     = 1.0
local STUCK_MOVEMENT_EPSILON      = 0.05
local STUCK_NUDGE_RADIUS          = 0.75

local PATHFINDING_TIMEOUT         = 18
local MAX_CONCURRENT_PATHS        = 8
local PATHFINDING_SLOT_LOG_DELAY  = 1.5
local PATH_CACHE_TTL              = 120
local MAX_PATH_WAYPOINTS          = 90
local MAX_SPAWN_PATH_WAYPOINTS    = 90

-- ─── Global door cache ────────────────────────────────────────────────────────

local doorCache = {}
local doorCacheLastUpdate  = 0
local doorCacheRebuilding = false
local DOOR_CACHE_UPDATE_INTERVAL = 30
local activePathComputes = 0
local pathCache = {}
local fallbackNpcDebugCounter = 0

local function isLikelyFloorName(name)
	local text = tostring(name or "")
	return text:match("^[Ff]loor%d+") ~= nil or text:match("^[Pp]iso%d+") ~= nil
end

local function getDoorFloorName(doorModel)
	local current = doorModel
	while current do
		if current.Parent and current.Parent.Name == "Doors" then
			if current ~= doorModel or isLikelyFloorName(current.Name) then
				return current.Name
			end
			return nil
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

local function quantizeCoord(value, step)
	return math.floor((value / step) + 0.5) * step
end

local function makePathCacheKey(fromPos, toPos, floorName, explicitKey)
	local step = 10
	if explicitKey and explicitKey ~= "" then
		return table.concat({
			explicitKey,
			quantizeCoord(fromPos.X, step),
			quantizeCoord(fromPos.Y, step),
			quantizeCoord(fromPos.Z, step),
			quantizeCoord(toPos.X, step),
			quantizeCoord(toPos.Y, step),
			quantizeCoord(toPos.Z, step),
		}, "|")
	end

	return table.concat({
		tostring(floorName or "any"),
		quantizeCoord(fromPos.X, step),
		quantizeCoord(fromPos.Y, step),
		quantizeCoord(fromPos.Z, step),
		quantizeCoord(toPos.X, step),
		quantizeCoord(toPos.Y, step),
		quantizeCoord(toPos.Z, step),
	}, "|")
end

local function serializeWaypoints(waypoints)
	local result = {}
	for index, waypoint in ipairs(waypoints) do
		result[index] = {
			position = waypoint.Position,
			action = waypoint.Action,
		}
	end
	return result
end

local function getDoorPosition(doorModel)
	if not doorModel or not doorModel.Parent then
		return nil
	end

	local proxy = doorModel:FindFirstChild("DoorPathfindingProxy", true)
	if proxy and proxy:IsA("BasePart") then
		return proxy.Position
	end

	local doorPart = doorModel:FindFirstChild("Door", true)
	if doorPart and doorPart:IsA("BasePart") then
		return doorPart.Position
	end

	local ok, pivot = pcall(function()
		return doorModel:GetPivot()
	end)
	if ok and pivot then
		return pivot.Position
	end

	return nil
end

local function rebuildDoorCache()
	if doorCacheRebuilding then return end
	doorCacheRebuilding = true
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
			modifier.Label = "DoorPass"
			modifier.PassThrough = true
			modifier.Parent = proxy
		end

		local doorPart = doorModel:FindFirstChild("Door", true)
		if doorPart and doorPart:IsA("BasePart") then
			proxy.CFrame = doorPart.CFrame
			proxy.Size = doorPart.Size + Vector3.new(1, 1, 1)
			return
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

	local function ensureDoorPassThroughParts(doorModel)
		if not doorModel or not doorModel:IsA("Model") then return end
		for _, part in ipairs(doorModel:GetDescendants()) do
			if part:IsA("BasePart") then
				local modifier = part:FindFirstChild("DoorPathfindingModifier")
				if not modifier then
					modifier = Instance.new("PathfindingModifier")
					modifier.Name = "DoorPathfindingModifier"
					modifier.Label = "DoorPass"
					modifier.PassThrough = true
					modifier.Parent = part
				end
			end
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
				ensureDoorPassThroughParts(container)
				table.insert(doorCache, container)
				seen[container] = true
			end
		end
		if descendant:IsA("Model") and descendant.Name == "DoorModel" then
			local container = findDoorContainer(descendant)
			if container and not seen[container] then
				container:SetAttribute("FloorName", getDoorFloorName(container))
				ensureDoorPathProxy(container)
				ensureDoorPassThroughParts(container)
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
				ensureDoorPassThroughParts(mm)
				table.insert(doorCache, mm)
				seen[mm] = true
			end
		end
	end

	doorCacheLastUpdate = tick()
	doorCacheRebuilding = false
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

	if not npcModel:GetAttribute("NPCDebugId") then
		fallbackNpcDebugCounter += 1
		local debugId = string.format("manual-%04d", fallbackNpcDebugCounter)
		npcModel:SetAttribute("NPCDebugId", debugId)
		npcModel.Name = string.format("%s_%s", npcModel.Name, debugId)
	end

	-- Ensure the humanoid can actually move
	if rootPart.Anchored then rootPart.Anchored = false end
	if humanoid.PlatformStand then humanoid.PlatformStand = false end
	if humanoid.Sit then humanoid.Sit = false end
	if humanoid.AutoRotate == false then humanoid.AutoRotate = true end
	if humanoid.WalkSpeed <= 0 then humanoid.WalkSpeed = 10 end

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
	local function requestDoorOpen(doorModel, reason)
		if not doorModel or not doorModel.Parent then
			return false
		end
		if getDoorOpenState(doorModel) == true then
			return true
		end

		if not doorDebounces[doorModel] then doorDebounces[doorModel] = {} end
		local lastTriggered = doorDebounces[doorModel].lastTriggeredTime or 0
		if tick() - lastTriggered < DOOR_DEBOUNCE_TIME then
			return true
		end

		local openEvent = doorModel:FindFirstChild("OpenDoorEvent", true)
		if not openEvent or not openEvent:IsA("BindableEvent") then
			return false
		end

		doorDebounces[doorModel].lastTriggeredTime = tick()
		doorDebounces[doorModel].openedByNpc = true
		Logger.debug("NPC", string.format(
			"%s requested door open%s: %s",
			npcModel.Name,
			reason and (" (" .. reason .. ")") or "",
			doorModel.Name
		))
		openEvent:Fire()
		return true
	end

	local function tryOpenNearbyDoors(floorName)
		if humanoid.Health <= 0 then return end
		local npcPos = rootPart.Position

		if tick() - doorCacheLastUpdate > DOOR_CACHE_UPDATE_INTERVAL then rebuildDoorCache() end

		local closestDoor      = nil
		local closestDistance  = math.huge
		local closestEvent     = nil

		for _, doorModel in ipairs(doorCache) do
			if not doorModel or not doorModel.Parent then continue end

			local doorPos = getDoorPosition(doorModel)
			if not doorPos then continue end

			local distance = (doorPos - npcPos).Magnitude
			if distance > DOOR_DETECTION_RADIUS then continue end
			if getDoorOpenState(doorModel) == true then continue end
			if not doorMatchesFloor(doorModel, floorName) then continue end

			local openEvent = doorModel:FindFirstChild("OpenDoorEvent", true)
			if not openEvent or not openEvent:IsA("BindableEvent") then continue end

			if distance < closestDistance then
				closestDoor     = doorModel
				closestDistance = distance
				closestEvent    = openEvent
			end
		end

		if closestDoor and closestEvent and closestDistance <= DOOR_TRIGGER_DISTANCE then
			requestDoorOpen(closestDoor, string.format("%.0f studs", closestDistance))
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

			local doorPos = getDoorPosition(doorModel)
			if not doorPos then continue end

			if not doorMatchesFloor(doorModel, floorName) then continue end
			if math.abs(doorPos.Y - segMidY) > DOOR_SEGMENT_HEIGHT_TOLERANCE then continue end

			local dist = segmentDistanceToPoint(segStart, segEnd, doorPos)
			if dist > DOOR_DETECTION_RADIUS then continue end
			if getDoorOpenState(doorModel) == true then continue end

			local openEvent = doorModel:FindFirstChild("OpenDoorEvent", true)
			if not openEvent or not openEvent:IsA("BindableEvent") then continue end

			if dist < bestDist then
				bestDoor  = doorModel
				bestEvent = openEvent
				bestDist  = dist
			end
		end

		if bestDoor and bestEvent and bestDist <= DOOR_TRIGGER_DISTANCE then
			requestDoorOpen(bestDoor, "segment")
		end
	end

	local function findDoorGatewayBetween(fromPos, toPos, floorName)
		if tick() - doorCacheLastUpdate > DOOR_CACHE_UPDATE_INTERVAL then rebuildDoorCache() end

		local bestDoor = nil
		local bestScore = math.huge
		local midpoint = (fromPos + toPos) * 0.5
		local segMidY = midpoint.Y

		for _, doorModel in ipairs(doorCache) do
			if not doorModel or not doorModel.Parent then continue end
			if not doorMatchesFloor(doorModel, floorName) then continue end

			local doorPos = getDoorPosition(doorModel)
			if not doorPos then continue end
			if math.abs(doorPos.Y - segMidY) > DOOR_SEGMENT_HEIGHT_TOLERANCE * 2 then continue end

			local segmentDist = segmentDistanceToPoint(fromPos, toPos, doorPos)
			local endpointDist = math.min((doorPos - fromPos).Magnitude, (doorPos - toPos).Magnitude)
			if segmentDist > DOOR_ROUTE_SEARCH_RADIUS and endpointDist > DOOR_ROUTE_SEARCH_RADIUS then
				continue
			end

			local score = segmentDist * 2 + (doorPos - midpoint).Magnitude * 0.25 + endpointDist * 0.1
			if score < bestScore then
				bestScore = score
				bestDoor = doorModel
			end
		end

		return bestDoor, bestDoor and getDoorPosition(bestDoor) or nil
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
		local finalGoal = targetPos + effectiveOffset
		local commandedGoal = finalGoal
		local reached = false

		local stagnantTime = 0
		local lastPos      = rootPart.Position
		local nudgePhase   = (math.abs(rootPart.Position.X * 0.73 + rootPart.Position.Z * 1.37) % 1) * (math.pi * 2)

		local conn = humanoid.MoveToFinished:Connect(function(didReach)
			if didReach then reached = true end
		end)

		humanoid:MoveTo(commandedGoal)

		local distance = (rootPart.Position - finalGoal).Magnitude
		local speed = math.max(humanoid.WalkSpeed, 1)
		local timeout = math.clamp(distance / speed + 3, 4, MOVETO_TIMEOUT)
		local elapsed = 0
		while elapsed < timeout do
			if humanoid.Health <= 0 then
				conn:Disconnect()
				return false
			end
			if reached or (rootPart.Position - finalGoal).Magnitude <= ARRIVE_RADIUS then
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
				local nudgedGoal = finalGoal + nudge
				if NodeGraph.isSegmentNavigable(rootPart.Position, nudgedGoal, { npcModel }) then
					commandedGoal = nudgedGoal
				else
					commandedGoal = finalGoal
				end
				humanoid:MoveTo(commandedGoal)
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
		humanoid:MoveTo(finalGoal)
		if debugLabel then
			Logger.debug("NPC", string.format(
				"%s: MoveTo timeout (%s) goal=(%.1f, %.1f, %.1f) current=(%.1f, %.1f, %.1f)",
				npcModel.Name,
				debugLabel,
				finalGoal.X,
				finalGoal.Y,
				finalGoal.Z,
				rootPart.Position.X,
				rootPart.Position.Y,
				rootPart.Position.Z
			))
		end
		return false
	end

	local function moveUsingPathfinding(targetPos, offset, floorName, allowFallback, explicitCacheKey, maxWaypoints)
		local effectiveOffset = offset or Vector3.zero
		local goal = targetPos + effectiveOffset
		local deadline = tick() + PATHFINDING_TIMEOUT
		local startPos = rootPart.Position
		local canFallback = (allowFallback ~= false)
		local cacheKey = makePathCacheKey(startPos, goal, floorName, explicitCacheKey)
		local waypointLimit = maxWaypoints or MAX_PATH_WAYPOINTS

		if NodeGraph.isSegmentNavigable(rootPart.Position, goal, { npcModel }) then
			return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "direct-visible")
		end

		Logger.debug("NPC", string.format(
			"%s: pathfinding from (%.1f, %.1f, %.1f) to (%.1f, %.1f, %.1f)",
			npcModel.Name, startPos.X, startPos.Y, startPos.Z, goal.X, goal.Y, goal.Z
		))

		local function canUseDirectFallback()
			return NodeGraph.isSegmentNavigable(rootPart.Position, goal, { npcModel })
		end

		local function followCachedWaypoints(points, debugLabel)
			local prevPos = rootPart.Position
			for nextWaypointIndex = 2, #points do
				if humanoid.Health <= 0 or not npcModel.Parent then return false end

				local wp = points[nextWaypointIndex]
				if wp.action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				local isLast = (nextWaypointIndex == #points)
				local wpOffset = isLast and offset or nil
				if not moveTo(wp.position, wpOffset, prevPos, wp.position, floorName, debugLabel) then
					pathCache[cacheKey] = nil
					return false
				end
				prevPos = wp.position
			end
			return true
		end

		local cached = pathCache[cacheKey]
		if cached and cached.status == "success" and tick() - cached.updatedAt <= PATH_CACHE_TTL then
			Logger.debug("NPC", string.format("%s: using cached path with %d waypoints", npcModel.Name, #cached.points))
			return followCachedWaypoints(cached.points, "cached-path")
		end

		if cached and cached.status == "computing" then
			local nextWaitLog = tick()
			while tick() < deadline do
				local latest = pathCache[cacheKey]
				if not latest or latest.status ~= "computing" then
					if latest and latest.status == "success" and tick() - latest.updatedAt <= PATH_CACHE_TTL then
						Logger.debug("NPC", string.format("%s: using shared path with %d waypoints", npcModel.Name, #latest.points))
						return followCachedWaypoints(latest.points, "shared-path")
					end
					break
				end
				if tick() >= nextWaitLog then
					Logger.debug("NPC", string.format("%s: waiting for shared path", npcModel.Name))
					nextWaitLog = tick() + PATHFINDING_SLOT_LOG_DELAY
				end
				task.wait(0.1)
			end
		end

		pathCache[cacheKey] = {
			status = "computing",
			updatedAt = tick(),
		}

		while tick() < deadline do
			if humanoid.Health <= 0 or not npcModel.Parent then return false end

			local nextWaitLog = tick()
			local loggedWait = false
			while activePathComputes >= MAX_CONCURRENT_PATHS do
				if not loggedWait or tick() >= nextWaitLog then
					Logger.debug("NPC", string.format(
						"%s: waiting for pathfinding slot (%d/%d)",
						npcModel.Name, activePathComputes, MAX_CONCURRENT_PATHS
					))
					loggedWait = true
					nextWaitLog = tick() + PATHFINDING_SLOT_LOG_DELAY
				end
				if tick() >= deadline then
					if canFallback and canUseDirectFallback() then
						return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "path-slot-deadline")
					end
					pathCache[cacheKey] = nil
					return false
				end
				task.wait(0.1)
			end

			activePathComputes += 1
			local released = false
			local function releaseSlot()
				if released then return end
				released = true
				activePathComputes = math.max(0, activePathComputes - 1)
			end
			local agentRadiusRaw = (rootPart.Size.X + rootPart.Size.Z) * 0.25
			local agentRadius = math.clamp(agentRadiusRaw, 1.5, 2.5)
			local agentHeightRaw = humanoid.HipHeight * 2 + 2
			local agentHeight = math.clamp(agentHeightRaw, 5, 6)
			local path = PathfindingService:CreatePath({
				AgentRadius = agentRadius,
				AgentHeight = agentHeight,
				AgentCanJump = true,
				AgentCanClimb = true,
				WaypointSpacing = 4,
				Costs = {
					DoorPass = 1,
				},
			})
			local ok, err = pcall(function()
				path:ComputeAsync(rootPart.Position, goal)
			end)
			releaseSlot()

			if not ok or path.Status ~= Enum.PathStatus.Success then
				Logger.debug("NPC", string.format(
					"%s: pathfinding failed (%s) status=%s%s",
					npcModel.Name,
					tostring(err),
					tostring(path.Status),
					canFallback and "; falling back to direct move" or "; strict mode"
				))
				if canFallback then
					if canUseDirectFallback() then
						pathCache[cacheKey] = nil
						return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "path-fallback")
					end
					pathCache[cacheKey] = nil
					return false
				end
				pathCache[cacheKey] = nil
				return false
			end

			local waypoints = path:GetWaypoints()
			if #waypoints == 0 then
				Logger.debug("NPC", string.format(
					"%s: path computed but returned 0 waypoints%s",
					npcModel.Name,
					canFallback and "; falling back to direct move" or "; strict mode"
				))
				if canFallback then
					if canUseDirectFallback() then
						pathCache[cacheKey] = nil
						return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "path-empty")
					end
					pathCache[cacheKey] = nil
					return false
				end
				pathCache[cacheKey] = nil
				return false
			end

			if #waypoints > waypointLimit then
				Logger.debug("NPC", string.format(
					"%s: path rejected with %d waypoints (limit=%d)",
					npcModel.Name, #waypoints, waypointLimit
				))
				pathCache[cacheKey] = nil
				return false
			end

			Logger.debug("NPC", string.format(
				"%s: path ok with %d waypoints (status=%s)",
				npcModel.Name, #waypoints, tostring(path.Status)
			))
			pathCache[cacheKey] = {
				status = "success",
				updatedAt = tick(),
				points = serializeWaypoints(waypoints),
			}

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
					blockedConn:Disconnect()
					pathCache[cacheKey] = nil
					return false
				end
				prevPos = wp.Position
				nextWaypointIndex += 1
			end

			blockedConn:Disconnect()
			if not blockedAhead then
				return true
			end
		end

		if canFallback then
			if canUseDirectFallback() then
				pathCache[cacheKey] = nil
				return moveTo(targetPos, offset, rootPart.Position, goal, floorName, "path-timeout")
			end
			pathCache[cacheKey] = nil
			return false
		end
		pathCache[cacheKey] = nil
		Logger.warn("NPC", string.format(
			"%s: pathfinding timed out; strict mode stop",
			npcModel.Name
		))
		return false
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

	local function moveAlongNodePath(path, buildingName, preferFloor, offset)
		if not path or #path == 0 then
			return true
		end

		for i, nodeInst in ipairs(path) do
			if not npcModel.Parent or humanoid.Health <= 0 then
				return false
			end

			local segStart = (i == 1) and rootPart.Position or path[i - 1].Position

			local segFloor
			if NodeGraph.isTransitionNode(nodeInst, buildingName) then
				segFloor = nil
			else
				segFloor = NodeGraph.getPathFloor(nodeInst, buildingName) or preferFloor
			end

			if not moveTo(nodeInst.Position, offset, segStart, nodeInst.Position, segFloor, "node-chain") then
				return false
			end
		end

		return true
	end

	local function moveDirectlyToWaypoint(wp, offset, debugLabel)
		local goal = wp.Position + (offset or Vector3.zero)
		if NodeGraph.isSegmentNavigable(rootPart.Position, goal, { npcModel }) then
			return moveTo(wp.Position, offset, rootPart.Position, wp.Position, nil, debugLabel)
		end

		return moveUsingPathfinding(
			wp.Position,
			offset,
			nil,
			true,
			string.format("waypoint:%s:%s", tostring(npcModel:GetAttribute("BuildingName")), wp:GetFullName()),
			MAX_PATH_WAYPOINTS
		)
	end

	local function holdAtWaypoint(wp, offset)
		if humanoid.Health <= 0 then return false end
		local holdDuration = wp:GetAttribute("HoldDuration") or 3
		local finalPos = wp.Position + (offset or Vector3.zero)
		local held = 0
		while held < holdDuration do
			if not npcModel.Parent or humanoid.Health <= 0 then
				return false
			end
			humanoid:MoveTo(finalPos)
			local step = math.min(1, holdDuration - held)
			task.wait(step)
			held += step
		end
		return true
	end

	local function stayAtFinishWaypoint(wp, offset)
		task.spawn(function()
			local finalPos = wp.Position + (offset or Vector3.zero)
			while npcModel.Parent and humanoid.Health > 0 do
				humanoid:MoveTo(finalPos)
				task.wait(1)
			end
		end)
	end

	-- ─── Main runner ──────────────────────────────────────────────────────────

	local function run()
		local buildingName  = npcModel:GetAttribute("BuildingName")
		local eventType     = npcModel:GetAttribute("EventType")
		local startDelay    = npcModel:GetAttribute("StartDelay") or 0
		local rawOffset     = npcModel:GetAttribute("PositionOffset")
		local preferFloor   = npcModel:GetAttribute("FloorName")
		local spawnKey      = npcModel:GetAttribute("SpawnPointKey")

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

		local firstEntry = waypoints[1]
		local firstWaypoint = firstEntry.part
		local startFloor = preferFloor
		local targetFloor = firstEntry.floorName or preferFloor

		-- Seed currentNode on the NPC's spawn floor. This is the "Primer Nodo"
		-- in the route contract: spawn uses Roblox pathfinding to leave the room,
		-- then graph nodes handle same-floor movement and floor transitions.
		local currentNode = NodeGraph.getNearestNavigableNode(rootPart.Position, buildingName, startFloor, { npcModel })
			or NodeGraph.getNearestNodeOnFloor(rootPart.Position, buildingName, startFloor)
			or NodeGraph.getNearestNode(rootPart.Position, buildingName)

		-- Spawn -> Primer Nodo: Pathfinding.
		if currentNode and (rootPart.Position - currentNode.Position).Magnitude > ARRIVE_RADIUS then
			local firstNodeCacheKey = string.format(
				"spawn:%s:%s:%s:%s",
				buildingName,
				tostring(startFloor or "any"),
				tostring(spawnKey or "unknown"),
				currentNode:GetFullName()
			)
			if not moveUsingPathfinding(currentNode.Position, nil, startFloor, true, firstNodeCacheKey, MAX_SPAWN_PATH_WAYPOINTS) then
				Logger.warn("NPC", string.format(
					"%s: movement from spawn to first node failed; stopping",
					npcModel.Name
				))
				return
			end
		end

		-- Primer Nodo -> ... -> Nodo cercano al primer waypoint: MoveTo node chain.
		local firstPath, firstTargetNode = getRouteToPosition(
			currentNode,
			firstWaypoint.Position,
			buildingName,
			targetFloor
		)

		if firstPath and #firstPath > 0 then
			if not moveAlongNodePath(firstPath, buildingName, startFloor, nil) then
				Logger.warn("NPC", string.format(
					"%s: node-chain movement to first waypoint node failed; stopping",
					npcModel.Name
				))
				return
			end
		else
			Logger.warn("NPC", string.format(
				"%s: no graph path to first waypoint node; continuing with direct first-waypoint pathfinding",
				npcModel.Name
			))
		end

		-- Nodo cercano -> Primer Waypoint: Pathfinding.
		local firstWaypointCacheKey = string.format(
			"first-waypoint:%s:%s:%s:%s",
			buildingName,
			tostring(targetFloor or "any"),
			firstTargetNode and firstTargetNode:GetFullName() or "no-node",
			firstWaypoint:GetFullName()
		)
		if not moveUsingPathfinding(firstWaypoint.Position, offset, targetFloor, true, firstWaypointCacheKey, MAX_PATH_WAYPOINTS) then
			Logger.warn("NPC", string.format(
				"%s: movement from first waypoint node to %s failed; stopping",
				npcModel.Name,
				firstWaypoint.Name
			))
			return
		end

		local firstType = firstWaypoint:GetAttribute("WaypointType") or "Transit"
		if firstType == "Hold" then
			if not holdAtWaypoint(firstWaypoint, offset) then return end
		elseif firstType == "Finish" then
			stayAtFinishWaypoint(firstWaypoint, offset)
			return
		end

		-- Primer Waypoint -> demas waypoints: direct MoveTo, with segment-based
		-- door scans active on every movement tick.
		for index = 2, #waypoints do
			if not npcModel.Parent then return end
			if humanoid.Health <= 0 then return end

			local entry = waypoints[index]
			local wp = entry.part
			local wpType = wp:GetAttribute("WaypointType") or "Transit"

			if not moveDirectlyToWaypoint(wp, offset, "waypoint-chain") then
				Logger.warn("NPC", string.format(
					"%s: direct MoveTo to %s failed; stopping",
					npcModel.Name,
					wp.Name
				))
				return
			end

			if wpType == "Hold" then
				if not holdAtWaypoint(wp, offset) then return end
			elseif wpType == "Finish" then
				stayAtFinishWaypoint(wp, offset)
				return
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
