-- EmberMovementHandler
-- Applies cabina movement locally so Roblox character controls stay responsive.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VRService = game:GetService("VRService")

local PLAYER = Players.LocalPlayer
local REMOTE_EVENT_NAME = "EmberMovementUpdate"
local DEFAULT_STALE_SECONDS = 0.75

local currentDirection = "idle"
local staleSeconds = DEFAULT_STALE_SECONDS
local lastUpdateAt = 0

local VALID_DIRECTIONS = {
	idle = true,
	forward = true,
	backward = true,
	left = true,
	right = true,
}

local function horizontalUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 0.001 then
		return Vector3.zero
	end

	return flat.Unit
end

local function getController()
	local character = PLAYER.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end

	return humanoid
end

local function basisVectors()
	local camera = workspace.CurrentCamera
	if camera then
		return horizontalUnit(camera.CFrame.LookVector), horizontalUnit(camera.CFrame.RightVector)
	end

	local character = PLAYER.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		return horizontalUnit(rootPart.CFrame.LookVector), horizontalUnit(rootPart.CFrame.RightVector)
	end

	return Vector3.zero, Vector3.zero
end

local function directionToMoveVector(direction)
	local forward, right = basisVectors()

	if direction == "forward" then
		return forward
	elseif direction == "backward" then
		return -forward
	elseif direction == "left" then
		return -right
	elseif direction == "right" then
		return right
	end

	return Vector3.zero
end

local function shouldControlMovement()
	return PLAYER:GetAttribute("EmberMovementDisabled") ~= true
end

local movementEvent = ReplicatedStorage:WaitForChild(REMOTE_EVENT_NAME)

movementEvent.OnClientEvent:Connect(function(direction, serverStaleSeconds)
	if not VALID_DIRECTIONS[direction] then
		direction = "idle"
	end

	currentDirection = direction
	lastUpdateAt = os.clock()

	if type(serverStaleSeconds) == "number" and serverStaleSeconds > 0 then
		staleSeconds = serverStaleSeconds
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local humanoid = getController()
	if not humanoid then
		return
	end

	if not shouldControlMovement() then
		return
	end

	local direction = currentDirection
	if os.clock() - lastUpdateAt > staleSeconds then
		direction = "idle"
	end

	if direction == "idle" then
		return
	end

	if VRService and VRService.VREnabled then
		local character = PLAYER.Character
		local moveVec = directionToMoveVector(direction)
		local speed = humanoid.WalkSpeed or 16
		local delta = moveVec * speed * dt
		if character and character:IsA("Model") then
			if character.Pivot and character.Pivot ~= nil and character.GetPivot then
				local currentPivot = character:GetPivot()
				character:PivotTo(currentPivot + Vector3.new(delta.X, delta.Y, delta.Z))
				else
					local hrp = character:FindFirstChild("HumanoidRootPart")
					if hrp then
						hrp.CFrame = hrp.CFrame + delta
					end
			end
		end
	else
		humanoid:Move(directionToMoveVector(direction), false)
	end
end)
