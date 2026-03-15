--// Global Light + Neon + Glass Manager (Optimizado)
--// Place in: ServerScriptService (Script)

local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- =========================
-- CONFIG
-- =========================
local NIGHT_START = 18.0
local NIGHT_END   = 6.0

-- Parámetros luces normales
local DAY_LIGHT_BRIGHTNESS = 0.25
local DAY_LIGHT_COLOR = Color3.fromRGB(255, 255, 255)

local NIGHT_LIGHT_BRIGHTNESS = 0.5
local NIGHT_LIGHT_COLOR = Color3.fromRGB(200, 200, 200)

-- Glass transparency
local DAY_GLASS_TRANSPARENCY = 0.6
local NIGHT_GLASS_TRANSPARENCY = 0.8

-- Material swap
local OFF_MATERIAL = Enum.Material.SmoothPlastic
local ON_MATERIAL  = Enum.Material.Neon

local LIGHT_CLASSES = {
	PointLight = true,
	SurfaceLight = true,
	SpotLight = true,
}

local VALID_MODES = {
	NORMAL = true,
	BLACKOUT = true,
	FORCE_ON = true,
}

-- Tween settings
local TWEEN_TIME_LIGHT = 0.35
local TWEEN_TIME_GLASS = 0.35

local TRANSPARENCY_EPSILON = 0.01

-- =========================
-- CACHE
-- =========================
local cachedLights = {}
local cachedNeonParts = {}
local cachedGlassParts = {}

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

-- =========================
-- CACHE BUILD
-- =========================
local function tryCacheInstance(inst: Instance)
	if LIGHT_CLASSES[inst.ClassName] then
		table.insert(cachedLights, inst)
		return
	end

	if inst:IsA("BasePart") then
		if inst.Material == Enum.Material.Neon or isEmergency(inst) then
			table.insert(cachedNeonParts, inst)
		end

		if inst.Material == Enum.Material.Glass then
			table.insert(cachedGlassParts, inst)
		end
	end
end

local function buildCache()
	table.clear(cachedLights)
	table.clear(cachedNeonParts)
	table.clear(cachedGlassParts)

	for _, inst in ipairs(workspace:GetDescendants()) do
		tryCacheInstance(inst)
	end
end

local function cleanupCache()
	for i = #cachedLights, 1, -1 do
		if not cachedLights[i] or not cachedLights[i].Parent then
			table.remove(cachedLights, i)
		end
	end
	for i = #cachedNeonParts, 1, -1 do
		if not cachedNeonParts[i] or not cachedNeonParts[i].Parent then
			table.remove(cachedNeonParts, i)
		end
	end
	for i = #cachedGlassParts, 1, -1 do
		if not cachedGlassParts[i] or not cachedGlassParts[i].Parent then
			table.remove(cachedGlassParts, i)
		end
	end
end

-- =========================
-- TWEENS
-- =========================
local function tweenLight(light: Instance, brightness: number, color: Color3)
	local tweenInfo = TweenInfo.new(TWEEN_TIME_LIGHT, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(light, tweenInfo, {
		Brightness = brightness,
		Color = color
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
	if key == lastAppliedKey then return end
	lastAppliedKey = key

	cleanupCache()

	local instant = (mode == "BLACKOUT")

	-- 1) LIGHTS
	for _, light in ipairs(cachedLights) do
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
	for _, part in ipairs(cachedNeonParts) do
		if part and part.Parent then
			local on = shouldBeOn(mode, night, isEmergency(part))
			part.Material = on and ON_MATERIAL or OFF_MATERIAL
		end
	end

	-- 3) GLASS
	local targetGlass = night and NIGHT_GLASS_TRANSPARENCY or DAY_GLASS_TRANSPARENCY
	for _, part in ipairs(cachedGlassParts) do
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
workspace.DescendantAdded:Connect(tryCacheInstance)

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

buildCache()
applyState()

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
