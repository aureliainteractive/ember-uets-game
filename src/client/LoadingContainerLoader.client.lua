local plyr = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

-- UTILS ----------------------------------------------------

local function tweenWait(obj, prop, startValue, endValue, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	obj[prop] = startValue
	local tween = TweenService:Create(obj, TweenInfo.new(duration, easingStyle, easingDir), { [prop] = endValue })
	tween:Play()
	tween.Completed:Wait()
end

local function tweenAsync(obj, prop, startValue, endValue, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	obj[prop] = startValue
	local tween = TweenService:Create(obj, TweenInfo.new(duration, easingStyle, easingDir), { [prop] = endValue })
	tween:Play()
	return tween
end

local function tweenWaitMulti(obj, props, startValues, endValues, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	local tweenGoals = {}
	for i, prop in ipairs(props) do
		obj[prop] = startValues[i]
		tweenGoals[prop] = endValues[i]
	end
	local tween = TweenService:Create(obj, TweenInfo.new(duration, easingStyle, easingDir), tweenGoals)
	tween:Play()
	tween.Completed:Wait()
end

local function tweenAsyncMulti(obj, props, startValues, endValues, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	local tweenGoals = {}
	for i, prop in ipairs(props) do
		obj[prop] = startValues[i]
		tweenGoals[prop] = endValues[i]
	end
	local tween = TweenService:Create(obj, TweenInfo.new(duration, easingStyle, easingDir), tweenGoals)
	tween:Play()
	return tween
end

local function fadeBrightness(startValue, endValue, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	local Lighting = game:GetService("Lighting")
	local colorCorrection = Lighting:FindFirstChild("ColorCorrection")
	if colorCorrection then
		colorCorrection.Brightness = startValue
		local tween = TweenService:Create(colorCorrection, TweenInfo.new(duration, easingStyle, easingDir), { Brightness = endValue })
		tween:Play()
		return tween
	end
end

-- Estado compartido de precarga para que la intro espere al progreso real
local preloadState = {
	targets = {},
	total = 1,
	loaded = 0,
	finished = false,
	failedCount = 0,
}

local INTRO_PRELOAD_TIMEOUT = 60
local PRELOAD_RETRY_PASSES = 1

--------------------------------------------------------------
-- ESPERAR JUEGO
--------------------------------------------------------------
if not game:IsLoaded() then
	game.Loaded:Wait()
end
task.wait(0.5)

--------------------------------------------------------------
-- REFERENCIAS
--------------------------------------------------------------
local gui = plyr.PlayerGui:WaitForChild("LoadingContainer")
local logos = gui:WaitForChild("SecondScreen")
local blk = gui:WaitForChild("BLK")
local logo = blk:WaitForChild("aureliaLogo")
local subtitle = blk:WaitForChild("subtitle")
local loadingStatus = logos:WaitForChild("LoadingStatus")

local gameVersion = game.PlaceVersion

local function setLoadingStatus(message)
	loadingStatus.Text = "Cargando: " .. message .. " - " .. gameVersion
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
	elseif
		instance:IsA("Decal")
		or instance:IsA("Texture")
		or instance:IsA("ImageLabel")
		or instance:IsA("ImageButton")
		or instance:IsA("SurfaceAppearance")
	then
		return "texturas e interfaz"
	end

	return "recursos del juego"
end

local function buildPreloadTargets()
	local targets = {}
	for _, descendant in ipairs(game:GetDescendants()) do
		if
			descendant:IsA("Decal")
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

local function startRealLoadingStatus()
	local targets = buildPreloadTargets()
	preloadState.targets = targets
	preloadState.total = math.max(#targets, 1)
	preloadState.loaded = 0
	preloadState.finished = false
	preloadState.failedCount = 0

	local startedAt = tick()
	Logger.info("UI", string.format("Intro preload started. targets=%d", #targets))

	if #targets == 0 then
		setLoadingStatus("No hay assets que precargar")
		preloadState.finished = true
		Logger.info("UI", "Intro preload skipped (no targets)")
		return
	end

	setLoadingStatus(string.format("Analizando %d assets del juego", preloadState.total))

	local seen = {}
	local failed = {}

	local function runPreloadPass(passTargets, passName)
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync(passTargets, function(asset, status)
				if not seen[asset] then
					seen[asset] = true
					preloadState.loaded += 1
				end
				local category = typeof(asset) == "Instance" and getAssetCategory(asset) or "recursos del juego"
				local percent = math.clamp(math.floor((preloadState.loaded / preloadState.total) * 100 + 0.5), 0, 100)
				if status == Enum.AssetFetchStatus.Failure then
					failed[asset] = true
					loadingStatus.Text = string.format("Cargando: %s (%d%%, reintentando)", category, percent)
				else
					failed[asset] = nil
					loadingStatus.Text = string.format("Cargando: %s (%d%%)", category, percent)
				end
			end)
		end)

		if not ok then
			Logger.error("UI", string.format("Intro preload pass '%s' failed: %s", passName, tostring(err)))
		end
	end

	task.spawn(function()
		runPreloadPass(preloadState.targets, "initial")

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

			Logger.warn("UI", string.format("Intro preload retry pass %d with %d failed assets", pass, #retryTargets))
			setLoadingStatus(string.format("Reintentando %d assets fallidos", #retryTargets))
			runPreloadPass(retryTargets, "retry-" .. tostring(pass))
		end

		local remainingFailures = 0
		for _, isFailed in pairs(failed) do
			if isFailed then
				remainingFailures += 1
			end
		end
		preloadState.failedCount = remainingFailures
		preloadState.finished = true

		local elapsed = tick() - startedAt
		if remainingFailures > 0 then
			loadingStatus.Text = string.format("Cargando: listo con %d incidencias", remainingFailures)
			Logger.warn("UI", string.format("Intro preload completed with failures=%d elapsed=%.2fs", remainingFailures, elapsed))
		else
			loadingStatus.Text = "Cargando: contenido del juego listo"
			Logger.info("UI", string.format("Intro preload completed successfully in %.2fs", elapsed))
		end
	end)
end

--------------------------------------------------------------
-- ESTADO INICIAL
--------------------------------------------------------------
gui.Enabled = true
logos.GroupTransparency = 1
logo.ImageTransparency = 1
subtitle.TextTransparency = 1
setLoadingStatus("Preparando assets del juego")

-- Fade brightness: 0 → -1 (oscurecer pantalla)
fadeBrightness(0, -1, 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

--------------------------------------------------------------
-- SECUENCIA SINCRONIZADA
--------------------------------------------------------------

-- [0.000 - 2.200] Textos entran con Back.Out para efecto cinematográfico
task.spawn(startRealLoadingStatus)
local tIn1 = tweenAsync(logo, "ImageTransparency", 1, 0, 2.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tIn2 = tweenAsync(subtitle, "TextTransparency", 1, 0, 2.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
tIn2.Completed:Wait()

-- Esperar hasta que la precarga real termine (o timeout) antes de continuar la secuencia
local startWait = tick()
while not preloadState.finished and (tick() - startWait) < INTRO_PRELOAD_TIMEOUT do
	-- mantener la intro visible; la tarea `startRealLoadingStatus` actualiza `loadingStatus`
	task.wait(0.1)
end

-- Si se alcanzó timeout, informar y continuar con la secuencia para no dejar al jugador atascado
if not preloadState.finished then
	setLoadingStatus("Carga ralentizada, continuando...")
	Logger.warn("UI", string.format("Intro preload timeout reached at %.2fs", INTRO_PRELOAD_TIMEOUT))
end

-- [3.200 - 4.700] Textos salen con Sine.In para suavidad
local tOut1 = tweenAsync(logo, "ImageTransparency", 0, 1, 1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local tOut2 = tweenAsync(subtitle, "TextTransparency", 0, 1, 1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
tOut2.Completed:Wait()

-- Logos fade-in y fade-out (timings conservados)
tweenWait(logos, "GroupTransparency", 1, 0, 3.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
tweenWait(logos, "GroupTransparency", 0, 1, 3, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

-- [11.200 - 12.095] Fade a negro con Sine.In
setLoadingStatus("Finalizando carga real")
tweenWait(
	blk,
	"BackgroundTransparency",
	blk.BackgroundTransparency,
	1,
	0.895,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.In
)

-- Fade brightness: -1 → 0 (aclarar pantalla)
fadeBrightness(-1, 0, 1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
if gui then
	task.wait(1.5)
end

gui.Enabled = false
