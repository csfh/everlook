local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme")
local t, check, Theme = f.t, f.check, f.Theme

-- The panel -------------------------------------------------------------------------------------
local function near(x, y) return math.abs(x - y) < 1e-6 end
local host = t.widget()
local panel = Theme.Panel(host, true, true)
check(panel.parent == host and panel.parentLevel == true, "a panel is a frame of its own, drawn at its parent's level")
check(panel.fill and panel.fill.colorTexture[1] == Theme.BACKGROUND[1], "with a fill it has the dark solid")
check(panel.line and panel.line.texture == nil and panel.line.atlas == nil, "and one line, no artwork")
check(panel.line.points[1][1] == "BOTTOMLEFT" and panel.line.points[2][1] == "BOTTOMRIGHT" and #panel.line.points == 2,
	"the line runs along the bottom edge")
check(panel.line.height == 2, "the line is the line's thickness, two units")
check(near(panel.line.vertex[1], 0.65) and near(panel.line.vertex[2], 0.533) and near(panel.line.vertex[3], 0),
	"in the muted gold, the same for every character")
local plain = Theme.Panel(host, false, false)
check(plain.fill == nil and plain.line == nil, "without either it draws nothing")
local line = Theme.LINE
Theme.LINE = 0.1
t.fire("UI_SCALE_CHANGED")
check(panel.line.height == 1, "the line is never thinner than two screen pixels, and follows the scale")
Theme.LINE = line
t.fire("UI_SCALE_CHANGED")

-- The engine -------------------------------------------------------------------------------------
-- A surface of the test's own, on protected frames, run through the engine the way chat.lua and
-- the rest are.
local target = f.shownTexture()
local host2 = t.widget()
local styled, after = 0, 0
Theme:Surface({
	key = "probe",
	combat = true,
	frames = function() return { host2, false } end,
	style = function(frame)
		styled = styled + 1
		Theme.HideArt("probe", target, "alpha")
		Theme.Draw("probe", frame, function() return Theme.Panel(frame, true, true) end)
	end,
	after = function() after = after + 1 end,
})
Theme.db.probe = true
t.combat = true
Theme:Apply("probe")
check(styled == 0 and after == 1, "in combat a surface on protected frames waits; its after() still runs")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(styled == 1 and target.alpha == 0 and Theme.Drawn("probe", host2).shown, "after combat it applies, to usable frames only")
t.fire("PLAYER_REGEN_ENABLED")
check(styled == 1, "and only once")
Theme.db.probe = false
Theme:Apply("probe")
check(target.alpha == 1 and not Theme.Drawn("probe", host2).shown, "off: what it hid is back and what it drew is hidden")
local heard = 0
Theme:On("PLAYER_REGEN_ENABLED", function() heard = heard + 1 end)
t.combat = true
Theme.db.probe = true
Theme:Apply("probe")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(heard == 1 and styled == 2, "two handlers on one event both run: a surface can't take the engine's")
t.combat = true
Theme.db.probe = false
Theme:Apply("probe")
check(target.alpha == 0 and not Theme.Drawn("probe", host2).shown,
	"off in combat: what it drew is hidden at once, the game's art on protected frames waits")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(target.alpha == 1 and styled == 2, "and comes back after combat, without styling again")
Theme:OnSettingChanged("nothing")
check(true, "a setting that isn't a surface is ignored")

-- The solids' opacity is a setting, half by default, and moving it changes every solid at once.
check(Theme.db.backgroundOpacity == 0.5 and panel.fill.colorTexture[4] == 0.5, "the solids start at 50% opacity")
t.change("EverlookTheme_backgroundOpacity", 0.8)
check(panel.fill.colorTexture[4] == 0.8 and panel.fill.colorTexture[1] == Theme.BACKGROUND[1], "moving the slider sets every solid's opacity")
local opacity = t.settings.EverlookTheme_backgroundOpacity.slider
check(opacity.min == 0.1 and opacity.max == 1 and opacity.format(0.5) == "50%", "the slider runs from 10% to 100%")
t.change("EverlookTheme_backgroundOpacity", 0.5)

t.done()
