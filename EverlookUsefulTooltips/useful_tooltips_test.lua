local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookUsefulTooltips")

local postCalls = {}
Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) postCalls[kind] = fn end }

-- Tooltips that record their lines.
local function tooltip(name)
	local tip = { name = name, lines = {} }
	function tip:AddLine(text) self.lines[#self.lines + 1] = text end
	function tip:GetUnit() return "name", self.unit end
	return tip
end
GameTooltip = tooltip("GameTooltip")
ItemRefTooltip = tooltip("ItemRefTooltip")
local shopping = tooltip("ShoppingTooltip1")

local prices, counts = { [100] = 250, [200] = 0 }, { [100] = 3, [200] = 5 }
C_Item = {
	GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[id] end,
	GetItemCount = function(id) return counts[id] end,
}
local guids = { target = "Creature-0-1234-0-5678-1500-0000ABCDEF" }
UnitGUID = function(unit) return guids[unit] end

t.load("EverlookUsefulTooltips")
t.fire("PLAYER_LOGIN")
local U = Everlook:GetAddon("EverlookUsefulTooltips")

local function lines(tip) return table.concat(tip.lines, " | ") end
local function show(kind, tip, data)
	tip.lines = {}
	postCalls[kind](tip, data)
	return lines(tip)
end

check(U.db.itemIDs and U.db.npcIDs and U.db.vendorPrice and U.db.bagTotal, "every line starts on")
check(postCalls[0] and postCalls[2], "hooks item and unit tooltips")

check(show(0, GameTooltip, { id = 100 }) == "Item ID: 100 | Vendor: 2s 50c | In bags: 3 (7s 50c)",
	"item: ID, vendor price, bag count and total")
check(show(0, ItemRefTooltip, { id = 100 }) == "Item ID: 100 | Vendor: 2s 50c | In bags: 3 (7s 50c)",
	"also on a clicked item link")
check(show(0, shopping, { id = 100 }) == "", "comparison tooltips stay as they are")
check(show(0, GameTooltip, { id = 200 }) == "Item ID: 200", "no sell price: no vendor or bag lines")

counts[100] = 1
check(show(0, GameTooltip, { id = 100 }) == "Item ID: 100 | Vendor: 2s 50c", "a single copy gets no bag line")
counts[100] = 3

t.change("EverlookUsefulTooltips_itemIDs", false)
t.change("EverlookUsefulTooltips_bagTotal", false)
check(show(0, GameTooltip, { id = 100 }) == "Vendor: 2s 50c", "each line has its own switch")
t.change("EverlookUsefulTooltips_itemIDs", true)
t.change("EverlookUsefulTooltips_bagTotal", true)

check(show(2, GameTooltip, { guid = "Creature-0-1234-0-5678-1500-0000ABCDEF" }) == "NPC ID: 1500", "unit: NPC ID")
check(show(2, GameTooltip, { guid = "Vehicle-0-1234-0-5678-27000-0000ABCDEF" }) == "NPC ID: 27000", "vehicles too")
check(show(2, GameTooltip, { guid = "Player-1234-0ABCDEF0" }) == "", "players get nothing")
GameTooltip.unit = "target"
check(show(2, GameTooltip, {}) == "NPC ID: 1500", "falls back to the tooltip's unit when data has no GUID")
GameTooltip.unit = nil
t.change("EverlookUsefulTooltips_npcIDs", false)
check(show(2, GameTooltip, { guid = "Creature-0-1234-0-5678-1500-0000ABCDEF" }) == "", "NPC IDs can be turned off")
t.change("EverlookUsefulTooltips_npcIDs", true)

issecretvalue = function(value) return value == 100 end
check(show(0, GameTooltip, { id = 100 }) == "", "a hidden (secret) item ID adds nothing")
issecretvalue = nil

check(U.NpcID("Creature-0-1-2-3-42-ab") == 42 and U.NpcID(nil) == nil and U.NpcID("garbage") == nil, "NpcID parsing")

t.done()
