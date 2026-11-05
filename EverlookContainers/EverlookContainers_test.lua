local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookContainers")

NUM_BAG_SLOTS = 0

-- Bag 0: slot 1 a clam (has loot), slot 2 a locked box, slot 3 a plain item.
local bag
local function fillBag()
	bag = {
		[1] = { hasLoot = true, isLocked = false, stackCount = 1, guid = "Item-clam" },
		[2] = { hasLoot = true, isLocked = true, stackCount = 1, guid = "Item-locked" },
		[3] = { hasLoot = false, isLocked = false, stackCount = 5, guid = "Item-plain" },
	}
end
C_Container = {
	GetContainerNumSlots = function() return 3 end,
	GetContainerItemInfo = function(_, slot) return bag[slot] end,
	UseContainerItem = function(_, slot) t.log("use " .. slot) end,
}
ItemLocation = {}
function ItemLocation:CreateFromBagAndSlot(b, s) return { bag = b, slot = s } end
C_Item = {
	DoesItemExist = function(location) return bag[location.slot] ~= nil end,
	GetItemGUID = function(location) return bag[location.slot].guid end,
}
CursorHasItem = function() return false end
GetCursorInfo = function() return nil end
SpellCanTargetItem = function() return false end
SpellCanTargetItemID = function() return false end

-- Loot window: slot -> { texture, locked, source GUID }
local loot = {}
GetNumLootItems = function() return #loot end
GetLootSlotInfo = function(slot) local l = loot[slot] return l.texture, "name", 1, nil, 1, l.locked end
GetLootSourceInfo = function(slot) return loot[slot].source, 1 end
LootSlot = function(slot) t.log("loot " .. slot) end
LootFrame = t.widget("LootFrame")
MerchantFrame = t.widget("MerchantFrame")

fillBag()
t.load("EverlookContainers")
t.fire("PLAYER_LOGIN")
local C = Everlook:GetAddon("EverlookContainers")

check(C.db.open, "opening containers starts on")
check(has("use 1") and not has("use 2") and not has("use 3"), "at login it uses the first unlocked container, nothing else")

-- The clam opens a loot window with its own loot and something from another source.
loot = {
	{ texture = "icon", locked = false, source = "Item-clam" },
	{ texture = "icon", locked = false, source = "Creature-other" },
	{ texture = "icon", locked = true, source = "Item-clam" },
}
t.reset()
t.fire("LOOT_OPENED", false, true)
check(has("loot 1") and not has("loot 2") and not has("loot 3"), "takes only unlocked loot that came from the container")

-- Window closes; the clam is gone.
loot = {}
bag[1] = nil
t.reset()
t.fire("LOOT_CLOSED")
t.runTicker()
check(not t.printed("use "), "nothing left to open: stops")

-- A loot window the container didn't open (fromItem false) is left alone.
fillBag()
bag[1].guid = "Item-clam2"
t.reset()
t.fire("BAG_UPDATE_DELAYED")
loot = { { texture = "icon", locked = false, source = "Item-clam2" } }
t.fire("LOOT_OPENED", false, false)
check(has("use 1") and not has("loot 1"), "loot not marked as from an item is left for you")
loot = {}
t.fire("LOOT_CLOSED")

-- A container that opens no loot window isn't tried again unchanged.
fillBag()
bag[1].guid = "Item-dud"
t.reset()
t.fire("BAG_UPDATE_DELAYED")
t.runTicker(10)
local uses = 0
for _, call in ipairs(t.calls) do if call == "use 1" then uses = uses + 1 end end
check(uses == 1, "a container that opens nothing is tried once, then left")

-- Pauses.
fillBag()
bag[1].guid = "Item-fresh"
t.shift = true
t.reset()
t.fire("BAG_UPDATE_DELAYED")
check(not t.printed("use "), "Shift pauses")
t.shift = false

t.combat = true
t.reset()
t.fire("PLAYER_REGEN_ENABLED")
check(not t.printed("use "), "combat pauses")
t.combat = false

MerchantFrame:Show()
t.reset()
t.fire("BAG_UPDATE_DELAYED")
check(not t.printed("use "), "an open vendor window pauses (it would sell)")
MerchantFrame:Hide()

t.reset()
t.fire("MERCHANT_CLOSED")
check(has("use 1"), "closing the vendor resumes")
loot = {}

-- Missing API fails closed.
local getGUID = C_Item.GetItemGUID
C_Item.GetItemGUID = nil
fillBag()
bag[1].guid = "Item-other"
t.reset()
t.fire("BAG_UPDATE_DELAYED")
check(not t.printed("use "), "a missing game function means nothing is used")
C_Item.GetItemGUID = getGUID

-- Off means off.
t.change("EverlookContainers_open", false)
fillBag()
bag[1].guid = "Item-new"
t.reset()
t.fire("BAG_UPDATE_DELAYED")
check(not t.printed("use "), "turned off, nothing is opened")
t.change("EverlookContainers_open", true)
check(has("use 1"), "turned back on, it opens again")

t.done()
