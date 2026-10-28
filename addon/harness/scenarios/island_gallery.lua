-- The island in each state a player meets it in, one picture each.
harness.include("lib/game.lua")
game.quests()
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Island")
game.login()
-- The minimap button is not part of what is being looked at.
if EverlookMinimapButton then EverlookMinimapButton:Hide() end
Everlook.module.set("island", "enabled", true)
harness.advance(1)
game.snapshot("Resting: the level", "closed")

Everlook.module.set("island", "quest_context", true)
harness.advance(1)
game.snapshot("Resting: the quest", "closed")

local flight = Everlook.island.notify({ source = "Gallery", key = "flight", text = "Flying to Ratchet", presentation = "status",
	capsule = { text = "Ratchet", icon = "flight", labels = { "~5 yd" }, ring = { fraction = 0.4, tone = "warning" } } })
harness.advance(1)
game.snapshot("A status over the quest", "closed")
Everlook.island.dismiss(flight)
harness.advance(1)

local toast, why = Everlook.island.notify({ source = "Gallery", key = "toast", text = "Greatshot found", detail = "Looted from Thrall's Chest", duration = 20,
	actions = { { id = "equip", label = "Equip", type = "callback", on_click = function() end }, { id = "later", label = "Later", type = "callback", on_click = function() end } } })
harness.check("the toast was accepted (" .. tostring(why) .. ")", toast ~= nil)
harness.advance(1)
game.snapshot("A toast with two actions", "closed")

local island = harness.find("EverlookSmartIsland")
local x, y = harness.center(island)
harness.click(x, y)
harness.advance(1)
game.snapshot("Open, pinned", "pinned")

local function button_with_text(text)
	for _, frame in ipairs(harness.frames()) do
		if harness.info(frame).visible then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.GetText and region:GetText() == text then
					local walker = frame
					while walker and not walker:GetScript("OnClick") do walker = walker:GetParent() end
					if walker then return walker end
				end
			end
		end
	end
end
local pin = button_with_text("Pin")
if pin then
	harness.hover(pin)
	harness.advance(0.3)
	game.snapshot("Open, pointer on a Pin button", "pinned")
end
for _, e in ipairs(harness.errors()) do print("script error:", e) end
