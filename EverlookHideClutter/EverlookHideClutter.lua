local HideClutter = Everlook:NewAddon("EverlookHideClutter", {
	label = "Hide Clutter",
	defaults = {
		talkingHead = true,
		zoneText = false,
		errorMessages = false,
		raidWarnings = false,
		stanceBar = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookHideClutter", {
	"TalkingHeadFrame",
	"ZoneTextFrame",
	"UIErrorsFrame",
	"RaidWarningFrame",
	"StanceBar.Update",
	"RegisterStateDriver",
	"UnregisterStateDriver",
	"securecallfunction",
	"InCombatLockdown",
})

-- Each element is shown by its own Blizzard frame, in answer to events that frame registers.
-- Unregistering them hides it and registering them again brings it back, as the default UI's
-- own /uierrorsoff does for errors.
local ELEMENTS = {
	talkingHead = { frame = "TalkingHeadFrame", events = { "TALKINGHEAD_REQUESTED" } },
	zoneText = { frame = "ZoneTextFrame", events = { "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" } },
	errorMessages = { frame = "UIErrorsFrame", events = { "UI_ERROR_MESSAGE" } },
	raidWarnings = { frame = "RaidWarningFrame", events = { "CHAT_MSG_RAID_WARNING" } },
}

local stopped = {} -- [key] = the events we unregistered, to register again
local stanceHidden

function HideClutter:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "World & Camera")
	page:Checkbox("talkingHead", "Hide the talking head", "Stop the talking-head portrait when an NPC speaks.")
	page:Checkbox("zoneText", "Hide the center-screen zone name", "Stop the large zone name when you change areas.")
	page:Checkbox("errorMessages", "Hide red error messages", "Stop red errors such as \"Out of range\" on screen.")
	page:Checkbox("raidWarnings", "Hide raid warnings", "Stop raid warnings on screen. They still show in chat.")
	page:Checkbox("stanceBar", "Hide the stance bar",
		"Hide the bar for stances, stealth, auras and aspects. Waits until combat ends.")
end

function HideClutter:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Apply")
	self:RegisterEvent("PLAYER_REGEN_ENABLED", "Apply")
	self:Apply()
end

function HideClutter:OnSettingChanged()
	self:Apply()
end

-- Only events the frame was listening to are stopped, so turning it back on never starts one
-- that something else had stopped.
local function applyElement(key, element, wanted)
	local frame = _G[element.frame]
	if not frame or wanted == (stopped[key] ~= nil) then return end
	if wanted then
		local events = {}
		for _, event in ipairs(element.events) do
			if frame:IsEventRegistered(event) then
				frame:UnregisterEvent(event)
				events[#events + 1] = event
			end
		end
		stopped[key] = events
	else
		for _, event in ipairs(stopped[key]) do
			frame:RegisterEvent(event)
		end
		stopped[key] = nil
	end
end

-- StanceBar is protected: a secure state driver owns its visibility, and it only changes out of
-- combat. PLAYER_REGEN_ENABLED applies a change that combat held back.
local function applyStance(wanted)
	local bar = StanceBar
	if not bar or not InCombatLockdown or InCombatLockdown() then return end
	if not (RegisterStateDriver and UnregisterStateDriver and securecallfunction and bar.Update) then return end
	if wanted and not stanceHidden then
		RegisterStateDriver(bar, "visibility", "hide")
		stanceHidden = true
	elseif not wanted and stanceHidden then
		-- Unregistering alone leaves it hidden; show it securely, then let Blizzard decide.
		RegisterStateDriver(bar, "visibility", "show")
		UnregisterStateDriver(bar, "visibility")
		stanceHidden = nil
		securecallfunction(bar.Update, bar)
	end
end

function HideClutter:Apply()
	for key, element in pairs(ELEMENTS) do
		applyElement(key, element, self.db[key] == true)
	end
	applyStance(self.db.stanceBar == true)
end
