-- NPCFollowerController
-- Purpose: Centralize explicit activation of NPC pathing scripts.
-- Usage  : NPCFollowerController.activate(npcModel)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Logger = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logger"))

local START_EVENT_NAME = "StartPathing"

local NPCFollowerController = {}

local function getOrCreateStartEvent(npcModel)
	local startEvent = npcModel:FindFirstChild(START_EVENT_NAME)
	if startEvent and startEvent:IsA("BindableEvent") then
		return startEvent
	end

	if startEvent and not startEvent:IsA("BindableEvent") then
		Logger.warn(
			"NPC",
			string.format(
				"%s.%s exists with invalid class %s; replacing with BindableEvent",
				npcModel:GetFullName(),
				START_EVENT_NAME,
				startEvent.ClassName
			)
		)
		startEvent:Destroy()
	end

	startEvent = Instance.new("BindableEvent")
	startEvent.Name = START_EVENT_NAME
	startEvent.Parent = npcModel
	return startEvent
end

function NPCFollowerController.activate(npcModel)
	if typeof(npcModel) ~= "Instance" or not npcModel:IsA("Model") then
		Logger.warn("NPC", "activate() expects a Model instance")
		return false
	end

	local startEvent = getOrCreateStartEvent(npcModel)
	if not startEvent then
		return false
	end

	task.defer(function()
		if npcModel.Parent then
			startEvent:Fire()
		end
	end)

	return true
end

return NPCFollowerController
