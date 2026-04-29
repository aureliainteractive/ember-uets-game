local Logger = {}

local SCOPE_EMOJIS = {
	NPC = "🚶",
	Door = "🚪",
	System = "⚙️",
	Network = "🌐",
	Animation = "🎬",
	UI = "🖥️",
}

local LEVEL_LABELS = {
	INFO = "INFO",
	WARN = "WARN",
	ERROR = "ERROR",
	DEBUG = "DEBUG",
}

local function normalizeScope(scope)
	local text = tostring(scope or "System")
	local emoji = SCOPE_EMOJIS[text] or SCOPE_EMOJIS.System
	return emoji, text
end

local function formatMessage(level, scope, message)
	local levelLabel = LEVEL_LABELS[level] or LEVEL_LABELS.INFO
	local emoji, scopeName = normalizeScope(scope)
	local text = tostring(message or "")
	return string.format("[%s %s] %s - %s", emoji, scopeName, levelLabel, text)
end

local function emit(level, scope, message)
	local formatted = formatMessage(level, scope, message)
	if level == "WARN" then
		warn(formatted)
		return
	end
	if level == "ERROR" then
		warn(formatted)
		return
	end
	print(formatted)
end

function Logger.info(scope, message)
	emit("INFO", scope, message)
end

function Logger.warn(scope, message)
	emit("WARN", scope, message)
end

function Logger.error(scope, message)
	emit("ERROR", scope, message)
end

function Logger.debug(scope, message)
	emit("DEBUG", scope, message)
end

return Logger
