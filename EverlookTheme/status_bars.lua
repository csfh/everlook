-- Experience and reputation bars. The container is only the frame (StatusTrackingBar.xml, forever
-- 1.60.1, 17px tall). The bar itself is each child status bar, inset by STATUS_BAR_SIZE_ADJUSTMENT.
-- The flat bar is a dark track on that status bar, a fill in the bar's own color, and the theme's
-- gold line along the part the fill has not reached. The game's frame, trough, textured
-- fill, rested prediction and tick are hidden and put back when this is turned off.
local _, ns = ...
local Theme = ns.Theme
local KEY = "statusBars"

-- The fill says what the bar is, as the game's own atlases do (12.0.0): experience purple, blue
-- while rested (ExpBarOverrides.lua, UpdateStatusBarTextures); reputation red, orange, yellow or
-- green by reaction, blue for paragon and renown (ReputationBarOverrides.lua, UpdateBarTextures);
-- honor its own, and artifact, azerite and house favor the artifact-power gold. The game sets
-- atlases, not colors, so these are flat stand-ins for them.
local COLORS = {
	-- Muted, not the atlases' saturated magenta and blue: a dusty violet and a slate blue.
	experience = { 0.42, 0.30, 0.62 },
	rested = { 0.22, 0.42, 0.72 },
	-- The rested reach ahead of the fill: lighter as well as fainter, so it reads apart from it.
	restedAhead = { 0.45, 0.6, 0.85, 0.6 },
	reputation = {
		{ 0.8, 0.3, 0.22 }, { 0.8, 0.3, 0.22 }, { 0.75, 0.27, 0 }, { 0.9, 0.7, 0 },
		{ 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 }, { 0, 0.6, 0.1 },
	},
	honor = { 0.9, 0.35, 0.1 },
	artifact = { 0.9, 0.75, 0.3 },
	unknown = { 0.6, 0.6, 0.62 },
}
COLORS.paragon = COLORS.rested

-- StatusTrackingBarInfo.BarsEnum (StatusTrackingManager.lua, 12.0.0), for a client without it.
local BARS = { Reputation = 1, Honor = 2, Artifact = 3, Experience = 4, Azerite = 5, HouseFavor = 6 }
local function barsEnum()
	return StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum or BARS
end

-- What the game last told each bar: { rested = bool } or { reaction = n, blue = bool }.
local state = setmetatable({}, { __mode = "k" })

local function reactionColor(reaction)
	local game = FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]
	if type(game) == "table" and type(game.r) == "number" then return { game.r, game.g, game.b } end
	return COLORS.reputation[reaction] or COLORS.unknown
end

-- The fill color for the bar at `index` in its container's bars.
local function fillColor(bar, index)
	local enum, known = barsEnum(), state[bar] or {}
	if index == enum.Experience then
		local rested = known.rested
		if rested == nil and GetRestState then
			local restState = GetRestState()
			rested = not Theme.Secret(restState) and restState == 1
		end
		return rested and COLORS.rested or COLORS.experience
	elseif index == enum.Reputation then
		local reaction = known.reaction
		if known.blue then return COLORS.paragon end
		-- Before the game's first call: the watched faction's reaction, as ReputationBar.lua reads
		-- it. Paragon and renown turn blue at its next update.
		if reaction == nil and C_Reputation and C_Reputation.GetWatchedFactionData then
			local watched = C_Reputation.GetWatchedFactionData()
			reaction = type(watched) == "table" and watched.reaction or nil
		end
		if type(reaction) ~= "number" or Theme.Secret(reaction) then return COLORS.unknown end
		return reactionColor(reaction)
	elseif index == enum.Honor then
		return COLORS.honor
	elseif index == enum.Artifact or index == enum.Azerite or index == enum.HouseFavor then
		return COLORS.artifact
	end
	return COLORS.unknown
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
	local fallback, fallbackIndex
	if type(container.bars) ~= "table" then return end
	for index, bar in pairs(container.bars) do
		if Theme.Usable(bar) and Theme.Usable(bar.StatusBar) then
			if not fallback then fallback, fallbackIndex = bar, index end
			if bar:IsShown() then return bar, index end
		end
	end
	return fallback, fallbackIndex
