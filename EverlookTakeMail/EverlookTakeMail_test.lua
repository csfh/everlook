local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookTakeMail")

NUM_BAG_SLOTS = 0
local freeSlots = 5
C_Container = { GetContainerNumFreeSlots = function() return freeSlots end }

local mails, pending
local function fillInbox()
	mails = {
		{ money = 100, cod = 0, items = { 7 } },
		{ money = 0, cod = 50, items = { 8 } }, -- COD
		{ money = 0, cod = 0, items = { 9, 10 } },
	}
	pending = false
end
C_Mail = { IsCommandPending = function() return pending end }
GetInboxNumItems = function() return #mails end
GetInboxHeaderInfo = function(i)
	local mail, count = mails[i], 0
	for _ in pairs(mail.items) do count = count + 1 end
	return nil, nil, nil, nil, mail.money, mail.cod, nil, count > 0 and count or nil
end
HasInboxItem = function(i, slot) return mails[i].items[slot] ~= nil end
GetInboxItem = function(i, slot) return "name", mails[i].items[slot] end
TakeInboxMoney = function(i) t.log("money " .. i) mails[i].money = 0 end
TakeInboxItem = function(i, slot) t.log("item " .. mails[i].items[slot]) mails[i].items[slot] = nil end

t.load("EverlookTakeMail")
t.fire("PLAYER_LOGIN")
local M = Everlook:GetAddon("EverlookTakeMail")

check(M.db.takeMail, "taking mail starts on")

fillInbox(); t.reset()
t.fire("MAIL_SHOW"); t.runTicker()
check(has("money 1") and has("item 7") and has("item 9") and has("item 10"), "takes money and every item")
check(not has("item 8"), "leaves COD mail")
t.fire("MAIL_CLOSED")

fillInbox(); t.reset()
t.fire("MAIL_SHOW")
pending = true
t.tickers[#t.tickers].fn()
check(#t.calls == 0, "waits while the last take is pending")
pending = false
t.fire("MAIL_CLOSED")

fillInbox(); t.reset()
freeSlots = 0
t.fire("MAIL_SHOW"); t.runTicker()
check(has("money 1") and not t.printed("item "), "full bags: takes money, leaves items")
freeSlots = 5
t.fire("MAIL_CLOSED")

fillInbox(); t.reset()
t.fire("MAIL_SHOW")
t.fire("MAIL_FAILED", 9)
t.runTicker()
check(has("item 10") and not has("item 9"), "an item the game refused is skipped")
t.fire("MAIL_CLOSED")

fillInbox(); t.reset()
t.fire("MAIL_SHOW")
t.shift = true
t.runTicker()
t.shift = false
check(#t.calls == 0, "Shift stops it")
t.fire("MAIL_CLOSED")

M.db.takeMail = false
fillInbox(); t.reset()
t.fire("MAIL_SHOW")
check(#t.tickers == 0 or t.tickers[#t.tickers].cancelled, "off means off")

t.done()
