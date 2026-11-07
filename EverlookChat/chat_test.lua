local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookChat")

-- The game's own strings, and a chat window that records what it is given.
CHAT_SAY_GET = "%s says: "
CHAT_GUILD_GET = "|Hchannel:GUILD|h[Guild]|h %s: "
CHAT_WHISPER_GET = "%s whispers: "
CHAT_CHANNEL_GET = "%s: "
local GAME = { CHAT_SAY_GET = CHAT_SAY_GET, CHAT_GUILD_GET = CHAT_GUILD_GET, CHAT_WHISPER_GET = CHAT_WHISPER_GET }
ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 }, CHANNEL2 = { r = 1, g = 0.75, b = 0.75 } }

-- The game's chat font, which every chat window inherits: Arial, outlined by nothing, shadowed.
local ARIAL = "Fonts\\ARIALN.TTF"
local function fontInstance(object, path, size, flags)
	object.path, object.size, object.flags, object.sets = path, size, flags, 0
	object.shadow, object.shadowColor = { 1, -1 }, { 0, 0, 0, 1 }
	function object:GetFont() return self.path, self.size, self.flags end
	function object:SetFont(p, s, f) self.path, self.size, self.flags, self.sets = p, s, f, self.sets + 1 end
	function object:GetShadowOffset() return self.shadow[1], self.shadow[2] end
	function object:SetShadowOffset(x, y) self.shadow = { x, y } end
	function object:GetShadowColor() return unpack(self.shadowColor) end
	function object:SetShadowColor(r, g, b, a) self.shadowColor = { r, g, b, a } end
	return object
end
ChatFontNormal = fontInstance({}, ARIAL, 14, "")

local hooks = {}
hooksecurefunc = function(target, name, fn)
	if type(target) == "string" then target, name, fn = _G, target, name end
	local original = target[name]
	target[name] = function(...)
		local results = { original(...) }
		fn(...)
		return unpack(results)
	end
	hooks[name] = true
end
FCF_OpenTemporaryWindow = function() end

