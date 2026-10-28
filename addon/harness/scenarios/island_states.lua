-- The awkward states: nothing to show, warnings, text that is too long, the narrowest capsule.
harness.include("lib/game.lua")
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Island")
harness.load_addon("Everlook_IslandWarnings")
game.login()
if EverlookMinimapButton then EverlookMinimapButton:Hide() end
Everlook.module.set("island", "enabled", true)
harness.advance(1)

local island = harness.find("EverlookSmartIsland")
local function open()
	local x, y = harness.center(island)
	harness.click(x, y)
	harness.advance(1)
end
local function close()
	-- The header is the part of the island nothing else covers, so that is where a click lands.
	local rect = harness.rect(island)
	harness.click(rect.left + rect.width / 2, rect.top + 8)
	harness.move(5, 5)
	harness.advance(1.5)
end

game.snapshot("Resting, nothing else to show", "closed")
open()
game.snapshot("Open, nothing else to show", "pinned")

-- A tooltip over a metric cell, with the first line in the people font.
do
	local cell
	for _, frame in ipairs(harness.frames()) do
		if harness.info(frame).visible then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.GetText and region:GetText() == "Gear" then cell = frame end
			end
		end
	end
	if cell then
		harness.hover(cell)
		harness.advance(0.2)
		harness.check("the tooltip over a cell is shown", GameTooltip:IsShown() and GameTooltip:NumLines() > 0)
		game.snapshot("Open, a tooltip over Gear", "pinned")
		harness.move(5, 5)
		harness.advance(0.2)
	else
		harness.check("a Gear cell is on the open island", false)
	end
end
close()

-- Gear and bags both low, with the closed pill told to say so.
Everlook.module.set("island", "source_durability", true)
Everlook.module.set("island", "source_bags", true)
game.slots = { [1] = { 5, 50 }, [5] = { 10, 20 } }
game.bags = { [0] = 0, [1] = 1 }
harness.event("UPDATE_INVENTORY_DURABILITY")
harness.event("BAG_UPDATE")
harness.advance(2)
game.snapshot("Resting, gear and bags low", "closed")
open()
game.snapshot("Open, gear and bags low", "pinned")
close()

-- Text that is too long for the capsule.
local long = Everlook.island.notify({ source = "States", key = "long", presentation = "status",
	text = "Flying to the Crossroads by way of the Barrens and Stonetalon",
	capsule = { text = "Flying to the Crossroads by way of the Barrens and Stonetalon", icon = "flight" } })
harness.advance(1)
game.snapshot("A status with a title over 40 characters", "closed")
Everlook.island.dismiss(long)
harness.advance(1)

local narrow = Everlook.island.notify({ source = "States", key = "narrow", presentation = "status", text = "x", capsule = { text = "x" } })
harness.advance(1)
game.snapshot("The narrowest status", "closed")
Everlook.island.dismiss(narrow)
harness.advance(1)

-- Four notices in the history.
for index = 1, 4 do
	Everlook.island.notify({ source = "Source " .. index, key = "n" .. index, text = "Notice number " .. index, detail = "A line of detail for number " .. index, persist = true })
end
harness.advance(2)
local mine = 0
for _, notice in ipairs(Everlook.smart_island.view().notices) do if tostring(notice.source):find("^Source ") then mine = mine + 1 end end
harness.check("four notices of this scenario are in the history (" .. mine .. " are)", mine == 4)
open()
game.snapshot("Open, four notices in the history", "pinned")

-- A history row says the rest of what it holds in a tooltip.
do
	local row
	for _, frame in ipairs(harness.frames()) do
		if harness.info(frame).visible then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.GetText and region:GetText() == "Notice number 2" then
					local walker = frame
					while walker and not walker:GetScript("OnEnter") do walker = walker:GetParent() end
					row = walker
				end
			end
		end
	end
	harness.check("a notice row is on the open island", row ~= nil)
	if row then
		harness.hover(row)
		harness.advance(0.2)
		harness.check("hovering it shows a tooltip with its text", GameTooltip:IsShown() and GameTooltipTextLeft1:GetText():find("Notice number 2", 1, true) ~= nil)
		game.snapshot("Open, a tooltip over a notice", "pinned")
	end
end

for _, e in ipairs(harness.errors()) do print("script error:", e) end
for _, m in ipairs(harness.missing()) do print("missing method:", m) end
