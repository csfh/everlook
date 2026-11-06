local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookUnitFrames")

-- Hooks run after the function they hook, as hooksecurefunc does.
hooksecurefunc = function(target, name, fn)
	if type(target) == "string" then target, name, fn = _G, target, name end
	local original = target[name]
	target[name] = function(...)
		local a, b, c, d, e = original(...)
		fn(...)
		return a, b, c, d, e
	end
end

-- Units: who they are and how they see you.
local units = {
	player = { player = true, class = "MAGE" },
	target = { reaction = 2 },
	party1 = { player = true, class = "PRIEST" },
}
UnitIsPlayer = function(unit) return units[unit] and units[unit].player == true end
UnitClass = function(unit) local u = units[unit] return u and u.class, u and u.class end
UnitReaction = function(unit) return units[unit] and units[unit].reaction end
UnitIsTapDenied = function(unit) return units[unit] and units[unit].tapped == true end
RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PRIEST = { r = 1, g = 1, b = 1 } }
FACTION_BAR_COLORS = { [2] = { r = 1, g = 0, b = 0 }, [4] = { r = 1, g = 1, b = 0 } }
GetClassAtlas = function(class) return "classicon-" .. class:lower() end
BreakUpLargeNumbers = function(value) return tostring(value) end
AbbreviateLargeNumbers = function(value) return "abbr" .. value end

-- Text that shows and hides.
local function text()
	local s = t.widget()
	s.shown = true
	return s
end

-- A status bar with the game's text code copied in (TextStatusBarMixin), reduced to what
-- matters here: the game writes its own text, then the hook runs.
local function bar(unit, frame)
	local b = t.widget()
	b.unit, b.unitFrame = unit, frame
	b.TextString, b.LeftText, b.RightText = text(), text(), text()
	b.value, b.max = 12345, 45678
	b.capNumericDisplay = true -- UnitFrame_Initialize sets it on every health and mana bar
	b.fill = { desaturated = false }
	function b.fill:SetDesaturated(on) self.desaturated = on end
	function b:GetStatusBarTexture() return self.fill end
	function b:SetStatusBarColor(r, g, bl) self.rgb = { r, g, bl } end
	function b:UpdateTextStringWithValues(textString, value, _, valueMax)
		-- The game's Both layout: percent on the left, value on the right, middle hidden.
		self.LeftText:SetText(math.ceil(value / valueMax * 100) .. "%")
		self.LeftText:Show()
		self.RightText:SetText(tostring(value))
		self.RightText:Show()
		textString:SetText("")
		textString:Hide()
	end
	function b:GetValue() return self.value end
	function b:GetMinMaxValues() return 0, self.max end
	function b:UpdateTextString()
		self:UpdateTextStringWithValues(self.TextString, self.value, 0, self.max)
	end
	return b
end

-- A font string's font, and the font it inherits.
local function fontString(size)
	local s = t.widget()
	s.font = { "Fonts\\FRIZQT__.TTF", size, "" }
	local object = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end }
	function s:GetFont() return self.font[1], self.font[2], self.font[3] end
	function s:SetFont(path, sz, flags) self.font = { path, sz, flags } end
	function s:GetFontObject() return object end
	return s
end

local function unitFrame(unit)
	local f = t.widget()
	f.unit = unit
	f.healthbar = bar(unit, f)
	f.manabar = bar(unit, f)
	f.name = fontString(10)
	f.portrait = t.widget()
	function f.portrait:SetAtlas(atlas) self.atlas = atlas end
	return f
end

PlayerFrame = unitFrame("player")
TargetFrame = unitFrame("target")
function TargetFrame:CheckClassification()
	self.healthbar.fill.desaturated = false -- the game swaps in a new atlas
end
PetFrame = unitFrame("pet")

-- The game's functions, as far as this addon sees them.
UnitFrame_Update = function() end
UnitFrameHealthBar_Update = function(statusbar) statusbar:SetStatusBarColor(0, 1, 0) end
UnitFrameManaBar_Update = function() end
HealthBar_OnValueChanged = function(self) self:SetStatusBarColor(0, 1, 0) end
UnitFramePortrait_Update = function(frame) frame.portrait.atlas = "face" end

t.cvars.statusTextDisplay = "BOTH"
local defaults = { ReplaceMyPlayerPortrait = "0", ReplaceOtherPlayerPortraits = "0" }
GetCVarDefault = function(name) return defaults[name] end

