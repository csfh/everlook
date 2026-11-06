local Containers = Everlook:NewAddon("EverlookContainers", {
	label = "Containers",
	defaults = {
		open = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookContainers", {
	"C_Container.GetContainerNumSlots",
	"C_Container.GetContainerItemInfo",
	"C_Container.UseContainerItem",
	"C_Item.GetItemGUID",
	"C_Item.DoesItemExist",
	"ItemLocation.CreateFromBagAndSlot",
	"C_Timer.NewTicker",
	"IsShiftKeyDown",
	"InCombatLockdown",
	"CursorHasItem",
	"GetCursorInfo",
	"SpellCanTargetItem",
	"SpellCanTargetItemID",
	"GetNumLootItems",
	"GetLootSlotInfo",
	"GetLootSourceInfo",
	"LootSlot",
	"LootFrame",
	"NUM_BAG_SLOTS",
})

-- UseContainerItem also sells, banks, trades and attaches to mail, so any of these windows pauses it.
local BUSY_FRAMES = { "MerchantFrame", "BankFrame", "MailFrame", "TradeFrame", "GuildBankFrame", "AuctionHouseFrame" }

local ticker, pending
local lootOpen, takingLoot = false, false
local quiet = {} -- [item GUID] = stack count already tried that opened no loot window

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

-- Every function this needs, or nothing happens.
local function apiReady()
	return type(C_Container) == "table"
		and type(C_Container.GetContainerNumSlots) == "function"
		and type(C_Container.GetContainerItemInfo) == "function"
		and type(C_Container.UseContainerItem) == "function"
		and type(C_Item) == "table" and type(C_Item.GetItemGUID) == "function"
		and type(C_Item.DoesItemExist) == "function"
		and type(ItemLocation) == "table" and type(ItemLocation.CreateFromBagAndSlot) == "function"
		and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function"
		and type(IsShiftKeyDown) == "function" and type(InCombatLockdown) == "function"
		and type(CursorHasItem) == "function" and type(GetCursorInfo) == "function"
		and type(SpellCanTargetItem) == "function" and type(SpellCanTargetItemID) == "function"
		and type(GetNumLootItems) == "function" and type(GetLootSlotInfo) == "function"
		and type(GetLootSourceInfo) == "function" and type(LootSlot) == "function"
		and type(LootFrame) == "table" and type(LootFrame.IsShown) == "function"
end

local function blocked()
	if not apiReady() or not Containers.db.open or IsShiftKeyDown() or InCombatLockdown() then return true end
	if CursorHasItem() or GetCursorInfo() ~= nil or SpellCanTargetItem() or SpellCanTargetItemID() then return true end
	for _, name in ipairs(BUSY_FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown() then return true end
	end
	return false
end

local function lootCount()
	local count = GetNumLootItems()
	if secret(count) or type(count) ~= "number" then return end
	return count
end

local function itemGUID(bag, slot)
	local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
	if not C_Item.DoesItemExist(location) then return end
	local guid = C_Item.GetItemGUID(location)
	if secret(guid) or type(guid) ~= "string" or guid == "" then return end
	return guid
end

-- LOOT_OPENED can't say which bag item opened the window, so a loot slot is ours only when every
-- source GetLootSourceInfo names (GUID, quantity, GUID, quantity, ...) is the container we used.
local function ownSlot(slot, guid)
	local sources = { GetLootSourceInfo(slot) }
	if #sources == 0 then return false end
	for index = 1, #sources, 2 do
		if secret(sources[index]) or sources[index] ~= guid then return false end
	end
	return true
end

local function takeLoot(guid)
	local count = lootCount()
	if not count then return end
	takingLoot = true
	for slot = count, 1, -1 do
		if not lootOpen or blocked() then break end
		local texture, _, _, _, _, locked = GetLootSlotInfo(slot)
		if not secret(texture) and not secret(locked) and texture and not locked and ownSlot(slot, guid) then
			LootSlot(slot)
		end
	end
	takingLoot = false
end

local function bagCount()
	local bags = NUM_BAG_SLOTS or 4
	if type(NUM_REAGENTBAG_SLOTS) == "number" and NUM_REAGENTBAG_SLOTS > 0 then
		bags = bags + NUM_REAGENTBAG_SLOTS
	end
	return bags
end

-- The first unlocked container with loot whose stack hasn't already failed to open.
local function findContainer()
	for bag = 0, bagCount() do
		local slots = C_Container.GetContainerNumSlots(bag)
		if secret(slots) or type(slots) ~= "number" then return end
		for slot = 1, slots do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if type(info) == "table" and not secret(info.hasLoot) and not secret(info.isLocked)
				and info.hasLoot and not info.isLocked then
				local guid = itemGUID(bag, slot)
				local count = not secret(info.stackCount) and type(info.stackCount) == "number" and info.stackCount
				if guid and count and quiet[guid] ~= count then return bag, slot, guid, count end
			end
		end
	end
end

local function stop()
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	pending = nil
end

-- One container per tick, and only while no loot window is open.
local function tick()
	if not Containers.db.open or not apiReady() then
		stop()
		return
	end
	if takingLoot or blocked() then return end
	local count = lootCount()
	if not count or lootOpen or count > 0 or LootFrame:IsShown() then return end
	if pending then
		if itemGUID(pending.bag, pending.slot) ~= pending.guid then
			pending = nil
		else
			-- Used, but no loot window after three ticks: a locked box or one that doesn't loot.
			pending.waits = pending.waits + 1
			if pending.waits < 3 then return end
			quiet[pending.guid] = pending.count
			pending = nil
		end
	end
	local bag, slot, guid, stack = findContainer()
	if not bag then
		stop()
		return
	end
	pending = { bag = bag, slot = slot, guid = guid, count = stack, waits = 0 }
	C_Container.UseContainerItem(bag, slot)
end

local function start()
	if not Containers.db.open or not apiReady() or takingLoot then return end
	if not ticker then ticker = C_Timer.NewTicker(0.2, tick) end
	tick()
end

function Containers:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Bags & Loot")
	page:Checkbox("open", "Open containers",
		"Open clams, crates and other containers in your bags and take what's inside. Pauses in combat, while you hold Shift, and while a vendor, bank, mail, trade or auction window is open.")
end

function Containers:OnEnable()
	for _, event in ipairs({ "BAG_UPDATE_DELAYED", "LOOT_CLOSED", "PLAYER_REGEN_ENABLED", "MERCHANT_CLOSED",
		"BANKFRAME_CLOSED", "MAIL_CLOSED", "TRADE_CLOSED" }) do
		self:RegisterEvent(event, "OnBagsChanged")
	end
	self:RegisterEvent("LOOT_OPENED")
	start()
end

function Containers:OnBagsChanged(event)
	if event == "LOOT_CLOSED" then lootOpen = false end
	start()
end

function Containers:LOOT_OPENED(_, _, fromItem)
	lootOpen = true
	local opened = pending
	pending = nil
	if not opened then return end
	-- This stack isn't opened again unchanged, whether or not the loot was ours to take.
	quiet[opened.guid] = opened.count
	if not secret(fromItem) and fromItem == true and not blocked() then takeLoot(opened.guid) end
end

function Containers:OnSettingChanged(key, value)
	if key ~= "open" then return end
	if value then
		start()
	else
		quiet, lootOpen = {}, false
		stop()
	end
end
