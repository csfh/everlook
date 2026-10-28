-- Island capsule: the closed pill's one row, from the spec a producer gives a status to the states people see it in.
return function(check, lib)
	local island_world, quest_world, secret_stat = lib.island_world, lib.quest_world, lib.secret_stat
	do
		-- The capsule spec a producer gives a status: what it accepts, what it draws, and how it stays right
		-- as it changes. Every call goes through Everlook.island, as an outside addon would make it.
		local layout = lib.layout

		local function world()
			local addon, env, event, state, afters, tickers, frames = island_world()
			addon.module.set("island", "enabled", true)
			addon.module.set("island", "reduced_motion", true)
			return addon, env, state, frames, afters
		end

		local function status(overrides)
			local spec = { source = "MyAddon", key = "trip", text = "Flying to Ratchet", presentation = "status",
				capsule = { text = "Ratchet", icon = "flight" } }
			for name, value in pairs(overrides or {}) do spec[name] = value end
			return spec
		end

		do
			local addon, env = world()
			local api = env.Everlook.island
			check("the capsule api is part of version 3", api.api == 3)

			local function rejected(label, capsule, reason)
				local handle, why = api.notify(status({ capsule = capsule }))
				check("a capsule is rejected: " .. label, handle == nil and why == (reason or "invalid_capsule"))
			end
			rejected("with nothing in it", {})
			rejected("with four labels", { text = "x", labels = { "a", "b", "c", "d" } })
			rejected("with three labels and a trailing one", { text = "x", labels = { "a", "b", "c" }, trailing = "d" })
			rejected("with a ring past one", { text = "x", ring = { fraction = 2 } })
			rejected("with a ring in a color that does not exist", { text = "x", ring = { fraction = 0.5, tone = "pink" } })
			rejected("with an arrow that is a string", { text = "x", arrow = "up" })
			rejected("with a label that has markup", { text = "x", labels = { "|cffff0000red|r" } })
			rejected("with a badge too long", { text = "x", badge = string.rep("9", 17) })
			rejected("with a title past 64 bytes", { text = string.rep("x", 65) })
			rejected("with a held width that is too narrow", { text = "x", min_width = 50 })
			rejected("with a held width that is too wide", { text = "x", min_width = 400 })
			rejected("with a held width that is not whole", { text = "x", min_width = 100.5 })

			local handle = api.notify(status({ capsule = { text = string.rep("x", 40), icon = "flight", arrow = function() return 0 end,
				ring = { fraction = 0.5, tone = "success" }, labels = { "~5 yd", { text = "20", tone = "primary" } }, badge = "45%", min_width = 300 } }))
			check("a capsule with a long title, an arrow, a ring, labels in tones, a badge and a held width is accepted", type(handle) == "number")
			local only_parts = api.notify(status({ key = "parts", capsule = { arrow = 1, labels = { "~5 yd" } } }))
			check("a capsule needs no title when it has other parts", type(only_parts) == "number")
		end

		do
			local addon, env, state, frames = world()
			local api = env.Everlook.island
			local angle, calls = 0.5, 0
			local errors = {}
			env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
			local handle = api.notify(status({ capsule = { text = "Ratchet", icon = "flight", arrow = function() calls = calls + 1; return angle end,
				ring = { fraction = 0.4, tone = "warning" }, labels = { "~5 yd" }, badge = "45%" } }))
			layout.settle(frames)
			local function region(text)
				for _, frame in ipairs(frames) do
					for _, found in ipairs(frame.regions or {}) do
						if found.text == text and found.shown ~= false then return found end
					end
				end
			end
			local function arrow_texture()
				for _, frame in ipairs(frames) do
					local walker, in_slot = frame, false
					while walker do
						if walker.name == "EverlookIslandFace" then in_slot = true end
						walker = walker.parent
					end
					if in_slot then
						for _, found in ipairs(frame.regions or {}) do
							if type(found.path) == "string" and found.path:find("island_arrow", 1, true) and found.shown == true then return found end
						end
					end
				end
			end
			check("a status capsule draws its title, label and badge", region("Ratchet") and region("~5 yd") and region("45%"))
			check("its arrow points at the angle the function gave", arrow_texture() and arrow_texture().rotation == 0.5 and calls >= 1)
			local driver
			for _, frame in ipairs(frames) do
				if frame.name == nil and frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookIslandFace" then driver = frame end
			end
			angle = 1.25
			driver.scripts.OnUpdate(driver, 0.05)
			local asked = calls
			driver.scripts.OnUpdate(driver, 0.06)
			check("it is asked at most every tenth of a second, and then the arrow turns", calls == asked + 1 and arrow_texture().rotation == 1.25)
			angle = nil
			driver.scripts.OnUpdate(driver, 0.1)
			check("a function that gives no angle hides the arrow", arrow_texture() == nil)

			-- A change of words is set in place: no crossfade, and the width holds.
			local before = addon.island.view().shell
			api.update(handle, { capsule = { text = "Ratchet", icon = "flight", arrow = function() return 0 end,
				ring = { fraction = 0.6, tone = "warning" }, labels = { "~4 yd" }, badge = "46%" } })
			local after = addon.island.view().shell
			check("new words and a new fraction replace in place, with no fade", region("~4 yd") ~= nil and region("~5 yd") == nil and after.fading ~= true)
			-- An update of the notice's own fields keeps the capsule whole.
			api.update(handle, { detail = "30 seconds elapsed" })
			local kept = addon.island.view().status.capsule
			check("an update that does not name the capsule keeps all of it: arrow, ring, labels and badge",
				type(kept.arrow) == "function" and kept.ring and kept.ring.tone == "warning" and kept.labels[1] == "~4 yd" and kept.badge == "46%")
		end

		do
			local addon, env = world()
			local api = env.Everlook.island
			api.notify(status({ capsule = { text = "x", min_width = 320 } }))
			check("a capsule that asks to hold a width is that wide", addon.island.view().width == 320)
			api.notify(status({ key = "narrow", capsule = { text = "x" } }))
			check("one that does not is as wide as its words need", addon.island.view().width < 100)
		end

		-- A background status holds the capsule and nothing else.
		do
			local addon, env, state, frames, afters = world()
			local api = env.Everlook.island
			local function background(overrides)
				local spec = { source = "MyAddon", key = "quest", text = "Excavation", detail = "~885 yd", presentation = "status", rank = "background",
					capsule = { icon = "quest", text = "Excavation", labels = { "~885 yd" } } }
				for name, value in pairs(overrides or {}) do
					if value == false then spec[name] = nil else spec[name] = value end
				end
				return spec
			end
			local function rejected(label, spec)
				local handle, why = api.notify(spec)
				check("a background status is rejected: " .. label .. " (" .. tostring(why) .. ")", handle == nil and why == "invalid_rank")
			end
			rejected("with a rank that does not exist", background({ rank = "loud" }))
			rejected("on a toast", background({ presentation = "toast", capsule = false }))
			rejected("without a capsule to show", background({ capsule = false }))

			local handle = api.notify(background())
			local function region(text)
				for _, frame in ipairs(frames) do
					local visible, walker = true, frame
					while walker do
						if walker.shown == false or (walker.alpha or 1) == 0 then visible = false end
						walker = walker.parent
					end
					for _, found in ipairs(frame.regions or {}) do
						if visible and found.text == text and found.shown ~= false then return found end
					end
				end
			end
			layout.settle(frames)
			local view = addon.island.view()
			check("a background status shows on the capsule", type(handle) == "number" and region("Excavation") ~= nil and view.background and view.background.count == 1)
			check("it is no status, no history row, no toast and not unread",
				view.status == nil and #view.notices == 0 and #view.toasts == 0 and view.unread_count == 0)

			-- The control: a normal status under the same clock does go, so a pass here means the clock ran.
			local mortal = api.notify({ source = "MyAddon", key = "mortal", text = "Mortal", presentation = "status", capsule = { text = "Mortal" } })
			state.time = state.time + 600
			for _, after in ipairs(afters) do
				if after.delay == 30 and not after.done then after.done = true; after.callback() end
			end
			layout.settle(frames)
			check("a normal status leaves when its thirty seconds pass", type(mortal) == "number" and addon.island.view().status == nil)
			check("a background status stays through the same clock", addon.island.view().background ~= nil and region("Excavation") ~= nil)

			local status_handle = api.notify({ source = "MyAddon", key = "flight", text = "Flying", presentation = "status", capsule = { text = "Ratchet", icon = "flight" } })
			layout.settle(frames)
			check("a real status takes the capsule while it lasts", region("Ratchet") ~= nil and region("Excavation") == nil and addon.island.view().background ~= nil)
			api.dismiss(status_handle)
			layout.settle(frames)
			check("and when it is dismissed the background status is back", region("Excavation") ~= nil and region("Ratchet") == nil)

			for index = 1, 12 do api.notify({ source = "MyAddon", key = "s" .. index, text = "Status " .. index, presentation = "status", capsule = { text = "S" .. index } }) end
			for index = 1, 12 do api.dismiss(addon.island.view().status and addon.island.view().status.id or 0) end
			check("a pile of statuses does not push it out", addon.island.view().background ~= nil)

			local again = api.update(handle, { detail = "~700 yd" })
			check("an update keeps its handle and its rank", again == handle and addon.island.view().background.count == 1 and #addon.island.view().notices == 0)
			check("dismissing it clears the capsule", api.dismiss(handle) == true and addon.island.view().background == nil)

			api.notify(background())
			addon.module.set("island", "enabled", false)
			addon.module.set("island", "enabled", true)
			check("turning the island off clears it", addon.island.view().background == nil)
		end
	end

	do
		-- The closed capsule in the states people see it: its resolved rectangles are written out so a change
		-- to how it is drawn can be compared with how it was, and its measurements are held here.
		local layout = lib.layout

		local function ready(world)
			local addon, env, event, state, afters, tickers, frames = world()
			addon.module.set("island", "enabled", true)
			addon.module.set("island", "reduced_motion", true)
			local top
			for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then top = frame end end
			return addon, env, event, state, tickers, frames, top
		end

		local states = {}

		-- The wide quest capsule.
		do
			local addon, _, _, _, _, frames, top = ready(quest_world)
			addon.module.set("island", "quest_context", true)
			layout.settle(frames)
			states.wide = { addon = addon, frames = frames, top = top }
		end

		-- The compact quest capsule: no title, no ring.
		do
			local addon, _, _, _, _, frames, top = ready(quest_world)
			addon.module.set("island", "quest_context", true)
			addon.module.set("island", "quest_title", false)
			layout.settle(frames)
		end

		-- With an unread count.
		do
			local addon, env, _, _, _, frames, top = ready(quest_world)
			addon.module.set("island", "quest_context", true)
			env.Everlook.island.notify({ source = "Test", key = "unread", text = "Something new", presentation = "inbox" })
			layout.settle(frames)
		end

		-- A status with a mark, trailing text and progress.
		do
			local addon, env, _, _, _, frames, top = ready(island_world)
			env.Everlook.island.notify({ source = "Test", key = "flight", text = "Flying to Ratchet", presentation = "status",
				capsule = { text = "Ratchet", icon = "flight", trailing = "0:30", progress = 0.5 } })
			layout.settle(frames)
		end

		-- The level chip.
		do
			local addon, _, _, _, _, frames, top = ready(island_world)
			layout.settle(frames)
		end
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local function finish_morph()
			local island, resting
			for _, object in ipairs(frames) do
				if object.name == "EverlookIsland" then island = object end
				if object.name == "EverlookIslandResting" then resting = object end
			end
			if island and island.scripts.OnUpdate and resting and resting.animation_groups and resting.animation_groups[1] then
				resting.animation_groups[1].animations[1].progress = 1
				island.scripts.OnUpdate()
			end
		end
		local function shown_text(needle)
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text and region.text:find(needle, 1, true) then return region.text end
				end
			end
		end
		local payload = { source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status",
			capsule = { icon = "flight", text = "1:10", trailing = "Ratchet" } }
		local handle = api.notify(payload)
		payload.capsule.text = "9:99"
		local view = addon.island.view()
		check("a copied capsule survives mutation of the caller's table", handle and view.status.capsule.text == "1:10" and view.status.capsule.trailing == "Ratchet")
		check("a capsule morph starts from the resting width", view.shell.playing and view.shell.from == 64 and view.shell.to == view.width and view.width > 64)
		finish_morph()
		local settled = addon.island.view().shell.width
		api.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status", capsule = { icon = "clock", text = "1:10", trailing = "Ratchet" } })
		view = addon.island.view()
		check("an icon change starts from the current width", view.shell.playing and view.shell.from == settled)
		finish_morph()
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		for index = #afters, 1, -1 do
			if afters[index].delay == 0.75 then afters[index].callback() end
		end
		local pill = addon.island.view().shell.width
		api.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status", capsule = { icon = "clock", text = "1:09", trailing = "Ratchet" } })
		view = addon.island.view()
		check("a clock update keeps one read notice and the same pill width", view.unread_count == 0 and #view.notices == 1 and view.shell.width == pill and view.status.capsule.text == "1:09")
		local rejected, reason = api.notify({ source = "A", key = "toast", text = "Hello", capsule = { text = "1:10" } })
		check("a capsule on a toast is rejected", rejected == nil and reason == "invalid_capsule")
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		rejected, reason = api.notify({ source = "A", key = "secret", text = "Flying", presentation = "status", capsule = { text = secret } })
		check("a secret capsule is rejected", rejected == nil and reason == "invalid_capsule" and addon.island.view().status.capsule.text == "1:09")
		env.issecretvalue = nil
		rejected, reason = api.notify({ source = "A", key = "mark", text = "Flying", presentation = "status", capsule = { text = "1:10|T" } })
		check("markup in capsule text is rejected", rejected == nil and reason == "invalid_capsule")
		local runs = {}
		for index = 1, 7 do runs[index] = { text = "Run" } end
		rejected, reason = api.notify({ source = "A", key = "runs", text = "Too many", runs = runs })
		check("a seventh run is rejected", rejected == nil and reason == "invalid_runs")
		rejected, reason = api.notify({ source = "A", key = "atlas", text = "Bad atlas", runs = { { atlas = "Interface/Icons/Foo" } } })
		check("a path-like atlas is rejected", rejected == nil and reason == "invalid_atlas")
		env.GetMoneyString = function(amount) return "<coin:" .. amount .. ">" end
		handle = api.notify({ source = "A", key = "rich", text = "Paid", runs = {
			{ text = "Paid", tone = "primary" }, { money = -21500 }, { atlas = "Taxi_Frame_Gray" },
		} })
		local compiled = shown_text("|A:Taxi_Frame_Gray:16:16|a")
		check("compiled runs contain the coin color and the atlas escape", handle and compiled and compiled:find("|cffffd166", 1, true) and compiled:find("|A:Taxi_Frame_Gray:16:16|a", 1, true))
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "reduced_motion", true)
		env.Everlook.island.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status",
			capsule = { icon = "flight", text = "1:10", trailing = "Ratchet" } })
		local view = addon.island.view()
		check("reduced motion settles on the target width in one paint", view.shell.width == view.width and view.width > 64 and view.shell.playing)
	end
	do
		local addon = island_world()
		local layout = addon.island_capsule.layout
		local function measure(text) return #text * 7 end
		local with_progress = layout({ text = "Flight to Stormwind", progress = 0.4 }, measure, 280)
		check("a status capsule shows its progress as a percent in purple, not as a bar",
			with_progress.row.badge == "40%" and with_progress.row.title == "Flight to Stormwind" and #with_progress.row.labels == 0)
		local with_trailing = layout({ text = "Flight", trailing = "soon", progress = 0.4 }, measure, 280)
		check("a trailing mark of its own is a label and keeps the percent away", with_trailing.row.labels[1] == "soon" and with_trailing.row.badge == nil)
		check("with no progress there is nothing to show", layout({ text = "Flight" }, measure, 280).row.badge == nil)
		-- The width a capsule asks for is worked out from its words with the row's own spacing:
		-- 12 inset, the title, 12, then the trailing parts, then 12 more. With a mark the title starts at 34.
		local plain = layout({ text = "Flight" }, measure, 280)
		local marked = layout({ text = "Flight", icon = "flight" }, measure, 280)
		local counted = layout({ text = "Flight", progress = 0.4 }, measure, 280)
		check("a capsule's width is its title plus the row's insets, and a mark adds its room, 64 at the least",
			plain.width == 66 and marked.width == 88 and counted.width == 100)
		check("a capsule is at most 280 wide unless it asks to hold a width, and its width is even", layout({ text = string.rep("x", 100) }, measure, 400).width == 280
			and layout({ text = "x", min_width = 320 }, measure, 400).width == 320 and layout({ text = "xxxxxxx" }, measure, 400).width % 2 == 0)
		check("a held width is kept clear of the unread count's room", layout({ text = "x", min_width = 320 }, measure, 400, 20).width == 340)
		local signature = addon.island_capsule.signature
		check("a capsule's shape is what parts it has, so a new distance does not change it",
			signature({ text = "a", labels = { "~5 yd" } }) == signature({ text = "b", labels = { "~6 yd" } })
			and signature({ text = "a", labels = { "~5 yd" } }) ~= signature({ text = "a", labels = { "~5 yd", "12" } })
			and signature({ text = "a" }) ~= signature({ text = "a", ring = { fraction = 0.5 } }))
	end
end
