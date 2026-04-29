-- ConfirmationUIHandler
-- Purpose: Client-side handler for the ConfirmationUI ScreenGui shown
--          after the player completes mode/location/difficulty selection
--          at the kiosk. Populates the detailed step objectives from
--          KioskConfig, then fires KioskConfirm back to the server.
--
-- ConfirmationUI hierarchy (StarterGui):
--   ConfirmationUI  (ScreenGui)
--     ├── Panel       (ImageLabel)   — animated in/out
--     │   └── Objectives  (Frame)
--     │         ├── UIGridLayout
--     │         ├── Objective1  (TextLabel)
--     │         ├── Objective2  (TextLabel)
--     │         ├── Objective3  (TextLabel)
--     │         └── Objective4  (TextLabel)
--     ├── Controles   (ImageLabel)   — static controls hint
--     └── Confirmar   (ImageButton)  — confirm only, no cancel button
--
-- RemoteEvent dependencies (all in ReplicatedStorage):
--   KioskShowConfirmation  Server → Client  payload table or nil to hide
--   KioskConfirm           Client → Server  player confirmed

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UIManager = require(ReplicatedStorage.Shared.UIManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local KioskConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig"))

local showConfirmationEvent = ReplicatedStorage:WaitForChild("KioskShowConfirmation")
local confirmEvent = ReplicatedStorage:WaitForChild("KioskConfirm")

-- ── UI REFERENCES ──────────────────────────────────────────────────

local Screen = UIManager.get(playerGui, "ConfirmationUI") -- ScreenGui
local Panel = UIManager.get(Screen, "Panel") -- ImageLabel (animated)
local Controles = UIManager.get(Screen, "Controles") -- ImageLabel (animated)
local Objectives = UIManager.get(Panel, "Objectives") -- Frame (UIGridLayout)
local btnConfirm = UIManager.get(Screen, "Confirmar") -- ImageButton

-- Objective TextLabels (Objective1–Objective4)
local ObjectiveLabels = {
	Objectives:WaitForChild("Objective1"),
	Objectives:WaitForChild("Objective2"),
	Objectives:WaitForChild("Objective3"),
	Objectives:WaitForChild("Objective4"),
}

-- ── ANIMATION ──────────────────────────────────────────────────────
local TWEEN_IN = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local STAGGER_STEP = 0.05
local ANIMATION_ORDER = { Panel, Controles, btnConfirm }

local DEFAULT_IMAGE_TRANSPARENCY = {
	[Panel] = Panel.ImageTransparency,
	[Controles] = Controles.ImageTransparency,
	[btnConfirm] = btnConfirm.ImageTransparency,
}

local function toHidden(pos)
	return UDim2.new(pos.X.Scale, pos.X.Offset, pos.Y.Scale + 0.25, pos.Y.Offset)
end

local VISIBLE_POSITIONS = {
	[Panel] = Panel.Position,
	[Controles] = Controles.Position,
	[btnConfirm] = btnConfirm.Position,
}

local HIDDEN_POSITIONS = {
	[Panel] = toHidden(Panel.Position),
	[Controles] = toHidden(Controles.Position),
	[btnConfirm] = toHidden(btnConfirm.Position),
}

local transitionToken = 0

local function setHiddenImmediate()
	for ui, hiddenPos in pairs(HIDDEN_POSITIONS) do
		ui.Position = hiddenPos
		ui.ImageTransparency = 1
	end
end

local function showUI()
	transitionToken += 1
	local token = transitionToken
	Screen.Enabled = true
	setHiddenImmediate()
	for index, ui in ipairs(ANIMATION_ORDER) do
		local visiblePos = VISIBLE_POSITIONS[ui]
		task.delay((index - 1) * STAGGER_STEP, function()
			if token ~= transitionToken or not Screen.Enabled then
				return
			end
			TweenService:Create(ui, TWEEN_IN, {
				Position = visiblePos,
				ImageTransparency = DEFAULT_IMAGE_TRANSPARENCY[ui],
			}):Play()
		end)
	end
end

local function hideUI()
	transitionToken += 1
	local token = transitionToken
	for index = #ANIMATION_ORDER, 1, -1 do
		local ui = ANIMATION_ORDER[index]
		local hiddenPos = HIDDEN_POSITIONS[ui]
		task.delay((#ANIMATION_ORDER - index) * STAGGER_STEP * 0.8, function()
			if token ~= transitionToken then
				return
			end
			TweenService:Create(ui, TWEEN_OUT, {
				Position = hiddenPos,
				ImageTransparency = 1,
			}):Play()
		end)
	end
	task.delay(TWEEN_OUT.Time + STAGGER_STEP * (#ANIMATION_ORDER - 1), function()
		if token == transitionToken then
			Screen.Enabled = false
		end
	end)
end

-- ── POPULATE ───────────────────────────────────────────────────────
local function populate(mode)
	local steps = KioskConfig.getSteps(mode)
	local detailed = steps.stepNamesDetailed or {}

	for i, label in ipairs(ObjectiveLabels) do
		local text = detailed[i]
		if text then
			label.Text = i .. ". " .. text
			label.Visible = true
		else
			label.Text = ""
			label.Visible = false
		end
	end
end

-- ── BUTTON HANDLING ────────────────────────────────────────────────
btnConfirm.Activated:Connect(function()
	if not Screen.Enabled then
		return
	end
	hideUI()
	pcall(function()
		confirmEvent:FireServer()
	end)
end)

-- ── REMOTE EVENT ───────────────────────────────────────────────────
-- Payload is a table { mode, location, diff } to show, or nil/false to hide.
showConfirmationEvent.OnClientEvent:Connect(function(payload)
	if not payload then
		hideUI()
		return
	end
	populate(payload.mode)
	showUI()
end)

-- Start hidden (matches your place setup where Enabled=false on load)
Screen.Enabled = false
setHiddenImmediate()
