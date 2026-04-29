local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIManager = require(ReplicatedStorage.Shared.UIManager)

local player = Players.LocalPlayer

local loadingUI = UIManager.get(player:WaitForChild("PlayerGui"), "LoadingUI")

local loadingEvent = ReplicatedStorage:WaitForChild("SimulationLoadingEvent")
local loadingReadyEvent = ReplicatedStorage:WaitForChild("SimulationLoadingReady")
local controllerHUDEvent = ReplicatedStorage:WaitForChild("ControllerUI_HUD")
local KioskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig"))

local BackgroundFrame = loadingUI:WaitForChild("Background")
local LoadingBar = loadingUI:WaitForChild("LoadingBar")
local LoadingBarFill = LoadingBar:WaitForChild("FillBar")
local LoadingCircles = loadingUI:WaitForChild("LoadingCircles")
local HeroText = loadingUI:WaitForChild("HeroText")
local Logo = loadingUI:WaitForChild("Logo")
local InfoContainer = loadingUI:WaitForChild("InfoContainer")
local InfoLabel = InfoContainer:WaitForChild("Info")
local LoadingNowLabel = loadingUI:FindFirstChild("LoadingNow")

local START_SCALE_X = 0.15
local END_SCALE_X = 1
local MIN_LOADING_DURATION = 6

local TWEEN_IN = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.32, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local TWEEN_PROGRESS = TweenInfo.new(0.85, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local TWEEN_PROGRESS_FAST = TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local BAR_Y_SCALE = LoadingBarFill.Size.Y.Scale
local BAR_Y_OFFSET = LoadingBarFill.Size.Y.Offset

local transitionToken = 0
local progressThreadActive = false
local isVisible = false

local UI_ITEMS = {
	BackgroundFrame,
	Logo,
	HeroText,
	LoadingBar,
	LoadingCircles,
	InfoContainer,
	InfoLabel,
	LoadingNowLabel,
}

local SHOW_POSITIONS = {}
local HIDE_POSITIONS = {}
local IMAGE_DEFAULT_TRANSPARENCY = {}
local BG_DEFAULT_TRANSPARENCY = {}
local TEXT_DEFAULT_TRANSPARENCY = {}
local VISIBLE_DEFAULT = {}

local function toHidden(pos, yDelta)
	return UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale + (yDelta or 0.03), pos.Y.Offset)
end

local function captureDefaults()
	for _, ui in ipairs(UI_ITEMS) do
		SHOW_POSITIONS[ui] = ui.Position
		HIDE_POSITIONS[ui] = toHidden(ui.Position)
		if ui:IsA("GuiObject") then
			VISIBLE_DEFAULT[ui] = ui.Visible
		end
		if ui:IsA("ImageLabel") or ui:IsA("ImageButton") then
			IMAGE_DEFAULT_TRANSPARENCY[ui] = ui.ImageTransparency
		end
		if ui:IsA("Frame") or ui:IsA("TextLabel") or ui:IsA("TextButton") then
			BG_DEFAULT_TRANSPARENCY[ui] = ui.BackgroundTransparency
		end
		if ui:IsA("TextLabel") or ui:IsA("TextButton") then
			TEXT_DEFAULT_TRANSPARENCY[ui] = ui.TextTransparency
		end
	end

	TEXT_DEFAULT_TRANSPARENCY[InfoLabel] = InfoLabel.TextTransparency
	TEXT_DEFAULT_TRANSPARENCY[LoadingNowLabel] = LoadingNowLabel.TextTransparency
	BG_DEFAULT_TRANSPARENCY[InfoContainer] = InfoContainer.BackgroundTransparency
	IMAGE_DEFAULT_TRANSPARENCY[Logo] = Logo.ImageTransparency
end

local function tween(obj, info, goal)
	local t = TweenService:Create(obj, info, goal)
	t:Play()
	return t
end

