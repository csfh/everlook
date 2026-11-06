-- When you train a new rank of a spell, puts it on every action bar slot that holds an older rank,
-- in the same place. No list of spells: it asks the spellbook which version you know now.
local SpellRanks = Everlook:NewAddon("EverlookSpellRanks", {
	label = "Spell Ranks",
	defaults = {
		upgrade = true,
		announce = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookSpellRanks", {
	"C_SpellBook.GetNumSpellBookSkillLines",
	"C_SpellBook.GetSpellBookSkillLineInfo",
	"C_SpellBook.GetSpellBookItemInfo",
	"Enum.SpellBookSpellBank.Player",
	"Enum.SpellBookItemType.Spell",
	"C_Spell.GetSpellName",
	"C_Spell.GetSpellSubtext",
	"C_Spell.PickupSpell",
	"GetActionInfo",
	"PlaceAction",
	"ClearCursor",
	"GetCursorInfo",
	"InCombatLockdown",
	"IsShiftKeyDown",
	"C_Timer.After",
})

local MAX_SLOTS = 180 -- every action slot the game has, all bars and pages

function SpellRanks:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Action Bars")
	page:Checkbox("upgrade", "Upgrade spells on the action bars",
		"When you train a new rank of a spell, it replaces the older rank on your bars, in the same slot. Waits until combat ends.")
	page:Checkbox("announce", "Tell me in chat",
		"Prints a line when a spell on your bars is upgraded. Needs Upgrade spells on the action bars.")
end

-- "Rank 3" -> 3. Nil when the game gives no rank.
local function rankOf(spellID)
	local subtext = C_Spell.GetSpellSubtext(spellID)
	local rank = type(subtext) == "string" and subtext:match("(%d+)")
	return rank and tonumber(rank)
end

-- Every spell in your spellbook, by name: { [name] = { { spellID, rank }, ... } }.
local function spellbook()
	local byName = {}
	local bank = Enum.SpellBookSpellBank.Player
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info then
			for index = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(index, bank)
				if item and item.itemType == Enum.SpellBookItemType.Spell and item.spellID and not item.isPassive then
					local known = byName[item.name] or {}
					known[#known + 1] = { spellID = item.spellID, rank = rankOf(item.spellID) }
					byName[item.name] = known
				end
			end
		end
	end
	return byName
end

-- The newer version of this spell you know, or nil. Newer means a higher rank when the game gives
-- ranks. When it doesn't, the bar's spell no longer being in the spellbook, with exactly one spell of
-- that name there, means that one replaced it. Anything less certain stays as it is.
function SpellRanks:Newer(spellID, book)
	local name = C_Spell.GetSpellName(spellID)
	local known = name and book[name]
	if not known then return nil end

	local current = rankOf(spellID)
	local best
	for _, entry in ipairs(known) do
		if entry.spellID == spellID then
			-- Still in the spellbook: only a higher rank beats it.
			if not current then return nil end
		elseif entry.rank and current and entry.rank > current and (not best or entry.rank > best.rank) then
			best = entry
		end
	end
	if best then return best.spellID, best.rank end

	-- No ranks, and the loop above found the bar's spell isn't listed any more.
	if not current and #known == 1 then return known[1].spellID, known[1].rank end
	return nil
end

-- Swaps the spell in one slot. Picking up the new spell and placing it puts the old one on the
-- cursor, which is then cleared: what the game does when you drag a spell onto a filled slot.
local function replace(slot, spellID)
	C_Spell.PickupSpell(spellID)
	PlaceAction(slot)
	ClearCursor()
end

local waitingForCombat = false

-- One pass over every slot. Returns { [name] = { rank, slots } } of what it changed.
function SpellRanks:Upgrade()
	if not self.db.upgrade or IsShiftKeyDown() then return {} end
	-- The game blocks bar changes in combat; something on the cursor is yours, and is left there.
	if InCombatLockdown() then
		waitingForCombat = true
		return {}
	end
	if GetCursorInfo() then
		C_Timer.After(1, function() self:Queue() end)
		return {}
	end

	local book = spellbook()
	local changed = {}
	for slot = 1, MAX_SLOTS do
		local actionType, id = GetActionInfo(slot)
		if actionType == "spell" and id then
			local newID, rank = self:Newer(id, book)
			if newID then
				replace(slot, newID)
				local name = C_Spell.GetSpellName(newID)
				local entry = changed[name] or { rank = rank, slots = 0 }
				entry.slots = entry.slots + 1
				changed[name] = entry
			end
		end
	end

	if self.db.announce then
		for name, entry in pairs(changed) do
			local what = entry.rank and (name .. " (Rank " .. entry.rank .. ")") or name
			self:Print(("Upgraded %s on %d slot%s"):format(what, entry.slots, entry.slots == 1 and "" or "s"))
		end
	end
	return changed
end

-- Learning several ranks at a trainer fires a burst of events; they all become one pass.
function SpellRanks:Queue()
	Everlook.Schedule.Defer("spellranks", function() self:Upgrade() end)
end

-- Checks only when you load into the game and when you learn a spell.
function SpellRanks:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
		if isLogin or isReload then self:Queue() end
	end)
	-- The spellbook drops the old rank just after the new one is learned; give it a moment.
	local function learned()
		C_Timer.After(0.5, function() self:Queue() end)
	end
	-- LEARNED_SPELL_IN_SKILL_LINE (SpellBookDocumentation.lua, 12.0.0); Forever has no LEARNED_SPELL_IN_TAB.
	self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", learned)
	-- A check that combat held back runs when it ends.
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if waitingForCombat then
			waitingForCombat = false
			self:Queue()
		end
	end)
end