end

-- Where the track sits: on the status bar, or, while the bottom layout is in use
-- (bottom_layout.lua), across the row's full width, centred on the bar the way the layout centres
-- the row. That width can't be an Edit Mode size, which moves in 5% steps.
local function shapeTrack(panel, status)
	local row = Theme.BottomRow()
	panel:ClearAllPoints()
	if row then
		panel:SetPoint("TOP", status, "TOP")
		panel:SetPoint("BOTTOM", status, "BOTTOM")
		panel:SetWidth(row.width)
	else
		panel:SetAllPoints(status)
	end
end

-- The track's width, for the fill: the row's while the layout is in use, else the status bar's.
local function trackWidth(status)
	local row = Theme.BottomRow()
	if row then return row.width end
	local width = status:GetWidth()
	if Theme.Secret(width) or type(width) ~= "number" then return nil end
	return width
end

local function paint(container)
	local panel = Theme.Drawn(KEY, container)
	if not panel or not Theme:IsOn(KEY) then return end
	local bar, index = activeBar(container)
	local status = bar and bar.StatusBar
	if not status or not status.GetWidth then return end
	local width = trackWidth(status)
	if not width then return end
	local share = portion(status)
	if not share then return end
	local fill = fillColor(bar, index)
	panel.progress:SetColorTexture(fill[1], fill[2], fill[3], 1)
	place(panel.progress, width * share)
	local prediction = bar.ExhaustionLevelFillBar
	local restedWidth = prediction and prediction:IsShown() and prediction.GetWidth and prediction:GetWidth()
	if Theme.Secret(restedWidth) or type(restedWidth) ~= "number" then restedWidth = nil end
	-- The game's rested reach is measured on its own bar; the track may be wider.
	local barWidth = status:GetWidth()
	if restedWidth and type(barWidth) == "number" and not Theme.Secret(barWidth) and barWidth > 0 then
		restedWidth = restedWidth * width / barWidth
	end
	if restedWidth and restedWidth > width then restedWidth = width end
	local ahead = COLORS.restedAhead
	panel.rested:SetColorTexture(ahead[1], ahead[2], ahead[3], ahead[4])
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
	-- The dark trough, hidden rather than faded: the game never shows or hides it, and Forever puts
	-- the alpha of this bar's frame art back itself. A trough at full alpha under the track would
	-- make the background opacity look like it does nothing (2026-11-06; statusBarUnder checks).
	Theme.HideArt(KEY, status.Background, "hide")
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

-- The frame around the bar. Forever sets its alpha back to 1 itself (a session's record,
-- 2026-11-06: hidden by alpha, it was showing again), so it is hidden, which that can't undo.
local function hideFrameArt(container)
	local art = container.BarFrameTexture
	if Theme.Usable(art) and art:IsShown() then Theme.HideArt(KEY, art, "hide") end
end

-- TEMP: what sits under the track ten seconds after the first apply, saved as
-- Theme.db.statusBarUnder: whether the trough stays hidden, and any other art of the bar still
-- showing. Remove once a session shows the background opacity reaching the bar.
local lateLook = false
local function seen(texture)
	if not Theme.Usable(texture) then return nil end
	return { shown = texture:IsShown(), alpha = texture.GetAlpha and texture:GetAlpha() or nil }
end
local function lookLater()
	if lateLook or not (C_Timer and C_Timer.After) then return end
	lateLook = true
	C_Timer.After(10, function()
		if not Theme.db then return end
		Theme.db.statusBarFrameLate = nil -- the earlier record, now read: the frame stays hidden
		local under = {}
		for _, container in ipairs({ MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer }) do
			local bar = Theme.Usable(container) and activeBar(container)
			local status = bar and bar.StatusBar
			if Theme.Usable(status) then
				under[container.GetName and container:GetName() or "?"] = {
					background = seen(status.Background),
					underlay = seen(status.Underlay),
					fill = seen(status.GetStatusBarTexture and status:GetStatusBarTexture()),
					prediction = seen(bar.ExhaustionLevelFillBar),
					barAlpha = bar.GetAlpha and bar:GetAlpha() or nil,
					width = status.GetWidth and status:GetWidth() or nil,
					opacity = Theme:Opacity(),
					restState = GetRestState and GetRestState() or nil,
				}
				-- Our own track: how far the fill and the rested reach cover it.
				local panel = Theme.Drawn(KEY, container)
				if panel then
					under[container.GetName and container:GetName() or "?"].panel = {
						progress = panel.progress:IsShown() and panel.progress:GetWidth() or 0,
						rested = panel.rested:IsShown() and panel.rested:GetWidth() or 0,
					}
				end
			end
		end
		Theme.db.statusBarUnder = under
	end)
