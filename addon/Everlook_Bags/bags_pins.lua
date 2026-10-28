local addon_name = ...
local Everlook = Everlook
local junk = Everlook.bags_junk

-- The items the player pinned, as item id -> true. Like a junk mark, a pin is
-- on the item and every copy of it, not on a bag slot.
local pins = {}

function pins.is_pinned(data, item_id)
	return junk.valid(item_id) and data[item_id] == true
end

-- Pins the item, or unpins it when it was pinned. Returns the new state, or nil
-- for an id this store will not hold.
function pins.toggle(data, item_id)
	if not junk.valid(item_id) then return nil end
	if data[item_id] then
		data[item_id] = nil
		return false
	end
	data[item_id] = true
	return true
end

-- The saved table, kept with the rest of the Bags settings. Its key is not the option's name, which would share it.
function pins.data()
	EverlookSaved = EverlookSaved or {}
	EverlookSaved.modules = EverlookSaved.modules or {}
	EverlookSaved.modules.bags = EverlookSaved.modules.bags or {}
	EverlookSaved.modules.bags.pinned = EverlookSaved.modules.bags.pinned or {}
	return EverlookSaved.modules.bags.pinned
end

Everlook.bags_pins = pins
