-- The island's dividers are one physical pixel at any UI scale, and a title that is too long for its row is cut at a
-- word, in each of the faces the Fonts addon uses.
harness.include("lib/game.lua")
GetPhysicalScreenSize = function() return 1920, 1080 end
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Island")
game.login()
Everlook.module.set("fonts", "enabled", true)
Everlook.module.set("smart_island", "enabled", true)
harness.advance(1)
if EverlookMinimapButton then EverlookMinimapButton:Hide() end
local island = harness.find("EverlookSmartIsland")

for _, scale in ipairs({ 0.64, 1.0, 1.2 }) do
	UIParent:SetScale(scale)
	harness.advance(0.5)
	local want = 768 / 1080 / island:GetEffectiveScale()
	local got = Everlook.island.hairline()
	harness.check(("at UI scale %.2f the hairline is one physical pixel (%.4f units, wanted %.4f)"):format(scale, got or -1, want), got and math.abs(got - want) < 0.0001)
	harness.check(("and the physical pixels it covers come to one at scale %.2f"):format(scale), got and math.abs(got * island:GetEffectiveScale() * 1080 / 768 - 1) < 0.001)
end
UIParent:SetScale(1)

-- Cutting at a word, measured in the game's own faces.
local fit = Everlook.island_row.fit
local frame = CreateFrame("Frame")
for _, font in ipairs({ "GameFontHighlight", "GameFontHighlightMedium", "GameFontHighlightSmall", "GameFontHighlightLarge" }) do
	local text = frame:CreateFontString(nil, "OVERLAY", font)
	local function measure(value) text:SetText(value); return text:GetStringWidth() end
	local full = "Gathering Idols of Kolkar in the Barrens"
	local width = measure(full)
	harness.check(font .. ": a room that holds the whole title gets the whole title", fit({ full, "Gathering Idols" }, width, measure) == full)
	harness.check(font .. ": a room that holds only the short wording gets it", fit({ full, "Gathering Idols" }, measure("Gathering Idols"), measure) == "Gathering Idols")
	local cut = fit(full, width * 0.6, measure)
	local body = cut:gsub("%.%.%.$", "")
	harness.check(font .. ": a title cut for room ends at a word and fits (" .. cut .. ")", measure(cut) <= width * 0.6 and (full:sub(#body + 1, #body + 1) == " "), cut)
end
