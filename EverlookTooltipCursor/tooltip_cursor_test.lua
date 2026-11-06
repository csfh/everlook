local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookTooltipCursor")

local hooks = {}
hooksecurefunc = function(name, fn) hooks[name] = fn end
GameTooltip_SetDefaultAnchor = function() end

local owner
function GameTooltip.SetOwner(_, parent, anchor, x, y) owner = { parent, anchor, x, y } end
local other = t.widget("OtherTooltip")
function other.SetOwner() owner = "other moved" end

-- Strata, and OnShow hooks run after the frame's own script.
function t.Widget:GetFrameStrata() return self.strata or "MEDIUM" end
function t.Widget:SetFrameStrata(strata) self.strata = strata end
function t.Widget:HookScript(name, fn) self.hooks = self.hooks or {} self.hooks[name] = fn end
GameTooltip.strata = "TOOLTIP"

t.load("EverlookTooltipCursor")
t.fire("PLAYER_LOGIN")
local C = Everlook:GetAddon("EverlookTooltipCursor")

check(C.db.followCursor, "following the cursor starts on")
check(hooks.GameTooltip_SetDefaultAnchor ~= nil, "hooks the game's default tooltip placement")

local parent = t.widget("SomeFrame")
hooks.GameTooltip_SetDefaultAnchor(GameTooltip, parent)
check(owner and owner[1] == parent and owner[2] == "ANCHOR_CURSOR" and owner[3] == 16 and owner[4] == 16,
	"the default tooltip is anchored to the cursor, offset off the pointer")

owner = nil
hooks.GameTooltip_SetDefaultAnchor(other, parent)
check(owner == nil, "other tooltips stay where they are")

-- Keeping it above the action bars.
check(C.db.onTop, "keeping the tooltip on top starts on")
GameTooltip.strata = "MEDIUM" -- lowered by something else, as when dragging onto the bars
hooks.GameTooltip_SetDefaultAnchor(GameTooltip, parent)
check(GameTooltip.strata == "TOOLTIP", "placing it puts it back in the top layer")

GameTooltip.strata = "LOW"
GameTooltip.hooks.OnShow(GameTooltip)
check(GameTooltip.strata == "TOOLTIP", "and so does showing it, however it was placed")

other.strata = "LOW"
hooks.GameTooltip_SetDefaultAnchor(other, parent)
check(other.strata == "LOW", "other tooltips' layers are left alone")

t.change("EverlookTooltipCursor_onTop", false)
GameTooltip.strata = "LOW"
GameTooltip.hooks.OnShow(GameTooltip)
hooks.GameTooltip_SetDefaultAnchor(GameTooltip, parent)
check(GameTooltip.strata == "LOW", "turned off, its layer is left as it is")

owner = nil
t.change("EverlookTooltipCursor_followCursor", false)
hooks.GameTooltip_SetDefaultAnchor(GameTooltip, parent)
check(owner == nil, "turned off, the game's placement stays")

t.done()
