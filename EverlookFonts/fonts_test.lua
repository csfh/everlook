local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookFonts")

local EXPRESSWAY = "Interface\\AddOns\\EverlookFonts\\assets\\expressway.ttf"
local MANROPE = "Interface\\AddOns\\EverlookFonts\\assets\\manrope.ttf"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local ARIAL = "Fonts\\ARIALN.TTF"

-- Font objects. One with a parent and no font of its own reports its parent's font, as an
-- inheriting font does in the game.
local function font(kind, path, size, parent, name)
	local object = { kind = kind, path = path, size = size, flags = "", parent = parent, sets = 0, name = name }
	function object:GetObjectType() return self.kind end
	function object:GetName() return self.name end
	function object:GetFontObject() return self.parent end
	function object:GetFont()
		if not self.path and self.parent then return self.parent:GetFont() end
		return self.path, self.size, self.flags
	end
	function object:SetFont(path, size, flags)
		self.path, self.size, self.flags = path, size, flags
		self.sets = self.sets + 1
	end
	return object
end

GameFontNormal = font("Font", FRIZ, 12, nil, "GameFontNormal")
-- The fonts Everlook's tokens start from (Everlook/font_tokens.lua).
GameFontNormalLarge = font("Font", FRIZ, 16, nil, "GameFontNormalLarge")
GameFontHighlight = font("Font", FRIZ, 12, nil, "GameFontHighlight")
GameFontHighlightSmall = font("Font", FRIZ, 10, nil, "GameFontHighlightSmall")
NumberFontNormal = font("Font", ARIAL, 14, nil, "NumberFontNormal")
ChatFontNormal = font("Font", ARIAL, 14, nil, "ChatFontNormal")
GameTooltipHeaderText = font("Font", FRIZ, 14, nil, "GameTooltipHeaderText")
ObjectiveTrackerLineFont = font("Font", FRIZ, 12, nil, "ObjectiveTrackerLineFont")

-- Hotkey labels' font, which inherits a number font (GameFontStyles.xml, 12.0.0).
NumberFontNormalSmall = font("Font", ARIAL, 12, nil, "NumberFontNormalSmall")
NumberFontNormalSmallGray = font("Font", nil, nil, NumberFontNormalSmall, "NumberFontNormalSmallGray")
-- Text in the game: it follows its font object, so the tests only read it.
local inherits = font("FontString", nil, nil, GameFontNormal)
local ownFont = font("FontString", FRIZ, 10)
local hotkey = font("FontString", nil, nil, NumberFontNormalSmallGray)

CHAT_FRAMES = { "ChatFrame1" }
-- Each chat window has its own copy of ChatFontNormal, sized by its tab.
ChatFrame1 = font("ChatFrame", ARIAL, 16, font("Font", ARIAL, 16))
STANDARD_TEXT_FONT, DAMAGE_TEXT_FONT, UNIT_NAME_FONT = FRIZ, FRIZ, FRIZ

local locale = "enUS"
GetLocale = function() return locale end

t.load("EverlookFonts")
t.fire("PLAYER_LOGIN")
local F = Everlook:GetAddon("EverlookFonts")

local TOKENS = { "heading", "body", "small", "chat", "number" }
local allGame = true
for _, key in ipairs(TOKENS) do allGame = allGame and F.db[key .. "Face"] == "game" end
check(allGame, "every token starts on the game's font")
local sizeSettings = 0
for variable in pairs(t.settings) do
	if variable:find("^EverlookFonts_") and not variable:find("Face$") then sizeSettings = sizeSettings + 1 end
end
check(sizeSettings == 0, "Fonts chooses fonts only: no size settings")

