-- The grouped combined bag on real frames: where the chips, the search box, the headers and the grid
-- end up, in the harness's anchors and with its text widths. The bag itself is a stand-in for the game's
-- (the harness has no Blizzard XML for it), laid out the way ContainerFrame.lua lays it out. The money
-- frame's anchors are the game's (ContainerFrame.lua:2496); the bag's height and its place on the screen
-- are assumed, so no vertical gap here is read from the client.
harness.include("lib/game.lua")

local SLOT_TOTAL, STOCK_COLUMNS, STEP = 20, 10, 42
local PORTRAIT_CLEARANCE = 62

-- Armor and a weapon, a potion, a grey item and the empty slots, as in a fresh bag.
local items = {
	[1] = { class = 4, quality = 4 }, [2] = { class = 2, quality = 3 }, [3] = { class = 0, quality = 1 },
	[4] = { class = 15, quality = 0 }, [5] = { class = 15, quality = 1 }, [6] = { class = 7, quality = 1 },
}
game.bags = { [0] = SLOT_TOTAL - 6 }
C_Container.GetContainerItemInfo = function(bag, slot)
	local item = items[slot]
	if bag == 0 and item then
		return { itemID = 1000 + slot, hyperlink = "link" .. slot, quality = item.quality, stackCount = 1 }
	end
end
C_Container.GetContainerNumSlots = function() return SLOT_TOTAL end
Enum = Enum or {}
Enum.ItemClass = {
	Consumable = 0, Weapon = 2, Gem = 3, Armor = 4, Reagent = 5, Tradegoods = 7, ItemEnhancement = 8,
	Recipe = 9, Questitem = 12, Key = 13, Miscellaneous = 15, Profession = 19,
}
C_Item = {
	GetItemInfoInstant = function(item_id) return item_id, nil, nil, nil, nil, items[item_id - 1000].class end,
	GetItemInfo = function() return end,
	GetDetailedItemLevelInfo = function() return 1 end,
}
-- Sizes the client gives these atlases are not known here: a larger arrow than the module was written
-- for shows whether the title still clears it.
C_Texture = { GetAtlasInfo = function(atlas)
	if atlas == "Options_HorizontalDivider" then return { width = 330, height = 3 } end
	if atlas == "campaign_headericon_open" or atlas == "campaign_headericon_closed" then return { width = 22, height = 22 } end
end }

-- The stock bag: ten columns of 37 pixel slots five apart, a search box at the top left, money at the bottom.
local frame = CreateFrame("Frame", "ContainerFrameCombinedBags", UIParent)
frame.MoneyFrame = CreateFrame("Frame", nil, frame)
frame.MoneyFrame:SetHeight(16)
-- As ContainerFrame.lua:2496 anchors it when no token tracker is shown: across the bag, eight in from each side.
frame.MoneyFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 8, 8)
frame.MoneyFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8)
local box = CreateFrame("EditBox", "BagItemSearchBox", frame)
box:SetHeight(20)
frame.buttons = {}
for index = 1, SLOT_TOTAL do
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(37, 37)
	button.slot = index
	function button:GetBagID() return 0 end
	function button:GetID() return self.slot end
	function button:IsExtended() return false end
	function button:IsMouseOver() return false end
	frame.buttons[index] = button
end
function frame:EnumerateValidItems()
	return function(container, index)
		index = index + 1
		if container.buttons[index] then return index, container.buttons[index] end
	end, self, 0
end
function frame:SetSearchBoxPoint(target)
	target:SetPoint("TOPLEFT", self, "TOPLEFT", PORTRAIT_CLEARANCE, -37)
	target:SetWidth(330)
end
function frame:UpdateSearchBox()
	box:ClearAllPoints()
	self:SetSearchBoxPoint(box)
	box.anchorBag = self
end
function frame:UpdateItemLayout()
	local rows = math.ceil(SLOT_TOTAL / STOCK_COLUMNS)
	self:SetSize(430, rows * STEP - 5 + 75 + 28)
	for index, button in ipairs(self.buttons) do
		button:ClearAllPoints()
		button:SetPoint("BOTTOMRIGHT", self.MoneyFrame, "TOPRIGHT", -((index - 1) % STOCK_COLUMNS) * STEP, 4 + math.floor((index - 1) / STOCK_COLUMNS) * STEP)
	end
