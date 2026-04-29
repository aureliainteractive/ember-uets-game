-- SetupNavigation.server.lua
-- Place in ServerScriptService to create NPC_Nodes and NPC_Waypoints structure
-- Usage: Paste into a Script in ServerScriptService, or into Command Bar

local Workspace = game:GetService("Workspace")

local function ensureFolder(parent, name)
	local f = parent:FindFirstChild(name)
	if not f then
		f = Instance.new("Folder")
		f.Name = name
		f.Parent = parent
	end
	return f
end

local function makeNode(parent, name, position, attrs)
	local part = parent:FindFirstChild(name)
	if not part then
		part = Instance.new("Part")
		part.Size = Vector3.new(1, 1, 1)
		part.Anchored = true
		part.CanCollide = false
		part.Name = name
		part.Position = position
		part.Parent = parent
	end
	if attrs then
		for k, v in pairs(attrs) do
			part:SetAttribute(k, v)
		end
	end
	return part
end

-- ─── Create NPC_Nodes structure ──────────────────────────────────────
local npcNodes = ensureFolder(Workspace, "NPC_Nodes")
local mainBuilding = ensureFolder(npcNodes, "MainBuilding")
local floor1 = ensureFolder(mainBuilding, "Floor1")
local floor2 = ensureFolder(mainBuilding, "Floor2")

print("[Navigation Setup] Created NPC_Nodes > MainBuilding > Floor1, Floor2")

-- ─── Create Sample Navigation Nodes on Floor1 ───────────────────────
local n1 = makeNode(floor1, "Node_Corridor_A", Vector3.new(0, 4, 0))
local n2 = makeNode(floor1, "Node_Corridor_B", Vector3.new(12, 4, 0))
local n3 = makeNode(floor1, "Node_Stairs_Up", Vector3.new(24, 4, 0))

-- ─── Create Sample Navigation Nodes on Floor2 ───────────────────────
local n4 = makeNode(floor2, "Node_Corridor_C", Vector3.new(24, 12, 0))
local n5 = makeNode(floor2, "Node_Corridor_D", Vector3.new(36, 12, 0))
local n6 = makeNode(floor2, "Node_Stairs_Down", Vector3.new(24, 12, 5))

-- ─── Connect nodes explicitly (stairs) ─────────────────────────────
n3:SetAttribute("ConnectTo", "Node_Stairs_Down")
n6:SetAttribute("ConnectTo", "Node_Stairs_Up")
n3:SetAttribute("FloorName", "Floor1")
n6:SetAttribute("FloorName", "Floor2")

print("[Navigation Setup] Created sample navigation nodes with stair connections")

-- ─── Create NPC_Waypoints structure for compatibility ────────────────
local npcWay = ensureFolder(Workspace, "NPC_Waypoints")
local wpBuilding = ensureFolder(npcWay, "MainBuilding")
local wpEvac = ensureFolder(wpBuilding, "Evacuation")

print("[Navigation Setup] Created NPC_Waypoints > MainBuilding > Evacuation")

-- ─── Create Sample Evacuation Waypoint ────────────────────────────
local wp1 = wpEvac:FindFirstChild("Waypoint1")
if not wp1 then
	wp1 = Instance.new("Part")
	wp1.Name = "Waypoint1"
	wp1.Anchored = true
	wp1.CanCollide = false
	wp1.Size = Vector3.new(2, 2, 2)
	wp1.Position = Vector3.new(50, 0, 0)
	wp1.Parent = wpEvac
	wp1:SetAttribute("WaypointType", "Finish")
end

print("[Navigation Setup] Created evacuation waypoint")

-- ─── Summary ──────────────────────────────────────────────────────
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("[Navigation Setup] Complete!")
print("  NPC_Nodes structure created:")
print("    - MainBuilding/Floor1 (3 nodes)")
print("    - MainBuilding/Floor2 (3 nodes)")
print("  NPC_Waypoints structure created:")
print("    - MainBuilding/Evacuation (1 waypoint)")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
