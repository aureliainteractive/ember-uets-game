-- NodeGraph module
-- Provides building-scoped navigation graphs built from BasePart nodes placed under
-- Workspace/NPC_Nodes/<BuildingName>/<FloorFolder>/
--
-- ── Floor folder naming convention ─────────────────────────────────────────
--
--   Floor1        → regular nodes that live on floor 1
--   Floor2        → regular nodes that live on floor 2
--   Floor1u2      → STAIRCASE nodes that bridge floor 1 and floor 2
--                   (the "u" stands for "union")
--
-- Regular nodes only connect to other regular nodes on the SAME floor
-- (within NEIGHBOR_RADIUS).  Staircase nodes connect to every node whose
-- primary floor appears in their bridge set (within STAIR_RADIUS).  This
-- means NPCs can only cross floors through an explicit staircase folder —
-- no accidental cross-floor shortcuts.

local NodeGraph = {}
local workspace        = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local NPC_NODES_ROOT_NAME = "NPC_Nodes"
local NEIGHBOR_RADIUS     = 12   -- studs: same-floor node connection radius
local STAIR_RADIUS        = 22   -- studs: cross-floor connection radius via staircase nodes

-- ── Helpers ────────────────────────────────────────────────────────────────

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

-- ── Floor info parser ──────────────────────────────────────────────────────
-- Returns a table describing which floors a folder's nodes belong to.
--
--   "Floor1"   → { primary="Floor1", bridges={"Floor1"=true}, isTransition=false }
--   "Floor1u2" → { primary="Floor1", secondary="Floor2",
--                   bridges={"Floor1"=true,"Floor2"=true}, isTransition=true }
--   anything else → treated as its own single-floor group

local function parseFloorInfo(folderName)
	local a, b = folderName:match("^[Ff]loor(%d+)[uU](%d+)$")
	if a and b then
		local fa, fb = "Floor" .. a, "Floor" .. b
		return {
			primary      = fa,
			secondary    = fb,
			bridges      = { [fa] = true, [fb] = true },
			isTransition = true,
		}
	end

	local n = folderName:match("^[Ff]loor(%d+)$")
	if n then
		local f = "Floor" .. n
		return {
			primary      = f,
			secondary    = nil,
			bridges      = { [f] = true },
			isTransition = false,
		}
	end

	-- Unknown folder name: treat as its own floor, no bridging
	return {
		primary      = folderName,
		secondary    = nil,
		bridges      = { [folderName] = true },
		isTransition = false,
	}
end

-- ── Graph cache ────────────────────────────────────────────────────────────

local buildingCache  = {}
local staleBuildings = {}

local function findNodesRoot()
	return workspace:FindFirstChild(NPC_NODES_ROOT_NAME)
end

local function markBuildingStale(buildingName)
	staleBuildings[buildingName] = true
end

-- Auto-invalidate cache when the node tree changes
local nodesRoot = findNodesRoot()
if nodesRoot then
	nodesRoot.DescendantAdded:Connect(function(desc)
		local b = desc
		while b and b.Parent and b.Parent ~= nodesRoot do b = b.Parent end
		if b and b.Parent == nodesRoot and b:IsA("Folder") then
			markBuildingStale(b.Name)
		end
	end)
	nodesRoot.DescendantRemoving:Connect(function(desc)
		local b = desc
		while b and b.Parent and b.Parent ~= nodesRoot do b = b.Parent end
		if b and b.Parent == nodesRoot and b:IsA("Folder") then
			markBuildingStale(b.Name)
		end
	end)
end

-- ── Adjacency rule ─────────────────────────────────────────────────────────
-- Two nodes A and B may be connected when:
--   • Same primary floor AND dist ≤ NEIGHBOR_RADIUS
--   • A is a staircase node whose bridge set includes B's primary floor
--     AND dist ≤ STAIR_RADIUS  (and vice-versa)
--   • Both are staircase nodes sharing at least one floor in their bridge
--     sets AND dist ≤ STAIR_RADIUS  (same staircase run)

