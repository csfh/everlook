-- The theme: a flat look for some of the game's own frames, each a dark solid with one thin line
-- along its bottom in a muted gold, and no artwork. This file holds the style, the
-- panel it draws, and the engine that applies a surface; each surface (chat.lua, status_bars.lua,
-- action_bars.lua, micro_menu.lua, bags_bar.lua, tooltips.lua, level_badges.lua) is one record handed to Theme:Surface. AGENTS.md's "Restyling
-- the game's frames" holds the rules: the game's frames only have textures hidden and frames of
-- this addon's own drawn on them, and turning a surface off gives back every texture it hid.
local _, ns = ...

local Theme = Everlook:NewAddon("EverlookTheme", {
	label = "Theme",
	defaults = {
		chat = false,
		statusBars = false,
		actionBars = false,
		microMenu = false,
		bagsBar = false,
		-- The bottom bars lined up through an Everlook Edit Mode layout (bottom_layout.lua).
		bottomLayout = false,
		-- The chat window moved down to the experience bar's level, in the same layout.
		chatDown = false,
		-- Layout parts turned off and not yet put back (bottom_layout.lua).
		layoutTurnedOff = {},
		tooltips = false,
		levelBadges = false,
		-- How much of the scene the solids cover, 0 to 1.
		backgroundOpacity = 0.5,
	},
})
ns.Theme = Theme

-- What the engine and the style need; each surface adds its own in its record.
local NEEDS = { "hooksecurefunc", "CreateFrame", "InCombatLockdown", "PixelUtil.SetWidth", "PixelUtil.SetHeight" }
local OPTIONAL = { "issecretvalue" }

-- True for a value the game keeps secret (12.0).
function Theme.Secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

-- A frame or texture this addon may work with: a table the game hasn't made forbidden.
function Theme.Usable(frame)
	return type(frame) == "table" and not (frame.IsForbidden and frame:IsForbidden())
end

------------------------------------------------------------------------------------------------
-- Panels: the one shape the theme draws

-- The style: a dark solid under a surface's content and one accent line along its bottom edge,
-- in a muted gold, the same for every character. A surface that isn't the one in use (a chat tab
-- not selected) has a gray line instead. Colors are r, g, b, a; the solid's opacity is a setting.
Theme.BACKGROUND = { 0.05, 0.05, 0.06 }
Theme.ACCENT_IDLE = { 0.3, 0.3, 0.32, 1 }
-- The accent: the gold of the game's own headings (1, 0.82, 0) at 0.65 brightness, calmer
-- against the dark solid.
Theme.ACCENT = { 0.65, 0.533, 0, 1 }
-- The line's thickness in interface units, and never thinner than two screen pixels.
Theme.LINE = 2
Theme.LINE_PIXELS = 2

local panels = {} -- every panel made, to size its line again when the interface scale changes

-- The line is whole screen pixels, worked out from the panel's scale on screen.
local function sizeLine(panel)
	if panel.line then PixelUtil.SetHeight(panel.line, Theme.LINE, Theme.LINE_PIXELS) end
end

-- Colors a panel's line.
function Theme.Paint(panel, color)
	if panel.line then panel.line:SetVertexColor(color[1], color[2], color[3], color[4]) end
end

