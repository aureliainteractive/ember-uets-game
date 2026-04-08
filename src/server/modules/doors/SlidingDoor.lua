-- SlidingDoor.lua
-- Purpose: Handles server-side sliding door toggling for a single door model.
-- Dependencies: TweenService, RemoteEvent ToggleDoor, Model Attributes

local TweenService = game:GetService("TweenService")

local SlidingDoor = {}
local CLICK_DISTANCE = 12

local function bindHandleClickDetector(doorModel, handleName, onToggle)
	local handle = doorModel:FindFirstChild(handleName, true)
	if not handle or not handle:IsA("BasePart") then
		warn("[SlidingDoor] Missing " .. handleName .. " BasePart on " .. doorModel:GetFullName())
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
		warn("[SlidingDoor] Invalid or missing SlideDistance on " .. fullName)
		return false
	end

	if typeof(slideTime) ~= "number" then
		warn("[SlidingDoor] Invalid or missing SlideTime on " .. fullName)
		return false
	end

	if typeof(slideDirection) ~= "number" then
		warn("[SlidingDoor] Invalid or missing SlideDirection on " .. fullName)
		return false
	end

	if typeof(cooldown) ~= "number" then
		warn("[SlidingDoor] Invalid or missing Cooldown on " .. fullName)
		return false
	end

	local door = doorModel:FindFirstChild("Door")
	local slidePivot = doorModel:FindFirstChild("SlidePivot")
	local toggleDoor = doorModel:FindFirstChild("ToggleDoor")

	if not door or not door:IsA("BasePart") then
		warn("[SlidingDoor] Missing Door BasePart on " .. fullName)
		return false
	end

	if not slidePivot or not slidePivot:IsA("BasePart") then
		warn("[SlidingDoor] Missing SlidePivot BasePart on " .. fullName)
		return false
	end

	if not toggleDoor or not toggleDoor:IsA("RemoteEvent") then
		warn("[SlidingDoor] Missing ToggleDoor RemoteEvent on " .. fullName)
		return false
	end

	local closedCFrame = door.CFrame
	local isOpen = false
	local isAnimating = false
	local onCooldown = false

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
		isAnimating = false
		beginCooldown()
	end

	toggleDoor.OnServerEvent:Connect(function()
		tryToggleDoor()
	end)

	bindHandleClickDetector(doorModel, "HandleInside", tryToggleDoor)
	bindHandleClickDetector(doorModel, "HandleOutside", tryToggleDoor)

	return true
end

return SlidingDoor