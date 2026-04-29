local UIManager = {}

local cache = {}

function UIManager.get(playerGui, name, timeout)
	timeout = timeout or 10

	-- cache first
	if cache[playerGui] and cache[playerGui][name] then
		return cache[playerGui][name]
	end

	local start = os.clock()
	local ui

	repeat
		ui = playerGui:FindFirstChild(name)

		if not ui then
			playerGui.ChildAdded:Wait()
		end

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