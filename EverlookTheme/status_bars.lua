-- Experience and reputation bars: each bar container's frame art (StatusTrackingBar.xml, 12.0.0)
-- gives way to the dark solid with the class-colored line under the bar.
local _, ns = ...
local Theme = ns.Theme
local KEY = "statusBars"

Theme:Surface({
	key = KEY,
	label = "Flat experience and reputation bars",
	help = "Gives the experience and reputation bars a dark solid background and a line in your class color "
		.. "in place of their gray frame.",
	optional = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
	frames = function()
		return { MainStatusTrackingBarContainer or false, SecondaryStatusTrackingBarContainer or false }
	end,
	style = function(container)
		local art = container.BarFrameTexture
		if not Theme.Usable(art) then return end
		Theme.HideArt(KEY, art, "alpha")
		Theme.Draw(KEY, container, function()
			-- The bars are frames above the container, so the panel reaches 2 past its edges to
			-- show its line under them.
			local panel = Theme.Panel(container, true, true)
			panel:SetPoint("TOPLEFT", container, "TOPLEFT", -2, 2)
			panel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 2, -2)
			return panel
		end)
	end,
})
