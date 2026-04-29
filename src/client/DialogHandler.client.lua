-- DialogHandler (versión mejorada simulador)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local HUD = playerGui:WaitForChild("HUD_VR")

local dialogContainer = HUD:WaitForChild("SistemaEmberInfo")
local textLabel = dialogContainer:WaitForChild("LabelTexto")
local iconLabel = dialogContainer:WaitForChild("Icon")
local radioBeep = dialogContainer:WaitForChild("RadioBeep")

local showDialogEvent = ReplicatedStorage:WaitForChild("ShowDialog")

-- =============================================================================
-- CONFIG
-- =============================================================================

local CONFIG = {

	MaxQueueSize = 6,
	MinDisplayTime = 2,
	MaxDisplayTime = 7,

	CharsPerSecond = 22,
	TypeSpeed = 0.02,

	PauseBetweenDialogs = 0.5,
	AnimationDuration = 0.35,
	DuplicateWindow = 2,
}

-- =============================================================================
-- ICONOS
-- CONFIGURA AQUÍ
-- =============================================================================

local ICON_MAP = {

	Info = "rbxassetid://88497389453400",
	Warning = "rbxassetid://86393744209066",
	Success = "rbxassetid://123913911760584",
	Error = "rbxassetid://77702474213008",
	Result = "rbxassetid://94199853920673",
}

-- =============================================================================
-- PRIORIDADES
-- =============================================================================

local PRIORITY = {

	Info = 1,
	Success = 1,
	Result = 1,

	Warning = 2,

	Error = 3,
}

-- =============================================================================
-- POSICIONES
-- =============================================================================

local TWEEN_IN = TweenInfo.new(CONFIG.AnimationDuration + 0.05, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(CONFIG.AnimationDuration - 0.05, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

local POS_VISIBLE = UDim2.new(0.5, 0, 0.9, 0)
local POS_HIDDEN = UDim2.new(0.5, 0, 1.3, 0)

local DEFAULT_DIALOG_IMAGE_TRANSPARENCY = dialogContainer.ImageTransparency
local DEFAULT_TEXT_TRANSPARENCY = textLabel.TextTransparency
local DEFAULT_ICON_TRANSPARENCY = iconLabel.ImageTransparency

-- =============================================================================
-- SISTEMA
-- =============================================================================

local DialogSystem = {

	queue = {},
	isActive = false,
	currentTween = nil,

	lastDialog = {
		text = "",
		time = 0,
	},
}

local function updateContainerEnabled()
	HUD.Enabled = HUD:GetAttribute("HUDVisible") == true or HUD:GetAttribute("DialogBusy") == true
end

function DialogSystem:CancelTween()
	if self.currentTween then
		self.currentTween:Cancel()
		self.currentTween = nil
	end
end

function DialogSystem:IsDuplicate(text)
	return self.lastDialog.text == text and (tick() - self.lastDialog.time) < CONFIG.DuplicateWindow
end

function DialogSystem:CalculateDisplayTime(text)
	return math.clamp(#text / CONFIG.CharsPerSecond, CONFIG.MinDisplayTime, CONFIG.MaxDisplayTime)
end

-- =============================================================================
-- TYPEWRITER
-- =============================================================================

function DialogSystem:TypeText(text)
	textLabel.Text = ""

	for i = 1, #text do
		textLabel.Text = string.sub(text, 1, i)

		task.wait(CONFIG.TypeSpeed)
	end
end

-- =============================================================================
-- COLA CON PRIORIDAD
-- =============================================================================

function DialogSystem:Add(icon, text)
	if not text or text == "" then
		return false
	end
	if self:IsDuplicate(text) then
		return false
	end

	local data = {

		icon = icon or "Info",
		text = text,
		priority = PRIORITY[icon] or 1,
	}

	if data.priority >= 3 then
		self:ClearQueue()
	end

	if #self.queue >= CONFIG.MaxQueueSize then
		table.remove(self.queue, 1)
	end

	table.insert(self.queue, data)

	return true
end

function DialogSystem:PlayRadio()
	if radioBeep then
		radioBeep:Play()
	end
end

function DialogSystem:ShowDialog(data)
	HUD:SetAttribute("DialogBusy", true)
	HUD.Enabled = true

	iconLabel.Image = ICON_MAP[data.icon] or ""
	iconLabel.Visible = iconLabel.Image ~= ""

	self.lastDialog.text = data.text
	self.lastDialog.time = tick()

	self:CancelTween()

	dialogContainer.Position = POS_HIDDEN
	dialogContainer.ImageTransparency = 1
	textLabel.TextTransparency = 1
	iconLabel.ImageTransparency = 1

	local tweenIn = TweenService:Create(dialogContainer, TWEEN_IN, {
		Position = POS_VISIBLE,
		ImageTransparency = DEFAULT_DIALOG_IMAGE_TRANSPARENCY,
	})
	local textFadeIn = TweenService:Create(textLabel, TWEEN_IN, { TextTransparency = DEFAULT_TEXT_TRANSPARENCY })
	local iconFadeIn = TweenService:Create(iconLabel, TWEEN_IN, { ImageTransparency = DEFAULT_ICON_TRANSPARENCY })

	self.currentTween = tweenIn
	tweenIn:Play()
	textFadeIn:Play()
	iconFadeIn:Play()
	tweenIn.Completed:Wait()

	self:PlayRadio()

	self:TypeText(data.text)

	task.wait(self:CalculateDisplayTime(data.text))

	local tweenOut = TweenService:Create(dialogContainer, TWEEN_OUT, {
		Position = POS_HIDDEN,
		ImageTransparency = 1,
	})
	local textFadeOut = TweenService:Create(textLabel, TWEEN_OUT, { TextTransparency = 1 })
	local iconFadeOut = TweenService:Create(iconLabel, TWEEN_OUT, { ImageTransparency = 1 })

	self.currentTween = tweenOut
	tweenOut:Play()
	textFadeOut:Play()
	iconFadeOut:Play()
	tweenOut.Completed:Wait()

	self.currentTween = nil
end

function DialogSystem:Process()
	if self.isActive then
		return
	end
	self.isActive = true

	task.spawn(function()
		while #self.queue > 0 do
			local data = table.remove(self.queue, 1)

			pcall(function()
				self:ShowDialog(data)
			end)

			if #self.queue > 0 then
				task.wait(CONFIG.PauseBetweenDialogs)
			end
		end

		self.isActive = false
		HUD:SetAttribute("DialogBusy", false)
		updateContainerEnabled()
	end)
end

function DialogSystem:ClearQueue()
	self.queue = {}

	self:CancelTween()

	dialogContainer.Position = POS_HIDDEN
	dialogContainer.ImageTransparency = 1
	textLabel.TextTransparency = 1
	iconLabel.ImageTransparency = 1
end

function DialogSystem:Show(icon, text)
	if self:Add(icon, text) then
		self:Process()
	end
end

-- =============================================================================
-- EVENTO
-- =============================================================================

showDialogEvent.OnClientEvent:Connect(function(icon, text)
	DialogSystem:Show(icon, text)
end)

-- =============================================================================
-- INIT
-- =============================================================================

dialogContainer.Position = POS_HIDDEN
dialogContainer.ImageTransparency = 1
textLabel.TextTransparency = 1
iconLabel.ImageTransparency = 1
if HUD:GetAttribute("DialogBusy") == nil then
	HUD:SetAttribute("DialogBusy", false)
end
updateContainerEnabled()
