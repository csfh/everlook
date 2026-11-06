local SellJunk = Everlook:NewAddon("EverlookSellJunk", {
	label = "Sell Junk",
	defaults = {
		sellGray = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookSellJunk", {
	"C_Container.GetContainerNumSlots",
	"C_Container.GetContainerItemInfo",
	"C_Container.GetContainerItemQuestInfo",
	"C_Container.UseContainerItem",
	"C_Item.GetItemInfo",
	"C_Timer.NewTicker",
	"Enum.ItemQuality.Poor",
	"NUM_BAG_SLOTS",
	"IsShiftKeyDown",
})

local POOR = Enum and Enum.ItemQuality and Enum.ItemQuality.Poor or 0

local ticker, queue
local total = 0
local merchantOpen = false

function SellJunk:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Vendors & Mail")
	page:Checkbox("sellGray", "Sell gray items",
		"Sell gray items when a vendor opens. Quest items stay. Hold Shift to stop.")
end

function SellJunk:OnEnable()
	self:RegisterEvent("MERCHANT_SHOW")
	self:RegisterEvent("MERCHANT_CLOSED")
end

-- Quest items stay, and so does anything whose quest info the client can't read.
local function questItem(bag, slot)
	if not C_Container.GetContainerItemQuestInfo then return true end
	local info = C_Container.GetContainerItemQuestInfo(bag, slot)
	if type(info) ~= "table" then return true end
	return info.isQuestItem == true or (info.questID or 0) > 0
end

local function isJunk(info)
	return info and info.quality == POOR and not info.hasNoValue
end

local function stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	if total > 0 then
		SellJunk:Print("Sold junk for " .. Everlook.FormatMoney(total) .. ".")
	end
	queue, total = nil, 0
end

-- One item per tick, so the server keeps up.
local function tick()
	if not merchantOpen or IsShiftKeyDown() then
		stop()
		return
	end
	while queue and #queue > 0 do
		local entry = table.remove(queue, 1)
		local info = C_Container.GetContainerItemInfo(entry.bag, entry.slot)
		if isJunk(info) and info.itemID == entry.itemID and not info.isLocked then
			local price = select(11, C_Item.GetItemInfo(info.itemID))
			if price and price > 0 then
				total = total + price * (info.stackCount or 1)
				C_Container.UseContainerItem(entry.bag, entry.slot)
				return
			end
		end
	end
	stop()
end

function SellJunk:MERCHANT_SHOW()
	merchantOpen = true
	stop()
	if not self.db.sellGray or IsShiftKeyDown() then return end

	queue = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if isJunk(info) and not questItem(bag, slot) then
				queue[#queue + 1] = { bag = bag, slot = slot, itemID = info.itemID }
			end
		end
	end
	if #queue > 0 then
		ticker = C_Timer.NewTicker(0.15, tick)
	end
end

function SellJunk:MERCHANT_CLOSED()
	merchantOpen = false
	stop()
end
