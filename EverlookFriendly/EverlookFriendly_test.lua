local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookFriendly")

-- Unit tokens -> { guid, name, realm, player }.
local units = {
	player = { guid = "Player-1", name = "Me", player = true },
	target = { guid = "Player-2", name = "Kind", player = true },
	mouseover = { guid = "Player-3", name = "Far", realm = "Elsewhere", player = true },
	party1 = { guid = "Player-4", name = "Friend", player = true },
	nameplate1 = { guid = "Creature-5", name = "Totem", player = false },
}
local grouped = { ["Player-4"] = true }
UnitIsPlayer = function(unit) return units[unit].player end
UnitIsUnit = function(a, b) return units[a].guid == units[b].guid end
UnitGUID = function(unit) return units[unit].guid end
UnitName = function(unit) return units[unit].name, units[unit].realm end
IsGUIDInGroup = function(guid) return grouped[guid] == true end

local sent = {}
local lockdown = false
C_ChatInfo = {
	SendChatMessage = function(message, chatType, _, target) sent[#sent + 1] = { message, chatType, target } end,
	InChatMessagingLockdown = function() return lockdown end,
	PerformEmote = function(emote, target) sent[#sent + 1] = { "emote " .. emote, "EMOTE", target } end,
}
local inInstance = false
IsInInstance = function() return inInstance end
-- Timers wait until the test runs them.
local timers = {}
C_Timer.After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end
local function runTimers()
	local due = timers
	timers = {}
	for _, timer in ipairs(due) do timer.fn() end
end

t.load("EverlookFriendly")
t.fire("PLAYER_LOGIN")
local F = Everlook:GetAddon("EverlookFriendly")

local function buff(unit, helpful)
	t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = helpful ~= false, sourceUnit = unit } } })
end
local function reset() sent, timers = {}, {} end

check(F.db.thankBuffs, "thanking starts on")

buff("target")
check(#sent == 0 and #timers == 1 and timers[1].seconds == 4, "a stranger's buff waits 4 seconds")
runTimers()
check(#sent == 1 and sent[1][1] == "Thank you!" and sent[1][2] == "WHISPER" and sent[1][3] == "Kind", "then whispers them thank you")

reset()
buff("target")
check(#timers == 0, "the same player again within 5 minutes: no second whisper")
t.now = t.now + 301
buff("target")
runTimers()
check(#sent == 1, "after 5 minutes they're thanked again")

reset()
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true, sourceUnit = "mouseover" }, { isHelpful = true, sourceUnit = "mouseover" } } })
runTimers()
check(#sent == 1 and sent[1][3] == "Far-Elsewhere", "two buffs at once are one whisper, with the realm for another realm")

reset()
buff("party1")
buff("player")
buff("nameplate1")
t.now = t.now + 301
buff("target", false)
runTimers()
check(#sent == 0, "group members, yourself, NPCs and debuffs get nothing")

-- A caster the game can't name (no unit token).
reset()
buff(nil)
check(#timers == 1 and timers[1].seconds == 4, "an unknown caster's buff waits 4 seconds too")
runTimers()
check(#sent == 1 and sent[1][1] == "emote THANK" and sent[1][3] == "none", "outside an instance: /thank everyone, not your target")
reset()
buff(nil)
check(#timers == 0, "unknown casters share the 5-minute quiet")
t.now = t.now + 301
inInstance = true
buff(nil)
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true }, { isHelpful = true } } })
runTimers()
inInstance = false
check(#sent == 1 and sent[1][1] == "Thank you!" and sent[1][2] == "SAY", "in an instance: /say thank you, once for several buffs")

reset()
t.fire("UNIT_AURA", "target", { addedAuras = { { isHelpful = true, sourceUnit = "mouseover" } } })
t.fire("UNIT_AURA", "player", { isFullUpdate = true })
runTimers()
check(#sent == 0, "auras on other units, and full updates, are ignored")

reset()
t.now = t.now + 301
buff("target")
grouped["Player-2"] = true
runTimers()
check(#sent == 0, "someone who joins your group during the wait isn't whispered")
grouped["Player-2"] = nil

reset()
t.now = t.now + 301
buff("target")
t.shift = true
runTimers()
t.shift = false
check(#sent == 0, "Shift skips it")

reset()
t.now = t.now + 301
buff("target")
lockdown = true
runTimers()
lockdown = false
check(#sent == 0, "chat lockdown skips it")

reset()
t.now = t.now + 301
buff("target")
t.change("EverlookFriendly_thankBuffs", false)
runTimers()
buff("target")
check(#sent == 0 and #timers == 0, "off: a waiting thank-you is dropped and new buffs are ignored")
t.change("EverlookFriendly_thankBuffs", true)
buff("target")
runTimers()
check(#sent == 1, "on again: thanks resume")

t.done()
