local HideClutter = Everlook:NewAddon("EverlookHideClutter", {
	label = "Hide Clutter",
	defaults = {
		talkingHead = true,
		zoneText = false,
		errorMessages = false,
		raidWarnings = false,
		stanceBar = false,
		gryphons = false,
		actionBarPage = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
-- UpdateEndCaps and UpdateSystemSettingHideBarScrolling are how the bar shows the gryphons and
-- the page switcher again (MainActionBar.lua, EditModeSystemTemplates.lua, forever 1.60.1).
-- Without them, hiding once and showing once is the fallback.
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
	"MainActionBar.EndCaps",
	"MainActionBar.ActionBarPageNumber",
	"hooksecurefunc",
}, {
	"MainActionBar.UpdateEndCaps",
	"MainActionBar.UpdateSystemSettingHideBarScrolling",
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
local gryphonsHidden, pageHidden
local gryphonsHooked, pageHooked

function HideClutter:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Interface")
	page:Checkbox("talkingHead", "Hide the talking head", "Stop the talking-head portrait when an NPC speaks.")
	page:Checkbox("zoneText", "Hide the center-screen zone name", "Stop the large zone name when you change areas.")
	page:Checkbox("errorMessages", "Hide red error messages", "Stop red errors such as \"Out of range\" on screen.")
	page:Checkbox("raidWarnings", "Hide raid warnings", "Stop raid warnings on screen. They still show in chat.")
	page:Checkbox("stanceBar", "Hide the stance bar",
		"Hide the bar for stances, stealth, auras and aspects. Waits until combat ends.")
	page:Checkbox("gryphons", "Hide the gryphons",
		"Hide the gryphons, or the wyverns, at the ends of the main action bar.")
	page:Checkbox("actionBarPage", "Hide the action bar page switcher",
		"Hide the page number and arrows beside the main action bar.")
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

-- The bar shows the gryphons again from UpdateEndCaps whenever it lays its art out. Hiding the
-- parent EndCaps covers both ends; the hook hides them again after that call.
local function hookGryphons(bar)
	if gryphonsHooked or not (hooksecurefunc and bar.UpdateEndCaps) then return end
	hooksecurefunc(bar, "UpdateEndCaps", function(self)
		if HideClutter.db.gryphons and self.EndCaps then self.EndCaps:Hide() end
	end)
	gryphonsHooked = true
end

local function applyGryphons(wanted)
	local bar = MainActionBar
	if not (bar and bar.EndCaps) then return end
	hookGryphons(bar)
	if wanted then
		bar.EndCaps:Hide()
		gryphonsHidden = true
	elseif gryphonsHidden then
		gryphonsHidden = nil
		if bar.UpdateEndCaps then bar:UpdateEndCaps(bar.hideBarArt) else bar.EndCaps:Show() end
	end
end

-- UpdateSystemSettingHideBarScrolling shows the page number unless Edit Mode's own
-- "Hide bar scrolling" is on. The hook hides it again after that call.
local function hookPage(bar)
	if pageHooked or not (hooksecurefunc and bar.UpdateSystemSettingHideBarScrolling) then return end
	hooksecurefunc(bar, "UpdateSystemSettingHideBarScrolling", function(self)
		if HideClutter.db.actionBarPage and self.ActionBarPageNumber then self.ActionBarPageNumber:Hide() end
	end)
	pageHooked = true
end

local function applyPage(wanted)
	local bar = MainActionBar
	local page = bar and bar.ActionBarPageNumber
	if not page then return end
	hookPage(bar)
	if wanted then
		page:Hide()
		pageHidden = true
	elseif pageHidden then
		pageHidden = nil
		if bar.UpdateSystemSettingHideBarScrolling then
			bar:UpdateSystemSettingHideBarScrolling()
		else
			page:Show()
		end
	end
end

function HideClutter:Apply()
	for key, element in pairs(ELEMENTS) do
		applyElement(key, element, self.db[key] == true)
	end
	applyStance(self.db.stanceBar == true)
	applyGryphons(self.db.gryphons == true)
	applyPage(self.db.actionBarPage == true)
end
