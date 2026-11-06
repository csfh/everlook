local AutoResponses = Everlook:NewAddon("EverlookAutoResponses", {
	label = "Auto Responses",
	defaults = {
		acceptSummons = true,
		acceptResurrections = true,
		easyDelete = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookAutoResponses", {
	"C_SummonInfo.ConfirmSummon",
	"Enum.SummonReason.Scenario",
	"AcceptResurrect",
	"StaticPopup_Hide",
	"StaticPopupDialogs.DELETE_GOOD_ITEM",
	"DELETE_ITEM_CONFIRM_STRING",
	"hooksecurefunc",
	"InCombatLockdown",
	"IsShiftKeyDown",
})

local RESURRECT_POPUPS = { "RESURRECT", "RESURRECT_NO_SICKNESS", "RESURRECT_NO_TIMER" }

function AutoResponses:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Chat & Social")
	page:Checkbox("acceptSummons", "Accept summons",
		"Accept a summon and close its popup. Starting-area and scenario summons, and summons in combat, are left to you. Hold Shift to skip.")
	page:Checkbox("acceptResurrections", "Accept resurrections",
		"Accept a resurrection another player offers, even in combat. Releasing your spirit stays manual. Hold Shift to skip.")
	page:Checkbox("easyDelete", "Fill in the delete confirmation",
		"Type the confirmation word when you delete a good item. You still click Yes. Hold Shift to skip.")
end

function AutoResponses:OnEnable()
	self:RegisterEvent("CONFIRM_SUMMON")
	self:RegisterEvent("RESURRECT_REQUEST")
	self:HookDelete()
end

-- A summon into a starting area or a scenario changes where you are, so it stays with you.
-- A combat state the client can't report counts as combat.
function AutoResponses:CONFIRM_SUMMON(_, summonType, skipStartingArea)
	if IsShiftKeyDown() or not self.db.acceptSummons then return end
	if skipStartingArea or not (Enum and Enum.SummonReason) or summonType == Enum.SummonReason.Scenario then return end
	if not InCombatLockdown or InCombatLockdown() then return end
	if not (C_SummonInfo and C_SummonInfo.ConfirmSummon) then return end
	C_SummonInfo.ConfirmSummon()
	StaticPopup_Hide("CONFIRM_SUMMON")
end

function AutoResponses:RESURRECT_REQUEST()
	if IsShiftKeyDown() or not self.db.acceptResurrections or not AcceptResurrect then return end
	AcceptResurrect()
	for _, popup in ipairs(RESURRECT_POPUPS) do
		StaticPopup_Hide(popup)
	end
end

-- The delete popup enables Yes once its box holds the confirmation word, so typing it is enough.
function AutoResponses:HookDelete()
	if self.deleteHooked then return end
	if not (hooksecurefunc and StaticPopupDialogs and StaticPopupDialogs.DELETE_GOOD_ITEM) then return end
	hooksecurefunc(StaticPopupDialogs.DELETE_GOOD_ITEM, "OnShow", function(dialog)
		if self.db.easyDelete and not IsShiftKeyDown() and DELETE_ITEM_CONFIRM_STRING then
			dialog:GetEditBox():SetText(DELETE_ITEM_CONFIRM_STRING)
		end
	end)
	self.deleteHooked = true
end