local function nodesCanConnect(infoA, infoB, dist)
	local sameFloor = infoA.floorInfo.primary == infoB.floorInfo.primary
	if sameFloor then
		return dist <= NEIGHBOR_RADIUS
	end

	local aStair = infoA.floorInfo.isTransition
	local bStair = infoB.floorInfo.isTransition

	-- Staircase A bridges into B's floor
	if aStair and infoA.floorInfo.bridges[infoB.floorInfo.primary] then
		return dist <= STAIR_RADIUS
	end
	-- Staircase B bridges into A's floor
	if bStair and infoB.floorInfo.bridges[infoA.floorInfo.primary] then
		return dist <= STAIR_RADIUS
	end
	-- Both staircase nodes sharing a floor (same staircase segment)
	if aStair and bStair then
		for f in pairs(infoA.floorInfo.bridges) do
			if infoB.floorInfo.bridges[f] then
				return dist <= STAIR_RADIUS
			end
		end
	end

	return false
end

-- ── Graph builder ──────────────────────────────────────────────────────────

local function buildGraphForBuilding(buildingName)
	if buildingCache[buildingName] and not staleBuildings[buildingName] then
		return buildingCache[buildingName]
	end

	local root = findNodesRoot()
	if not root then
		Logger.warn("NodeGraph", "Workspace.NPC_Nodes not found")
		return nil
	end

	local buildingFolder = findChildAgnostic(root, buildingName)
	if not buildingFolder then
		Logger.warn("NodeGraph", "Building folder not found: " .. tostring(buildingName))
		return nil
	end

	-- Collect all BasePart nodes from every floor folder
	local nodes = {}
	for _, floorFolder in ipairs(buildingFolder:GetChildren()) do
		if floorFolder:IsA("Folder") or floorFolder:IsA("Model") then
			local floorInfo = parseFloorInfo(floorFolder.Name)
			for _, descendant in ipairs(floorFolder:GetDescendants()) do
				if descendant:IsA("BasePart") then
					table.insert(nodes, {
						inst      = descendant,
						floorInfo = floorInfo,
						pos       = descendant.Position,
					})
				end
			end
		end
	end

	if #nodes == 0 then
		buildingCache[buildingName] = { nodes = {}, instToIndex = {}, adjacency = {} }
		staleBuildings[buildingName] = false
		return buildingCache[buildingName]
	end

	-- Build index
	local instToIndex = {}
	for i, info in ipairs(nodes) do
		instToIndex[info.inst] = i
	end

	-- Build adjacency using the strict floor-aware rule
	local adjacency = {}
	for i = 1, #nodes do adjacency[i] = {} end

	for i = 1, #nodes do
		local a = nodes[i]
		for j = i + 1, #nodes do
			local b    = nodes[j]
			local dist = (a.pos - b.pos).Magnitude
			if nodesCanConnect(a, b, dist) then
				table.insert(adjacency[i], { idx = j, cost = dist })
				table.insert(adjacency[j], { idx = i, cost = dist })
			end
		end
	end

	-- Optional explicit connections via "ConnectTo" attribute (comma-separated part names)
	local nameToIndex = {}
	for i, info in ipairs(nodes) do
		nameToIndex[info.inst.Name] = i
	end
	for i, info in ipairs(nodes) do
		local attr = info.inst:GetAttribute("ConnectTo")
		if attr and type(attr) == "string" then
			for name in string.gmatch(attr, "[^,]+") do
				name = name:match("^%s*(.-)%s*$")
				local j = nameToIndex[name]
				if j and j ~= i then
					local dist = (info.pos - nodes[j].pos).Magnitude
					table.insert(adjacency[i], { idx = j, cost = dist })
				end
			end
		end
	end

	buildingCache[buildingName] = {
		nodes      = nodes,
		instToIndex = instToIndex,
		adjacency  = adjacency,
	}
	staleBuildings[buildingName] = false
	Logger.debug(
		"NodeGraph",
		string.format("Built graph for %s: %d nodes", buildingName, #nodes)
	)
	return buildingCache[buildingName]
end

-- ── Public: nearest node queries ───────────────────────────────────────────

-- Returns the nearest node to `position` across all floors.
-- If `preferFloor` is given, nodes belonging to or bridging that floor
-- are preferred, but the search is never restricted to them.
local function getNearestNode(position, buildingName, preferFloor)
	local graph = buildGraphForBuilding(buildingName)
	if not graph or #graph.nodes == 0 then return nil end

	local bestDist   = math.huge
	local bestIdx    = nil
	local preferDist = math.huge
	local preferIdx  = nil

	for i, info in ipairs(graph.nodes) do
		local d = (info.pos - position).Magnitude
		if d < bestDist then
			bestDist = d
			bestIdx  = i
		end
		if preferFloor and info.floorInfo.bridges[preferFloor] and d < preferDist then
			preferDist = d
			preferIdx  = i
		end
	end

	if preferIdx then return graph.nodes[preferIdx].inst end
	return graph.nodes[bestIdx] and graph.nodes[bestIdx].inst or nil
end

-- Returns the nearest node that belongs to (or bridges) `floorName`.
-- Falls back to any nearest node if no floor match is found.
local function getNearestNodeOnFloor(position, buildingName, floorName)
	if not floorName then return getNearestNode(position, buildingName) end

	local graph = buildGraphForBuilding(buildingName)
	if not graph or #graph.nodes == 0 then return nil end

	local bestDist = math.huge
	local bestIdx  = nil

	for i, info in ipairs(graph.nodes) do
		-- Accept both regular floor nodes and staircase nodes bridging this floor
		if info.floorInfo.bridges[floorName] then
			local d = (info.pos - position).Magnitude
			if d < bestDist then
				bestDist = d
				bestIdx  = i
			end
		end
	end

	if bestIdx then return graph.nodes[bestIdx].inst end
	-- Fallback: nearest node in any floor
	return getNearestNode(position, buildingName)
end

-- ── Public: floor query ────────────────────────────────────────────────────

-- Returns the primary floor name for a given node BasePart, or nil.
local function getPathFloor(inst, buildingName)
	local graph = buildGraphForBuilding(buildingName)
	if not graph then return nil end
	local idx = graph.instToIndex[inst]
	if not idx then return nil end
	return graph.nodes[idx] and graph.nodes[idx].floorInfo.primary or nil
end

-- Returns true when `inst` is a staircase (transition) node.
local function isTransitionNode(inst, buildingName)
	local graph = buildGraphForBuilding(buildingName)
	if not graph then return false end
	local idx = graph.instToIndex[inst]
	if not idx then return false end
	return graph.nodes[idx] and graph.nodes[idx].floorInfo.isTransition or false
end

-- ── Public: A* pathfinding ─────────────────────────────────────────────────

-- Returns an ordered list of BaseParts (nodes) from startInst to goalInst.
-- Returns nil when no path exists.
local function findPathBetweenNodes(startInst, goalInst, buildingName)
	if not startInst or not goalInst then return nil end
	if startInst == goalInst then return { startInst } end

	local graph = buildGraphForBuilding(buildingName)
	if not graph or #graph.nodes == 0 then return nil end

	local startIdx = graph.instToIndex[startInst]
	local goalIdx  = graph.instToIndex[goalInst]
	if not startIdx or not goalIdx then return nil end

	local openSet  = { [startIdx] = true }
	local cameFrom = {}
	local gScore   = {}
	local fScore   = {}
	for i = 1, #graph.nodes do gScore[i] = math.huge; fScore[i] = math.huge end
	gScore[startIdx] = 0

	local goalPos = graph.nodes[goalIdx].pos
	local function heuristic(i)
		return (graph.nodes[i].pos - goalPos).Magnitude
	end
	fScore[startIdx] = heuristic(startIdx)

	local function lowestF()
		local best, bestVal = nil, math.huge
		for i in pairs(openSet) do
			if fScore[i] < bestVal then bestVal = fScore[i]; best = i end
		end
		return best
	end

	while next(openSet) do
		local current = lowestF()
		if not current then break end

		if current == goalIdx then
			-- Reconstruct path
			local path = {}
			local node = current
			while node do
				table.insert(path, 1, graph.nodes[node].inst)
				node = cameFrom[node]
			end
			return path
		end

		openSet[current] = nil
		for _, edge in ipairs(graph.adjacency[current] or {}) do
			local nb  = edge.idx
			local tg  = gScore[current] + edge.cost
			if tg < gScore[nb] then
				cameFrom[nb] = current
				gScore[nb]   = tg
				fScore[nb]   = tg + heuristic(nb)
				openSet[nb]  = true
			end
		end
	end

	return nil  -- no path found
end

-- ── Export ─────────────────────────────────────────────────────────────────

NodeGraph.getNearestNode        = getNearestNode
NodeGraph.getNearestNodeOnFloor = getNearestNodeOnFloor
NodeGraph.getPathFloor          = getPathFloor
NodeGraph.isTransitionNode      = isTransitionNode
NodeGraph.findPathBetweenNodes  = findPathBetweenNodes
NodeGraph.markBuildingStale     = markBuildingStale
NodeGraph.buildGraphForBuilding = buildGraphForBuilding

return NodeGraph