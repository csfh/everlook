local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookSpellRanks")

-- Spells by ID: name and rank text.
local spells = {
	[331] = { "Healing Wave", "Rank 1" },
	[332] = { "Healing Wave", "Rank 2" },
	[547] = { "Healing Wave", "Rank 3" },
	[403] = { "Lightning Bolt", "Rank 1" },
	[529] = { "Lightning Bolt", "Rank 2" },
	[8017] = { "Rockbiter Weapon", "Rank 1" },
	[900] = { "Ghost Wolf", "" },   -- no ranks: the old version left the spellbook
	[901] = { "Ghost Wolf", "" },
	[950] = { "Totem", "" },        -- no ranks, still in the spellbook
	[951] = { "Totem", "" },
}
local book -- the spellbook: list of spell IDs
local bars -- [slot] = { type, id }
local cursor

Enum = Enum or {}
Enum.SpellBookSpellBank = { Player = 0 }
Enum.SpellBookItemType = { Spell = 1 }
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return 1 end,
	GetSpellBookSkillLineInfo = function() return { itemIndexOffset = 0, numSpellBookItems = #book } end,
	GetSpellBookItemInfo = function(index)
		local id = book[index]
		return { itemType = 1, spellID = id, name = spells[id][1], isPassive = false }
	end,
}
C_Spell = {
	GetSpellName = function(id) return spells[id] and spells[id][1] end,
	GetSpellSubtext = function(id) return spells[id] and spells[id][2] end,
	PickupSpell = function(id) cursor = id t.log("pickup " .. id) end,
}
GetActionInfo = function(slot) local action = bars[slot] if action then return action[1], action[2] end end
PlaceAction = function(slot) t.log("place " .. slot) bars[slot] = { "spell", cursor } end
ClearCursor = function() cursor = nil t.log("clear") end
GetCursorInfo = function() return cursor and "spell" or nil end
local afters = {}
C_Timer.After = function(_, fn) afters[#afters + 1] = fn end
local function runAfters() local list = afters afters = {} for _, fn in ipairs(list) do fn() end end

local function reset(newBook, newBars)
	book, bars, cursor = newBook, newBars, nil
	t.reset()
end

t.load("EverlookSpellRanks")
t.fire("PLAYER_LOGIN")
local S = Everlook:GetAddon("EverlookSpellRanks")
local function upgradedTo(slot) return bars[slot] and bars[slot][2] end

check(S.db.upgrade and S.db.announce, "upgrading and the chat line start on")

-- Picking the newer rank.
reset({ 331, 332, 547, 403, 529, 8017 }, {})
local function newer(id) return (S:Newer(id, (function()
	local byName = {}
	for _, bookID in ipairs(book) do
		local name = spells[bookID][1]
		byName[name] = byName[name] or {}
		table.insert(byName[name], { spellID = bookID, rank = tonumber(spells[bookID][2]:match("%d+") or "") })
	end
	return byName
end)())) end
check(newer(331) == 547 and newer(332) == 547, "an older rank finds the highest rank you know")
check(newer(547) == nil and newer(8017) == nil, "the highest rank, or a spell with one rank, stays")

-- A pass over the bars, the way it runs at login.
reset({ 331, 332, 547, 403, 529 }, {
	[1] = { "spell", 331 },        -- Healing Wave 1
	[2] = { "spell", 403 },        -- Lightning Bolt 1
	[3] = { "macro", 12 },
	[4] = { "item", 6948 },
	[25] = { "spell", 332 },       -- Healing Wave 2, on another bar
	[30] = { "spell", 547 },       -- already the newest
})
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
check(upgradedTo(1) == 547 and upgradedTo(25) == 547, "Healing Wave on every bar becomes Rank 3, in the same slot")
check(upgradedTo(2) == 529, "Lightning Bolt becomes Rank 2")
check(bars[3][1] == "macro" and bars[4][1] == "item" and upgradedTo(30) == 547, "macros, items and up-to-date spells are left alone")
check(has("pickup 547") and has("place 1") and has("clear") and cursor == nil, "each swap picks up, places, and clears the cursor")
check(t.printed("Upgraded Healing Wave (Rank 3) on 2 slots") and t.printed("Upgraded Lightning Bolt (Rank 2) on 1 slot"),
	"it says what it upgraded")

-- Learning a spell.
reset({ 403, 529 }, { [5] = { "spell", 403 } })
t.fire("LEARNED_SPELL_IN_SKILL_LINE", 529)
check(upgradedTo(5) == 403, "it waits a moment after learning, for the spellbook to catch up")
runAfters()
t.runSchedule()
check(upgradedTo(5) == 529, "then upgrades the bar")

-- Nothing else triggers a check.
reset({ 331, 547 }, { [6] = { "spell", 331 } })
t.fire("SPELLS_CHANGED")
t.fire("PLAYER_ENTERING_WORLD", false, false) -- a zone change
t.runSchedule()
check(upgradedTo(6) == 331, "zone changes and other spellbook changes don't check")

-- Clients without rank text.
reset({ 901, 950, 951 }, { [7] = { "spell", 900 }, [8] = { "spell", 950 } })
t.fire("PLAYER_ENTERING_WORLD", false, true)
t.runSchedule()
check(upgradedTo(7) == 901, "without ranks, a spell that left the spellbook is replaced by the one with its name")
check(upgradedTo(8) == 950, "without ranks, a spell still in the spellbook is left alone")

-- Combat, the cursor, Shift, and off.
reset({ 331, 547 }, { [9] = { "spell", 331 } })
t.combat = true
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
check(upgradedTo(9) == 331, "nothing changes in combat")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
t.runSchedule()
check(upgradedTo(9) == 547, "and the check runs when combat ends")

reset({ 331, 547 }, { [10] = { "spell", 331 } })
cursor = 8017
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
check(upgradedTo(10) == 331 and cursor == 8017, "something on your cursor is left alone, and so is the bar")
cursor = nil
runAfters()
t.runSchedule()
check(upgradedTo(10) == 547, "it tries again a second later")

reset({ 331, 547 }, { [11] = { "spell", 331 } })
t.shift = true
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
t.shift = false
check(upgradedTo(11) == 331, "Shift skips it")

S.db.upgrade = false
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
check(upgradedTo(11) == 331, "off means off")

t.done()
