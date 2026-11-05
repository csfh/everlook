local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has, printed = t.check, t.has, t.printed

t.out("EverlookAutoRepair")

local cost, money, canRepair = 500, 1000, true
local allowance, guildMoney = 600, 10000
CanMerchantRepair = function() return canRepair end
GetRepairAllCost = function() return cost, cost > 0 end
RepairAllItems = function(guild) t.log("repair " .. tostring(guild)) end
GetMoney = function() return money end
CanGuildBankRepair = function() return true end
GetGuildBankWithdrawMoney = function() return allowance end
GetGuildBankMoney = function() return guildMoney end

t.load("EverlookAutoRepair")
t.fire("PLAYER_LOGIN")
local R = Everlook:GetAddon("EverlookAutoRepair")
local function visit() t.reset() t.fire("MERCHANT_SHOW") end

check(R.db.repair and not R.db.guildFunds, "repair starts on, guild funds off")

visit()
check(has("repair false") and printed("Repaired for 5s."), "repairs from your own gold")

R.db.guildFunds = true
visit()
check(has("repair true") and printed("from guild funds"), "uses guild funds when allowed")

allowance = 100
visit()
check(has("repair false"), "falls back to your gold when the allowance is short")

allowance = -1
visit()
check(has("repair true"), "an unlimited allowance pays")
R.db.guildFunds = false

cost = 5000
visit()
check(not t.printed("repair ") and printed("Not enough gold to repair."), "says so when you can't afford it")

cost = 0
visit()
check(#t.calls == 0, "nothing to repair, nothing happens")

cost, canRepair = 500, false
visit()
check(#t.calls == 0, "a vendor who can't repair is left alone")
canRepair = true

t.shift = true
visit()
check(#t.calls == 0, "Shift skips")
t.shift = false

R.db.repair = false
visit()
check(#t.calls == 0, "off means off")

t.done()
