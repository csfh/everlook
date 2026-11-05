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
	"C_Item.IsItemDataCachedByID",
	"GetInventoryItemLink",
	"C_Container.GetContainerItemLink",
	"C_Container.GetContainerItemInfo",
	"C_Item.GetDetailedItemLevelInfo",
	"C_Item.GetItemQualityColor",
	"Enum.ItemClass.Weapon",
	"Enum.ItemClass.Armor",
	"C_TooltipInfo.GetBagItem",
	"C_TooltipInfo.GetQuestItem",
	"C_TooltipInfo.GetInventoryItem",
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
	"ARMOR_TEMPLATE",
	"DPS_TEMPLATE",
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

-- A game format string such as "%s Armor" as a pattern that captures its number.
local function numberPattern(template)
	local first, last = template:find("%%[%d%.]*[sdf]")
	if not first then return nil end -- a template this can't read, such as a positional %1$s
	local function escape(text) return (text:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0")) end
	return "^" .. escape(template:sub(1, first - 1)) .. "([%d%.,]+)" .. escape(template:sub(last + 1)) .. "$"
end

-- The first tooltip line that matches the pattern, as a number.
local function tooltipNumber(tooltipData, pattern)
	if not tooltipData or not pattern then return nil end
	for _, line in ipairs(tooltipData.lines or {}) do
		local text = line.leftText and line.leftText:match(pattern)
		if text then return tonumber((text:gsub(",", ""))) end
	end
	return nil
end

-- Mainline's GetItemStats leaves out armor, and can leave out DPS, so those come from the tooltip.
local ARMOR = numberPattern(ARMOR_TEMPLATE or "%s Armor")
local DPS = numberPattern(DPS_TEMPLATE or "(%s damage per second)")

-- nil when the item's data hasn't loaded yet. GetItemStats returns nothing for a loaded item with no
-- stats (white and starter gear), so those score on what the tooltip shows. getTooltip is called only
-- when the stats lack armor or DPS.
local function score(link, weapon, getTooltip)
	local stats = C_Item.GetItemStats(link)
	if not stats then
		if not C_Item.IsItemDataCachedByID(link) then return nil end
		stats = {}
	end
	if weapon then
		return stats.ITEM_MOD_DAMAGE_PER_SECOND_SHORT or tooltipNumber(getTooltip(), DPS) or 0
	end
	local total = 0
	for _, value in pairs(stats) do
		total = total + value
	end
	if not stats.RESISTANCE0_NAME then
		total = total + (tooltipNumber(getTooltip(), ARMOR) or 0)
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
	local tooltip, fetched
	local function candidateTooltip()
		if not fetched then tooltip, fetched = getTooltip(), true end
		return tooltip
	end
	local candidate = score(link, weapon, candidateTooltip)
	if not candidate then
		pending = true
		return nil
	end

	local weakest
	for _, slot in ipairs(slots) do
		local equipped = GetInventoryItemLink("player", slot)
		local value = -1 -- empty slot: anything is an upgrade
		if equipped then
			value = score(equipped, weapon, function()
				return C_TooltipInfo and C_TooltipInfo.GetInventoryItem("player", slot)
			end)
			if not value then
				pending = true
				return nil
			end
		end
		if not weakest or value < weakest then
			weakest = value
		end
	end

	return candidate > weakest and usable(candidateTooltip())
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

-- TEMP: a record of what the bag pass sees, saved in EverlookDB.EverlookUpgrades.debug so the next
-- reload writes it to disk. Remove once the missing-arrow bug is found.
local function describeStats(link)
	local ok, stats = pcall(C_Item.GetItemStats, link)
	if not ok then return "error: " .. tostring(stats) end
	if not stats then return "nil (cached=" .. tostring(C_Item.IsItemDataCachedByID(link)) .. ")" end
	local parts = {}
	for key, value in pairs(stats) do parts[#parts + 1] = key .. "=" .. tostring(value) end
	table.sort(parts)
	return "{" .. table.concat(parts, " ") .. "}"
end

local function describeLines(data)
	if not data then return { "no tooltip data" } end
	local out = {}
	for i, line in ipairs(data.lines or {}) do
		local function color(c) return c and string.format("%.2f,%.2f,%.2f", c.r or -1, c.g or -1, c.b or -1) or "-" end
		out[i] = string.format("[type=%s] %s (%s) | %s (%s)", tostring(line.type), tostring(line.leftText), color(line.leftColor),
			tostring(line.rightText), color(line.rightColor))
	end
	return out
end

local fresh = false
local function record()
	local db = Upgrades.db
	if not db then return nil end
	if not fresh then db.debug, fresh = { items = {}, errors = {}, passes = 0 }, true end
	return db.debug
end

function Upgrades:RecordButton(bag, slot, link, result)
	local debug = record()
	if not debug or not link then return end
	local equipLoc = select(4, C_Item.GetItemInfoInstant(link))
	if not SLOTS[equipLoc] then return end
	local entry = { link = link, equipLoc = equipLoc, result = tostring(result), stats = describeStats(link) }
	pcall(function() entry.lines = describeLines(C_TooltipInfo.GetBagItem(bag, slot)) end)
	entry.equipped = {}
	for _, s in ipairs(SLOTS[equipLoc]) do
		local worn = GetInventoryItemLink("player", s)
		if worn then
			local e = { link = worn, stats = describeStats(worn) }
			pcall(function() e.lines = describeLines(C_TooltipInfo.GetInventoryItem("player", s)) end)
			entry.equipped[#entry.equipped + 1] = e
		end
	end
	debug.items[bag .. ":" .. slot] = entry
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
	pcall(self.RecordButton, self, bag, slot, link, show) -- TEMP

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
local reported = false

local function reportOnce(err)
	local debug = record() -- TEMP
	if debug and #debug.errors < 10 then debug.errors[#debug.errors + 1] = tostring(err) end
	if reported then return end
	reported = true
	local handler = geterrorhandler and geterrorhandler()
	if handler then handler(err) end
end
local bagsDirty = false

local bagTask = Everlook.Schedule.Task("upgrades.bags", {
	-- Bag buttons aren't protected, and the budget keeps this light, so it runs in combat too.
	combat = "run",
	step = function(limitMs)
		if bagsDirty or not pass then
			bagsDirty, pending = false, false
			pass = { buttons = bagButtons(), index = 1 }
			local debug = record() -- TEMP
			if debug then
				debug.passes = debug.passes + 1
				debug.lastPass = { time = date and date("%H:%M:%S"), buttons = #pass.buttons, atlas = tostring(C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("bags-greenarrow") ~= nil),
					armorTemplate = tostring(ARMOR_TEMPLATE), dpsTemplate = tostring(DPS_TEMPLATE) }
			end
		end
		local began = debugprofilestop and debugprofilestop()
		local buttons = pass.buttons
		while pass.index <= #buttons do
			-- A button that fails is skipped, not retried, so it can't hold up the rest of the bag.
			local ok, err = pcall(Upgrades.RefreshButton, Upgrades, buttons[pass.index])
			pass.index = pass.index + 1
			if not ok then reportOnce(err) end
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
