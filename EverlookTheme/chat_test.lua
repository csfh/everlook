local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme chat")
local t, check, Theme = f.t, f.check, f.Theme
local chat = f.chat
local chatBackground = f.chatBackground
local border = f.border
local tab = f.tab
local edit = f.edit
local editArt = f.editArt
local panelOn = f.panelOn

-- Chat ------------------------------------------------------------------------------------------
check(border[1].shown and tab.Left.alpha == 1, "off by default: the chat keeps its own art")
t.change("EverlookTheme_chat", true)
local allHidden = true
for _, texture in ipairs(border) do allHidden = allHidden and not texture.shown end
check(allHidden, "on: the chat border is hidden")
check(tab.Left.alpha == 0 and tab.ActiveMiddle.alpha == 0 and editArt[1].alpha == 0 and editArt[4].alpha == 0,
	"the tab's and the input line's art is faded")
FCFTab_UpdateColors(tab, true)
local tabPanel = panelOn(tab)
check(tabPanel and tabPanel.fill and tabPanel.line.vertex[1] == Theme.Accent()[1], "a selected tab has the class-colored line")
local windowPanel, editPanel = panelOn(chat), panelOn(edit)
check(windowPanel and windowPanel.allPoints == chatBackground and windowPanel.fill and windowPanel.line
	and not chatBackground.shown, "the window's own background gives way to the dark solid, with the line along its bottom")
check(editPanel and editPanel.fill and editPanel.line == nil and editPanel.points[1][2] == chatBackground
	and editPanel.points[1][5] == 0 and editPanel.points[2][2] == chatBackground,
	"the input line is a solid as wide as the window, right under the divider, with no line of its own")
FCFTab_UpdateColors(tab, false)
check(tabPanel.line.vertex[1] == Theme.ACCENT_IDLE[1], "and the others a gray one")

t.change("EverlookTheme_chat", false)
local allShown = true
for _, texture in ipairs(border) do allShown = allShown and texture.shown end
check(allShown and chatBackground.shown and tab.Left.alpha == 1 and editArt[1].alpha == 1, "off: the chat's own art is back")
check(not tabPanel.shown and not windowPanel.shown and not editPanel.shown, "and the panels are hidden")

t.done()
