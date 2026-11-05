local TakeMail = Everlook:NewAddon("EverlookTakeMail", {
	label = "Take Mail",
	defaults = {
		takeMail = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookTakeMail", {
	"C_Mail.IsCommandPending",
	"GetInboxNumItems",
	"GetInboxHeaderInfo",
	"HasInboxItem",
	"GetInboxItem",
	"TakeInboxMoney",
	"TakeInboxItem",
	"C_Container.GetContainerNumFreeSlots",
	"ATTACHMENTS_MAX_RECEIVE",
	"NUM_BAG_SLOTS",
	"C_Timer.NewTicker",
	"IsShiftKeyDown",
})

local ticker
local open = false
local refused = {} -- item IDs the game refused this visit

function TakeMail:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Bags & Vendors")
	page:Checkbox("takeMail", "Take mail automatically",
		"Take money and items from the mailbox, one letter at a time. Cash-on-delivery mail stays. Hold Shift to stop.")
end

function TakeMail:OnEnable()
	self:RegisterEvent("MAIL_SHOW")
	self:RegisterEvent("MAIL_CLOSED")
	self:RegisterEvent("MAIL_FAILED")
end

local function stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function freeBagSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	return free
end

local function firstItemSlot(index)
	for slot = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
		if HasInboxItem(index, slot) then
			local _, itemID = GetInboxItem(index, slot)
			if not refused[itemID] then return slot end
		end
	end
end

-- One take per tick, and only once the previous one has finished.
-- Reads from the top every time: taking a letter's last thing removes it and the rest move up.
local function tick()
	if not open or IsShiftKeyDown() then
		stop()
		return
	end
	if C_Mail.IsCommandPending() then return end

	local hasRoom = freeBagSlots() > 0
	for index = 1, GetInboxNumItems() do
		local _, _, _, _, money, cod, _, itemCount = GetInboxHeaderInfo(index)
		-- A COD letter, or one whose COD can't be read, stays.
		if cod == 0 then
			if money and money > 0 then
				TakeInboxMoney(index)
				return
			end
			if itemCount and itemCount > 0 and hasRoom then
				local slot = firstItemSlot(index)
				if slot then
					TakeInboxItem(index, slot)
					return
				end
			end
		end
	end
	stop()
end

function TakeMail:MAIL_SHOW()
	open = true
	stop()
	if not self.db.takeMail or IsShiftKeyDown() then return end
	if not (C_Mail and C_Mail.IsCommandPending) then return end
	refused = {}
	ticker = C_Timer.NewTicker(0.15, tick)
end

function TakeMail:MAIL_CLOSED()
	open = false
	stop()
end

function TakeMail:MAIL_FAILED(_, itemID)
	if itemID then
		refused[itemID] = true
	else
		stop()
	end
end
