local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookUpgrades")

hooksecurefunc = function() end

-- link -> { equip location, stats }
local items = {
	sword10 = { "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 10, ITEM_MOD_STRENGTH_SHORT = 50 } },
	sword12 = { "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 12 } },
	sword8 = { "INVTYPE_WEAPON", { ITEM_MOD_DAMAGE_PER_SECOND_SHORT = 8, ITEM_MOD_STRENGTH_SHORT = 99 } },
	helmA = { "INVTYPE_HEAD", { RESISTANCE0_NAME = 20, ITEM_MOD_STAMINA_SHORT = 3 } }, -- 23
	helmB = { "INVTYPE_HEAD", { RESISTANCE0_NAME = 18, ITEM_MOD_STAMINA_SHORT = 6 } }, -- 24
	helmC = { "INVTYPE_HEAD", { RESISTANCE0_NAME = 15, ITEM_MOD_STAMINA_SHORT = 5 } }, -- 20
	boots = { "INVTYPE_FEET", { RESISTANCE0_NAME = 1 } },
	ring5 = { "INVTYPE_FINGER", { ITEM_MOD_STAMINA_SHORT = 5 } },
	ring9 = { "INVTYPE_FINGER", { ITEM_MOD_STAMINA_SHORT = 9 } },
	ring6 = { "INVTYPE_FINGER", { ITEM_MOD_STAMINA_SHORT = 6 } },
	shirt = { "INVTYPE_BODY", { ITEM_MOD_STAMINA_SHORT = 1 } },
	potion = { "", nil },
	uncached = { "INVTYPE_HEAD", nil },
	-- Loaded, but with no stats: GetItemStats returns nothing for these.
	plainCloak = { "INVTYPE_CLOAK", nil },
	plainCloak2 = { "INVTYPE_CLOAK", nil },
	cloak = { "INVTYPE_CLOAK", { ITEM_MOD_AGILITY_SHORT = 2 } },
	-- Starter belts: armor only, which Mainline's GetItemStats leaves out; the tooltip has it.
	raggedBelt = { "INVTYPE_WAIST", nil },
	wornBelt = { "INVTYPE_WAIST", nil },
	flimsyBelt = { "INVTYPE_WAIST", nil },
	club = { "INVTYPE_WEAPON", nil },
}
-- Weapon and armor class IDs, as Enum.ItemClass has them.
-- Line types in Forever's numbering, as its tooltip data showed them (21 slot, 43 level, 41 the
-- combat notice); the real client has more.
Enum = { ItemClass = { Weapon = 2, Armor = 4 },
	TooltipDataLineType = { EquipSlot = 21, RestrictedLevel = 43, RestrictedRaceClass = 44, ItemLevel = 41 } }
local classes = { sword10 = 2, sword12 = 2, sword8 = 2, potion = 0 }
local levels = { sword12 = 27, helmB = 25, helmC = 20, potion = 1 }
local qualityColors = { [2] = { 0.1, 1, 0 }, [3] = { 0, 0.4, 0.8 } }
C_Item = {
	GetItemInfoInstant = function(link) return 1, "", "", items[link][1], nil, classes[link] or 4 end,
	GetItemStats = function(link) return items[link][2] end,
	GetDetailedItemLevelInfo = function(link) return levels[link] end,
	GetItemQualityColor = function(quality) return unpack(qualityColors[quality]) end,
	IsItemDataCachedByID = function(link) return link ~= "uncached" end,
}
local equipped = { [16] = "sword10", [1] = "helmA", [11] = "ring5", [12] = "ring9", [15] = "plainCloak", [6] = "raggedBelt" }
GetInventoryItemLink = function(_, slot) return equipped[slot] end
local function lines(...)
	local data = { lines = {} }
	for _, text in ipairs({ ... }) do data.lines[#data.lines + 1] = { leftText = text, leftColor = { r = 1, g = 1, b = 1 } } end
	return data
end
local tooltips = { raggedBelt = lines("Ragged Leather Belt", "Waist", "18 Armor", "Durability 14 / 16") }
C_TooltipInfo = { GetInventoryItem = function(_, slot) return tooltips[equipped[slot]] end }

t.load("EverlookUpgrades")
t.fire("PLAYER_LOGIN")
local U = Everlook:GetAddon("EverlookUpgrades")

local usable = { lines = { { leftColor = { r = 1, g = 1, b = 1 } } } }
local red = { lines = { { type = 44, leftColor = { r = 1, g = 0.125, b = 0.125 } } } }
local redRight = { lines = { { type = 21, leftColor = { r = 1, g = 1, b = 1 }, rightColor = { r = 1, g = 0.125, b = 0.125 } } } }
local function upgrade(link, tooltip)
	return U:IsUpgrade(link, function() return tooltip or usable end)
end

check(U.db.bags and U.db.quests, "both markers start on")
check(upgrade("sword12") == true, "weapon: higher DPS is an upgrade")
check(upgrade("sword8") == false, "weapon: lower DPS isn't, whatever its stats")
check(upgrade("helmB") == true, "armor: higher stat sum is an upgrade")
check(upgrade("helmC") == false, "armor: lower stat sum isn't")
check(upgrade("boots") == true, "empty slot: anything is an upgrade")
check(upgrade("ring6") == true, "rings: beating the weaker ring is enough")
check(upgrade("ring5") == false, "rings: a tie with the weaker ring isn't")
check(upgrade("helmB", red) == false, "red class restriction: not usable")
check(upgrade("helmB", redRight) == false, "red right-side text (armor type): not usable")
-- Forever's own numbers for the line types, as its tooltip data showed them.
local combatNotice = { lines = {
	{ type = 21, leftText = "Back", leftColor = { r = 1, g = 1, b = 1 } },
	{ type = 41, leftText = "Cannot change equip status while in combat", leftColor = { r = 1, g = 0.13, b = 0.13 } },
} }
local tooLow = { lines = { { type = 43, leftText = "Requires Level 30", leftColor = { r = 1, g = 0.13, b = 0.13 } } } }
local wrongArmor = { lines = { { type = 21, leftText = "Legs", leftColor = { r = 1, g = 1, b = 1 },
	rightText = "Plate", rightColor = { r = 1, g = 0.13, b = 0.13 } } } }
check(upgrade("helmB", combatNotice) == true, "the red combat notice every item carries doesn't make it unusable")
check(upgrade("helmB", tooLow) == false, "a red level requirement does")
check(upgrade("helmB", wrongArmor) == false, "a red armor type beside the slot does")
check(upgrade("shirt") == false and upgrade("potion") == false, "shirts and non-gear are never marked")
check(upgrade("uncached") == nil, "missing item data waits for a refresh")
check(upgrade(nil) == false, "an empty bag slot isn't an upgrade")
check(upgrade("cloak") == true, "worn gear with no stats: anything with stats beats it")
check(upgrade("plainCloak2") == false, "no stats against no stats: loaded, and not an upgrade")
check(upgrade("wornBelt", lines("Worn Leather Belt", "Waist", "22 Armor", "Durability 18 / 18")) == true,
	"armor only: more armor on the tooltip is an upgrade")
check(upgrade("flimsyBelt", lines("Flimsy Belt", "Waist", "12 Armor")) == false, "armor only: less armor isn't")
check(upgrade("club", lines("Club", "One-Hand", "(12.5 damage per second)")) == true,
	"weapon with no DPS stat: the tooltip's DPS line counts")

-- Item level on gear.
check(U.db.itemLevel, "item level starts on")
local text, r, g, b = U:ItemLevelText("sword12", 2)
check(text == "27" and r == 0.1 and g == 1 and b == 0, "weapon: its item level in its quality color")
check(U:ItemLevelText("helmB", 3) == "25", "armor: its item level")
check(U:ItemLevelText("potion", 1) == nil, "non-gear: no label")
check(U:ItemLevelText("uncached", 2) == nil and U:ItemLevelText(nil, 2) == nil, "unknown level or empty slot: no label")
text, r, g, b = U:ItemLevelText("helmB", nil)
check(text == "25" and r == 1 and g == 1 and b == 1, "unknown quality: white")

-- A bag pass puts arrows and item levels on the buttons.
local bagSlots = { [1] = { link = "sword12", quality = 2 }, [2] = { link = "potion", quality = 1 }, [3] = { link = "helmC", quality = 3 } }
C_Container = {
	GetContainerItemLink = function(_, slot) return bagSlots[slot] and bagSlots[slot].link end,
	GetContainerItemInfo = function(_, slot) return bagSlots[slot] and { quality = bagSlots[slot].quality } end,
}
C_TooltipInfo.GetBagItem = function() return usable end
function t.Widget:SetAtlas(atlas) self.atlas = atlas end
function t.Widget:GetBagID() return 0 end
function t.Widget:GetID() return self.slot end
local buttons = {}
-- Bag buttons read unset fields as nil, like game frames do (stub widgets raise on those).
for slot = 1, 3 do
	buttons[slot] = setmetatable({ slot = slot, scripts = {}, events = {} }, { __index = t.Widget })
end
ContainerFrameCombinedBags = t.widget("ContainerFrameCombinedBags")
ContainerFrameCombinedBags:Show()
function ContainerFrameCombinedBags.EnumerateValidItems() return ipairs(buttons) end

U:RefreshBags()
local sword, potion, helm = buttons[1], buttons[2], buttons[3]
check(sword.EverlookUpgradeArrow and sword.EverlookUpgradeArrow:IsShown(), "bag pass: arrow on the upgrade")
check(sword.EverlookItemLevel:GetText() == "27" and sword.EverlookItemLevel.color[1] == 0.1, "bag pass: item level on the weapon")
check(potion.EverlookItemLevel == nil and potion.EverlookUpgradeArrow == nil, "bag pass: nothing on a potion")
check(helm.EverlookItemLevel:IsShown() and not (helm.EverlookUpgradeArrow and helm.EverlookUpgradeArrow:IsShown()),
	"bag pass: item level but no arrow on a worse helm")

t.change("EverlookUpgrades_itemLevel", false)
t.runSchedule()
check(not sword.EverlookItemLevel:IsShown() and not helm.EverlookItemLevel:IsShown(), "turning item level off removes the labels")
check(sword.EverlookUpgradeArrow:IsShown(), "and leaves the arrows")
t.change("EverlookUpgrades_itemLevel", true)
t.runSchedule()
check(sword.EverlookItemLevel:IsShown(), "turning it on again brings them back")

-- A full bag on the shared budget: each button "costs" 0.5 ms, so 1.5 ms a frame does 3 at a time.
for slot = 4, 30 do
	bagSlots[slot] = { link = "helmB", quality = 2 }
	buttons[slot] = setmetatable({ slot = slot, scripts = {}, events = {} }, { __index = t.Widget })
end
local scored = 0
local refreshButton = U.RefreshButton
function U:RefreshButton(button)
	scored = scored + 1
	t.ms = t.ms + 0.5
	return refreshButton(self, button)
end

t.fire("BAG_UPDATE_DELAYED")
Everlook.Schedule.Tick()
check(scored > 0 and scored < 30, "a bag update scores a few buttons a frame, not all at once")
check(buttons[30].EverlookItemLevel == nil, "the rest wait for later frames")
local frames = t.runSchedule()
check(scored == 30 and buttons[30].EverlookItemLevel:GetText() == "25", "the pass finishes over the next frames")
check(frames > 3, "spread over several frames")

scored = 0
t.fire("BAG_UPDATE_DELAYED")
Everlook.Schedule.Tick()
local before = scored
t.fire("BAG_UPDATE_DELAYED") -- something changed mid-pass
t.runSchedule()
check(scored == before + 30, "a trigger mid-pass starts the pass over from the first button")

scored = 0
for _ = 1, 5 do t.fire("BAG_UPDATE_DELAYED") end
t.runSchedule()
check(scored == 30, "a burst of bag updates is one pass")
U.RefreshButton = refreshButton

-- One button that throws doesn't hold up the rest of the bag.
local errors = 0
geterrorhandler = function() return function() errors = errors + 1 end end
for slot = 4, 30 do buttons[slot].EverlookItemLevel:Hide() end
local getLink = C_Container.GetContainerItemLink
C_Container.GetContainerItemLink = function(bag, slot)
	if slot == 2 then error("broken slot") end
	return getLink(bag, slot)
end
t.fire("BAG_UPDATE_DELAYED")
t.runSchedule()
check(buttons[30].EverlookItemLevel:IsShown(), "a button that errors is skipped, and the pass reaches the end")
check(errors == 1, "and its error is reported once")
C_Container.GetContainerItemLink = getLink

t.done()
