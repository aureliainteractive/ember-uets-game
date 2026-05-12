local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UIManager = require(ReplicatedStorage.Shared.UIManager)
local GameConstants = require(ReplicatedStorage.Shared.GameConstants)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUDContainer = UIManager.get(playerGui, "HUD_VR")

local ControllerUI_HUD = ReplicatedStorage:WaitForChild("ControllerUI_HUD")
local HUDUpdate = ReplicatedStorage:WaitForChild("HUDUpdate")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

-- Referencias UI
local UI = {
	simulationActive = HUDContainer:WaitForChild("SimProgreso"),
	timeLeft = HUDContainer:WaitForChild("TiempoRestante"),
	score = HUDContainer:WaitForChild("Puntuacion"),
	progressContainer = HUDContainer:WaitForChild("ProgresoActual"),
}

-- Labels
local Labels = {
	timeLeft = UI.timeLeft:WaitForChild("LabelTiempo"),
	score = UI.score:WaitForChild("LabelScore"),
}

-- Objetivos
local progressFrame = UI.progressContainer:WaitForChild("Frame")
local Objectives = {
	progressFrame:WaitForChild("Obj1"),
	progressFrame:WaitForChild("Obj2"),
	progressFrame:WaitForChild("Obj3"),
	progressFrame:WaitForChild("Obj4"),
}

local ObjectiveLabels = {}
for i, obj in ipairs(Objectives) do
	ObjectiveLabels[i] = obj:FindFirstChildWhichIsA("TextLabel", true)
end

local IMG_INCOMPLETE = "rbxassetid://139565534034394"
local IMG_IN_PROGRESS = "rbxassetid://75916766300891"
local IMG_COMPLETE = "rbxassetid://94228531190693"

local isHUDVisible = false

local function updateContainerEnabled()
	HUDContainer.Enabled = isHUDVisible or HUDContainer:GetAttribute("DialogBusy") == true
end

local function resetHUDContent()
	Labels.timeLeft.Text = "05:00"
	Labels.score.Text = "100"

	for _, obj in ipairs(Objectives) do
		obj.Icon.Image = IMG_INCOMPLETE
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

-- Animaciones (from GameConstants)
local TWEEN_IN = TweenInfo.new(
	GameConstants.ANIMATION.HUD_ANIMATION_DURATION,
	GameConstants.ANIMATION.HUD_EASING_STYLE,
	GameConstants.ANIMATION.HUD_EASING_DIRECTION_IN
)
local TWEEN_OUT = TweenInfo.new(
	GameConstants.ANIMATION.HUD_ANIMATION_DURATION - 0.08,
	GameConstants.ANIMATION.HUD_EASING_STYLE,
	GameConstants.ANIMATION.HUD_EASING_DIRECTION_OUT
)
local STAGGER_STEP = GameConstants.ANIMATION.HUD_STAGGER_STEP

local ANIMATION_ORDER = {
	UI.simulationActive,
	UI.timeLeft,
	UI.score,
	UI.progressContainer,
}

local DEFAULT_IMAGE_TRANSPARENCY = {}
for _, ui in ipairs(ANIMATION_ORDER) do
	DEFAULT_IMAGE_TRANSPARENCY[ui] = ui.ImageTransparency
end

local hudTransitionToken = 0

local SHOW_POSITIONS = {
	[UI.simulationActive] = UDim2.new(0.15, 0, 0.05, 0),
	[UI.timeLeft] = UDim2.new(0.5, 0, 0.06, 0),
	[UI.score] = UDim2.new(0.9, 0, 0.06, 0),
	[UI.progressContainer] = UDim2.new(0.85, 0, 0.5, 0),
}

local HIDE_POSITIONS = {
	[UI.simulationActive] = UDim2.new(0.15, 0, -0.2, 0),
	[UI.timeLeft] = UDim2.new(0.5, 0, -0.2, 0),
	[UI.score] = UDim2.new(0.9, 0, -0.2, 0),
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
	hudTransitionToken += 1
	local token = hudTransitionToken
	isHUDVisible = true
	HUDContainer:SetAttribute("HUDVisible", true)
	HUDContainer.Enabled = true

	for index, ui in ipairs(ANIMATION_ORDER) do
		ui.Position = HIDE_POSITIONS[ui]
		ui.ImageTransparency = 1
		local pos = SHOW_POSITIONS[ui]
		task.delay((index - 1) * STAGGER_STEP, function()
			if token ~= hudTransitionToken or not isHUDVisible then
				return
			end
			tweenUI(ui, TWEEN_IN, {
				Position = pos,
				ImageTransparency = DEFAULT_IMAGE_TRANSPARENCY[ui],
			})
		end)
	end
end

-- Ocultar HUD
local function hideHUD(immediate)
	hudTransitionToken += 1
	local token = hudTransitionToken
	isHUDVisible = false
	HUDContainer:SetAttribute("HUDVisible", false)
	resetHUDContent()

	if immediate then
		for _, ui in ipairs(ANIMATION_ORDER) do
			ui.Position = HIDE_POSITIONS[ui]
			ui.ImageTransparency = 1
		end
		updateContainerEnabled()
		return
	end

	for index = #ANIMATION_ORDER, 1, -1 do
		local ui = ANIMATION_ORDER[index]
		local pos = HIDE_POSITIONS[ui]
		task.delay((#ANIMATION_ORDER - index) * STAGGER_STEP * 0.8, function()
			if token ~= hudTransitionToken then
				return
			end
			tweenUI(ui, TWEEN_OUT, {
				Position = pos,
				ImageTransparency = 1,
			})
		end)
	end

	task.delay(TWEEN_OUT.Time + STAGGER_STEP * (#ANIMATION_ORDER - 1), function()
		if token == hudTransitionToken and not isHUDVisible then
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
		Logger.warn("UI", string.format("Unknown HUD action received: %s", tostring(action)))
	end
end)

HUDUpdate.OnClientEvent:Connect(function(changes)
	if not isHUDVisible then
		return
	end

	-- Changes is a delta table: {timeLeft = X, score = Y, completedSteps = Z, stepNames = {...}}
	-- Only fields that changed are present, so we only update those
	
	if changes.timeLeft ~= nil then
		local mins = math.floor(changes.timeLeft / 60)
		local secs = changes.timeLeft % 60
		Labels.timeLeft.Text = string.format("%02d:%02d", mins, secs)
	end

	if changes.score ~= nil then
		Labels.score.Text = tostring(changes.score)
	end

	if changes.completedSteps ~= nil or changes.stepNames ~= nil then
		local completedSteps = changes.completedSteps or 0
		local stepNames = changes.stepNames or {}
		
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
	end
end)

HUDContainer:SetAttribute("HUDVisible", false)
if HUDContainer:GetAttribute("DialogBusy") == nil then
	HUDContainer:SetAttribute("DialogBusy", false)
end
hideHUD(true)
