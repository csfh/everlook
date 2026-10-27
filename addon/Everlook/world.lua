local addonName, Everlook = ...

-- Module addons are separate addons, and a global is the only table they can
-- share with this one. Everlook.module and Everlook.island are the supported
-- interface for other addons.
_G.Everlook = Everlook

Everlook.world = {}

function Everlook.world.usable(value)
	if issecretvalue and issecretvalue(value) then
		return false
	end
	return true
end

-- A value the client hides cannot be compared or put into text. `secret` says
-- whether a value is hidden, `public` gives the value back or nil when it is.
function Everlook.secret(value)
	return not Everlook.world.usable(value)
end

function Everlook.public(value)
	if Everlook.world.usable(value) then
		return value
	end
end

-- Whether a value is there and can be read: not nil and not hidden. The hidden
-- check comes first, so a hidden value is never compared.
function Everlook.readable(value)
	return Everlook.world.usable(value) and value ~= nil
end

-- Whether a value is a number that can be compared and shown: public, and
-- neither NaN nor infinite.
function Everlook.finite(value)
	return Everlook.world.usable(value) and type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function Everlook.say(text)
	if type(text) ~= "string" or text == "" then
		return
	end
	local frame = DEFAULT_CHAT_FRAME
	if type(frame) ~= "table" or type(frame.AddMessage) ~= "function" then
		return
	end
	frame:AddMessage("Everlook: " .. text)
end

-- The entry id in a unit guid. The id is the fifth hyphen-separated field
-- after the kind prefix, which is how this client writes Creature and Vehicle.
local function guid_id(guid, kind)
	if not Everlook.world.usable(guid) or type(guid) ~= "string" or type(kind) ~= "string" then
		return nil
	end
	local length = #kind
	if #guid <= length or guid:byte(length + 1) ~= 45 then
		return nil
	end
	for index = 1, length do
		if guid:byte(index) ~= kind:byte(index) then
			return nil
		end
	end
	local hyphens = 1
	local start
	local guid_length = #guid
	for index = length + 2, guid_length do
		local byte = guid:byte(index)
		if byte == 45 then
			hyphens = hyphens + 1
			if hyphens == 5 then
				start = index + 1
				break
			end
		end
	end
	if not start or start > guid_length then
		return nil
	end
	local id = 0
	local digits = 0
	for index = start, guid_length do
		local byte = guid:byte(index)
		if byte == 45 then
			break
		end
		if byte < 48 or byte > 57 then
			return nil
		end
		id = id * 10 + (byte - 48)
		digits = digits + 1
	end
	if digits == 0 then
		return nil
	end
	return id
end

Everlook.npcs = {}

local guid_ids = {}

function Everlook.npcs.creature_id(guid)
	if not Everlook.world.usable(guid) or type(guid) ~= "string" then
		return nil
	end
	local cached = guid_ids[guid]
	if cached == false then
		return nil
	end
	if cached ~= nil then
		return cached
	end
	local id = guid_id(guid, "Creature") or guid_id(guid, "Vehicle")
	guid_ids[guid] = id or false
	return id
end

Everlook.items = {}

-- Loot and merchants repeat the same link shape. The id is read in place
-- so the capture is not allocated.
function Everlook.items.id_from_link(link)
	if not Everlook.world.usable(link) or type(link) ~= "string" then
		return nil
	end
	local start = link:find("item:", 1, true)
	if not start then
		return nil
	end
	start = start + 5
	local id = 0
	local digits = 0
	for index = start, #link do
		local byte = link:byte(index)
		if byte < 48 or byte > 57 then
			break
		end
		id = id * 10 + (byte - 48)
		digits = digits + 1
	end
	if digits == 0 then
		return nil
	end
	return id
end
