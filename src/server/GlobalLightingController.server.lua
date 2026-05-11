--// Global Light + Neon + Glass Manager (Optimizado con CacheManager)
--// Place in: ServerScriptService (Script)
--// Uses CacheManager for O(1) light/part tracking instead of linear array iteration.

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CacheManager = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Modules"):WaitForChild("CacheManager"))
local GameConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConstants"))

-- =========================
-- CONFIG (from GameConstants)
-- =========================
local NIGHT_START = GameConstants.LIGHTING.NIGHT_START
local NIGHT_END = GameConstants.LIGHTING.NIGHT_END

local DAY_LIGHT_BRIGHTNESS = GameConstants.LIGHTING.DAY_LIGHT_BRIGHTNESS
local DAY_LIGHT_COLOR = GameConstants.LIGHTING.DAY_LIGHT_COLOR

local NIGHT_LIGHT_BRIGHTNESS = GameConstants.LIGHTING.NIGHT_LIGHT_BRIGHTNESS
local NIGHT_LIGHT_COLOR = GameConstants.LIGHTING.NIGHT_LIGHT_COLOR

local DAY_GLASS_TRANSPARENCY = GameConstants.LIGHTING.DAY_GLASS_TRANSPARENCY
local NIGHT_GLASS_TRANSPARENCY = GameConstants.LIGHTING.NIGHT_GLASS_TRANSPARENCY

local OFF_MATERIAL = GameConstants.LIGHTING.OFF_MATERIAL
local ON_MATERIAL = GameConstants.LIGHTING.ON_MATERIAL

local TRANSPARENCY_EPSILON = GameConstants.LIGHTING.TRANSPARENCY_EPSILON

local LIGHT_CLASSES = {
	PointLight = true,
	SurfaceLight = true,
	SpotLight = true,
}

local VALID_MODES = GameConstants.LIGHTING.VALID_MODES

-- Tween settings
local TWEEN_TIME_LIGHT = GameConstants.ANIMATION.LIGHT_TWEEN_TIME
local TWEEN_TIME_GLASS = GameConstants.ANIMATION.GLASS_TWEEN_TIME

-- =========================
-- HELPERS (define early for use in CacheManager)
-- =========================
local function isNight(clockTime: number): boolean
	return (clockTime >= NIGHT_START) or (clockTime < NIGHT_END)
end

local function isEmergency(inst: Instance): boolean
	return CollectionService:HasTag(inst, "Emergency") or inst:GetAttribute("Emergency") == true
end

local function getPowerMode(): string
	local mode = Lighting:GetAttribute("PowerMode")
	if type(mode) == "string" and VALID_MODES[mode] then
		return mode
	end
	return "NORMAL"
end

-- 🔑 Regla final
local function shouldBeOn(mode: string, night: boolean, emergency: boolean): boolean
	if emergency then
		return mode == "BLACKOUT"
	end

	if mode == "BLACKOUT" then
		return false
	elseif mode == "FORCE_ON" then
		return true
	else
		return night
	end
end

local function getLightParamsForTime(night: boolean)
	if night then
		return NIGHT_LIGHT_BRIGHTNESS, NIGHT_LIGHT_COLOR
	else
		return DAY_LIGHT_BRIGHTNESS, DAY_LIGHT_COLOR
	end
end

-- =========================
-- CACHE (Using CacheManager)
-- =========================
local cacheManager = nil

local function initializeCacheManager()
	cacheManager = CacheManager.new(workspace, {
		lightClasses = { "PointLight", "SurfaceLight", "SpotLight" },
		neonFilter = function(inst)
			return inst:IsA("BasePart") and (inst.Material == Enum.Material.Neon or isEmergency(inst))
		end,
		glassFilter = function(inst)
			return inst:IsA("BasePart") and inst.Material == Enum.Material.Glass
		end,
	})
	cacheManager:initialize()
end

local lastAppliedKey = nil

-- =========================
-- HELPERS
-- =========================
local function isNight(clockTime: number): boolean
	return (clockTime >= NIGHT_START) or (clockTime < NIGHT_END)
end

local function isEmergency(inst: Instance): boolean
	return CollectionService:HasTag(inst, "Emergency") or inst:GetAttribute("Emergency") == true