end

local watched = {}

local function watch(container)
	if watched[container] or not hooksecurefunc or type(container.bars) ~= "table" then return end
	watched[container] = true
	for _, bar in pairs(container.bars) do
		local status = Theme.Usable(bar) and bar.StatusBar
		if Theme.Usable(status) then
			local function again()
				if Theme:IsOn(KEY) then
					hideStatusArt(bar)
					hideFrameArt(container)
				end
				paint(container)
			end
			if status.SetValue then hooksecurefunc(status, "SetValue", again) end
			if status.SetAnimatedValues then hooksecurefunc(status, "SetAnimatedValues", again) end
			if status.OnValueChanged then hooksecurefunc(status, "OnValueChanged", again) end
			if status.OnUpdate then hooksecurefunc(status, "OnUpdate", again) end
			if status.SetStatusBarTexture then hooksecurefunc(status, "SetStatusBarTexture", again) end
		end
		-- Where the game decides the bar's look: rested or not, and the reputation's reaction. A
		-- secret answer is forgotten, so the bar falls back to what it can read.
		if Theme.Usable(bar) and bar.UpdateStatusBarTextures then
			hooksecurefunc(bar, "UpdateStatusBarTextures", function(_, isRested)
				state[bar] = not Theme.Secret(isRested) and { rested = isRested == true } or nil
				paint(container)
			end)
		end
		if Theme.Usable(bar) and bar.UpdateBarTextures then
			hooksecurefunc(bar, "UpdateBarTextures", function(_, reaction, blue)
				if Theme.Secret(reaction) or Theme.Secret(blue) then
					state[bar] = nil
				else
					state[bar] = { reaction = reaction, blue = blue == true }
				end
				paint(container)
			end)
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
	help = "Replaces the experience and reputation bars with a flat bar: a dark track and a fill in "
		.. "the bar's own color, purple experience, blue while rested and reputation in its standing's "
		.. "color, in place of the frame and the textured bar.",
	optional = { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer", "GetRestState",
		"FACTION_BAR_COLORS", "StatusTrackingBarInfo.BarsEnum", "C_Reputation.GetWatchedFactionData" },
	frames = function()
		return { MainStatusTrackingBarContainer or false, SecondaryStatusTrackingBarContainer or false }
	end,
	style = function(container)
		hideFrameArt(container)
		if type(container.bars) == "table" then
			for _, bar in pairs(container.bars) do
				if Theme.Usable(bar) then hideStatusArt(bar) end
			end
		end
		hideDividers(container)
		watch(container)
		lookLater()
		local bar = activeBar(container)
		local status = bar and bar.StatusBar
		if not Theme.Usable(status) then return end
		-- With the bottom layout, the second bar sits under the main one, which shows the bar
		-- the game ranks highest, so only the main one is drawn: a watched reputation takes the
		-- experience bar's place.
		if Theme.BottomRow() and container == SecondaryStatusTrackingBarContainer then return end
		local panel = Theme.Draw(KEY, container, function()
			local panel = Theme.Panel(container, true, true)
			-- The rested reach under the fill, so it shows only ahead of the value. Paint colors both.
			panel.rested = panel:CreateTexture(nil, "ARTWORK")
			panel.rested:SetPoint("TOPLEFT")
			panel.rested:SetPoint("BOTTOMLEFT")
			panel.progress = panel:CreateTexture(nil, "ARTWORK", nil, 1)
			panel.progress:SetPoint("TOPLEFT")
			panel.progress:SetPoint("BOTTOMLEFT")
			return panel
		end)
		shapeTrack(panel, status)
		paint(container)
	end,
})
