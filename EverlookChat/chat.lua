local Chat = Everlook:NewAddon("EverlookChat", {
	label = "Chat",
	defaults = {
		shortLabels = true,
		timestamps = false,
		font = "game",
		outline = "game",
		shadow = "game",
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
	"ChatFontNormal",
	"FCF_OpenTemporaryWindow",
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

-- The chat windows' font: an Everlook token's file, an outline and a shadow, each its own dropdown
-- that starts on the game's. The size stays the tab's own (Font Size in its menu), which keeps the
-- file and outline it finds (FCF_SetChatWindowFontSize, FloatingChatFrame.lua, 12.0.0). Each part
-- is set only while chosen, and choosing the game's again puts back the game's own: ChatFontNormal,
-- inherited by every chat window (Fonts.xml), and the core's copy of its file. A window opened later
-- (FCF_OpenTemporaryWindow) gets the choice too.
--
-- The game's chat text has no outline and a black shadow one pixel down and right
-- (NumberFont_Shadow_Med, Fonts.xml), so neither menu repeats those.
Chat.OUTLINES = { outline = "OUTLINE", thick = "THICKOUTLINE" }
Chat.SHADOWS = { none = { 0, 0 }, soft = { 1, 0.5 }, strong = { 2, 1 } } -- offset, alpha
local EVERLOOK_FONTS = "Interface\\AddOns\\EverlookFonts\\"
local styled = setmetatable({}, { __mode = "k" }) -- [chat frame] = { font, outline, shadow } this session set

local function chatWindows()
	local list = {}
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local frame = _G[name]
		if type(frame) == "table" and type(frame.GetFont) == "function" and type(frame.SetFont) == "function"
			and not (frame.IsForbidden and frame:IsForbidden()) then
			list[#list + 1] = frame
		end
	end
	return list
end

local function gameFlags()
	local _, _, flags = ChatFontNormal and ChatFontNormal:GetFont()
	return flags or ""
end

local function styleWindow(frame, db)
	local set = styled[frame] or {}
	styled[frame] = set
	local path, size, flags = frame:GetFont()
	if not path or not size then return end
	local file, wantedFlags = path, flags
	local token = Everlook.Font[db.font]
	if token then
		file = token:GetFont() or path
		set.font = true
	elseif set.font or path:find(EVERLOOK_FONTS, 1, true) == 1 then
		-- A window opened while Fonts gave ChatFontNormal one of its files copied that file; on the
		-- game's font it goes back to the game's too.
		file = Everlook.FontTokenGameFile("Chat") or path
		set.font = nil
	end
	if Chat.OUTLINES[db.outline] then
		wantedFlags = Chat.OUTLINES[db.outline]
		set.outline = true
	elseif set.outline then
		wantedFlags = gameFlags()
		set.outline = nil
	end
	if file ~= path or wantedFlags ~= flags then frame:SetFont(file, size, wantedFlags) end
	if type(frame.SetShadowOffset) ~= "function" then return end
	local shadow = Chat.SHADOWS[db.shadow]
	if shadow then
		frame:SetShadowOffset(shadow[1], -shadow[1])
		frame:SetShadowColor(0, 0, 0, shadow[2])
		set.shadow = true
	elseif set.shadow then
		local x, y = 1, -1
		local r, g, b, a = 0, 0, 0, 1
		if ChatFontNormal and ChatFontNormal.GetShadowOffset then
			x, y = ChatFontNormal:GetShadowOffset()
			r, g, b, a = ChatFontNormal:GetShadowColor()
		end
		frame:SetShadowOffset(x, y)
		frame:SetShadowColor(r, g, b, a)
		set.shadow = nil
	end
end

function Chat:ApplyFont()
	for _, frame in ipairs(chatWindows()) do styleWindow(frame, self.db) end
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
	self:ApplyFont()
end

function Chat:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Chat & Social")
	page:Checkbox("shortLabels", "Short chat labels",
		"Say, party, guild, whisper and other lines start with a short label (S, P, G, W, To ...), then the name with no brackets. Numbered channels show just their number.")
	page:Checkbox("timestamps", "Chat timestamps",
		"Show the time before each chat line. Turning this off puts the game's own timestamp setting back.")
	local fonts = { { "game", "Game's font" } }
	for _, token in ipairs(Everlook.FONT_TOKENS) do fonts[#fonts + 1] = { token, token .. " token" } end
	page:Dropdown("font", "Chat font",
		"The font of the chat windows' text: the font Fonts gives one of Everlook's tokens. The size stays the one on each tab's Font Size menu.",
		fonts)
	page:Dropdown("outline", "Chat outline", "An outline around the chat windows' text.",
		{ { "game", "None, the game's" }, { "outline", "Outline" }, { "thick", "Thick outline" } })
	page:Dropdown("shadow", "Chat shadow", "A shadow behind the chat windows' text.",
		{ { "game", "The game's" }, { "none", "None" }, { "soft", "Soft" }, { "strong", "Strong" } })
end

function Chat:OnEnable()
	self:Apply()
	if self.db.timestamps then applyTimestamps(true) end
	-- New chat windows and color changes: format again.
	self:RegisterEvent("UPDATE_CHAT_COLOR", "Apply")
	self:RegisterEvent("UPDATE_CHAT_WINDOWS", "Apply")
	self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "Apply")
	-- Whisper windows open later, and a token's font can change after ours was set.
	if type(FCF_OpenTemporaryWindow) == "function" then
		hooksecurefunc("FCF_OpenTemporaryWindow", function() self:ApplyFont() end)
	end
	hooksecurefunc(Everlook, "SetFontToken", function() self:ApplyFont() end)
end

function Chat:OnSettingChanged(key, value)
	if key == "shortLabels" then
		self:Apply()
	elseif key == "timestamps" then
		applyTimestamps(value)
	elseif key == "font" or key == "outline" or key == "shadow" then
		self:ApplyFont()
	end
end
