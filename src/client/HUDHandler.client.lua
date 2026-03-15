local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUDContainer = playerGui:WaitForChild("HUD_VR")
local overlay = HUDContainer:WaitForChild("Overlay")

local ControllerUI_HUD = ReplicatedStorage:WaitForChild("ControllerUI_HUD")
local RunService = game:GetService("RunService")
local HUDUpdate  = ReplicatedStorage:WaitForChild("HUDUpdate")

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

local ObjectiveLabels = {}
for i, obj in ipairs(Objectives) do
	ObjectiveLabels[i] = obj:FindFirstChildWhichIsA("TextLabel", true)
end

local IMG_INCOMPLETE  = "rbxassetid://139565534034394"
local IMG_IN_PROGRESS = "rbxassetid://75916766300891"
local IMG_COMPLETE    = "rbxassetid://94228531190693"

local isHUDVisible = false

local function updateContainerEnabled()
	HUDContainer.Enabled = isHUDVisible or HUDContainer:GetAttribute("DialogBusy") == true
end

local function resetHUDContent()
	Labels.timeLeft.Text = "05:00"
	Labels.score.Text    = "100"

	for _, obj in ipairs(Objectives) do
		obj.Image   = IMG_INCOMPLETE
		obj.Visible = true
		if obj:FindFirstChild("Icon") then
			obj.Icon.Image = IMG_INCOMPLETE
		end
	end

	for _, label in ipairs(ObjectiveLabels) do
		if label then
			label.Text = ""
		end
	end
end

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
	isHUDVisible = true
	HUDContainer:SetAttribute("HUDVisible", true)
	HUDContainer.Enabled = true

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
local function hideHUD(immediate)
	isHUDVisible = false
	HUDContainer:SetAttribute("HUDVisible", false)
	resetHUDContent()

	if immediate then
		for ui, pos in pairs(HIDE_POSITIONS) do
			ui.Position = pos
		end
		overlay.ImageTransparency = CONFIG.OverlayHiddenTransparency
		updateContainerEnabled()
		return
	end

	for ui, pos in pairs(HIDE_POSITIONS) do
		tweenUI(ui, TWEEN_OUT, {Position = pos})
	end

	-- Overlay desaparece
	tweenUI(
		overlay,
		TWEEN_OUT,
		{ImageTransparency = CONFIG.OverlayHiddenTransparency}
	)

	task.delay(CONFIG.AnimationDuration, function()
		if not isHUDVisible then
			updateContainerEnabled()
		end
	end)
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

HUDUpdate.OnClientEvent:Connect(function(
	timeLeft, score, completedSteps, stepNames
)
	if not isHUDVisible then return end

	local mins = math.floor(timeLeft / 60)
	local secs = timeLeft % 60
	Labels.timeLeft.Text = string.format("%02d:%02d", mins, secs)

	Labels.score.Text = tostring(score)

	for i, obj in ipairs(Objectives) do
		local name = stepNames and stepNames[i]
		local label = ObjectiveLabels[i]
		if name then
			obj.Visible = true
			if label then
				label.Text = tostring(name)
			end
			if i <= completedSteps then
				obj.Icon.Image = IMG_COMPLETE
			elseif i == completedSteps + 1 then
				obj.Icon.Image = IMG_IN_PROGRESS
			else
				obj.Icon.Image = IMG_INCOMPLETE
			end
		else
			obj.Visible = false
			if label then
				label.Text = ""
			end
		end
	end
end)

HUDContainer:SetAttribute("HUDVisible", false)
if HUDContainer:GetAttribute("DialogBusy") == nil then
	HUDContainer:SetAttribute("DialogBusy", false)
end
hideHUD(true)