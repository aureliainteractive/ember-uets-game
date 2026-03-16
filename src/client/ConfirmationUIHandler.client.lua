-- ConfirmationUIHandler
-- Purpose: Client-side handler for the ConfirmationUI ScreenGui shown
--          after the player completes mode/location/difficulty selection
--          at the kiosk. Populates the UI from KioskConfig display data,
--          then fires KioskConfirm or KioskCancel back to the server.
--
-- Expected ConfirmationUI hierarchy (adjust child names to match yours):
--
--   ConfirmationUI  (ScreenGui)
--     └── Container  (Frame, AnchorPoint 0.5, 0.5)
--           ├── modeLabel      (TextLabel) — simulation type display name
--           ├── locationLabel  (TextLabel) — selected location
--           ├── diffLabel      (TextLabel) — difficulty display name
--           ├── descLabel      (TextLabel) — simulation description  [optional]
--           ├── stepsLabel     (TextLabel) — step flow summary        [optional]
--           ├── BtnConfirm     (TextButton / ImageButton)
--           └── BtnCancel      (TextButton / ImageButton)
--
-- RemoteEvent dependencies (all in ReplicatedStorage):
--   KioskShowConfirmation  Server → Client  payload table or nil to hide
--   KioskConfirm           Client → Server  player confirmed
--   KioskCancel            Client → Server  player cancelled

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local KioskConfig = require(
	ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KioskConfig")
)

local showConfirmationEvent = ReplicatedStorage:WaitForChild("KioskShowConfirmation")
local confirmEvent          = ReplicatedStorage:WaitForChild("KioskConfirm")
local cancelEvent           = ReplicatedStorage:WaitForChild("KioskCancel")

-- ── UI REFERENCES ──────────────────────────────────────────────────
-- Adjust child names below to match your actual ConfirmationUI hierarchy.

local Screen    = playerGui:WaitForChild("ConfirmationUI")   -- ScreenGui
local Container = Screen:WaitForChild("Container")           -- Main frame

-- Required labels
local labelMode     = Container:FindFirstChild("modeLabel")
local labelLocation = Container:FindFirstChild("locationLabel")
local labelDiff     = Container:FindFirstChild("diffLabel")

-- Optional labels (silently skipped if absent in the ScreenGui)
local labelDesc     = Container:FindFirstChild("descLabel")   -- simulation description
local labelSteps    = Container:FindFirstChild("stepsLabel")  -- step flow summary

-- Action buttons
local btnConfirm    = Container:WaitForChild("BtnConfirm")
local btnCancel     = Container:WaitForChild("BtnCancel")

-- ── ANIMATION ──────────────────────────────────────────────────────
local TWEEN_IN  = TweenInfo.new(0.35, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

local POS_VISIBLE = UDim2.new(0.5, 0, 0.5, 0)  -- centred on screen
local POS_HIDDEN  = UDim2.new(0.5, 0, 1.6, 0)  -- below visible area

local function showUI()
	Screen.Enabled     = true
	Container.Position = POS_HIDDEN
	TweenService:Create(Container, TWEEN_IN, { Position = POS_VISIBLE }):Play()
end

local function hideUI()
	local t = TweenService:Create(Container, TWEEN_OUT, { Position = POS_HIDDEN })
	t:Play()
	t.Completed:Once(function()
		Screen.Enabled = false
	end)
end

-- ── POPULATE ───────────────────────────────────────────────────────
local function populate(mode, location, diff)
	local modeData = KioskConfig.getModeData(mode)
	local diffData = KioskConfig.getDifficultyData(diff)
	local steps    = KioskConfig.getSteps(mode)

	if labelMode then
		labelMode.Text = modeData and modeData.display or mode
	end
	if labelLocation then
		labelLocation.Text = location or "—"
	end
	if labelDiff then
		labelDiff.Text = diffData and diffData.display or diff
	end
	if labelDesc then
		labelDesc.Text = modeData and modeData.description or ""
	end
	if labelSteps then
		local detailed = steps.stepNamesDetailed
		if detailed and #detailed > 0 then
			-- Number each detailed step for readability
			local lines = {}
			for i, s in ipairs(detailed) do
				lines[i] = i .. ". " .. s
			end
			labelSteps.Text = table.concat(lines, "\n")
		else
			labelSteps.Text = steps.description or ""
		end
	end
end

-- ── BUTTON HANDLING ────────────────────────────────────────────────
-- Guard against ghost activations when the UI is not visible.

btnConfirm.Activated:Connect(function()
	if not Screen.Enabled then return end
	hideUI()
	pcall(function()
		confirmEvent:FireServer()
	end)
end)

btnCancel.Activated:Connect(function()
	if not Screen.Enabled then return end
	hideUI()
	pcall(function()
		cancelEvent:FireServer()
	end)
end)

-- ── REMOTE EVENT ───────────────────────────────────────────────────
-- Payload is a table { mode, location, diff } to show, or nil/false to hide.

showConfirmationEvent.OnClientEvent:Connect(function(payload)
	if not payload then
		hideUI()
		return
	end
	populate(payload.mode, payload.location, payload.diff)
	showUI()
end)

-- Start hidden
Screen.Enabled = false
