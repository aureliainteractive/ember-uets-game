local UIManager = {}

local cache = {}

function UIManager.get(playerGui, name, timeout)
	timeout = timeout or 10

	-- cache first
	if cache[playerGui] and cache[playerGui][name] then
		local cached = cache[playerGui][name]
		if cached and cached.Parent and cached:IsDescendantOf(playerGui) then
			return cached
		end
		cache[playerGui][name] = nil
	end

	local start = os.clock()
	local ui

	-- Try first without waiting
	ui = playerGui:FindFirstChild(name)
	if ui then
		cache[playerGui] = cache[playerGui] or {}
		cache[playerGui][name] = ui
		return ui
	end

	-- If not found, wait for ChildAdded with proper timeout
	local connection
	local foundUI = false
	connection = playerGui.ChildAdded:Connect(function(child)
		if child.Name == name and not foundUI then
			ui = child
			foundUI = true
			connection:Disconnect()
		end
	end)

	-- Wait for either the UI to be found or timeout
	while not foundUI and (os.clock() - start) < timeout do
		task.wait(0.1)
	end

	connection:Disconnect()

	if not ui then
		warn("[UIManager] Missing UI: " .. name)
		return nil
	end

	cache[playerGui] = cache[playerGui] or {}
	cache[playerGui][name] = ui

	return ui
end

function UIManager.clear(playerGui)
	cache[playerGui] = nil
end

return UIManager