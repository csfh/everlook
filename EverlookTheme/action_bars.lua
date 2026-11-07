-- Action bars: every button on the main bar and the extra bars becomes a dark tile with the gold
-- line along its bottom, gray while its slot is empty, with the scene showing between the tiles.
-- The bar's frame, the dividers and each button's slot art are hidden; the icon and everything
-- that tells the button's state (highlight, pushed, checked, flash, proc glow, cooldowns) stay the
-- game's. The gryphons are EverlookHideClutter's switch, and the key labels are EverlookFonts'
-- and EverlookActionShortcuts'.
local _, ns = ...
local Theme = ns.Theme
local KEY = "actionBars"

-- Every bar made from EditModeActionBarTemplate (MainActionBar.xml, MultiActionBars.xml, 12.0.0),
-- with the prefix of its buttons' names for a client whose bars keep no actionButtons list.
local BARS = {
	{ "MainActionBar", "ActionButton" },
	{ "MultiBarBottomLeft", "MultiBarBottomLeftButton" },
	{ "MultiBarBottomRight", "MultiBarBottomRightButton" },
	{ "MultiBarRight", "MultiBarRightButton" },
	{ "MultiBarLeft", "MultiBarLeftButton" },
	{ "MultiBar5", "MultiBar5Button" },
	{ "MultiBar6", "MultiBar6Button" },
	{ "MultiBar7", "MultiBar7Button" },
}
local prefixOf = {} -- [bar] = its buttons' name prefix

-- A bar's buttons: ActionBarMixin:ActionBar_OnLoad fills actionButtons (ActionBar.lua, 12.0.0).
local function buttonsOf(bar)
	if type(bar.actionButtons) == "table" then return bar.actionButtons end
	local list, prefix = {}, prefixOf[bar]
	for index = 1, 12 do
		local button = prefix and _G[prefix .. index]
		if button then list[#list + 1] = button end
	end
	return list
end

-- The line says whether the slot holds anything.
local function paintTile(button)
	local tile = Theme.Drawn(KEY, button)
	if not tile or not Theme:IsOn(KEY) then return end
	local action = button.action
	local filled = type(action) == "number" and not Theme.Secret(action) and HasAction(action)
	Theme.Paint(tile, (filled and not Theme.Secret(filled)) and Theme.ACCENT or Theme.ACCENT_IDLE)
end

local watched = {}

local function styleButton(button)
	-- The game shows one of the slot art and the slot background and hides the other, by the bar's
	-- Hide Bar Art setting (BaseActionButtonMixin:UpdateButtonArt, Mainline/ActionButtonOverrides.lua,
	-- 12.0.0), and sets the normal texture again: all three are faded, so turning this off leaves
	-- the game's choice.
	Theme.HideArt(KEY, button.SlotArt, "alpha")
	Theme.HideArt(KEY, button.SlotBackground, "alpha")
	Theme.HideArt(KEY, button.GetNormalTexture and button:GetNormalTexture(), "alpha")
	-- The icon is in the button's BACKGROUND layer (ActionButtonTemplate.xml).
	Theme.Tile(KEY, button)
	paintTile(button)
	-- ActionBarActionButtonMixin:Update runs from UpdateAction, on a slot change and a page change.
	if not watched[button] and button.Update then
		watched[button] = true
		hooksecurefunc(button, "Update", paintTile)
	end
end

Theme:Surface({
	key = KEY,
	label = "Flat action bars",
	help = "Replaces the action bars' frame and slot art with a dark tile under each button and a "
		.. "line along its bottom, gold when the slot holds something and gray when it is empty. "
		.. "The gryphons are Hide Clutter's.",
	needs = { "HasAction" },
	optional = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight",
		"MultiBarLeft", "MultiBar5", "MultiBar6", "MultiBar7", "MainActionBar.BorderArt",
		"MainActionBar.UpdateDividers", "MainActionBar.actionButtons", "ActionButton1.SlotArt",
		"ActionButton1.SlotBackground", "ActionButton1.Update" },
	-- The buttons are secure action buttons: tiles are made and art hidden out of combat only.
	combat = true,
	frames = function()
		local list = {}
		for _, entry in ipairs(BARS) do
			local bar = _G[entry[1]]
			if bar then prefixOf[bar] = entry[2] end
			list[#list + 1] = bar or false
		end
		return list
	end,
	style = function(bar)
		-- The game shows and hides the frame itself (UpdateSystemSettingHideBarArt).
		Theme.HideArt(KEY, bar.BorderArt, "alpha")
		Theme.HideDividers(KEY, bar)
		if not watched[bar] and bar.UpdateDividers then
			watched[bar] = true
			hooksecurefunc(bar, "UpdateDividers", function(self)
				if Theme:IsOn(KEY) and not InCombatLockdown() then Theme.HideDividers(KEY, self) end
			end)
		end
		for _, button in pairs(buttonsOf(bar)) do
			if Theme.Usable(button) then styleButton(button) end
		end
	end,
})
