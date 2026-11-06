local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookSkipGossip")

Enum = { GossipOptionStatus = { Available = 0, Unavailable = 1, Locked = 2, AlreadyComplete = 3 } }
local options, available, active, forced = {}, 0, 0, false
C_GossipInfo = {
	GetOptions = function() return options end,
	GetNumAvailableQuests = function() return available end,
	GetNumActiveQuests = function() return active end,
	ForceGossip = function() return forced end,
	SelectOptionByIndex = function(index) t.log("select " .. index) end,
}
local function vendor(name)
	return { name = name or "I would like to buy from you.", status = 0, orderIndex = 3, flags = 0,
		selectOptionWhenOnlyOption = false }
end
bit = bit or { band = function(a, b)
	local result, place = 0, 1
	while a > 0 and b > 0 do
		if a % 2 == 1 and b % 2 == 1 then result = result + place end
		a, b, place = math.floor(a / 2), math.floor(b / 2), place * 2
	end
	return result
end }

t.load("EverlookSkipGossip")
t.fire("PLAYER_LOGIN")
local G = Everlook:GetAddon("EverlookSkipGossip")
local function show() t.reset() t.fire("GOSSIP_SHOW") end

options = { vendor() }
show()
check(not G.db.skip and #t.calls == 0, "starts off and leaves the window")

G.db.skip = true
show()
check(t.calls[1] == "select 3", "one option and no quests: goes straight to it")

t.now = 1
show()
check(#t.calls == 0, "the same option again straight away is left, so a window that reopens can't loop")
t.now = 5
show()
check(t.calls[1] == "select 3", "the same NPC later is skipped again")

t.now = 10
options = { vendor(), vendor("Train me.") }
show()
check(#t.calls == 0, "two options: left to you")

options = { vendor() }
available = 1
show()
check(#t.calls == 0, "a quest to pick up: left to you")
available, active = 0, 1
show()
check(#t.calls == 0, "a quest in progress: left to you")
active = 0

forced = true
show()
check(#t.calls == 0, "an NPC that insists on talking: left to you")
forced = nil
show()
check(#t.calls == 0, "a client that can't say whether it's forced: left to you")
forced = false

local flagged = vendor()
flagged.selectOptionWhenOnlyOption = true
options = { flagged }
show()
check(#t.calls == 0, "an option the game's own frame already takes: left to the game")
local quest = vendor("Tell me about the mine.")
quest.flags = 1
options = { quest }
show()
check(#t.calls == 0, "an option the game marks as a quest step: left to you")
local movie = vendor("Show me.")
movie.flags = 4
options = { movie }
show()
check(#t.calls == 0, "an option that plays a movie: left to you")

options = { { name = "Locked", status = 2, orderIndex = 1 } }
show()
check(#t.calls == 0, "a locked option: left to you")
options = { { name = "Soon", status = 0, orderIndex = 1, failureDescription = "Requires level 20" } }
show()
check(#t.calls == 0, "an option with a failure reason: left to you")

t.now = 20
options = { vendor() }
t.shift = true
show()
check(#t.calls == 0, "Shift leaves the window open")
t.shift = false
show()
check(t.calls[1] == "select 3", "and without Shift it goes through")

t.done()
