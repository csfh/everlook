local Friendly = Everlook:NewAddon("EverlookFriendly", {
	label = "Friendly",
	defaults = {
		thankBuffs = true,
		greetCampfire = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookFriendly", {
	"C_ChatInfo.SendChatMessage",
	"C_ChatInfo.PerformEmote",
	"IsInInstance",
	"C_Timer.After",
	"UnitIsPlayer",
	"UnitIsUnit",
	"UnitGUID",
	"UnitName",
	"IsGUIDInGroup",
	"IsShiftKeyDown",
	"GetTime",
	"hooksecurefunc",
	"SitStandOrDescendStart",
	"C_UnitAuras.GetPlayerAuraBySpellID",
	"IsMounted",
	"IsFlying",
	"IsSwimming",
}, {
	"C_ChatInfo.InChatMessagingLockdown",
	"issecretvalue",
})

local MESSAGE = "Thank you!"
local DELAY = 4
-- One thank-you per player in this long, so a rebuff or a handful of buffs at once is one whisper.
local QUIET = 300
-- After a loading screen (login, /reload, a zone change) the game adds back every aura you already
-- have, some with no caster yet; none of them is a buff that just landed. They're ignored this long.
local SETTLE = 5
-- A buff cast just now started at most this many seconds ago.
local FRESH = 1

-- A player the game can't name (no unit token) shares this key.
local UNKNOWN = "unknown"

local waiting = {} -- [guid] = name (false for UNKNOWN), while a thank-you waits out its delay
local thanked = {} -- [guid] = GetTime() of the last one
-- One buff can land as several auras, some naming the caster and some not. An unknown caster's
-- thank-you is dropped when a named player's buff landed this close to it: they were thanked.
local lastNamed -- GetTime() a named stranger's buff last landed

-- Sitting by a campfire: /hello after this long, once every QUIET seconds at most.
local GREET_DELAY = 5
-- The aura a campfire puts on everyone near it.
local COZY_FIRE = 7353
-- The game can't say whether you sit, so this follows /sit, /stand, the sit key and moving.
local sitting = false
local sitCount = 0 -- moves on with every sit and stand, so a timer from an earlier sit does nothing
local greeted -- GetTime() of the last /hello
local settled = 0 -- GetTime() after which auras count again

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

-- "Name" or "Name-Realm" for a whisper, or nil.
local function whisperName(unit)
	local name, realm = UnitName(unit)
	if not name or secret(name) then return nil end
	if realm and realm ~= "" then return name .. "-" .. realm end
	return name
end

-- Who to thank for a buff that just landed on you: guid, name for another player outside your group,
-- UNKNOWN, false when the game has no unit token for the caster, or nil for no one. Group members
-- always have a token, so an unknown caster is never one of them.
-- False for a timed aura that started before just now, one you already had.
local function fresh(aura)
	local duration, expires = aura.duration, aura.expirationTime
	if secret(duration) or secret(expires) or type(duration) ~= "number" or type(expires) ~= "number" then return true end
	if duration <= 0 then return true end
	return expires - duration >= GetTime() - FRESH
end

local function stranger(aura)
	if not aura or secret(aura.isHelpful) or not aura.isHelpful or not fresh(aura) then return nil end
	local unit = aura.sourceUnit
	if unit == nil then
		-- Only a buff a player cast; a campfire, an object or a world buff has no caster to thank.
		local fromPlayer = aura.isFromPlayerOrPlayerPet
		if secret(fromPlayer) or fromPlayer ~= true then return nil end
		return UNKNOWN, false
	end
	if secret(unit) then return nil end
	if UnitIsUnit(unit, "player") or not UnitIsPlayer(unit) then return nil end
	local guid = UnitGUID(unit)
	if not guid or secret(guid) or IsGUIDInGroup(guid) then return nil end
	local name = whisperName(unit)
	if not name then return nil end
	return guid, name
end

local function lockedDown()
	return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

function Friendly:Thank(guid)
	local name = waiting[guid]
	waiting[guid] = nil
	-- Shift pauses it; and they may have joined your group while it waited.
	if name == nil or not self.db.thankBuffs or IsShiftKeyDown() or IsGUIDInGroup(guid) or lockedDown() then return end
	if not name and lastNamed and GetTime() - lastNamed <= DELAY then return end
	thanked[guid] = GetTime()
	if name then
		C_ChatInfo.SendChatMessage(MESSAGE, "WHISPER", nil, name)
	elseif IsInInstance() then
		C_ChatInfo.SendChatMessage(MESSAGE, "SAY")
	else
		-- Outside instances an addon may only /say on a key press, so this uses the /thank emote.
		-- "none" keeps it from thanking whoever you have targeted.
		C_ChatInfo.PerformEmote("THANK", "none")
	end
end

local function byFire()
	local aura = C_UnitAuras.GetPlayerAuraBySpellID(COZY_FIRE)
	return not secret(aura) and aura ~= nil
end

function Friendly:Stand()
	sitting = false
	sitCount = sitCount + 1
end

function Friendly:Sit()
	sitting = true
	sitCount = sitCount + 1
	if not self.db.greetCampfire then return end
	local count = sitCount
	C_Timer.After(GREET_DELAY, function() self:Greet(count) end)
end

function Friendly:Greet(count)
	if count ~= sitCount or not sitting or not self.db.greetCampfire or IsShiftKeyDown() or lockedDown() then return end
	if greeted and GetTime() - greeted < QUIET then return end
	if not byFire() then return end
	greeted = GetTime()
	-- "none" greets everyone around you, not your target.
	C_ChatInfo.PerformEmote("HELLO", "none")
end

function Friendly:UNIT_AURA(_, unit, updateInfo)
	if unit ~= "player" or not self.db.thankBuffs or not updateInfo or secret(updateInfo) then return end
	if GetTime() < settled then return end
	-- The whole list can be secret (in combat, in instances); nothing in it can be read then.
	local added = updateInfo.addedAuras
	if not added or secret(added) then return end
	for _, aura in ipairs(added) do
		local guid, name = stranger(aura)
		if name then lastNamed = GetTime() end
		local last = guid and thanked[guid]
		if guid and waiting[guid] == nil and not (last and GetTime() - last < QUIET) then
			waiting[guid] = name
			C_Timer.After(DELAY, function() self:Thank(guid) end)
		end
	end
end

function Friendly:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Chat & Social")
	page:Checkbox("thankBuffs", "Thank players who buff you",
		"Whisper \"" .. MESSAGE .. "\" to a player outside your group " .. DELAY .. " seconds after they buff you, once every "
			.. QUIET / 60 .. " minutes at most. When the game can't say who it was, /say it in an instance, or /thank"
			.. " everyone around you outside one. Hold Shift to skip.")
	page:Checkbox("greetCampfire", "Greet when you sit by a campfire",
		"Wave /hello to everyone around you " .. GREET_DELAY .. " seconds after you sit down by a campfire, once every "
			.. QUIET / 60 .. " minutes at most. Hold Shift to skip.")
end

function Friendly:PLAYER_ENTERING_WORLD()
	settled = GetTime() + SETTLE
end

function Friendly:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	self:RegisterEvent("UNIT_AURA")
	self:RegisterEvent("PLAYER_STARTED_MOVING", "Stand")
	self:RegisterEvent("PLAYER_REGEN_DISABLED", "Stand")
	-- /sit and /stand typed in chat.
	hooksecurefunc(C_ChatInfo, "PerformEmote", function(emote)
		if secret(emote) then return end
		if emote == "SIT" then self:Sit() elseif emote == "STAND" then self:Stand() end
	end)
	-- The sit key sits or stands you up in turn; mounted, flying or swimming it moves you down instead.
	hooksecurefunc("SitStandOrDescendStart", function()
		if IsMounted() or IsFlying() or IsSwimming() then return end
		if sitting then self:Stand() else self:Sit() end
	end)
end