-- A panel on `parent`, for the caller to anchor. `fill` gives it the dark solid and `line` the
-- accent along its bottom edge, just inside it. It draws at its parent's frame level, so on a
-- frame with text of its own (a tab, a tooltip) the solid stays under the text by its layer.
function Theme.Panel(parent, fill, line)
	local panel = CreateFrame("Frame", nil, parent)
	panel:SetUsingParentLevel(true)
	if fill then
		panel.fill = panel:CreateTexture(nil, "BACKGROUND")
		panel.fill:SetAllPoints()
		panel.fill:SetColorTexture(Theme.BACKGROUND[1], Theme.BACKGROUND[2], Theme.BACKGROUND[3], Theme:Opacity())
	end
	if line then
		panel.line = panel:CreateTexture(nil, "BORDER")
		panel.line:SetColorTexture(1, 1, 1, 1)
		panel.line:SetPoint("BOTTOMLEFT")
		panel.line:SetPoint("BOTTOMRIGHT")
		sizeLine(panel)
		Theme.Paint(panel, Theme.ACCENT)
	end
	panels[#panels + 1] = panel
	return panel
end

function Theme:SizeLines()
	for _, made in ipairs(panels) do sizeLine(made) end
end

function Theme:Opacity()
	return self.db and self.db.backgroundOpacity or self.defaults.backgroundOpacity
end

-- Every solid at the opacity now set.
function Theme:FillAll()
	for _, made in ipairs(panels) do
		if made.fill then
			made.fill:SetColorTexture(Theme.BACKGROUND[1], Theme.BACKGROUND[2], Theme.BACKGROUND[3], self:Opacity())
		end
	end
end

------------------------------------------------------------------------------------------------
-- The engine
--
-- A surface record:
--   key          its setting, one of the defaults above
--   label, help  its checkbox on the settings page
--   needs        the game names it uses, for EverlookQA; optional, the ones with a fallback
--   frames()     the game frames it restyles, found fresh each time it applies
--   style(frame) restyles one frame, with Theme.HideArt and Theme.Draw only
--   combat       true if it draws on protected frames: then it applies only out of combat
--   after()      runs after every apply, in combat too (only on this addon's own frames)
--   enable()     its hooks and events, once at login; events through Theme:On, never RegisterEvent
-- Surfaces are applied, and appear on the settings page, in the TOC's order.

Theme.surfaces = {}
local byKey = {}

function Theme:Surface(record)
	self.surfaces[#self.surfaces + 1] = record
	byKey[record.key] = record
end

function Theme:IsOn(key)
	return self.db ~= nil and self.db[key] == true
end

-- The game's own textures a surface hid, and how: "hide" (Hide, Show to undo) for art the game
-- fades by alpha, "alpha" (SetAlpha 0, 1 to undo) for art the game shows and hides itself.
-- A faded texture the game keeps below full alpha names that alpha as `restore`.
local hidden = {} -- [key] = { [texture] = "hide" | "alpha" }
local restoreAlpha = {} -- [texture] = the alpha the game gives it, when not 1

function Theme.HideArt(key, texture, how, restore)
	if not Theme.Usable(texture) then return end
	hidden[key] = hidden[key] or {}
	hidden[key][texture] = how
	restoreAlpha[texture] = restore
	if how == "hide" then texture:Hide() else texture:SetAlpha(0) end
end

local function restoreArt(key)
	for texture, how in pairs(hidden[key] or {}) do
		if how == "hide" then texture:Show() else texture:SetAlpha(restoreAlpha[texture] or 1) end
	end
	hidden[key] = nil
end

-- The frames a surface drew, keyed by the game frame they're on, so turning it off hides them.
local drawn = {} -- [key] = { [host] = frame }

-- The frame `key` drew on `host`, made by `make` the first time, and shown.
function Theme.Draw(key, host, make)
	drawn[key] = drawn[key] or {}
	local frame = drawn[key][host]
	if not frame then
		frame = make()
		drawn[key][host] = frame
	end
	frame:Show()
	return frame
end

-- The frame `key` drew on `host`, if any.
function Theme.Drawn(key, host)
	return drawn[key] and drawn[key][host]
end

-- Every game frame `key` drew on, and what it drew there.
function Theme.Hosts(key)
	return pairs(drawn[key] or {})
end

-- A tile on a button: the dark solid under the button's own art and the line over it, drawn by
-- `key` and inset by `inset` units on each side (0 when nil). The action, micro and bag buttons use it.
function Theme.Tile(key, button, inset)
	return Theme.Draw(key, button, function()
		local tile = Theme.Panel(button, true, true)
		inset = inset or 0
		tile:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
		tile:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
		-- Icons sit in the BACKGROUND or ARTWORK layer: the solid goes under them all and the line
		-- over them, so an icon covers neither.
		tile.fill:SetDrawLayer("BACKGROUND", -8)
		tile.line:SetDrawLayer("OVERLAY")
		return tile
	end)
end

-- The dividers a bar lays out between its buttons (MainActionBarMixin:UpdateDividers,
-- BagsBarMixin:UpdateDividers): NineSlice frames from the bar's two pools, so every piece of each
-- is hidden. The game shows the divider frames themselves.
function Theme.HideDividers(key, bar)
	for _, pool in ipairs({ bar.HorizontalDividersPool or false, bar.VerticalDividersPool or false }) do
		if pool and pool.EnumerateActive then
			for divider in pool:EnumerateActive() do
				if Theme.Usable(divider) and divider.GetRegions then
					for _, region in ipairs({ divider:GetRegions() }) do Theme.HideArt(key, region, "hide") end
				end
			end
		end
	end
end

-- Everlook keeps one handler per event per addon, so the engine and every surface share an event
-- through here: each `fn(event, ...)` runs, in the order they were added.
local handlers = {} -- [event] = { fn, ... }

function Theme:On(event, fn)
	if not handlers[event] then
		local list = {}
		handlers[event] = list
		self:RegisterEvent(event, function(...)
			for _, handler in ipairs(list) do handler(...) end
		end)
	end
	table.insert(handlers[event], fn)
end

local waiting = {} -- [key] = true for a surface on protected frames held back by combat

function Theme:Apply(key)
	local record = byKey[key]
	for _, made in pairs(drawn[key] or {}) do made:Hide() end
	if not self:IsOn(key) then
		-- What it drew is hidden at once, but the game's own art on protected frames comes back
		-- only after combat, as touching it is what the combat rule holds back.
		if record.combat and InCombatLockdown() then
			waiting[key] = true
			return
		end
		waiting[key] = nil
		return restoreArt(key)
	end
	if record.combat and InCombatLockdown() then
		waiting[key] = true
	else
		waiting[key] = nil
		for _, frame in ipairs(record.frames()) do
			if Theme.Usable(frame) then record.style(frame) end
		end
	end
	if record.after then record.after() end
end

function Theme:ApplyAll()
	for _, record in ipairs(self.surfaces) do self:Apply(record.key) end
end

------------------------------------------------------------------------------------------------

function Theme:OnInitialize()
	local needs, optional = {}, {}
	for _, name in ipairs(NEEDS) do needs[#needs + 1] = name end
	for _, name in ipairs(OPTIONAL) do optional[#optional + 1] = name end
	for _, record in ipairs(self.surfaces) do
		for _, name in ipairs(record.needs or {}) do needs[#needs + 1] = name end
		for _, name in ipairs(record.optional or {}) do optional[#optional + 1] = name end
	end
	for _, name in ipairs(self.BottomLayout.NEEDS) do optional[#optional + 1] = name end
	-- Called here, once every surface file has loaded, as EverlookQA keeps one list per addon.
	EverlookQA:Expect("EverlookTheme", needs, optional)

	local page = EverlookPreferences:NewPage(self, "Interface")
	for _, record in ipairs(self.surfaces) do page:Checkbox(record.key, record.label, record.help) end
	page:Checkbox("bottomLayout", "Line up the bottom bars",
		"Keeps an Edit Mode layout named Everlook, a copy of yours, and switches to it: Action Bar 4 and 5 on "
		.. "top, Action Bar 2 and 3 under them, then the main bar, micro menu and bags, and the experience bar "
		.. "along the bottom, all with the same edges, even gaps and smaller square buttons. Turn on Action "
		.. "Bar 4 and 5 under Settings, Action Bars to fill the top row. A watched reputation takes the experience bar's place. It "
		.. "waits for combat to end and Edit Mode to close. While it is on, changes you make to the bottom bars "
		.. "in that layout are put back. Turned off, the bars go back to the game's defaults; with Move the "
		.. "chat down off too, it switches back to the game's own layout if you are still on Everlook's.")
	page:Checkbox("chatDown", "Move the chat down",
		"Moves the chat window down until its input line is level with the experience bar, in the same "
		.. "Everlook Edit Mode layout. Turned off, the chat goes back to where the game's own layout has it.")
	page:Slider("backgroundOpacity", "Background opacity",
		"How much of the scene the dark backgrounds cover, on every surface above.", 0.1, 1, 0.05, EverlookPreferences.Percent)
end

function Theme:OnEnable()
	for _, record in ipairs(self.surfaces) do
		if record.enable then record.enable() end
	end
	self:On("PLAYER_REGEN_ENABLED", function()
		for key in pairs(waiting) do self:Apply(key) end
	end)
	-- A screen pixel is a different number of units after either; the lines stay one pixel.
	self:On("UI_SCALE_CHANGED", function() self:SizeLines() end)
	self:On("DISPLAY_SIZE_CHANGED", function() self:SizeLines() end)
	self.BottomLayout.Enable()
	self:ApplyAll()
end

function Theme:OnSettingChanged(key)
	if key == "backgroundOpacity" then return self:FillAll() end
	if key == "bottomLayout" or key == "chatDown" then
		if not self:IsOn(key) then self.BottomLayout.TurnedOff(key) end
		return self.BottomLayout.Apply(true)
	end
	if byKey[key] then self:Apply(key) end
end