local shown = {}
local ChatFrameType = { AddMessage = function(_, text) shown[#shown + 1] = text end }
ChatFrame1 = fontInstance(setmetatable({}, { __index = ChatFrameType }), ARIAL, 16, "")
CHAT_FRAMES = { "ChatFrame1" }

local cvars = { showTimestamps = "none" }
local defaults = { showTimestamps = "none" }
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) cvars[name] = value return true end
GetCVarDefault = function(name) return defaults[name] end
TIMESTAMP_FORMAT_HHMM = "%I:%M "

t.load("EverlookChat")
t.fire("PLAYER_LOGIN")
local Chat = Everlook:GetAddon("EverlookChat")

check(Chat.db.shortLabels == true and Chat.db.timestamps == false, "short labels start on, timestamps off")

-- What the game builds: format(CHAT_<TYPE>_GET .. message, sender).
local player = "|Hplayer:Thrall|h[Thrall]|h"
local function say(getter, message)
	ChatFrame1:AddMessage(string.format(_G[getter] .. message, player))
	return shown[#shown]
end

check(say("CHAT_SAY_GET", "hello") == "|cffffffffS|r |Hplayer:Thrall|hThrall|h hello",
	"say: S label, name without brackets, then the message")
check(say("CHAT_GUILD_GET", "hi") == "|cff40ff40G|r |Hplayer:Thrall|hThrall|h hi",
	"guild: G label in the guild color")
check(say("CHAT_WHISPER_GET", "psst"):find("^|cffffffffW|r ") ~= nil, "whisper: W label")

ChatFrame1:AddMessage("|Hchannel:channel:2|h[2. Trade - City]|h " .. string.format(CHAT_CHANNEL_GET .. "wts", player))
check(shown[#shown] == "|Hchannel:channel:2|h|cffffbfbf2|r|h |Hplayer:Thrall|hThrall|h wts",
	"numbered channel: just its number, name without brackets")

ChatFrame1:AddMessage("You have learned [Fireball].")
check(shown[#shown] == "You have learned [Fireball].", "a system line we didn't format keeps its brackets")

issecretvalue = function(value) return value == "secret" end
ChatFrame1:AddMessage("secret")
check(shown[#shown] == "secret", "text the client hides passes through untouched")
issecretvalue = nil

-- Turning it off puts the game's own strings and AddMessage back.
t.change("EverlookChat_shortLabels", false)
check(CHAT_SAY_GET == GAME.CHAT_SAY_GET and CHAT_GUILD_GET == GAME.CHAT_GUILD_GET
	and CHAT_WHISPER_GET == GAME.CHAT_WHISPER_GET, "off: the game's own chat formats are back")
check(rawget(ChatFrame1, "AddMessage") == nil, "off: the chat window's own AddMessage is back")
check(CHAT_RAID_GET == nil, "a format the client doesn't have is never created")

t.change("EverlookChat_shortLabels", true)
check(CHAT_SAY_GET ~= GAME.CHAT_SAY_GET and rawget(ChatFrame1, "AddMessage") ~= nil, "on again: formats again")

-- Timestamps.
t.change("EverlookChat_timestamps", true)
check(cvars.showTimestamps == TIMESTAMP_FORMAT_HHMM, "timestamps on: sets the game's timestamp format")
t.change("EverlookChat_timestamps", false)
check(cvars.showTimestamps == "none", "timestamps off: the game's default is back")

cvars.showTimestamps = "%H:%M "
t.change("EverlookChat_timestamps", false)
check(cvars.showTimestamps == "%H:%M ", "a timestamp setting this session never wrote is left alone")

-- The chat windows' font, outline and shadow.
check(Chat.db.font == "game" and Chat.db.outline == "game" and Chat.db.shadow == "game",
	"font, outline and shadow start on the game's own")
check(ChatFrame1.sets == 0 and ChatFrame1.shadow[1] == 1, "on the game's own, the chat window is never touched")

local body = Everlook.Font.Body
body.path = "Interface\\AddOns\\EverlookFonts\\assets\\manrope.ttf"
t.change("EverlookChat_font", "Body")
check(ChatFrame1.path == body.path and ChatFrame1.size == 16 and ChatFrame1.flags == "",
	"a token: its file, at the tab's own size")

Everlook.SetFontToken("Body", "Interface\\AddOns\\EverlookFonts\\assets\\expressway.ttf")
check(ChatFrame1.path == body:GetFont(), "a token given another font: chat follows it")

-- The tab's Font Size menu sets the size and keeps the file and flags it finds.
ChatFrame1:SetFont(ChatFrame1.path, 18, ChatFrame1.flags)
t.change("EverlookChat_outline", "thick")
check(ChatFrame1.flags == "THICKOUTLINE" and ChatFrame1.size == 18 and ChatFrame1.path == body:GetFont(),
	"outline: set in the flags, keeping the tab's size and the token's file")
t.change("EverlookChat_shadow", "strong")
check(ChatFrame1.shadow[1] == 2 and ChatFrame1.shadow[2] == -2 and ChatFrame1.shadowColor[4] == 1,
	"shadow: strong, two pixels")
t.change("EverlookChat_shadow", "soft")
check(ChatFrame1.shadow[1] == 1 and ChatFrame1.shadowColor[4] == 0.5, "shadow: soft, one pixel at half strength")
t.change("EverlookChat_shadow", "none")
check(ChatFrame1.shadow[1] == 0 and ChatFrame1.shadow[2] == 0, "shadow: none")

-- A whisper window opened later gets the choice.
ChatFrame2 = fontInstance(setmetatable({}, { __index = ChatFrameType }), ARIAL, 14, "")
CHAT_FRAMES[2] = "ChatFrame2"
FCF_OpenTemporaryWindow()
check(ChatFrame2.path == body:GetFont() and ChatFrame2.flags == "THICKOUTLINE" and ChatFrame2.shadow[1] == 0,
	"a window opened later gets the font, outline and shadow")

-- Back to the game's own: ChatFontNormal's file, flags and shadow, at each tab's size.
t.change("EverlookChat_font", "game")
t.change("EverlookChat_outline", "game")
t.change("EverlookChat_shadow", "game")
check(ChatFrame1.path == ARIAL and ChatFrame1.flags == "" and ChatFrame1.size == 18
	and ChatFrame1.shadow[1] == 1 and ChatFrame1.shadow[2] == -1,
	"the game's own again: ChatFontNormal's file, outline and shadow, the tab's size kept")
check(ChatFrame2.path == ARIAL and ChatFrame2.size == 14, "and on the later window too")
-- A whisper window opened while Fonts gave ChatFontNormal Manrope copied it; on the game's font
-- it goes back to the game's. Another addon's file is left alone.
ChatFrame3 = fontInstance(setmetatable({}, { __index = ChatFrameType }), body.path, 14, "")
ChatFrame4 = fontInstance(setmetatable({}, { __index = ChatFrameType }), "Interface\\AddOns\\Other\\a.ttf", 14, "")
CHAT_FRAMES[3], CHAT_FRAMES[4] = "ChatFrame3", "ChatFrame4"
FCF_OpenTemporaryWindow()
check(ChatFrame3.path == ARIAL, "a window that copied an Everlook font goes back to the game's")
check(ChatFrame4.sets == 0, "a window on another addon's font is left alone")
CHAT_FRAMES[3], CHAT_FRAMES[4] = nil, nil

local sets = ChatFrame1.sets
t.change("EverlookChat_shortLabels", false)
check(ChatFrame1.sets == sets, "once back, nothing is set again")

t.done()
