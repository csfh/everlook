-- Chooses the font of Everlook's five font tokens (Everlook/font_tokens.lua): Heading, Body,
-- Small, Chat and Number, and gives the game's font globals, its font objects and the engine's font
-- paths, the font of the token their role belongs to, each at its own size. That is all it changes:
-- it never walks frames or sets a text's font. Text that follows a font object changes with it; an
-- addon that wants another token, size, outline or shadow for its own text, or for a game text it
-- owns, sets that itself. Waits while you're in combat, and going back to the game's font puts back
-- the fonts it found. The font files and their licences are in assets/ (see assets/fonts.txt).
local defaults = {}
for _, token in ipairs(Everlook.FONT_TOKENS) do defaults[token:lower() .. "Face"] = "game" end
local Fonts = Everlook:NewAddon("EverlookFonts", { label = "Fonts", defaults = defaults })

-- Game functions this addon needs; EverlookQA checks they exist. Fonts that load on demand or may
-- not exist on every client (nameplate fonts, the objective tracker fonts, UNIT_NAME_FONT_ROMAN)
-- are left out: the code checks for them before use.
EverlookQA:Expect("EverlookFonts", {
	"InCombatLockdown",
	"GetLocale",
	"debugprofilestop",
	"STANDARD_TEXT_FONT",
	"DAMAGE_TEXT_FONT",
	"UNIT_NAME_FONT",
	"ChatFontNormal",
	"GameTooltipHeaderText",
	"CHAT_FRAMES",
	"NumberFontNormalSmallGray",
}, {
	"GetFonts",
})

local ASSETS = "Interface\\AddOns\\EverlookFonts\\assets\\"
-- The fonts to choose from, in menu order, for every token. `file` draws Latin; `russian` is the
-- file for a Russian client, false when the font has no Cyrillic. Which font suits chat and names,
-- which carry every alphabet players type, is the player's call. The game's files and their _CYR
-- versions are the roman and russian members in Blizzard_Fonts_Shared (12.0.0).
local FACES = {
	{ id = "expressway", label = "Expressway", file = ASSETS .. "expressway.ttf" },
	{ id = "manrope", label = "Manrope", file = ASSETS .. "manrope.ttf" },
	{ id = "inter", label = "Inter", file = ASSETS .. "inter.ttf" },
	{ id = "robotoCondensed", label = "Roboto Condensed", file = ASSETS .. "roboto_condensed.ttf" },
	{ id = "firaSans", label = "Fira Sans", file = ASSETS .. "fira_sans.ttf" },
	{ id = "barlowSemiCondensed", label = "Barlow Semi Condensed", file = ASSETS .. "barlow_semi_condensed.ttf",
		russian = false },
	{ id = "notoSans", label = "Noto Sans", file = ASSETS .. "noto_sans.ttf" },
	{ id = "sourceSans3", label = "Source Sans 3", file = ASSETS .. "source_sans_3.ttf" },
	{ id = "ptSansNarrow", label = "PT Sans Narrow", file = ASSETS .. "pt_sans_narrow.ttf" },
	{ id = "friz", label = "Friz Quadrata (game)", file = "Fonts\\FRIZQT__.TTF", russian = "Fonts\\FRIZQT___CYR.TTF" },
	{ id = "arialNarrow", label = "Arial Narrow (game)", file = "Fonts\\ARIALN.TTF" },
	{ id = "morpheus", label = "Morpheus (game)", file = "Fonts\\MORPHEUS.TTF", russian = "Fonts\\MORPHEUS_CYR.TTF" },
	{ id = "skurri", label = "Skurri (game)", file = "Fonts\\skurri.ttf", russian = "Fonts\\SKURRI_CYR.TTF" },
}
local GAME_FONT = "The game's font"

-- The file for a choice on this client, or nil for the game's own font. A choice this client
-- can't draw, or one this list no longer has, counts as the game's font.
function Fonts.FaceFile(id)
	for _, face in ipairs(FACES) do
		if face.id == id then
			if GetLocale() == "ruRU" and face.russian ~= nil then return face.russian or nil end
			return face.file
		end
	end
	return nil
end

