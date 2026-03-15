local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUDContainer = playerGui:WaitForChild("HUD_VR")
local overlay = HUDContainer:WaitForChild("Overlay")

local ControllerUI_HUD = ReplicatedStorage:WaitForChild("ControllerUI_HUD")

local CONFIG = {
	AnimationDuration = 0.4,
	OverlayVisibleTransparency = 0.44,
	OverlayHiddenTransparency = 1
}

-- Referencias UI
local UI = {
	simulationActive  = HUDContainer:WaitForChild("SimProgreso"),
	timeLeft          = HUDContainer:WaitForChild("TiempoRestante"),
	score             = HUDContainer:WaitForChild("Puntuacion"),
	progressContainer = HUDContainer:WaitForChild("ProgresoActual")
}

-- Labels
local Labels = {
	timeLeft = UI.timeLeft:WaitForChild("LabelTiempo"),
	score    = UI.score:WaitForChild("LabelScore"),
}

-- Objetivos
local progressFrame = UI.progressContainer:WaitForChild("Frame")
local Objectives = {
	progressFrame:WaitForChild("Obj1"),
	progressFrame:WaitForChild("Obj2"),
	progressFrame:WaitForChild("Obj3"),
	progressFrame:WaitForChild("Obj4")
}

-- Animaciones
local TWEEN_IN = TweenInfo.new(CONFIG.AnimationDuration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(CONFIG.AnimationDuration, Enum.EasingStyle.Back, Enum.EasingDirection.In)

local SHOW_POSITIONS = {
	[UI.simulationActive]  = UDim2.new(0.15, 0, 0.05, 0),
	[UI.timeLeft]          = UDim2.new(0.5, 0, 0.06, 0),
	[UI.score]             = UDim2.new(0.9, 0, 0.06, 0),
	[UI.progressContainer] = UDim2.new(0.85, 0, 0.5, 0),
}

local HIDE_POSITIONS = {
	[UI.simulationActive]  = UDim2.new(0.15, 0, -0.2, 0),
	[UI.timeLeft]          = UDim2.new(0.5, 0, -0.2, 0),
	[UI.score]             = UDim2.new(0.9, 0, -0.2, 0),
	[UI.progressContainer] = UDim2.new(1.3, 0, 0.5, 0),
}

-- Función genérica tween
local function tweenUI(target, tweenInfo, goal)
	local tween = TweenService:Create(target, tweenInfo, goal)
	tween:Play()
	return tween
end

-- Mostrar HUD
local function showHUD()

	for ui, pos in pairs(SHOW_POSITIONS) do
		ui.Position = HIDE_POSITIONS[ui]
		tweenUI(ui, TWEEN_IN, {Position = pos})
	end

	-- Overlay aparece
	tweenUI(
		overlay,
		TWEEN_IN,
		{ImageTransparency = CONFIG.OverlayVisibleTransparency}
	)
end

-- Ocultar HUD
local function hideHUD()

	for ui, pos in pairs(HIDE_POSITIONS) do
		tweenUI(ui, TWEEN_OUT, {Position = pos})
	end

	-- Overlay desaparece
	tweenUI(
		overlay,
		TWEEN_OUT,
		{ImageTransparency = CONFIG.OverlayHiddenTransparency}
	)
end

-- Evento remoto
ControllerUI_HUD.OnClientEvent:Connect(function(action)

	if action == "Show" then
		showHUD()

	elseif action == "Hide" then
		hideHUD()

	else
		warn("[HUDHandler] Acción desconocida:", action)
	end

end)

hideHUD()