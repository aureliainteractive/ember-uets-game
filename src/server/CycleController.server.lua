-- Place in: ServerScriptService (Script)

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

-- =========================
-- CONFIG
-- =========================
local DAY_LENGTH_SECONDS = 30 -- un día completo (24h) dura esto en segundos
local BLACKOUT_NIGHT_TIME = 0 -- hora forzada durante blackout (0 = medianoche)

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
		Lighting.Atmosphere.Density = 0.6
		return
	else
		Lighting.Atmosphere.Density = 0
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
