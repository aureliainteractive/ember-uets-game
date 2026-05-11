-- CacheManager
-- Purpose: Efficient O(1) light and part tracking with batch cleanup operations.
-- Location: ReplicatedStorage.Shared.Modules.CacheManager
--
-- Replaces manual table iteration with Set-based tracking for better performance.
-- Supports incremental updates via DescendantAdded/Removed events.
--
-- Usage:
--   local manager = CacheManager.new(workspace, {
--     lightClasses = { "PointLight", "SurfaceLight", "SpotLight" },
--     neonFilter = function(inst) return inst.Material == Enum.Material.Neon end,
--     glassFilter = function(inst) return inst.Material == Enum.Material.Glass end,
--   })
--   manager:addLight(lightInstance)
--   manager:removeLight(lightInstance)
--   local lights = manager:getLights()  -- returns array
--   manager:cleanup()  -- disconnect events
--
-- Event System:
--   manager.LightAdded:Connect(function(light) ... end)
--   manager.LightRemoved:Connect(function(light) ... end)
--   manager.NeonAdded:Connect(function(part) ... end)
--   etc.

local CacheManager = {}
CacheManager.__index = CacheManager

local BindableEvent = Instance.new("BindableEvent")

-- Private: Convert set table to array
local function setToArray(set)
	local arr = {}
	for inst, _ in pairs(set) do
		table.insert(arr, inst)
	end
	return arr
end

-- Constructor
function CacheManager.new(workspace, options)
	options = options or {}
	
	local self = setmetatable({
		workspace = workspace,
		
		-- Set-based caches (O(1) lookup)
		lights = {},        -- { [light] = true }
		neonParts = {},     -- { [part] = true }
		glassParts = {},    -- { [part] = true }
		
		-- Filters for classification
		lightClasses = options.lightClasses or { "PointLight", "SurfaceLight", "SpotLight" },
		neonFilter = options.neonFilter or function(inst)
			return inst:IsA("BasePart") and inst.Material == Enum.Material.Neon
		end,
		glassFilter = options.glassFilter or function(inst)
			return inst:IsA("BasePart") and inst.Material == Enum.Material.Glass
		end,
		
		-- Events
		LightAdded = Instance.new("BindableEvent"),
		LightRemoved = Instance.new("BindableEvent"),
		NeonAdded = Instance.new("BindableEvent"),
		NeonRemoved = Instance.new("BindableEvent"),
		GlassAdded = Instance.new("BindableEvent"),
		GlassRemoved = Instance.new("BindableEvent"),
		
		-- Connections (for cleanup)
		connections = {},
		
		-- Mark-and-sweep state
		markedForRemoval = {},
	}, self)
	
	-- Connect to workspace events
	self:_connectEvents()
	
	return self
end

-- Private: Connect to workspace descendant events
function CacheManager:_connectEvents()
	local function onDescendantAdded(descendant)
		self:_classifyAndAdd(descendant)
	end
	
	local function onDescendantRemoved(descendant)
		self:_removeFromCaches(descendant)
	end
	
	local addedConn = self.workspace.DescendantAdded:Connect(onDescendantAdded)
	local removedConn = self.workspace.DescendantRemoved:Connect(onDescendantRemoved)
	
	table.insert(self.connections, addedConn)
	table.insert(self.connections, removedConn)
end

-- Private: Classify and add instance to appropriate cache
function CacheManager:_classifyAndAdd(inst)
	if not inst or not inst.Parent then
		return
	end
	
	-- Check light classes
	for _, className in ipairs(self.lightClasses) do
		if inst:IsA(className) then
			self.lights[inst] = true
			self.LightAdded:Fire(inst)
			return
		end
	end
	
	-- Check neon filter
	if self.neonFilter(inst) then
		self.neonParts[inst] = true
		self.NeonAdded:Fire(inst)
		return
	end
	
	-- Check glass filter
	if self.glassFilter(inst) then
		self.glassParts[inst] = true
		self.GlassAdded:Fire(inst)
		return
	end
end

