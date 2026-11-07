local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookExperience")

local W = t.Widget
function W:SetAllPoints(other) self.allPoints = other end
function W:SetFontObject(font) self.font = font end
function W:SetWordWrap(on) self.wrap = on end
function W:SetAlpha(alpha) self.alpha = alpha end
function W:SetColorTexture(r, g, b, a) self.colorTexture = { r, g, b, a } end
function W:SetWidth(width) self.width = width end
function W:GetWidth() return self.width or 0 end
function W:SetPoint(...) self.points = self.points or {} self.points[#self.points + 1] = { ... } end
function W:ClearAllPoints() self.points = {} end

-- The player: level 10, 2,000 of 8,000, 1,000 rested.
local xp, max, level, rested = 2000, 8000, 10, 1000
UnitXP = function() return xp end
UnitXPMax = function() return max end
UnitLevel = function() return level end
GetXPExhaustion = function() return rested end
BreakUpLargeNumbers = nil
AbbreviateNumbers = nil

-- The quest log: a header, a complete quest worth 1,500, one in progress, one whose reward hasn't
-- arrived, and a complete bonus objective.
local quests = {
	{ isHeader = true },
	{ questID = 1, complete = true, xp = 1500 },
	{ questID = 2, complete = false, xp = 900 },
	{ questID = 3, complete = true, xp = 700, noData = true },
	{ questID = 4, complete = true, xp = 300, isTask = true },
}
C_QuestLog = {
	GetNumQuestLogEntries = function() return #quests end,
	GetInfo = function(i) return quests[i] end,
	IsComplete = function(id) for _, q in ipairs(quests) do if q.questID == id then return q.complete end end end,
}
HaveQuestRewardData = function(id) for _, q in ipairs(quests) do if q.questID == id then return not q.noData end end end
GetQuestLogRewardXP = function(id) for _, q in ipairs(quests) do if q.questID == id then return q.xp end end end

local asked = {}
C_TaskQuest = { RequestPreloadRewardData = function(id) asked[id] = true end }

-- The experience bar, as StatusTrackingBarTemplate builds it, with the game's own text.
StatusTrackingBarInfo = { BarsEnum = { Experience = 4 } }
local bar = t.widget()
bar.StatusBar = t.widget()
bar.OverlayFrame = t.widget()
bar.OverlayFrame.Text = t.widget()
bar.OverlayFrame.Text.alpha = 1
MainStatusTrackingBarContainer = { bars = { [4] = bar } }
-- The same bar in the second container, where the game puts it under a watched reputation.
local second = t.widget()
second.StatusBar, second.OverlayFrame = t.widget(), t.widget()
second.OverlayFrame.Text = t.widget()
SecondaryStatusTrackingBarContainer = { bars = { [4] = second } }
-- EverlookTheme's bottom layout, as far as this addon reads it.
local themeRow
local theme = { BottomRow = function() return themeRow end }
function theme:BottomRowChanged() end
Everlook.addons.EverlookTheme = theme

local made = {}
local createFrame = CreateFrame
CreateFrame = function(kind, name, parent)
	local frame = createFrame(kind, name)
	frame.parent = parent
	made[#made + 1] = frame
	return frame
end
hooksecurefunc = function(target, name, fn)
	local original = target[name]
	target[name] = function(...) original(...) fn(...) end
end
Everlook.Font.Small:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
Everlook.Font.Number:SetFont("Fonts\\ARIALN.TTF", 12, "")

t.load("EverlookExperience")
t.fire("PLAYER_LOGIN")
local E = Everlook:GetAddon("EverlookExperience")
local function frame() for _, f in ipairs(made) do if f.parent == bar.OverlayFrame then return f end end end

check(not E.db.numbers and not E.db.ready and not E.db.rate and not E.db.gains, "every stat starts off")
check(frame() == nil and #t.tickers == 0, "and nothing is drawn and no timer runs")

-- Experience and rested.
t.change("EverlookExperience_numbers", true)
local f = frame()
local own = EverlookExperienceFont
check(f and f.allPoints == bar.StatusBar and f.text.font == own and f.text.wrap == false,
	"on: a line of our own on the bar, in a font object of its own")
check(own.path == "Fonts\\FRIZQT__.TTF" and own.size == 10 and own.flags == "",
	"which starts as the Small token: its file at its size, no outline")
check(f.text.text == "2000 / 8000 (25.0%)   rested 12.5%" and f.text:IsShown(), "experience and rested")
rested = nil
t.fire("UPDATE_EXHAUSTION")
check(f.text.text == "2000 / 8000 (25.0%)", "no rested, no rested part")

-- Font, size and outline.
t.change("EverlookExperience_font", "Number")
t.change("EverlookExperience_size", 14)
t.change("EverlookExperience_outline", "thick")
check(own.path == "Fonts\\ARIALN.TTF" and own.size == 14 and own.flags == "THICKOUTLINE",
	"another token's file, at the chosen size, with the chosen outline")
local sets = 0
local setText = f.text.SetText
f.text.SetText = function(self, text) sets = sets + 1 return setText(self, text) end
t.change("EverlookExperience_size", 16)
check(sets >= 2 and f.text.font == own and f.text.text == "2000 / 8000 (25.0%)",
	"each change gives the line its font again and redraws it at once")
f.text.SetText = nil
Everlook.SetFontToken("Number", "Interface\\AddOns\\EverlookFonts\\assets\\manrope.ttf")
check(own.path == "Interface\\AddOns\\EverlookFonts\\assets\\manrope.ttf" and own.size == 16
	and own.flags == "THICKOUTLINE", "the token given another font: the line follows it, keeping its size and outline")
t.change("EverlookExperience_outline", "none")
check(own.flags == "", "no outline")

-- The game's own bar text, which it shows on hover: invisible while a stat is on.
local gameText = bar.OverlayFrame.Text
gameText:Show()
check(gameText.alpha == 0 and f.text:IsShown(), "the game's hover text is invisible and the line stays")
t.change("EverlookExperience_numbers", false)
check(not f:IsShown() and gameText.alpha == 1, "off: the line is gone and the game's text is back")

-- Quests ready to turn in.
f.width = 400
t.change("EverlookExperience_ready", true)
check(f.text.text == "+18.8% ready", "ready: only complete quests with their reward known, no tasks")
local from = f.ready.points[1]
check(f.ready:IsShown() and from[4] == 100 and f.ready.width == 75,
	"a fill from where the experience ends, as wide as the quests' experience")
check(asked[3] and not asked[2], "a complete quest without its reward data has it asked for")
quests[4].noData = false -- quest 3; the header is first
t.fire("QUEST_DATA_LOAD_RESULT", 3, true)
t.runSchedule()
check(f.text.text == "+27.5% ready", "and counts once it arrives")
xp = 7000
t.fire("PLAYER_XP_UPDATE")
check(f.text.text == "+27.5% ready (level up)" and f.ready.width == 50,
	"more than the level needs: says so, and the fill stops at the end of the bar")
f.width = 800
f.scripts.OnSizeChanged(f)
check(f.ready.width == 100, "the fill follows the bar's size")
t.change("EverlookExperience_ready", false)
check(not f.ready:IsShown() and not f:IsShown(), "off: no fill and no line")

-- Gains to level. The login look was the baseline; 2,000 -> 7,000 was one gain of 5,000.
t.change("EverlookExperience_gains", true)
check(f.text.text == "~1 more like the last", "gains: from the size of the last gain")
xp = 7200
t.fire("PLAYER_XP_UPDATE")
check(f.text.text == "~4 more like the last", "a small gain: more of them to level")
-- A level-up: the rest of the old level (800) and 300 into the new one.
xp, max, level = 300, 9000, 11
t.fire("PLAYER_XP_UPDATE")
check(f.text.text == "~8 more like the last", "a gain across a level-up counts both parts")
t.change("EverlookExperience_gains", false)

-- Experience per hour: 6,300 gained since login (5,000, 200 and 1,100).
t.change("EverlookExperience_rate", true)
check(#t.tickers == 1 and f.text.text == "", "rate: nothing before two minutes have passed")
t.now = 3600
t.tickers[1].fn()
check(f.text.text == "6.3k/h, 1h 23m to level", "per hour since login, and the time to level")
t.change("EverlookExperience_rate", false)
check(t.tickers[1].cancelled and not f:IsShown(), "off: the timer stops and the line is gone")

-- EverlookTheme's bottom layout in use: the line is as wide as the theme's track, and the bar in
-- the second container, under a watched reputation, shows nothing.
t.change("EverlookExperience_numbers", true)
local underneath
for _, made_ in ipairs(made) do if made_.parent == second.OverlayFrame then underneath = made_ end end
themeRow = { width = 1150 }
theme:BottomRowChanged()
check(f.width == 1150 and f.points[1][1] == "TOP" and f.points[2][1] == "BOTTOM",
	"with the bottom layout: the line spans the theme's track, centred on the bar")
check(underneath and not underneath:IsShown(), "and the experience bar under a reputation writes nothing over it")
themeRow = nil
theme:BottomRowChanged()
check(f.allPoints == bar.StatusBar and underneath:IsShown(), "without it: back on the bar, both bars written")
t.change("EverlookExperience_numbers", false)

-- At the level cap the game shows no bar, and the line has nothing to say.
t.change("EverlookExperience_numbers", true)
max = 0
t.fire("PLAYER_XP_UPDATE")
check(f.text.text == "" and not f.text:IsShown(), "no experience to gain: no line")

t.done()
