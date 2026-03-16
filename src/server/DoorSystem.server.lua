-- DoorSystem.server.lua
-- Purpose: Central coordinator for all door instances in the game.
-- Dependencies: HingeDoor, SlidingDoor

local HingeDoor = require(script.Parent.modules.doors.HingeDoor)
local SlidingDoor = require(script.Parent.modules.doors.SlidingDoor)

local initializedDoors = {}

local function resolveDoorType(model)
	local declaredType = model:GetAttribute("DoorType")
	local hasHinge = model:FindFirstChild("Hinge") ~= nil
	local hasSlidePivot = model:FindFirstChild("SlidePivot") ~= nil

	if declaredType == "Hinge" and hasSlidePivot and not hasHinge then
		warn("[DoorSystem] DoorType mismatch on " .. model:GetFullName() .. " — using Sliding")
		return "Sliding"
	end

	if declaredType == "Sliding" and hasHinge and not hasSlidePivot then
		warn("[DoorSystem] DoorType mismatch on " .. model:GetFullName() .. " — using Hinge")
		return "Hinge"
	end

	return declaredType
end

local function initDoorModel(model)
	if not model:IsA("Model") then
		return
	end

	if initializedDoors[model] then
		return
	end

	local doorType = resolveDoorType(model)
	if typeof(doorType) ~= "string" then
		if model:FindFirstChild("ToggleDoor") then
			warn("[DoorSystem] Unknown DoorType on " .. model:GetFullName() .. " — skipped")
		end
		return
	end

	if doorType == "Hinge" then
		local ok = HingeDoor.init(model)
		if ok then
			initializedDoors[model] = true
			print("[DoorSystem] Initialized: " .. model:GetFullName() .. " (Hinge)")
		end
		return
	end

	if doorType == "Sliding" then
		local ok = SlidingDoor.init(model)
		if ok then
			initializedDoors[model] = true
			print("[DoorSystem] Initialized: " .. model:GetFullName() .. " (Sliding)")
		end
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
