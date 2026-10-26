harness.include("lib/game.lua")
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Island")
game.login()
Everlook.module.set("smart_island", "enabled", true)
harness.advance(1)
local island = harness.find("EverlookSmartIsland")
harness.check("the island frame exists", island ~= nil)
for _, e in ipairs(harness.errors()) do print("script error:", e) end
for _, m in ipairs(harness.missing()) do print("missing method:", m) end
for _, m in ipairs(harness.fields_read()) do print("unset field read:", m) end
