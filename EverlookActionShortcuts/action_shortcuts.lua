local ActionShortcuts = Everlook:NewAddon("EverlookActionShortcuts", {
	label = "Action Shortcuts",
	defaults = {
		shorten = true,
		style = false,
		font = "game",
		size = 12,
		outline = "game",
		shadow = "game",
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookActionShortcuts", {
	"ActionBarButtonEventsFrame.ForEachFrame",
	"ActionBarButtonEventsFrame.RegisterFrame",
	"hooksecurefunc",
	"InCombatLockdown",
	"NumberFontNormalSmallGray",
}, {
	"RANGE_INDICATOR",
})

-- Blizzard_ActionBar/Shared/ActionButton.lua (12.0.0) registers each button with
-- ActionBarButtonEventsFrame and writes its HotKey text in UpdateHotkeys.
local hookedButtons = setmetatable({}, { __mode = "k" })
local managerHooked = false
local labels = setmetatable({}, { __mode = "k" }) -- [HotKey font string] = { original, applied }

local function readable(text)
	return not (issecretvalue and issecretvalue(text)) and type(text) == "string"
end

-- "s-a-4" -> "SA4", "s-4" -> "S4". Ctrl and labels without Shift or Alt stay as they are.
function ActionShortcuts.Shorten(text)
	local prefix, key = "", text
	while true do
		local modifier, rest = key:match("^([sSaA])%-(.+)$")
		if not modifier then break end
		prefix, key = prefix .. modifier:upper(), rest
	end
	return prefix .. key
end

local function compact(button)
	local font = button.HotKey
	if not font or type(font.GetText) ~= "function" or type(font.SetText) ~= "function" then return end
	local text = font:GetText()
	if not readable(text) then return end
	local short = ActionShortcuts.Shorten(text)
	if short == text then return end
	labels[font] = { original = text, applied = short }
	font:SetText(short)
end

-- Puts back each label we shortened, unless something else changed it since.
local function restore()
	for font, state in pairs(labels) do
		local text = font:GetText()
		if readable(text) and text == state.applied then font:SetText(state.original) end
		labels[font] = nil
	end
end

------------------------------------------------------------------------------------------------
-- The labels' look: a token's font, a size, an outline and a shadow, set only while "style" is on.
--
-- The labels inherit NumberFontNormalSmallGray: Arial Narrow at 12 points with an outline and no
-- shadow (GameFontStyles.xml and GameFonts.xml, Blizzard_Fonts_Shared, 12.0.0), which EverlookFonts
-- keeps on the game's file. Turned off, each label is given that font object again.
ActionShortcuts.OUTLINES = { none = "", thick = "THICKOUTLINE" }
ActionShortcuts.SHADOWS = { soft = { 1, 0.5 }, strong = { 2, 1 } } -- offset, alpha
local styled = setmetatable({}, { __mode = "k" }) -- [HotKey font string] = true while this addon set it
local waiting = setmetatable({}, { __mode = "k" }) -- labels to style once combat ends

-- A button with no key bound shows RANGE_INDICATOR ("●", ActionButton.lua, 12.0.0) in its label
-- while out of range. Only the game's font draws it, so the label keeps that file meanwhile.
local function showsRangeDot(label)
	if type(RANGE_INDICATOR) ~= "string" then return false end
	local text = label:GetText()
	return readable(text) and text == RANGE_INDICATOR
end

-- A font string doesn't always redraw when its font changes, so its text is set again.
local function redraw(label)
	local text = label:GetText()
	if readable(text) then label:SetText(text) end
end

-- The game font's shadow; SetFontObject doesn't take back a shadow set on the label itself.
local function gameShadow(label)
	local game = NumberFontNormalSmallGray
	label:SetShadowOffset(game:GetShadowOffset())
	label:SetShadowColor(game:GetShadowColor())
end

local function unstyle(label)
	if not styled[label] then return end
	styled[label] = nil
	label:SetFontObject(NumberFontNormalSmallGray)
	gameShadow(label)
	redraw(label)
end

local function style(label)
	if type(label) ~= "table" or type(label.SetFont) ~= "function" then return end
	if label.IsForbidden and label:IsForbidden() then return end
	local db = ActionShortcuts.db
	if InCombatLockdown() then
		waiting[label] = true
		return
	end
	if not db.style then return unstyle(label) end
	local game = NumberFontNormalSmallGray
	local file, _, flags = game:GetFont()
	local token = Everlook.Font[db.font]
	if token and not showsRangeDot(label) then file = token:GetFont() or file end
	if not file then return end
	flags = ActionShortcuts.OUTLINES[db.outline] or flags or ""
	label:SetFont(file, db.size, flags)
	local shadow = ActionShortcuts.SHADOWS[db.shadow]
	if shadow then
		label:SetShadowOffset(shadow[1], -shadow[1])
		label:SetShadowColor(0, 0, 0, shadow[2])
	else
		gameShadow(label)
	end
	styled[label] = true
	redraw(label)
end

local function refresh(button)
	if ActionShortcuts.db.shorten then compact(button) end
	if ActionShortcuts.db.style or styled[button.HotKey] then style(button.HotKey) end
end

local function attach(button)
	if type(button.UpdateHotkeys) ~= "function" then return end
	if not hookedButtons[button] then
		-- The mixin was copied onto existing buttons, so each button is hooked, keeping the
		-- label through Blizzard's UPDATE_BINDINGS refresh.
		hooksecurefunc(button, "UpdateHotkeys", refresh)
		hookedButtons[button] = true
	end
	refresh(button)
end

local function manager()
	local frame = ActionBarButtonEventsFrame
	if type(frame) ~= "table" or type(frame.ForEachFrame) ~= "function" or type(frame.RegisterFrame) ~= "function" then
		return nil
	end
	return frame
end

function ActionShortcuts:Apply()
	if not self.db.shorten then restore() end
	local frame = manager()
	if not frame then return end
	if (self.db.shorten or self.db.style) and not managerHooked then
		hooksecurefunc(frame, "RegisterFrame", function(_, button)
			if self.db.shorten or self.db.style then attach(button) end
		end)
		managerHooked = true
	end
	if self.db.shorten or self.db.style then
		frame:ForEachFrame(attach)
	else
		frame:ForEachFrame(function(button) if styled[button.HotKey] then style(button.HotKey) end end)
	end
end

local function styleWaiting()
	for label in pairs(waiting) do
		waiting[label] = nil
		style(label)
	end
end

function ActionShortcuts:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Action Bars")
	page:Checkbox("shorten", "Shorten hotkey labels",
		"Show Shift and Alt on action bar hotkeys as S and A, so s-4 reads S4 and s-a-4 reads SA4.")
	page:Checkbox("style", "Style hotkey labels",
		"Give the action bar hotkey labels the font, size, outline and shadow below. Off, they're the game's.")
	local fonts = { { "game", "Game's font" } }
	for _, token in ipairs(Everlook.FONT_TOKENS) do fonts[#fonts + 1] = { token, token .. " token" } end
	page:Dropdown("font", "Hotkey font",
		"The labels' font: the game's, or the font Fonts gives one of Everlook's tokens. The range dot always shows in the game's font. Needs Style hotkey labels.",
		fonts)
	page:Slider("size", "Hotkey size", "The labels' font size; the game's is 12. Needs Style hotkey labels.", 8, 20, 1)
	page:Dropdown("outline", "Hotkey outline", "An outline around the labels. Needs Style hotkey labels.",
		{ { "game", "Outline, the game's" }, { "none", "None" }, { "thick", "Thick outline" } })
	page:Dropdown("shadow", "Hotkey shadow", "A shadow behind the labels. Needs Style hotkey labels.",
		{ { "game", "None, the game's" }, { "soft", "Soft" }, { "strong", "Strong" } })
end

function ActionShortcuts:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Apply")
	self:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_ActionBar" then self:Apply() end
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", styleWaiting)
	-- A token's new font shows on the labels at once.
	hooksecurefunc(Everlook, "SetFontToken", function(name)
		if self.db.style and name == self.db.font then self:Apply() end
	end)
	self:Apply()
end

function ActionShortcuts:OnSettingChanged()
	self:Apply()
end
