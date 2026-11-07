local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme bag bar")
local t, check, Theme = f.t, f.check, f.Theme
local panelOn, shownTexture = f.panelOn, f.shownTexture

function t.Widget:SetDrawLayer(layer, sublevel) self.layer, self.sublevel = layer, sublevel end

-- The bar (Camelot/MainMenuBarBagButtons.xml): its frame, a divider, the backpack and one bag in
-- the bag manager, and the keyring outside it. Every slot texture is the stone frame on Forever.
local bar = t.widget("BagsBar")
BagsBar = bar
bar.BorderArt = shownTexture()
local piece = shownTexture()
local divider = t.widget()
function divider:GetRegions() return piece end
bar.HorizontalDividersPool = { EnumerateActive = function()
	local done = false
	return function()
		if done then return nil end
		done = true
		return divider
	end
end }
function bar:UpdateDividers() end
local function slot(bagID)
	local made = t.widget()
	made.shown = true
	local normal, pushed, highlight = shownTexture(), shownTexture(), shownTexture()
	function made:GetNormalTexture() return normal end
	function made:GetPushedTexture() return pushed end
	function made:GetHighlightTexture() return highlight end
	made.normal, made.pushed, made.highlight = normal, pushed, highlight
	-- UpdateTextures keeps the mouseover glow at 0.4.
	highlight:SetAlpha(0.4)
	made.SlotHighlightTexture = shownTexture()
	made.SlotHighlightTexture:Hide()
	made.IconBorder = shownTexture()
	function made:GetBagID() return bagID end
	function made:UpdateTextures() end
	return made
end
local backpack, bag, keyring = slot(0), slot(1), slot(-2)
KeyRingButton = keyring
MainMenuBarBagManager = { EnumerateBagButtons = function() return ipairs({ backpack, bag }) end }
-- The backpack is open already.
backpack.SlotHighlightTexture:Show()

local function gold(panel) return panel.line.vertex[1] == Theme.ACCENT[1] end
local function gray(panel) return panel.line.vertex[1] == Theme.ACCENT_IDLE[1] end

t.change("EverlookTheme_bagsBar", true)
local packTile, bagTile, keyTile = panelOn(backpack), panelOn(bag), panelOn(keyring)
check(not bar.BorderArt:IsShown() and not piece:IsShown(), "on: the bar's frame and the dividers are gone")
check(bag.normal.alpha == 0 and bag.pushed.alpha == 0 and bag.highlight.alpha == 0 and bag.SlotHighlightTexture.alpha == 0,
	"on: the slot's frame is gone, normal, pushed, mouseover and open alike")
check(bag.IconBorder.alpha == 1, "the item quality border stays the game's")
check(packTile and bagTile and keyTile, "a tile on every bag, the keyring too")
check(gold(packTile) and gray(bagTile), "gold under a bag that is open, gray under a closed one")

-- A bag opens and closes (ContainerFrame_OnShow and _OnHide).
local container = t.widget()
container.shown = true
function container:MatchesBagID(id) return id == 1 end
EventRegistry:Trigger("ContainerFrame.OpenBag", container)
check(gold(bagTile) and gold(packTile), "the bag opens: its line turns gold, the others keep theirs")
container.shown = false
EventRegistry:Trigger("ContainerFrame.CloseBag", container)
check(gray(bagTile), "it closes: gray again")

-- A bag goes in: the game sets the slot's atlases again.
bag.normal:SetAlpha(1)
bag:UpdateTextures()
check(bag.normal.alpha == 0, "the slot's frame stays gone when the game sets it again")
piece:Show()
bar:UpdateDividers()
check(not piece:IsShown(), "and so do the dividers")

t.change("EverlookTheme_bagsBar", false)
check(bar.BorderArt:IsShown() and piece:IsShown() and bag.normal.alpha == 1 and bag.SlotHighlightTexture.alpha == 1
	and not bag.SlotHighlightTexture:IsShown() and bag.highlight.alpha == 0.4 and not bagTile:IsShown(),
	"off: the game's art is back, the open highlight as the game left it, the glow at its 0.4, and the tiles hidden")
container.shown = true
EventRegistry:Trigger("ContainerFrame.OpenBag", container)
check(gray(bagTile), "off: opening a bag paints nothing")

t.done()
