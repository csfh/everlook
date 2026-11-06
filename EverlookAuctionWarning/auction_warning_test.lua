local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookAuctionWarning")

local vendor = { ["item:1"] = 1000, ["item:2"] = 0, ["battlepet:3"] = 500 }
C_Item = {
	GetItemLink = function(item) return item.link end,
	GetItemInfo = function(link) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, vendor[link] end,
}
LinkUtil = { IsLinkType = function(link, kind) return link:sub(1, #kind + 1) == kind .. ":" end }
local loaded = false
C_AddOns.IsAddOnLoaded = function(name) return loaded and name == "Blizzard_AuctionHouseUI" end

local popup
StaticPopup_Show = function(which, text, _, data) popup = { which = which, text = text, data = data } end
StaticPopup_Hide = function(which) t.log("hide " .. which) end

local function item(link) return { link = link, IsValid = function() return true end } end

-- The two sell frames, with the methods the Post button and the check use.
local function sellFrames()
	local commodities = { item = item("item:1"), unitPrice = 2000 }
	function commodities:GetItem() return self.item end
	function commodities:GetUnitPrice() return self.unitPrice end
	function commodities:PostItem() t.log("post commodity") end

	local items = { item = item("item:1"), buyout = 2000 }
	function items:GetItem() return self.item end
	function items:GetPrice() return self.bid, self.buyout end
	function items:PostItem() t.log("post item") end

	AuctionHouseFrame = { CommoditiesSellFrame = commodities, ItemSellFrame = items }
	return commodities, items
end

local function post(frame) t.reset() popup = nil frame:PostItem() end

StaticPopupDialogs = {}
t.load("EverlookAuctionWarning")
t.fire("PLAYER_LOGIN")
local W = Everlook:GetAddon("EverlookAuctionWarning")

check(W.db.warn == false, "the warning starts off")

local commodities, items = sellFrames()
local before = commodities.PostItem
t.fire("ADDON_LOADED", "Other")
check(commodities.PostItem == before, "waits for the auction house to load")
t.fire("ADDON_LOADED", "Blizzard_AuctionHouseUI")
check(commodities.PostItem ~= before, "wraps the sell frames once the auction house loads")
local wrapped = commodities.PostItem
W:Hook()
check(commodities.PostItem == wrapped, "wraps a frame only once")

commodities.unitPrice = 100
post(commodities)
check(has("post commodity") and not popup, "off means off")

W.db.warn = true
post(commodities)
check(not has("post commodity") and popup and popup.which == "EVERLOOK_AUCTION_BELOW_VENDOR",
	"asks before posting a commodity below vendor price")
check(popup.text:find("item:1", 1, true) and popup.text:find("10s", 1, true) and popup.text:find("95c", 1, true),
	"names the item, the vendor price and what the auction brings in")
StaticPopupDialogs.EVERLOOK_AUCTION_BELOW_VENDOR.OnAccept(nil, popup.data)
check(has("post commodity"), "Post anyway posts")

commodities.unitPrice = 1053 -- 1000.35 after the cut
post(commodities)
check(has("post commodity") and not popup, "posts without asking at vendor price after the cut")
commodities.unitPrice = 1050 -- 997.5 after the cut
post(commodities)
check(popup ~= nil, "counts the auction house's cut")

t.shift = true
commodities.unitPrice = 100
post(commodities)
t.shift = false
check(has("post commodity") and not popup, "Shift posts without asking")

items.buyout = 5000
post(items)
check(has("post item") and not popup, "posts an item above vendor price")
items.bid = 100
post(items)
check(not has("post item") and popup, "a low bid asks even when the buyout is high")
items.bid, items.buyout = nil, 100
post(items)
check(popup ~= nil, "a low buyout alone asks")

items.item = item("item:2")
post(items)
check(has("post item") and not popup, "items a vendor won't buy post without asking")
items.item = item("battlepet:3")
post(items)
check(has("post item") and not popup, "battle pets post without asking")
items.item = item("item:9")
post(items)
check(has("post item") and not popup, "items the client can't price post without asking")

t.reset()
t.fire("AUCTION_HOUSE_CLOSED")
check(has("hide EVERLOOK_AUCTION_BELOW_VENDOR"), "closing the auction house drops the question")
t.reset()
W.db.warn = false
W:OnSettingChanged("warn", false)
check(has("hide EVERLOOK_AUCTION_BELOW_VENDOR"), "turning it off drops an open question")

-- An auction house that loaded before this addon enabled.
loaded = true
commodities = sellFrames()
local plain = commodities.PostItem
W:OnEnable()
check(commodities.PostItem ~= plain, "wraps an auction house that is already loaded")

t.done()
