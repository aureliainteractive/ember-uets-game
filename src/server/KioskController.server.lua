-- KioskController
-- Purpose: Physical in-world kiosk for simulation configuration
--          and launch. Detects player proximity via Hitbox part,
--          presents mode/location/difficulty selection UI, then
--          fires SimulationStartBindable to start the simulation.
-- Place file: Workspace.Menu (Model) must exist with children
--             MenuScreen (Part > SurfaceGui) and Hitbox (Part).

local Menu       = workspace:WaitForChild("Menu")
local gui        = Menu:WaitForChild("MenuScreen"):WaitForChild("SurfaceGui")
local hitboxPart = Menu:WaitForChild("Hitbox")

local startConfigBtn          = gui:WaitForChild("StartConfig")
local ModeSelectorFrame       = gui:WaitForChild("ModeSelector")
local DiffSelectorFrame       = gui:WaitForChild("DiffSelector")
local LocationSelectorFrame   = gui:WaitForChild("LocationSelector")
local blk                     = gui:WaitForChild("BLK")
local awaitTouchLabel         = blk:WaitForChild("WaitingLabel")
local infoLabel               = blk:WaitForChild("infoLabel")
local confLabelsFrame         = gui:WaitForChild("ConfirmationLabels")
local confInfoFrame           = gui:WaitForChild("ConfirmationInfo")
local confPlayBtn             = gui:WaitForChild("ConfirmationPlay")

local SimulationStartBindable =
  game.ReplicatedStorage:WaitForChild("SimulationStartBindable")

local selectionEvent = Instance.new("BindableEvent")

local mode, diff, loc  = nil, nil, nil
local currentPlayer    = nil
local configInProgress = false

-- Suspends the calling coroutine until a TextButton in
-- the given frame is clicked. Returns the button's Name.
local function waitForButtonClick(frame)
	local connections = {}
	local result
	for _, v in pairs(frame:GetChildren()) do
		if v:IsA("TextButton") then
			connections[#connections + 1] = v.MouseButton1Click:Connect(function()
				result = v.Name
				selectionEvent:Fire()
			end)
		end
	end
	selectionEvent.Event:Wait()
	for _, conn in pairs(connections) do conn:Disconnect() end
	return result
end

-- Resets all kiosk UI and state variables to idle.
local function resetKiosk()
	currentPlayer                 = nil
	configInProgress              = false
	mode, diff, loc               = nil, nil, nil
	startConfigBtn.Visible        = false
	awaitTouchLabel.Visible       = true
	ModeSelectorFrame.Visible     = false
	LocationSelectorFrame.Visible = false
	DiffSelectorFrame.Visible     = false
	confInfoFrame.Visible         = false
	confLabelsFrame.Visible       = false
	confPlayBtn.Visible           = false
	infoLabel.Visible             = false
	blk.Visible                   = false
end

-- Runs the full mode → location → difficulty selection flow.
local function startConfig()
	configInProgress = true
	startConfigBtn.Visible = false
	infoLabel.Visible = true

	ModeSelectorFrame.Visible = true
	infoLabel.Text = "Selecciona el Simulacro que deseas jugar"
	mode = waitForButtonClick(ModeSelectorFrame)
	ModeSelectorFrame.Visible = false

	LocationSelectorFrame.Visible = true
	infoLabel.Text = "Selecciona la Ubicación donde deseas empezar"
	loc = waitForButtonClick(LocationSelectorFrame)
	LocationSelectorFrame.Visible = false

	DiffSelectorFrame.Visible = true
	infoLabel.Text = "Selecciona la dificultad en la que deseas jugar"
	diff = waitForButtonClick(DiffSelectorFrame)
	DiffSelectorFrame.Visible = false

	confInfoFrame.modeLabel.Text     = mode
	confInfoFrame.diffLabel.Text     = diff
	confInfoFrame.locationLabel.Text = loc
	confInfoFrame.Visible  = true
	confLabelsFrame.Visible = true
	confPlayBtn.Visible    = true
end

-- Fires simulation start when player confirms selection.
confPlayBtn.MouseButton1Click:Connect(function()
	local playerSnapshot = currentPlayer
	if not (mode and diff and loc
		and playerSnapshot
		and playerSnapshot.Parent) then
		return
	end

	confInfoFrame.Visible   = false
	confLabelsFrame.Visible = false
	confPlayBtn.Visible     = false
	blk.Visible             = true
	infoLabel.Visible       = true
	infoLabel.Text          = "Iniciando simulación..."

	SimulationStartBindable:Fire(playerSnapshot, mode, loc, diff)
	print("Simulación iniciada para " .. playerSnapshot.Name)
	print("Modo: " .. mode .. ", Ubicación: " .. loc .. ", Dificultad: " .. diff)

	mode, diff, loc  = nil, nil, nil
	configInProgress = false

	task.wait(3)
	infoLabel.Visible = false
	blk.Visible       = false
	if currentPlayer then
		startConfigBtn.Visible = true
	end
end)

startConfigBtn.MouseButton1Click:Connect(startConfig)

-- Shows the Start button when a player steps onto the hitbox.
hitboxPart.Touched:Connect(function(hit)
	local humanoid = hit.Parent:FindFirstChild("Humanoid")
	if not humanoid or configInProgress then return end
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	if player and not currentPlayer then
		currentPlayer = player
		startConfigBtn.Visible  = true
		awaitTouchLabel.Visible = false
		print(player.Name .. " entró a la zona")
	end
end)

-- Resets kiosk when the player leaves the hitbox.
hitboxPart.TouchEnded:Connect(function(hit)
	local humanoid = hit.Parent:FindFirstChild("Humanoid")
	if not humanoid then return end
	local player = game.Players:GetPlayerFromCharacter(hit.Parent)
	if player ~= currentPlayer then return end

	task.wait(0.1)
	for _, part in pairs(hitboxPart:GetTouchingParts()) do
		if part.Parent == player.Character then return end
	end

	print(player.Name .. " salió de la zona (config cancelada)")
	resetKiosk()
end)

-- Resets kiosk if the current player disconnects mid-config.
game.Players.PlayerRemoving:Connect(function(player)
	if player == currentPlayer then
		print(player.Name .. " desconectado — kiosk reseteado")
		resetKiosk()
	end
end)