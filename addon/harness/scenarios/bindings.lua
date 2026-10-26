-- The key bindings: each has the name the game lists it under, each header is its own, and each binding's
-- body runs against the functions the addon defines.
harness.include("lib/game.lua")
game.quests()
harness.load_addon("Everlook")
harness.load_addon("Everlook_Island")
harness.load_addon("Everlook_IslandShare")
harness.load_addon("Everlook_RadialMenu")
game.login()
Everlook.module.set("smart_island", "enabled", true)
harness.advance(1)

local headers = {}
for _, addon in ipairs({ "Everlook_Island", "Everlook_IslandShare", "Everlook_RadialMenu" }) do
	for _, binding in ipairs(harness.bindings(addon)) do
		harness.check(addon .. ": " .. binding.name .. " has a name to list it under", type(_G["BINDING_NAME_" .. binding.name]) == "string")
		if binding.header then
			harness.check(addon .. ": header " .. binding.header .. " has a title", type(_G["BINDING_HEADER_" .. binding.header]) == "string")
			harness.check(addon .. ": header " .. binding.header .. " is used by no other addon", headers[binding.header] == nil)
			headers[binding.header] = addon
		end
		-- Running the body with each key state must not fail on a function that does not exist.
		local chunk, why = loadstring("local keystate = ...; " .. binding.body)
		harness.check(addon .. ": " .. binding.name .. " has a body that compiles", chunk ~= nil)
		if chunk then
			local ok, err = pcall(chunk, "down")
			if ok and binding.run_on_up then ok, err = pcall(chunk, "up") end
			harness.check(addon .. ": " .. binding.name .. " runs" .. (ok and "" or ": " .. tostring(err)), ok)
		end
	end
end

-- The island's key, held and released, opens and then pins or closes it.
local island_key = harness.bindings("Everlook_Island")[1]
local chunk = loadstring("local keystate = ...; " .. island_key.body)
local before = Everlook.smart_island.view().pinned
chunk("down")
harness.advance(0.2)
harness.check("holding the island key opens it", Everlook.smart_island.view().mode == "open")
chunk("up")
harness.advance(0.5)
harness.check("a quick tap of it toggles the pin", Everlook.smart_island.view().pinned == not before)
