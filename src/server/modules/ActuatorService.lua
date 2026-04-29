-- ActuatorService
-- Purpose: Sends actuator commands to the external API endpoint.
-- Dependencies: HttpService

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActuatorConfig = require(script.Parent.ActuatorConfig)
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local ActuatorService = {}

-- Fires a physical actuator request and resolves through callback.
function ActuatorService.fire(player, actuatorName, value, duration, callback)
	if not player or not player.Parent then
		if callback then
			callback(false, "Jugador invalido")
		end
		return
	end
	if not actuatorName or value == nil then
		if callback then
			callback(false, "Parametros invalidos")
		end
		return
	end

	local payload = {
		actuator = actuatorName,
		value = tostring(value),
		duration = tonumber(duration) or 0,
		player = player.UserId,
		timestamp = os.time(),
	}

	local ok, result = pcall(function()
		return HttpService:PostAsync(
			ActuatorConfig.API_URL .. "/actuator",
			HttpService:JSONEncode(payload),
			Enum.HttpContentType.ApplicationJson,
			false,
			{ ["Content-Type"] = "application/json", ["Authorization"] = "Bearer " .. ActuatorConfig.API_KEY }
		)
	end)

	if not ok then
		Logger.error("Network", string.format("Actuator request failed for '%s': %s", actuatorName, tostring(result)))
		if callback then
			callback(false, "Error de conexion con el actuador")
		end
		return
	end

	if callback then
		callback(true, result)
	end
end

return ActuatorService
