local UIManager = {}

local cache = {}

function UIManager.get(playerGui, name, timeout)
	timeout = timeout or 10
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
	local ui

	-- Poll for child with a timeout instead of blocking indefinitely
	repeat
		ui = playerGui:FindFirstChild(name)
		if ui then break end
		task.wait(0.08)
	until ui or (os.clock() - start) > timeout

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