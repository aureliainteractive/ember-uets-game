-- NPCWaypointFollower
-- Location : Inside the NPC Model in ReplicatedStorage (cloned to Workspace by NPCSpawner).
-- Purpose  : Walk the NPC through an ordered waypoint path once activated.
--
-- Waypoint path  : Workspace.NPC_Waypoints.<BuildingName>.<EventType>.Waypoint<N>
-- Waypoint attrs : WaypointType (string) "Transit" | "Hold" | "Finish"
--                  HoldDuration (number) seconds — only used on Hold waypoints
--
-- Attrs set by NPCSpawner on the NPC Model before parenting to Workspace:
--   BuildingName   (string)
--   EventType      (string)
--   StartDelay     (number)  seconds to wait before beginning — staggers the crowd
--   PositionOffset (Vector3) small random XZ nudge so NPCs don't stack on waypoints

-- ─── Constants ────────────────────────────────────────────────────────────────

local ARRIVE_RADIUS = 2.5 -- studs: "close enough" to a waypoint node
local MOVETO_TIMEOUT = 12 -- seconds before giving up on a waypoint and skipping
local TICK_RATE = 0.1 -- seconds between movement checks

-- Walk animation IDs (public Roblox default animations — no ownership required)
local WALK_ANIM_R6 = "rbxassetid://180426354"
local WALK_ANIM_R15 = "rbxassetid://507777826"

local WALK_SPEED_THRESHOLD = 0.1
local START_EVENT_NAME = "StartPathing"

-- ─── Bootstrap ────────────────────────────────────────────────────────────────

local npcModel = script.Parent
local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
local rootPart = npcModel:FindFirstChild("HumanoidRootPart")
local started = false

if not humanoid or not rootPart then
	warn("[NPCWaypointFollower] Missing Humanoid or HumanoidRootPart in: " .. npcModel.Name)
	return
end

-- ─── Animation setup ─────────────────────────────────────────────────────────
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

local DOOR_DETECTION_RADIUS = 8 -- studs: search for doors within this distance
local DOOR_TRIGGER_DISTANCE = 6 -- studs: distance to trigger door opening
local DOOR_DEBOUNCE_TIME = 1.5 -- seconds: prevent door spam from same NPC

local doorDebounces = {} -- { doorModel = { lastTriggeredTime = number } }

local function tryOpenNearbyDoors()
	if humanoid.Health <= 0 then
		return
	end

	local npcPos = rootPart.Position

	-- Use Workspace:FindPartBoundsInRadius to efficiently find nearby doors
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Blacklist
	params.FilterDescendantsInstances = { npcModel }

	local nearbyParts = workspace:FindPartBoundsInRadius(npcPos, DOOR_DETECTION_RADIUS, params)

	for _, part in ipairs(nearbyParts) do
		-- Check if this part is a door model or inside one
		local doorModel = nil
		if part:GetAttribute("DoorType") ~= nil then
			doorModel = part
		else
			-- Walk up the tree to find a door model
			local parent = part.Parent
			while parent do
				if parent:GetAttribute("DoorType") ~= nil then
					doorModel = parent
					break
				end
				parent = parent.Parent
			end
		end

		if doorModel and (doorModel.Position - npcPos).Magnitude <= DOOR_TRIGGER_DISTANCE then
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

			if timeSinceLastTrigger >= DOOR_DEBOUNCE_TIME then
				-- Trigger the door
				local openDoorEvent = doorModel:FindFirstChild("OpenDoorEvent")
				if openDoorEvent and openDoorEvent:IsA("BindableEvent") then
					doorDebounces[doorModel].lastTriggeredTime = tick()
					openDoorEvent:Fire()
				end
			end
		end
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

-- ─── Entry point ──────────────────────────────────────────────────────────────

local function start()
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

local startEvent = npcModel:FindFirstChild(START_EVENT_NAME)
if startEvent and startEvent:IsA("BindableEvent") then
	startEvent.Event:Connect(start)
else
	warn(
		string.format(
			"[NPCWaypointFollower] Missing BindableEvent '%s' in %s. Pathing will not auto-start.",
			START_EVENT_NAME,
			npcModel:GetFullName()
		)
	)
end
