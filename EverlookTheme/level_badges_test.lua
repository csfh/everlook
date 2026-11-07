local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local f = dofile(dir .. "/test_setup.lua")(dir, "EverlookTheme level badges")
local t, check, Theme = f.t, f.check, f.Theme
local created = f.created
local member = f.member
local levels = f.levels
local panelOn = f.panelOn

-- Level badges ----------------------------------------------------------------------------------
local function badgeOn(frame)
	for _, made in ipairs(created) do
		if made.parent == frame and made.text then return made end
	end
end
t.combat = true
t.change("EverlookTheme_levelBadges", true)
check(badgeOn(member) == nil, "in combat no badge is made on the game's unit frames")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
local badge = badgeOn(member)
check(badge and badge.text.text == "17" and badge.shown, "after combat a party member gets a badge with its level")
check(badge.atlas == nil and panelOn(badge) and panelOn(badge).fill, "a flat one: a panel, no artwork")
check(badge.text.fontObject == Everlook.Font.Number, "its number is in Everlook's Number token")
local sets = 0
local setText = badge.text.SetText
badge.text.SetText = function(self, text) sets = sets + 1 return setText(self, text) end
badge.text.fontObject = nil
Everlook.SetFontToken("Number", "Interface\\AddOns\\EverlookFonts\\assets\\manrope.ttf")
check(badge.text.fontObject == Everlook.Font.Number and sets >= 2 and badge.text.text == "17",
	"the Number token given another font: the badge gets its font again and redraws its number")
badge.text.SetText = nil
check(badgeOn(PlayerFrame) == nil, "the player frame keeps the badge it already has")
levels.party1 = -1
t.fire("UNIT_LEVEL", "party1")
check(badge.text.text == "??", "a level far above yours reads ??")
local secretLevel = newproxy()
levels.party1 = secretLevel
issecretvalue = function(value) return value == secretLevel end
t.fire("UNIT_LEVEL", "party1")
check(not badge.shown, "a secret level hides the badge")
issecretvalue = nil
levels.party1 = 17
t.change("EverlookTheme_levelBadges", false)
check(not badge.shown, "off: the badges are hidden")

t.done()
