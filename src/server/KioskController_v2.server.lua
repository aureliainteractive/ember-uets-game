-- KioskController_v2
-- Purpose: Physical in-world kiosk for simulation configuration
--          and launch. Detects player proximity via Hitbox part,
--          presents mode/location/difficulty selection UI, shows
--          a ConfirmationUI ScreenGui on the player's screen for
--          the final confirm/cancel step, then fires
--          SimulationStartBindable to start the simulation.
--          Using CanvasGroup for better UI state management.
-- Place file: Workspace.Menu (Model) must exist with children
--             MenuScreen (Part > SurfaceGui) and Hitbox (Part).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- KioskConfig: display names, descriptions, and step data.
local KioskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig"))

local SimulationStartBindable = ReplicatedStorage:WaitForChild("SimulationStartBindable")

local Menu = workspace:WaitForChild("Menu_v2")
local gui = Menu:WaitForChild("MenuScreen"):WaitForChild("SurfaceGui")
local hitboxPart = Menu:WaitForChild("Hitbox")

local homeCanvas = gui:WaitForChild("homeCanvas")
local typeCanvas = gui:WaitForChild("typeCanvas")
local typesFrame = typeCanvas:WaitForChild("types")
local envCanvas = gui:WaitForChild("envCanvas")
local envsFrame = envCanvas:WaitForChild("envs")
local diffCanvas = gui:WaitForChild("diffCanvas")
local diffsFrame = diffCanvas:WaitForChild("diffs")
local confirmationCanvas = gui:WaitForChild("confirmationCanvas")
local sysChecksFrame = confirmationCanvas:WaitForChild("statusCheck")
local buttonsFrame = confirmationCanvas:WaitForChild("buttons")
local infoFrame = confirmationCanvas:WaitForChild("info")

local startConfigBtn = homeCanvas:FindFirstChild("startConfigBtn")

local nextBtnName = "nextBtn"
local backBtnName = "backBtn"

local enabledControlCanvas = {
	homeCanvas = false,
	typeCanvas = true,
	envCanvas = true,
	diffCanvas = true,
	confirmationCanvas = false,
}

local eqkBtn = typesFrame:WaitForChild("eqkBtn")
local fireBtn = typesFrame:WaitForChild("fireBtn")
local armBtn = typesFrame:WaitForChild("armBtn")
local evacBtn = typesFrame:WaitForChild("evacBtn")

local emrBtn = envsFrame:WaitForChild("emrBtn") -- Stands for: Edificio Miguel Rua
local eccBtn = envsFrame:WaitForChild("eccBtn") -- Stands for: Edificio Carlos Crespi
local emmBtn = envsFrame:WaitForChild("emmBtn") -- Stands for: Edificio Mamá Margarita
local cmmoBtn = envsFrame:WaitForChild("cmmoBtn") -- Stands for: Coliseo Miguel Merchán Ochoa

local basicBtn = diffsFrame:WaitForChild("basicBtn")
local intBtn = diffsFrame:WaitForChild("intBtn")
local critBtn = diffsFrame:WaitForChild("critBtn")

local statuses = {
	cabinStatus = true,
	mpuStatus = true,
	headsetStatus = true,
	serverStatus = true,
	robloxStatus = true,
}

local DEFAULT_STATUS_OK_IMAGE = "rbxassetid://84290038693966"
local DEFAULT_STATUS_ERROR_IMAGE = "rbxassetid://112767078554500"
local DEFAULT_STATUS_OK_WIDTH = 39
local DEFAULT_STATUS_ERROR_WIDTH = 74

local function resolveStatusVisualConfig()
	local okImage = sysChecksFrame:GetAttribute("StatusOkImage")
	local errorImage = sysChecksFrame:GetAttribute("StatusErrorImage")
	local okWidth = sysChecksFrame:GetAttribute("StatusOkWidth")
	local errorWidth = sysChecksFrame:GetAttribute("StatusErrorWidth")

	if type(okImage) ~= "string" or okImage == "" then
		okImage = DEFAULT_STATUS_OK_IMAGE
	end
	if type(errorImage) ~= "string" or errorImage == "" then
		errorImage = DEFAULT_STATUS_ERROR_IMAGE
	end
	if type(okWidth) ~= "number" then
		okWidth = DEFAULT_STATUS_OK_WIDTH
	end
	if type(errorWidth) ~= "number" then
		errorWidth = DEFAULT_STATUS_ERROR_WIDTH
	end

	return okImage, errorImage, okWidth, errorWidth
