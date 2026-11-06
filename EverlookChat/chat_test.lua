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

local shown = {}
local ChatFrameType = { AddMessage = function(_, text) shown[#shown + 1] = text end }
ChatFrame1 = setmetatable({}, { __index = ChatFrameType })
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

t.done()
