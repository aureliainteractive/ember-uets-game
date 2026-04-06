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

--------------------------------------------------------------
-- ESTADO INICIAL
--------------------------------------------------------------
gui.Enabled = true;
logos.GroupTransparency = 1
aureliaLogo.ImageTransparency = 1
subtitle.TextTransparency = 1
local aureliaLogoBasePos = aureliaLogo.Position
local subtitleBasePos = subtitle.Position
aureliaLogo.Position = aureliaLogoBasePos + UDim2.new(0, 0, 0.03, 0)
subtitle.Position = subtitleBasePos + UDim2.new(0, 0, 0.03, 0)

--------------------------------------------------------------
-- SECUENCIA SINCRONIZADA
--------------------------------------------------------------

-- [0.000 - 2.200] Textos entran
local tIn1 = tweenAsync(aureliaLogo, 1.4, {
	ImageTransparency = 0,
	Position = aureliaLogoBasePos,
})
local tIn2 = tweenAsync(subtitle, 1.4, {
	TextTransparency = 0,
	Position = subtitleBasePos,
})
tIn2.Completed:Wait()

-- [2.200 - 3.200] Pausa
task.wait(0.7)

-- [3.200 - 4.700] Textos salen
local tOut1 = tweenAsync(aureliaLogo, 1.0, {
	ImageTransparency = 1,
	Position = aureliaLogoBasePos - UDim2.new(0, 0, 0.02, 0),
})
local tOut2 = tweenAsync(subtitle, 1.0, {
	TextTransparency = 1,
	Position = subtitleBasePos - UDim2.new(0, 0, 0.02, 0),
})
tOut2.Completed:Wait()

-- [4.700 - 8.200] Logos fade-in (3.5 s)
tweenWait(logos, 2.4, {GroupTransparency = 0})

-- [8.200 - 11.200] Logos fade-out (3 s)
tweenWait(logos, 2.0, {GroupTransparency = 1})

-- [11.200 - 12.095] Fade a negro
tweenWait(blk, 0.8, {BackgroundTransparency = 1})

gui.Enabled = false