local function setHiddenImmediate()
	for _, ui in ipairs(UI_ITEMS) do
		ui.Position = HIDE_POSITIONS[ui]
		if ui:IsA("GuiObject") then
			ui.Visible = false
		end
		if ui:IsA("ImageLabel") or ui:IsA("ImageButton") then
			ui.ImageTransparency = 1
		end
		if ui:IsA("Frame") or ui:IsA("TextLabel") or ui:IsA("TextButton") then
			ui.BackgroundTransparency = 1
		end
		if ui:IsA("TextLabel") or ui:IsA("TextButton") then
			ui.TextTransparency = 1
		end
	end

	InfoLabel.TextTransparency = 1
	LoadingNowLabel.TextTransparency = 1
	LoadingBarFill.Size = UDim2.new(START_SCALE_X, 0, BAR_Y_SCALE, BAR_Y_OFFSET)
end

local function setVisibleDefaults()
	for _, ui in ipairs(UI_ITEMS) do
		if ui:IsA("GuiObject") then
			ui.Visible = (VISIBLE_DEFAULT[ui] ~= false)
		end
		if IMAGE_DEFAULT_TRANSPARENCY[ui] ~= nil then
			ui.ImageTransparency = IMAGE_DEFAULT_TRANSPARENCY[ui]
		end
		if BG_DEFAULT_TRANSPARENCY[ui] ~= nil then
			ui.BackgroundTransparency = BG_DEFAULT_TRANSPARENCY[ui]
		end
		if TEXT_DEFAULT_TRANSPARENCY[ui] ~= nil then
			ui.TextTransparency = TEXT_DEFAULT_TRANSPARENCY[ui]
		end
	end
	InfoLabel.TextTransparency = TEXT_DEFAULT_TRANSPARENCY[InfoLabel] or 0
	LoadingNowLabel.TextTransparency = TEXT_DEFAULT_TRANSPARENCY[LoadingNowLabel] or 0
end

local function setLoadingProgress(scaleX, fast)
	local clamped = math.clamp(scaleX, START_SCALE_X, END_SCALE_X)
	local info = fast and TWEEN_PROGRESS_FAST or TWEEN_PROGRESS
	tween(LoadingBarFill, info, {
		Size = UDim2.new(clamped, 0, BAR_Y_SCALE, BAR_Y_OFFSET),
	})
end

