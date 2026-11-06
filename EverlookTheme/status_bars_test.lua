local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme status bars")
local t, check, Theme = f.t, f.check, f.Theme
local panelOn = f.panelOn

-- Experience and reputation bars ----------------------------------------------------------------
local barArt = MainStatusTrackingBarContainer.BarFrameTexture
t.change("EverlookTheme_statusBars", true)
check(barArt.alpha == 0 and panelOn(MainStatusTrackingBarContainer).fill, "on: the bar's gray frame gives way to a panel")
t.change("EverlookTheme_statusBars", false)
check(barArt.alpha == 1, "off: the gray frame is back")

t.done()
