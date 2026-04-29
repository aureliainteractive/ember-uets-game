-- LocalScript en StarterPlayer > StarterPlayerScripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local VRService = game:GetService("VRService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local CameraShakeEvent = ReplicatedStorage:WaitForChild("CameraShakeEvent")

local shaking = false
local shakeConnection = nil
local activeHumanoid = nil

local function getHumanoid()
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChildOfClass("Humanoid")
end

local function stopShake()
	if shakeConnection then
		shakeConnection:Disconnect()
		shakeConnection = nil
	end

	if activeHumanoid then
		activeHumanoid.CameraOffset = Vector3.zero
		activeHumanoid = nil
	end

	shaking = false
end

-- Detectar si está en VR
local function isVR()
	return VRService.VREnabled
end

-- Ease suave
local function easeInOutCubic(t)
	if t < 0.5 then
		return 4 * t * t * t
	else
		local f = (2 * t) - 2
		return 0.5 * f * f * f + 1
	end
end

-- ================================
-- SHAKE NORMAL (NO VR)
-- ================================
local function shakeNormal(duration, intensity)
	if shaking then
		return
	end
	shaking = true

	local startTime = tick()
	local fadeInDuration = math.min(duration * 0.15, 1.5)
	local fadeOutDuration = math.min(duration * 0.20, 2.0)

	if shakeConnection then
		shakeConnection:Disconnect()
	end

	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime

		if elapsed >= duration then
			stopShake()
			return
		end

		local currentIntensity = intensity

		if elapsed < fadeInDuration then
			currentIntensity *= easeInOutCubic(elapsed / fadeInDuration)
		elseif elapsed > (duration - fadeOutDuration) then
			currentIntensity *= easeInOutCubic((duration - elapsed) / fadeOutDuration)
		end

		local time = elapsed * 12

		local wave = math.sin(time * 1.8) + math.cos(time * 2.4) + math.sin(time * 3.1) * 0.5

		local noiseX = wave * (math.random() * 0.3 + 0.85)

		local shakeX = noiseX * currentIntensity * 0.6
		local shakeRotY = math.rad(noiseX * currentIntensity * 0.8)

		if camera.CameraType == Enum.CameraType.Custom then
			camera.CFrame *= CFrame.new(shakeX, 0, 0)
			camera.CFrame *= CFrame.Angles(0, shakeRotY, 0)
		end
	end)
end

-- ================================
-- SHAKE VR (NEXUSVR SAFE)
-- ================================
-- ⚠️ En VR NO se debe modificar Camera.CFrame directamente.
-- Se aplica un offset pequeño para evitar motion sickness.

local function shakeVR(duration, intensity)
	if shaking then
		return
	end
	local humanoid = getHumanoid()
	if not humanoid then
		return
	end

	shaking = true
	local startTime = tick()
	activeHumanoid = humanoid

	if shakeConnection then
		shakeConnection:Disconnect()
	end

	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		local currentHumanoid = getHumanoid()
		if not currentHumanoid then
			stopShake()
			return
		end

		activeHumanoid = currentHumanoid

		if elapsed >= duration then
			stopShake()
			return
		end

		local progress = elapsed / duration
		local currentIntensity = intensity * (1 - progress)

		local time = elapsed * 8

		-- Movimiento MUY sutil para VR
		local offsetX = math.sin(time * 2) * currentIntensity * 0.05
		local offsetZ = math.cos(time * 1.5) * currentIntensity * 0.025

		-- Aplicar offset compatible con frameworks tipo NexusVR
		currentHumanoid.CameraOffset = Vector3.new(offsetX, 0, offsetZ)
	end)
end

-- ================================
-- EVENTO
-- ================================
CameraShakeEvent.OnClientEvent:Connect(function(duration, scale)
	if typeof(duration) ~= "number" or typeof(scale) ~= "number" then
		return
	end
	if duration <= 0 or scale <= 0 then
		return
	end

	local intensity = scale * 0.35

	if isVR() then
		-- Reducimos intensidad en VR para evitar mareo
		shakeVR(duration, intensity * 0.5)
	else
		shakeNormal(duration, intensity)
	end
end)

-- Limpieza
player.CharacterAdded:Connect(function()
	stopShake()
end)