-- Private: Remove instance from all caches
function CacheManager:_removeFromCaches(inst)
	if self.lights[inst] then
		self.lights[inst] = nil
		self.LightRemoved:Fire(inst)
	end
	
	if self.neonParts[inst] then
		self.neonParts[inst] = nil
		self.NeonRemoved:Fire(inst)
	end
	
	if self.glassParts[inst] then
		self.glassParts[inst] = nil
		self.GlassRemoved:Fire(inst)
	end
end

-- Public: Manually add a light instance
function CacheManager:addLight(light)
	if light and not self.lights[light] then
		self.lights[light] = true
		self.LightAdded:Fire(light)
	end
end

-- Public: Manually remove a light instance
function CacheManager:removeLight(light)
	if light and self.lights[light] then
		self.lights[light] = nil
		self.LightRemoved:Fire(light)
	end
end

-- Public: Manually add a neon part
function CacheManager:addNeonPart(part)
	if part and not self.neonParts[part] then
		self.neonParts[part] = true
		self.NeonAdded:Fire(part)
	end
end

-- Public: Manually remove a neon part
function CacheManager:removeNeonPart(part)
	if part and self.neonParts[part] then
		self.neonParts[part] = nil
		self.NeonRemoved:Fire(part)
	end
end

-- Public: Manually add a glass part
function CacheManager:addGlassPart(part)
	if part and not self.glassParts[part] then
		self.glassParts[part] = true
		self.GlassAdded:Fire(part)
	end
end

-- Public: Manually remove a glass part
function CacheManager:removeGlassPart(part)
	if part and self.glassParts[part] then
		self.glassParts[part] = nil
		self.GlassRemoved:Fire(part)
	end
end

-- Public: Get all lights as array
function CacheManager:getLights()
	return setToArray(self.lights)
end

-- Public: Get all neon parts as array
function CacheManager:getNeonParts()
	return setToArray(self.neonParts)
end

-- Public: Get all glass parts as array
function CacheManager:getGlassParts()
	return setToArray(self.glassParts)
end

-- Public: Mark an instance for removal (used in mark-and-sweep pattern)
function CacheManager:markForRemoval(inst)
	if inst then
		self.markedForRemoval[inst] = true
	end
end

-- Public: Clear all marked instances and return count
function CacheManager:sweepMarked()
	local count = 0
	for inst, _ in pairs(self.markedForRemoval) do
		if inst and not inst.Parent then
			self:_removeFromCaches(inst)
			count += 1
		end
	end
	self.markedForRemoval = {}
	return count
end

-- Public: Initialize cache by scanning existing descendants
-- Called once at startup to populate initial state
function CacheManager:initialize()
	local descendants = self.workspace:GetDescendants()
	for i, inst in ipairs(descendants) do
		-- Yield every 2000 items to prevent frame lag
		if i % 2000 == 0 then
			task.wait()
		end
		self:_classifyAndAdd(inst)
	end
end

-- Public: Disconnect all events and cleanup
function CacheManager:cleanup()
	for _, conn in ipairs(self.connections) do
		conn:Disconnect()
	end
	self.connections = {}
	
	self.LightAdded:Destroy()
	self.LightRemoved:Destroy()
	self.NeonAdded:Destroy()
	self.NeonRemoved:Destroy()
	self.GlassAdded:Destroy()
	self.GlassRemoved:Destroy()
	
	self.lights = {}
	self.neonParts = {}
	self.glassParts = {}
	self.markedForRemoval = {}
end

-- Public: Validate all cached instances still exist (for debugging)
function CacheManager:validateCaches()
	local lightCount = 0
	local neonCount = 0
	local glassCount = 0
	
	for light, _ in pairs(self.lights) do
		if light and light.Parent then
			lightCount += 1
		else
			self.lights[light] = nil
		end
	end
	
	for part, _ in pairs(self.neonParts) do
		if part and part.Parent then
			neonCount += 1
		else
			self.neonParts[part] = nil
		end
	end
	
	for part, _ in pairs(self.glassParts) do
		if part and part.Parent then
			glassCount += 1
		else
			self.glassParts[part] = nil
		end
	end
	
	return {
		lights = lightCount,
		neonParts = neonCount,
		glassParts = glassCount,
	}
end

return CacheManager
