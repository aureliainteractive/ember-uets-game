-- NodeGraph module
-- Provides building-scoped navigation graphs built from BasePart nodes placed under
-- Workspace/NPC_Nodes/<BuildingName>/<FloorName>/

local NodeGraph = {}
local workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local NPC_NODES_ROOT_NAME = "NPC_Nodes"
local NEIGHBOR_RADIUS = 12 -- studs: default radius to implicitly connect nearby nodes
local FLOOR_INTERCONNECT_BONUS = 1.5 -- allow slightly larger radius to connect stairs between floors

-- Cache per building: { nodes = { {inst=Instance, floor=string, pos=Vector3} }, instToIndex = {}, adjacency = { [i] = { {idx=_, cost=_}, ... } } }
local buildingCache = {}
local staleBuildings = {}

local function getFloorFolderName(node, buildingFolder)
    local current = node and node.Parent
    while current and current ~= buildingFolder do
        if current.Parent == buildingFolder then
            return current.Name
        end
        current = current.Parent
    end

    return nil
end

local function findNodesRoot()
    return workspace:FindFirstChild(NPC_NODES_ROOT_NAME)
end

local function markBuildingStale(buildingName)
    staleBuildings[buildingName] = true
end

-- Listen for changes under NPC_Nodes and mark affected building stale.
local nodesRoot = findNodesRoot()
if nodesRoot then
    nodesRoot.DescendantAdded:Connect(function(desc)
        local b = desc
        while b and b.Parent and b.Parent ~= nodesRoot do
            b = b.Parent
        end
        if b and b.Parent == nodesRoot and b:IsA("Folder") then
            markBuildingStale(b.Name)
        end
    end)
    nodesRoot.DescendantRemoving:Connect(function(desc)
        local b = desc
        while b and b.Parent and b.Parent ~= nodesRoot do
            b = b.Parent
        end
        if b and b.Parent == nodesRoot and b:IsA("Folder") then
            markBuildingStale(b.Name)
        end
    end)
end

local function buildGraphForBuilding(buildingName)
    if buildingCache[buildingName] and not staleBuildings[buildingName] then
        return buildingCache[buildingName]
    end

    local root = findNodesRoot()
    if not root then
        Logger.warn("NodeGraph", "Workspace.NPC_Nodes not found")
        return nil
    end

    local buildingFolder = root:FindFirstChild(buildingName)
    if not buildingFolder then
        Logger.warn("NodeGraph", "Building folder not found: " .. tostring(buildingName))
        return nil
    end

    local nodes = {}
    for _, floor in ipairs(buildingFolder:GetChildren()) do
        if floor:IsA("Folder") or floor:IsA("Model") then
            for _, descendant in ipairs(floor:GetDescendants()) do
                if descendant:IsA("BasePart") then
                    local floorName = getFloorFolderName(descendant, buildingFolder) or floor.Name
                    table.insert(nodes, { inst = descendant, floor = floorName, pos = descendant.Position })
                end
            end
        end
    end

    if #nodes == 0 then
        buildingCache[buildingName] = { nodes = {}, instToIndex = {}, adjacency = {} }
        staleBuildings[buildingName] = false
        return buildingCache[buildingName]
    end

    local instToIndex = {}
    for i, info in ipairs(nodes) do
        instToIndex[info.inst] = i
    end

    local adjacency = {}
    for i = 1, #nodes do
        adjacency[i] = {}
    end

    for i = 1, #nodes do
        local a = nodes[i]
        for j = i + 1, #nodes do
            local b = nodes[j]
            local dist = (a.pos - b.pos).Magnitude
            local radius = NEIGHBOR_RADIUS
            if a.floor ~= b.floor then
                radius = radius * FLOOR_INTERCONNECT_BONUS
            end
            if dist <= radius then
                table.insert(adjacency[i], { idx = j, cost = dist })
                table.insert(adjacency[j], { idx = i, cost = dist })
            end
        end
    end

    -- Optional explicit connections via "ConnectTo" attribute (comma-separated names)
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

    buildingCache[buildingName] = { nodes = nodes, instToIndex = instToIndex, adjacency = adjacency }
    staleBuildings[buildingName] = false
    Logger.debug("NodeGraph", string.format("Built graph for %s: %d nodes", buildingName, #nodes))
    return buildingCache[buildingName]
end

local function getNearestNode(position, buildingName, preferFloor)
    local graph = buildGraphForBuilding(buildingName)
    if not graph or #graph.nodes == 0 then
        return nil
    end

    local bestDist = math.huge
    local bestIdx = nil
    local bestSameFloorDist = math.huge
    local bestSameFloorIdx = nil

    for i, info in ipairs(graph.nodes) do
        local d = (info.pos - position).Magnitude
        if d < bestDist then
            bestDist = d
            bestIdx = i
        end
        if preferFloor and info.floor == preferFloor and d < bestSameFloorDist then
            bestSameFloorDist = d
            bestSameFloorIdx = i
        end
    end

    if bestSameFloorIdx then
        return graph.nodes[bestSameFloorIdx].inst
    end
    return graph.nodes[bestIdx].inst
end

local function findPathBetweenNodes(startInst, goalInst, buildingName)
    if not startInst or not goalInst then
        return nil
    end
    if startInst == goalInst then
        return { startInst }
    end

    local graph = buildGraphForBuilding(buildingName)
    if not graph or #graph.nodes == 0 then
        return nil
    end

    local startIdx = graph.instToIndex[startInst]
    local goalIdx = graph.instToIndex[goalInst]
    if not startIdx or not goalIdx then
        return nil
    end

    -- A* search on indices
    local openSet = { [startIdx] = true }
    local cameFrom = {}
    local gScore = {}
    local fScore = {}
    for i = 1, #graph.nodes do
        gScore[i] = math.huge
        fScore[i] = math.huge
    end
    gScore[startIdx] = 0
    local function heuristic(i)
        return (graph.nodes[i].pos - graph.nodes[goalIdx].pos).Magnitude
    end
    fScore[startIdx] = heuristic(startIdx)

    local function lowestF()
        local best, bestVal = nil, math.huge
        for i in pairs(openSet) do
            if fScore[i] < bestVal then
                bestVal = fScore[i]
                best = i
            end
        end
        return best
    end

    while next(openSet) do
        local current = lowestF()
        if not current then break end
        if current == goalIdx then
            -- reconstruct path
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
            local neighbor = edge.idx
            local tentative_g = gScore[current] + edge.cost
            if tentative_g < gScore[neighbor] then
                cameFrom[neighbor] = current
                gScore[neighbor] = tentative_g
                fScore[neighbor] = tentative_g + heuristic(neighbor)
                openSet[neighbor] = true
            end
        end
    end

    return nil
end

NodeGraph.getNearestNode = getNearestNode
NodeGraph.findPathBetweenNodes = findPathBetweenNodes
NodeGraph.markBuildingStale = markBuildingStale
NodeGraph.buildGraphForBuilding = buildGraphForBuilding

return NodeGraph
