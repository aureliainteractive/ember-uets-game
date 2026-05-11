-- SlidingDoor.lua
-- Purpose: Handles server-side sliding door toggling for a single door model.
-- Dependencies: TweenService, RemoteEvent ToggleDoor, Model Attributes

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local SlidingDoor = {}
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

function SlidingDoor.init(doorModel)
	if not doorModel or not doorModel:IsA("Model") then
		return false
	end

	local fullName = doorModel:GetFullName()
	local slideDistance = doorModel:GetAttribute("SlideDistance")
	local slideTime = doorModel:GetAttribute("SlideTime")
	local slideDirection = doorModel:GetAttribute("SlideDirection")
	local cooldown = doorModel:GetAttribute("Cooldown")

	if typeof(slideDistance) ~= "number" then
		Logger.warn("Door", "Invalid or missing SlideDistance on " .. fullName)
		return false
	end

	if typeof(slideTime) ~= "number" then
		Logger.warn("Door", "Invalid or missing SlideTime on " .. fullName)
		return false
	end

	if typeof(slideDirection) ~= "number" then
		Logger.warn("Door", "Invalid or missing SlideDirection on " .. fullName)
		return false
	end

	if typeof(cooldown) ~= "number" then
		Logger.warn("Door", "Invalid or missing Cooldown on " .. fullName)
		return false
	end

	local door = doorModel:FindFirstChild("Door")
	local slidePivot = doorModel:FindFirstChild("SlidePivot")
	local toggleDoor = doorModel:FindFirstChild("ToggleDoor")

	if not door or not door:IsA("BasePart") then
		Logger.warn("Door", "Missing door BasePart on " .. fullName)
		return false
	end

	if not slidePivot or not slidePivot:IsA("BasePart") then
		Logger.warn("Door", "Missing SlidePivot BasePart on " .. fullName)
		return false
	end

	if not toggleDoor or not toggleDoor:IsA("RemoteEvent") then
		Logger.warn("Door", "Missing ToggleDoor RemoteEvent on " .. fullName)
		return false
	end

	local closedCFrame = door.CFrame
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
		local targetCFrame = closedCFrame
		if openState then
			local offset = slidePivot.CFrame.RightVector * (slideDistance * slideDirection)
			targetCFrame = closedCFrame + offset
		end

		return targetCFrame
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

		if not isOpen then
			closedCFrame = door.CFrame
		end

		isAnimating = true
		local nextOpenState = not isOpen
		local targetCFrame = targetCFrameForState(nextOpenState)

		local tween = TweenService:Create(
			door,
			TweenInfo.new(slideTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
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

	-- Create ForceCloseDoor event for external reset requests (e.g., simulation restart)
	local forceCloseDoorEvent = doorModel:FindFirstChild("ForceCloseDoor")
	if not forceCloseDoorEvent then
		forceCloseDoorEvent = Instance.new("BindableEvent")
		forceCloseDoorEvent.Name = "ForceCloseDoor"
		forceCloseDoorEvent.Parent = doorModel
	end

	-- Handler to force door to closed state immediately
	forceCloseDoorEvent.Event:Connect(function()
		-- Cancel any ongoing cooldown or animation
		onCooldown = false
		
		-- If currently animating, we need to complete it first
		if isAnimating then
			task.wait(slideTime + 0.1)
		end
		
		-- Force close without animation
		if isOpen then
			door.CFrame = closedCFrame
			isOpen = false
			doorModel:SetAttribute("IsOpen", false)
		end
	end)

	return true
end

return SlidingDoor
