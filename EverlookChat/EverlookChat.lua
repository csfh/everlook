local Chat = Everlook:NewAddon("EverlookChat", {
	label = "Chat",
	defaults = {
		shortLabels = true,
		timestamps = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookChat", {
	"CHAT_FRAMES",
	"ChatTypeInfo",
	"CHAT_SAY_GET",
	"CHAT_GUILD_GET",
	"CHAT_WHISPER_GET",
	"GetCVar",
	"SetCVar",
	"GetCVarDefault",
	"TIMESTAMP_FORMAT_HHMM",
})

-- Blizzard builds a chat line as format(CHAT_<TYPE>_GET .. message, sender). Replacing those strings
-- sets the prefix without ever reading the message, which can be secret in restricted content.
local LABELS = {
	SAY = "S", YELL = "Y",
	PARTY = "P", PARTY_LEADER = "PL", RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW",
	GUILD = "G", OFFICER = "O", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
	WHISPER = "W", WHISPER_INFORM = "To", BN_WHISPER = "W", BN_WHISPER_INFORM = "To",
	CHANNEL = false, -- the channel's own link is shortened to its number below
}

-- An invisible, empty color span in front of every line we format. Only a line that carries it
-- gets its sender's brackets removed, so system messages keep theirs.
local MARK = "|cff000001|r"
local MARK_PATTERN = MARK:gsub("%p", "%%%0")

local originals = {} -- [global name] = the game's own string, while ours is in place
local wrapped = setmetatable({}, { __mode = "k" }) -- [chat frame] = { own, wrapper }

local function hex(info)
	if type(info) ~= "table" or type(info.r) ~= "number" or type(info.g) ~= "number" or type(info.b) ~= "number" then
		return "ffffff"
	end
	return string.format("%02x%02x%02x", math.floor(info.r * 255 + 0.5), math.floor(info.g * 255 + 0.5),
		math.floor(info.b * 255 + 0.5))
end

local function color(text, info)
	return "|cff" .. hex(info) .. text .. "|r"
end

-- Label, name, message.
local function formatFor(kind, label)
	local prefix = label and (color(label, ChatTypeInfo and ChatTypeInfo[kind]) .. " ") or ""
	return MARK .. prefix .. "%s "
end

local function applyFormats(on)
	for kind, label in pairs(LABELS) do
		local name = "CHAT_" .. kind .. "_GET"
		if on then
			if _G[name] ~= nil then
				if originals[name] == nil then originals[name] = _G[name] end
				_G[name] = formatFor(kind, label)
			end
		elseif originals[name] ~= nil then
			_G[name] = originals[name]
			originals[name] = nil
		end
	end
end

local function stripBrackets(text)
	local replaced = text:gsub("(|Hplayer:[^|]*|h)%[(.-)%](|h)", "%1%2%3", 1)
	if replaced ~= text then return replaced end
	return (text:gsub("(|HBNplayer:[^|]*|h)%[(.-)%](|h)", "%1%2%3", 1))
end

-- "[2. Trade - City] " -> "2 ", in the channel's color.
local function shrinkChannel(text)
	return (text:gsub("|Hchannel:channel:(%d+)|h%[[^%]]*%]|h ", function(number)
		local info = ChatTypeInfo and ChatTypeInfo["CHANNEL" .. number]
		return "|Hchannel:channel:" .. number .. "|h" .. color(number, info) .. "|h "
	end, 1))
end

-- Lines we didn't format, and text the client hides, pass through untouched.
function Chat:FormatLine(text)
	if not self.db.shortLabels or type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then
		return text
	end
	if not text:find(MARK, 1, true) then
		return text
	end
	return stripBrackets(shrinkChannel((text:gsub(MARK_PATTERN, ""))))
end

-- Each chat window's AddMessage is wrapped while short labels are on and given back when they go
-- off: its own field, or none when the method came from its type. A window another addon wrapped
-- since keeps ours inside its own; ours then passes lines through untouched.
local function wrap(frame)
	if type(frame) ~= "table" or wrapped[frame] or type(frame.AddMessage) ~= "function" then return end
	local add = frame.AddMessage
	local held = { own = rawget(frame, "AddMessage") }
	held.wrapper = function(self, text, ...)
		return add(self, Chat:FormatLine(text), ...)
	end
	frame.AddMessage = held.wrapper
	wrapped[frame] = held
end

local function unwrap(frame, held)
	if rawget(frame, "AddMessage") ~= held.wrapper then return end
	frame.AddMessage = held.own
	wrapped[frame] = nil
end

-- Timestamps: the showTimestamps CVar Options, Social sets. Only reset what this session wrote.
local CVAR = "showTimestamps"
local wroteTimestamps = false

local function writeCVar(value)
	local ok, success = pcall(SetCVar, CVAR, value)
	return ok and success ~= false
end

local function applyTimestamps(on)
	if type(GetCVar) ~= "function" or type(SetCVar) ~= "function" then return end
	if on then
		local current = GetCVar(CVAR)
		-- A setting the client doesn't have, or hides, is left alone.
		if type(current) ~= "string" or (issecretvalue and issecretvalue(current)) then return end
		if type(TIMESTAMP_FORMAT_HHMM) == "string" and writeCVar(TIMESTAMP_FORMAT_HHMM) then
			wroteTimestamps = true
		end
	elseif wroteTimestamps then
		local ok, default = pcall(GetCVarDefault, CVAR)
		if ok and type(default) == "string" then writeCVar(default) end
		wroteTimestamps = false
	end
end

function Chat:Apply()
	applyFormats(self.db.shortLabels)
	if self.db.shortLabels then
		for _, name in ipairs(CHAT_FRAMES or {}) do
			wrap(_G[name])
		end
	else
		for frame, held in pairs(wrapped) do
			unwrap(frame, held)
		end
	end
end

function Chat:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Chat & Social")
	page:Checkbox("shortLabels", "Short chat labels",
		"Say, party, guild, whisper and other lines start with a short label (S, P, G, W, To ...), then the name with no brackets. Numbered channels show just their number.")
	page:Checkbox("timestamps", "Chat timestamps",
		"Show the time before each chat line. Turning this off puts the game's own timestamp setting back.")
end

function Chat:OnEnable()
	self:Apply()
	if self.db.timestamps then applyTimestamps(true) end
	-- New chat windows and color changes: format again.
	self:RegisterEvent("UPDATE_CHAT_COLOR", "Apply")
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", "Apply")
	self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "Apply")
end

function Chat:OnSettingChanged(key, value)
	if key == "shortLabels" then
		self:Apply()
	elseif key == "timestamps" then
		applyTimestamps(value)
	end
end
