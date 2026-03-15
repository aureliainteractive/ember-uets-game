-- NavigationUtils
-- Purpose: Waypoint, refuge, highlight, and teleport utility helpers.
-- Dependencies: Workspace folders and ReplicatedStorage.HighlightTemplate

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local highlightTemplate = ReplicatedStorage:WaitForChild("HighlightTemplate")
local spawnpointsFolder = workspace:WaitForChild("Spawnpoints")
local waypointsFolder = workspace:WaitForChild("Waypoints")
local refugeesFolder = workspace:WaitForChild("Refugees")

local NavigationUtils = {}

-- Teleports a player to a target BasePart with a small vertical offset.
function NavigationUtils.teleportPlayer(player, targetPart)
	if not player or not player.Character then return false end
	local hrp = player.Character:FindFirstChild("HumanoidRootPart")
	if hrp and targetPart then
		hrp.CFrame = targetPart.CFrame + Vector3.new(0, 3, 0)
		return true
	end
	return false
end

-- Teleports a player to a random spawnpoint for simulation type and location.
function NavigationUtils.teleportToSpawn(player, simType, locationName)
	local locationFolder = spawnpointsFolder:FindFirstChild(locationName)
	if not locationFolder then
		warn(string.format("[SimController] Spawnpoints: ubicacion '%s' no encontrada.", locationName))
		return false
	end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then
		warn(string.format("[SimController] Spawnpoints: tipo '%s' no encontrado en '%s'.", simType, locationName))
		return false
	end
	local points = {}
	for _, v in pairs(simFolder:GetChildren()) do
		if v:IsA("BasePart") then table.insert(points, v) end
	end
	if #points == 0 then
		warn(string.format("[SimController] Spawnpoints: sin puntos en '%s/%s'.", locationName, simType))
		return false
	end
	return NavigationUtils.teleportPlayer(player, points[math.random(1, #points)])
end

-- Teleports a player to the closest spawnpoint relative to an origin part.
function NavigationUtils.teleportToClosestSpawn(player, simType, locationName, originPart)
	if not originPart or not originPart:IsA("BasePart") then
		warn("[SimController] Spawn más cercano: origin inválido. Usando spawn aleatorio.")
		return NavigationUtils.teleportToSpawn(player, simType, locationName)
	end
	local locationFolder = spawnpointsFolder:FindFirstChild(locationName)
	if not locationFolder then return false end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then return false end

	local points = {}
	for _, v in pairs(simFolder:GetChildren()) do
		if v:IsA("BasePart") then table.insert(points, v) end
	end
	if #points == 0 then return false end

	local closest = points[1]
	local closestDist = (closest.Position - originPart.Position).Magnitude
	for i = 2, #points do
		local d = (points[i].Position - originPart.Position).Magnitude
		if d < closestDist then
			closestDist = d
			closest = points[i]
		end
	end

	print(string.format("[SimController] Spawn seleccionado a %.1f studs del origen del fuego.", closestDist))
	return NavigationUtils.teleportPlayer(player, closest)
end

-- Returns a numbered waypoint from Waypoints/<location>/<simType>/.
function NavigationUtils.getWaypoint(locationName, simType, number)
	local locationFolder = waypointsFolder:FindFirstChild(locationName)
	if not locationFolder then
		warn(string.format("[SimController] Waypoints: ubicacion '%s' no encontrada.", locationName))
		return nil
	end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then
		warn(string.format("[SimController] Waypoints: tipo '%s' no encontrado en '%s'.", simType, locationName))
		return nil
	end
	local wp = simFolder:FindFirstChild("Waypoint" .. number)
	if not wp or not wp:IsA("BasePart") then
		warn(string.format("[SimController] Waypoints: Waypoint%d no encontrado.", number))
		return nil
	end
	return wp
end

-- Returns all refuge parts from Refugees/<location>/<simType>/.
function NavigationUtils.getRefuges(locationName, simType)
	local locationFolder = refugeesFolder:FindFirstChild(locationName)
	if not locationFolder then
		warn(string.format("[SimController] Refugees: ubicacion '%s' no encontrada.", locationName))
		return {}
	end
	local simFolder = locationFolder:FindFirstChild(simType)
	if not simFolder then
		warn(string.format("[SimController] Refugees: tipo '%s' no encontrado en '%s'.", simType, locationName))
		return {}
	end
	local refuges = {}
	for _, v in pairs(simFolder:GetChildren()) do
		if v:IsA("BasePart") and v.Name:match("Refuge%d+") then
			table.insert(refuges, v)
		end
	end
	return refuges
end

-- Enables or disables highlight on a BasePart.
function NavigationUtils.highlightPart(part, enable)
	if not part or not part:IsA("BasePart") then return end
	if enable then
		if not part:FindFirstChild(highlightTemplate.Name) then
			local clone = highlightTemplate:Clone()
			clone.Parent = part
		end
		part.Transparency = 0
	else
		local existing = part:FindFirstChild(highlightTemplate.Name)
		part.Transparency = 1
		if existing then existing:Destroy() end
	end
end

-- Enables or disables highlight on a refuge list.
function NavigationUtils.highlightRefuges(refuges, enable)
	for _, refuge in pairs(refuges) do
		NavigationUtils.highlightPart(refuge, enable)
	end
end

-- Connects one-shot waypoint touched detection for a player.
function NavigationUtils.setupWaypointDetection(player, waypoint, waypointNumber, onTouch)
	if not waypoint then return end
	local connection
	connection = waypoint.Touched:Connect(function(hit)
		if hit.Parent == player.Character then
			local humanoid = hit.Parent:FindFirstChild("Humanoid")
			if humanoid then
				connection:Disconnect()
				if onTouch then onTouch(waypointNumber) end
			end
		end
	end)
	return connection
end

-- Connects refuge touched detection and resolves once any refuge is reached.
function NavigationUtils.setupRefugeDetection(player, refuges, onRefugeReached)
	if not refuges or #refuges == 0 then return {} end
	local connections = {}
	local reached = false
	for _, refuge in pairs(refuges) do
		local conn
		conn = refuge.Touched:Connect(function(hit)
			if not reached and hit.Parent == player.Character then
				local humanoid = hit.Parent:FindFirstChild("Humanoid")
				if humanoid then
					reached = true
					for _, c in pairs(connections) do c:Disconnect() end
					if onRefugeReached then onRefugeReached(refuge) end
				end
			end
		end)
		table.insert(connections, conn)
	end
	return connections
end

return NavigationUtils
