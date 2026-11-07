-- Micro menu: the row of buttons for the character, spellbook, quest log and the other panels.
-- Each button becomes a dark tile with the gold line along its bottom, as the action bars' do, and
-- the stone frame around the row and the buttons' own backgrounds are hidden. The icons, their
-- mouseover and pushed art, and the alert flash stay the game's.
local _, ns = ...
local Theme = ns.Theme
local KEY = "microMenu"

-- The action tiles' height (ActionButtonTemplate.xml at 100%): every micro tile is as tall, so the
-- row reads as one height. The bottom layout makes the buttons smaller, and says how much.
local HEIGHT = 45
-- How far the buttons overlap when the micro menu doesn't say (MicroMenuTemplate's childXPadding,
-- MainMenuBarMicroMenuTemplate.xml).
local OVERLAP = -5

-- The row's art (Camelot/MainMenuBarMicroMenu.xml, forever 1.60.1): nothing in the game shows or
-- hides either, so both are hidden.
local ROW_ART = { "BorderArt", "BackgroundArt" }
-- Each button's background (MainMenuBarMicroButton, MainMenuBarMicroButtons.xml); SetPushed and
-- SetNormal show one and hide the other, so both are faded. The character button's portrait
-- shadows the same way.
local BUTTON_ART = { "Background", "PushedBackground", "Shadow", "PushedShadow" }

-- The buttons MicroMenuMixin:AddButton took: each has a layoutIndex (MicroMenuContainer.lua).
-- Which buttons there are differs by game type, so the game's own list is used, not names.
local function buttonsOf(menu)
	local list = {}
	if not menu.GetChildren then return list end
	for _, child in ipairs({ menu:GetChildren() }) do
		if Theme.Usable(child) and type(child.layoutIndex) == "number" then list[#list + 1] = child end
	end
	return list
end

-- Each tile is centred on its button, HEIGHT tall. Its width leaves Theme.GAP between tiles, or is
-- the width the bottom layout worked out while that's in use (bottom_layout.lua), which puts the
-- row's edges exactly where bars 2 and 3 end. Sizes are in the button's own units, which the
-- micro menu's Size setting scales.
local function shape(tile, button)
	local scale = MicroMenu and MicroMenu.GetScale and MicroMenu:GetScale() or 1
	local row = Theme.BottomRow()
	local width, height = nil, row and row.button or HEIGHT
	if row then
		width = row.tile / scale
	else
		local overlap = MicroMenu and MicroMenu.childXPadding or OVERLAP
		width = button:GetWidth() + overlap - Theme.GAP / scale
	end
	tile:ClearAllPoints()
	tile:SetPoint("CENTER", button, "CENTER")
	tile:SetSize(width, height / scale)
end

Theme:Surface({
	key = KEY,
	label = "Flat micro menu",
	help = "Replaces the micro menu's frame and button backgrounds with a dark tile under each "
		.. "button and a gold line along its bottom.",
	optional = { "MicroMenu", "MicroMenu.BorderArt", "MicroMenu.BackgroundArt", "CharacterMicroButton.Background",
		"CharacterMicroButton.PushedBackground" },
	frames = function() return { MicroMenu or false } end,
	style = function(menu)
		for _, key in ipairs(ROW_ART) do Theme.HideArt(KEY, menu[key], "hide") end
		for _, button in ipairs(buttonsOf(menu)) do
			for _, key in ipairs(BUTTON_ART) do Theme.HideArt(KEY, button[key], "alpha") end
			shape(Theme.Tile(KEY, button), button)
		end
	end,
})
