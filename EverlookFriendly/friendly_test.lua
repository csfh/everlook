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

-- Hooks run after the function, as in the game.
hooksecurefunc = function(target, name, fn)
	if type(target) == "string" then target, name, fn = _G, target, name end
	local original = target[name]
	target[name] = function(...)
		local a, b, c = original(...)
		fn(...)
		return a, b, c
	end
end
SitStandOrDescendStart = function() end
local mounted, cozy = false, false
IsMounted = function() return mounted end
IsFlying = function() return false end
IsSwimming = function() return false end
C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return cozy and id == 7353 and {} or nil end }

t.load("EverlookFriendly")
t.fire("PLAYER_LOGIN")
local F = Everlook:GetAddon("EverlookFriendly")

local function buff(unit, helpful)
	t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = helpful ~= false, sourceUnit = unit,
		isFromPlayerOrPlayerPet = true } } })
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
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true, isFromPlayerOrPlayerPet = true }, { isHelpful = true, isFromPlayerOrPlayerPet = true } } })
runTimers()
inInstance = false
check(#sent == 1 and sent[1][1] == "Thank you!" and sent[1][2] == "SAY", "in an instance: /say thank you, once for several buffs")

-- One buff as two auras, one naming the caster and one not: one whisper, no emote.
reset()
t.now = t.now + 301
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true, sourceUnit = "target" }, { isHelpful = true, isFromPlayerOrPlayerPet = true } } })
runTimers()
check(#sent == 1 and sent[1][2] == "WHISPER", "a buff that lands named and unnamed is one whisper, without the /thank emote")
reset()
t.now = t.now + 301
buff(nil)
t.now = t.now + 1
buff("mouseover")
runTimers()
check(#sent == 1 and sent[1][2] == "WHISPER", "the named part landing just after the unnamed part: still only the whisper")
reset()
t.now = t.now + 60
buff("mouseover")
buff(nil)
runTimers()
check(#sent == 0, "a player thanked a minute ago rebuffs: no whisper, and no emote either")
reset()
t.now = t.now + 301
buff(nil)
runTimers()
check(#sent == 1 and sent[1][1] == "emote THANK", "an unnamed buff on its own still gets the /thank emote")

-- A campfire's warmth, or any buff no player cast: nothing.
reset()
t.now = t.now + 301
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true, isFromPlayerOrPlayerPet = false } } })
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true } } })
runTimers()
check(#sent == 0 and #timers == 0, "a buff no player cast, or one the game can't say, is never thanked")

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

-- Logging in, reloading or zoning: the game adds back the buffs you already have, some unnamed.
reset()
t.now = t.now + 301
t.fire("PLAYER_ENTERING_WORLD", true, false)
buff(nil)
buff("target")
t.now = t.now + 4
buff(nil)
runTimers()
check(#sent == 0 and #timers == 0, "buffs added back after a loading screen get no /thank and no whisper")
t.now = t.now + 2
buff("target")
runTimers()
check(#sent == 1 and sent[1][2] == "WHISPER", "a few seconds later, a new buff is thanked again")

-- A buff that started a while ago is one you already had, whenever it shows up.
reset()
t.now = t.now + 301
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true, isFromPlayerOrPlayerPet = true,
	duration = 1800, expirationTime = t.now + 1200 } } })
runTimers()
check(#sent == 0 and #timers == 0, "an old buff showing up again is not thanked")
t.fire("UNIT_AURA", "player", { addedAuras = { { isHelpful = true, isFromPlayerOrPlayerPet = true,
	duration = 1800, expirationTime = t.now + 1800 } } })
runTimers()
check(#sent == 1 and sent[1][1] == "emote THANK", "the same buff cast just now is")

-- Sitting by a campfire: /hello after 5 seconds, when switched on.
local function greets()
	local n = 0
	for _, entry in ipairs(sent) do if entry[1] == "emote HELLO" then n = n + 1 end end
	return n
end
reset()
cozy = true
check(not F.db.greetCampfire, "the campfire greeting starts off")
C_ChatInfo.PerformEmote("SIT")
runTimers()
check(greets() == 0, "off: sitting by a fire greets no one")
t.change("EverlookFriendly_greetCampfire", true)

reset()
C_ChatInfo.PerformEmote("SIT")
check(#timers == 1 and timers[1].seconds == 5, "/sit by a fire waits 5 seconds")
runTimers()
check(greets() == 1 and sent[#sent][3] == "none", "then /hello to everyone, not your target")
C_ChatInfo.PerformEmote("STAND")

reset()
C_ChatInfo.PerformEmote("SIT")
runTimers()
check(greets() == 0, "sitting again within 5 minutes: no second greeting")
C_ChatInfo.PerformEmote("STAND")

reset()
t.now = t.now + 301
SitStandOrDescendStart()
runTimers()
check(greets() == 1, "the sit key greets too")
reset()
t.now = t.now + 301
SitStandOrDescendStart() -- stands up
runTimers()
check(#timers == 0 and greets() == 0, "the sit key again stands you up: no greeting")

reset()
SitStandOrDescendStart()
t.fire("PLAYER_STARTED_MOVING")
runTimers()
check(greets() == 0, "walking off before 5 seconds: no greeting")

reset()
C_ChatInfo.PerformEmote("SIT")
C_ChatInfo.PerformEmote("STAND")
C_ChatInfo.PerformEmote("SIT")
runTimers()
check(greets() == 1, "sit, stand, sit: one greeting, from the last sit")
C_ChatInfo.PerformEmote("STAND")

reset()
t.now = t.now + 301
cozy = false
C_ChatInfo.PerformEmote("SIT")
runTimers()
check(greets() == 0, "sitting away from a fire greets no one")
C_ChatInfo.PerformEmote("STAND")
cozy = true

reset()
mounted = true
SitStandOrDescendStart()
mounted = false
runTimers()
check(#timers == 0 and greets() == 0, "the sit key while mounted doesn't count as sitting")

reset()
C_ChatInfo.PerformEmote("SIT")
t.shift = true
runTimers()
t.shift = false
check(greets() == 0, "Shift skips the greeting")
C_ChatInfo.PerformEmote("STAND")

reset()
C_ChatInfo.PerformEmote("SIT")
t.change("EverlookFriendly_greetCampfire", false)
runTimers()
check(greets() == 0, "switched off while waiting: no greeting")
C_ChatInfo.PerformEmote("STAND")

-- In combat the game can hand over the whole list as a secret, which ipairs can't walk.
reset()
t.now = t.now + 301
local secretList = newproxy() -- like a secret, ipairs fails on it
local before = issecretvalue
issecretvalue = function(value) return value == secretList end
local ok = pcall(t.fire, "UNIT_AURA", "player", { addedAuras = secretList })
issecretvalue = before
check(ok and #timers == 0, "a secret aura list is skipped without an error")

t.done()
