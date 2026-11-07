local TooltipCursor = Everlook:NewAddon("EverlookTooltipCursor", {
	label = "Tooltip Cursor",
	defaults = {
		followCursor = true,
		onTop = true,
		hideInCombat = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookTooltipCursor", {
	"hooksecurefunc",
	"GameTooltip_SetDefaultAnchor",
	"GameTooltip",
	"GameTooltip.HookScript",
	"GameTooltip.GetFrameStrata",
	"GameTooltip.SetFrameStrata",
	"GameTooltip.Hide",
	"InCombatLockdown",
	"IsShiftKeyDown",
})

-- Offset of the tooltip's corner from the pointer, so the pointer stays visible.
local OFFSET_X, OFFSET_Y = 16, 16

-- Blizzard's XML puts GameTooltip in the TOOLTIP strata, above the action bars
-- (SharedTooltipTemplates.xml, wow-ui-source 12.0.0). Something can still lower it, and then it draws
-- under the bars while you drag a spell onto them, so it goes back every time it's placed or shown.
local function keepOnTop(tooltip)
	if tooltip:GetFrameStrata() ~= "TOOLTIP" then
		tooltip:SetFrameStrata("TOOLTIP")
	end
end

function TooltipCursor:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Tooltips")
	page:Checkbox("followCursor", "Tooltip follows the cursor",
		"Moves the game's default tooltip just off the mouse pointer and keeps it there as you move.")
	page:Checkbox("onTop", "Keep the tooltip above the action bars",
		"Puts the game's tooltip back in the top layer whenever it shows, so it never draws under the action bars, for example while you drag a spell onto them.")
	page:Checkbox("hideInCombat", "Hide tooltips in combat",
		"Hides the game's tooltip while you're in combat, for action buttons, units, bags and everything else. Hold Shift as you point at something to see its tooltip anyway.")
end

-- The game places its default tooltip through GameTooltip_SetDefaultAnchor; one hook moves them all.
function TooltipCursor:OnEnable()
	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
		if tooltip ~= GameTooltip then return end
		if self.db.followCursor then
			tooltip:SetOwner(parent, "ANCHOR_CURSOR", OFFSET_X, OFFSET_Y)
		end
		if self.db.onTop then keepOnTop(tooltip) end
	end)
	-- Tooltips placed some other way, such as the spellbook's, still pass through OnShow.
	-- Every tooltip passes through OnShow, so in combat it is hidden again as soon as it shows,
	-- unless Shift is held (Shift pauses what Everlook does for the player).
	GameTooltip:HookScript("OnShow", function(tooltip)
		if self.db.hideInCombat and InCombatLockdown() and not IsShiftKeyDown() then
			tooltip:Hide()
			return
		end
		if self.db.onTop then keepOnTop(tooltip) end
	end)
end
