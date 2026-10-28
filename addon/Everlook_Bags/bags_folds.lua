local addon_name = ...
local Everlook = Everlook

-- The sections the player folded, as section key -> true. A fold is on the
-- section, not on what is in it, so it outlives the items.
local folds = {}

local function valid(key)
	if issecretvalue and issecretvalue(key) then return false end
	return type(key) == "string" and key ~= "" and #key <= 32
end

function folds.is_folded(data, key)
	return valid(key) and data[key] == true
end

-- Folds the section, or opens it when it was folded. Returns the new state, or
-- nil for a key this store will not hold.
function folds.toggle(data, key)
	if not valid(key) then return nil end
	if data[key] then
		data[key] = nil
		return false
	end
	data[key] = true
	return true
end

-- The saved table, kept with the rest of the Bags settings. Its key is not the option's name.
function folds.data()
	EverlookSaved = EverlookSaved or {}
	EverlookSaved.modules = EverlookSaved.modules or {}
	EverlookSaved.modules.bags = EverlookSaved.modules.bags or {}
	EverlookSaved.modules.bags.folded = EverlookSaved.modules.bags.folded or {}
	return EverlookSaved.modules.bags.folded
end

Everlook.bags_folds = folds
