-- HingeDoor.lua
-- Purpose: Handles server-side hinge door toggling for a single door model.
-- Dependencies: TweenService, RemoteEvent ToggleDoor, Model Attributes

local TweenService = game:GetService("TweenService")

local HingeDoor = {}

function HingeDoor.init(doorModel)
	if not doorModel or not doorModel:IsA("Model") then
		return false
	end

	local fullName = doorModel:GetFullName()
	local openAngle = doorModel:GetAttribute("OpenAngle")
	local openTime = doorModel:GetAttribute("OpenTime")
	local cooldown = doorModel:GetAttribute("Cooldown")

	if typeof(openAngle) ~= "number" then
		warn("[HingeDoor] Invalid or missing OpenAngle on " .. fullName)
		return false
	end

	if typeof(openTime) ~= "number" then
		warn("[HingeDoor] Invalid or missing OpenTime on " .. fullName)
		return false
	end

	if typeof(cooldown) ~= "number" then
		warn("[HingeDoor] Invalid or missing Cooldown on " .. fullName)
		return false
	end

	local door = doorModel:FindFirstChild("Door")
	local hinge = doorModel:FindFirstChild("Hinge")
	local toggleDoor = doorModel:FindFirstChild("ToggleDoor")

	if not door or not door:IsA("BasePart") then
		warn("[HingeDoor] Missing Door BasePart on " .. fullName)
		return false
	end

	if not hinge or not hinge:IsA("BasePart") then
		warn("[HingeDoor] Missing Hinge BasePart on " .. fullName)
		return false
	end

	if not toggleDoor or not toggleDoor:IsA("RemoteEvent") then
		warn("[HingeDoor] Missing ToggleDoor RemoteEvent on " .. fullName)
		return false
	end

	local closedRelative = hinge.CFrame:ToObjectSpace(door.CFrame)
	local isOpen = false
	local isAnimating = false
	local onCooldown = false

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

	toggleDoor.OnServerEvent:Connect(function()
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
		isAnimating = false
		beginCooldown()
	end)

	return true
end

return HingeDoor