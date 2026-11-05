local Upgrades = Everlook:NewAddon("EverlookUpgrades", {
	label = "Upgrades",
	defaults = {
		bags = true,
		quests = true,
		itemLevel = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookUpgrades", {
	"C_Item.GetItemStats",
	"C_Item.GetItemInfoInstant",
	"GetInventoryItemLink",
	"C_Container.GetContainerItemLink",
	"C_Container.GetContainerItemInfo",
	"C_Item.GetDetailedItemLevelInfo",
	"C_Item.GetItemQualityColor",
	"Enum.ItemClass.Weapon",
	"Enum.ItemClass.Armor",
	"C_TooltipInfo.GetBagItem",
	"C_TooltipInfo.GetQuestItem",
	"ContainerFrameCombinedBags.EnumerateValidItems",
	"ContainerFrameCombinedBags.UpdateItems",
	"ContainerFrame1.EnumerateValidItems",
	"ContainerFrame1.UpdateItems",
	"hooksecurefunc",
	"GetNumQuestChoices",
	"GetNumQuestRewards",
	"GetQuestItemLink",
	"QuestInfoFrame.rewardsFrame",
	"QuestInfo_GetRewardButton",
	"debugprofilestop",
}, {
	"C_Texture.GetAtlasInfo",
})

local RANGED_SLOT = INVSLOT_RANGED or 16

-- Equip location -> inventory slots it competes with.
local SLOTS = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { RANGED_SLOT },
	INVTYPE_RANGEDRIGHT = { RANGED_SLOT },
	INVTYPE_THROWN = { RANGED_SLOT },
}

-- Compared by DPS; everything else by the sum of its stats.
local WEAPONS = {
	INVTYPE_WEAPON = true,
	INVTYPE_2HWEAPON = true,
	INVTYPE_WEAPONMAINHAND = true,
	INVTYPE_WEAPONOFFHAND = true,
	INVTYPE_RANGED = true,
	INVTYPE_RANGEDRIGHT = true,
	INVTYPE_THROWN = true,
}

-- nil when the item's data hasn't loaded yet.
local function score(link, weapon)
	local stats = C_Item.GetItemStats(link)
	if not stats then return nil end
	if weapon then
		return stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or 0
	end
	local total = 0
	for _, value in pairs(stats) do
		total = total + value
	end
	return total
end

-- Red tooltip text means the player can't use it (armor type, level, class).
local function isRed(color)
	return color and color.r > 0.99 and color.g < 0.2 and color.b < 0.2
end

local function usable(tooltipData)
	if not tooltipData then return true end
	for _, line in ipairs(tooltipData.lines or {}) do
		if isRed(line.leftColor) or isRed(line.rightColor) then
			return false
		end
	end
	return true
end

local pending = false

-- true/false, or nil when some data isn't loaded yet (a refresh is scheduled).
function Upgrades:IsUpgrade(link, getTooltip)
	if not link then return false end
	local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
	local slots = SLOTS[equipLoc]
	if not slots then return false end

	local weapon = WEAPONS[equipLoc]
	local candidate = score(link, weapon)
	if not candidate then
		pending = true
		return nil
	end

	local weakest
	for _, slot in ipairs(slots) do
		local equipped = GetInventoryItemLink("player", slot)
		local value = -1 -- empty slot: anything is an upgrade
		if equipped then
			value = score(equipped, weapon)
			if not value then
				pending = true
				return nil
			end
		end
		if not weakest or value < weakest then
			weakest = value
		end
	end

	return candidate > weakest and usable(getTooltip())
end

local function setArrow(button, show)
	if not button then return end
	local arrow = button.EverlookUpgradeArrow
	if not show then
		if arrow then arrow:Hide() end
		return
	end
	if not arrow then
		arrow = button:CreateTexture(nil, "OVERLAY", nil, 7)
		if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-greenarrow") then
			arrow:SetAtlas("bags-greenarrow")
		else
			arrow:SetTexture("Interface\\Buttons\\UI-MicroStream-Green")
		end
		arrow:SetSize(14, 14)
		arrow:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
		button.EverlookUpgradeArrow = arrow
	end
	arrow:Show()
end

-- Item level on gear ------------------------------------------------------

-- The item level label for a weapon or piece of armor (rings, trinkets and cloaks included), in the
-- color of its quality: text, r, g, b. Nil for anything else, or when the level isn't known.
function Upgrades:ItemLevelText(link, quality)
	if not link then return nil end
	local classID = select(6, C_Item.GetItemInfoInstant(link))
	if classID ~= Enum.ItemClass.Weapon and classID ~= Enum.ItemClass.Armor then return nil end
	local level = C_Item.GetDetailedItemLevelInfo(link)
	if type(level) ~= "number" or level <= 1 then return nil end
	local r, g, b = 1, 1, 1
	if type(quality) == "number" then
		r, g, b = C_Item.GetItemQualityColor(quality)
	end
	return tostring(math.floor(level)), r, g, b
end

-- Where a stack count would sit; gear doesn't stack.
local function setItemLevel(button, text, r, g, b)
	local label = button.EverlookItemLevel
	if not text then
		if label then label:Hide() end
		return
	end
	if not label then
		label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		label:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -2, 2)
		button.EverlookItemLevel = label
	end
	label:SetText(text)
	label:SetTextColor(r, g, b)
	label:Show()
