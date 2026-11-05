local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookAutoResponses")

Enum = { SummonReason = { Spell = 0, Scenario = 1 } }
C_SummonInfo = { ConfirmSummon = function() t.log("ConfirmSummon") end }
AcceptResurrect = function() t.log("AcceptResurrect") end
StaticPopup_Hide = function(which) t.log("hide " .. which) end
DELETE_ITEM_CONFIRM_STRING = "DELETE"
local deleteOnShow
StaticPopupDialogs = { DELETE_GOOD_ITEM = {} }
hooksecurefunc = function(tbl, method, fn)
	if tbl == StaticPopupDialogs.DELETE_GOOD_ITEM and method == "OnShow" then deleteOnShow = fn end
end

t.load("EverlookAutoResponses")
t.fire("PLAYER_LOGIN")
local R = Everlook:GetAddon("EverlookAutoResponses")
local function fire(...) t.reset() t.fire(...) end

check(R.db.acceptSummons and R.db.acceptResurrections and not R.db.easyDelete,
	"summons and resurrections start on, delete fill-in off")

fire("CONFIRM_SUMMON", Enum.SummonReason.Spell, false)
check(has("ConfirmSummon") and has("hide CONFIRM_SUMMON"), "accepts a summon and closes it")

fire("CONFIRM_SUMMON", Enum.SummonReason.Scenario, false)
check(#t.calls == 0, "leaves a scenario summon")

fire("CONFIRM_SUMMON", Enum.SummonReason.Spell, true)
check(#t.calls == 0, "leaves a starting-area summon")

t.combat = true
fire("CONFIRM_SUMMON", Enum.SummonReason.Spell, false)
check(#t.calls == 0, "leaves a summon in combat")

fire("RESURRECT_REQUEST", "Healer")
check(has("AcceptResurrect") and has("hide RESURRECT") and has("hide RESURRECT_NO_SICKNESS"),
	"accepts a resurrection, even in combat, and closes it")
t.combat = false

local reason = Enum.SummonReason
Enum.SummonReason = nil
fire("CONFIRM_SUMMON", 0, false)
check(#t.calls == 0, "no summon reasons on the client: leaves every summon")
Enum.SummonReason = reason

t.shift = true
fire("CONFIRM_SUMMON", Enum.SummonReason.Spell, false)
t.fire("RESURRECT_REQUEST", "Healer")
check(#t.calls == 0, "Shift skips both")
t.shift = false

R.db.acceptSummons, R.db.acceptResurrections = false, false
fire("CONFIRM_SUMMON", Enum.SummonReason.Spell, false)
t.fire("RESURRECT_REQUEST", "Healer")
check(#t.calls == 0, "off means off")

-- Delete confirmation.
local box = { SetText = function(_, text) t.log("typed " .. text) end }
local dialog = { GetEditBox = function() return box end }
check(deleteOnShow ~= nil, "hooks the good-item delete popup")
fire("ADDON_LOADED", "x")
deleteOnShow(dialog)
check(#t.calls == 0, "leaves the box empty while the option is off")
R.db.easyDelete = true
t.reset()
deleteOnShow(dialog)
check(has("typed DELETE"), "types the confirmation word when on")
t.shift = true
t.reset()
deleteOnShow(dialog)
check(#t.calls == 0, "Shift leaves it empty")
t.shift = false

t.done()