end

local startNowBtn = buttonsFrame:WaitForChild("startNow")
local backBtn = buttonsFrame:WaitForChild("backBtn")
local cancelBtn = buttonsFrame:WaitForChild("cancelBtn")

local eventLabel = infoFrame:WaitForChild("eventLabel")
local envLabel = infoFrame:WaitForChild("envLabel")
local diffLabel = infoFrame:WaitForChild("diffLabel")
local durationLabel = infoFrame:WaitForChild("durationLabel")
local hapticsCheckLabel = infoFrame:FindFirstChild("hapticCheckLabel") or infoFrame:WaitForChild("hapticsCheckLabel")

-- ── ConfirmationUI RemoteEvents ──────────────────────────────────
-- Created here (server-authoritative) and waited on by the client.
local function getOrCreate(name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing then
		return existing
	end
	local e = Instance.new("RemoteEvent")
	e.Name = name
	e.Parent = ReplicatedStorage
	return e
end

local kioskShowConfirmationEvent = getOrCreate("KioskShowConfirmation")
local kioskConfirmEvent = getOrCreate("KioskConfirm")
local kioskCancelEvent = getOrCreate("KioskCancel")
local simulationLoadingEvent = getOrCreate("SimulationLoadingEvent")

local selectionEvent = Instance.new("BindableEvent")

local MODE_BY_BUTTON = {
	eqkBtn = "EarthquakeSimulation",
	fireBtn = "FireSimulation",
	armBtn = "ArmedGroupsSimulation",
	evacBtn = "ExploreSimulation",
}

local LOCATION_BY_BUTTON = {
	emrBtn = "Miguel Rua",
	eccBtn = "Carlos Crespi",
	emmBtn = "Patio de Comidas",
	cmmoBtn = "Coliseo",
}

local DIFFICULTY_BY_BUTTON = {
	basicBtn = "Easy",
	intBtn = "Medium",
	critBtn = "Hard",
}

local mode, diff, loc = nil, nil, nil
local currentPlayer = nil
local configInProgress = false
local pendingAction = nil
local waitingRemoteConfirm = false

local selectedModeButton = nil
local selectedEnvButton = nil
local selectedDiffButton = nil

local canvases = {
	homeCanvas = homeCanvas,
	typeCanvas = typeCanvas,
	envCanvas = envCanvas,
	diffCanvas = diffCanvas,
	confirmationCanvas = confirmationCanvas,
}

local CANVAS_FADE_OUT = TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local CANVAS_FADE_IN = TweenInfo.new(0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local currentCanvasName = "homeCanvas"
local canvasTransitionToken = 0

local selectableGroups = {
	mode = { eqkBtn, fireBtn, armBtn, evacBtn },
	env = { emrBtn, eccBtn, emmBtn, cmmoBtn },
	diff = { basicBtn, intBtn, critBtn },
}

local originalImages = {}
local hoverImages = {}

for _, group in pairs(selectableGroups) do
	for _, btn in ipairs(group) do
		originalImages[btn] = btn.Image
		hoverImages[btn] = btn.HoverImage
		btn.AutoButtonColor = false
	end
end

local function emitAction(action, value)
	pendingAction = {
		action = action,
		value = value,
	}
	selectionEvent:Fire()
end

local function restoreButtonVisuals(group)
	for _, btn in ipairs(group) do
		btn.Image = originalImages[btn]
	end
end

local function applySelectedVisual(group, selected)
	for _, btn in ipairs(group) do
		if btn == selected and hoverImages[btn] ~= "" then
			btn.Image = hoverImages[btn]
		else
			btn.Image = originalImages[btn]
		end
	end
end

local function updatePageIndicators()
	local typePage = typeCanvas:FindFirstChild("pageInd")
	local envPage = envCanvas:FindFirstChild("pageInd")
	local diffPage = diffCanvas:FindFirstChild("pageInd")

	if typePage and typePage:IsA("ImageLabel") then
		typePage.ImageColor3 = (mode and Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(170, 170, 170)
	end
	if envPage and envPage:IsA("ImageLabel") then
		envPage.ImageColor3 = (loc and Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(170, 170, 170)
	end
	if diffPage and diffPage:IsA("ImageLabel") then
		diffPage.ImageColor3 = (diff and Color3.fromRGB(255, 255, 255)) or Color3.fromRGB(170, 170, 170)
	end
end

local function setCurrentCanvas(canvasName, immediate)
	local targetCanvas = canvases[canvasName]
	if not targetCanvas then
		return
	end

	canvasTransitionToken += 1
	local token = canvasTransitionToken

	if immediate then
		for name, canvas in pairs(canvases) do
			canvas.Visible = (name == canvasName)
			canvas.GroupTransparency = (name == canvasName) and 0 or 1
		end
		currentCanvasName = canvasName
		updatePageIndicators()
		return
	end

	local previousCanvas = canvases[currentCanvasName]
	if previousCanvas == targetCanvas then
		targetCanvas.Visible = true
		targetCanvas.GroupTransparency = 0
		currentCanvasName = canvasName
		updatePageIndicators()
		return
	end

	targetCanvas.Visible = true
	targetCanvas.GroupTransparency = 1

	local fadeIn = TweenService:Create(targetCanvas, CANVAS_FADE_IN, { GroupTransparency = 0 })
	local fadeOut
	if previousCanvas then
		previousCanvas.Visible = true
		previousCanvas.GroupTransparency = 0
		fadeOut = TweenService:Create(previousCanvas, CANVAS_FADE_OUT, { GroupTransparency = 1 })
		fadeOut:Play()
	end
	fadeIn:Play()
	fadeIn.Completed:Wait()

	if token ~= canvasTransitionToken then
		return
	end

	if previousCanvas and previousCanvas ~= targetCanvas then
		previousCanvas.Visible = false
	end

	currentCanvasName = canvasName
	updatePageIndicators()
end

local function setStatusChecksVisuals()
	local statusOkImage, statusErrorImage, statusOkWidth, statusErrorWidth = resolveStatusVisualConfig()

	for statusName, isOk in pairs(statuses) do
		local indicator = sysChecksFrame:FindFirstChild(statusName)
		if indicator and indicator:IsA("ImageLabel") then
			local width = isOk and statusOkWidth or statusErrorWidth
			indicator.Image = isOk and statusOkImage or statusErrorImage
			indicator.Size = UDim2.new(indicator.Size.X.Scale, width, indicator.Size.Y.Scale, indicator.Size.Y.Offset)
		end
	end
end

local function getEstimatedDuration(modeKey)
	local steps = KioskConfig.getSteps(modeKey)
	local total = 0
	for _, t in ipairs(steps.maxTimes or {}) do
		total += t
	end
	if total <= 0 then
		return "Sin tiempo límite"
	end
	return string.format("%ds aprox.", total)
end

local function updateConfirmationInfo()
	eventLabel.Text = KioskConfig.getModeDisplay(mode)
	envLabel.Text = loc or "-"
	diffLabel.Text = KioskConfig.getDifficultyDisplay(diff)
	durationLabel.Text = getEstimatedDuration(mode)

	if mode == "EarthquakeSimulation" then
		hapticsCheckLabel.Visible = true
		hapticsCheckLabel.Text = "Habilitado"
	else
		hapticsCheckLabel.Visible = true
		hapticsCheckLabel.Text = "Deshabilitado"
	end

	setStatusChecksVisuals()
end

local function clearSelections()
	mode, diff, loc = nil, nil, nil
	selectedModeButton = nil
	selectedEnvButton = nil
	selectedDiffButton = nil
	restoreButtonVisuals(selectableGroups.mode)
	restoreButtonVisuals(selectableGroups.env)
	restoreButtonVisuals(selectableGroups.diff)
	updatePageIndicators()
end

local function resetKiosk()
	if currentPlayer and currentPlayer.Parent then
		pcall(function()
			kioskShowConfirmationEvent:FireClient(currentPlayer, nil)
		end)
	end

	currentPlayer = nil
	configInProgress = false
	waitingRemoteConfirm = false
	clearSelections()
	pendingAction = nil

	setCurrentCanvas("homeCanvas")
	startConfigBtn.Visible = false
	selectionEvent:Fire()
end

local function cancelAndReturnHome(message)
	if currentPlayer then
		pcall(function()
			kioskShowConfirmationEvent:FireClient(currentPlayer, nil)
		end)
	end

	configInProgress = false
	waitingRemoteConfirm = false
	clearSelections()
	if message then
		warn("[Kiosk v2] " .. message)
	end
	setCurrentCanvas("homeCanvas")
	if currentPlayer then
		startConfigBtn.Visible = true
	else
		startConfigBtn.Visible = false
	end
	selectionEvent:Fire()
end

local function waitForRemoteConfirmation()
	local decision = nil

	local confirmConn = kioskConfirmEvent.OnServerEvent:Connect(function(player)
		if player == currentPlayer then
			decision = true
			selectionEvent:Fire()
		end
	end)

	local cancelConn = kioskCancelEvent.OnServerEvent:Connect(function(player)
		if player == currentPlayer then
			decision = false
			selectionEvent:Fire()
		end
	end)

	while configInProgress and currentPlayer and decision == nil do
		selectionEvent.Event:Wait()
		if pendingAction and pendingAction.action == "cancelConfirmationWait" then
			decision = false
			pendingAction = nil
		end
	end

	confirmConn:Disconnect()
	cancelConn:Disconnect()

	return decision == true
end

local function beginConfig()
	if configInProgress or not currentPlayer then
		return
	end

	configInProgress = true
	startConfigBtn.Visible = false
	clearSelections()
	setCurrentCanvas("typeCanvas")
end

local function selectMode(buttonName)
	if not configInProgress then
		return
	end
	local value = MODE_BY_BUTTON[buttonName]
	if not value then
		return
	end

	if mode ~= value then
		loc = nil
		diff = nil
		selectedEnvButton = nil
		selectedDiffButton = nil
		restoreButtonVisuals(selectableGroups.env)
		restoreButtonVisuals(selectableGroups.diff)
	end

	mode = value
	selectedModeButton = ({
		eqkBtn = eqkBtn,
		fireBtn = fireBtn,
		armBtn = armBtn,
		evacBtn = evacBtn,
	})[buttonName]

	if selectedModeButton then
		applySelectedVisual(selectableGroups.mode, selectedModeButton)
	end

	updatePageIndicators()
end

local function selectLocation(buttonName)
	if not configInProgress then
		return
	end
	local value = LOCATION_BY_BUTTON[buttonName]
	if not value then
		return
	end

	loc = value
	selectedEnvButton = ({
		emrBtn = emrBtn,
		eccBtn = eccBtn,
		emmBtn = emmBtn,
		cmmoBtn = cmmoBtn,
	})[buttonName]

	if selectedEnvButton then
		applySelectedVisual(selectableGroups.env, selectedEnvButton)
	end

	updatePageIndicators()
end

local function selectDifficulty(buttonName)
	if not configInProgress then
		return
	end
	local value = DIFFICULTY_BY_BUTTON[buttonName]
	if not value then
		return
	end

	diff = value
	selectedDiffButton = ({
		basicBtn = basicBtn,
		intBtn = intBtn,
		critBtn = critBtn,
	})[buttonName]

	if selectedDiffButton then
		applySelectedVisual(selectableGroups.diff, selectedDiffButton)
	end

	updatePageIndicators()
end

local function onCanvasBack(canvasName)
	if not configInProgress then
		return
	end

	if canvasName == "typeCanvas" then
		cancelAndReturnHome("Configuración cancelada desde selección de simulacro")
		return
	end

	if canvasName == "envCanvas" then
		setCurrentCanvas("typeCanvas")
		return
	end

	if canvasName == "diffCanvas" then
		setCurrentCanvas("envCanvas")
		return
	end
end

local function onCanvasNext(canvasName)
	if not configInProgress then
		return
	end

	if canvasName == "typeCanvas" then
		if not mode then
			warn("[Kiosk v2] Selecciona un simulacro antes de continuar")
			return
		end
		setCurrentCanvas("envCanvas")
		return
	end

	if canvasName == "envCanvas" then
		if not loc then
			warn("[Kiosk v2] Selecciona una ubicación antes de continuar")
			return
		end
		setCurrentCanvas("diffCanvas")
		return
	end

	if canvasName == "diffCanvas" then
		if not diff then
			warn("[Kiosk v2] Selecciona una dificultad antes de continuar")
			return
		end
		updateConfirmationInfo()
		setCurrentCanvas("confirmationCanvas")
	end
end

local function requestFinalConfirmation()
	if not configInProgress or waitingRemoteConfirm then
		return
	end
	if not currentPlayer or not mode or not loc or not diff then
		return
	end

	waitingRemoteConfirm = true
	startNowBtn.Active = false
	startNowBtn.AutoButtonColor = false

	kioskShowConfirmationEvent:FireClient(currentPlayer, {
		mode = mode,
		location = loc,
		diff = diff,
	})

	task.spawn(function()
		local confirmed = waitForRemoteConfirmation()
		waitingRemoteConfirm = false
		startNowBtn.Active = true
		startNowBtn.AutoButtonColor = true

		if currentPlayer and currentPlayer.Parent then
			kioskShowConfirmationEvent:FireClient(currentPlayer, nil)
		end

		if not configInProgress or not currentPlayer then
			return
		end

		if not confirmed then
			cancelAndReturnHome("Selección cancelada por el jugador")
			return
		end

		local playerSnapshot = currentPlayer
		simulationLoadingEvent:FireClient(playerSnapshot, {
			action = "Start",
			mode = mode,
			location = loc,
			diff = diff,
		})
		SimulationStartBindable:Fire(playerSnapshot, mode, loc, diff)
		print(string.format("[Kiosk v2] Simulación iniciada para %s", playerSnapshot.Name))
		print(string.format("[Kiosk v2] Modo: %s, Ubicación: %s, Dificultad: %s", mode, loc, diff))

		configInProgress = false
		clearSelections()
		setCurrentCanvas("homeCanvas")
		if currentPlayer then
			startConfigBtn.Visible = true
		end
	end)
end

startConfigBtn.MouseButton1Click:Connect(beginConfig)

eqkBtn.MouseButton1Click:Connect(function()
	selectMode("eqkBtn")
end)
fireBtn.MouseButton1Click:Connect(function()
	selectMode("fireBtn")
end)
armBtn.MouseButton1Click:Connect(function()
	selectMode("armBtn")
end)
evacBtn.MouseButton1Click:Connect(function()
	selectMode("evacBtn")
end)

emrBtn.MouseButton1Click:Connect(function()
	selectLocation("emrBtn")
end)
eccBtn.MouseButton1Click:Connect(function()
	selectLocation("eccBtn")
end)
emmBtn.MouseButton1Click:Connect(function()
	selectLocation("emmBtn")
end)
cmmoBtn.MouseButton1Click:Connect(function()
	selectLocation("cmmoBtn")
end)

basicBtn.MouseButton1Click:Connect(function()
	selectDifficulty("basicBtn")
end)
intBtn.MouseButton1Click:Connect(function()
	selectDifficulty("intBtn")
end)
critBtn.MouseButton1Click:Connect(function()
	selectDifficulty("critBtn")
end)

for canvasName, enabled in pairs(enabledControlCanvas) do
	if enabled then
		local canvas = canvases[canvasName]
		local nextBtn = canvas:FindFirstChild(nextBtnName)
		local backBtnInCanvas = canvas:FindFirstChild(backBtnName)

		if nextBtn and nextBtn:IsA("ImageButton") then
			nextBtn.MouseButton1Click:Connect(function()
				onCanvasNext(canvasName)
			end)
		end

		if backBtnInCanvas and backBtnInCanvas:IsA("ImageButton") then
			backBtnInCanvas.MouseButton1Click:Connect(function()
				onCanvasBack(canvasName)
			end)
		end
	end
end

backBtn.MouseButton1Click:Connect(function()
	if waitingRemoteConfirm then
		emitAction("cancelConfirmationWait")
		return
	end
	setCurrentCanvas("diffCanvas")
end)

cancelBtn.MouseButton1Click:Connect(function()
	if waitingRemoteConfirm then
		emitAction("cancelConfirmationWait")
		return
	end
	cancelAndReturnHome("Configuración cancelada en confirmación")
end)

startNowBtn.MouseButton1Click:Connect(requestFinalConfirmation)

setCurrentCanvas("homeCanvas", true)
startConfigBtn.Visible = false

hitboxPart.Touched:Connect(function(hit)
	local humanoid = hit.Parent and hit.Parent:FindFirstChild("Humanoid")
	if not humanoid or configInProgress then
		return
	end

	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player and not currentPlayer then
		currentPlayer = player
		setCurrentCanvas("homeCanvas")
		startConfigBtn.Visible = true
		print(string.format("[Kiosk v2] %s entró a la zona", player.Name))
	end
end)

hitboxPart.TouchEnded:Connect(function(hit)
	local humanoid = hit.Parent and hit.Parent:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local player = Players:GetPlayerFromCharacter(hit.Parent)
	if player ~= currentPlayer then
		return
	end

	task.wait(0.1)
	for _, part in pairs(hitboxPart:GetTouchingParts()) do
		if part.Parent == player.Character then
			return
		end
	end

	print(string.format("[Kiosk v2] %s salió de la zona (config cancelada)", player.Name))
	resetKiosk()
end)

Players.PlayerRemoving:Connect(function(player)
	if player == currentPlayer then
		print(string.format("[Kiosk v2] %s desconectado — kiosk reseteado", player.Name))
		resetKiosk()
	end
end)
