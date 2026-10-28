-- World: the core's shared helpers, from a creature's id in its GUID to the readable, finite and text checks.
return function(check, lib)
	local source = lib.source
	local function load_core(extra)
		local Everlook = {}
		local env = setmetatable(extra or {}, { __index = _G })
		env.EventUtil = { ContinueOnAddOnLoaded = function() end }
		for _, file in ipairs({ "world" }) do
			local chunk = assert(loadfile(source(file)))
			setfenv(chunk, env)
			chunk("Everlook", Everlook)
		end
		return Everlook, env
	end

	do
		local addon = load_core()
		check("the namespace is the global Everlook, for module addons", rawget(_G, "Everlook") == addon)
		check("creature id is the entry field", addon.npcs.creature_id("Creature-0-1-0-2-448-abc") == 448)
		check("creature id can end on the entry", addon.npcs.creature_id("Creature-0-1-0-2-448") == 448)
		check("a vehicle id is read the same way", addon.npcs.creature_id("Vehicle-0-1-0-2-69") == 69)
		check("players are not creatures", addon.npcs.creature_id("Player-1-2") == nil)
		check("the same guid is read once", addon.npcs.creature_id("Creature-0-1-0-2-448-abc") == 448)
		check("an item link gives its id", addon.items.id_from_link("item:2589") == 2589)
		check("a coloured item link gives its id", addon.items.id_from_link("|cff9d9d9d|Hitem:2589::::::::1:::::::::|h[Linen Cloth]|h|r") == 2589)
		check("a link that is not an item has no id", addon.items.id_from_link("spell:133") == nil)
		local playing = load_core({ UnitGUID = function(unit) return unit == "player" and "Player-1-0A" or nil end })
		check("the player's GUID is the key for what is kept per character", playing.player_guid() == "Player-1-0A")
		check("no GUID, a creature's, or a client without UnitGUID gives no key",
			load_core({ UnitGUID = function() return nil end }).player_guid() == nil
			and load_core({ UnitGUID = function() return "Creature-0-1-0-2-448" end }).player_guid() == nil
			and load_core({}).player_guid() == nil)
		check("a hidden GUID gives no key", load_core({
			UnitGUID = function() return "hidden" end, issecretvalue = function(value) return value == "hidden" end,
		}).player_guid() == nil)
		local said = {}
		local talking = load_core({
			DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) said[#said + 1] = text end },
		})
		talking.say("Sold junk.")
		talking.say("")
		check("say writes one chat line with the Everlook prefix", #said == 1 and said[1] == "Everlook: Sold junk.")
		local hidden = load_core({ issecretvalue = function(value) return value == "hidden" end })
		check("a hidden value is secret", hidden.secret("hidden") == true and hidden.public("hidden") == nil)
		check("a public value comes back", hidden.public(7) == 7 and hidden.secret(7) == false)
		check("a hidden guid is not a creature", hidden.npcs.creature_id("hidden") == nil)
		check("a hidden link is not an item", hidden.items.id_from_link("hidden") == nil)
		local masked = load_core({ issecretvalue = function(value) return value == 42 end })
		check("a public number that is neither NaN nor infinite is finite",
			masked.finite(7) == true and masked.finite(0) == true and masked.finite(-2.5) == true)
		check("nil, a hidden number, NaN, the infinities and a numeric string are not finite",
			masked.finite(nil) == false and masked.finite(42) == false and masked.finite(0 / 0) == false
			and masked.finite(math.huge) == false and masked.finite(-math.huge) == false and masked.finite("7") == false)
		check("a value that is there and public is readable, false included",
			masked.readable(7) == true and masked.readable("text") == true and masked.readable(false) == true)
		check("nil and a hidden value are not readable", masked.readable(nil) == false and masked.readable(42) == false)
		local widget = { size = 3 }
		function widget:Grow(by, times) self.size = self.size + by * times; return self.size, "grown" end
		local size, word = masked.call(widget, "Grow", 2, 3)
		check("call runs a method the object has, with its arguments, and gives back what it returns", size == 9 and word == "grown")
		check("call does nothing for a method the object lacks, a value that is not a method, or no object",
			masked.call(widget, "Shrink") == nil and masked.call(widget, "size") == nil and masked.call(nil, "Grow", 1, 1) == nil and widget.size == 9)
		local timed = load_core({ debugprofilestop = function() return 1234.5 end })
		check("the clock reads the game's profiling timer in milliseconds", timed.clock() == 1234.5)
		check("without that timer the clock gives nothing", masked.clock() == nil)
		check("text is a readable string with something in it, up to the length given",
			masked.text("Inspect", 7) == true and masked.text(" a ", 3) == true)
		check("a longer, blank, empty, missing or non-string value is not text",
			masked.text("Inspect", 6) == false and masked.text("   ", 8) == false and masked.text("", 8) == false
			and masked.text(nil, 8) == false and masked.text(42, 8) == false and masked.text(7, 8) == false)
	end
end
