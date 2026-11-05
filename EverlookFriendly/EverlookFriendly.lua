local Friendly = Everlook:NewAddon("EverlookFriendly", {
	label = "Friendly",
	defaults = {
		thankBuffs = true,
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
}, {
	"C_ChatInfo.InChatMessagingLockdown",
	"issecretvalue",
})

local MESSAGE = "Thank you!"
local DELAY = 4
-- One thank-you per player in this long, so a rebuff or a handful of buffs at once is one whisper.
local QUIET = 300

-- A caster the game can't name shares this key: a stranger with no unit token, an NPC or a world buff.
local UNKNOWN = "unknown"

local waiting = {} -- [guid] = name (false for UNKNOWN), while a thank-you waits out its delay
local thanked = {} -- [guid] = GetTime() of the last one

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
local function stranger(aura)
	if not aura or secret(aura.isHelpful) or not aura.isHelpful then return nil end
	local unit = aura.sourceUnit
	if unit == nil then return UNKNOWN, false end
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

function Friendly:UNIT_AURA(_, unit, updateInfo)
	if unit ~= "player" or not self.db.thankBuffs or not updateInfo or not updateInfo.addedAuras then return end
	for _, aura in ipairs(updateInfo.addedAuras) do
		local guid, name = stranger(aura)
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
end

function Friendly:OnEnable()
	self:RegisterEvent("UNIT_AURA")
end
