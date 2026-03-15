-- ActuatorService
-- Purpose: Sends actuator commands to the external API endpoint.
-- Dependencies: HttpService

local HttpService = game:GetService("HttpService")

local API_URL = "https://myurlhere.com/api"
local API_KEY = "REPLACE_WITH_KEY"

local ActuatorService = {}

-- Fires a physical actuator request and resolves through callback.
function ActuatorService.fire(player, actuatorName, value, duration, callback)
	if not player or not player.Parent then
		if callback then callback(false, "Jugador invalido") end
		return
	end
	if not actuatorName or value == nil then
		if callback then callback(false, "Parametros invalidos") end
		return
	end

	local payload = {
		actuator  = actuatorName,
		value     = tostring(value),
		duration  = tonumber(duration) or 0,
		player    = player.UserId,
		timestamp = os.time(),
	}

	local ok, result = pcall(function()
		return HttpService:PostAsync(
			API_URL .. "/actuator",
			HttpService:JSONEncode(payload),
			Enum.HttpContentType.ApplicationJson,
			false,
			{ ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. API_KEY }
		)
	end)

	if not ok then
		warn(string.format("[SimController] Error al contactar actuador '%s': %s", actuatorName, tostring(result)))
		if callback then callback(false, "Error de conexion con el actuador") end
		return
	end

	if callback then callback(true, result) end
end

return ActuatorService
