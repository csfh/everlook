local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookFonts")

local EXPRESSWAY = "Interface\\AddOns\\EverlookFonts\\assets\\expressway.ttf"
local MANROPE = "Interface\\AddOns\\EverlookFonts\\assets\\manrope.ttf"
local FRIZ = "Fonts\\FRIZQT__.TTF"
local ARIAL = "Fonts\\ARIALN.TTF"

-- Font objects and font strings. A string with a parent and no font of its own reports its
-- parent's font, as inherited text does in the game.
local function font(kind, path, size, parent)
	local object = { kind = kind, path = path, size = size, flags = "", parent = parent, sets = 0 }
	function object:GetObjectType() return self.kind end
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

GameFontNormal = font("Font", FRIZ, 12)
ChatFontNormal = font("Font", ARIAL, 14)
GameTooltipHeaderText = font("Font", FRIZ, 14)
ObjectiveTrackerLineFont = font("Font", FRIZ, 12)

local inherits = font("FontString", nil, nil, GameFontNormal)
local ownFont = font("FontString", FRIZ, 10)
local trackerLine = font("FontString", nil, nil, ObjectiveTrackerLineFont)
-- An action button's hotkey label: a binding, or the range dot when no key is bound.
RANGE_INDICATOR = "●"
local hotkey = font("FontString", nil, nil, GameFontNormal)
hotkey.text = RANGE_INDICATOR
function hotkey:GetText() return self.text end
local actionButton = { HotKey = hotkey, UpdateHotkeys = function() end }
ActionBarButtonEventsFrame = {
	ForEachFrame = function(_, fn) fn(actionButton) end,
	RegisterFrame = function() end,
}
local frames = { { regions = { inherits, ownFont, trackerLine, hotkey } } }
for _, frame in ipairs(frames) do
	function frame:GetRegions() return unpack(self.regions) end
end
EnumerateFrames = function(previous)
	if not previous then return frames[1] end
	for index, frame in ipairs(frames) do
		if frame == previous then return frames[index + 1] end
	end
end

CHAT_FRAMES = { "ChatFrame1" }
-- Each chat window has its own copy of ChatFontNormal, sized by its tab.
ChatFrame1 = font("ChatFrame", ARIAL, 16, font("Font", ARIAL, 16))
PlayerName = font("FontString", FRIZ, 10)
STANDARD_TEXT_FONT, DAMAGE_TEXT_FONT, UNIT_NAME_FONT = FRIZ, FRIZ, FRIZ

local locale = "enUS"
GetLocale = function() return locale end
local hooks = {}
hooksecurefunc = function(target, name, fn)
	if type(target) == "string" then target, name, fn = _G, target, name end
	hooks[name] = fn
end
DefaultCompactUnitFrameSetup = function() end
PartyFrame = { InitializePartyMemberFrames = function() end }

t.load("EverlookFonts")
t.fire("PLAYER_LOGIN")
local F = Everlook:GetAddon("EverlookFonts")

check(F.db.interfaceFont and F.db.peopleFont and not F.db.setSizes and F.db.sizeOffset == 0,
	"Expressway and Manrope start on, size change off at +0")
local slider = t.settings.EverlookFonts_sizeOffset.slider
check(slider.min == -4 and slider.max == 8 and slider.step == 1 and slider.format(2) == "+2 pt",
	"size slider runs from -4 to +8 points")

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
check(ChatFontNormal.path == MANROPE and GameTooltipHeaderText.path == MANROPE, "chat and tooltip title fonts become Manrope")
check(STANDARD_TEXT_FONT == EXPRESSWAY and DAMAGE_TEXT_FONT == EXPRESSWAY and UNIT_NAME_FONT == MANROPE,
	"the engine's font globals follow")
check(ChatFrame1.path == MANROPE and ChatFrame1.size == 16, "chat windows get Manrope and keep their tab's size")
check(ownFont.path == EXPRESSWAY and inherits.path == EXPRESSWAY, "text in the interface font changes, own font or inherited")
check(ObjectiveTrackerLineFont.sets == 0 and trackerLine.sets == 0, "objective tracker fonts are left alone")
check(PlayerName.path == MANROPE, "unit frame names get Manrope")
check(hooks.InitializePartyMemberFrames and hooks.DefaultCompactUnitFrameSetup, "party and raid-style frames are hooked")

