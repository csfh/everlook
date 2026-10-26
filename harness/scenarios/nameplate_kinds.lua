-- The nameplate view over every kind of plate: the game's own layout, and the same plates with the view on, a quest
-- mark from a provider and a subtitle, so the kinds can be compared side by side.
harness.include("lib/game.lua")
harness.include("lib/nameplates.lua")
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Nameplates")
harness.load_addon("Everlook_QuestNameplates")
game.login()
if EverlookMinimapButton then EverlookMinimapButton:Hide() end
nameplate.install()
Everlook.module.set("fonts", "enabled", true)

local layout = {
	{ "friendly_npc", "Brother Paxton", "27", -330, 60 },
	{ "enemy_npc", "Murloc", "6", 0, 60 },
	{ "enemy_player", "Rival", "55", 330, 60 },
	{ "friendly_player", "Friend", "54", -330, -70 },
	{ "name_only", "Fiddler Voltz", "55", 0, -70 },
	{ "simplified", "Minion", "10", 330, -70 },
	{ "widgets_only", "Objective", "1", -330, -200 },
	{ "forbidden", "Forbidden", "60", 0, -200 },
	{ "personal", "You", "60", 330, -200 },
}
local plates = {}
for _, row in ipairs(layout) do
	local plate, unit = nameplate.make(row[1], { name = row[2], level = row[3], x = row[4], y = row[5] })
	plates[row[1]] = { plate = plate, unit = unit }
end
function UnitIsUnit(unit, other) return other == "player" and plates.personal and unit == plates.personal.unit end
function UnitIsPlayer() return false end
function UnitCanAttack() return false end

harness.snapshot("The game's own plates, nine kinds")

-- The kind of each plate is told apart from what the plate says about itself.
local kinds = Everlook.nameplates
for _, row in ipairs(layout) do
	harness.check(row[1] .. " is told apart", kinds.kind_of(plates[row[1]].plate, plates[row[1]].unit) == row[1])
end

Everlook.module.set("nameplates", "enabled", true)
Everlook.nameplates.provide({
	source = "gallery", order = 1,
	lead = function(unit, kind) if kind ~= "enemy_player" then return { atlas = "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Quest", file = "Interface\\TargetingFrame\\PortraitQuestBadge" } end end,
	subtitle = function(unit, kind) if kind == "friendly_npc" or kind == "name_only" then return { text = "<Quest Giver>", color = { 0.1, 1, 0.1 } } end end,
})
harness.advance(1)
harness.event("PLAYER_ENTERING_WORLD")
harness.advance(1)
harness.snapshot("With the nameplate view on")

local function left_aligned(kind) return plates[kind].plate.UnitFrame.name:GetJustifyH() == "LEFT" end
for _, kind in ipairs({ "friendly_npc", "enemy_npc", "enemy_player", "friendly_player" }) do
	harness.check(kind .. " has its name left-aligned", left_aligned(kind))
end
harness.check("name_only keeps its name centred, as there is no bar to line up with", plates.name_only.plate.UnitFrame.name:GetJustifyH() == "CENTER")
for _, kind in ipairs({ "simplified", "widgets_only", "forbidden", "personal" }) do
	harness.check(kind .. " is left exactly as the game made it", plates[kind].plate.UnitFrame.name:GetJustifyH() == "CENTER")
end

-- The game lays a plate out again.
plates.friendly_npc.plate.UnitFrame:UpdateAnchors()
harness.check("when the game lays a plate out again the name is left-aligned again", left_aligned("friendly_npc"))
harness.snapshot("After the game laid a plate out again")

Everlook.module.set("nameplates", "layout", "name_left")
harness.advance(0.1)
harness.snapshot("Mark beside the name only")
Everlook.module.set("nameplates", "layout", "rows")
Everlook.module.set("nameplates", "align_name", false)
harness.snapshot("Names centred, marks and subtitles kept")
for _, e in ipairs(harness.errors()) do print("script error:", e) end
