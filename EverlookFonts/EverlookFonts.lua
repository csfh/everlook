-- Sets the interface in Expressway, chat and names in Manrope, and adjusts every font's size, each
-- while its own choice is on. Waits while you're in combat, and turning a choice off puts back the
-- fonts it found. The font files and their licences are in assets/ (see assets/fonts.txt).
local Fonts = Everlook:NewAddon("EverlookFonts", {
	label = "Fonts",
	defaults = {
		interfaceFont = true,
		peopleFont = true,
		setSizes = false,
		sizeOffset = 0,
	},
})

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
})

local INTERFACE_FONT = "Interface\\AddOns\\EverlookFonts\\assets\\expressway.ttf"
-- Chat and names carry what players type. Manrope draws Latin, Cyrillic, Greek and Vietnamese,
-- and Expressway has no Greek.
local PEOPLE_FONT = "Interface\\AddOns\\EverlookFonts\\assets\\manrope.ttf"
-- Each game font is a family with one member per alphabet, and SetFont replaces only the member
-- for the client's own alphabet. On a Korean or Chinese client that member is one neither font
-- can draw, so those clients keep every font and size.
local UNSUPPORTED_LOCALES = { koKR = true, zhCN = true, zhTW = true }
local INTERFACE_GLOBALS = { "STANDARD_TEXT_FONT", "DAMAGE_TEXT_FONT" }
-- The engine draws names in the world with these. NAMEPLATE_FONT names a font object, so it stays.
local NAME_GLOBALS = { "UNIT_NAME_FONT", "UNIT_NAME_FONT_ROMAN" }
local PEOPLE_FONT_NAMES = {
	"ChatFontNormal", "ChatFontSmall", "ChatBubbleFont",
	"SystemFont_NamePlate", "SystemFont_NamePlate_Outlined", "SystemFont_NamePlateFixed",
	"SystemFont_LargeNamePlate", "SystemFont_LargeNamePlateFixed", "SystemFont_NamePlateCastBar",
	-- A tooltip's first line is the name of the unit, item or spell it describes.
	"GameTooltipHeaderText",
}

local originals = setmetatable({}, { __mode = "k" })
local constants = {}
local compactNames = setmetatable({}, { __mode = "k" })
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

-- What a pass gives the text: each family's file while its own choice is on, and the size
-- adjustment while Change font sizes is on.
local function wanted()
	local db = Fonts.db
	return {
		interface = db.interfaceFont and INTERFACE_FONT or nil,
		people = db.peopleFont and PEOPLE_FONT or nil,
		offset = db.setSizes and db.sizeOffset or 0,
	}
end

local function same(choice, other)
	return choice ~= nil and choice.interface == other.interface and choice.people == other.people
		and choice.offset == other.offset
end

local function empty(choice)
	return not choice.interface and not choice.people and choice.offset == 0
end

