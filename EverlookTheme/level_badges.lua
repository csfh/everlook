-- Level badges: a small flat badge with the level on unit frames that show none. Forever's player
-- and target frames already have their own (LevelBackgroundCircle), so in practice this is the
-- party members.
local _, ns = ...
local Theme = ns.Theme
local KEY = "levelBadges"

Theme.BADGE_SIZE = 20

local function hasOwnBadge(frame)
	for _, key in ipairs({ "TargetFrameContent", "PlayerFrameContent" }) do
		local content = frame[key]
		local main = content and (content.TargetFrameContentMain or content.PlayerFrameContentMain)
		if main and main.LevelBackgroundCircle then return true end
	end
	return false
end

-- The level as the game writes it: ?? for a unit far above you, nothing while it is secret.
function Theme.LevelText(unit)
	if not unit or not UnitExists(unit) then return nil end
	local level = UnitLevel(unit)
	if Theme.Secret(level) or type(level) ~= "number" then return nil end
	if level <= 0 then return "??" end
	return tostring(level)
end

local function makeBadge(frame)
	-- Its own frame, not at its parent's level: it sits on top of the portrait.
	local badge = CreateFrame("Frame", nil, frame)
	badge:SetSize(Theme.BADGE_SIZE, Theme.BADGE_SIZE)
	badge:SetPoint("CENTER", frame.Portrait or frame, "BOTTOMLEFT", 2, 2)
	badge:SetFrameLevel(frame:GetFrameLevel() + 5)
	local panel = Theme.Panel(badge, true, true)
	panel:SetAllPoints(badge)
	-- The Number token: EverlookFonts sets its font and size.
	local text = badge:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(Everlook.Font.Number)
	text:SetPoint("CENTER", badge, "CENTER", 0, 0)
	badge.text = text
	return badge
end

-- The number on each badge. Only text on this addon's own frames changes, so this runs in combat too.
local function updateLevels()
	if not Theme:IsOn(KEY) then return end
	for frame, badge in Theme.Hosts(KEY) do
		local text = Theme.LevelText(frame.unit)
		badge.text:SetText(text or "")
		badge:SetShown(text ~= nil and frame:IsShown())
	end
end

-- When Fonts changes the Number token, each badge gets its font again and its number set afresh,
-- as a font string doesn't always redraw when its font object changes.
local function refont(token)
	if token ~= "Number" then return end
	for _, badge in Theme.Hosts(KEY) do
		badge.text:SetFontObject(Everlook.Font.Number)
		badge.text:SetText("")
	end
	updateLevels()
end

Theme:Surface({
	key = KEY,
	label = "Level badges on every unit frame",
	help = "Shows the level in a small flat badge on unit frames that have none, such as party members. "
		.. "The player and target frames already have one.",
	needs = { "UnitLevel", "UnitExists" },
	optional = { "PartyFrame.PartyMemberFramePool", "PlayerFrame", "TargetFrame", "FocusFrame" },
	-- Badges are new frames on the game's unit frames, which are secure: made out of combat only.
	combat = true,
	frames = function()
		local list = {}
		for _, frame in ipairs({ PlayerFrame or false, TargetFrame or false, FocusFrame or false }) do
			if Theme.Usable(frame) and not hasOwnBadge(frame) then list[#list + 1] = frame end
		end
		local pool = type(PartyFrame) == "table" and PartyFrame.PartyMemberFramePool
		if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
			for member in pool:EnumerateActive() do list[#list + 1] = member end
		end
		return list
	end,
	style = function(frame) Theme.Draw(KEY, frame, function() return makeBadge(frame) end) end,
	after = updateLevels,
	enable = function()
		local function apply()
			Everlook.Schedule.Defer("EverlookTheme.badges", function() Theme:Apply(KEY) end)
		end
		Theme:On("GROUP_ROSTER_UPDATE", apply)
		Theme:On("PLAYER_ENTERING_WORLD", apply)
		Theme:On("PLAYER_TARGET_CHANGED", updateLevels)
		Theme:On("PLAYER_FOCUS_CHANGED", updateLevels)
		Theme:On("UNIT_LEVEL", updateLevels)
		hooksecurefunc(Everlook, "SetFontToken", refont)
	end,
})
