local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("Everlook")

-- An addon defined inline, loaded the way the game would.
local addon = Everlook:NewAddon("TestAddon", {
	label = "Test",
	defaults = { flag = true, nested = { size = 3 } },
})
local order = {}
function addon:OnInitialize()
	order[#order + 1] = "init"
end
function addon:OnEnable() order[#order + 1] = "enable" end
t.fire("ADDON_LOADED", "TestAddon")

check(addon.db.flag == true and addon.db.nested.size == 3, "db is filled from defaults")
check(EverlookDB.TestAddon == addon.db, "db is saved under the addon's name")
check(order[1] == "init" and order[2] == nil, "OnInitialize runs on ADDON_LOADED, OnEnable waits")

t.fire("PLAYER_LOGIN")
check(order[2] == "enable", "OnEnable runs on PLAYER_LOGIN")

-- Saved values win over defaults.
EverlookDB.Late = { flag = false }
local late = Everlook:NewAddon("Late", { defaults = { flag = true, other = 1 } })
local lateEnabled = false
function late:OnEnable() lateEnabled = true end
t.fire("ADDON_LOADED", "Late")
check(late.db.flag == false and late.db.other == 1, "saved values are kept, missing keys filled")
check(lateEnabled, "an addon loaded after login is enabled at once")

-- Events.
local got
function addon:SOME_EVENT(event, value) got = event .. value end
addon:RegisterEvent("SOME_EVENT")
t.fire("SOME_EVENT", 7)
check(got == "SOME_EVENT7", "RegisterEvent calls the method named for the event")

addon:RegisterEvent("OTHER_EVENT", function(event) got = "fn " .. event end)
t.fire("OTHER_EVENT")
check(got == "fn OTHER_EVENT", "RegisterEvent takes a function")

addon:UnregisterEvent("SOME_EVENT")
check(not t.frame.events.SOME_EVENT, "UnregisterEvent drops the frame event when nobody listens")

-- Print and slash commands.
t.reset()
addon:Print("hello")
check(t.printed("TestAddon") and t.printed("hello") and not t.printed("TestAddon:"), "Print prefixes the addon name, no colon")

addon:RegisterChatCommand("tst", function(input) got = "slash " .. input end)
SlashCmdList.EVERLOOK_TESTADDON_TST("hi")
check(got == "slash hi" and SLASH_EVERLOOK_TESTADDON_TST1 == "/tst", "RegisterChatCommand")

check(not pcall(Everlook.NewAddon, Everlook, "TestAddon"), "NewAddon refuses a duplicate name")
check(Everlook.category == nil and Everlook.addons.TestAddon.AddCheckbox == nil, "the core has no settings code of its own")

-- Money text: newest API first, then GetMoneyString, then plain text.
check(Everlook.FormatMoney(12345) == "1g 23s 45c" and Everlook.FormatMoney(500) == "5s"
	and Everlook.FormatMoney(0) == "0c", "FormatMoney falls back to plain gold/silver/copper")
GetMoneyString = function(copper) return "money " .. copper end
check(Everlook.FormatMoney(7) == "money 7", "FormatMoney uses GetMoneyString when there is one")
C_CurrencyInfo = { GetCoinTextureString = function(copper) return "coins " .. copper end }
check(Everlook.FormatMoney(7) == "coins 7", "FormatMoney prefers C_CurrencyInfo.GetCoinTextureString")
GetMoneyString, C_CurrencyInfo = nil, nil

t.done()
