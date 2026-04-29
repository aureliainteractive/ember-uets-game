-- HingeDoor.lua
-- Purpose: Handles server-side hinge door toggling for a single door model.
-- Dependencies: TweenService, RemoteEvent ToggleDoor, Model Attributes

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local HingeDoor = {}
local CLICK_DISTANCE = 12

local function bindHandleClickDetector(doorModel, handleName, onToggle)
	local handle = doorModel:FindFirstChild(handleName, true)
	if not handle or not handle:IsA("BasePart") then
		Logger.warn("Door", "Missing handle part " .. handleName .. " on " .. doorModel:GetFullName())
		return
	end

	local clickDetector = handle:FindFirstChildOfClass("ClickDetector")
	if not clickDetector then
		clickDetector = Instance.new("ClickDetector")
		clickDetector.Name = "DoorClickDetector"
		clickDetector.MaxActivationDistance = CLICK_DISTANCE
		clickDetector.Parent = handle
	end

	clickDetector.MouseClick:Connect(function()
		onToggle()
	end)
end

function HingeDoor.init(doorModel)
	if not doorModel or not doorModel:IsA("Model") then
		return false
	end

	local fullName = doorModel:GetFullName()
	local openAngle = doorModel:GetAttribute("OpenAngle")
	local openTime = doorModel:GetAttribute("OpenTime")
	local cooldown = doorModel:GetAttribute("Cooldown")

	if typeof(openAngle) ~= "number" then
		Logger.warn("Door", "Invalid or missing OpenAngle on " .. fullName)
		return false
	end

	if typeof(openTime) ~= "number" then
		Logger.warn("Door", "Invalid or missing OpenTime on " .. fullName)
		return false
	end

	if typeof(cooldown) ~= "number" then
		Logger.warn("Door", "Invalid or missing Cooldown on " .. fullName)
		return false
	end

	local door = doorModel:FindFirstChild("Door")
	local hinge = doorModel:FindFirstChild("Hinge")
	local toggleDoor = doorModel:FindFirstChild("ToggleDoor")

	if not door or not door:IsA("BasePart") then
		Logger.warn("Door", "Missing door BasePart on " .. fullName)
		return false
	end

	if not hinge or not hinge:IsA("BasePart") then
		Logger.warn("Door", "Missing hinge BasePart on " .. fullName)
		return false
	end

	if not toggleDoor or not toggleDoor:IsA("RemoteEvent") then
		Logger.warn("Door", "Missing ToggleDoor RemoteEvent on " .. fullName)
		return false
	end

	local closedRelative = hinge.CFrame:ToObjectSpace(door.CFrame)
	local isOpen = false
	local isAnimating = false
	local onCooldown = false

	-- Set initial IsOpen attribute for NPC detection
	doorModel:SetAttribute("IsOpen", false)

	-- Create OpenDoorEvent for NPC integration
	local openDoorEvent = doorModel:FindFirstChild("OpenDoorEvent")
	if not openDoorEvent then
		openDoorEvent = Instance.new("BindableEvent")
		openDoorEvent.Name = "OpenDoorEvent"
		openDoorEvent.Parent = doorModel
	end

	local function targetCFrameForState(openState)
		if openState then
			local rotatedRelative = CFrame.Angles(0, math.rad(openAngle), 0) * closedRelative
			return hinge.CFrame:ToWorldSpace(rotatedRelative)
		end

		return hinge.CFrame:ToWorldSpace(closedRelative)
	end

	local function beginCooldown()
		onCooldown = true
		task.delay(cooldown, function()
			onCooldown = false
		end)
	end

	local function tryToggleDoor()
		if onCooldown or isAnimating then
			return
		end

		isAnimating = true
		local nextOpenState = not isOpen
		local targetCFrame = targetCFrameForState(nextOpenState)

		local tween = TweenService:Create(
			door,
			TweenInfo.new(openTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = targetCFrame }
		)

		tween:Play()
		tween.Completed:Wait()

		isOpen = nextOpenState
		doorModel:SetAttribute("IsOpen", isOpen)
		isAnimating = false
		beginCooldown()
	end

	toggleDoor.OnServerEvent:Connect(function()
		tryToggleDoor()
	end)

	-- Connect OpenDoorEvent for NPC integration
	openDoorEvent.Event:Connect(function()
		tryToggleDoor()
	end)

	bindHandleClickDetector(doorModel, "HandleInside", tryToggleDoor)
	bindHandleClickDetector(doorModel, "HandleOutside", tryToggleDoor)

	return true
end

return HingeDoor