-- The menus: the game's font first, then every font, for every token: which suits what is the
-- player's call.
local function menu(key)
	local ids = {}
	for _, option in ipairs(t.settings["EverlookFonts_" .. key].options()) do ids[#ids + 1] = option.value end
	return table.concat(ids, " ")
end
local EVERY = "game expressway manrope inter robotoCondensed firaSans barlowSemiCondensed notoSans sourceSans3 ptSansNarrow friz arialNarrow morpheus skurri"
local menus = true
for _, key in ipairs(TOKENS) do menus = menus and menu(key .. "Face") == EVERY end
check(menus, "every token's menu lists every font")
check(F.FaceFile("gone") == nil, "a font that's gone counts as the game's font")

-- The game's interface fonts are every token but Chat; these tests set them together.
local function interface(id)
	for _, key in ipairs({ "heading", "body", "small", "number" }) do t.change("EverlookFonts_" .. key .. "Face", id) end
end

-- A Russian client gets the game's Cyrillic files, and no font without Cyrillic.
locale = "ruRU"
check(F.FaceFile("friz") == "Fonts\\FRIZQT___CYR.TTF" and F.FaceFile("arialNarrow") == ARIAL
	and F.FaceFile("barlowSemiCondensed") == nil, "Russian: Cyrillic files, and Barlow left out")
check(F.FaceFile("ptSansNarrow") == "Interface\\AddOns\\EverlookFonts\\assets\\pt_sans_narrow.ttf",
	"Russian: PT Sans Narrow draws Cyrillic")
check(not menu("bodyFace"):find("barlow"), "Russian: Barlow isn't in the menu")
locale = "enUS"

-- The game's font changes nothing.
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
check(GameFontNormal.sets == 0 and ChatFontNormal.sets == 0 and STANDARD_TEXT_FONT == FRIZ,
	"with the game's font and no size change, nothing changes")

for _, key in ipairs({ "heading", "body", "small", "number" }) do F.db[key .. "Face"] = "expressway" end
F.db.chatFace = "manrope"

-- An unsupported client keeps everything.
locale = "koKR"
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
check(GameFontNormal.path == FRIZ and STANDARD_TEXT_FONT == FRIZ, "a Korean or Chinese client keeps its fonts")
locale = "enUS"

-- Login: one pass, on the scheduler.
t.fire("PLAYER_ENTERING_WORLD", true, false)
t.runSchedule()
check(GameFontNormal.path == EXPRESSWAY and GameFontNormal.size == 12, "interface fonts become Expressway, same size")
check(ChatFontNormal.path == MANROPE, "the chat font becomes Manrope, the Chat token's")
check(GameTooltipHeaderText.path == EXPRESSWAY and GameTooltipHeaderText.size == 14, "tooltip titles take the Heading token's font")
check(STANDARD_TEXT_FONT == EXPRESSWAY and DAMAGE_TEXT_FONT == EXPRESSWAY and UNIT_NAME_FONT == MANROPE,
	"the engine's font globals follow")
check(ChatFrame1.path == ARIAL and ChatFrame1.size == 16 and ChatFrame1.sets == 0,
	"chat windows are left alone: their font is EverlookChat's")
check((inherits:GetFont()) == EXPRESSWAY and inherits.sets == 0, "text on a game font follows it, untouched")
check(ownFont.path == FRIZ and ownFont.sets == 0, "text with a font of its own is never set: no frame walk")
check(ObjectiveTrackerLineFont.sets == 0, "objective tracker fonts are left alone")
check(NumberFontNormalSmall.path == EXPRESSWAY and (hotkey:GetFont()) == ARIAL and hotkey.sets == 0,
	"hotkey labels' font keeps the game's file, which draws the range dot, though the font it inherits changes")

local sets = GameFontNormal.sets
t.fire("PLAYER_ENTERING_WORLD", false, false)
t.runSchedule()
check(GameFontNormal.sets == sets, "a zone change doesn't walk everything again")

-- A new choice waits for combat to end, and no text's size ever changes.
t.combat = true
t.change("EverlookFonts_bodyFace", "inter")
t.runSchedule(5)
check(GameFontNormal.path == EXPRESSWAY, "combat holds back changes")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
t.runSchedule()
check(GameFontNormal.path:find("inter.ttf"), "after combat the new font is set")
check(GameFontNormal.size == 12 and ChatFrame1.size == 16 and select(2, hotkey:GetFont()) == 12,
	"every font keeps its own size; chat windows their tab's")
t.change("EverlookFonts_bodyFace", "expressway")
t.runSchedule()

-- Turning one family off puts that family back.
interface("game")
t.runSchedule()
check(GameFontNormal.path == FRIZ and GameFontNormal.size == 12 and STANDARD_TEXT_FONT == FRIZ,
	"Expressway off: interface fonts go back")
check(ChatFontNormal.path == MANROPE, "Manrope stays on chat")

-- Another font in its place: from the game's fonts, not on top of the last choice.
interface("inter")
t.runSchedule()
check(GameFontNormal.path == "Interface\\AddOns\\EverlookFonts\\assets\\inter.ttf" and STANDARD_TEXT_FONT:find("inter"),
	"choosing Inter sets the game's text in Inter")
interface("game")
t.runSchedule()

-- Everything off puts back exactly what was there.
t.change("EverlookFonts_chatFace", "game")
t.runSchedule()
check(GameFontNormal.path == FRIZ and GameFontNormal.size == 12, "all off: interface font back to its own size")
check(ChatFontNormal.path == ARIAL and ChatFontNormal.size == 14 and ChatFrame1.path == ARIAL and ChatFrame1.size == 16,
	"all off: chat back to its own font")
check(NumberFontNormalSmall.path == ARIAL and (hotkey:GetFont()) == ARIAL and select(2, hotkey:GetFont()) == 12,
	"all off: number fonts back to their own font and size")
check(UNIT_NAME_FONT == FRIZ and DAMAGE_TEXT_FONT == FRIZ, "all off: font globals back")

-- On the shared budget: with many fonts to replace and every clock read "costing" 0.5 ms, a pass
-- takes several frames and never runs at once.
local many = { "GameFontNormal" }
for index = 1, 400 do
	local name = "ManyFont" .. index
	_G[name] = font("Font", FRIZ, 10, nil, name)
	many[#many + 1] = name
end
GetFonts = function() return many end
local last = _G[many[#many]]
t.clockStep = 0.5
interface("expressway")
check(GameFontNormal.path == FRIZ, "a pass is scheduled, not run at once")
Everlook.Schedule.Tick()
check(last.path == FRIZ, "the first frame of work doesn't reach the end of the list")
local spent = t.runSchedule()
check(last.path == EXPRESSWAY and GameFontNormal.path == EXPRESSWAY and spent > 1, "the pass finishes over several frames")

-- Each frame of the pass stops at the budget: when replacing one font takes 0.2 ms, a frame runs
-- past it by one font at most.
t.clockStep = 0.001
for index = 2, #many do
	local object = _G[many[index]]
	local setFont = object.SetFont
	function object:SetFont(...)
		t.ms = t.ms + 0.2
		return setFont(self, ...)
	end
end
interface("game")
t.runSchedule()
interface("expressway")
local ticks = t.runSchedule()
local history = Everlook.Schedule.Snapshot().frames
local worst = 0
for index = math.max(1, #history - ticks + 1), #history do worst = math.max(worst, history[index]) end
check(last.path == EXPRESSWAY and ticks < #history and worst <= Everlook.Schedule.Budget() + 0.25,
	"no frame of the pass runs past the budget (worst " .. worst .. " ms)")
t.clockStep = 0.5
check(Everlook.Schedule.Snapshot().tasks.fonts.state == "idle", "and then the task goes idle")

-- Combat pauses a pass under way.
interface("game")
t.runSchedule()
interface("expressway")
Everlook.Schedule.Tick()
t.combat = true
for _ = 1, 50 do Everlook.Schedule.Tick() end
check(last.path == FRIZ and Everlook.Schedule.Snapshot().tasks.fonts.state == "paused", "combat pauses the pass")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
t.runSchedule()
check(last.path == EXPRESSWAY, "and it carries on after combat")
t.clockStep = 0

-- Without a profiling clock, a pass runs in one go.
local profiler = debugprofilestop
debugprofilestop = nil
interface("game")
interface("expressway")
check(last.path == EXPRESSWAY and GameFontNormal.path == EXPRESSWAY, "without a profiling clock the pass runs at once")
debugprofilestop = profiler
interface("game")
GetFonts = nil
for _, name in ipairs(many) do if name ~= "GameFontNormal" then _G[name] = nil end end

-- The game names its font objects (GetFonts); then only those are replaced, and a Font kept out of
-- the list is left alone.
local unlisted = font("Font", FRIZ, 12)
UnlistedFont = unlisted
GetFonts = function() return { "GameFontNormal", "NoSuchFont" } end
interface("game")
t.runSchedule()
interface("expressway")
t.runSchedule()
check(GameFontNormal.path == EXPRESSWAY and unlisted.path == FRIZ, "with GetFonts, the fonts the game names are replaced")
GetFonts, UnlistedFont = nil, nil

-- Which token the game's fonts belong to: a sample of Blizzard_Fonts_Shared (12.0.0), each with
-- the file and size the game gives it.
local SAMPLE = {
	{ "GameFontNormal", FRIZ, 12, "Body" }, { "GameTooltipText", FRIZ, 12, "Body" }, { "QuestFont", FRIZ, 13, "Body" },
	{ "GameFontNormalSmall", FRIZ, 10, "Small" }, { "GameFontHighlightSmall", FRIZ, 10, "Small" },
	{ "SystemFont_Outline_Small", FRIZ, 10, "Small" },
	{ "GameFontNormalLarge", FRIZ, 16, "Heading" }, { "GameTooltipHeaderText", FRIZ, 14, "Heading" },
	{ "QuestTitleFont", "Fonts\\MORPHEUS.ttf", 18, "Heading" }, { "ZoneTextFont", FRIZ, 32, "Heading" },
	{ "ChatFontNormal", ARIAL, 14, "Chat" }, { "ChatBubbleFont", FRIZ, 13, "Chat" }, { "SystemFont_NamePlate", FRIZ, 9, "Chat" },
	{ "NumberFontNormal", ARIAL, 14, "Number" }, { "NumberFont_Outline_Med", ARIAL, 14, "Number" },
	{ "GameNormalNumberFont", FRIZ, 10, "Number" }, { "TextStatusBarText", FRIZ, 10, "Number" },
	{ "CombatTextFont", FRIZ, 25, "Number" },
}
local wrong = {}
for _, entry in ipairs(SAMPLE) do
	local token = F.TokenFor(entry[1], entry[2], entry[3])
	if token ~= entry[4] then wrong[#wrong + 1] = entry[1] .. " " .. token end
end
check(#wrong == 0, "the game's fonts sort into the five tokens (" .. table.concat(wrong, ", ") .. ")")
check(F.TokenFor(nil, FRIZ, 10) == "Small" and F.TokenFor(nil, FRIZ, 12) == "Body", "a text's own font sorts by its size")

-- Each token's font follows its choice, at the core's fixed size.
t.change("EverlookFonts_bodyFace", "inter")
local path, size = Everlook.Font.Body:GetFont()
check(path:find("inter.ttf") and size == 12, "the Body token takes the chosen font, at its fixed 12 points")
local smallPath = Everlook.Font.Small:GetFont()
check(smallPath == EXPRESSWAY, "each token has its own font")
t.change("EverlookFonts_bodyFace", "game")
path, size = Everlook.Font.Body:GetFont()
check(path == Everlook.FontTokenGameFile("Body") and size == 12, "the game's font: the token's own file, at its size")
locale = "koKR"
t.change("EverlookFonts_bodyFace", "inter")
check(Everlook.Font.Body:GetFont() == Everlook.FontTokenGameFile("Body"), "a Korean or Chinese client keeps the game's file in the tokens")
locale = "enUS"
t.change("EverlookFonts_bodyFace", "expressway")

-- The tokens are never walked: the token decides.
GetFonts = function() return { "GameFontNormal", "EverlookFontHeading" } end
local headingSets = 0
local setHeading = Everlook.Font.Heading.SetFont
function Everlook.Font.Heading:SetFont(...) headingSets = headingSets + 1 return setHeading(self, ...) end
interface("game")
t.runSchedule()
interface("expressway")
headingSets = 0
t.runSchedule()
check(headingSets == 0 and Everlook.Font.Heading:GetFont() == EXPRESSWAY,
	"Everlook's tokens are set by the token alone, never by the pass")
Everlook.Font.Heading.SetFont = setHeading
GetFonts = nil

t.done()