-- The menu for a dropdown: the game's font, then each font this client can draw.
local function choices()
	local list = { { "game", GAME_FONT } }
	for _, face in ipairs(FACES) do
		if Fonts.FaceFile(face.id) then list[#list + 1] = { face.id, face.label } end
	end
	return list
end

-- Each game font is a family with one member per alphabet, and SetFont replaces only the member
-- for the client's own alphabet. On a Korean or Chinese client that member is one neither font
-- can draw, so those clients keep every font and size.
local UNSUPPORTED_LOCALES = { koKR = true, zhCN = true, zhTW = true }
-- The engine's own font paths, by token: interface text, damage numbers, and the names it draws
-- in the world. NAMEPLATE_FONT names a font object, so it stays.
local GLOBALS = {
	Body = { "STANDARD_TEXT_FONT" },
	Number = { "DAMAGE_TEXT_FONT" },
	Chat = { "UNIT_NAME_FONT", "UNIT_NAME_FONT_ROMAN" },
}

------------------------------------------------------------------------------------------------
-- Which token the game's text belongs to
--
-- The chat token's fonts are named, and so are the health and power bars' text fonts, which are
-- numbers in the game's ordinary font; the rest is sorted by the font's own file and size as the
-- game made it (Blizzard_Fonts_Shared, 12.0.0, 416 fonts): numbers are the fonts named for them
-- and the Arial Narrow ones (timers, counts); headings are titles, headers and anything 16 points
-- or more; small print is 10 points or less; the rest is body text.
local CHAT_FONT_NAMES = {
	ChatFontNormal = true, ChatFontSmall = true, ChatBubbleFont = true,
	SystemFont_NamePlate = true, SystemFont_NamePlate_Outlined = true, SystemFont_NamePlateFixed = true,
	SystemFont_LargeNamePlate = true, SystemFont_LargeNamePlateFixed = true, SystemFont_NamePlateCastBar = true,
}
local NUMBER_FONT_NAMES = { TextStatusBarText = true, TextStatusBarTextLarge = true }
-- Fonts that keep the game's file. Hotkey labels (action buttons, pet battles, the objective
-- tracker's item buttons) use NumberFontNormalSmallGray, and a button with no key bound shows
-- RANGE_INDICATOR ("●", Blizzard_ActionBar/Shared/ActionButton.lua, 12.0.0) in it while out of range,
-- which none of the fonts draw. It's pinned to the game's file even if a font it inherits changes.
-- Action Shortcuts gives the action bar's labels a token of the player's choice.
local GAME_FONT_NAMES = { NumberFontNormalSmallGray = true }
local HEADING_SIZE, SMALL_SIZE = 16, 10

-- The token for a game font or text: `name` is a font object's name (nil for a text of its own),
-- `file` and `size` what the game gave it.
function Fonts.TokenFor(name, file, size)
	if name and CHAT_FONT_NAMES[name] then return "Chat" end
	local upper = type(file) == "string" and file:upper() or ""
	if (name and (NUMBER_FONT_NAMES[name] or name:find("Number") or name:find("CombatText"))) or upper:find("ARIALN", 1, true) then
		return "Number"
	end
	if (name and (name:find("Header") or name:find("Title"))) or (size and size >= HEADING_SIZE) then
		return "Heading"
	end
	if size and size <= SMALL_SIZE then return "Small" end
	return "Body"
end

-- Everlook's own tokens are set by name, never walked.
local function isToken(object)
	if type(object.GetName) ~= "function" then return false end
	local name = object:GetName()
	return type(name) == "string" and name:find("^EverlookFont") ~= nil
end

local originals = setmetatable({}, { __mode = "k" })
-- Each font object's and text's token, worked out the first time it is seen, from what the game
-- gave it. It outlives a restore, as the role doesn't change.
local tokens = setmetatable({}, { __mode = "k" })
local constants = {}
-- A pass walks every font object, so it runs only when something may have changed:
-- another addon loaded, a pass was blocked by combat, or a choice changed.
local stale = true
local passed

local function inCombat()
	return InCombatLockdown()
end

local function unsupported()
	return UNSUPPORTED_LOCALES[GetLocale()] == true
end

-- What a pass gives the game's text: each token's file while a font is chosen for it, nil for the
-- game's own.
local function wanted()
	local db = Fonts.db
	local files = {}
	for _, token in ipairs(Everlook.FONT_TOKENS) do files[token] = Fonts.FaceFile(db[token:lower() .. "Face"]) end
	return { files = files }
end

local function sameFiles(choice, other)
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		if choice.files[token] ~= other.files[token] then return false end
	end
	return true
end

local function same(choice, other)
	return choice ~= nil and sameFiles(choice, other)
end

local function empty(choice)
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		if choice.files[token] then return false end
	end
	return true
end

local function fontObjectOf(object)
	if type(object.GetFontObject) ~= "function" then return nil end
	return object:GetFontObject()
end

-- A font object's token, sorted once by its name and what the game gave it.
local function tokenOf(object)
	if tokens[object] then return tokens[object] end
	local original = originals[object]
	local path, size = object:GetFont()
	if original then path, size = original[1], original[2] end
	local name = type(object.GetName) == "function" and object:GetName() or nil
	tokens[object] = Fonts.TokenFor(name, path, size)
	return tokens[object]
end

-- A font that inherits one of these changes along with it.
local function follows(object, fonts)
	if fonts[object] then return true end
	local parent = fontObjectOf(object)
	return parent ~= nil and fonts[parent] == true
end

-- The record of the font a font inherits, when it shows that font as this addon replaced it, at
-- this pass's size or the one before.
local function replacedParent(object, path, size)
	local parent = fontObjectOf(object)
	local inherited = parent and originals[parent]
	if inherited and path == inherited.font and (size == inherited.lastSize or size == inherited.earlierSize) then
		return inherited
	end
end

-- A font that inherits one this addon already replaced reports the replacement, so what it had
-- before is the font it inherited.
local function originalOf(object, path, size, flags)
	local inherited = replacedParent(object, path, size)
	if inherited then return { inherited[1], inherited[2], flags } end
	return { path, size, flags }
end

-- A font another addon resized since this one set it keeps that size as its own. A font set back to
-- the font it inherits has that font's own again, so the adjustment isn't added twice.
local function rebase(original, object, path, size)
	local inherited = replacedParent(object, path, size)
	if inherited then
		original[1], original[2] = inherited[1], inherited[2]
	else
		original[2] = size
	end
end

-- `font` is the file to give the font, or nil for the one it had before this addon set it.
-- A font this addon hasn't set stays as it is while nothing would change it.
local function replace(object, font)
	if not object or not object.GetFont or not object.SetFont then return end
	if object.IsForbidden and object:IsForbidden() then return end
	local original = originals[object]
	if not original and not font then return end
	local path, size, flags = object:GetFont()
	if not path or not size then return end
	local seenBefore = original ~= nil
	if not original then
		original = originalOf(object, path, size, flags)
		originals[object] = original
	elseif original.lastSize and size ~= original.lastSize then
		rebase(original, object, path, size)
	end
	original.font = font or original[1]
	original.earlierSize = original.lastSize
	original.lastSize = original[2]
	-- A later pass leaves a font it already set where it is.
	if seenBefore and path == original.font and size == original.lastSize then return end
	object:SetFont(original.font, original.lastSize, flags)
end

local function chatFrames()
	local list = {}
	if type(CHAT_FRAMES) ~= "table" then return list end
	for _, name in ipairs(CHAT_FRAMES) do
		local frame = _G[name]
		if type(frame) == "table" and type(frame.GetFont) == "function" and type(frame.SetFont) == "function" then
			list[#list + 1] = frame
		end
	end
	return list
end

-- The file the game gave a font, before this addon set it or the font it inherits.
local function gameFile(object)
	if originals[object] then return originals[object][1] end
	local path, size, flags = object:GetFont()
	return originalOf(object, path, size, flags)[1]
end

local function setGlobals(keys, font)
	for _, key in ipairs(keys) do
		if type(_G[key]) == "string" then
			constants[key] = constants[key] or _G[key]
			_G[key] = font
		end
	end
end

local function restore()
	for object, original in pairs(originals) do
		if not object.IsForbidden or not object:IsForbidden() then
			local path, size, flags = object:GetFont()
			if size and size ~= original.lastSize then rebase(original, object, path, size) end
			object:SetFont(original[1], original[2], flags or original[3])
		end
	end
	for key, path in pairs(constants) do _G[key] = path end
	originals = setmetatable({}, { __mode = "k" })
	constants = {}
end

-- A pass over every font object can take more than a frame's share, the more so without GetFonts.
-- It runs as a task on Everlook.Schedule, a slice per frame within the shared budget, `job` holding
-- where it is.
local job

-- Milliseconds, or nil when the client has no profiling clock (then a pass runs in one go).
local function clock()
	if debugprofilestop then return debugprofilestop() end
end

-- Sets the globals and the font objects, which is quick, and returns the pass.
local function beginPass()
	local choice = wanted()
	-- After a font choice changed, the pass starts from the fonts the game had, so the family
	-- turned off takes back all it set, globals and chat windows too.
	if passed and not sameFiles(passed, choice) then restore() end
	passed = choice
	stale = false
	for token, keys in pairs(GLOBALS) do
		if choice.files[token] then setGlobals(keys, choice.files[token]) end
	end
	-- Tracker text follows shared fonts that its text size option points at other fonts. Chat
	-- lines follow their window's own copy of ChatFontNormal.
	local kept = {}
	if ObjectiveTrackerLineFont then kept[ObjectiveTrackerLineFont] = true end
	if ObjectiveTrackerHeaderFont then kept[ObjectiveTrackerHeaderFont] = true end
	local chatFonts = {}
	for name in pairs(CHAT_FONT_NAMES) do
		if _G[name] then chatFonts[_G[name]] = true end
	end
	-- Chat windows are EverlookChat's (AGENTS.md's ownership table), so their fonts are left be.
	for _, frame in ipairs(chatFrames()) do
		local own = fontObjectOf(frame)
		if own and not chatFonts[own] then kept[own] = true end
	end
	-- The font objects are only listed here; replacing them happens in the slices. GetFonts names
	-- every font object (FontDocumentation.lua, 12.0.0). Without it, every table among the globals is
	-- a candidate, and listing those took up to 20 ms in one frame.
	local candidates = {}
	if GetFonts then
		for _, name in ipairs(GetFonts()) do
			local object = _G[name]
			if object then candidates[#candidates + 1] = object end
		end
	else
		for _, object in pairs(_G) do
			local kind = type(object)
			if kind == "table" or kind == "userdata" then candidates[#candidates + 1] = object end
		end
	end
	return { files = choice.files, kept = kept, candidates = candidates, at = 0 }
end

-- Replaces the font objects among the listed globals until limitMs is up, and says whether any
-- are left.
local function walkFonts(pass, limitMs)
	local began = clock()
	local candidates = pass.candidates
	while pass.at < #candidates do
		pass.at = pass.at + 1
		local object = candidates[pass.at]
		if object.GetObjectType and (not object.IsForbidden or not object:IsForbidden())
			and object:GetObjectType() == "Font" and not follows(object, pass.kept) and not isToken(object) then
			local name = type(object.GetName) == "function" and object:GetName()
			if name and GAME_FONT_NAMES[name] then
				replace(object, gameFile(object))
			else
				replace(object, pass.files[tokenOf(object)])
			end
		end
		-- Reading the clock costs next to nothing; checking after each one keeps a slice in its limit.
		if began and clock() - began >= limitMs then return true end
	end
	pass.candidates = nil
	return false
end

-- One slice of the pass. True while work is left; combat pauses it. A request that came in during
-- the pass starts the next one when this one ends.
local function slice(limitMs)
	if unsupported() or empty(wanted()) then
		job = nil
		return false
	end
	if inCombat() then return true end
	if not job then
		if not stale and same(passed, wanted()) then return false end
		job = beginPass()
	end
	if walkFonts(job, limitMs or 0) then return true end
	job = nil
	return stale or not same(passed, wanted())
end

-- Font objects belong to the game's own frames, so the pass waits out combat.
local fontsTask = Everlook.Schedule.Task("fonts", { step = slice, combat = "pause" })

-- Without a profiling clock the pass can't be sliced, so it runs in one go.
local function runNow()
	local guard = 0
	while slice(1e9) and guard < 1000 and not inCombat() do guard = guard + 1 end
end

local function restoreAll()
	job = nil
	if inCombat() then
		stale = true
		return
	end
	restore()
	stale, passed = true, nil
end

-- Every choice off puts the fonts back at once. A new choice or size, a loaded addon or a blocked
-- pass asks for a pass, and a burst of requests is answered by one pass, a few milliseconds a frame.
function Fonts:Apply()
	-- Everlook's tokens are this addon's own font objects, set at once, in combat too. A client
	-- whose alphabet none of the fonts draw keeps the game's file in them.
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		local key = token:lower()
		local file = not unsupported() and Fonts.FaceFile(self.db[key .. "Face"]) or nil
		Everlook.SetFontToken(token, file)
	end
	if empty(wanted()) then return restoreAll() end
	if unsupported() then return end
	if not stale and same(passed, wanted()) and not job then return end
	stale = stale or not same(passed, wanted())
	if debugprofilestop then fontsTask:Wake() else runNow() end
end

-- What each token is for, on its settings.
local ROLES = {
	Heading = "titles: windows, quests, sections and tooltip headers",
	Body = "most of the interface's text",
	Small = "small print: labels, captions and timers",
	Chat = "the chat input, chat bubbles and nameplates (Chat sets the chat windows' font)",
	Number = "numbers: health and power, damage, cooldowns and counts (Action Shortcuts sets the hotkey labels')",
}

function Fonts:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Interface")
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		local key = token:lower()
		page:Dropdown(key .. "Face", token .. " font",
			"The font for " .. ROLES[token] .. ", in the game's text and in Everlook's. A font file added while the game is running shows only after a full restart.",
			choices)
	end
end

function Fonts:OnEnable()
	-- Another addon's fonts appear as it loads.
	self:RegisterEvent("ADDON_LOADED", function()
		stale = true
		self:Apply()
	end)
	-- Zone changes and instance loading screens add no new fonts, so only login or a reload
	-- walks them again.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
		if not isLogin and not isReload then return end
		stale = true
		self:Apply()
	end)
	-- What combat blocked happens once it ends.
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if stale or job then self:Apply() end
	end)
end

function Fonts:OnSettingChanged()
	self:Apply()
end
