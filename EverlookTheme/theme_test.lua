local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme")
local t, check, Theme = f.t, f.check, f.Theme

-- The panel -------------------------------------------------------------------------------------
local function near(x, y) return math.abs(x - y) < 1e-6 end
local host = t.widget()
local panel = Theme.Panel(host, true, true)
check(panel.parent == host and panel.parentLevel == true, "a panel is a frame of its own, drawn at its parent's level")
check(panel.fill and panel.fill.colorTexture[4] == Theme.BACKGROUND[4], "with a fill it has the dark solid")
check(panel.line and panel.line.texture == nil and panel.line.atlas == nil, "and one line, no artwork")
check(panel.line.points[1][1] == "BOTTOMLEFT" and panel.line.points[2][1] == "BOTTOMRIGHT" and #panel.line.points == 2,
	"the line runs along the bottom edge")
check(panel.line.height == 1, "the line is the line's thickness")
check(near(panel.line.vertex[1], 0.25 * Theme.ACCENT_BRIGHTNESS) and near(panel.line.vertex[3], 0.92 * Theme.ACCENT_BRIGHTNESS),
	"in the player's class color, darker")
local plain = Theme.Panel(host, false, false)
check(plain.fill == nil and plain.line == nil, "without either it draws nothing")
local line = Theme.LINE
Theme.LINE = 0.1
t.fire("UI_SCALE_CHANGED")
check(panel.line.height == 0.5, "the line is never thinner than a screen pixel, and follows the scale")
Theme.LINE = line
t.fire("UI_SCALE_CHANGED")
local unnamed = UnitClass
UnitClass = function() return nil, nil end
check(Theme.Accent()[1] > 0 and Theme.Accent()[1] < 1, "a client that can't name the class gets a gray line")
UnitClass = unnamed

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
Theme.db.probe = false
Theme:Apply("probe")
Theme:OnSettingChanged("nothing")
check(true, "a setting that isn't a surface is ignored")

t.done()