t.load("EverlookUnitFrames")
t.fire("PLAYER_LOGIN")
local U = Everlook:GetAddon("EverlookUnitFrames")
local db = U.db

check(not db.classHealth and not db.classPortraits and not db.shortNumbers and not db.currentOnly
	and not db.oneLine and not db.resizeNames and db.nameSize == 10, "every switch starts off, names at 10 pt")
check(t.has("page Unit Frames"), "its page sits in the Unit Frames folder")
check(t.settings.EverlookUnitFrames_nameSize.slider.min == 8 and t.settings.EverlookUnitFrames_nameSize.slider.max == 16,
	"name size runs from 8 to 16 points")

-- Short numbers.
check(U.Short(999) == "999" and U.Short(1000) == "1k" and U.Short(12345) == "12.3k"
	and U.Short(999949) == "999.9k" and U.Short(999950) == "1m" and U.Short(2345678) == "2.3m",
	"short numbers: 999, 1k, 12.3k, 999.9k, 1m, 2.3m")

-- Health color.
local health = PlayerFrame.healthbar
HealthBar_OnValueChanged(health)
check(health.rgb[2] == 1 and not health.fill.desaturated, "off: the game's green stays")
t.change("EverlookUnitFrames_classHealth", true)
check(health.rgb[1] == 0.25 and health.fill.desaturated, "on: the player's bar takes the class color at once")
HealthBar_OnValueChanged(health)
check(health.rgb[1] == 0.25, "and keeps it when health changes")
UnitFrameHealthBar_Update(TargetFrame.healthbar, "target")
check(TargetFrame.healthbar.rgb[1] == 1 and TargetFrame.healthbar.rgb[2] == 0, "a hostile NPC's bar is red")
units.target.tapped = true
HealthBar_OnValueChanged(TargetFrame.healthbar)
check(TargetFrame.healthbar.rgb[1] == 0.5, "a tapped NPC's bar is gray")
units.target.tapped = nil
units.target.reaction = nil
HealthBar_OnValueChanged(TargetFrame.healthbar)
check(not TargetFrame.healthbar.fill.desaturated and TargetFrame.healthbar.rgb[2] == 1,
	"a unit with no reaction gets the game's own bar back, not a gray one tinted green")
units.target.reaction = 2
TargetFrame:CheckClassification()
check(TargetFrame.healthbar.fill.desaturated, "a rank change on the target redraws the color")
HealthBar_OnValueChanged(PetFrame.healthbar)
check(PetFrame.healthbar.rgb[2] == 1 and not PetFrame.healthbar.fill.desaturated, "the pet frame keeps the game's look")
health.disconnected = true
health:SetStatusBarColor(0.5, 0.5, 0.5)
HealthBar_OnValueChanged(health)
check(health.rgb[2] == 1, "a disconnected player's bar is left to the game") -- the stub greens it
health.disconnected = nil
HealthBar_OnValueChanged(health)
t.change("EverlookUnitFrames_classHealth", false)
check(health.rgb[1] == 0 and health.rgb[2] == 1 and not health.fill.desaturated
	and TargetFrame.healthbar.rgb[2] == 1, "off: bars go back to the game's green")

-- Portraits: the game's own settings.
t.change("EverlookUnitFrames_classPortraits", true)
check(t.cvars.ReplaceMyPlayerPortrait == "1" and t.cvars.ReplaceOtherPlayerPortraits == "1",
	"on: the game's class-icon portrait settings are on")
check(PlayerFrame.portrait.atlas == "face", "the game draws the portrait, no hook needed")
t.change("EverlookUnitFrames_classPortraits", false)
check(t.cvars.ReplaceMyPlayerPortrait == "0" and t.cvars.ReplaceOtherPlayerPortraits == "0",
	"off: back to the game's defaults")

-- A client without those settings: the addon draws the icon itself.
defaults = {}
t.change("EverlookUnitFrames_classPortraits", true)
check(PlayerFrame.portrait.atlas == "classicon-mage", "no portrait settings: players get their class icon")
UnitFramePortrait_Update(TargetFrame)
check(TargetFrame.portrait.atlas == "face", "an NPC keeps its face")
t.change("EverlookUnitFrames_classPortraits", false)
check(PlayerFrame.portrait.atlas == "face", "off: the game draws the face again")
defaults = { ReplaceMyPlayerPortrait = "0", ReplaceOtherPlayerPortraits = "0" }

