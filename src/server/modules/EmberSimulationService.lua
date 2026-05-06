-- EmberSimulationService
-- Notifies ember-server when Roblox starts or stops a simulation.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(script.Parent.EmberServerConfig)
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local EmberSimulationService = {}

local activeByUserId = {}

local function endpoint(path)
	return Config.API_BASE_URL .. path
end

local function postJson(path, payload)
	local response = HttpService:RequestAsync({
		Url = endpoint(path),
		Method = "POST",
		Headers = {
			["Content-Type"] = "application/json",
		},
		Body = HttpService:JSONEncode(payload or {}),
	})

	if not response.Success then
		return false, string.format("HTTP %d: %s", response.StatusCode, response.Body)
	end

	local decoded = {}
	if response.Body and response.Body ~= "" then
		local ok, result = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if ok and type(result) == "table" then
			decoded = result
		end
	end

	return true, decoded
end

function EmberSimulationService.start(player, robloxMode, difficultyLevel)
	if not player or not player.Parent then
		return false, "Jugador invalido"
	end

	local emberMode = Config.ROBLOX_MODE_TO_EMBER_MODE[robloxMode]
	local emberDifficulty = Config.ROBLOX_DIFFICULTY_TO_EMBER_DIFFICULTY[difficultyLevel]
	if not emberMode or not emberDifficulty then
		return false, "Simulacion o dificultad no soportada por ember-server"
	end

	local ok, result = postJson("/simulation/start", {
		mode = emberMode,
		difficulty = emberDifficulty,
	})

	if not ok then
		Logger.error("Network", "EMBER simulation_start failed: " .. tostring(result))
		return false, result
	end

	activeByUserId[player.UserId] = {
		mode = emberMode,
		difficulty = emberDifficulty,
		startedAt = os.clock(),
	}

	if result.cabina_notified == false then
		Logger.warn("Network", "EMBER server accepted simulation_start but cabina is disconnected")
	else
		Logger.info("Network", string.format("EMBER simulation_start sent: %s [%s]", emberMode, emberDifficulty))
	end

	return true, result
end

function EmberSimulationService.stop(player)
	if not player then
		return true
	end

	if not activeByUserId[player.UserId] then
		return true
	end

	local ok, result = postJson("/simulation/stop", {})
	activeByUserId[player.UserId] = nil

	if not ok then
		Logger.error("Network", "EMBER simulation_stop failed: " .. tostring(result))
		return false, result
	end

	if result.cabina_notified == false then
		Logger.warn("Network", "EMBER server accepted simulation_stop but cabina is disconnected")
	else
		Logger.info("Network", "EMBER simulation_stop sent")
	end

	return true, result
end

function EmberSimulationService.startEarthquakeMotor(durationSeconds, difficultyLevel)
	local motorConfig = Config.EARTHQUAKE_MOTOR_BY_DIFFICULTY[difficultyLevel]
	if not motorConfig then
		return false, "Dificultad de motor no soportada"
	end

	local durationMs = math.max(1, math.floor((tonumber(durationSeconds) or 0) * 1000))
	local speed = tonumber(motorConfig.speed) or 0

	local ok, result = postJson("/motor", {
		duracion = durationMs,
		velocidad = speed,
	})

	if not ok then
		Logger.error("Network", "EMBER motor command failed: " .. tostring(result))
		return false, result
	end

	if result.sent == false then
		Logger.warn("Network", "EMBER server accepted motor command but cabina is disconnected")
	else
		Logger.info("Network", string.format("EMBER motor command sent: %dms speed=%d", durationMs, speed))
	end

	return true, result
end

function EmberSimulationService.clear(player)
	if player then
		activeByUserId[player.UserId] = nil
	end
end

return EmberSimulationService
