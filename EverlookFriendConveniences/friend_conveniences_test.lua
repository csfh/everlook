local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookFriendConveniences")

local friends = { { name = "Aly" }, { name = "Bob-Other Realm" } }
local guild = { "Gus-MyRealm" }
local inGuild = true
C_FriendList = {
	GetNumFriends = function() return #friends end,
	GetFriendInfoByIndex = function(i) return friends[i] end,
}
GetNormalizedRealmName = function() return "MyRealm" end
IsInGuild = function() return inGuild end
GetNumGuildMembers = function() return #guild end
GetGuildRosterInfo = function(i) return guild[i], "rank" end
AcceptGroup = function() t.log("AcceptGroup") end
DeclineGroup = function() t.log("DeclineGroup") end
CancelDuel = function() t.log("CancelDuel") end
StaticPopup_Hide = function(which) t.log("hide " .. which) end

t.load("EverlookFriendConveniences")
t.fire("PLAYER_LOGIN")
local F = Everlook:GetAddon("EverlookFriendConveniences")
local function invite(name) t.reset() t.fire("PARTY_INVITE_REQUEST", name) end

check(F.db.friends and F.db.guild and not F.db.declineOthers and not F.db.declineDuels,
	"friends and guild start on, declining off")

invite("Aly")
check(has("AcceptGroup") and has("hide PARTY_INVITE"), "accepts a friend on your realm")
invite("aly-myrealm")
check(has("AcceptGroup"), "names match regardless of case, realm included")
invite("Bob-OtherRealm")
check(has("AcceptGroup"), "realm spaces are ignored")
invite("Gus")
check(has("AcceptGroup"), "accepts a guildmate")
invite("Aly-Elsewhere")
check(#t.calls == 0, "same name on another realm isn't trusted")
invite("Stranger")
check(#t.calls == 0, "a stranger's invite stays on screen")

F.db.declineOthers = true
invite("Stranger")
check(has("DeclineGroup") and has("hide PARTY_INVITE"), "declines a stranger when asked to")
F.db.declineOthers = false

F.db.guild = false
invite("Gus")
check(#t.calls == 0, "guild off: a guildmate's invite stays")
F.db.guild = true
inGuild = false
invite("Gus")
check(#t.calls == 0, "not in a guild: no guildmates")
inGuild = true

issecretvalue = function(v) return v == "SECRET" end
F.db.declineOthers = true
invite("SECRET")
check(#t.calls == 0, "a hidden name is left alone, never declined")
issecretvalue = nil
F.db.declineOthers = false

t.combat = true
invite("Aly")
check(#t.calls == 0, "nothing in combat")
t.combat = false
t.shift = true
invite("Aly")
check(#t.calls == 0, "Shift skips")
t.shift = false

t.reset()
t.fire("DUEL_REQUESTED", "Aly")
check(#t.calls == 0, "duels stay while declining is off")
F.db.declineDuels = true
t.reset()
t.fire("DUEL_REQUESTED", "Aly")
check(has("CancelDuel") and has("hide DUEL_REQUESTED"), "declines a duel when asked to")

t.done()
