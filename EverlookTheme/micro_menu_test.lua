local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme micro menu")
local t, check, Theme = f.t, f.check, f.Theme
local panelOn, shownTexture = f.panelOn, f.shownTexture

function t.Widget:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end
function t.Widget:GetWidth() return self.width end
function t.Widget:GetScale() return self.scale or 1 end

-- The row (Camelot/MainMenuBarMicroMenu.xml): its frame and background, the character button with
-- its portrait shadows, and a quest log button. A child without a layoutIndex isn't a button.
local menu = t.widget("MicroMenu")
MicroMenu = menu
menu.BorderArt, menu.BackgroundArt = shownTexture(), shownTexture()
local function button(index)
	local made = t.widget()
	made.shown, made.layoutIndex, made.width = true, index, 32
	made.Background, made.PushedBackground = shownTexture(), shownTexture()
	made.FlashBorder = shownTexture()
	return made
end
local character, quests, other = button(1), button(2), t.widget()
other.layoutIndex = nil
character.Shadow, character.PushedShadow = shownTexture(), shownTexture()
function menu:GetChildren() return character, quests, other end

t.change("EverlookTheme_microMenu", true)
local tile = panelOn(character)
check(not menu.BorderArt:IsShown() and not menu.BackgroundArt:IsShown(), "on: the row's frame and background are gone")
check(character.Background.alpha == 0 and character.PushedBackground.alpha == 0 and character.Shadow.alpha == 0
	and character.PushedShadow.alpha == 0 and quests.Background.alpha == 0, "on: each button's backgrounds are gone")
check(character.FlashBorder.alpha == 1, "the alert flash stays the game's")
check(tile and panelOn(quests) and not panelOn(other), "a tile on each of the game's buttons, nothing on other children")
check(tile.point[1] == "CENTER" and tile.point[2] == character and tile.width == 23 and tile.height == 45,
	"centred on its button, as tall as an action tile, and GAP apart from the next though the buttons overlap")
check(tile.line.vertex[1] == Theme.ACCENT[1] and tile.fill.colorTexture[4] == Theme:Opacity(),
	"in the gold line and the background opacity")

-- The micro menu at 90%: the tile keeps its size on screen.
menu.scale = 0.9
t.change("EverlookTheme_microMenu", false)
t.change("EverlookTheme_microMenu", true)
check(math.abs(tile.height * 0.9 - 45) < 1e-9 and math.abs(tile.width - (27 - 4 / 0.9)) < 1e-9,
	"at another micro menu size the tile is still 45 tall on screen, with the same gap")
-- While the bottom layout is in use, its width wins.
local row = Theme.BottomRow
Theme.BottomRow = function() return { tile = 18, scale = 0.9 } end
t.change("EverlookTheme_microMenu", false)
t.change("EverlookTheme_microMenu", true)
check(math.abs(tile.width * 0.9 - 18) < 1e-9, "with the bottom layout in use, the tile takes the width it worked out")
Theme.BottomRow = row
menu.scale = nil

t.change("EverlookTheme_microMenu", false)
check(menu.BorderArt:IsShown() and menu.BackgroundArt:IsShown() and character.Background.alpha == 1
	and character.PushedShadow.alpha == 1 and not tile:IsShown(), "off: the game's art is back and the tiles hidden")

t.done()
