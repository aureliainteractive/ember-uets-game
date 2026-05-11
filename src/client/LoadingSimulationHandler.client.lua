local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UIManager = require(ReplicatedStorage.Shared.UIManager)
local ContentProvider = game:GetService("ContentProvider")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local player = Players.LocalPlayer

local loadingUI = UIManager.get(player:WaitForChild("PlayerGui"), "LoadingUI")

local loadingEvent = ReplicatedStorage:WaitForChild("SimulationLoadingEvent")
local loadingReadyEvent = ReplicatedStorage:WaitForChild("SimulationLoadingReady")
local controllerHUDEvent = ReplicatedStorage:WaitForChild("ControllerUI_HUD")
local KioskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig"))

-- Acceder a ColorCorrection existente
local Lighting = game:GetService("Lighting")
local colorCorrection = Lighting:FindFirstChild("ColorCorrection")

local function fadeBrightness(startValue, endValue, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	if colorCorrection then
		colorCorrection.Brightness = startValue
		local tween = TweenService:Create(colorCorrection, TweenInfo.new(duration, easingStyle, easingDir), { Brightness = endValue })
		tween:Play()
		return tween
	end
end

local function getAssetCategory(instance)
	if instance:IsA("Sound") then
		return "sonidos"
	elseif instance:IsA("Animation") then
		return "animaciones"
	elseif instance:IsA("ParticleEmitter") or instance:IsA("Trail") then
		return "efectos visuales"
	elseif instance:IsA("MeshPart") or instance:IsA("SpecialMesh") then
		return "modelos 3D"
	elseif instance:IsA("Decal") or instance:IsA("Texture") or instance:IsA("ImageLabel") or instance:IsA("ImageButton") or instance:IsA("SurfaceAppearance") then
		return "texturas e interfaz"
	end
	return "recursos del juego"
end

local function buildPreloadTargets()
	local targets = {}
	for _, descendant in ipairs(game:GetDescendants()) do
		if descendant:IsA("Decal")
			or descendant:IsA("Texture")
			or descendant:IsA("ImageLabel")
			or descendant:IsA("ImageButton")
			or descendant:IsA("Sound")
			or descendant:IsA("Animation")
			or descendant:IsA("MeshPart")
			or descendant:IsA("SpecialMesh")
			or descendant:IsA("SurfaceAppearance")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Trail")
		then
			targets[#targets + 1] = descendant
		end
	end
	return targets
end

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
local PRELOAD_TIMEOUT = 45
local PRELOAD_RETRY_PASSES = 1
local LOADING_WATCHDOG_TIMEOUT = PRELOAD_TIMEOUT + 10

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
		-- Fade brightness: -1 → 0 (aclarar pantalla, instantáneamente)
		colorCorrection.Brightness = 0
		return
	end

	LoadingNowLabel.Text = "Listo"
	setLoadingProgress(END_SCALE_X, true)

	-- Fade brightness: -1 → 0 (aclarar pantalla)
	task.spawn(function()
		fadeBrightness(-1, 0, 0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end)

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
	local readySent = false
	isVisible = true
	progressThreadActive = true

	local function fireReadyOnce(reason)
		if readySent or token ~= transitionToken then
			return
		end
		readySent = true
		pcall(function()
			loadingReadyEvent:FireServer(payload.mode, payload.location, payload.diff)
		end)
		Logger.info(
			"Network",
			string.format(
				"Simulation loading ready sent (%s) for %s in %.2fs",
				tostring(reason),
				tostring(payload.mode),
				tick() - startedAt
			)
		)
	end

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
	Logger.info(
		"UI",
		string.format(
			"Simulation loading started for %s | %s | %s",
			tostring(payload.mode),
			tostring(payload.location),
			tostring(payload.diff)
		)
	)

	-- Fade brightness: 0 → -1 (oscurecer pantalla)
	task.spawn(function()
		fadeBrightness(0, -1, 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
	end)

	task.spawn(function()
		-- Real preload: construir lista de targets y precargar con retry y timeout
		local preloadStartedAt = tick()
		local targets = buildPreloadTargets()
		local total = math.max(#targets, 1)
		local loaded = 0
		local preloadFinished = false
		local seen = {}
		local failed = {}

		Logger.debug("UI", string.format("Simulation preload targets=%d", #targets))

		local function runPreloadPass(passTargets, passName)
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync(passTargets, function(asset, status)
					if not seen[asset] then
						seen[asset] = true
						loaded = loaded + 1
					end
					local category = typeof(asset) == "Instance" and getAssetCategory(asset) or "recursos del juego"
					local percent = math.clamp(math.floor((loaded / total) * 100 + 0.5), 0, 100)
					if status == Enum.AssetFetchStatus.Failure then
						failed[asset] = true
						LoadingNowLabel.Text = string.format("Cargando: %s (%d%%, reintentando)", category, percent)
					else
						failed[asset] = nil
						LoadingNowLabel.Text = string.format("Cargando: %s (%d%%)", category, percent)
					end
					setLoadingProgress(math.max(START_SCALE_X, (percent / 100)), true)
				end)
			end)

			if not ok then
				Logger.error("UI", string.format("Simulation preload pass '%s' failed: %s", passName, tostring(err)))
			end
		end

		if #targets == 0 then
			LoadingNowLabel.Text = "No hay assets que precargar"
			preloadFinished = true
		else
			LoadingNowLabel.Text = "Cargando entorno 3D..."
			setLoadingProgress(0.55)

			task.spawn(function()
				runPreloadPass(targets, "initial")

				for pass = 1, PRELOAD_RETRY_PASSES do
					local retryTargets = {}
					for asset, isFailed in pairs(failed) do
						if isFailed then
							retryTargets[#retryTargets + 1] = asset
						end
					end

					if #retryTargets == 0 then
						break
					end

					Logger.warn("UI", string.format("Simulation preload retry pass %d with %d assets", pass, #retryTargets))
					LoadingNowLabel.Text = string.format("Reintentando %d assets fallidos...", #retryTargets)
					runPreloadPass(retryTargets, "retry-" .. tostring(pass))
				end

				preloadFinished = true
			end)

			while
				not preloadFinished
				and token == transitionToken
				and progressThreadActive
				and isVisible
				and (tick() - preloadStartedAt) < PRELOAD_TIMEOUT
			do
				task.wait(0.1)
			end

			if not preloadFinished then
				LoadingNowLabel.Text = "Carga lenta detectada, continuando..."
				Logger.warn("UI", string.format("Simulation preload timeout after %.2fs", PRELOAD_TIMEOUT))
			end
		end

		local failureCount = 0
		for _, isFailed in pairs(failed) do
			if isFailed then
				failureCount += 1
			end
		end
		if failureCount > 0 then
			Logger.warn("UI", string.format("Simulation preload finished with failures=%d", failureCount))
		else
			Logger.debug("UI", "Simulation preload finished with no failures")
		end

		-- Asegurar duración mínima visual
		while token == transitionToken and progressThreadActive and isVisible and (tick() - startedAt) < MIN_LOADING_DURATION do
			task.wait(0.1)
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

		fireReadyOnce("normal")
	end)

	task.delay(LOADING_WATCHDOG_TIMEOUT, function()
		if token == transitionToken and isVisible and not readySent then
			Logger.warn(
				"UI",
				string.format("Simulation loading watchdog reached (%.2fs), forcing ready signal", LOADING_WATCHDOG_TIMEOUT)
			)
			LoadingNowLabel.Text = "Carga lenta detectada, sincronizando..."
			setLoadingProgress(END_SCALE_X, true)
			progressThreadActive = false
			fireReadyOnce("watchdog-timeout")
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