local function fontObjectOf(object)
	if type(object.GetFontObject) ~= "function" then return nil end
	return object:GetFontObject()
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
local function replaceChat(frame)
	if frame.IsForbidden and frame:IsForbidden() then return end
	local path, size, flags = frame:GetFont()
	if not path or not size then return end
	if not originals[frame] then
		local source = ChatFontNormal and originals[ChatFontNormal]
		originals[frame] = { path == PEOPLE_FONT and source and source[1] or path, nil, flags }
	end
	frame:SetFont(PEOPLE_FONT, size, flags)
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
	local function add(text)
		if type(text) == "table" then list[#list + 1] = text end
	end
	add(PlayerName)
	add(PetName)
	for _, key in ipairs({ "TargetFrame", "FocusFrame" }) do
		local frame = _G[key]
		if type(frame) == "table" then
			local content = frame.TargetFrameContent
			local main = type(content) == "table" and content.TargetFrameContentMain
			if type(main) == "table" then add(main.Name) end
			if type(frame.totFrame) == "table" then add(frame.totFrame.Name) end
		end
	end
	local pool = type(PartyFrame) == "table" and PartyFrame.PartyMemberFramePool
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for member in pool:EnumerateActive() do
			add(member.Name)
			if type(member.PetFrame) == "table" then add(member.PetFrame.Name) end
		end
	end
	for text in pairs(compactNames) do add(text) end
	return list
end

local function ready()
	return not inCombat() and not unsupported()
end

-- Names are set in Manrope while it's on, and are interface text otherwise.
local function nameFont(choice)
	return choice.people or choice.interface
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
			and not follows(region, pass.kept) and not follows(region, pass.peopleFonts) then
			replace(region, pass.names[region] and nameFont(pass) or pass.interface, pass.offset)
			pass.names[region] = nil
		end
	end
end

-- Sets the globals and the font objects, which is quick, and returns the pass.
local function beginPass()
	local choice = wanted()
	-- After a font choice changed, the pass starts from the fonts the game had, so the family
	-- turned off takes back all it set, globals and chat windows too.
	if passed and (passed.interface ~= choice.interface or passed.people ~= choice.people) then restore() end
	passed = choice
	stale = false
	hookNameFrames()
	if choice.interface then setGlobals(INTERFACE_GLOBALS, INTERFACE_FONT) end
	if choice.people then setGlobals(NAME_GLOBALS, PEOPLE_FONT) end
	local peopleFonts = {}
	for _, name in ipairs(PEOPLE_FONT_NAMES) do
		local object = _G[name]
		if object then peopleFonts[object] = true end
	end
	-- Tracker text follows shared fonts that its text size option points at other fonts. Chat
	-- lines follow their window's own copy of ChatFontNormal.
	local kept = {}
	if ObjectiveTrackerLineFont then kept[ObjectiveTrackerLineFont] = true end
	if ObjectiveTrackerHeaderFont then kept[ObjectiveTrackerHeaderFont] = true end
	for _, frame in ipairs(chatFrames()) do
		if choice.people then replaceChat(frame) end
		local own = fontObjectOf(frame)
		if own and not peopleFonts[own] then kept[own] = true end
	end
	-- The globals are only listed here. Asking each one what it is takes most of the time, so that
	-- happens in the slices.
	local candidates = {}
	for _, object in pairs(_G) do
		local kind = type(object)
		if kind == "table" or kind == "userdata" then candidates[#candidates + 1] = object end
	end
	local names = {}
	for _, text in ipairs(nameTexts()) do names[text] = true end
	return {
		interface = choice.interface, people = choice.people, offset = choice.offset,
		kept = kept, peopleFonts = peopleFonts, names = names, frame = false, candidates = candidates, at = 0,
	}
end

-- Replaces the font objects among the listed globals until limitMs is up, and says whether any
-- are left.
local function walkFonts(pass, limitMs)
	local began = clock()
	local candidates, count = pass.candidates, 0
	while pass.at < #candidates do
		pass.at = pass.at + 1
		local object = candidates[pass.at]
		if object.GetObjectType and (not object.IsForbidden or not object:IsForbidden())
			and object:GetObjectType() == "Font" and not follows(object, pass.kept) then
			-- Chat and name fonts carry Greek, which Expressway lacks, so they keep their own
			-- file while Manrope is off.
			local file = pass.interface
			if pass.peopleFonts[object] then file = pass.people end
			replace(object, file, pass.offset)
		end
		count = count + 1
		if began and count % 64 == 0 and clock() - began >= limitMs then return true end
	end
	pass.candidates = nil
	return false
end

-- Walks frames until limitMs is up, and says whether any are left.
local function walk(pass, limitMs)
	local began = clock()
	local frame
	if pass.frame == false then frame = EnumerateFrames() else frame = EnumerateFrames(pass.frame) end
	local count = 0
	while frame do
		count = count + 1
		if not frame.IsForbidden or not frame:IsForbidden() then
			restyleRegions(pass, frame:GetRegions())
		end
		pass.frame = frame
		frame = EnumerateFrames(frame)
		if frame and began and count % 32 == 0 and clock() - began >= limitMs then return true end
	end
	pass.frame = nil
	return false
end

local function finish(pass)
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
	if empty(wanted()) then return restoreAll() end
	if unsupported() then return end
	if not stale and same(passed, wanted()) and not job then return end
	stale = stale or not same(passed, wanted())
	if debugprofilestop then fontsTask:Wake() else runNow() end
end

function Fonts:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "World & Camera")
	page:Checkbox("interfaceFont", "Use Expressway for the interface",
		"Sets the interface in Expressway. Chat, chat bubbles, nameplates and tooltip titles keep their own font, as Expressway has no Greek.")
	page:Checkbox("peopleFont", "Use Manrope for chat and names",
		"Sets chat, chat bubbles, nameplates, unit frame names and tooltip titles in Manrope.")
	page:Checkbox("setSizes", "Change font sizes",
		"Adds Font size adjustment to every font. Chat windows keep the size set on their tab.")
	page:Slider("sizeOffset", "Font size adjustment",
		"Points added to each font's own size; nothing goes below 6. Needs Change font sizes.",
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
	-- What combat blocked happens once it ends.
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if stale or job then self:Apply() end
	end)
end

function Fonts:OnSettingChanged()
	self:Apply()
end
