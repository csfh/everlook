-- A line of stats on the experience bar, and a lighter fill for the experience in quests ready to
-- turn in. Each stat is its own switch, off by default. Everything here is this addon's own frames,
-- drawn on the game's bar (StatusTrackingBarTemplate.xml, 12.0.0): one per experience bar, on its
-- OverlayFrame, which sits above the bar and above Theme's flat panel. While a stat is on, the
-- game's own bar text (shown on hover, or always with its "xpBarText" option) is made invisible,
-- so the line stays as it is; the game keeps showing and hiding that text itself, so it is hidden
-- by alpha, and turning every stat off gives it back.
local Experience = Everlook:NewAddon("EverlookExperience", {
	label = "Experience Bar",
	defaults = {
		numbers = false,
		ready = false,
		rate = false,
		gains = false,
		font = "Small",
		size = Everlook.FONT_TOKEN_DEFAULTS.Small.size,
		outline = "none",
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookExperience", {
	"UnitXP",
	"UnitXPMax",
	"UnitLevel",
	"GetXPExhaustion",
	"GetQuestLogRewardXP",
	"HaveQuestRewardData",
	"C_QuestLog.GetNumQuestLogEntries",
	"C_QuestLog.GetInfo",
	"C_QuestLog.IsComplete",
	"hooksecurefunc",
	"C_Timer.NewTicker",
	"GetTime",
}, {
	"MainStatusTrackingBarContainer",
	"SecondaryStatusTrackingBarContainer",
	"StatusTrackingBarInfo.BarsEnum.Experience",
	"BreakUpLargeNumbers",
	"AbbreviateNumbers",
	"C_TaskQuest.RequestPreloadRewardData",
})

local SWITCHES = { "numbers", "ready", "rate", "gains" }
local EXPERIENCE = 4 -- StatusTrackingBarInfo.BarsEnum.Experience (StatusTrackingManager.lua, 12.0.0)
local SETTLE = 120 -- seconds of play before the rate is shown
local TICK = 20 -- seconds between rate updates
-- Quests ready to turn in: the game's quest-complete gold, light enough to read as "not yet".
local READY_COLOR = { 1, 0.82, 0, 0.35 }

local function readable(value)
	return value ~= nil and not (issecretvalue and issecretvalue(value))
end

local function number(value)
	return type(value) == "number" and readable(value) and value or nil
end

------------------------------------------------------------------------------------------------
-- What the stats are made of

-- Experience now: current, needed for the level, level. Nil when the game can't say, or at the
-- level cap, where the game shows no experience bar.
local function current()
	local xp, max, level = number(UnitXP("player")), number(UnitXPMax("player")), number(UnitLevel("player"))
	if not xp or not max or not level or max <= 0 then return end
	return xp, max, level
end

-- Gains this session: the baseline is the first look after login; a level-up between two looks
-- counts the rest of the old level and the start of the new one.
local session = { started = nil, gained = 0, last = nil, xp = nil, max = nil, level = nil }

function Experience.NoteGain()
	local xp, max, level = current()
	if not xp then return end
	if session.xp then
		local gain
		if level > session.level then
			gain = (session.max - session.xp) + xp
		else
			gain = xp - session.xp
		end
		if gain > 0 then
			session.gained = session.gained + gain
			session.last = gain
		end
	else
		session.started = GetTime()
	end
	session.xp, session.max, session.level = xp, max, level
end

-- Experience per hour this session, once it has run long enough to mean something.
function Experience.Rate()
	if not session.started or session.gained <= 0 then return end
	local elapsed = GetTime() - session.started
	if elapsed < SETTLE then return end
	return session.gained / elapsed * 3600
end

-- The experience in quests in the log that are ready to turn in. A quest whose reward the game
-- hasn't sent yet is asked for, as the world map does (WorldMapFrame.lua, 12.0.0), and counts once
-- it arrives.
function Experience.ReadyXP()
	local total = 0
	local count = number(C_QuestLog.GetNumQuestLogEntries()) or 0
	for i = 1, count do
		local info = C_QuestLog.GetInfo(i)
		local id = info and info.questID
		if id and readable(id) and not info.isHeader and not info.isHidden and not info.isTask
			and C_QuestLog.IsComplete(id) == true then
			if HaveQuestRewardData(id) then
				total = total + (number(GetQuestLogRewardXP(id)) or 0)
			elseif C_TaskQuest and C_TaskQuest.RequestPreloadRewardData then
				C_TaskQuest.RequestPreloadRewardData(id)
			end
		end
	end
	return total
end

local readyXP = 0

------------------------------------------------------------------------------------------------
-- Words

local function full(value)
	if BreakUpLargeNumbers then return BreakUpLargeNumbers(math.floor(value + 0.5)) end
	return tostring(math.floor(value + 0.5))
end

local function short(value)
	if AbbreviateNumbers then return AbbreviateNumbers(math.floor(value + 0.5)) end
	if value >= 1e6 then return string.format("%.1fM", value / 1e6) end
	if value >= 1e3 then return string.format("%.1fk", value / 1e3) end
	return tostring(math.floor(value + 0.5))
end

local function percent(part, whole)
	return string.format("%.1f%%", part / whole * 100)
end

local function duration(seconds)
	local minutes = math.ceil(seconds / 60)
	if minutes < 60 then return minutes .. "m" end
	return math.floor(minutes / 60) .. "h " .. (minutes % 60) .. "m"
end

-- The line, from the switches that are on, in a fixed order.
function Experience.Line()
	local xp, max = current()
	if not xp then return "" end
	local db, parts = Experience.db, {}
	if db.numbers then
		parts[#parts + 1] = full(xp) .. " / " .. full(max) .. " (" .. percent(xp, max) .. ")"
		local rested = number(GetXPExhaustion())
		if rested and rested > 0 then parts[#parts + 1] = "rested " .. percent(rested, max) end
	end
	if db.ready and readyXP > 0 then
		local note = "+" .. percent(readyXP, max) .. " ready"
		if readyXP >= max - xp then note = note .. " (level up)" end
		parts[#parts + 1] = note
	end
	if db.rate then
		local rate = Experience.Rate()
		if rate then
			parts[#parts + 1] = short(rate) .. "/h, " .. duration((max - xp) / rate * 3600) .. " to level"
		end
	end
	if db.gains and session.last then
		parts[#parts + 1] = "~" .. math.ceil((max - xp) / session.last) .. " more like the last"
	end
	return table.concat(parts, "   ")
end

------------------------------------------------------------------------------------------------
-- The line's font: one of Everlook's tokens, at a size and outline of its own. The line's own
-- font object takes the token's file, so it follows the token when EverlookFonts changes it.

local OUTLINES = { none = "", outline = "OUTLINE", thick = "THICKOUTLINE" }
local lineFont = CreateFont("EverlookExperienceFont")

local drawn = setmetatable({}, { __mode = "k" }) -- [experience bar] = our frame on it

-- A font string doesn't always redraw when its font object changes, so each line is given the
-- font again and its text set afresh.
function Experience.ApplyFont()
	local db = Experience.db
	local token = Everlook.Font[db.font] or Everlook.Font.Small
	local file = token:GetFont()
	local size = number(db.size) or Everlook.FONT_TOKEN_DEFAULTS.Small.size
	if not file then return end
	lineFont:SetFont(file, size, OUTLINES[db.outline] or "")
	for _, frame in pairs(drawn) do
		frame.text:SetFontObject(lineFont)
		frame.text:SetText("")
	end
	Experience:Refresh()
end

------------------------------------------------------------------------------------------------
-- Drawing

local function anyOn()
	for _, key in ipairs(SWITCHES) do
		if Experience.db[key] then return true end
	end
	return false
end

local containerOf = setmetatable({}, { __mode = "k" }) -- [bar] = the status bar container holding it

-- EverlookTheme's bottom layout while it's in use (EverlookTheme/bottom_layout.lua): the theme's
-- track then spans the whole row, and the second status bar sits hidden under the first.
local function bottomRow()
	local theme = Everlook:GetAddon("EverlookTheme")
	return theme and theme.BottomRow and theme.BottomRow() or nil
end

local function bars()
	local list = {}
	local index = StatusTrackingBarInfo and StatusTrackingBarInfo.BarsEnum
		and StatusTrackingBarInfo.BarsEnum.Experience or EXPERIENCE
	for _, container in ipairs({ MainStatusTrackingBarContainer, SecondaryStatusTrackingBarContainer }) do
		local bar = type(container) == "table" and type(container.bars) == "table" and container.bars[index]
		if type(bar) == "table" and type(bar.OverlayFrame) == "table" and type(bar.StatusBar) == "table"
			and not (bar.IsForbidden and bar:IsForbidden()) then
			containerOf[bar] = container
			list[#list + 1] = bar
		end
	end
	return list
end

local mutedText = setmetatable({}, { __mode = "k" }) -- [game bar text] = true while we hid it

local function muteGameText(bar, on)
	local text = bar.OverlayFrame.Text
	if type(text) ~= "table" or type(text.SetAlpha) ~= "function" then return end
	if on then
		text:SetAlpha(0)
		mutedText[text] = true
	elseif mutedText[text] then
		text:SetAlpha(1)
		mutedText[text] = nil
	end
end

-- The ready fill starts where the experience ends and reaches no further than the bar.
local function placeReady(frame)
	local xp, max = current()
	local width = number(frame:GetWidth())
	if not (Experience.db.ready and xp and width and readyXP > 0) then
		frame.ready:Hide()
		return
	end
	local from = xp / max
	local share = math.min(readyXP, max - xp) / max
	if share <= 0 then
		frame.ready:Hide()
		return
	end
	frame.ready:ClearAllPoints()
	frame.ready:SetPoint("TOPLEFT", frame, "TOPLEFT", width * from, 0)
	frame.ready:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", width * from, 0)
	frame.ready:SetWidth(width * share)
	frame.ready:Show()
end

-- On the bar, or as wide as the theme's track while the bottom layout is in use, so the ready fill
-- starts where the theme's fill ends.
local function shape(frame, bar, row)
	frame:ClearAllPoints()
	if row then
		frame:SetPoint("TOP", bar.StatusBar, "TOP")
		frame:SetPoint("BOTTOM", bar.StatusBar, "BOTTOM")
		frame:SetWidth(row.width)
	else
		frame:SetAllPoints(bar.StatusBar)
	end
end

local function paint(bar)
	local frame = drawn[bar]
	if not frame then return end
	local row = bottomRow()
	-- Under a watched reputation, which then takes the experience bar's place, the line would be
	-- written over the reputation bar.
	if row and containerOf[bar] == SecondaryStatusTrackingBarContainer then
		frame:Hide()
		return
	end
	shape(frame, bar, row)
	placeReady(frame)
	muteGameText(bar, anyOn())
	if not anyOn() then
		frame:Hide()
		return
	end
	frame:Show()
	local line = Experience.Line()
	frame.text:SetText(line)
	frame.text:SetShown(line ~= "")
end

local function make(bar)
	local frame = CreateFrame("Frame", nil, bar.OverlayFrame)
	frame.ready = frame:CreateTexture(nil, "BACKGROUND")
	frame.ready:SetColorTexture(READY_COLOR[1], READY_COLOR[2], READY_COLOR[3], READY_COLOR[4])
	frame.ready:Hide()
	frame.text = frame:CreateFontString(nil, "OVERLAY")
	frame.text:SetFontObject(lineFont)
	-- Across the bar, so a line too long for a short bar is cut off rather than spilling past it.
	frame.text:SetPoint("LEFT", frame, "LEFT", 4, 0)
	frame.text:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
	frame.text:SetWordWrap(false)
	-- Edit Mode can resize the bar.
	frame:SetScript("OnSizeChanged", function() placeReady(frame) end)
	drawn[bar] = frame
	return frame
end

function Experience:Refresh()
	for _, bar in ipairs(bars()) do
		if not drawn[bar] and anyOn() then make(bar) end
		paint(bar)
	end
end

------------------------------------------------------------------------------------------------
-- Updates

local ticker

local function tickRate(on)
	if on and not ticker then
		ticker = C_Timer.NewTicker(TICK, function() Experience:Refresh() end)
	elseif not on and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function countReady()
	readyXP = Experience.db.ready and Experience.ReadyXP() or 0
	Experience:Refresh()
end

function Experience:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Interface")
	page:Checkbox("numbers", "Experience and rested",
		"Your experience and what the level needs, as numbers and a percentage, and your rested experience, on the experience bar. While any stat is on, the game's own bar text no longer shows on hover.")
	page:Checkbox("ready", "Quests ready to turn in",
		"A light gold fill on the experience bar for the experience in the quests you can turn in now, and how much that is. Says \"level up\" when turning them in would level you.")
	page:Checkbox("rate", "Experience per hour",
		"Experience per hour since you logged in or reloaded, and the time to level at that pace. Shows after two minutes of play.")
	page:Checkbox("gains", "Gains to level",
		"How many more gains the size of your last one would level you: kills, quests or anything else that gave experience.")
	local fonts = {}
	for _, token in ipairs(Everlook.FONT_TOKENS) do fonts[#fonts + 1] = { token, token .. " token" } end
	page:Dropdown("font", "Stats font",
		"The font of the stats line: the font Fonts gives one of Everlook's tokens. Does nothing until a stat above is on.",
		fonts)
	page:Slider("size", "Stats size", "The size of the stats line. Does nothing until a stat above is on.",
		6, 24, 1, function(value) return value .. " pt" end)
	page:Dropdown("outline", "Stats outline", "An outline around the stats line. Does nothing until a stat above is on.",
		{ { "none", "None" }, { "outline", "Outline" }, { "thick", "Thick outline" } })
end

function Experience:OnEnable()
	self.ApplyFont()
	-- A token's font can change after the line's was set.
	hooksecurefunc(Everlook, "SetFontToken", function() self.ApplyFont() end)
	-- The theme's bottom layout coming into or out of use moves the track this line sits on.
	local theme = Everlook:GetAddon("EverlookTheme")
	if theme and theme.BottomRowChanged then
		hooksecurefunc(theme, "BottomRowChanged", function() self:Refresh() end)
	end
	self.NoteGain()
	self:RegisterEvent("PLAYER_XP_UPDATE", function()
		self.NoteGain()
		self:Refresh()
	end)
	self:RegisterEvent("UPDATE_EXHAUSTION", "Refresh")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Refresh")
	local function recount()
		if self.db.ready then Everlook.Schedule.Defer("EverlookExperience", countReady) end
	end
	self:RegisterEvent("QUEST_LOG_UPDATE", recount)
	self:RegisterEvent("QUEST_DATA_LOAD_RESULT", recount)
	tickRate(self.db.rate)
	countReady()
end

function Experience:OnSettingChanged(key, value)
	if key == "font" or key == "size" or key == "outline" then return self.ApplyFont() end
	if key == "rate" then tickRate(value) end
	if key == "ready" then return countReady() end
	self:Refresh()
end
