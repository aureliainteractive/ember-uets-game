-- DoorSystem.server.lua
-- Purpose: Central coordinator for all door instances in the game.
-- Dependencies: HingeDoor, SlidingDoor

local HingeDoor = require(script.Parent.modules.doors.HingeDoor)
local SlidingDoor = require(script.Parent.modules.doors.SlidingDoor)

local initializedDoors = {}

local function initDoorModel(model)
	if not model:IsA("Model") then
		return
	end

	if initializedDoors[model] then
		return
	end

	local doorType = model:GetAttribute("DoorType")
	if typeof(doorType) ~= "string" then
		if model:FindFirstChild("ToggleDoor") then
			warn("[DoorSystem] Unknown DoorType on " .. model:GetFullName() .. " — skipped")
		end
		return
	end

	if doorType == "Hinge" then
		HingeDoor.init(model)
		initializedDoors[model] = true
		print("[DoorSystem] Initialized: " .. model:GetFullName() .. " (Hinge)")
		return
	end

	if doorType == "Sliding" then
		SlidingDoor.init(model)
		initializedDoors[model] = true
		print("[DoorSystem] Initialized: " .. model:GetFullName() .. " (Sliding)")
		return
	end

	warn("[DoorSystem] Unknown DoorType on " .. model:GetFullName() .. " — skipped")
end

for _, descendant in ipairs(workspace:GetDescendants()) do
	if descendant:IsA("Model") and descendant:GetAttribute("DoorType") ~= nil then
		initDoorModel(descendant)
	end
end

workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("Model") then
		initDoorModel(descendant)
	end
end)
