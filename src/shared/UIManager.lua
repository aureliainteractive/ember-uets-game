local UIManager = {}

local cache = {}

function UIManager.get(playerGui, name, timeout)
	-- If caller didn't specify timeout, use longer wait for PlayerGui replication
	if not timeout then
		if playerGui and playerGui:IsA("PlayerGui") then
			timeout = 30
		else
			timeout = 10
		end
	end
	-- defensive: check parent
	if not playerGui then
		warn("[UIManager] get() called with nil parent for UI: " .. tostring(name))
		return nil
	end

	-- cache first
	if cache[playerGui] and cache[playerGui][name] then
		return cache[playerGui][name]
	end

	local start = os.clock()
	local ui = playerGui:FindFirstChild(name)

	-- If not found yet, listen for ChildAdded for a quicker response to replication
	local conn
	if not ui then
		local signaled = false
		conn = playerGui.ChildAdded:Connect(function(child)
			if child.Name == name then
				ui = child
				signaled = true
				conn:Disconnect()
			end
		end)

		while not ui and (os.clock() - start) <= timeout do
			if signaled then break end
			task.wait(0.04)
		end

		if conn and conn.Connected then
			conn:Disconnect()
		end
	end

	if not ui then
		-- Try fallback: clone from ReplicatedStorage if a template exists there
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local template = ReplicatedStorage:FindFirstChild(name)
		if template and template:IsA("ScreenGui") then
			local ok, inst = pcall(function()
				local clone = template:Clone()
				clone.Parent = playerGui
				return clone
			end)
			if ok and inst then
				ui = inst
			end
		end

		if not ui then
			warn("[UIManager] Missing UI: " .. name)
			return nil
		end
	end

	cache[playerGui] = cache[playerGui] or {}
	cache[playerGui][name] = ui

	return ui
end

function UIManager.clear(playerGui)
	cache[playerGui] = nil
end

return UIManager