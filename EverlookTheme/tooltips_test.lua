local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme tooltips")
local t, check, Theme = f.t, f.check, f.Theme
local panelOn = f.panelOn
local tooltipBorder = f.tooltipBorder
local shownTexture = f.shownTexture

-- Tooltips --------------------------------------------------------------------------------------
SharedTooltip_SetBackdropStyle(GameTooltip)
check(tooltipBorder.TopEdge.alpha == 1, "off: tooltips keep their border")
t.change("EverlookTheme_tooltips", true)
check(tooltipBorder.TopEdge.alpha == 0 and tooltipBorder.Center.alpha == 0, "on: the tooltip's art goes, its background too")
check(panelOn(GameTooltip) and panelOn(GameTooltip).fill, "and a panel takes its place")
local other = t.widget("ItemRefTooltip")
other.NineSlice = t.widget()
other.NineSlice.shown = true
other.NineSlice.TopEdge = shownTexture()
SharedTooltip_SetBackdropStyle(other, nil, true)
check(other.NineSlice.TopEdge.alpha == 1, "an embedded tooltip is left alone")
SharedTooltip_SetBackdropStyle(other)
check(other.NineSlice.TopEdge.alpha == 0, "any other tooltip is themed as the game styles it")
t.change("EverlookTheme_tooltips", false)
check(tooltipBorder.TopEdge.alpha == 1 and tooltipBorder.Center.alpha == 1 and other.NineSlice.TopEdge.alpha == 1,
	"off: every tooltip's art is back")

t.done()