end
function frame:UpdateItems() end
frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -40, 90)
frame:UpdateSearchBox()
frame:UpdateItemLayout()
frame:Show()
box:Show()

harness.load_addon("Everlook")
harness.load_addon("Everlook_Bags")
game.login()
local screen = harness.rect(UIParent)
local stock_width = harness.rect(frame).width

local function bounds(rect) return rect.left, rect.top, rect.left + rect.width, rect.top + rect.height end
local function inside(inner, outer)
	local left, top, right, bottom = bounds(inner)
	local outer_left, outer_top, outer_right, outer_bottom = bounds(outer)
	return left >= outer_left - 0.5 and top >= outer_top - 0.5 and right <= outer_right + 0.5 and bottom <= outer_bottom + 0.5
end
local function overlap(first, second)
	local left, top, right, bottom = bounds(first)
	local other_left, other_top, other_right, other_bottom = bounds(second)
	return left < other_right - 0.5 and other_left < right - 0.5 and top < other_bottom - 0.5 and other_top < bottom - 0.5
end
local function shown_children(parent, kind)
	local found = {}
	for _, child in ipairs(harness.frames()) do
		if child:GetParent() == parent and child:IsShown() and (kind == nil or child:GetObjectType() == kind) then found[#found + 1] = child end
	end
	return found
end
local function text_of(child)
	for _, region in ipairs({ child:GetRegions() }) do
		if region.GetText and region:GetText() ~= nil then return region end
	end
end

local function settle()
	frame:UpdateSearchBox()
	frame:UpdateItemLayout()
	frame:UpdateItems()
	harness.advance(0.1)
end

Everlook.module.set("bags", "enabled", true)
Everlook.module.set("bags", "group", true)
settle()

-- Grouped, no chips: the bag is as wide as stock draws it and the search box meets the grid's right edge.
do
	local bag, search, money = harness.rect(frame), harness.rect(box), harness.rect(frame.MoneyFrame)
	harness.check("grouped at ten columns the bag is as wide as stock", bag.width == stock_width)
	harness.check("the search box reaches the grid's right edge", math.abs((search.left + search.width) - (money.left + money.width)) < 0.5)
	harness.check("the search box keeps clear of the portrait", search.left - bag.left >= PORTRAIT_CLEARANCE - 0.5)
	harness.check("every slot is inside the bag", (function()
		for _, button in ipairs(frame.buttons) do if not inside(harness.rect(button), bag) then return false end end
		return true
	end)())
	harness.check("the bag fits on the screen", inside(bag, screen))
end

-- Free Space is one live slot by default: the rest are parked clear, and the bag is that much shorter.
local function drawn()
	local count = 0
	for _, button in ipairs(frame.buttons) do
		if button:GetAlpha() > 0 then count = count + 1 end
	end
	return count
end
do
	local collapsed_height = harness.rect(frame).height
	harness.check("by default one of the fourteen free slots is drawn, with the six items", drawn() == 7)
	Everlook.module.set("bags", "all_free", true)
	settle()
	harness.check("asking for every free slot draws all twenty", drawn() == SLOT_TOTAL)
	harness.check("and makes the bag taller by the extra row", harness.rect(frame).height > collapsed_height)
	Everlook.module.set("bags", "all_free", false)
	settle()
	harness.check("turning it off draws one again", drawn() == 7 and harness.rect(frame).height == collapsed_height)
end

-- Fold on: the arrow and the title do not overlap, whatever the arrow's size.
Everlook.module.set("bags", "fold", true)
settle()
do
	local headers = {}
	for _, child in ipairs(shown_children(frame, "Button")) do
		local title = text_of(child)
		if title and child:GetHeight() == 20 then headers[#headers + 1] = child end
	end
	harness.check("a header is shown for each section that has slots", #headers == 6)
	local clear = true
	for _, header in ipairs(headers) do
		local arrow
		for _, region in ipairs({ header:GetRegions() }) do
			if region.GetAtlas and region:GetAtlas() == "campaign_headericon_open" and region:IsShown() then arrow = region end
		end
		local title, count = nil, nil
		for _, region in ipairs({ header:GetRegions() }) do
			if region.GetText and region:GetText() ~= nil then
				if title == nil then title = region else count = region end
			end
		end
		if not (arrow and title and count) then clear = false
		else
			local arrow_rect, title_rect, count_rect = harness.rect(arrow), harness.rect(title), harness.rect(count)
			if arrow_rect.left + arrow_rect.width > title_rect.left + 0.5 then clear = false end
			if title_rect.left + title_rect.width > count_rect.left + 0.5 then clear = false end
			if not inside(count_rect, harness.rect(header)) then clear = false end
		end
	end
	harness.check("in every header the arrow, the title and the count follow one another without overlap", clear)
end
Everlook.module.set("bags", "fold", false)

-- Chips: over the grid, inside the bag, clear of each other and of the search box.
Everlook.module.set("bags", "sidebar", true)
settle()
do
	local bag, search, money = harness.rect(frame), harness.rect(box), harness.rect(frame.MoneyFrame)
	local list
	for _, child in ipairs(shown_children(frame, "Frame")) do
		if child ~= frame.MoneyFrame and #shown_children(child, "Button") > 0 then list = child end
	end
	harness.check("the chips have a frame", list ~= nil)
	local chips = shown_children(list, "Button")
	harness.check("a chip for everything and one for each of the six sections", #chips == 7)
	harness.check("with chips the bag is still as wide as stock", bag.width == stock_width)
	local list_rect = harness.rect(list)
	harness.check("the chips frame is the grid's width, right edge to right edge", math.abs(list_rect.width - 415) < 0.5
		and math.abs((list_rect.left + list_rect.width) - (money.left + money.width)) < 0.5)
	harness.check("the chips are inside the bag", inside(list_rect, bag))
	harness.check("the chips are below the search box and do not touch it", list_rect.top >= search.top + search.height and not overlap(list_rect, search))
	local clear = true
	for first = 1, #chips do
		local rect = harness.rect(chips[first])
		if not inside(rect, list_rect) then clear = false end
		for second = first + 1, #chips do
			if overlap(rect, harness.rect(chips[second])) then clear = false end
		end
	end
	harness.check("every chip is inside its frame and none overlaps another", clear)
	harness.check("each chip holds its name and its count", (function()
		for _, chip in ipairs(chips) do
			local rect, texts = harness.rect(chip), {}
			for _, region in ipairs({ chip:GetRegions() }) do
				if region.GetText and region:GetText() ~= nil then texts[#texts + 1] = harness.rect(region) end
			end
			if #texts ~= 2 or not inside(texts[1], rect) or not inside(texts[2], rect) or overlap(texts[1], texts[2]) then return false end
		end
		return true
	end)())
	-- The topmost header sits under the chips with the margin between them.
	local top_header
	for _, child in ipairs(shown_children(frame, "Button")) do
		if text_of(child) and child:GetHeight() == 20 then
			local rect = harness.rect(child)
			if top_header == nil or rect.top < harness.rect(top_header).top then top_header = child end
		end
	end
	harness.check("the top section's header is under the chips with their margin", top_header ~= nil
		and harness.rect(top_header).top - (list_rect.top + list_rect.height) >= 8 - 0.5)
	harness.check("with chips no header shows a count", (function()
		for _, child in ipairs(shown_children(frame, "Button")) do
			if child:GetHeight() == 20 then
				for _, region in ipairs({ child:GetRegions() }) do
					if region.GetObjectType and region:GetObjectType() == "FontString" and region:GetText() and region:IsShown() and tonumber(region:GetText()) then return false end
				end
			end
		end
		return true
	end)())
	harness.check("the bag still fits on the screen", inside(bag, screen))
	harness.snapshot("Grouped, with chips")
end

-- More columns: the search box follows the grid's right edge.
Everlook.module.set("bags", "columns", 14)
settle()
do
	local bag, search, money = harness.rect(frame), harness.rect(box), harness.rect(frame.MoneyFrame)
	harness.check("fourteen columns widen the bag", bag.width > stock_width)
	harness.check("the search box still reaches the grid's right edge", math.abs((search.left + search.width) - (money.left + money.width)) < 0.5)
	harness.check("and still keeps clear of the portrait", search.left - bag.left >= PORTRAIT_CLEARANCE - 0.5)
end
Everlook.module.set("bags", "columns", 10)

-- Twelve columns pack the small sections side by side: each header over its own slots, clear of the next.
-- Run with the count and the arrow counted in the headers' width, and again with neither.
local function packed(label)
	settle()
	local bag = harness.rect(frame)
	local headers = {}
	for _, child in ipairs(shown_children(frame, "Button")) do
		if text_of(child) and child:GetHeight() == 20 then headers[#headers + 1] = child end
	end
	harness.check(label .. ": every section still has a header", #headers == 6)
	harness.check(label .. ": the headers keep clear of each other", (function()
		for first = 1, #headers do
			for second = first + 1, #headers do
				if overlap(harness.rect(headers[first]), harness.rect(headers[second])) then return false end
			end
		end
		return true
	end)())
	harness.check(label .. ": each header is inside the bag", (function()
		for _, header in ipairs(headers) do if not inside(harness.rect(header), bag) then return false end end
		return true
	end)())
	harness.check(label .. ": every text in a header is inside it and clear of the others", (function()
		for _, header in ipairs(headers) do
			local header_rect, texts = harness.rect(header), {}
			for _, region in ipairs({ header:GetRegions() }) do
				if region.GetText and region:IsShown() and region:GetText() ~= nil then texts[#texts + 1] = harness.rect(region) end
			end
			for index, text in ipairs(texts) do
				if not inside(text, header_rect) then return false end
				for other = index + 1, #texts do if overlap(text, texts[other]) then return false end end
			end
		end
		return true
	end)())
	harness.check(label .. ": some sections share a row", (function()
		local tops, rows = {}, 0
		for _, header in ipairs(headers) do tops[harness.rect(header).top] = true end
		for _ in pairs(tops) do rows = rows + 1 end
		return rows < #headers
	end)())
	local solid = {}
	for _, button in ipairs(frame.buttons) do
		if button:GetAlpha() > 0 then solid[#solid + 1] = button end
	end
	harness.check(label .. ": every drawn slot is inside the bag", (function()
		for _, button in ipairs(solid) do if not inside(harness.rect(button), bag) then return false end end
		return true
	end)())
	harness.check(label .. ": no drawn slot overlaps another or a header", (function()
		for index, button in ipairs(solid) do
			for other = index + 1, #solid do
				if overlap(harness.rect(button), harness.rect(solid[other])) then return false end
			end
			for _, header in ipairs(headers) do
				if overlap(harness.rect(button), harness.rect(header)) then return false end
			end
		end
		return true
	end)())
end
Everlook.module.set("bags", "columns", 12)
Everlook.module.set("bags", "sidebar", false)
Everlook.module.set("bags", "fold", true)
packed("twelve columns with counts and arrows")
Everlook.module.set("bags", "fold", false)
Everlook.module.set("bags", "sidebar", true)
packed("twelve columns with chips")
harness.snapshot("Grouped, twelve columns, packed")
Everlook.module.set("bags", "columns", 10)

-- The game draws this bag below full scale, and the module scales it on top of that.
Everlook.module.set("bags", "scale", 80)
frame:SetScale(0.9)
settle()
do
	local search, money = harness.rect(box), harness.rect(frame.MoneyFrame)
	harness.check("scaled, the search box still reaches the grid's right edge", math.abs((search.left + search.width) - (money.left + money.width)) < 0.5)
	harness.check("scaled, the bag still fits on the screen", inside(harness.rect(frame), screen))
end
Everlook.module.set("bags", "scale", 100)
frame:SetScale(1)

-- Toggling with the bag closed: stock lays it out fresh when it opens, so none of ours may be left showing.
frame:Hide()
Everlook.module.set("bags", "group", false)
Everlook.module.set("bags", "enabled", false)
frame:Show()
settle()
do
	local shown = 0
	for _, child in ipairs(shown_children(frame, "Frame")) do
		if child ~= frame.MoneyFrame and #shown_children(child, "Button") > 0 then shown = shown + 1 end
	end
	harness.check("after toggling with the bag closed no chips are left over the grid", shown == 0)
	harness.check("and the search box is as stock sizes it", math.abs(harness.rect(box).width - 330) < 0.5)
	harness.check("and every slot stock draws is solid again, the free ones too", drawn() == SLOT_TOTAL)
end
Everlook.module.set("bags", "enabled", true)

-- Everything off: the bag is as stock draws it.
Everlook.module.set("bags", "enabled", false)
settle()
do
	local bag, search = harness.rect(frame), harness.rect(box)
	harness.check("turning the module off gives stock's width back", bag.width == stock_width)
	harness.check("and stock's search box", math.abs(search.width - 330) < 0.5)
end
