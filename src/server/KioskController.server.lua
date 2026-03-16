-- KioskController
-- Purpose: Physical in-world kiosk for simulation configuration
--          and launch. Detects player proximity via Hitbox part,
--          presents mode/location/difficulty selection UI, shows
--          a ConfirmationUI ScreenGui on the player's screen for
--          the final confirm/cancel step, then fires
--          SimulationStartBindable to start the simulation.
-- Place file: Workspace.Menu (Model) must exist with children
--             MenuScreen (Part > SurfaceGui) and Hitbox (Part).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- KioskConfig: display names, descriptions, and step data.
local KioskConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig")
)

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

local SimulationStartBindable =
	ReplicatedStorage:WaitForChild("SimulationStartBindable")

-- ── ConfirmationUI RemoteEvents ──────────────────────────────────
-- Created here (server-authoritative) and waited on by the client.
local function getOrCreate(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then return existing end
	local e = Instance.new("RemoteEvent")
	e.Name   = name
	e.Parent = ReplicatedStorage
	return e
end

local kioskShowConfirmationEvent = getOrCreate("KioskShowConfirmation")
local kioskConfirmEvent          = getOrCreate("KioskConfirm")
local kioskCancelEvent           = getOrCreate("KioskCancel")

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
	-- Hide ConfirmationUI on the player's screen before clearing state.
	if currentPlayer and currentPlayer.Parent then
		pcall(function()
			kioskShowConfirmationEvent:FireClient(currentPlayer, nil)
		end)
	end
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
	infoLabel.Visible             = false
	blk.Visible                   = false
	-- Unblock any coroutine waiting on a selection or confirmation step.
	selectionEvent:Fire()
end

-- Runs the full mode → location → difficulty → confirmation flow.
local function startConfig()
	configInProgress   = true
	startConfigBtn.Visible = false
	blk.Visible        = true
	infoLabel.Visible  = true

	-- Step 1: Mode
	ModeSelectorFrame.Visible = true
	infoLabel.Text = "Selecciona el Simulacro que deseas jugar"
	mode = waitForButtonClick(ModeSelectorFrame)
	ModeSelectorFrame.Visible = false
	if not mode or not currentPlayer then configInProgress = false; return end

	-- Step 2: Location
	LocationSelectorFrame.Visible = true
	infoLabel.Text = "Selecciona la Ubicación donde deseas empezar"
	loc = waitForButtonClick(LocationSelectorFrame)
	LocationSelectorFrame.Visible = false
	if not loc or not currentPlayer then configInProgress = false; return end

	-- Step 3: Difficulty
	DiffSelectorFrame.Visible = true
	infoLabel.Text = "Selecciona la dificultad en la que deseas jugar"
	diff = waitForButtonClick(DiffSelectorFrame)
	DiffSelectorFrame.Visible = false
	if not diff or not currentPlayer then configInProgress = false; return end

	-- Step 4: Confirmation — show summary on the kiosk surface using
	-- display-friendly names from KioskConfig, then show the ScreenGui
	-- ConfirmationUI on the player's screen and await their decision.
	confInfoFrame.modeLabel.Text     = KioskConfig.getModeDisplay(mode)
	confInfoFrame.diffLabel.Text     = KioskConfig.getDifficultyDisplay(diff)
	confInfoFrame.locationLabel.Text = loc
	confInfoFrame.Visible            = true
	confLabelsFrame.Visible          = true
	infoLabel.Text = "Confirma la selección en tu pantalla"

	kioskShowConfirmationEvent:FireClient(currentPlayer, {
		mode     = mode,
		location = loc,
		diff     = diff,
	})

	-- Wait for the player to confirm or cancel via the ConfirmationUI.
	local confirmed = false

	local confirmConn = kioskConfirmEvent.OnServerEvent:Connect(function(p)
		if p == currentPlayer then
			confirmed = true
			selectionEvent:Fire()
		end
	end)
	local cancelConn = kioskCancelEvent.OnServerEvent:Connect(function(p)
		if p == currentPlayer then
			confirmed = false
			selectionEvent:Fire()
		end
	end)

	selectionEvent.Event:Wait()
	confirmConn:Disconnect()
	cancelConn:Disconnect()

	confInfoFrame.Visible   = false
	confLabelsFrame.Visible = false

	if not confirmed or not currentPlayer then
		-- Player cancelled or the session was reset externally.
		configInProgress = false
		mode, diff, loc  = nil, nil, nil
		if currentPlayer then
			-- Player is still in range — let them retry.
			infoLabel.Text = "Selección cancelada. Intenta de nuevo."
			task.wait(2)
			if currentPlayer then
				infoLabel.Visible      = false
				startConfigBtn.Visible = true
			end
		end
		return
	end

	-- Confirmed — launch the simulation.
	local playerSnapshot = currentPlayer
	infoLabel.Text = "Iniciando simulación..."

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
end

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