check(hotkey.path == FRIZ, "a hotkey label showing the range dot keeps the game's font, which draws it")
hotkey.text = "S4"
hooks.UpdateHotkeys(actionButton)
check(hotkey.path == EXPRESSWAY, "a key bound to the button: its label gets Expressway")
hotkey.text = RANGE_INDICATOR
hooks.UpdateHotkeys(actionButton)
check(hotkey.path == FRIZ, "the binding removed: the dot is back in the game's font")
t.combat = true
hotkey.text = "S5"
hooks.UpdateHotkeys(actionButton)
check(hotkey.path == FRIZ, "a key bound in combat: the label waits")
local passSets = GameFontNormal.sets
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
t.runSchedule()
check(hotkey.path == EXPRESSWAY and GameFontNormal.sets == passSets,
	"after combat that label alone gets Expressway, without a whole new pass")
hotkey.text = RANGE_INDICATOR
hooks.UpdateHotkeys(actionButton)

local compactName = font("FontString", FRIZ, 11)
hooks.DefaultCompactUnitFrameSetup({ name = compactName })
check(compactName.path == MANROPE, "a raid-style frame's name gets Manrope as it's set up")

local sets = GameFontNormal.sets
t.fire("PLAYER_ENTERING_WORLD", false, false)
t.runSchedule()
check(GameFontNormal.sets == sets, "a zone change doesn't walk everything again")

-- Sizes wait for combat to end.
t.combat = true
t.change("EverlookFonts_setSizes", true)
t.change("EverlookFonts_sizeOffset", 2)
t.runSchedule(5)
check(GameFontNormal.size == 12, "combat holds back changes")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
t.runSchedule()
check(GameFontNormal.size == 14 and ownFont.size == 12 and ChatFrame1.size == 16,
	"after combat every font grows by the adjustment; chat windows keep their size")

t.change("EverlookFonts_sizeOffset", -8)
t.runSchedule()
check(ownFont.size == 6, "nothing goes below 6 points")
t.change("EverlookFonts_sizeOffset", 2)
t.runSchedule()

-- Turning one family off puts that family back.
t.change("EverlookFonts_interfaceFont", false)
t.runSchedule()
check(GameFontNormal.path == FRIZ and GameFontNormal.size == 14 and STANDARD_TEXT_FONT == FRIZ,
	"Expressway off: interface fonts go back, the size change stays")
check(ChatFontNormal.path == MANROPE and PlayerName.path == MANROPE, "Manrope stays on chat and names")

-- Everything off puts back exactly what was there.
t.change("EverlookFonts_peopleFont", false)
t.change("EverlookFonts_setSizes", false)
t.runSchedule()
check(GameFontNormal.path == FRIZ and GameFontNormal.size == 12, "all off: interface font back to its own size")
check(ChatFontNormal.path == ARIAL and ChatFontNormal.size == 14 and ChatFrame1.path == ARIAL and ChatFrame1.size == 16,
	"all off: chat back to its own font")
check(ownFont.path == FRIZ and ownFont.size == 10 and PlayerName.path == FRIZ and PlayerName.size == 10,
	"all off: text back to its own font and size")
check(UNIT_NAME_FONT == FRIZ and DAMAGE_TEXT_FONT == FRIZ, "all off: font globals back")

-- On the shared budget: with many frames to walk and every clock read "costing" 0.5 ms, a pass
-- takes several frames and never runs at once.
for _ = 1, 400 do
	local frame = { regions = { font("FontString", FRIZ, 10) } }
	function frame:GetRegions() return unpack(self.regions) end
	frames[#frames + 1] = frame
end
local last = frames[#frames].regions[1]
t.clockStep = 0.5
t.change("EverlookFonts_interfaceFont", true)
check(GameFontNormal.path == FRIZ, "a pass is scheduled, not run at once")
Everlook.Schedule.Tick()
check(last.path == FRIZ, "the first frame of work doesn't reach the end of the walk")
local spent = t.runSchedule()
check(last.path == EXPRESSWAY and ownFont.path == EXPRESSWAY and spent > 1, "the pass finishes over several frames")
check(Everlook.Schedule.Snapshot().tasks.fonts.state == "idle", "and then the task goes idle")

-- Combat pauses a pass under way.
t.change("EverlookFonts_interfaceFont", false)
t.runSchedule()
t.change("EverlookFonts_interfaceFont", true)
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
t.change("EverlookFonts_interfaceFont", false)
t.change("EverlookFonts_interfaceFont", true)
check(last.path == EXPRESSWAY and GameFontNormal.path == EXPRESSWAY, "without a profiling clock the pass runs at once")
debugprofilestop = profiler

t.done()
