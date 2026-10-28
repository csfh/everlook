-- The helpers every addon finds already loaded in the game, written in Lua 5.1 as the game has them.
-- Nothing here knows about a particular addon.

strlen, strsub, strfind, strlower, strupper, strrep, strbyte, strchar = string.len, string.sub, string.find, string.lower, string.upper, string.rep, string.byte, string.char
strmatch, strgmatch, strgsub, strreverse = string.match, string.gmatch, string.gsub, string.reverse
format = string.format
gsub = string.gsub
tinsert, tremove, sort, concat = table.insert, table.remove, table.sort, table.concat
floor, ceil, abs, sqrt, sin, cos, tan, min, max, random = math.floor, math.ceil, math.abs, math.sqrt, math.sin, math.cos, math.tan, math.min, math.max, math.random
mod = math.fmod
fmod = math.fmod
Round = function(value) return floor(value + 0.5) end

function strtrim(text, characters)
	characters = characters or "%s"
	return (text:gsub("^[" .. characters .. "]+", ""):gsub("[" .. characters .. "]+$", ""))
end

function strsplit(delimiter, text, pieces)
	local out, start = {}, 1
	while true do
		if pieces and #out == pieces - 1 then break end
		local first, last = text:find(delimiter, start, true)
		if not first then break end
		out[#out + 1] = text:sub(start, first - 1)
		start = last + 1
	end
	out[#out + 1] = text:sub(start)
	return unpack(out)
end

function strjoin(delimiter, ...)
	local parts = {}
	for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
	return table.concat(parts, delimiter)
end

function wipe(target)
	for key in pairs(target) do target[key] = nil end
	return target
end

function tContains(list, value)
	for _, found in ipairs(list) do if found == value then return true end end
	return false
end

function Mixin(target, ...)
	for index = 1, select("#", ...) do
		for key, value in pairs((select(index, ...))) do target[key] = value end
	end
	return target
end

function CreateFromMixins(...)
	return Mixin({}, ...)
end

function hooksecurefunc(target, name, hook)
	if type(target) == "string" then target, name, hook = _G, target, name end
	local original = target[name]
	target[name] = function(...)
		local results = { original(...) }
		hook(...)
		return unpack(results)
	end
end

function securecall(callback, ...)
	if type(callback) == "string" then callback = _G[callback] end
	return callback(...)
end

function issecretvalue() return false end
function canaccessvalue() return true end
function issecrettable() return false end

local handler = function(message) error(message, 0) end
function geterrorhandler() return handler end
function seterrorhandler(next_handler) handler = next_handler end

-- Stand-ins for the few Blizzard UI Lua helpers the addons use. The real ones live in wow-ui-source and
-- pull in half the interface; these keep only what the addons call.
EventUtil = {}
do
	local waiting, loaded, logged_in, login_waiting = {}, {}, false, {}
	function EventUtil.ContinueOnAddOnLoaded(name, callback)
		if loaded[name] then callback() return end
		waiting[name] = waiting[name] or {}
		waiting[name][#waiting[name] + 1] = callback
	end
	function EventUtil.ContinueOnPlayerLogin(callback)
		if logged_in then callback() else login_waiting[#login_waiting + 1] = callback end
	end
	function EventUtil.__addon_loaded(name)
		loaded[name] = true
		for _, callback in ipairs(waiting[name] or {}) do callback() end
		waiting[name] = nil
	end
	function EventUtil.__login()
		logged_in = true
		for _, callback in ipairs(login_waiting) do callback() end
		login_waiting = {}
	end
end

function CreateColor(r, g, b, a)
	local color = { r = r, g = g, b = b, a = a }
	function color:GetRGB() return self.r, self.g, self.b end
	function color:GetRGBA() return self.r, self.g, self.b, self.a end
	return color
end
