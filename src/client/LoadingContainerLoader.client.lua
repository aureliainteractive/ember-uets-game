local plyr = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

-- UTILS ----------------------------------------------------

local function tweenWait(obj, prop, startValue, endValue, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	obj[prop] = startValue
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, easingStyle, easingDir),
		{[prop] = endValue}
	)
	tween:Play()
	tween.Completed:Wait()
end

local function tweenAsync(obj, prop, startValue, endValue, duration, easingStyle, easingDir)
	easingStyle = easingStyle or Enum.EasingStyle.Sine
	easingDir = easingDir or Enum.EasingDirection.InOut
	obj[prop] = startValue
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, easingStyle, easingDir),
		{[prop] = endValue}
	)
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
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, easingStyle, easingDir),
		tweenGoals
	)
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
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, easingStyle, easingDir),
		tweenGoals
	)
	tween:Play()
	return tween
end

--------------------------------------------------------------
-- ESPERAR JUEGO
--------------------------------------------------------------
if not game:IsLoaded() then game.Loaded:Wait() end
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
	elseif instance:IsA("Decal") or instance:IsA("Texture") or instance:IsA("ImageLabel") or instance:IsA("ImageButton") or instance:IsA("SurfaceAppearance") then
		return "texturas e interfaz"
	end

	return "recursos del juego"
end

local function buildPreloadTargets()
	local targets = {}
	for _, descendant in ipairs(game:GetDescendants()) do
		if descendant:IsA("Decal") or descendant:IsA("Texture") or descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") or descendant:IsA("Sound") or descendant:IsA("Animation") or descendant:IsA("MeshPart") or descendant:IsA("SpecialMesh") or descendant:IsA("SurfaceAppearance") or descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") then
			targets[#targets + 1] = descendant
		end
	end
	return targets
end

local function startRealLoadingStatus()
	local targets = buildPreloadTargets()
	local total = math.max(#targets, 1)
	local loaded = 0
	local finished = false

	if #targets == 0 then
		setLoadingStatus("No hay assets que precargar")
		return
	end

	setLoadingStatus(string.format("Analizando %d assets del juego", total))

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(targets, function(asset, status)
				loaded += 1
				local category = typeof(asset) == "Instance" and getAssetCategory(asset) or "recursos del juego"
				local percent = math.clamp(math.floor((loaded / total) * 100 + 0.5), 0, 100)
				if status == Enum.AssetFetchStatus.Failure then
					loadingStatus.Text = string.format("Cargando: %s (%d%%, reintentando)", category, percent)
				else
					loadingStatus.Text = string.format("Cargando: %s (%d%%)", category, percent)
				end
			end)
		end)

		finished = true
	end)

	while not finished do
		local percent = math.clamp(math.floor((loaded / total) * 100 + 0.5), 0, 100)
		loadingStatus.Text = string.format("Cargando: recursos del juego (%d%%)", percent)
		task.wait(0.1)
	end

	loadingStatus.Text = "Cargando: contenido del juego listo"
	end

--------------------------------------------------------------
-- ESTADO INICIAL
--------------------------------------------------------------
gui.Enabled = true;
logos.GroupTransparency = 1
logo.ImageTransparency = 1
subtitle.TextTransparency = 1
setLoadingStatus("Preparando assets del juego")

--------------------------------------------------------------
-- SECUENCIA SINCRONIZADA
--------------------------------------------------------------

-- [0.000 - 2.200] Textos entran con Back.Out para efecto cinematográfico
task.spawn(startRealLoadingStatus)
local tIn1 = tweenAsync(logo, "ImageTransparency", 1, 0, 2.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local tIn2 = tweenAsync(subtitle, "TextTransparency", 1, 0, 2.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
tIn2.Completed:Wait()

-- [2.200 - 3.200] Pausa
task.wait(1)

-- [3.200 - 4.700] Textos salen con Sine.In para suavidad
local tOut1 = tweenAsync(logo, "ImageTransparency", 0, 1, 1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
local tOut2 = tweenAsync(subtitle, "TextTransparency", 0, 1, 1.5, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
tOut2.Completed:Wait()

-- [4.700 - 8.200] Logos fade-in con Sine.Out (3.5 s)
tweenWait(logos, "GroupTransparency", 1, 0, 3.5, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

-- [8.200 - 11.200] Logos fade-out con Sine.In (3 s)
tweenWait(logos, "GroupTransparency", 0, 1, 3, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

-- [11.200 - 12.095] Fade a negro con Sine.In
setLoadingStatus("Finalizando carga real")
tweenWait(blk, "BackgroundTransparency", blk.BackgroundTransparency, 1, 0.895, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

gui.Enabled = false
