local FriendConveniences = Everlook:NewAddon("EverlookFriendConveniences", {
	label = "Friend Conveniences",
	defaults = {
		friends = true,
		guild = true,
		declineOthers = false,
		declineDuels = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookFriendConveniences", {
	"C_FriendList.GetNumFriends",
	"C_FriendList.GetFriendInfoByIndex",
	"GetNormalizedRealmName",
	"IsInGuild",
	"GetNumGuildMembers",
	"GetGuildRosterInfo",
	"AcceptGroup",
	"DeclineGroup",
	"CancelDuel",
	"StaticPopup_Hide",
	"InCombatLockdown",
	"IsShiftKeyDown",
})

function FriendConveniences:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Chat & Social")
	page:Checkbox("friends", "Accept party invites from friends",
		"Accept a party invite from someone on your in-game friend list. Hold Shift to skip.")
	page:Checkbox("guild", "Accept party invites from guildmates",
		"Accept a party invite from someone in your guild. Hold Shift to skip.")
	page:Checkbox("declineOthers", "Decline party invites from everyone else",
		"Decline a party invite that the two options above don't accept. Hold Shift to skip.")
	page:Checkbox("declineDuels", "Decline duels", "Decline every duel request. Hold Shift to skip.")
end

function FriendConveniences:OnEnable()
	self:RegisterEvent("PARTY_INVITE_REQUEST")
	self:RegisterEvent("DUEL_REQUESTED")
end

-- "Name" or "Name-Realm" as "name-realm", or nil for a name the client hides.
local function fullName(name)
	-- A secret name is still a string, and string methods on it error.
	if issecretvalue and issecretvalue(name) then return nil end
	if type(name) ~= "string" then return nil end
	local player, realm = name:match("^([^%-]+)%-(.+)$")
	if not player then
		player, realm = name, GetNormalizedRealmName() or ""
	end
	return player:lower() .. "-" .. realm:gsub("%s", ""):lower()
end

function FriendConveniences:Trusted(name)
	local target = fullName(name)
	if not target then return false end
	if self.db.friends then
		for index = 1, C_FriendList.GetNumFriends() do
			local friend = C_FriendList.GetFriendInfoByIndex(index)
			if friend and fullName(friend.name) == target then return true end
		end
	end
	if self.db.guild and IsInGuild() then
		for index = 1, GetNumGuildMembers() do
			if fullName((GetGuildRosterInfo(index))) == target then return true end
		end
	end
	return false
end

-- Nothing is answered in combat, or when the client can't report combat.
local function paused()
	return IsShiftKeyDown() or not InCombatLockdown or InCombatLockdown()
end

function FriendConveniences:PARTY_INVITE_REQUEST(_, name)
	if paused() then return end
	if fullName(name) == nil then return end
	if self:Trusted(name) then
		AcceptGroup()
		StaticPopup_Hide("PARTY_INVITE")
	elseif self.db.declineOthers then
		DeclineGroup()
		StaticPopup_Hide("PARTY_INVITE")
	end
end

function FriendConveniences:DUEL_REQUESTED()
	if paused() or not self.db.declineDuels then return end
	CancelDuel()
	StaticPopup_Hide("DUEL_REQUESTED")
end
