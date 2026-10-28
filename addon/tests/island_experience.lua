-- Island experience: shows the experience you earned in the last hour and day in the open island.
return function(check, lib)
	local island_world = lib.island_world
	do
		local addon, env, event, state = island_world()
		local server = 1000000
		env.GetServerTime = function() return server end
		env.UnitGUID = function() return "Player-1-00000002" end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_experience", true)
		local experience = addon.island_experience
		event("PLAYER_ENTERING_WORLD")
		local first = experience.report()
		check("the experience report is reused within a second", rawequal(first, experience.report()))
		state.xp = state.xp + 100
		event("PLAYER_XP_UPDATE")
		local second = experience.report()
		check("a new gain makes a new report", not rawequal(first, second) and second.hour.total == 100)
		server = server + 1
		check("the next second makes a new report", not rawequal(second, experience.report()))
	end
	do
		local addon, env, event, state = island_world()
		local server = 2000000
		env.GetServerTime = function() return server end
		env.UnitGUID = function() return "Player-1-00000003" end
		env.GetXPExhaustion = function() return 0 end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_experience", true)
		local experience = addon.island_experience
		event("PLAYER_ENTERING_WORLD")
		state.xp = state.xp + 120
		event("PLAYER_XP_UPDATE")
		local data = experience.table()
		check("the experience table starts with a total row for hour and day", data and data.rows[1][1] == "Total"
			and data.rows[1][2] == "120" and data.rows[1][3] == "120")
		check("an unlabeled gain shows as Other", data.rows[2] and data.rows[2][1] == "Other" and data.rows[2][2] == "120")
		check("slices with nothing in them stay out", #data.rows == 2)
		check("the footer carries rested and pace", type(data.footer) == "string" and data.footer:find("rested", 1, true) ~= nil)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.GetServerTime = function() return 3000000 end
		env.UnitGUID = function() return "Player-1-00000004" end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_experience", true)
		event("PLAYER_ENTERING_WORLD")
		state.xp = state.xp + 90
		event("PLAYER_XP_UPDATE")
		env.everlook_island_key("down")
		local function text_of(match)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if type(region.text) == "string" and region.text:find(match, 1, true) and region.shown ~= false then return region.text end
				end
			end
		end
		local function heading_button()
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if (region.text == "Show sources" or region.text == "Hide sources") and region.shown ~= false then return region.parent.parent end
				end
			end
		end
		check("experience starts folded to its Total row, with a button to show the sources", text_of("EXPERIENCE") and not text_of("> EXPERIENCE") and text_of("Show sources") and text_of("Total") and not text_of("Other"))
		local toggle = heading_button()
		toggle.scripts.OnClick(toggle)
		check("the button opens the slices and offers to hide them", text_of("Hide sources") and text_of("Other"))
		toggle = heading_button()
		toggle.scripts.OnClick(toggle)
		check("and another folds them again", not text_of("Other") and text_of("Show sources"))
	end
end
