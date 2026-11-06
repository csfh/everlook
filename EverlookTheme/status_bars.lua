-- Experience and reputation bars. The container is only the frame (StatusTrackingBar.xml, forever
-- 1.60.1, 17px tall). The bar itself is each child status bar, inset by STATUS_BAR_SIZE_ADJUSTMENT.
-- The flat bar is a dark track on that status bar, the class color as its fill, and the theme's
-- line along the part the fill has not reached. The game's frame, trough, textured fill, rested
-- prediction and tick are hidden and put back when this is turned off.
local _, ns = ...
local Theme = ns.Theme
local KEY = "statusBars"

-- The class color at full brightness. The line under the empty part is Theme.Accent, the same
-- color darkened, so the two stay apart.
local function classColor()
	local _, class = UnitClass("player")
	local color = class and C_ClassColor.GetClassColor(class)
	if color then return color.r, color.g, color.b, 1 end
	return 0.8, 0.8, 0.8, 1
end

-- How far across the status bar its value sits, or nil when the numbers can't be read.
-- GetAnimatedValue is the position on screen while the bar is still sliding (GradualAnimatedStatusBar).
local function valueOf(status)
	if status.GetAnimatedValue then
		local animated = status:GetAnimatedValue()
		if type(animated) == "number" and not Theme.Secret(animated) then return animated end
	end
	if status.GetValue then return status:GetValue() end
end

local function portion(status)
	if not status.GetMinMaxValues then return end
	local value = valueOf(status)
	local minValue, maxValue = status:GetMinMaxValues()
	if Theme.Secret(value) or Theme.Secret(minValue) or Theme.Secret(maxValue) then return end
	if type(value) ~= "number" or type(minValue) ~= "number" or type(maxValue) ~= "number" then return end
	local range = maxValue - minValue
	if range <= 0 then return 0 end
	local share = (value - minValue) / range
	if share < 0 then return 0 end
	if share > 1 then return 1 end
	return share
end

local function place(texture, width)
	if not width or width <= 0 then
		texture:Hide()
		return
	end
	texture:Show()
	texture:SetWidth(width)
end

-- The bar on screen, or the first one when none is showing yet.
local function activeBar(container)
	local fallback
	if type(container.bars) ~= "table" then return end
	for _, bar in pairs(container.bars) do
		if Theme.Usable(bar) and Theme.Usable(bar.StatusBar) then
			fallback = fallback or bar
			if bar:IsShown() then return bar end
		end
	end
	return fallback
end

local function paint(container)
	local panel = Theme.Drawn(KEY, container)
	if not panel or not Theme:IsOn(KEY) then return end
	local bar = activeBar(container)
	local status = bar and bar.StatusBar
	if not status or not status.GetWidth then return end
	local width = status:GetWidth()
	if Theme.Secret(width) or type(width) ~= "number" then return end
	local share = portion(status)
	if not share then return end
	local r, g, b, a = classColor()
	panel.progress:SetColorTexture(r, g, b, a)
	place(panel.progress, width * share)
	local prediction = bar.ExhaustionLevelFillBar
	local restedWidth = prediction and prediction:IsShown() and prediction.GetWidth and prediction:GetWidth()
	if Theme.Secret(restedWidth) or type(restedWidth) ~= "number" then restedWidth = nil end
	if restedWidth and restedWidth > width then restedWidth = width end
	panel.rested:SetColorTexture(r, g, b, 0.4)
	place(panel.rested, restedWidth)
end

-- Textures the game shows and hides itself, so alpha keeps them invisible. Recorded so turning
-- the surface off puts each one back, including a fill texture SetStatusBarTexture picks later.
local function hideAlpha(texture)
	Theme.HideArt(KEY, texture, "alpha")
end

