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

local ARRIVE_RADIUS  = 2.5   -- studs: "close enough" to a waypoint node
local MOVETO_TIMEOUT = 12    -- seconds before giving up on a waypoint and skipping
local TICK_RATE      = 0.1   -- seconds between movement checks

-- ─── Bootstrap ────────────────────────────────────────────────────────────────

local npcModel = script.Parent
local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
local rootPart = npcModel:FindFirstChild("HumanoidRootPart")

if not humanoid or not rootPart then
	warn("[NPCWaypointFollower] Missing Humanoid or HumanoidRootPart in: " .. npcModel.Name)
	return
end

-- ─── Waypoint collection ──────────────────────────────────────────────────────

local function resolveWaypointsRoot()
	local preferred = workspace:FindFirstChild("NPC_Waypoints")
	if preferred then return preferred end

	-- Fallback for places that still keep routes under Workspace.Waypoints
	local legacy = workspace:FindFirstChild("Waypoints")
	if legacy then
		warn("[NPCWaypointFollower] Using legacy root Workspace.Waypoints (NPC_Waypoints not found).")
		return legacy
	end

	warn("[NPCWaypointFollower] Neither Workspace.NPC_Waypoints nor Workspace.Waypoints exists.")
	return nil
end

local function parseWaypointIndex(name)
	-- Supports: Waypoint1, Waypoint_1, Waypoint-1, WP1
	return tonumber(name:match("^Waypoint[_%-]?(%d+)$")) or tonumber(name:match("^WP(%d+)$"))
end

local function collectWaypoints(buildingName, eventType)
	local root = resolveWaypointsRoot()
	if not root then return {} end

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

	table.sort(list, function(a, b) return a.index < b.index end)
	if #list == 0 then
		warn(string.format(
			"[NPCWaypointFollower] No waypoint parts found in '%s/%s'. Expected names like Waypoint1, Waypoint2...",
			buildingName,
			eventType
		))
	end
	return list
end

-- ─── Movement ─────────────────────────────────────────────────────────────────

local function moveTo(targetPos, offset)
	local goal = targetPos + (offset or Vector3.zero)
	local reached = false
	local connection = humanoid.MoveToFinished:Connect(function(didReach)
		if didReach then reached = true end
	end)
	humanoid:MoveTo(goal)

	local elapsed = 0
	while elapsed < MOVETO_TIMEOUT do
		if humanoid.Health <= 0 then return false end
		if reached or (rootPart.Position - goal).Magnitude <= ARRIVE_RADIUS then
			connection:Disconnect()
			return true
		end
		task.wait(TICK_RATE)
		elapsed += TICK_RATE
	end

	connection:Disconnect()
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
	task.spawn(function()
		local finalPos = wp.Position + (offset or Vector3.zero)
		while npcModel.Parent and humanoid.Health > 0 do
			humanoid:MoveTo(finalPos)
			task.wait(1)
		end
	end)
	return false
end

-- ─── Runner ───────────────────────────────────────────────────────────────────

local function run()
	local buildingName  = npcModel:GetAttribute("BuildingName")
	local eventType     = npcModel:GetAttribute("EventType")
	local startDelay    = npcModel:GetAttribute("StartDelay") or 0
	local rawOffset     = npcModel:GetAttribute("PositionOffset")

	if not buildingName or not eventType then
		warn("[NPCWaypointFollower] BuildingName or EventType missing on: " .. npcModel.Name)
		return
	end

	local offset = rawOffset or Vector3.zero

	if startDelay > 0 then task.wait(startDelay) end

	local waypoints = collectWaypoints(buildingName, eventType)
	if #waypoints == 0 then return end

	for _, entry in ipairs(waypoints) do
		if not npcModel.Parent then return end
		if humanoid.Health <= 0 then return end

		local wp     = entry.part
		local wpType = wp:GetAttribute("WaypointType") or "Transit"

		if wpType == "Transit" then
			handleTransit(wp, offset)
		elseif wpType == "Hold" then
			handleHold(wp, offset)
		elseif wpType == "Finish" then
			if handleFinish(wp, offset) == false then return end
		else
			warn("[NPCWaypointFollower] Unknown WaypointType '" .. tostring(wpType) .. "' — treating as Transit.")
			handleTransit(wp, offset)
		end
	end
end

task.spawn(run)