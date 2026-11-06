local UsefulTooltips = Everlook:NewAddon("EverlookUsefulTooltips", {
	label = "Useful Tooltips",
	defaults = {
		itemIDs = true,
		npcIDs = true,
		vendorPrice = true,
		bagTotal = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookUsefulTooltips", {
	"TooltipDataProcessor.AddTooltipPostCall",
	"Enum.TooltipDataType.Item",
	"Enum.TooltipDataType.Unit",
	"GameTooltip",
	"ItemRefTooltip",
	"C_Item.GetItemInfo",
	"C_Item.GetItemCount",
	"UnitGUID",
})

function UsefulTooltips:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Tooltips")
	page:Checkbox("itemIDs", "Show item IDs", "Adds the item ID to item tooltips.")
	page:Checkbox("npcIDs", "Show NPC IDs", "Adds the NPC ID to creature tooltips.")
	page:Checkbox("vendorPrice", "Show vendor price", "Adds what a vendor pays for one of the item.")
	page:Checkbox("bagTotal", "Show bag count and total value",
		"When you carry more than one, adds how many are in your bags and what a vendor pays for all of them.")
end

-- A hidden (secret) value adds nothing.
local function readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

-- Only the main tooltip and a clicked item link get lines, so comparison tooltips don't repeat them.
local function wanted(tooltip)
	return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

-- The NPC ID from a creature or vehicle GUID: "Creature-0-1-2-3-<npcID>-<spawn>".
function UsefulTooltips.NpcID(guid)
	if type(guid) ~= "string" then return nil end
	local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
	if kind == "Creature" or kind == "Vehicle" then
		return tonumber(id)
	end
end

function UsefulTooltips:AddItemLines(tooltip, data)
	if not wanted(tooltip) then return end
	local itemID = data and data.id
	if not readable(itemID) or type(itemID) ~= "number" then return end
	local db = self.db

	if db.itemIDs then
		tooltip:AddLine("Item ID: " .. itemID, 0.6, 0.8, 1)
	end
	local price = select(11, C_Item.GetItemInfo(itemID))
	if type(price) ~= "number" or price <= 0 then return end
	if db.vendorPrice then
		tooltip:AddLine("Vendor: " .. Everlook.FormatMoney(price), 0.8, 0.8, 0.8)
	end
	if db.bagTotal then
		local count = C_Item.GetItemCount(itemID, false)
		if type(count) == "number" and count > 1 then
			tooltip:AddLine("In bags: " .. count .. " (" .. Everlook.FormatMoney(price * count) .. ")", 0.8, 0.8, 0.8)
		end
	end
end

function UsefulTooltips:AddUnitLines(tooltip, data)
	if not wanted(tooltip) or not self.db.npcIDs then return end
	local guid = data and data.guid
	if not readable(guid) then
		local _, unit = tooltip:GetUnit()
		guid = unit and UnitGUID(unit)
		if not readable(guid) then return end
	end
	local npcID = UsefulTooltips.NpcID(guid)
	if npcID then
		tooltip:AddLine("NPC ID: " .. npcID, 0.6, 0.8, 1)
	end
end

function UsefulTooltips:OnEnable()
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		self:AddItemLines(tooltip, data)
	end)
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		self:AddUnitLines(tooltip, data)
	end)
end
