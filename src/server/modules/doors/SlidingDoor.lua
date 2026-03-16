-- SlidingDoor.lua
-- Purpose: Handles server-side sliding door toggling for a single door model.
-- Dependencies: TweenService, RemoteEvent ToggleDoor, Model Attributes

local TweenService = game:GetService("TweenService")

local SlidingDoor = {}

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

	local closedPosition = door.Position
	local closedRotation = door.CFrame - door.Position
	local isOpen = false
	local isAnimating = false
	local onCooldown = false

	local function targetCFrameForState(openState)
		local targetPosition = closedPosition
		if openState then
			targetPosition = closedPosition + (slidePivot.CFrame.LookVector * (slideDistance * slideDirection))
		end

		return CFrame.new(targetPosition) * closedRotation
	end

	local function beginCooldown()
		onCooldown = true
		task.delay(cooldown, function()
			onCooldown = false
		end)
	end

	toggleDoor.OnServerEvent:Connect(function()
		if onCooldown or isAnimating then
			return
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
	end)

	return true
end

return SlidingDoor