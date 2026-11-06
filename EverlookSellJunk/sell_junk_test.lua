local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has, printed = t.check, t.has, t.printed

t.out("EverlookSellJunk")

Enum = { ItemQuality = { Poor = 0 } }
NUM_BAG_SLOTS = 0

local bag
local function fillBag()
	bag = {
		[1] = { itemID = 1, quality = 0, stackCount = 2 }, -- gray, 10c each
		[2] = { itemID = 2, quality = 0, stackCount = 1 }, -- gray quest item
		[3] = { itemID = 3, quality = 1, stackCount = 1 }, -- white
		[4] = { itemID = 4, quality = 0, stackCount = 1, hasNoValue = true },
		[5] = { itemID = 5, quality = 0, stackCount = 1, isLocked = true },
		[6] = { itemID = 6, quality = 0, stackCount = 3 }, -- gray, 1c each
	}
end
local prices = { 10, 5, 100, 0, 7, 1 }
C_Container = {
	GetContainerNumSlots = function() return 6 end,
	GetContainerItemInfo = function(_, slot) return bag[slot] end,
	GetContainerItemQuestInfo = function(_, slot) return { isQuestItem = slot == 2 } end,
	UseContainerItem = function(_, slot) t.log("sell " .. slot) bag[slot] = nil end,
}
C_Item = {
	GetItemInfo = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, prices[id] end,
}

t.load("EverlookSellJunk")
t.fire("PLAYER_LOGIN")
local S = Everlook:GetAddon("EverlookSellJunk")

check(S.db.sellGray, "selling grays starts on")

fillBag(); t.reset()
t.fire("MERCHANT_SHOW"); t.runTicker()
check(has("sell 1") and has("sell 6"), "sells gray items")
check(not has("sell 2") and not has("sell 3") and not has("sell 4") and not has("sell 5"),
	"keeps quest items, non-grays, no-value and locked items")
check(printed("Sold junk for 23c."), "prints the total")
t.fire("MERCHANT_CLOSED")

fillBag(); t.reset()
t.fire("MERCHANT_SHOW")
t.tickers[#t.tickers].fn() -- one sale
t.fire("MERCHANT_CLOSED")
t.runTicker()
check(has("sell 1") and not has("sell 6"), "closing the vendor stops the rest")

fillBag(); t.reset()
t.fire("MERCHANT_SHOW")
t.shift = true
t.runTicker()
t.shift = false
check(not t.printed("sell "), "Shift stops selling")
t.fire("MERCHANT_CLOSED")

local questInfo = C_Container.GetContainerItemQuestInfo
C_Container.GetContainerItemQuestInfo = nil
fillBag(); t.reset()
t.fire("MERCHANT_SHOW"); t.runTicker()
check(not t.printed("sell "), "unreadable quest info keeps everything")
C_Container.GetContainerItemQuestInfo = questInfo
t.fire("MERCHANT_CLOSED")

S.db.sellGray = false
fillBag(); t.reset()
t.fire("MERCHANT_SHOW"); t.runTicker()
check(#t.calls == 0, "off means off")

t.done()
