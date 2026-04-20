local plyr = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")
local WARN_PREFIX = "[LoadingContainerLoader]"
local CHILD_TIMEOUT = 10
local FAILSAFE_TIMEOUT = 20

-- UTILS ----------------------------------------------------

local function warnLoading(fmt, ...)
	warn(string.format("%s " .. fmt, WARN_PREFIX, ...))
end

local function safeSet(obj, propName, value)
	local ok, err = pcall(function()
		obj[propName] = value
	end)

	if not ok then
		warnLoading("No se pudo asignar %s.%s = %s (%s)", obj:GetFullName(), propName, tostring(value), tostring(err))
		return false
	end

	return true
end

local function waitForChildOrWarn(parent, childName, expectedClass)
	local child = parent:FindFirstChild(childName)
	if not child then
		child = parent:WaitForChild(childName, CHILD_TIMEOUT)
	end

	if not child then
		warnLoading("No se encontro %s dentro de %s luego de %ds", childName, parent:GetFullName(), CHILD_TIMEOUT)
		return nil
	end

	if expectedClass and not child:IsA(expectedClass) then
		warnLoading("%s existe pero no es %s, clase actual: %s", child:GetFullName(), expectedClass, child.ClassName)
	end

	return child
end

local function createTweenSafe(obj, duration, goal)
	local ok, tweenOrErr = pcall(function()
		return TweenService:Create(
			obj,
			TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			goal
		)
	end)

	if not ok then
		warnLoading("No se pudo crear tween para %s (%s)", obj:GetFullName(), tostring(tweenOrErr))
		for prop, value in pairs(goal) do
			safeSet(obj, prop, value)
		end
		return nil
	end

	local tween = tweenOrErr
	local played, playErr = pcall(function()
		tween:Play()
	end)

	if not played then
		warnLoading("No se pudo ejecutar tween en %s (%s)", obj:GetFullName(), tostring(playErr))
		for prop, value in pairs(goal) do
			safeSet(obj, prop, value)
		end
		return nil
	end

	return tween
end

local function waitTweenSafe(tween, label)
	if not tween then
		return
	end

	local ok, err = pcall(function()
		tween.Completed:Wait()
	end)

	if not ok then
		warnLoading("Error esperando tween (%s): %s", label or "sin-label", tostring(err))
	end
end

local function collectAnimObjects(container)
	local targets = {}

	if container:IsA("Frame") or container:IsA("ImageLabel") or container:IsA("TextLabel") then
		table.insert(targets, container)
	end

	for _, desc in ipairs(container:GetDescendants()) do
		if desc:IsA("Frame") or desc:IsA("ImageLabel") or desc:IsA("TextLabel") then
			table.insert(targets, desc)
		end
	end

	return targets
end

local function goalForAlpha(obj, alpha)
	local goal = {}

	if obj:IsA("Frame") then
		goal.Transparency = alpha
		goal.BackgroundTransparency = 1
	elseif obj:IsA("ImageLabel") then
		goal.Transparency = alpha
		goal.ImageTransparency = alpha
		goal.BackgroundTransparency = 1
	elseif obj:IsA("TextLabel") then
		goal.Transparency = alpha
		goal.TextTransparency = alpha
		goal.BackgroundTransparency = 1
	end

	return goal
end

local function setAlphaImmediate(obj, alpha)
	local goal = goalForAlpha(obj, alpha)
	for prop, value in pairs(goal) do
		safeSet(obj, prop, value)
	end
end

local function tweenAlpha(obj, duration, alpha, extraGoal)
	local goal = goalForAlpha(obj, alpha)
	if extraGoal then
		for prop, value in pairs(extraGoal) do
			goal[prop] = value
		end
	end
	return createTweenSafe(obj, duration, goal)
end

local function setGroupAlpha(targets, alpha)
	for _, obj in ipairs(targets) do
		setAlphaImmediate(obj, alpha)
	end
end

local function tweenGroupAlpha(targets, duration, alpha)
	local tweens = {}
	for _, obj in ipairs(targets) do
		local tween = tweenAlpha(obj, duration, alpha)
		if tween then
			table.insert(tweens, tween)
		end
	end
	return tweens
end

local function waitTweens(tweens, label)
	for _, tween in ipairs(tweens) do
		waitTweenSafe(tween, label)
	end
end

--------------------------------------------------------------
-- ESPERAR JUEGO
--------------------------------------------------------------
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(0.5)

--------------------------------------------------------------
-- REFERENCIAS
--------------------------------------------------------------
local playerGui = waitForChildOrWarn(plyr, "PlayerGui")
if not playerGui then
	return
end

local gui = waitForChildOrWarn(playerGui, "LoadingContainer", "ScreenGui")
if not gui then
	return
end

local logos = waitForChildOrWarn(gui, "Logos", "CanvasGroup")
local blk = waitForChildOrWarn(gui, "BLK", "Frame")

if not logos or not blk then
	safeSet(gui, "Enabled", false)
	return
end

local aureliaLogo = waitForChildOrWarn(blk, "aureliaLogo", "ImageLabel")
local subtitle = waitForChildOrWarn(blk, "subtitle", "TextLabel")

if not aureliaLogo or not subtitle then
	safeSet(gui, "Enabled", false)
	return
end

-- Elementos dentro de Logos para animaciones separadas
local mainLogos = waitForChildOrWarn(logos, "MainLogos", "Frame")
local brandLogos = waitForChildOrWarn(logos, "BrandLogos", "Frame")
local credits = waitForChildOrWarn(logos, "Credits", "TextLabel")