local function hideStatusArt(bar)
	local status = bar.StatusBar
	if not Theme.Usable(status) then return end
	hideAlpha(status.Background)
	hideAlpha(status.GetStatusBarTexture and status:GetStatusBarTexture())
	hideAlpha(status.GainFlareAnimationTexture)
	hideAlpha(status.LevelUpTexture)
	hideAlpha(status.Overlay)
	hideAlpha(bar.ExhaustionLevelFillBar)
	local tick = bar.ExhaustionTick
	if Theme.Usable(tick) then
		hideAlpha(tick.GetNormalTexture and tick:GetNormalTexture())
		hideAlpha(tick.GetHighlightTexture and tick:GetHighlightTexture())
	end
end

-- Segment lines between the bars (StatusBarDividerTemplate). The game shows the divider frame;
-- the texture stays hidden.
local function hideDividers(container)
	local pool = container.HorizontalDividersPool
	if not (pool and pool.EnumerateActive) then return end
	for divider in pool:EnumerateActive() do
		if Theme.Usable(divider) then Theme.HideArt(KEY, divider.BarDividerTexture, "hide") end
	end
end

local watched = {}

local function watch(container)
	if watched[container] or not hooksecurefunc or type(container.bars) ~= "table" then return end
	watched[container] = true
	for _, bar in pairs(container.bars) do
		local status = Theme.Usable(bar) and bar.StatusBar
		if Theme.Usable(status) then
			local function again()
				if Theme:IsOn(KEY) then hideStatusArt(bar) end
				paint(container)
			end
			if status.SetValue then hooksecurefunc(status, "SetValue", again) end
			if status.SetAnimatedValues then hooksecurefunc(status, "SetAnimatedValues", again) end
			if status.OnValueChanged then hooksecurefunc(status, "OnValueChanged", again) end
			if status.OnUpdate then hooksecurefunc(status, "OnUpdate", again) end
			if status.SetStatusBarTexture then hooksecurefunc(status, "SetStatusBarTexture", again) end
		end
	end
	if container.ApplyPendingBarToShow then
		hooksecurefunc(container, "ApplyPendingBarToShow", function() paint(container) end)
	end
	if container.UpdateDividers then
		hooksecurefunc(container, "UpdateDividers", function(self)
			if Theme:IsOn(KEY) then hideDividers(self) end
		end)
	end
	if container.ResizeContainerBars then
		hooksecurefunc(container, "ResizeContainerBars", function() paint(container) end)
	end
end

Theme:Surface({
	key = KEY,
	label = "Flat experience and reputation bars",
	help = "Replaces the experience and reputation bars with a flat bar: a dark track and your "
		.. "class color as the fill, in place of the frame and the textured bar.",
	optional = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
	frames = function()
		return { MainStatusTrackingBarContainer or false, SecondaryStatusTrackingBarContainer or false }
	end,
	style = function(container)
		hideAlpha(container.BarFrameTexture)
		if type(container.bars) == "table" then
			for _, bar in pairs(container.bars) do
				if Theme.Usable(bar) then hideStatusArt(bar) end
			end
		end
		hideDividers(container)
		watch(container)
		local bar = activeBar(container)
		local status = bar and bar.StatusBar
		if not Theme.Usable(status) then return end
		Theme.Draw(KEY, container, function()
			local panel = Theme.Panel(container, true, true)
			panel:SetAllPoints(status)
			local r, g, b, a = classColor()
			-- Under the solid fill, so rested XP reads as the same color before the value.
			panel.rested = panel:CreateTexture(nil, "ARTWORK")
			panel.rested:SetPoint("TOPLEFT")
			panel.rested:SetPoint("BOTTOMLEFT")
			panel.rested:SetColorTexture(r, g, b, 0.4)
			panel.progress = panel:CreateTexture(nil, "ARTWORK", nil, 1)
			panel.progress:SetPoint("TOPLEFT")
			panel.progress:SetPoint("BOTTOMLEFT")
			panel.progress:SetColorTexture(r, g, b, a)
			return panel
		end)
		paint(container)
	end,
})
