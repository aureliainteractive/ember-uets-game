local plyr = game.Players.LocalPlayer
local TweenService = game:GetService("TweenService")

-- UTILS ----------------------------------------------------

local function tweenWait(obj, prop, startValue, endValue, duration)
	obj[prop] = startValue
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{[prop] = endValue}
	)
	tween:Play()
	tween.Completed:Wait()
end

local function tweenAsync(obj, prop, startValue, endValue, duration)
	obj[prop] = startValue
	local tween = TweenService:Create(
		obj,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{[prop] = endValue}
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

--------------------------------------------------------------
-- ESTADO INICIAL
--------------------------------------------------------------
gui.Enabled = true;
logos.GroupTransparency = 1
logo.ImageTransparency = 1
subtitle.TextTransparency = 1

--------------------------------------------------------------
-- SECUENCIA SINCRONIZADA
--------------------------------------------------------------

-- [0.000 - 2.200] Textos entran
local tIn1 = tweenAsync(logo, "ImageTransparency", 1, 0, 2.2)
local tIn2 = tweenAsync(subtitle, "TextTransparency", 1, 0, 2.2)
tIn2.Completed:Wait()

-- [2.200 - 3.200] Pausa
task.wait(1)

-- [3.200 - 4.700] Textos salen
local tOut1 = tweenAsync(logo, "ImageTransparency", 0, 1, 1.5)
local tOut2 = tweenAsync(subtitle, "TextTransparency", 0, 1, 1.5)
tOut2.Completed:Wait()

-- [4.700 - 8.200] Logos fade-in (3.5 s)
tweenWait(logos, "GroupTransparency", 1, 0, 3.5)

-- [8.200 - 11.200] Logos fade-out (3 s)
tweenWait(logos, "GroupTransparency", 0, 1, 3)

-- [11.200 - 12.095] Fade a negro
tweenWait(blk, "BackgroundTransparency", blk.BackgroundTransparency, 1, 0.895)

gui.Enabled = false
