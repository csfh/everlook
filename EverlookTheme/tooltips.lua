-- Tooltips: every tooltip the game styles gives its art to the dark solid with the class-colored
-- line along its bottom. Embedded tooltips, drawn inside another, are left alone.
local _, ns = ...
local Theme = ns.Theme
local KEY = "tooltips"

-- The tooltip's NineSlice pieces (TooltipDefaultLayout), its background included: the panel is
-- both. SetCenterColor sets the Center's vertex color, never its alpha, so fading holds.
local ART = { "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }

local function style(tooltip)
	local slice = tooltip.NineSlice
	if not Theme.Usable(slice) or not slice:IsShown() then return end
	for _, key in ipairs(ART) do Theme.HideArt(KEY, slice[key], "alpha") end
	Theme.Draw(KEY, tooltip, function()
		local panel = Theme.Panel(tooltip, true, true)
		panel:SetAllPoints(tooltip)
		return panel
	end)
end

Theme:Surface({
	key = KEY,
	label = "Flat tooltips",
	help = "Gives tooltips a dark solid background and a line in your class color along the bottom in place of their art.",
	needs = { "SharedTooltip_SetBackdropStyle" },
	optional = { "GameTooltip" },
	-- Tooltips seen before stay themed; the rest are themed as the game styles them.
	frames = function()
		local list = { GameTooltip or false }
		for tooltip in Theme.Hosts(KEY) do
			if tooltip ~= GameTooltip then list[#list + 1] = tooltip end
		end
		return list
	end,
	style = style,
	enable = function()
		-- The game styles a tooltip each time it shows; the theme follows it.
		hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip, _, embedded)
			if not embedded and Theme:IsOn(KEY) and Theme.Usable(tooltip) then style(tooltip) end
		end)
	end,
})