end

local function getPowerMode(): string
	local mode = Lighting:GetAttribute("PowerMode")
	if type(mode) == "string" and VALID_MODES[mode] then
		return mode
	end
	return "NORMAL"
end

-- 🔑 Regla final
local function shouldBeOn(mode: string, night: boolean, emergency: boolean): boolean
	if emergency then
		return mode == "BLACKOUT"
	end

	if mode == "BLACKOUT" then
		return false
	elseif mode == "FORCE_ON" then
		return true
	else
		return night
	end
end

local function getLightParamsForTime(night: boolean)
	if night then
		return NIGHT_LIGHT_BRIGHTNESS, NIGHT_LIGHT_COLOR
	else
		return DAY_LIGHT_BRIGHTNESS, DAY_LIGHT_COLOR
	end
end

-- CacheManager initialization is deferred until after APPLY is defined

-- =========================
-- TWEENS
-- =========================
local function tweenLight(light: Instance, brightness: number, color: Color3)
	local tweenInfo = TweenInfo.new(TWEEN_TIME_LIGHT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(light, tweenInfo, {
		Brightness = brightness,
		Color = color,
	}):Play()
end

local function tweenTransparency(part: BasePart, target: number)
	if math.abs(part.Transparency - target) <= TRANSPARENCY_EPSILON then
		part.Transparency = target
		return
	end

	local tweenInfo = TweenInfo.new(TWEEN_TIME_GLASS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(part, tweenInfo, { Transparency = target }):Play()
end

-- =========================
-- APPLY
-- =========================
local function applyState()
	local mode = getPowerMode()
	local night = isNight(Lighting.ClockTime)

	local key = mode .. "|" .. (night and "N" or "D")
	if key == lastAppliedKey then
		return
	end
	lastAppliedKey = key

	if not cacheManager then
		return
	end

	local instant = (mode == "BLACKOUT")

	-- 1) LIGHTS
	for _, light in ipairs(cacheManager:getLights()) do
		if light and light.Parent then
			local emergency = isEmergency(light)
			local on = shouldBeOn(mode, night, emergency)

			-- 🚨 EMERGENCY: solo ON / OFF
			if emergency then
				light.Enabled = on
				continue
			end

			-- 💡 LUCES NORMALES
			if instant then
				light.Enabled = on
				if on then
					light.Brightness = NIGHT_LIGHT_BRIGHTNESS
					light.Color = NIGHT_LIGHT_COLOR
				end
			else
				light.Enabled = true
				local b, c = getLightParamsForTime(night)
				tweenLight(light, b, c)
			end
		end
	end

	-- 2) NEON PARTS
	for _, part in ipairs(cacheManager:getNeonParts()) do
		if part and part.Parent then
			local on = shouldBeOn(mode, night, isEmergency(part))
			part.Material = on and ON_MATERIAL or OFF_MATERIAL
		end
	end

	-- 3) GLASS
	local targetGlass = night and NIGHT_GLASS_TRANSPARENCY or DAY_GLASS_TRANSPARENCY
	for _, part in ipairs(cacheManager:getGlassParts()) do
		if part and part.Parent then
			if instant then
				part.Transparency = targetGlass
			else
				tweenTransparency(part, targetGlass)
			end
		end
	end
end

-- =========================
-- EVENTS
-- =========================
Lighting:GetAttributeChangedSignal("PowerMode"):Connect(function()
	lastAppliedKey = nil
	applyState()
end)

-- =========================
-- INIT
-- =========================
if Lighting:GetAttribute("PowerMode") == nil then
	Lighting:SetAttribute("PowerMode", "NORMAL")
end

-- Initialize CacheManager (must happen after applyState is defined)
initializeCacheManager()
applyState()

-- Periodic safety check
task.spawn(function()
	while true do
		applyState()
		task.wait(2)
	end
end)

-- =========================
-- OPTIONAL: BindableEvent
-- =========================
local powerEvent = ReplicatedStorage:FindFirstChild("PowerControl")
if powerEvent and powerEvent:IsA("BindableEvent") then
	powerEvent.Event:Connect(function(newMode)
		if VALID_MODES[newMode] then
			Lighting:SetAttribute("PowerMode", newMode)
		end
	end)
end
