-- Place in: ServerScriptService (Script)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConstants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GameConstants"))

-- =========================
-- CONFIG (from GameConstants)
-- =========================
local DAY_LENGTH_SECONDS = GameConstants.DAY_CYCLE.DAY_LENGTH_SECONDS
local BLACKOUT_NIGHT_TIME = GameConstants.DAY_CYCLE.BLACKOUT_NIGHT_TIME

-- =========================
-- INTERNAL
-- =========================
local gameHoursPerSecond = 24 / DAY_LENGTH_SECONDS
local last = time()

RunService.Heartbeat:Connect(function()
	local now = time()
	local dt = now - last
	last = now

	local powerMode = Lighting:GetAttribute("PowerMode")

	-- 🌑 BLACKOUT → noche forzada
	if powerMode == "BLACKOUT" then
		Lighting.ClockTime = BLACKOUT_NIGHT_TIME
		Lighting.Atmosphere.Density = GameConstants.DAY_CYCLE.ATMOSPHERE_DENSITY_BLACKOUT
		return
	else
		Lighting.Atmosphere.Density = GameConstants.DAY_CYCLE.ATMOSPHERE_DENSITY_NORMAL
	end

	-- 🕒 Ciclo normal
	local newClock = Lighting.ClockTime + (dt * gameHoursPerSecond)

	-- Mantener rango 0-24
	if newClock >= 24 then
		newClock -= 24
	elseif newClock < 0 then
		newClock += 24
	end

	Lighting.ClockTime = newClock
end)
