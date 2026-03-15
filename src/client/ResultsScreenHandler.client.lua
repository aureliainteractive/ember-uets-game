-- ResultsScreenHandler
-- Purpose: Receives the ShowResults payload and populates the results ScreenGui.
-- Dependencies: ReplicatedStorage.ShowResults, ReplicatedStorage.ReturnToLobby
-- NOTE: Adjust every WaitForChild name to match your actual ScreenGui hierarchy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local showResultsEvent   = ReplicatedStorage:WaitForChild("ShowResults")
local returnToLobbyEvent = ReplicatedStorage:WaitForChild("ReturnToLobby")

-- ============================================================
-- UI REFERENCES — adjust names to match your ScreenGui
-- ============================================================

local Screen      = playerGui:WaitForChild("ResultsScreen")       -- ScreenGui
local Container   = Screen:WaitForChild("Container")              -- Main Frame

-- Header
local LabelHeader = Container:WaitForChild("LabelHeader") -- TextLabel: "SimType | Location | Difficulty"

-- Score block
local LabelRank       = Container:WaitForChild("LabelRank")       -- TextLabel  (coloured)
local LabelPoints     = Container:WaitForChild("LabelPoints")     -- TextLabel
local LabelTime       = Container:WaitForChild("LabelTime")       -- TextLabel
local LabelPrecision  = Container:WaitForChild("LabelPrecision")  -- TextLabel
local LabelErrors     = Container:WaitForChild("LabelErrors")     -- TextLabel
local LabelObjectives = Container:WaitForChild("LabelObjectives") -- TextLabel  e.g. "4/4"

-- Per-step rows — one Frame per step, each with LabelName, LabelTime, LabelPoints
-- Adjust the parent folder name if needed.
local StepsFolder = Container:WaitForChild("Steps")
local StepRows = {
	StepsFolder:WaitForChild("Step1"),
	StepsFolder:WaitForChild("Step2"),
	StepsFolder:WaitForChild("Step3"),
	StepsFolder:WaitForChild("Step4"),
}

-- Return button
local BtnReturn = Container:WaitForChild("BtnReturn") -- TextButton

-- ============================================================
-- CONSTANTS
-- ============================================================

local DIFFICULTY_NAMES = { [1] = "Fácil", [2] = "Medio", [3] = "Difícil" }

-- Rank colour bands
--   Green  → S, A+, A
--   Yellow → B+, B, C+
--   Red    → C, D
local RANK_COLORS = {
	["S"]  = Color3.fromRGB(80,  200, 80),
	["A+"] = Color3.fromRGB(80,  200, 80),
	["A"]  = Color3.fromRGB(80,  200, 80),
	["B+"] = Color3.fromRGB(240, 200, 60),
	["B"]  = Color3.fromRGB(240, 200, 60),
	["C+"] = Color3.fromRGB(240, 200, 60),
	["C"]  = Color3.fromRGB(220, 70,  70),
	["D"]  = Color3.fromRGB(220, 70,  70),
}

local TWEEN_IN  = TweenInfo.new(0.4, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

local POS_VISIBLE = UDim2.new(0.5, 0, 0.5, 0)  -- centred
local POS_HIDDEN  = UDim2.new(0.5, 0, 1.6, 0)  -- below screen

-- ============================================================
-- HELPERS
-- ============================================================

local function showScreen()
	Screen.Enabled = true
	Container.Position = POS_HIDDEN
	TweenService:Create(Container, TWEEN_IN, { Position = POS_VISIBLE }):Play()
end

local function hideScreen()
	local t = TweenService:Create(Container, TWEEN_OUT, { Position = POS_HIDDEN })
	t:Play()
	t.Completed:Once(function()
		Screen.Enabled = false
	end)
end

local function populate(payload)
	-- Header
	local simType = payload.simType or "—"
	local location = payload.locationName or "—"
	local difficulty = DIFFICULTY_NAMES[payload.difficulty] or tostring(payload.difficulty)
	LabelHeader.Text = string.format("%s | %s | %s", simType, location, difficulty)

	-- Score block
	local rank = payload.rank or "D"
	LabelRank.Text      = rank
	LabelRank.TextColor3 = RANK_COLORS[rank] or Color3.fromRGB(220, 70, 70)

	LabelPoints.Text    = tostring(payload.totalPoints)
	LabelTime.Text      = payload.totalTime or "00:00"
	LabelPrecision.Text = tostring(payload.precision) .. "%"
	LabelErrors.Text    = tostring(payload.criticalErrors)
	LabelObjectives.Text = payload.objectivesDone .. "/" .. payload.objectivesTotal

	-- Per-step rows
	local steps = payload.stepResults or {}
	for i, row in ipairs(StepRows) do
		local step = steps[i]
		if step then
			row.Visible = true
			row:WaitForChild("LabelName").Text   = step.name   or ("Paso " .. i)
			row:WaitForChild("LabelTime").Text   = string.format("%.1fs", step.time)
			row:WaitForChild("LabelPoints").Text = tostring(step.points) .. " pts"
		else
			row.Visible = false
		end
	end
end

-- ============================================================
-- EVENTS
-- ============================================================

showResultsEvent.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	populate(payload)
	showScreen()
end)

BtnReturn.Activated:Connect(function()
	hideScreen()
	pcall(function()
		returnToLobbyEvent:FireServer()
	end)
end)

-- Start hidden
Screen.Enabled = false