-- Bar text, Status Text on Both.
health:UpdateTextString()
check(health.RightText.text == "12345" and health.LeftText.text == "28%", "off: the game's text stays")
t.change("EverlookUnitFrames_shortNumbers", true)
check(health.RightText.text == "12.3k" and health.LeftText.text == "28%", "short numbers on the right, percent stays")
t.change("EverlookUnitFrames_oneLine", true)
check(health.TextString.text == "12.3k / 45.7k (28%)" and health.TextString.shown
	and not health.LeftText.shown and not health.RightText.shown, "one line: value, maximum and percent in the middle")
t.change("EverlookUnitFrames_currentOnly", true)
check(health.TextString.text == "12.3k (28%)", "current only drops the maximum")
local rage = PlayerFrame.manabar
rage.powerToken = "RAGE"
rage:UpdateTextString()
check(rage.TextString.text == "12.3k", "power other than mana shows no percent, as in the game")

t.cvars.statusTextDisplay = "NUMERIC"
function health:UpdateTextStringWithValues(textString, value, _, valueMax)
	self.LeftText:Hide()
	self.RightText:Hide()
	textString:SetText(value .. " / " .. valueMax)
	textString:Show()
end
hooksecurefunc(health, "UpdateTextStringWithValues", U.Rewrite) -- the game's method was replaced
health:UpdateTextString()
check(health.TextString.text == "12.3k", "Numeric: short current value")
t.change("EverlookUnitFrames_shortNumbers", false)
check(health.TextString.text == "abbr12345", "short off: the game's own abbreviation")
t.change("EverlookUnitFrames_currentOnly", false)
t.change("EverlookUnitFrames_oneLine", false)
check(health.TextString.text == "12345 / 45678", "all off: the game's text again")

t.cvars.statusTextDisplay = "PERCENT"
t.change("EverlookUnitFrames_shortNumbers", true)
function health:UpdateTextStringWithValues(textString) textString:SetText("28%") textString:Show() end
hooksecurefunc(health, "UpdateTextStringWithValues", U.Rewrite)
health:UpdateTextString()
check(health.TextString.text == "28%", "Percentage: left as the game wrote it")

t.cvars.statusTextDisplay = "NUMERIC"
health.TextString:Hide()
function health:UpdateTextStringWithValues(textString) textString:SetText("") textString:Hide() end
hooksecurefunc(health, "UpdateTextStringWithValues", U.Rewrite)
health:UpdateTextString()
check(health.TextString.text == "", "text the game hid (until mouseover) stays hidden")

-- Secret numbers stay as the game wrote them.
issecretvalue = function(value) return value == 777 end
function health:UpdateTextStringWithValues(textString) textString:SetText("secret") textString:Show() end
hooksecurefunc(health, "UpdateTextStringWithValues", U.Rewrite)
health.value = 777
health:UpdateTextString()
check(health.TextString.text == "secret", "a secret value is left to the game")
health.TextString:SetText("kept")
t.change("EverlookUnitFrames_currentOnly", true)
check(health.TextString.text == "kept", "a switch flipped while a value is secret doesn't ask the game to redraw it")
t.change("EverlookUnitFrames_currentOnly", false)
issecretvalue = nil
t.change("EverlookUnitFrames_shortNumbers", false)

-- Name size.
t.change("EverlookUnitFrames_nameSize", 13)
check(PlayerFrame.name.font[2] == 10, "the size waits for Resize unit names")
t.change("EverlookUnitFrames_resizeNames", true)
check(PlayerFrame.name.font[2] == 13 and TargetFrame.name.font[2] == 13, "on: names take the chosen size")
check(PetFrame.name.font[2] == 10, "the pet's name stays")
PlayerFrame.name.font[1] = "Interface\\AddOns\\EverlookFonts\\assets\\inter.ttf"
t.change("EverlookUnitFrames_nameSize", 12)
check(PlayerFrame.name.font[1]:find("inter") and PlayerFrame.name.font[2] == 12, "a size change keeps the font Fonts chose")
local party = unitFrame("party1")
UnitFrame_Update(party)
check(party.name.font[2] == 12, "a party frame set up later gets the size too")
t.change("EverlookUnitFrames_resizeNames", false)
check(PlayerFrame.name.font[2] == 10 and PlayerFrame.name.font[1]:find("inter") and party.name.font[2] == 10,
	"off: back to the size of the font names inherit, the font stays")

t.done()
