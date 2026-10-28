-- Island toasts: the notices shown while the island is closed, their slots, lifetimes and motion, and do not disturb.
return function(_, check, lib)
	local read_source, island_world, fire_after, finish_animations, last_toast_text, notice_key = lib.read_source, lib.island_world, lib.fire_after, lib.finish_animations, lib.last_toast_text, lib.notice_key
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "Routine one" })
		api.notify({ text = "Routine two" })
		api.notify({ text = "Routine three" })
		for index = 1, 5 do api.notify({ text = "Warning " .. index, severity = "warning" }) end
		api.notify({ text = "Late routine" })
		local view = addon.island.view()
		check("a routine burst cannot evict queued warnings", #view.queue == 5 and view.queue[1].text == "Warning 1" and view.queue[5].text == "Warning 5")
		api.notify({ source = "Important", key = "error", text = "Equipment broken", severity = "error" })
		view = addon.island.view()
		check("an error releases the oldest routine card through its exit", view.toasts[1].id == first and view.toasts[1].phase == "exiting" and #view.toasts == 3)
		api.notify({ source = "Important", key = "error", text = "Equipment still broken", severity = "error" })
		check("a keyed error update cannot repeatedly preempt active cards", addon.island.view().toasts[2].phase ~= "exiting")
		finish_animations(frames)
		view = addon.island.view()
		check("errors promote ahead of warnings without erasing warning history", view.toasts[3].text == "Equipment still broken" and #view.queue == 4)
		api.dismiss(view.toasts[2].id)
		finish_animations(frames)
		check("warning promotion preserves FIFO within its severity", last_toast_text(addon) == "Warning 2")
	end
	do
		local addon, env, _, state, afters = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "Read without a deadline", duration = 4 })
		state.time = 100.5
		env.everlook_island_key("down")
		state.time = 200
		fire_after(afters, 4)
		env.everlook_island_key("up")
		check("resuming preserves the remaining visible lifetime", afters[#afters].delay == 3.5 and #addon.island.view().toasts == 1)
		fire_after(afters, 3.5)
		check("the resumed timer expires its own toast", addon.island.view().toasts[1].phase == "exiting")
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "First notice", duration = 2 })
		local second = api.notify({ text = "Second notice", duration = 6 })
		local third = api.notify({ text = "Third notice", duration = 8 })
		local view = addon.island.view()
		check("three notices emerge together without resizing the island", #view.toasts == 3 and view.width == 64 and view.mode == "closed")
		check("concurrent notices keep their own text and handles", view.toasts[1].id == first and view.toasts[2].id == second and view.toasts[3].id == third and view.toasts[2].text == "Second notice")
		finish_animations(frames)
		view = addon.island.view()
		check("toast entrances settle into separate rows", view.toasts[1].alpha == 1 and view.toasts[1].y > view.toasts[2].y and view.toasts[2].y > view.toasts[3].y)
		fire_after(afters, 2)
		check("only the expired toast begins leaving", addon.island.view().toasts[1].phase == "exiting" and addon.island.view().toasts[2].phase == "visible")
		finish_animations(frames)
		view = addon.island.view()
		check("an expired toast leaves the other notices visible", #view.toasts == 2 and view.toasts[1].id == second and view.toasts[2].id == third)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		for index = 1, 4 do env.Everlook.island.notify({ text = "Burst " .. index, duration = index + 1 }) end
		local view = addon.island.view()
		check("a fourth toast waits for a visible slot", #view.toasts == 3 and #view.queue == 1 and view.queue[1].text == "Burst 4")
		check("queued notices do not start their reading timer", #afters == 3)
		finish_animations(frames)
		fire_after(afters, 2)
		finish_animations(frames)
		view = addon.island.view()
		check("a queued toast enters when an earlier toast finishes leaving", #view.toasts == 3 and #view.queue == 0 and view.toasts[3].text == "Burst 4" and afters[#afters].delay == 5)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "First use", duration = 2 })
		finish_animations(frames)
		fire_after(afters, 2)
		finish_animations(frames)
		local frame_count = #frames
		env.Everlook.island.notify({ text = "Reuse the first slot" })
		finish_animations(frames)
		local view = addon.island.view()
		check("a reused toast frame becomes visible at the same position", #view.toasts == 1 and view.toasts[1].alpha == 1 and view.toasts[1].phase == "visible" and #frames == frame_count)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "reduced_motion", true)
		local handle = env.Everlook.island.notify({ text = "A quieter notice" })
		local view = addon.island.view()
		check("reduced motion fades a toast at its final position", view.toasts[1].y == -8 and view.toasts[1].alpha == 0)
		finish_animations(frames)
		addon.module.set("island", "reduced_motion", false)
		finish_animations(frames)
		env.Everlook.island.dismiss(handle)
		addon.module.set("island", "reduced_motion", true)
		view = addon.island.view()
		check("enabling reduced motion also settles a pending exit", view.toasts[1].y == 0)
		finish_animations(frames)
		check("a reduced-motion exit still cleans up the toast", #addon.island.view().toasts == 0)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local active = api.notify({ source = "Producer", key = "work", text = "Working", duration = 2 })
		local old_timeout = afters[#afters].callback
		local handles = {}
		for index = 2, 14 do handles[index] = api.notify({ text = "Burst " .. index }) end
		local view = addon.island.view()
		check("burst limits keep three active and preserve five waiting peers", #view.toasts == 3 and #view.queue == 5 and view.queue[1].text == "Burst 4" and view.queue[5].text == "Burst 8")
		local updated = api.notify({ source = "Producer", key = "work", text = "Done", duration = 6 })
		check("a keyed toast stays stable even after its history row is evicted", updated == active and addon.island.view().toasts[1].text == "Done")
		old_timeout()
		check("the replaced timer cannot close an updated toast", addon.island.view().toasts[1].phase ~= "exiting")
		api.dismiss(handles[4])
		local queued = api.notify({ source = "Producer", key = "pending", text = "Queued" })
		local timer_count = #afters
		updated = api.notify({ source = "Producer", key = "pending", text = "Queued update", duration = 8 })
		view = addon.island.view()
		check("queued updates replace one row without consuming a slot or timer", queued == updated and #view.queue == 5 and view.queue[5].text == "Queued update" and #afters == timer_count)
		check("a queued notification can be dismissed before it appears", api.dismiss(queued) and #addon.island.view().queue == 4)
		finish_animations(frames)
		api.dismiss(active)
		check("dismissing a visible toast begins an individual exit", addon.island.view().toasts[1].phase == "exiting" and #addon.island.view().toasts == 3)
		finish_animations(frames)
		check("a dismissal makes room for the next queued notice", #addon.island.view().toasts == 3 and #addon.island.view().queue == 3)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "A" })
		for index = 1, 3 do api.notify({ text = "More " .. index }) end
		local stale_timeout = afters[1].callback
		local stale_finished
		for _, card in ipairs(frames) do
			for _, group in ipairs(card.animation_groups or {}) do
				stale_finished = stale_finished or group.scripts.OnFinished
			end
		end
		addon.module.set("island", "enabled", false)
		check("disabling removes the active stack and waiting notices immediately", #addon.island.view().toasts == 0 and #addon.island.view().queue == 0)
		addon.module.set("island", "enabled", true)
		api.notify({ text = "Fresh" })
		stale_timeout()
		stale_finished()
		check("old timer and animation completions cannot affect reused frames", #addon.island.view().toasts == 1 and addon.island.view().toasts[1].text == "Fresh" and not api.dismiss(first))
		addon.module.set("island", "toasts", false)
		api.notify({ text = "History only" })
		check("toast controls preserve notifications in the expanded history", #addon.island.view().toasts == 0 and #addon.island.view().queue == 0 and addon.island.view().notices[#addon.island.view().notices].text == "History only")
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		for index = 1, 4 do env.Everlook.island.notify({ text = "Peek " .. index, duration = index + 1 }) end
		finish_animations(frames)
		env.everlook_island_key("down")
		check("opening the island hides the stack immediately", addon.island.view().mode == "open" and not addon.island.view().toasts[1].shown)
		fire_after(afters, 2)
		check("the queue and active lifetimes pause during inspection", #addon.island.view().toasts == 3 and #addon.island.view().queue == 1)
		state.time = state.time + 0.3
		env.everlook_island_key("up")
		check("closing a peek resumes the stack without consuming its queue", addon.island.view().mode == "closed" and #addon.island.view().toasts == 3 and #addon.island.view().queue == 1 and addon.island.view().toasts[1].shown)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.UIParent.GetWidth = function() return 240 end
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = string.rep("Long notice ", 30) })
		local view = addon.island.view()
		check("long notices wrap inside the screen width", view.toasts[1].width == 208 and view.toasts[1].height > 34)
		for _, card in ipairs(frames) do
			if card.animation_groups then check("toast surfaces let clicks through to the game", card.mouse == false) end
		end
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local handle = api.notify({ source = "A", key = "a", text = "In flight" })
		for _, card in ipairs(frames) do
			for _, group in ipairs(card.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do animation.progress = 0.5 end
			end
		end
		local before = addon.island.view().toasts[1]
		api.notify({ source = "A", key = "a", text = "Updated in flight" })
		local after = addon.island.view().toasts[1]
		check("mid-animation updates keep the current position and opacity", before.y == after.y and before.alpha == after.alpha and after.id == handle)
		api.dismiss(handle)
		after = addon.island.view().toasts[1]
		check("an interrupted entrance starts its exit from the visible position", before.y == after.y and before.alpha == after.alpha and after.phase == "exiting")
	end
	do
		local addon = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "do_not_disturb", true)
		addon.island.notify({ source = "Test", key = "quiet", text = "Routine", severity = "warning" })
		addon.island.notify({ source = "Test", key = "info", text = "Info" })
		local view = addon.island.view()
		check("do not disturb sends warnings and routine notices to the inbox", #view.toasts == 0 and #view.notices == 2)
		addon.island.notify({ source = "Test", key = "bad", text = "Failure", severity = "error" })
		check("do not disturb still toasts an error", #addon.island.view().toasts == 1)
	end
	do
		-- A notice that never toasts, under Do not disturb, kept quiet in combat or with toasts off,
		-- stays in the inbox until it is seen or dismissed. The inbox size still caps it.
		local function run_out(afters, seconds)
			for index = 1, #afters do
				local timer = afters[index]
				if timer.delay == seconds and not timer.done then timer.done = true; timer.callback() end
			end
		end
		local addon, env, _, state, afters = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "do_not_disturb", true)
		addon.island.notify({ source = "Test", key = "quiet", text = "Routine", duration = 4 })
		run_out(afters, 4)
		check("a notice do not disturb kept from toasting outlasts its duration", notice_key(addon, "quiet") ~= nil)
		-- Held, not tapped, so letting go closes it again.
		env.everlook_island_key("down")
		state.time = state.time + 2
		run_out(afters, 0.75)
		check("opening the island lets it be seen", notice_key(addon, "quiet") and notice_key(addon, "quiet").unread == false)
		env.everlook_island_key("up")
		check("and letting go closes it", addon.island.view().mode ~= "open")
		run_out(afters, 4)
		check("once seen it goes when its time runs out", notice_key(addon, "quiet") == nil)

		addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "toasts", false)
		addon.island.notify({ source = "Test", key = "untoasted", text = "Routine", duration = 4 })
		run_out(afters, 4)
		check("with toasts off a notice outlasts its duration in the inbox", notice_key(addon, "untoasted") ~= nil)

		addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		env.InCombatLockdown = function() return true end
		addon.island.notify({ source = "Test", key = "fight", text = "Routine", duration = 4 })
		run_out(afters, 4)
		check("a routine notice kept quiet in combat outlasts its duration", notice_key(addon, "fight") ~= nil)

		addon = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "do_not_disturb", true)
		for index = 1, 12 do addon.island.notify({ source = "Test", key = "q" .. index, text = "Quiet " .. index }) end
		check("the inbox size still caps notices that never toasted", #addon.island.view().notices == 10)
	end
	do
		local addon, env = island_world()
		addon.module.set("island", "enabled", true)
		check("dismiss with no toast does nothing", env.everlook_island_dismiss() == nil and addon.island.dismiss_top() == false)
		addon.island.notify({ source = "Test", key = "older", text = "Older" })
		addon.island.notify({ source = "Test", key = "newer", text = "Newer" })
		env.everlook_island_dismiss()
		local remaining = {}
		for _, notice in ipairs(addon.island.view().notices) do remaining[#remaining + 1] = notice.text end
		check("the dismiss key removes the newest toast first", table.concat(remaining, ",") == "Older")
		-- The game warns when a header is declared twice, in one file or across addons.
		local seen, once = {}, true
		for _, file in ipairs({ "Everlook_Island/Bindings.xml", "Everlook_IslandShare/Bindings.xml", "Everlook_RadialMenu/Bindings.xml" }) do
			for header in read_source(file):gmatch('header="([%w_]+)"') do
				if seen[header] then once = false end
				seen[header] = true
			end
		end
		check("every binding header is declared once, and each has a name to show", once and next(seen) ~= nil
			and (function()
				local names = read_source("Everlook_Island/island.lua") .. read_source("Everlook_IslandShare/island_share.lua") .. read_source("Everlook_RadialMenu/radial_menu.lua")
				for header in pairs(seen) do if not names:find("BINDING_HEADER_" .. header .. " =", 1, true) then return false end end
				return true
			end)())
		check("the binding file names the dismiss action", read_source("Everlook_Island/Bindings.xml"):find("EVERLOOK_ISLAND_DISMISS", 1, true) ~= nil)
	end
	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local function accents()
			local found = {}
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.width == 3 and region.shown == true and region.color and region.color[4] == 1 and region.height and region.height >= 4 then
						found[#found + 1] = region.color
					end
				end
			end
			return found
		end
		addon.island.notify({ source = "Test", key = "plain", text = "Plain" })
		check("an info toast has no severity bar", #accents() == 0)
		addon.island.notify({ source = "Test", key = "careful", text = "Careful", severity = "warning" })
		local bars = accents()
		check("a warning toast has a bar in the warning colour", #bars == 1 and bars[1][1] == 1 and bars[1][2] == 0.62)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local function has(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return true end
				end
			end
			return false
		end
		addon.island.notify({ source = "everlook.buffs", key = "own", text = "Own warning", severity = "warning" })
		check("an Everlook warning toast names its severity and not its source", has("Warning") and not has("Warning, Everlook"))
		addon.island.notify({ source = "OtherAddon", key = "foreign", text = "Their warning", severity = "warning" })
		check("another addon's toast names its source", has("Warning, OtherAddon"))
	end
end
