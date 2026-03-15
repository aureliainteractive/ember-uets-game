-- DialogService
-- Purpose: Safe server-to-client dialog dispatch through ShowDialog RemoteEvent.
-- Dependencies: ReplicatedStorage.ShowDialog

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local showDialogEvent = ReplicatedStorage:WaitForChild("ShowDialog")

local DialogService = {}

-- Sends a dialog message to a specific player safely.
function DialogService.send(player, icon, text)
	if player and player:IsA("Player") and player.Parent then
		pcall(function()
			showDialogEvent:FireClient(player, icon, text)
		end)
	end
end

return DialogService