local function hideLoading(immediate)
	if not isVisible and not immediate then
		return
	end

	transitionToken += 1
	local token = transitionToken
	progressThreadActive = false
	isVisible = false

	if immediate then
		setHiddenImmediate()
		loadingUI.Enabled = false
		return
	end

	LoadingNowLabel.Text = "Listo"
	setLoadingProgress(END_SCALE_X, true)

	for index = #UI_ITEMS, 1, -1 do
		local ui = UI_ITEMS[index]
		local hiddenPos = HIDE_POSITIONS[ui]
		task.delay((#UI_ITEMS - index) * 0.03, function()
			if token ~= transitionToken then
				return
			end
			local goals = { Position = hiddenPos }
			if IMAGE_DEFAULT_TRANSPARENCY[ui] ~= nil then
				goals.ImageTransparency = 1
			end
			if BG_DEFAULT_TRANSPARENCY[ui] ~= nil then
				goals.BackgroundTransparency = 1
			end
			if TEXT_DEFAULT_TRANSPARENCY[ui] ~= nil then
				goals.TextTransparency = 1
			end
			tween(ui, TWEEN_OUT, goals)
		end)
	end

	task.delay(TWEEN_OUT.Time + (#UI_ITEMS * 0.03) + 0.02, function()
		if token ~= transitionToken then
			return
		end
		setHiddenImmediate()
		setVisibleDefaults()
		loadingUI.Enabled = false
	end)
end

local function showLoading(payload)
	transitionToken += 1
	local token = transitionToken
	local startedAt = tick()
	isVisible = true
	progressThreadActive = true

	loadingUI.Enabled = true
	setHiddenImmediate()

	InfoLabel.Text = string.format(
		"Cargando %s | %s | %s",
		tostring(payload.location or "Ubicacion"),
		KioskConfig.getModeDisplay(payload.mode or "Simulacion"),
		KioskConfig.getDifficultyDisplay(payload.diff or "Nivel")
	)
	LoadingNowLabel.Text = "Sincronizando configuracion..."

	for index, ui in ipairs(UI_ITEMS) do
		local showPos = SHOW_POSITIONS[ui]
		task.delay((index - 1) * 0.04, function()
			if token ~= transitionToken or not isVisible then
				return
			end
			if ui:IsA("GuiObject") then
				ui.Visible = true
			end
			local goals = { Position = showPos }
			if IMAGE_DEFAULT_TRANSPARENCY[ui] ~= nil then
				goals.ImageTransparency = IMAGE_DEFAULT_TRANSPARENCY[ui]
			end
			if BG_DEFAULT_TRANSPARENCY[ui] ~= nil then
				goals.BackgroundTransparency = BG_DEFAULT_TRANSPARENCY[ui]
			end
			if TEXT_DEFAULT_TRANSPARENCY[ui] ~= nil then
				goals.TextTransparency = TEXT_DEFAULT_TRANSPARENCY[ui]
			end
			tween(ui, TWEEN_IN, goals)
		end)
	end

	setLoadingProgress(0.22, true)

	task.spawn(function()
		task.wait(0.6)
		if token ~= transitionToken or not progressThreadActive then
			return
		end
		LoadingNowLabel.Text = "Cargando entorno 3D..."
		setLoadingProgress(0.55)

		task.wait(0.95)
		if token ~= transitionToken or not progressThreadActive then
			return
		end
		LoadingNowLabel.Text = "Iniciando simulacion..."
		setLoadingProgress(0.78)

		if payload.mode == "FireSimulation" then
			task.wait(0.75)
			if token ~= transitionToken or not progressThreadActive then
				return
			end
			LoadingNowLabel.Text = "Preparando calefaccion..."
			setLoadingProgress(0.86)
		else
			setLoadingProgress(0.86)
		end

		while
			token == transitionToken
			and progressThreadActive
			and isVisible
			and (tick() - startedAt) < MIN_LOADING_DURATION
		do
			tween(LoadingBarFill, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.new(0.92, 0, BAR_Y_SCALE, BAR_Y_OFFSET),
			})
			task.wait(0.95)
			if
				token ~= transitionToken
				or not progressThreadActive
				or not isVisible
				or (tick() - startedAt) >= MIN_LOADING_DURATION
			then
				break
			end
			tween(LoadingBarFill, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
				Size = UDim2.new(0.88, 0, BAR_Y_SCALE, BAR_Y_OFFSET),
			})
			task.wait(0.95)
		end

		if token ~= transitionToken or not progressThreadActive or not isVisible then
			return
		end
		LoadingNowLabel.Text = "Trasladando participante..."
		setLoadingProgress(END_SCALE_X, true)
		task.wait(0.4)
		if token ~= transitionToken or not progressThreadActive or not isVisible then
			return
		end

		pcall(function()
			loadingReadyEvent:FireServer(payload.mode, payload.location, payload.diff)
		end)

		hideLoading(false)
	end)

	task.delay(25, function()
		if token == transitionToken and isVisible then
			progressThreadActive = false
		end
	end)
end

captureDefaults()
hideLoading(true)

loadingEvent.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and payload.action == "Start" then
		showLoading(payload)
		return
	end

	if type(payload) == "table" and payload.action == "Hide" then
		hideLoading(false)
		return
	end

	if payload == nil then
		hideLoading(false)
	end
end)

controllerHUDEvent.OnClientEvent:Connect(function(action)
	if action == "Show" then
		hideLoading(false)
	end
end)
