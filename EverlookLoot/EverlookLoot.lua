local Loot = Everlook:NewAddon("EverlookLoot", {
	label = "Looting",
	defaults = {
		fasterLoot = false,
		confirmBind = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookLoot", {
	"GetNumLootItems",
	"GetLootSlotInfo",
	"LootSlot",
	"ConfirmLootSlot",
	"IsInGroup",
	"StaticPopup_Show",
	"StaticPopup_Hide",
	"StaticPopupDialogs.LOOT_BIND",
	"hooksecurefunc",
	"GetTime",
	"IsShiftKeyDown",
}, {
	"LE_PARTY_CATEGORY_INSTANCE",
	"issecretvalue",
})

-- LOOT_READY can fire twice for one corpse; the second, this soon after, is skipped.
local REPEAT_SECONDS = 0.3

local lastLoot

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

function Loot:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Bags & Vendors")
	page:Checkbox("fasterLoot", "Faster auto loot",
		"When the game auto loots, take everything as the window opens instead of slot by slot. Follows the game's auto loot setting and its Shift toggle. Items up for a roll are left.")
	page:Checkbox("confirmBind", "Confirm bind-on-pickup loot when alone",
		"Answer the bind-on-pickup prompt for you when you're not in a group. In a group it's left to you. Hold Shift to skip.")
end

function Loot:OnEnable()
	self:RegisterEvent("LOOT_READY")
	self:RegisterEvent("LOOT_CLOSED")
	self:HookBind()
end

-- No Shift check here: Shift is the game's own auto loot toggle, and LOOT_READY's autoloot flag
-- already says what the game decided (the setting with the modifier applied). Off means we leave it.
function Loot:LOOT_READY(_, autoloot)
	if not self.db.fasterLoot or secret(autoloot) or autoloot ~= true then return end
	if not (GetNumLootItems and GetLootSlotInfo and LootSlot and GetTime) then return end
	local now = GetTime()
	if lastLoot and now - lastLoot < REPEAT_SECONDS then return end
	lastLoot = now
	local count = GetNumLootItems()
	if secret(count) or type(count) ~= "number" then return end
	-- From the last slot down, so taking one doesn't move the ones still to take.
	for slot = count, 1, -1 do
		local texture, _, _, _, _, locked = GetLootSlotInfo(slot)
		if not secret(texture) and not secret(locked) and texture and not locked then
			LootSlot(slot)
		end
	end
end

function Loot:LOOT_CLOSED()
	lastLoot = nil
end

-- A missing IsInGroup counts as a group, so the prompt stays with the player.
local function alone()
	if not IsInGroup then return false end
	if IsInGroup() then return false end
	if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return false end
	return true
end

-- UIParent shows the LOOT_BIND popup on LOOT_BIND_CONFIRM, and its handler may run before or after
-- ours, so the answer goes on the popup itself once it's up (StaticPopup_Show's data is the slot).
-- Someone Shift-looting with auto loot off holds Shift, so they get the prompt.
function Loot:HookBind()
	if self.bindHooked or not (hooksecurefunc and StaticPopup_Show) then return end
	hooksecurefunc("StaticPopup_Show", function(which, _, _, slot)
		if which ~= "LOOT_BIND" or not self.db.confirmBind or IsShiftKeyDown() then return end
		if secret(slot) or type(slot) ~= "number" or not alone() or not ConfirmLootSlot then return end
		ConfirmLootSlot(slot)
		StaticPopup_Hide("LOOT_BIND")
	end)
	self.bindHooked = true
end
