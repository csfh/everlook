-- Changes to the game's own unit frames (player, target, focus, their targets, party and boss):
-- health colored by class or reaction, class icons for player portraits, shorter bar text, and
-- the size of the unit's name. Each has its own switch; turning one off gives the frame back to
-- the game. Nothing here is protected, so none of it waits for combat.
local UnitFrames = Everlook:NewAddon("EverlookUnitFrames", {
	label = "Unit Frames",
	defaults = {
		classHealth = false,
		classPortraits = false,
		shortNumbers = false,
		currentOnly = false,
		oneLine = false,
		resizeNames = false,
		nameSize = 10, -- GameFontNormalSmall, the font every unit frame name inherits (FontStyles.xml, 12.0.0)
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookUnitFrames", {
	"hooksecurefunc",
	"UnitFrame_Update",
	"UnitFrameHealthBar_Update",
	"UnitFrameManaBar_Update",
	"HealthBar_OnValueChanged",
	"UnitFramePortrait_Update",
	"UnitIsPlayer",
	"UnitClass",
	"UnitReaction",
	"RAID_CLASS_COLORS",
	"FACTION_BAR_COLORS",
	"GetCVar",
	"SetCVar",
	"PlayerFrame",
	"TargetFrame",
}, {
	"GetCVarDefault",
	"GetClassAtlas",
	"UnitIsTapDenied",
	"issecretvalue",
	"BreakUpLargeNumbers",
	"AbbreviateLargeNumbers",
	"FocusFrame",
	"TargetFrame.CheckClassification",
	"PartyFrame.PartyMemberFramePool",
	"MAX_BOSS_FRAMES",
})

-- The units whose frames this addon changes. Pets, vehicles and raid-style frames keep the game's look.
local UNITS = { player = true, target = true, focus = true, targettarget = true, focustarget = true }
for i = 1, 4 do UNITS["party" .. i] = true end
for i = 1, 8 do UNITS["boss" .. i] = true end

local function covered(object)
	return type(object) == "table" and UNITS[object.unit] == true
end

-- The frames there are now: the fixed ones, then the party members the game has set up.
local function frames()
	local list = {}
	local function add(frame)
		if type(frame) == "table" then list[#list + 1] = frame end
	end
	add(PlayerFrame)
	for _, frame in ipairs({ TargetFrame, FocusFrame or false }) do
		if frame then
			add(frame)
			add(frame.totFrame)
		end
	end
	for i = 1, MAX_BOSS_FRAMES or 5 do add(_G["Boss" .. i .. "TargetFrame"]) end
	local pool = type(PartyFrame) == "table" and PartyFrame.PartyMemberFramePool
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for member in pool:EnumerateActive() do add(member) end
	end
	return list
end

local function bars(frame)
	return frame.healthbar, frame.manabar
end

-- In 12.0 a unit's numbers can be secret, which addon code can't compare or format. Text with
-- one stays as the game wrote it.
local function secret(value)
	return issecretvalue ~= nil and issecretvalue(value)
end

------------------------------------------------------------------------------------------------
-- Health color

-- The game's health bars are drawn green and then tinted green (UnitFrameHealthBar_Update and
-- HealthBar_OnValueChanged, 12.0.0). A tint can only darken, so the bar is drawn in gray first.
local painted = setmetatable({}, { __mode = "k" })

-- A player's class color; anyone else's reaction to you, hostile red to friendly green, or gray
-- once someone else has tapped them.
function UnitFrames.HealthColor(unit)
	if UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local color = class and RAID_CLASS_COLORS[class]
		if color then return color.r, color.g, color.b end
		return nil
	end
	if UnitIsTapDenied and UnitIsTapDenied(unit) then return 0.5, 0.5, 0.5 end
	local reaction = UnitReaction(unit, "player")
	local color = reaction and FACTION_BAR_COLORS[reaction]
	if color then return color.r, color.g, color.b end
end

-- A bar this addon grayed that it no longer colors (a disconnected player, a vehicle, a unit with
-- no reaction) gets its own texture back, so the game's tint looks as it should.
local function release(bar)
	if not painted[bar] then return end
	bar:GetStatusBarTexture():SetDesaturated(false)
	painted[bar] = nil
end

local function paint(bar)
	if type(bar) ~= "table" or not UnitFrames.db.classHealth then return end
	local r, g, b
	-- A disconnected player's bar stays the game's gray.
	if covered(bar) and bar.unitFrame and not bar.disconnected and not bar.lockColor then
		r, g, b = UnitFrames.HealthColor(bar.unit)
	end
	if not r then return release(bar) end
	bar:GetStatusBarTexture():SetDesaturated(true)
	bar:SetStatusBarColor(r, g, b)
	painted[bar] = true
end

-- Back to the game's own colors: gray while disconnected, else green (UnitFrameHealthBar_Update).
local function unpaint()
	for bar in pairs(painted) do
		bar:GetStatusBarTexture():SetDesaturated(false)
		if bar.disconnected then
			bar:SetStatusBarColor(0.5, 0.5, 0.5)
		else
			bar:SetStatusBarColor(0.0, 1.0, 0.0)
		end
		painted[bar] = nil
	end
end

------------------------------------------------------------------------------------------------
-- Portraits

-- The game can already show class icons in place of player portraits; these settings switch it
-- (UnitFrame_ShouldReplacePortrait, 12.0.0). A client without them gets the same through a hook.
local PORTRAIT_CVARS = { "ReplaceMyPlayerPortrait", "ReplaceOtherPlayerPortraits" }

local function portraitSettings()
	if not GetCVarDefault then return false end
	for _, name in ipairs(PORTRAIT_CVARS) do
		if GetCVarDefault(name) == nil then return false end
	end
	return true
end

local function classPortrait(frame)
	if not UnitFrames.db.classPortraits or portraitSettings() or not GetClassAtlas then return end
	if not covered(frame) or not frame.portrait or not UnitIsPlayer(frame.unit) then return end
	local _, class = UnitClass(frame.unit)
	local atlas = class and GetClassAtlas(class)
	if atlas then frame.portrait:SetAtlas(atlas) end
end

-- `changed` is true when the player just flipped the switch; only then does off reset the
-- game's settings, so a choice made in the game's own options survives a login.
local function applyPortraits(changed)
	local on = UnitFrames.db.classPortraits
	if not on and not changed then return end
	if portraitSettings() then
		for _, name in ipairs(PORTRAIT_CVARS) do
			SetCVar(name, on and "1" or GetCVarDefault(name))
		end
	end
	for _, frame in ipairs(frames()) do
		if covered(frame) and frame.portrait then UnitFramePortrait_Update(frame) end
	end
end

------------------------------------------------------------------------------------------------
-- Bar text

-- 12345 as 12.3k, 2345678 as 2.3m; below a thousand as it is.
function UnitFrames.Short(value)
	local size = math.abs(value)
	local text, unit
	if size >= 999950 then
		text, unit = ("%.1f"):format(value / 1e6), "m"
	elseif size >= 1000 then
		text, unit = ("%.1f"):format(value / 1e3), "k"
	else
		return tostring(value)
	end
	return (text:gsub("%.0$", "")) .. unit
end

-- One number as the game would write it on this bar (TextStatusBarMixin, 12.0.0), or short.
local function number(bar, value)
	if UnitFrames.db.shortNumbers then return UnitFrames.Short(value) end
	if bar.capNumericDisplay and AbbreviateLargeNumbers then return AbbreviateLargeNumbers(value) end
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(value) end
	return tostring(value)
end

local function numeric(bar, value, valueMax)
	local text = number(bar, value)
	if UnitFrames.db.currentOnly or bar.disableMaxValue then return text end
	return text .. " / " .. number(bar, valueMax)
end

-- The Status Text setting, with the bar's own overrides, in the game's order.
local function displayMode(bar)
	local mode = GetCVar("statusTextDisplay")
	if bar.showNumeric and bar.showPercentage then
		mode = "BOTH"
	elseif bar.showNumeric then
		mode = "NUMERIC"
	elseif bar.showPercentage then
		mode = "PERCENT"
	end
	if bar.disablePercentages and mode == "PERCENT" then mode = "NUMERIC" end
	return mode
end

local function textWanted()
	local db = UnitFrames.db
	return db.shortNumbers or db.currentOnly or db.oneLine
end

-- Runs after the game writes a bar's text, and rewrites only text the game left showing: the
-- Status Text setting and showing on mouseover stay the game's.
function UnitFrames.Rewrite(bar, textString, value, _, valueMax)
	if not textWanted() or not covered(bar) or not textString then return end
	if secret(value) or secret(valueMax) then return end
	if type(value) ~= "number" or type(valueMax) ~= "number" or valueMax <= 0 then return end
	if bar.pauseUpdates or bar.isZero then return end
	local left, right = bar.LeftText, bar.RightText
	local split = left and right and right:IsShown()
	if not split and not textString:IsShown() then return end

	local mode = displayMode(bar)
	if mode == "PERCENT" then return end
	-- The game shows a percent only for mana and health (TextStatusBarMixin, 12.0.0).
	local percent
	if not bar.disablePercentages and (not bar.powerToken or bar.powerToken == "MANA") then
		percent = math.ceil(value / valueMax * 100) .. "%"
	end

	if mode == "BOTH" then
		local db = UnitFrames.db
		if split and not db.oneLine then
			right:SetText(number(bar, value))
			return
		end
		if split then
			left:SetText("")
			left:Hide()
			right:SetText("")
			right:Hide()
		end
		local text = numeric(bar, value, valueMax)
		if percent then
			text = db.oneLine and (text .. " (" .. percent .. ")") or ("(" .. percent .. ") " .. text)
		end
		textString:SetText(text)
		textString:Show()
		return
	end

	local text = numeric(bar, value, valueMax)
	local locked = bar.cvar and GetCVar(bar.cvar) == "1" and bar.textLockable
	if bar.prefix and (bar.alwaysPrefix or not locked) then text = bar.prefix .. " " .. text end
	textString:SetText(text)
end

-- The game copies the text code into each bar, so each bar is hooked on its own, once.
local hookedBars = setmetatable({}, { __mode = "k" })

local function hookBar(bar)
	if type(bar) ~= "table" or hookedBars[bar] or type(bar.UpdateTextStringWithValues) ~= "function" then return end
	hooksecurefunc(bar, "UpdateTextStringWithValues", UnitFrames.Rewrite)
	hookedBars[bar] = true
end

-- Asks the game to write each bar's text again. A bar holding a secret value is skipped: the
-- game's own text code would compare it, and from addon code that fails.
local function refreshText()
	for bar in pairs(hookedBars) do
		if type(bar.UpdateTextString) == "function" then
			local _, valueMax = bar:GetMinMaxValues()
			if not secret(bar:GetValue()) and not secret(valueMax) then bar:UpdateTextString() end
		end
	end
end

------------------------------------------------------------------------------------------------
-- Name size

local sized = setmetatable({}, { __mode = "k" })

-- Only the size changes; the font stays, EverlookFonts' or the game's.
local function sizeName(frame)
	if not UnitFrames.db.resizeNames or not covered(frame) then return end
	local text = frame.name
	if type(text) ~= "table" or type(text.GetFont) ~= "function" then return end
	local path, size, flags = text:GetFont()
	if not path then return end
	sized[text] = true
	if size ~= UnitFrames.db.nameSize then text:SetFont(path, UnitFrames.db.nameSize, flags) end
end

-- Back to the size of the font the name inherits.
local function unsizeNames()
	for text in pairs(sized) do
		local object = text:GetFontObject()
		local size = object and select(2, object:GetFont())
		local path, _, flags = text:GetFont()
		if path and size then text:SetFont(path, size, flags) end
		sized[text] = nil
	end
end

------------------------------------------------------------------------------------------------

-- A frame seen for the first time gets its bars hooked; party frames come from a pool, so new
-- ones turn up as the game updates them.
local hookedFrames = setmetatable({}, { __mode = "k" })

local function adopt(frame)
	if type(frame) ~= "table" or hookedFrames[frame] then return end
	hookedFrames[frame] = true
	local health, mana = bars(frame)
	hookBar(health)
	hookBar(mana)
	-- Target and focus draw their health bar again when the unit's rank changes (elite, rare, minus).
	if type(frame.CheckClassification) == "function" then
		hooksecurefunc(frame, "CheckClassification", function(self) paint(self.healthbar) end)
	end
end

-- A game function this client lacks is left out; EverlookQA reports it.
local function hook(name, fn)
	if type(_G[name]) == "function" then hooksecurefunc(name, fn) end
end

local function hookGame()
	hook("UnitFrame_Update", function(frame)
		adopt(frame)
		sizeName(frame)
	end)
	hook("UnitFrameHealthBar_Update", function(bar)
		hookBar(bar)
		paint(bar)
	end)
	hook("UnitFrameManaBar_Update", hookBar)
	-- Health bars recolor on every change; this is called by name from each bar's handler.
	hook("HealthBar_OnValueChanged", paint)
	hook("UnitFramePortrait_Update", classPortrait)
end

function UnitFrames:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Unit Frames")
	page:Checkbox("classHealth", "Color health by class",
		"Players' health bars take their class color; everyone else's show how they see you: red hostile, yellow neutral, green friendly, gray when tapped.")
	page:Checkbox("classPortraits", "Class icons for player portraits",
		"Players show their class icon in place of their face. This is the game's own portrait setting; turning this off puts it back to the game's default.")
	page:Checkbox("shortNumbers", "Short numbers",
		"Bar text reads 12.3k and 2.3m. Which text shows still follows the game's Status Text setting.")
	page:Checkbox("currentOnly", "Current value only",
		"Bar text shows 12.3k, without the maximum after it.")
	page:Checkbox("oneLine", "Value and percent on one line",
		"With Status Text set to Both, shows 12.3k / 45.6k (27%) in the middle of the bar instead of the percent on the left and the value on the right.")
	page:Checkbox("resizeNames", "Resize unit names",
		"Sets the size of the name on each unit frame to Unit name size.")
	page:Slider("nameSize", "Unit name size",
		"The size of unit frame names, in points. The game's own is 10. Needs Resize unit names.",
		8, 16, 1, function(value) return value .. " pt" end)
end

function UnitFrames:OnEnable()
	hookGame()
	for _, frame in ipairs(frames()) do adopt(frame) end
	self:Apply()
end

-- Draws every frame there is now as the settings say.
function UnitFrames:Apply()
	local list = frames()
	for _, frame in ipairs(list) do
		adopt(frame)
		paint(frame.healthbar)
		sizeName(frame)
	end
	refreshText()
	applyPortraits(false)
end

function UnitFrames:OnSettingChanged(key)
	if key == "classHealth" then
		if self.db.classHealth then
			for _, frame in ipairs(frames()) do paint(frame.healthbar) end
		else
			unpaint()
		end
	elseif key == "classPortraits" then
		applyPortraits(true)
	elseif key == "resizeNames" or key == "nameSize" then
		if self.db.resizeNames then
			for _, frame in ipairs(frames()) do sizeName(frame) end
		else
			unsizeNames()
		end
	else
		refreshText()
	end
end
