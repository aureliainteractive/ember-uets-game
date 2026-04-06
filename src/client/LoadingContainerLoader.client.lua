local plyr = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")

-- UTILS ----------------------------------------------------

local function tweenWait(obj, duration, goal)
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		goal
	)
	tween:Play()
	tween.Completed:Wait()
end

local function tweenAsync(obj, duration, goal)
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		goal
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
local logos = gui:WaitForChild("Logos")
local blk = gui:WaitForChild("BLK")
local aureliaLogo = blk:WaitForChild("aureliaLogo")
local subtitle = blk:WaitForChild("subtitle")

-- Elementos dentro de Logos para animaciones separadas
local mainLogos = logos:WaitForChild("MainLogos")
local brandLogos = logos:WaitForChild("BrandLogos")
local credits = logos:WaitForChild("Credits")

--------------------------------------------------------------
-- ESTADO INICIAL
--------------------------------------------------------------
gui.Enabled = true;

-- Elementos de Logos inicialmente invisibles
mainLogos.Transparency = 1
brandLogos.Transparency = 1
credits.TextTransparency = 1

-- Logo Aurelia y subtitle inicialmente invisibles
aureliaLogo.ImageTransparency = 1
subtitle.TextTransparency = 1
local aureliaLogoBasePos = aureliaLogo.Position
local subtitleBasePos = subtitle.Position
aureliaLogo.Position = aureliaLogoBasePos + UDim2.new(0, 0, 0.03, 0)
subtitle.Position = subtitleBasePos + UDim2.new(0, 0, 0.03, 0)

--------------------------------------------------------------
-- SECUENCIA DE ANIMACIÓN MEJORADA
--------------------------------------------------------------

-- [0.000 - 1.400] Logo Aurelia fade-in
local tAureliaIn = tweenAsync(aureliaLogo, 1.4, {
	ImageTransparency = 0,
	Position = aureliaLogoBasePos,
})
tAureliaIn.Completed:Wait()

-- [1.400 - 2.800] Subtitle entra después del logo (con delay)
local tSubtitleIn = tweenAsync(subtitle, 1.0, {
	TextTransparency = 0,
	Position = subtitleBasePos,
})
tSubtitleIn.Completed:Wait()

-- [2.800 - 3.500] Pausa
task.wait(0.7)

-- [3.500 - 4.500] Textos salen
local tAureliaOut = tweenAsync(aureliaLogo, 1.0, {
	ImageTransparency = 1,
	Position = aureliaLogoBasePos - UDim2.new(0, 0, 0.02, 0),
})
local tSubtitleOut = tweenAsync(subtitle, 1.0, {
	TextTransparency = 1,
	Position = subtitleBasePos - UDim2.new(0, 0, 0.02, 0),
})
tSubtitleOut.Completed:Wait()

-- [4.500 - 11.000] Logos entran por separado
-- MainLogos entra primero
local tMainIn = tweenAsync(mainLogos, 2.0, {Transparency = 0})
tMainIn.Completed:Wait()

-- BrandLogos entra con un pequeño delay
task.wait(0.3)
local tBrandIn = tweenAsync(brandLogos, 1.5, {Transparency = 0})

-- Credits entra en paralelo con BrandLogos
local tCreditsIn = tweenAsync(credits, 1.5, {TextTransparency = 0})
tCreditsIn.Completed:Wait()

-- [11.000 - 12.095] Logos salen por separado (en orden inverso)
task.wait(0.5)

-- MainLogos sale primero
local tMainOut = tweenAsync(mainLogos, 1.2, {Transparency = 1})

-- BrandLogos y Credits salen juntos
local tBrandOut = tweenAsync(brandLogos, 1.0, {Transparency = 1})
local tCreditsOut = tweenAsync(credits, 1.0, {TextTransparency = 1})
tCreditsOut.Completed:Wait()

-- Esperar a que MainLogos termine
tMainOut.Completed:Wait()

-- [12.095 - 12.895] Fade a negro
tweenWait(blk, 0.8, {BackgroundTransparency = 1})

gui.Enabled = false
