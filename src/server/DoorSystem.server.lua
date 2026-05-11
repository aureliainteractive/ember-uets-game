-- DoorSystem.server.lua
-- Purpose: Central coordinator for all door instances in the game.
-- Dependencies: HingeDoor, SlidingDoor

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HingeDoor = require(script.Parent.modules.doors.HingeDoor)
local SlidingDoor = require(script.Parent.modules.doors.SlidingDoor)
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local initializedDoors = {}

local function closeDoor(doorModel)
	if not doorModel or not doorModel:IsA("Model") then
		return
	end
	
	local forceCloseDoorEvent = doorModel:FindFirstChild("ForceCloseDoor")
	if forceCloseDoorEvent and forceCloseDoorEvent:IsA("BindableEvent") then
		forceCloseDoorEvent:Fire()
	end
end

local function resetAllDoors()
	for doorModel, _ in pairs(initializedDoors) do
		if doorModel and doorModel.Parent then
			closeDoor(doorModel)
		end
	end
end

local function resolveDoorType(model)
	local declaredType = model:GetAttribute("DoorType")
	local hasHinge = model:FindFirstChild("Hinge") ~= nil
	local hasSlidePivot = model:FindFirstChild("SlidePivot") ~= nil

	if declaredType == "Hinge" and hasSlidePivot and not hasHinge then
		Logger.warn("Door", "DoorType mismatch; using Sliding: " .. model:GetFullName())
		return "Sliding"
	end

	if declaredType == "Sliding" and hasHinge and not hasSlidePivot then
		Logger.warn("Door", "DoorType mismatch; using Hinge: " .. model:GetFullName())
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
			Logger.warn("Door", "Unknown DoorType; initialization skipped: " .. model:GetFullName())
		end
		return
	end

	if doorType == "Hinge" then
		local ok = HingeDoor.init(model)
		if ok then
			initializedDoors[model] = true
			Logger.info("Door", "Initialized hinge door: " .. model:GetFullName())
		end
		return
	end

	if doorType == "Sliding" then
		local ok = SlidingDoor.init(model)
		if ok then
			initializedDoors[model] = true
			Logger.info("Door", "Initialized sliding door: " .. model:GetFullName())
		end
		return
	end

	Logger.warn("Door", "Unknown DoorType; initialization skipped: " .. model:GetFullName())
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

-- Expose resetAllDoors function via ReplicatedStorage for external calls (e.g., SimulationController)
local resetAllDoorsFunction = ReplicatedStorage:FindFirstChild("ResetAllDoorsFunction")
if not resetAllDoorsFunction then
	resetAllDoorsFunction = Instance.new("BindableFunction")
	resetAllDoorsFunction.Name = "ResetAllDoorsFunction"
	resetAllDoorsFunction.Parent = ReplicatedStorage
end

resetAllDoorsFunction.OnInvoke = function()
	resetAllDoors()
	Logger.info("Door", "All doors reset to closed state")
	return true
end