if not mainLogos or not brandLogos or not credits then
	warnLoading("No se pudo preparar Logos/MainLogos/BrandLogos/Credits")
	safeSet(gui, "Enabled", false)
	return
end

local mainLogoTargets = collectAnimObjects(mainLogos)
local brandLogoTargets = collectAnimObjects(brandLogos)

if #mainLogoTargets == 0 then
	warnLoading("MainLogos no tiene objetos animables (Frame/ImageLabel/TextLabel)")
end

if #brandLogoTargets == 0 then
	warnLoading("BrandLogos no tiene objetos animables (Frame/ImageLabel/TextLabel)")
end

--------------------------------------------------------------
-- ESTADO INICIAL
--------------------------------------------------------------
safeSet(gui, "Enabled", true)

local sequenceFinished = false
task.delay(FAILSAFE_TIMEOUT, function()
	if sequenceFinished then
		return
	end

	warnLoading("Timeout de %ds: forzando cierre de pantalla de carga para evitar negro infinito", FAILSAFE_TIMEOUT)
	safeSet(blk, "BackgroundTransparency", 1)
	safeSet(blk, "Visible", false)
	safeSet(logos, "Visible", false)
	safeSet(gui, "Enabled", false)
end)

safeSet(blk, "Visible", true)
safeSet(logos, "Visible", true)
safeSet(blk, "BackgroundTransparency", 0)
safeSet(logos, "Transparency", 0)
safeSet(logos, "BackgroundTransparency", 1)

-- Elementos de Logos inicialmente invisibles
setGroupAlpha(mainLogoTargets, 1)
setGroupAlpha(brandLogoTargets, 1)
setAlphaImmediate(credits, 1)

-- Logo Aurelia y subtitle inicialmente invisibles
setAlphaImmediate(aureliaLogo, 1)
setAlphaImmediate(subtitle, 1)
local aureliaLogoBasePos = aureliaLogo.Position
local subtitleBasePos = subtitle.Position
aureliaLogo.Position = aureliaLogoBasePos + UDim2.new(0, 0, 0.03, 0)
subtitle.Position = subtitleBasePos + UDim2.new(0, 0, 0.03, 0)

--------------------------------------------------------------
-- SECUENCIA DE ANIMACIÓN MEJORADA
--------------------------------------------------------------
local ok, err = xpcall(function()
	-- [0.000 - 1.400] Logo Aurelia fade-in
	local tAureliaIn = tweenAlpha(aureliaLogo, 1.4, 0, {
		Position = aureliaLogoBasePos,
	})
	waitTweenSafe(tAureliaIn, "AureliaIn")

	-- [1.400 - 2.800] Subtitle entra después del logo (con delay)
	local tSubtitleIn = tweenAlpha(subtitle, 1.0, 0, {
		Position = subtitleBasePos,
	})
	waitTweenSafe(tSubtitleIn, "SubtitleIn")

	-- [2.800 - 3.500] Pausa
	task.wait(0.7)

	-- [3.500 - 4.500] Textos salen
	local tAureliaOut = tweenAlpha(aureliaLogo, 1.0, 1, {
		Position = aureliaLogoBasePos - UDim2.new(0, 0, 0.02, 0),
	})
	local tSubtitleOut = tweenAlpha(subtitle, 1.0, 1, {
		Position = subtitleBasePos - UDim2.new(0, 0, 0.02, 0),
	})
	waitTweenSafe(tSubtitleOut, "SubtitleOut")
	waitTweenSafe(tAureliaOut, "AureliaOut")

	-- [4.500 - 11.000] Logos entran por separado
	-- MainLogos entra primero
	local tMainIn = tweenGroupAlpha(mainLogoTargets, 2.0, 0)
	waitTweens(tMainIn, "MainIn")

	-- BrandLogos entra con un pequeño delay
	task.wait(0.3)
	local tBrandIn = tweenGroupAlpha(brandLogoTargets, 1.5, 0)

	-- Credits entra en paralelo con BrandLogos
	local tCreditsIn = tweenAlpha(credits, 1.5, 0)
	waitTweenSafe(tCreditsIn, "CreditsIn")
	waitTweens(tBrandIn, "BrandIn")

	-- [11.000 - 12.095] Logos salen por separado (en orden inverso)
	task.wait(0.5)

	-- MainLogos sale primero
	local tMainOut = tweenGroupAlpha(mainLogoTargets, 1.2, 1)

	-- BrandLogos y Credits salen juntos
	local tBrandOut = tweenGroupAlpha(brandLogoTargets, 1.0, 1)
	local tCreditsOut = tweenAlpha(credits, 1.0, 1)
	waitTweenSafe(tCreditsOut, "CreditsOut")
	waitTweens(tBrandOut, "BrandOut")

	-- Esperar a que MainLogos termine
	waitTweens(tMainOut, "MainOut")

	-- [12.095 - 12.895] Fade a negro
	local tBlkOut = createTweenSafe(blk, 0.8, { BackgroundTransparency = 1 })
	waitTweenSafe(tBlkOut, "BlkOut")
end, debug.traceback)

if not ok then
	warnLoading("Error en secuencia de carga: %s", tostring(err))
end

sequenceFinished = true
safeSet(blk, "BackgroundTransparency", 1)
safeSet(blk, "Visible", false)
safeSet(logos, "Visible", false)
safeSet(gui, "Enabled", false)
