local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookLoot")

-- The loot window: { texture, locked } per slot.
local slots = {}
GetNumLootItems = function() return #slots end
GetLootSlotInfo = function(slot)
	local s = slots[slot]
	if not s then return end
	return s.texture, "Item", 1, nil, 1, s.locked
end
LootSlot = function(slot) t.log("loot " .. slot) end
ConfirmLootSlot = function(slot) t.log("confirm " .. slot) end

LE_PARTY_CATEGORY_INSTANCE = 2
local party, instance = false, false
IsInGroup = function(category)
	if category == LE_PARTY_CATEGORY_INSTANCE then return instance end
	return party
end

-- StaticPopup_Show with any post-hooks, as hooksecurefunc chains them.
local hooks = {}
StaticPopupDialogs = { LOOT_BIND = {} }
StaticPopup_Show = function(...)
	for _, hook in ipairs(hooks) do hook(...) end
end
StaticPopup_Hide = function(which) t.log("hide " .. which) end
hooksecurefunc = function(name, fn)
	if name == "StaticPopup_Show" then hooks[#hooks + 1] = fn end
end

t.load("EverlookLoot")
t.fire("PLAYER_LOGIN")
local L = Everlook:GetAddon("EverlookLoot")
local function fire(...) t.reset() t.fire(...) end
local function bind(slot) t.reset() StaticPopup_Show("LOOT_BIND", "Item", nil, slot) end

check(not L.db.fasterLoot and not L.db.confirmBind, "both start off")
check(#hooks == 1, "hooks the popup once")

-- Faster auto loot.
slots = { { texture = 1 }, { texture = 2, locked = true }, { texture = 3 } }
fire("LOOT_READY", true)
check(#t.calls == 0, "off: leaves the loot")

L.db.fasterLoot = true
fire("LOOT_READY", false)
check(#t.calls == 0, "leaves the loot when the game isn't auto looting")

fire("LOOT_READY", true)
check(t.calls[1] == "loot 3" and t.calls[2] == "loot 1" and #t.calls == 2,
	"takes every slot from the last down, and leaves roll items")

t.now = 0.1
fire("LOOT_READY", true)
check(#t.calls == 0, "a second LOOT_READY for the same window is skipped")

t.fire("LOOT_CLOSED")
fire("LOOT_READY", true)
check(#t.calls == 2, "a new window after LOOT_CLOSED is looted")

t.now = 5
slots = { { texture = nil }, { texture = 2 } }
fire("LOOT_READY", true)
check(t.calls[1] == "loot 2" and #t.calls == 1, "skips empty slots")

t.now = 10
issecretvalue = function(value) return value == "secret" end
slots = { { texture = "secret" }, { texture = 2 } }
fire("LOOT_READY", true)
check(t.calls[1] == "loot 2" and #t.calls == 1, "skips slots it can't read")
t.now = 15
fire("LOOT_READY", "secret")
check(#t.calls == 0, "a secret autoloot flag leaves the loot")
issecretvalue = nil

-- Bind-on-pickup.
bind(2)
check(#t.calls == 0, "off: leaves the prompt")

L.db.confirmBind = true
bind(2)
check(has("confirm 2") and has("hide LOOT_BIND"), "alone: confirms the slot and closes the prompt")

t.reset()
StaticPopup_Show("DELETE_ITEM", "Item", nil, 2)
check(#t.calls == 0, "leaves other popups")

party = true
bind(2)
check(#t.calls == 0, "leaves it in a party or raid")
party, instance = false, true
bind(2)
check(#t.calls == 0, "leaves it in an instance group")
instance = false

local isInGroup = IsInGroup
IsInGroup = nil
bind(2)
check(#t.calls == 0, "can't tell about the group: leaves it")
IsInGroup = isInGroup

bind(nil)
check(#t.calls == 0, "no slot: leaves it")

t.shift = true
bind(2)
check(#t.calls == 0, "Shift leaves it")
t.shift = false

t.done()
