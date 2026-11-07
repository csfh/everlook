-- Bag bar: the backpack, the bag slots, the reagent bag and the keyring. Each slot becomes a dark
-- tile with a line along its bottom, gold while that bag's window is open and gray otherwise, and
-- the stone frame around the bar, the dividers and each slot's frame are hidden. The bag icons, the
-- item quality border and the item count stay the game's.
local _, ns = ...
local Theme = ns.Theme
local KEY = "bagsBar"

-- On Forever every one of these is the slot's stone frame (BaseBagSlotButtonMixin:GetSlotAtlases
-- and UpdateTextures, Camelot/MainMenuBarBagButtons.lua, forever 1.60.1): the normal, pushed and
-- mouseover textures, and the highlight the game shows while the bag is open. The game sets their
-- atlas and shows and hides the open highlight, so all are faded. The line takes over the open
-- highlight's job. The mouseover glow is given back at the alpha UpdateTextures sets.
local HIGHLIGHT_ALPHA = 0.4

local function fade(button)
	Theme.HideArt(KEY, button.GetNormalTexture and button:GetNormalTexture(), "alpha")
	Theme.HideArt(KEY, button.GetPushedTexture and button:GetPushedTexture(), "alpha")
	Theme.HideArt(KEY, button.GetHighlightTexture and button:GetHighlightTexture(), "alpha", HIGHLIGHT_ALPHA)
	Theme.HideArt(KEY, button.SlotHighlightTexture, "alpha")
end

-- The fallback when the bag manager is missing: the bar's buttons by name (MainMenuBarBagButtons.xml).
local NAMES = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

local function buttons()
	local list = {}
	if MainMenuBarBagManager and MainMenuBarBagManager.EnumerateBagButtons then
		for _, button in MainMenuBarBagManager:EnumerateBagButtons() do list[#list + 1] = button end
	end
	if #list == 0 then
		for _, name in ipairs(NAMES) do
			if _G[name] then list[#list + 1] = _G[name] end
		end
	end
	-- The keyring isn't in the manager's list; it sits on the bar beside the reagent bag.
	if Theme.Usable(KeyRingButton) then
		local listed = false
		for _, button in ipairs(list) do listed = listed or button == KeyRingButton end
		if not listed then list[#list + 1] = KeyRingButton end
	end
	return list
end

local function paintTile(button, open)
	local tile = Theme.Drawn(KEY, button)
	if tile then Theme.Paint(tile, open and Theme.ACCENT or Theme.ACCENT_IDLE) end
end

-- Open as the game last showed it: its open highlight is shown, only faded.
local function shownOpen(button)
	local highlight = button.SlotHighlightTexture
	return Theme.Usable(highlight) and highlight:IsShown() == true
end

local watched = {}

local function styleButton(button)
	fade(button)
	Theme.Tile(KEY, button)
	paintTile(button, shownOpen(button))
	-- UpdateTextures sets the slot's atlases again when a bag goes in or out.
	if not watched[button] and button.UpdateTextures then
		watched[button] = true
		hooksecurefunc(button, "UpdateTextures", function(self)
			if Theme:IsOn(KEY) then fade(self) end
		end)
	end
end

-- The game marks an open bag from these two callbacks (BaseBagSlotButtonMixin:UpdateBagButtonHighlight,
-- MainMenuBarBagButtons.lua): the bag is open when a container frame showing it is shown.
local function bagToggled(_, container)
	if not Theme:IsOn(KEY) or not Theme.Usable(container) or not container.MatchesBagID then return end
	for host in Theme.Hosts(KEY) do
		if host.GetBagID and container:MatchesBagID(host:GetBagID()) then
			paintTile(host, container:IsShown())
		end
	end
end

local owner = {}

Theme:Surface({
	key = KEY,
	label = "Flat bag bar",
	help = "Replaces the bag bar's frame and slot frames with a dark tile under each bag and a line "
		.. "along its bottom, gold while that bag is open and gray while it is closed.",
	optional = { "BagsBar", "BagsBar.BorderArt", "BagsBar.UpdateDividers", "MainMenuBarBagManager.EnumerateBagButtons",
		"MainMenuBarBackpackButton.SlotHighlightTexture", "MainMenuBarBackpackButton.UpdateTextures",
		"EventRegistry.RegisterCallback", "KeyRingButton" },
	frames = function() return { BagsBar or false } end,
	style = function(bar)
		-- Nothing in the game shows or hides the bar's frame.
		Theme.HideArt(KEY, bar.BorderArt, "hide")
		Theme.HideDividers(KEY, bar)
		if not watched[bar] and bar.UpdateDividers then
			watched[bar] = true
			hooksecurefunc(bar, "UpdateDividers", function(self)
				if Theme:IsOn(KEY) then Theme.HideDividers(KEY, self) end
			end)
		end
		for _, button in ipairs(buttons()) do
			if Theme.Usable(button) then styleButton(button) end
		end
	end,
	enable = function()
		if EventRegistry and EventRegistry.RegisterCallback then
			EventRegistry:RegisterCallback("ContainerFrame.OpenBag", bagToggled, owner)
			EventRegistry:RegisterCallback("ContainerFrame.CloseBag", bagToggled, owner)
		end
	end,
})
