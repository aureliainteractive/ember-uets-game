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

local DEFAULT_OPTIONS = {
	includeOrigin = true,
	includeStackForWarnError = false,
	stackDepth = 3,
}

local options = {
	includeOrigin = DEFAULT_OPTIONS.includeOrigin,
	includeStackForWarnError = DEFAULT_OPTIONS.includeStackForWarnError,
	stackDepth = DEFAULT_OPTIONS.stackDepth,
}

local MAX_CALLSITE_SCAN = 20

local function normalizePath(source)
	local text = tostring(source or "")
	text = text:gsub("^@", "")
	text = text:gsub("\\", "/")
	local file = text:match("([^/]+)$")
	if file and file ~= "" then
		return file
	end
	if text ~= "" then
		return text
	end
	return "unknown"
end

local function isLoggerSource(source)
	local text = tostring(source or ""):gsub("\\", "/")
	return text:find("/Logger.lua", 1, true) ~= nil or text:find("Logger.lua", 1, true) ~= nil
end

local function safeDebugInfo(level, spec)
	local ok, a, b, c = pcall(function()
		return debug.info(level, spec)
	end)
	if not ok then
		return nil
	end
	return a, b, c
end

local function getCallerInfo()
	for level = 4, MAX_CALLSITE_SCAN do
		local source, line, name = safeDebugInfo(level, "sln")
		if type(source) == "string" and source ~= "" and not isLoggerSource(source) then
			return {
				file = normalizePath(source),
				line = tonumber(line) or 0,
				name = (type(name) == "string" and name ~= "") and name or "anonymous",
			}
		end
	end

	return nil
end

local function formatCaller(caller)
	if not caller then
		return nil
	end
	return string.format("%s:%d %s", caller.file, caller.line, caller.name)
end

local function buildStack(maxDepth)
	local lines = {}
	local depth = math.max(1, tonumber(maxDepth) or 1)

	for level = 4, MAX_CALLSITE_SCAN do
		if #lines >= depth then
			break
		end

		local source, line, name = safeDebugInfo(level, "sln")
		if type(source) == "string" and source ~= "" and not isLoggerSource(source) then
			local file = normalizePath(source)
			local fn = (type(name) == "string" and name ~= "") and name or "anonymous"
			table.insert(lines, string.format("%s:%d %s", file, tonumber(line) or 0, fn))
		end
	end

	if #lines == 0 then
		return nil
	end

	return table.concat(lines, " <- ")
end

local function normalizeScope(scope)
	local text = tostring(scope or "System")
	local emoji = SCOPE_EMOJIS[text] or SCOPE_EMOJIS.System
	return emoji, text
end

local function coerceMessage(message)
	if type(message) == "table" then
		local text = message.message or message.text or ""
		return tostring(text), message
	end
	return tostring(message or ""), nil
end

local function formatMessage(level, scope, message)
	local levelLabel = LEVEL_LABELS[level] or LEVEL_LABELS.INFO
	local emoji, scopeName = normalizeScope(scope)
	local text, messageTable = coerceMessage(message)
	local includeOrigin = options.includeOrigin
	if messageTable and type(messageTable.includeOrigin) == "boolean" then
		includeOrigin = messageTable.includeOrigin
	end

	local caller = includeOrigin and getCallerInfo() or nil
	local callerText = formatCaller(caller)

	local prefix
	if callerText then
		prefix = string.format("[%s %s] %s @ %s", emoji, scopeName, levelLabel, callerText)
	else
		prefix = string.format("[%s %s] %s", emoji, scopeName, levelLabel)
	end

	local includeStack = (level == "WARN" or level == "ERROR") and options.includeStackForWarnError
	if messageTable and type(messageTable.stack) == "boolean" then
		includeStack = messageTable.stack
	end

	if includeStack then
		local stackDepth = options.stackDepth
		if messageTable and messageTable.stackDepth ~= nil then
			stackDepth = messageTable.stackDepth
		end
		local stackText = buildStack(stackDepth)
		if stackText then
			return string.format("%s - %s | stack=%s", prefix, text, stackText)
		end
	end

	return string.format("%s - %s", prefix, text)
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

function Logger.configure(newOptions)
	if type(newOptions) ~= "table" then
		return
	end

	if type(newOptions.includeOrigin) == "boolean" then
		options.includeOrigin = newOptions.includeOrigin
	end
	if type(newOptions.includeStackForWarnError) == "boolean" then
		options.includeStackForWarnError = newOptions.includeStackForWarnError
	end
	if type(newOptions.stackDepth) == "number" then
		options.stackDepth = math.clamp(math.floor(newOptions.stackDepth), 1, 10)
	end
end

function Logger.resetConfig()
	options.includeOrigin = DEFAULT_OPTIONS.includeOrigin
	options.includeStackForWarnError = DEFAULT_OPTIONS.includeStackForWarnError
	options.stackDepth = DEFAULT_OPTIONS.stackDepth
end

return Logger
