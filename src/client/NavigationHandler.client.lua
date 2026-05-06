local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")

local player = Players.LocalPlayer
local TELEPORT_EVENT_NAME = "Navigation_Teleport"

local teleportEvent = ReplicatedStorage:WaitForChild(TELEPORT_EVENT_NAME)

teleportEvent.OnClientEvent:Connect(function(targetCFrame)
    if typeof(targetCFrame) ~= "CFrame" then
        return
    end
    local character = player.Character
    if not character then
        return
    end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then
        return
    end

    if VRService and VRService.VREnabled then
        if character.PrimaryPart then
            character:SetPrimaryPartCFrame(targetCFrame)
        else
            hrp.CFrame = targetCFrame
        end
    else
        hrp.CFrame = targetCFrame
    end

    if humanoid and humanoid.CameraOffset then
        humanoid.CameraOffset = Vector3.zero
    end
end)

player.CharacterAdded:Connect(function()
    -- ensure handler remains robust after character respawn
end)
