-- Sets Everlook's five font tokens (Everlook/font_tokens.lua): Heading, Body, Small, Chat and
-- Number, each a font and a size. Everlook's own text uses the tokens as they are. The game's own
-- text takes the font of the token its role belongs to and keeps its own size, which one
-- adjustment can change. Waits while you're in combat, and going back to the game's font puts back
-- the fonts it found. The font files and their licences are in assets/ (see assets/fonts.txt).
local defaults = { setSizes = false, sizeOffset = 0 }
for _, token in ipairs(Everlook.FONT_TOKENS) do
	defaults[token:lower() .. "Face"] = "game"
	defaults[token:lower() .. "Size"] = Everlook.FONT_TOKEN_DEFAULTS[token].size
end
local Fonts = Everlook:NewAddon("EverlookFonts", { label = "Fonts", defaults = defaults })

-- Game functions this addon needs; EverlookQA checks they exist. Fonts and frames that load on
-- demand or may not exist on every client (nameplate fonts, the objective tracker fonts, FocusFrame,
-- UNIT_NAME_FONT_ROMAN) are left out: the code checks for them before use.
EverlookQA:Expect("EverlookFonts", {
	"hooksecurefunc",
	"InCombatLockdown",
	"GetLocale",
	"EnumerateFrames",
	"debugprofilestop",
	"STANDARD_TEXT_FONT",
	"DAMAGE_TEXT_FONT",
	"UNIT_NAME_FONT",
	"ChatFontNormal",
	"GameTooltipHeaderText",
	"CHAT_FRAMES",
	"PlayerName",
	"TargetFrame",
	"PartyFrame.InitializePartyMemberFrames",
	"DefaultCompactUnitFrameSetup",
}, {
	"RANGE_INDICATOR",
	"ActionBarButtonEventsFrame.ForEachFrame",
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

-- True for a file this addon sets.
local function ours(path)
	for _, face in ipairs(FACES) do
		if path == face.file or path == face.russian then return true end
	end
	return false
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
local compactNames = setmetatable({}, { __mode = "k" })
-- The unit frame names EverlookUnitFrames sizes (player, target, focus, their targets, party and
-- boss) get the font but not the size adjustment. Pet and raid-style names get both.
local unitNames = setmetatable({}, { __mode = "k" })
local hooked = {}
-- A full pass walks every font and frame, so it runs only when something may have changed:
-- another addon loaded, a pass was blocked by combat, or a choice changed.
local stale = true
local passed

local function inCombat()
	return InCombatLockdown()
end

local function unsupported()
	return UNSUPPORTED_LOCALES[GetLocale()] == true
end

-- What a pass gives the game's text: each token's file while a font is chosen for it (nil for the
-- game's own), and the size adjustment while Change the game's font sizes is on.
local function wanted()
	local db = Fonts.db
	local files = {}
	for _, token in ipairs(Everlook.FONT_TOKENS) do files[token] = Fonts.FaceFile(db[token:lower() .. "Face"]) end
	return { files = files, offset = db.setSizes and db.sizeOffset or 0 }
end

local function sameFiles(choice, other)
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		if choice.files[token] ~= other.files[token] then return false end
	end
	return true
end

local function same(choice, other)
	return choice ~= nil and sameFiles(choice, other) and choice.offset == other.offset
end

local function empty(choice)
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		if choice.files[token] then return false end
	end
	return choice.offset == 0
end

local function fontObjectOf(object)
	if type(object.GetFontObject) ~= "function" then return nil end
	return object:GetFontObject()
end

-- A font object's or text's token. A text that inherits a font object has that font's token, read
-- each time, as the game gives a reused text (a list's rows) another font; a text with a font of
-- its own, or a font object, is sorted once by what the game gave it.
local function tokenOf(object)
	local parent = object:GetObjectType() == "FontString" and fontObjectOf(object)
	if parent then return tokenOf(parent) end
	if tokens[object] then return tokens[object] end
	local token
	do
		local original = originals[object]
		local path, size = object:GetFont()
		if original then path, size = original[1], original[2] end
		local name = object:GetObjectType() == "Font" and type(object.GetName) == "function" and object:GetName() or nil
		token = Fonts.TokenFor(name, path, size)
	end
	tokens[object] = token
	return token
end

-- Text that inherits one of these fonts changes along with it. SetFont on the text itself would
-- pin it at its current font and size.
local function follows(object, fonts)
	if fonts[object] then return true end
	local parent = fontObjectOf(object)
	return parent ~= nil and fonts[parent] == true
end

-- The record of the font a text inherits, when the text shows that font as this addon replaced
-- it, at this pass's size or the one before (a pass reaches fonts before their text).
local function replacedParent(object, path, size)
	local parent = fontObjectOf(object)
	local inherited = parent and originals[parent]
	if inherited and path == inherited.font and (size == inherited.lastSize or size == inherited.earlierSize) then
		return inherited
	end
end

-- Text that inherits a font this addon already replaced reports the replacement, so what it had
-- before is the font it inherited.
local function originalOf(object, path, size, flags)
	local inherited = replacedParent(object, path, size)
	if inherited then return { inherited[1], inherited[2], flags } end
	return { path, size, flags }
end

-- Text another addon resized since this one set it keeps that size as its own. Text set back to
-- the font it inherits has that font's own again, so the adjustment isn't added twice.
local function rebase(original, object, path, size)
	local inherited = replacedParent(object, path, size)
	if inherited then
		original[1], original[2] = inherited[1], inherited[2]
	else
		original[2] = size
	end
end

-- `font` is the file to give the text, or nil for the one it had before this addon set it.
-- Text this addon hasn't set stays as it is while nothing would change it.
local function replace(object, font, offset)
	if not object or not object.GetFont or not object.SetFont then return end
	if object.IsForbidden and object:IsForbidden() then return end
	if unitNames[object] then offset = 0 end
	local original = originals[object]
	if not original and not font and offset == 0 then return end
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
	original.lastSize = math.max(6, original[2] + offset)
	-- A later pass leaves text it already set where it is.
	if seenBefore and path == original.font and size == original.lastSize then return end
	object:SetFont(original.font, original.lastSize, flags)
end

-- A chat window's size belongs to its tab, so it stays. A window opened after ChatFontNormal
-- changed copied this addon's font, and goes back to the font ChatFontNormal had.
local function replaceChat(frame, file)
	if frame.IsForbidden and frame:IsForbidden() then return end
	local path, size, flags = frame:GetFont()
	if not path or not size then return end
	if not originals[frame] then
		local source = ChatFontNormal and originals[ChatFontNormal]
		originals[frame] = { ours(path) and source and source[1] or path, nil, flags }
	end
	frame:SetFont(file, size, flags)
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

-- Unit frame names inherit GameFontNormalSmall, which much other text shares, so each name gets
-- its own font.
local function nameTexts()
	local list = {}
	local function add(text, sized)
		if type(text) ~= "table" then return end
		list[#list + 1] = text
		if sized then unitNames[text] = true end
	end
	add(PlayerName, true)
	add(PetName)
	for _, key in ipairs({ "TargetFrame", "FocusFrame" }) do
		local frame = _G[key]
		if type(frame) == "table" then
			local content = frame.TargetFrameContent
			local main = type(content) == "table" and content.TargetFrameContentMain
			if type(main) == "table" then add(main.Name, true) end
			if type(frame.totFrame) == "table" then add(frame.totFrame.Name, true) end
		end
	end
	local pool = type(PartyFrame) == "table" and PartyFrame.PartyMemberFramePool
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for member in pool:EnumerateActive() do
			add(member.Name, true)
			if type(member.PetFrame) == "table" then add(member.PetFrame.Name) end
		end
	end
	-- Boss names keep the token of their own font, so they aren't in the list, only spared the adjustment.
	for i = 1, MAX_BOSS_FRAMES or 5 do
		local boss = _G["Boss" .. i .. "TargetFrame"]
		if type(boss) == "table" and type(boss.name) == "table" then unitNames[boss.name] = true end
	end
	for text in pairs(compactNames) do add(text) end
	return list
end

local function ready()
	return not inCombat() and not unsupported()
end

-- Player and unit names are the Chat token's.
local function nameFont(choice)
	return choice.files.Chat
end

local function refreshNames()
	if not ready() then
		stale = true
		return
	end
	local choice = wanted()
	for _, text in ipairs(nameTexts()) do replace(text, nameFont(choice), choice.offset) end
end

-- Party members and raid-style frames are made after login, so their names change as each one
-- is set up.
local function hookNameFrames()
	if not hooked.party and type(PartyFrame) == "table" and type(PartyFrame.InitializePartyMemberFrames) == "function" then
		hooksecurefunc(PartyFrame, "InitializePartyMemberFrames", refreshNames)
		hooked.party = true
	end
	if not hooked.compact and type(DefaultCompactUnitFrameSetup) == "function" then
		hooksecurefunc("DefaultCompactUnitFrameSetup", function(frame)
			if type(frame) ~= "table" or type(frame.name) ~= "table" then return end
			compactNames[frame.name] = true
			if not ready() then
				stale = true
				return
			end
			local choice = wanted()
			replace(frame.name, nameFont(choice), choice.offset)
		end)
		hooked.compact = true
	end
end

-- An action button with no key bound shows RANGE_INDICATOR ("●", Blizzard_ActionBar/Shared/
-- ActionButton.lua, 12.0.0) in its hotkey label while out of range. Neither font draws that
-- character, and the game compares the label's text with it, so the label keeps the game's font
-- while it shows the dot instead of the text changing.
local function showsRangeDot(text)
	if type(RANGE_INDICATOR) ~= "string" or type(text.GetText) ~= "function" then return false end
	local value = text:GetText()
	return not (issecretvalue and issecretvalue(value)) and value == RANGE_INDICATOR
end

-- The file the game gave this text, before this addon set it or the font it inherits.
local function gameFile(text)
	if originals[text] then return originals[text][1] end
	local path, size, flags = text:GetFont()
	return originalOf(text, path, size, flags)[1]
end

-- UpdateHotkeys writes the label when bindings change, so the label's font follows its new text.
-- A label changed in combat waits for combat to end, alone, instead of a whole new pass.
local waitingLabels = {}

local function restyleLabel(label)
	if not passed or empty(passed) then return end
	if not ready() then
		waitingLabels[label] = true
		return
	end
	local file = passed.files[tokenOf(label)]
	if showsRangeDot(label) then file = gameFile(label) end
	replace(label, file, passed.offset)
end

local function hotkeyChanged(button)
	if type(button.HotKey) == "table" then restyleLabel(button.HotKey) end
end

local function restyleWaitingLabels()
	local labels = waitingLabels
	waitingLabels = {}
	for label in pairs(labels) do restyleLabel(label) end
end

local function hookButton(button)
	if hooked[button] or type(button) ~= "table" or type(button.UpdateHotkeys) ~= "function" then return end
	hooksecurefunc(button, "UpdateHotkeys", hotkeyChanged)
	hooked[button] = true
end

local function hookActionButtons()
	local manager = ActionBarButtonEventsFrame
	if hooked.actionButtons or type(manager) ~= "table" or type(manager.ForEachFrame) ~= "function"
		or type(manager.RegisterFrame) ~= "function" then return end
	hooksecurefunc(manager, "RegisterFrame", function(_, button) hookButton(button) end)
	manager:ForEachFrame(hookButton)
	hooked.actionButtons = true
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

-- A pass over every frame is about thirteen thousand frames and close to a hundred milliseconds,
-- which would stall one frame. It runs as a task on Everlook.Schedule, a slice per frame within the
-- shared budget, `job` holding where it is.
local job

-- Milliseconds, or nil when the client has no profiling clock (then a pass runs in one go).
local function clock()
	if debugprofilestop then return debugprofilestop() end
end

local function restyleRegions(pass, ...)
	for index = 1, select("#", ...) do
		local region = select(index, ...)
		if region.GetObjectType and region:GetObjectType() == "FontString"
			and not follows(region, pass.kept) and not follows(region, pass.tokens) then
			local file = pass.names[region] and nameFont(pass) or pass.files[tokenOf(region)]
			if showsRangeDot(region) then file = gameFile(region) end
			replace(region, file, pass.offset)
			pass.names[region] = nil
		end
	end
end

-- TEMP: a record of what the font pass does to the unit frames and chat windows, saved in
-- EverlookDB.EverlookFonts.debug so the next reload or logout writes it to disk. Remove once the
-- unit frame font report is settled.
local debugRecord
local function record()
	local db = Fonts.db
	if not db then return nil end
	if not debugRecord then
		debugRecord = { locale = GetLocale(), started = 0, fontsDone = 0, framesDone = 0, finished = 0,
			errors = {}, fonts = {}, snapshots = {} }
		db.debug = debugRecord
	end
	return debugRecord
end

local function isSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

local function describeFont(object)
	if type(object) ~= "table" or type(object.GetFont) ~= "function" then return tostring(object) end
	local path, size, flags = object:GetFont()
	if isSecret(path) or isSecret(size) then return "secret font" end
	local parent = fontObjectOf(object)
	local parentName = parent and parent.GetName and parent:GetName()
	local file = type(path) == "string" and (path:match("[^\\/]+$") or path) or tostring(path)
	local text = ""
	if type(object.GetText) == "function" then
		local value = object:GetText()
		if isSecret(value) then text = " [secret text]" elseif value then text = " \"" .. tostring(value):sub(1, 20) .. "\"" end
	end
	return string.format("%s %s %s <%s>%s", file, tostring(size), tostring(flags), tostring(parentName), text)
end

local function nameOf(object)
	if type(object.GetDebugName) == "function" then return object:GetDebugName() end
	if type(object.GetName) == "function" then return tostring(object:GetName()) end
	return tostring(object)
end

local function snapshot(label)
	local debug = record()
	if not debug or #debug.snapshots >= 6 then return end
	local shot = { label = label, combat = inCombat(), fonts = {}, texts = {}, chat = {} }
	-- Each chat window's font and the font object it follows, to settle whether chat gets the
	-- Chat token's file and keeps it.
	shot.chat.ChatFontNormal = describeFont(ChatFontNormal)
	for _, frame in ipairs(chatFrames()) do shot.chat[nameOf(frame)] = describeFont(frame) end
	for _, name in ipairs({ "GameFontNormalSmall", "GameFontHighlightSmall", "TextStatusBarText",
		"GameNormalNumberFont", "SystemFont_Shadow_Small", "SystemFont_Outline_Small" }) do
		shot.fonts[name] = describeFont(_G[name])
	end
	local count = 0
	local function scan(frame, depth)
		if count >= 240 or depth > 8 or type(frame) ~= "table" or type(frame.GetRegions) ~= "function" then return end
		if frame.IsForbidden and frame:IsForbidden() then return end
		for _, region in ipairs({ frame:GetRegions() }) do
			if count < 240 and region.GetObjectType and region:GetObjectType() == "FontString" then
				count = count + 1
				shot.texts[count] = nameOf(region) .. " = " .. describeFont(region)
			end
		end
		if type(frame.GetChildren) == "function" then
			for _, child in ipairs({ frame:GetChildren() }) do scan(child, depth + 1) end
		end
	end
	for _, name in ipairs({ "PlayerFrame", "PetFrame", "TargetFrame", "FocusFrame", "PartyFrame",
		"CompactPartyFrame", "Boss1TargetFrame" }) do
		local before = count
		scan(_G[name], 0)
		shot.texts[#shot.texts + 1] = "-- " .. name .. ": " .. (count - before) .. " texts"
		count = count + 1
	end
	debug.snapshots[#debug.snapshots + 1] = shot
end

-- Sets the globals and the font objects, which is quick, and returns the pass.
local function beginPass()
	local debug = record() -- TEMP
	if debug then debug.started, debug.combatAtStart = debug.started + 1, inCombat() end
	local choice = wanted()
	-- After a font choice changed, the pass starts from the fonts the game had, so the family
	-- turned off takes back all it set, globals and chat windows too.
	if passed and not sameFiles(passed, choice) then restore() end
	passed = choice
	stale = false
	hookNameFrames()
	hookActionButtons()
	for token, keys in pairs(GLOBALS) do
		if choice.files[token] then setGlobals(keys, choice.files[token]) end
	end
	-- Everlook's own text follows its token, which EverlookFonts sets whole.
	local ownTokens = {}
	for _, token in ipairs(Everlook.FONT_TOKENS) do ownTokens[Everlook.Font[token]] = true end
	-- Tracker text follows shared fonts that its text size option points at other fonts. Chat
	-- lines follow their window's own copy of ChatFontNormal.
	local kept = {}
	if ObjectiveTrackerLineFont then kept[ObjectiveTrackerLineFont] = true end
	if ObjectiveTrackerHeaderFont then kept[ObjectiveTrackerHeaderFont] = true end
	local chatFonts = {}
	for name in pairs(CHAT_FONT_NAMES) do
		if _G[name] then chatFonts[_G[name]] = true end
	end
	for _, frame in ipairs(chatFrames()) do
		if choice.files.Chat then replaceChat(frame, choice.files.Chat) end
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
	local names = {}
	for _, text in ipairs(nameTexts()) do names[text] = true end
	return {
		files = choice.files, offset = choice.offset,
		kept = kept, tokens = ownTokens, names = names, frame = false, candidates = candidates, at = 0,
	}
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
			replace(object, pass.files[tokenOf(object)], pass.offset)
		end
		-- Reading the clock costs next to nothing; checking after each one keeps a slice in its limit.
		if began and clock() - began >= limitMs then return true end
	end
	pass.candidates = nil
	if debugRecord then debugRecord.fontsDone = debugRecord.fontsDone + 1 end -- TEMP
	return false
end

-- Walks frames until limitMs is up, and says whether any are left.
local function walk(pass, limitMs)
	local began = clock()
	local frame
	if pass.frame == false then frame = EnumerateFrames() else frame = EnumerateFrames(pass.frame) end
	while frame do
		if not frame.IsForbidden or not frame:IsForbidden() then
			restyleRegions(pass, frame:GetRegions())
		end
		pass.frame = frame
		frame = EnumerateFrames(frame)
		if frame and began and clock() - began >= limitMs then return true end
	end
	pass.frame = nil
	if debugRecord then debugRecord.framesDone = debugRecord.framesDone + 1 end -- TEMP
	return false
end

local lateShot = false -- TEMP
local function finish(pass)
	if debugRecord then -- TEMP
		debugRecord.finished = debugRecord.finished + 1
		local files = {}
		for _, token in ipairs(Everlook.FONT_TOKENS) do files[#files + 1] = token .. " " .. tostring(pass.files[token]) end
		debugRecord.choice = table.concat(files, " / ") .. " / " .. tostring(pass.offset)
		pcall(snapshot, "pass finished")
		if not lateShot and C_Timer and C_Timer.After then
			lateShot = true
			C_Timer.After(30, function() pcall(snapshot, "30 s after a pass") end)
		end
	end
	-- Party members and raid-style frames hang under frames this walk can miss.
	for text in pairs(pass.names) do replace(text, nameFont(pass), pass.offset) end
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
	local limit = limitMs or 0
	local began = clock()
	if job.candidates and walkFonts(job, limit) then return true end
	if walk(job, began and math.max(0, limit - (clock() - began)) or limit) then return true end
	finish(job)
	job = nil
	return stale or not same(passed, wanted())
end

-- Font objects belong to the game's own frames, so the pass waits out combat.
-- TEMP: the scheduler counts a step's errors without saving them, so the record keeps the first few
-- and where the walk was, then passes the error on.
local function recordedSlice(limitMs)
	local ok, result = pcall(slice, limitMs)
	if ok then return result end
	local debug = record()
	if debug and #debug.errors < 10 then
		local at = job and job.frame and nameOf(job.frame) or "-"
		debug.errors[#debug.errors + 1] = tostring(result) .. " | after frame " .. at
			.. " | fonts left " .. tostring(job and job.candidates and (#job.candidates - job.at) or 0)
	end
	error(result, 0)
end

local fontsTask = Everlook.Schedule.Task("fonts", { step = recordedSlice, combat = "pause" })

-- Without a profiling clock the pass can't be sliced, so it runs in one go.
local function runNow()
	local guard = 0
	while recordedSlice(1e9) and guard < 1000 and not inCombat() do guard = guard + 1 end
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
	-- whose alphabet none of the fonts draw keeps the game's file in them, at the chosen size.
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		local key = token:lower()
		local file = not unsupported() and Fonts.FaceFile(self.db[key .. "Face"]) or nil
		Everlook.SetFontToken(token, file, self.db[key .. "Size"])
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
	Chat = "chat windows, chat bubbles, nameplates and unit frame names",
	Number = "numbers: health and power, damage, cooldowns, counts and key bindings",
}

function Fonts:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Interface")
	for _, token in ipairs(Everlook.FONT_TOKENS) do
		local key = token:lower()
		page:Dropdown(key .. "Face", token .. " font",
			"The font for " .. ROLES[token] .. ", in the game's text and in Everlook's. A font file added while the game is running shows only after a full restart.",
			choices)
		page:Slider(key .. "Size", token .. " size",
			"The size of Everlook's own " .. token:lower() .. " text. The game's text keeps its own sizes; Change the game's font sizes adjusts those.",
			6, 32, 1, function(value) return value .. " pt" end)
	end
	page:Checkbox("setSizes", "Change the game's font sizes",
		"Adds Font size adjustment to every font in the game's text. Chat windows keep the size set on their tab, and unit frame names take theirs from Unit Frames.")
	page:Slider("sizeOffset", "Font size adjustment",
		"Points added to each of the game's fonts' own size; nothing goes below 6. Needs Change the game's font sizes.",
		-4, 8, 1, function(value) return (value > 0 and "+" or "") .. value .. " pt" end)
end

function Fonts:OnEnable()
	-- Another addon's text appears as it loads.
	self:RegisterEvent("ADDON_LOADED", function()
		stale = true
		self:Apply()
	end)
	-- Zone changes and instance loading screens add no new text, so only login or a reload
	-- walks everything again.
	self:RegisterEvent("PLAYER_ENTERING_WORLD", function(_, isLogin, isReload)
		if not isLogin and not isReload then return end
		stale = true
		self:Apply()
	end)
	-- TEMP: the unit frames once a target is chosen.
	self:RegisterEvent("PLAYER_TARGET_CHANGED", function()
		if debugRecord and not debugRecord.targetShot then
			debugRecord.targetShot = true
			pcall(snapshot, "first target")
		end
	end)
	-- What combat blocked happens once it ends.
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		restyleWaitingLabels()
		if stale or job then self:Apply() end
	end)
end

function Fonts:OnSettingChanged()
	self:Apply()
end
