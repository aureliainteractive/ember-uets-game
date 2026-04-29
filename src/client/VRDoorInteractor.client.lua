local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local NexusVRCharacterModel = ReplicatedStorage:WaitForChild("NexusVRCharacterModel")

local VRInputService = require(NexusVRCharacterModel.State.VRInputService).GetInstance()

local MAX_DISTANCE = 2

local function fireToggleFromHand(hand)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end

	local inputs = VRInputService:GetVRInputs()
	local handCF = hand == "Left" and inputs[Enum.UserCFrame.LeftHand] or inputs[Enum.UserCFrame.RightHand]

	local worldCF = cam:GetRenderCFrame() * inputs[Enum.UserCFrame.Head]:Inverse() * handCF

	local result = Workspace:Raycast(worldCF.Position, worldCF.LookVector * MAX_DISTANCE)

	if not result then
		return
	end

	local inst = result.Instance
	while inst do
		local toggle = inst:FindFirstChild("ToggleDoor")
		if toggle and toggle:IsA("RemoteEvent") then
			print("📤 FireServer a ToggleDoor:", toggle:GetFullName())
			toggle:FireServer()
			return
		end
		inst = inst.Parent
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then
		return
	end
	if input.KeyCode == Enum.KeyCode.ButtonR2 then
		fireToggleFromHand("Right")
	elseif input.KeyCode == Enum.KeyCode.ButtonL2 then
		fireToggleFromHand("Left")
	end
end)
