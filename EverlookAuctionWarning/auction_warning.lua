local AuctionWarning = Everlook:NewAddon("EverlookAuctionWarning", {
	label = "Auction Warning",
	defaults = {
		warn = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist. The auction house frames load on
-- demand, after login, so they are not listed.
EverlookQA:Expect("EverlookAuctionWarning", {
	"C_AddOns.IsAddOnLoaded",
	"C_Item.GetItemInfo",
	"C_Item.GetItemLink",
	"StaticPopup_Show",
	"StaticPopup_Hide",
	"StaticPopupDialogs",
	"IsShiftKeyDown",
}, {
	"LinkUtil.IsLinkType",
})

-- The auction house keeps 5% of a sale. The client has no constant for it
-- (AuctionHouseConstantsDocumentation.lua, 12.0.0, lists only the default price multiplier).
local CUT = 0.05

local POPUP = "EVERLOOK_AUCTION_BELOW_VENDOR"

function AuctionWarning:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Vendors & Mail")
	page:Checkbox("warn", "Warn before posting below vendor price",
		"Ask before posting an auction whose bid or buyout, after the auction house's 5% cut, brings in less than a vendor pays for the item. Hold Shift while clicking Post to skip the question.")
end

-- The lowest price per item the auction can sell at: the bid if there is one, else the buyout.
-- AuctionHouseCommoditiesSellFrameMixin:GetUnitPrice and AuctionHouseItemSellFrameMixin:GetPrice
-- (Blizzard_AuctionHouseUI/Shared, 12.0.0) are both per item.
local function lowestPrice(frame)
	if frame.GetUnitPrice then return frame:GetUnitPrice() end
	if frame.GetPrice then
		local bid, buyout = frame:GetPrice()
		return bid or buyout
	end
end

-- What a vendor pays for one of the item, or nil when the client can't say (not cached yet,
-- a battle pet, or worth nothing to a vendor).
local function vendorPrice(item)
	if not (item and item.IsValid and item:IsValid()) then return nil end
	local link = C_Item.GetItemLink(item)
	if type(link) ~= "string" then return nil end
	if LinkUtil and LinkUtil.IsLinkType and not LinkUtil.IsLinkType(link, "item") then return nil end
	local price = select(11, C_Item.GetItemInfo(link))
	if type(price) ~= "number" or price <= 0 then return nil end
	return price, link
end

-- The figures for a warning when posting from this sell frame would earn less than a vendor pays.
function AuctionWarning.Check(frame)
	local vendor, link = vendorPrice(frame.GetItem and frame:GetItem())
	if not vendor then return nil end
	local price = lowestPrice(frame)
	if type(price) ~= "number" or price <= 0 then return nil end
	local earned = math.floor(price * (1 - CUT))
	if earned >= vendor then return nil end
	return { link = link, vendor = vendor, earned = earned }
end

function AuctionWarning.Text(found)
	return found.link .. " sells to a vendor for " .. Everlook.FormatMoney(found.vendor)
		.. " each.\n\nAt this price you get " .. Everlook.FormatMoney(found.earned)
		.. " each after the auction house's cut.\n\nPost anyway?"
end

StaticPopupDialogs[POPUP] = {
	text = "%s",
	button1 = "Post anyway",
	button2 = CANCEL or "Cancel",
	OnAccept = function(_, data)
		if data and data.post then data.post(data.frame) end
	end,
	showAlert = true,
	hideOnEscape = 1,
	timeout = 0,
	whileDead = 1,
}

-- The Post button calls its sell frame's PostItem (AuctionHouseSellFramePostButtonMixin:OnClick).
-- The XML mixin copies PostItem onto each frame, so the wrapper goes on the frame itself. The popup's
-- Post anyway button calls the original, so a click still starts the post.
local function guard(frame)
	if not frame or frame.everlookAuctionWarning or type(frame.PostItem) ~= "function" then return end
	local post = frame.PostItem
	frame.everlookAuctionWarning = true
	frame.PostItem = function(self, ...)
		if AuctionWarning.db.warn and not IsShiftKeyDown() then
			local found = AuctionWarning.Check(self)
			if found then
				StaticPopup_Show(POPUP, AuctionWarning.Text(found), nil, { frame = self, post = post })
				return
			end
		end
		return post(self, ...)
	end
end

function AuctionWarning:Hook()
	local house = AuctionHouseFrame
	if not house then return end
	guard(house.ItemSellFrame)
	guard(house.CommoditiesSellFrame)
end

function AuctionWarning:OnEnable()
	self:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_AuctionHouseUI" then self:Hook() end
	end)
	self:RegisterEvent("AUCTION_HOUSE_CLOSED", function() StaticPopup_Hide(POPUP) end)
	if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_AuctionHouseUI") then
		self:Hook()
	end
end

function AuctionWarning:OnSettingChanged(key, value)
	if key == "warn" and not value then StaticPopup_Hide(POPUP) end
end
