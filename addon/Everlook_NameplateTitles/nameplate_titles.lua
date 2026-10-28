local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local plates = Everlook.nameplates
local id = "nameplate_titles"
local SOURCE = "everlook_titles"

-- The client draws an NPC's name and <title> in the world as engine text, which an addon cannot restyle. A friendly
-- NPC's nameplate is a frame, so it takes the same name style as a player's. Nameplates carry no title, so this
-- gives the nameplate view a subtitle line for it, and for every other NPC with a title, read from the second line of the unit's tooltip.

local plain = Everlook.readable

local function text_of(row)
	if not plain(row) or type(row) ~= "table" then return nil end
	local text = row.leftText
	if not plain(text) or type(text) ~= "string" then return nil end
	return text
end

-- Whether a line is the level line, which says "Level 16" in the client's language.
local function is_level(text)
	local word = plain(LEVEL) and type(LEVEL) == "string" and LEVEL or "Level"
	return text ~= nil and text:sub(1, #word) == word
end

-- The title from the unit's tooltip: the line under the name, when it is in angle brackets or the level line
-- comes right after it. A creature with no title has the level line there instead. Nil when there is none.
local function title_of(unit)
	if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
	local data = C_TooltipInfo.GetUnit(unit)
	if not plain(data) or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	local text = text_of(data.lines[2])
	if not text or text == "" or is_level(text) then return nil end
	if text:match("^<.+>$") or is_level(text_of(data.lines[3])) then return text end
	return nil
end

-- Any creature, friend or not: a neutral vendor or a guard has a title as much as a friendly one, and a plate with
-- only a name is one the game makes for friendly NPCs. Players have a guild in that line, which is not a title.
local function npc(unit)
	return UnitExists and UnitExists(unit) and not UnitIsPlayer(unit)
end

-- The line under an NPC's name, in the name's colour.
local function subtitle(unit, _, plate)
	if not npc(unit) then return nil end
	local title = title_of(unit)
	if not title then return nil end
	local red, green, blue = 0.1, 1, 0.1
	local name = plate and plate.UnitFrame and plate.UnitFrame.name
	if name and name.GetTextColor then
		local r, g, b = name:GetTextColor()
		if plain(r) and plain(g) and plain(b) then red, green, blue = r, g, b end
	end
	return { text = title, color = { red, green, blue } }
end

-- The nameplate settings that turn the engine's NPC text off and the friendly
-- NPC nameplates on, and the value this sets for each.
local WANTED = { nameplateShowFriendlyNpcs = "1", UnitNameNPC = "0", UnitNameFriendlySpecialNPCName = "0" }

local function current_value(name)
	local value = GetCVar(name)
	if type(value) == "string" and not Everlook.secret(value) then return value end
end

-- Options' NPC Names dropdown writes the two name settings together, so they are one choice.
local GROUPS = { { "nameplateShowFriendlyNpcs" }, { "UnitNameNPC", "UnitNameFriendlySpecialNPCName" } }

local function holds_ours(group)
	for _, name in ipairs(group) do
		if current_value(name) ~= WANTED[name] then return false end
	end
	return true
end

-- What each choice was is kept, and put back when this goes off, but only where it still holds
-- what this set: a choice the player made in Options meanwhile is theirs. Setting them again,
-- after combat or another change, takes such a choice as the one to put back.
local function switch_names(enabled)
	if type(InCombatLockdown) ~= "function" or InCombatLockdown() or not GetCVar or not SetCVar then return end
	EverlookDB = EverlookDB or {}
	if enabled and module.get(id, "use_nameplates") then
		local saved = EverlookDB.nameplate_titles_before
		if type(saved) ~= "table" then
			saved = {}
			EverlookDB.nameplate_titles_before = saved
		end
		for _, group in ipairs(GROUPS) do
			if saved[group[1]] == nil or not holds_ours(group) then
				for _, name in ipairs(group) do saved[name] = current_value(name) end
			end
			for _, name in ipairs(group) do SetCVar(name, WANTED[name]) end
		end
	elseif type(EverlookDB.nameplate_titles_before) == "table" then
		local saved = EverlookDB.nameplate_titles_before
		for _, group in ipairs(GROUPS) do
			if holds_ours(group) then
				for _, name in ipairs(group) do
					if type(saved[name]) == "string" then SetCVar(name, saved[name]) end
				end
			end
		end
		EverlookDB.nameplate_titles_before = nil
	end
end

local function apply(enabled)
	switch_names(enabled)
	if enabled then
		plates.provide({ source = SOURCE, order = 20, kinds = { "friendly_npc", "enemy_npc", "name_only" }, subtitle = subtitle })
	else
		plates.remove(SOURCE)
	end
end

module.register({
	addon = addon_name, page = "nameplates", order = 44,
	id = id,
	name = "NPC names on nameplates",
	description = "NPCs get the same name style as players, with their title under the name, such as Drink Vendor or Trade Supplies, whether they are friendly, neutral or hostile. The game draws an NPC's own name and title as engine text that an addon cannot restyle, so this uses friendly NPC nameplates instead. The title is a line on the Nameplates view, which does the placing and needs to be on for a title to show.",
	options = {
		use_nameplates = { name = "Switch the game's NPC names to nameplates", default = true, description = "Turns on friendly NPC nameplates and turns off the game's own NPC names for friendly special NPCs, such as trainers and flight masters. Turning this module off, or this option, puts those settings back as they were, or as you set them in Options since." },
	},
	apply = apply,
	out_of_combat = true,
})