end

-- Bags --------------------------------------------------------------------

local function bagFrames()
	local frames = {}
	if ContainerFrameCombinedBags then
		frames[#frames + 1] = ContainerFrameCombinedBags
	end
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame then frames[#frames + 1] = frame end
	end
	return frames
end

-- The item buttons of every open bag window.
local function bagButtons()
	local buttons = {}
	for _, frame in ipairs(bagFrames()) do
		if frame:IsShown() and frame.EnumerateValidItems then
			for _, button in frame:EnumerateValidItems() do
				buttons[#buttons + 1] = button
			end
		end
	end
	return buttons
end

-- Arrow and item level for one bag button.
function Upgrades:RefreshButton(button)
	local bag, slot = button:GetBagID(), button:GetID()
	local link = C_Container.GetContainerItemLink(bag, slot)
	local show = false
	if self.db.bags then
		show = self:IsUpgrade(link, function()
			return C_TooltipInfo and C_TooltipInfo.GetBagItem(bag, slot)
		end)
	end
	setArrow(button, show)

	if self.db.itemLevel then
		local info = C_Container.GetContainerItemInfo(bag, slot)
		setItemLevel(button, self:ItemLevelText(link, info and info.quality))
	else
		setItemLevel(button, nil)
	end
end

-- Every open bag button at once.
function Upgrades:RefreshBags()
	pending = false
	for _, button in ipairs(bagButtons()) do
		self:RefreshButton(button)
	end
end

-- The same pass, a few buttons a frame on the shared budget. Each button can scan a tooltip, so a
-- full bag at once could take several milliseconds. A trigger mid-pass starts it over from the top.
local pass -- { buttons, index } while a pass is under way
local bagsDirty = false

local bagTask = Everlook.Schedule.Task("upgrades.bags", {
	-- Bag buttons aren't protected, and the budget keeps this light, so it runs in combat too.
	combat = "run",
	step = function(limitMs)
		if bagsDirty or not pass then
			bagsDirty, pending = false, false
			pass = { buttons = bagButtons(), index = 1 }
		end
		local began = debugprofilestop and debugprofilestop()
		local buttons = pass.buttons
		while pass.index <= #buttons do
			Upgrades:RefreshButton(buttons[pass.index])
			pass.index = pass.index + 1
			if not began or debugprofilestop() - began >= limitMs then break end
		end
		if pass.index <= #buttons then return true end
		pass = nil
		return bagsDirty
	end,
})

-- Quest rewards -----------------------------------------------------------

local questButtons = {}

local function hideQuestArrows()
	for button in pairs(questButtons) do
		setArrow(button, false)
	end
end

function Upgrades:RefreshQuest()
	hideQuestArrows()
	if not self.db.quests or not QuestInfoFrame or not QuestInfoFrame.rewardsFrame then return end

	local numChoices = GetNumQuestChoices()
	local function check(kind, index, buttonIndex)
		local button = QuestInfo_GetRewardButton(QuestInfoFrame.rewardsFrame, buttonIndex)
		if not button then return end
		questButtons[button] = true
		setArrow(button, self:IsUpgrade(GetQuestItemLink(kind, index), function()
			return C_TooltipInfo and C_TooltipInfo.GetQuestItem(kind, index)
		end))
	end

	for i = 1, numChoices do
		check("choice", i, i)
	end
	for i = 1, GetNumQuestRewards() do
		check("reward", i, numChoices + i)
	end
end

-- Wiring -----------------------------------------------------------------

local questOpen = false

-- Bags on the scheduled pass; quest rewards on the next frame, once the quest window has laid
-- out its buttons. A burst of triggers is one pass and one quest refresh.
local function refreshSoon()
	bagsDirty = true
	bagTask:Wake()
	if questOpen then
		Everlook.Schedule.Defer("upgrades.quest", function() Upgrades:RefreshQuest() end)
	end
end

function Upgrades:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Bags & Vendors")
	page:Checkbox("bags", "Mark upgrades in bags", "Green arrow on bag items that beat what you have equipped.")
	page:Checkbox("quests", "Mark upgrades in quest rewards", "Green arrow on quest rewards that beat what you have equipped.")
	page:Checkbox("itemLevel", "Show item level on gear",
		"Writes the item level on weapons and armor in your bags, in the color of their quality.")
end

function Upgrades:OnSettingChanged()
	refreshSoon()
end

function Upgrades:OnEnable()
	for _, frame in ipairs(bagFrames()) do
		if frame.UpdateItems then
			hooksecurefunc(frame, "UpdateItems", refreshSoon)
		end
	end
	self:RegisterEvent("BAG_UPDATE_DELAYED", refreshSoon)
	self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", refreshSoon)
	self:RegisterEvent("GET_ITEM_INFO_RECEIVED", function()
		if pending then refreshSoon() end
	end)
	self:RegisterEvent("QUEST_DETAIL", "OnQuestShown")
	self:RegisterEvent("QUEST_COMPLETE", "OnQuestShown")
	self:RegisterEvent("QUEST_FINISHED", function()
		questOpen = false
		hideQuestArrows()
	end)
end

function Upgrades:OnQuestShown()
	questOpen = true
	refreshSoon()
end
