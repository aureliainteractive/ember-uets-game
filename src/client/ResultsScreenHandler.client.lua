-- ResultsScreenHandler
-- Purpose: Receives the ShowResults payload and populates the results ScreenGui.
-- Dependencies: ReplicatedStorage.ShowResults, ReplicatedStorage.ReturnToLobby
-- NOTE: Adjust every WaitForChild name to match your actual ScreenGui hierarchy.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local showResultsEvent = ReplicatedStorage:WaitForChild("ShowResults")
local returnToLobbyEvent = ReplicatedStorage:WaitForChild("ReturnToLobby")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

-- ============================================================
-- UI REFERENCES — adjust names to match your ScreenGui
-- ============================================================

local Screen = playerGui:WaitForChild("ResultsScreen") -- ScreenGui
local Container = Screen:WaitForChild("Container") -- Main Frame

-- Header
local LabelHeader = Container:WaitForChild("LabelHeader") -- TextLabel: "SimType | Location | Difficulty"

-- Score block
local LabelRank = Container:WaitForChild("LabelRank") -- TextLabel  (coloured)
local LabelPoints = Container:WaitForChild("LabelPoints") -- TextLabel
local LabelTime = Container:WaitForChild("LabelTime") -- TextLabel
local LabelPrecision = Container:WaitForChild("LabelPrecision") -- TextLabel
local LabelErrors = Container:WaitForChild("LabelErrors") -- TextLabel
local LabelObjectives = Container:WaitForChild("LabelObjectives") -- TextLabel  e.g. "4/4"
local RankContainer = Container:WaitForChild("RankContainer") -- ImageLabel or container with one

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
	["S"] = Color3.fromRGB(80, 200, 80),
	["A+"] = Color3.fromRGB(80, 200, 80),
	["A"] = Color3.fromRGB(80, 200, 80),
	["B+"] = Color3.fromRGB(240, 200, 60),
	["B"] = Color3.fromRGB(240, 200, 60),
	["C+"] = Color3.fromRGB(240, 200, 60),
	["C"] = Color3.fromRGB(220, 70, 70),
	["D"] = Color3.fromRGB(220, 70, 70),
}

local RANK_STATUS = {
	["S"] = "Aprobado",
	["A+"] = "Aprobado",
	["A"] = "Aprobado",
	["B+"] = "Aprobado",
	["B"] = "Aprobado",
	["C+"] = "Aprobado en el límite",
	["C"] = "No aprobado",
	["D"] = "No aprobado",
}

local RANK_BAND = {
	["S"] = "GREEN",
	["A+"] = "GREEN",
	["A"] = "GREEN",
	["B+"] = "YELLOW",
	["B"] = "YELLOW",
	["C+"] = "YELLOW",
	["C"] = "RED",
	["D"] = "RED",
}

-- Replace these with your real image asset ids.
local RANK_BAND_IMAGES = {
	GREEN = "rbxassetid://140721936487947",
	YELLOW = "rbxassetid://119407907574369",
	RED = "rbxassetid://88357135721128",
}

local TWEEN_IN = TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local ROW_TWEEN_IN = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local ROW_STAGGER = 0.04

local POS_VISIBLE = UDim2.new(0.5, 0, 0.5, 0) -- centred
local POS_HIDDEN = UDim2.new(0.5, 0, 1.6, 0) -- below screen

local DEFAULT_CONTAINER_IMAGE_TRANSPARENCY = Container.ImageTransparency

local function setRowTextTransparency(row, value)
	for _, desc in ipairs(row:GetDescendants()) do
		if desc:IsA("TextLabel") or desc:IsA("TextButton") then
			desc.TextTransparency = value
		end
	end
end

-- ============================================================
-- HELPERS
-- ============================================================

local function showScreen()
	Screen.Enabled = true
	Container.Position = POS_HIDDEN
	Container.ImageTransparency = 1
	for _, row in ipairs(StepRows) do
		setRowTextTransparency(row, 1)
	end
	TweenService:Create(Container, TWEEN_IN, {
		Position = POS_VISIBLE,
		ImageTransparency = DEFAULT_CONTAINER_IMAGE_TRANSPARENCY,
	}):Play()

	for index, row in ipairs(StepRows) do
		task.delay((index - 1) * ROW_STAGGER + 0.12, function()
			if not Screen.Enabled or not row.Visible then
				return
			end
			for _, desc in ipairs(row:GetDescendants()) do
				if desc:IsA("TextLabel") or desc:IsA("TextButton") then
					TweenService:Create(desc, ROW_TWEEN_IN, { TextTransparency = 0 }):Play()
				end
			end
		end)
	end
end

local function hideScreen()
	local t = TweenService:Create(Container, TWEEN_OUT, {
		Position = POS_HIDDEN,
		ImageTransparency = 1,
	})
	t:Play()
	t.Completed:Once(function()
		Screen.Enabled = false
	end)
end

local function getRankImageTarget()
	if RankContainer:IsA("ImageLabel") then
		return RankContainer
	end

	local explicit = RankContainer:FindFirstChild("RankImage")
	if explicit and explicit:IsA("ImageLabel") then
		return explicit
	end

	local firstImage = RankContainer:FindFirstChildWhichIsA("ImageLabel", true)
	if firstImage then
		return firstImage
	end

	Logger.warn("UI", "RankContainer has no ImageLabel target")
	return nil
end

local function populate(payload)
	-- Header
	local simType = payload.simType or "—"
	local location = payload.locationName or "—"
	local difficulty = DIFFICULTY_NAMES[payload.difficulty] or tostring(payload.difficulty)
	LabelHeader.Text = string.format("%s | %s | %s", simType, location, difficulty)

	-- Score block
	local rank = payload.rank or "D"
	local status = RANK_STATUS[rank] or "No aprobado"
	LabelRank.Text = string.format("%s - Rango %s", status, rank)
	LabelRank.TextColor3 = RANK_COLORS[rank] or Color3.fromRGB(220, 70, 70)

	local rankBand = RANK_BAND[rank] or "RED"
	local rankImageId = RANK_BAND_IMAGES[rankBand]
	local rankImageTarget = getRankImageTarget()
	if rankImageTarget and rankImageId and rankImageId ~= "" then
		rankImageTarget.Image = rankImageId
	end

	LabelPoints.Text = tostring(payload.totalPoints)
	LabelTime.Text = payload.totalTime or "00:00"
	LabelPrecision.Text = tostring(payload.precision) .. "%"
	LabelErrors.Text = tostring(payload.criticalErrors)
	LabelObjectives.Text = payload.objectivesDone .. "/" .. payload.objectivesTotal

	-- Per-step rows
	local steps = payload.stepResults or {}
	for i, row in ipairs(StepRows) do
		local step = steps[i]
		if step then
			row.Visible = true
			row:WaitForChild("LabelName").Text = step.name or ("Paso " .. i)
			row:WaitForChild("LabelTime").Text = string.format("%.1fs", step.time)
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
	if type(payload) ~= "table" then
		return
	end
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
