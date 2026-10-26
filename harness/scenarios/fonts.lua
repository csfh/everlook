-- Blizzard's font objects exist with their real sizes, the Fonts addon changes them, and text is
-- measured in the font it ends up in.
harness.include("lib/game.lua")
local before = { GameFontHighlight:GetFont() }
harness.check("GameFontHighlight is 12 high before the Fonts addon", before[2] == 12)
harness.check("and GameFontHighlightSmall is 10, Large is 16", select(2, GameFontHighlightSmall:GetFont()) == 10 and select(2, GameFontHighlightLarge:GetFont()) == 16)

harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
game.login()
Everlook.module.set("fonts", "enabled", true)
harness.advance(1)
local path, height = GameFontHighlight:GetFont()
harness.check("the Fonts addon puts Expressway on GameFontHighlight and keeps its height", path:lower():find("expressway", 1, true) ~= nil and height == 12)

local frame = CreateFrame("Frame")
local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetFontObject(GameFontHighlight)
text:SetText("Hello")
local narrow = text:GetStringWidth()
text:SetText("Hello Hello")
harness.check("two words are wider than one, and not a flat 7 a letter", text:GetStringWidth() > narrow * 2 - 1 and math.abs(narrow - 35) > 0.5)
text:SetFontObject(GameFontHighlightLarge)
harness.check("a larger font object gives a wider string with no new call to SetText", text:GetStringWidth() > narrow * 2)
text:SetText("")
harness.check("an empty string has no width", text:GetStringWidth() == 0)
text:SetWidth(40)
text:SetText("one two three four five six")
harness.check("a narrow width wraps the text onto more lines", text:GetStringHeight() > select(2, text:GetFont()) * 2)

-- A tooltip's first line is a name, and names are set in the people font; its other lines are not.
GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
GameTooltip:SetText("Thrall")
GameTooltip:AddLine("Warchief of the Horde")
local first, second = GameTooltipTextLeft1:GetFont(), GameTooltipTextLeft2:GetFont()
harness.check("the first line of a tooltip is in Manrope", first:lower():find("manrope", 1, true) ~= nil)
harness.check("the second line of a tooltip is in Expressway", second:lower():find("expressway", 1, true) ~= nil)
