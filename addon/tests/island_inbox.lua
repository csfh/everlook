-- Island inbox: the notices the open island keeps, which of them are unread, and which go when it is full.
return function(check, lib)
	local island_world, fire_after, finish_animations = lib.island_world, lib.fire_after, lib.finish_animations
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local handle = env.Everlook.island.notify({ text = "Keep this notice", duration = 4 })
		state.time = 100.5
		env.everlook_island_key("down")
		state.time = 100.6
		env.everlook_island_key("up")
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		local view = addon.island.view()
		check("a short peek retains an unread notice", #view.notices == 1 and view.notices[1].id == handle and view.unread_count == 1)
		env.everlook_island_key("down")
		state.time = 110
		fire_after(afters, 4)
		finish_animations(frames)
		check("inspection pauses visible toast expiry", #addon.island.view().toasts == 1)
		afters[#afters].callback()
		check("visible rows become read after the dwell", addon.island.view().unread_count == 0)
		env.everlook_island_key("up")
		check("closing inspection retains its history", #addon.island.view().notices == 1)
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		env.UIParent.GetWidth = function() return 320 end
		env.UIParent.GetHeight = function() return 400 end
		addon.module.set("island", "enabled", true)
		for index = 1, 10 do env.Everlook.island.notify({ text = "History row " .. index }) end
		env.everlook_island_key("down")
		local controls = {}
		for _, button in ipairs(frames) do if button.name then controls[button.name] = button end end
		local island_scroll_to = addon.island.scroll_to
		local view = addon.island.view()
		check("the inbox exposes overflow inside a bounded viewport", view.scroll_height <= 240 and view.content_height > view.scroll_height and view.height <= 400)
		local function shown_fades()
			local fades = {}
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.gradient and region.shown ~= false then fades[#fades + 1] = region end
				end
			end
			return fades
		end
		check("each fade has a white base for the gradient to tint", #shown_fades() == 1 and shown_fades()[1].color ~= nil and shown_fades()[1].color[4] == 1)
		check("a list with more below fades out at its bottom edge", view.more_below and not view.more_above and #shown_fades() == 1
			and shown_fades()[1].gradient.low.a > 0.9 and shown_fades()[1].gradient.high.a == 0)
		island_scroll_to(view.scroll_height)
		check("a list scrolled into the middle fades at both edges", addon.island.view().more_below and addon.island.view().more_above and #shown_fades() == 2)
		island_scroll_to(0)
		view = addon.island.view()
		local function button_text()
			for _, region in ipairs(controls.EverlookIslandNewNotices.regions or {}) do
				if type(region.text) == "string" then return region.text end
			end
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if type(region.text) == "string" and region.text:find(" new notice", 1, true) then return region.text end
				end
			end
		end
		check("the footer counts the unread rows below the visible ones", view.unread_below > 0 and view.unread_below < 10
			and button_text() == view.unread_below .. " new notices" and controls.EverlookIslandNewNotices.shown ~= false)
		local first_unread_below = view.unread_below
		controls.EverlookIslandNewNotices.scripts.OnClick()
		view = addon.island.view()
		check("the button brings the first of them to the top, not just the bottom", view.scroll_offset > 0 and view.scroll_offset < view.content_height - view.scroll_height + 1
			and view.unread_below < first_unread_below)
		check("new notices can be reached without growing the panel", view.scroll_offset > 0)
		for _ = 1, 10 do
			if addon.island.view().unread_below == 0 then break end
			controls.EverlookIslandNewNotices.scripts.OnClick()
		end
		island_scroll_to(addon.island.view().content_height)
		check("a list scrolled to its end fades only at its top", addon.island.view().more_above and not addon.island.view().more_below and #shown_fades() == 1
			and shown_fades()[1].gradient.high.a > 0.9 and shown_fades()[1].gradient.low.a == 0)
		check("with nothing unread below, the button goes away", controls.EverlookIslandNewNotices.shown == false)
		-- Room for one more, so the list grows and the new row starts below the old end.
		addon.module.set("island", "inbox_size", 30)
		local before_arrival = addon.island.view().content_height
		env.Everlook.island.notify({ text = "Arrives while you are at the end" })
		view = addon.island.view()
		check("a notice that arrives under your eyes is not counted as below them", view.content_height > before_arrival and view.unread_below == 0 and controls.EverlookIslandNewNotices.shown == false
			and view.scroll_offset == view.content_height - view.scroll_height)
		addon.module.set("island", "inbox_size", 10)
		controls.EverlookIslandClearHistory.scripts.OnClick()
		check("clear history acknowledges the inbox with Undo", #addon.island.view().notices == 0 and addon.island.view().can_undo)
		env.Everlook.island.notify({ source = "New arrival", text = "Arrived after clear" })
		controls.EverlookIslandUndo.scripts.OnClick()
		view = addon.island.view()
		check("Undo merges new arrivals without replaying toasts", #view.notices == 10 and view.notices[10].text == "Arrived after clear" and #view.toasts == 0 and not view.can_undo)
		controls.EverlookIslandClearHistory.scripts.OnClick()
		fire_after(afters, 5)
		-- The first clear's timeout is stale; the second clear owns the window.
		fire_after(afters, 5)
		check("Undo expires without restoring history", not addon.island.view().can_undo and #addon.island.view().notices == 0)
		state.time = 101
		env.everlook_island_key("up")
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ source = "Work", key = "one", text = "Before clear" })
		env.everlook_island_key("down")
		local stale_read = afters[#afters].callback
		addon.island.clear_history()
		addon.island.undo_clear()
		stale_read()
		check("Undo requires a fresh reading dwell", addon.island.view().unread_count == 1)
		afters[#afters].callback()
		check("a restored row becomes read after its new dwell", addon.island.view().unread_count == 0)
		env.Everlook.island.notify({ source = "Work", key = "one", text = "Changed after reading" })
		check("changed content rearms unread without duplicating history", addon.island.view().unread_count == 1 and #addon.island.view().notices == 1)
	end
	do
		local addon = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "inbox_size", 20)
		addon.module.set("island", "toast_count", 1)
		for index = 1, 15 do addon.island.notify({ source = "Test", key = "n" .. index, text = "Notice " .. index }) end
		local view = addon.island.view()
		check("the inbox keeps as many notices as the option allows", #view.notices == 15)
		check("the toast count option caps the stack", #view.toasts == 1)
		addon.module.set("island", "inbox_size", 10)
		check("lowering the inbox size trims the oldest notices", #addon.island.view().notices == 10)
	end
	do
		local addon = island_world()
		local inbox, toasts = addon.island_inbox, addon.island_toasts
		local list = {
			{ id = 1, text = "old routine", unread = false, updated_at = 1 },
			{ id = 2, text = "warning", severity = "warning", unread = false, updated_at = 2 },
			{ id = 3, text = "decision", persist = true, unread = false, updated_at = 3 },
			{ id = 4, text = "new routine", unread = true, updated_at = 4 },
		}
		check("the inbox counts unread notices", inbox.unread(list) == 1)
		inbox.evict(list, 3)
		check("a full inbox drops the oldest routine notice first", #list == 3 and list[1].id == 2)
		inbox.evict(list, 2)
		check("then the unread routine one before warnings and decisions", #list == 2 and list[1].id == 2 and list[2].id == 3)
		local merged = inbox.restore({ { id = 5, key = "k", source = "S", updated_at = 9 } }, {
			{ id = 6, key = "k", source = "S", updated_at = 1 }, { id = 7, updated_at = 5 }, { id = 8, updated_at = 5 } })
		local ids = {}
		for _, entry in ipairs(merged) do ids[#ids + 1] = entry.id end
		check("a cleared notice replaced by its producer stays gone and the rest merge in time order",
			table.concat(ids, ",") == "7,8,5")
		local queue = { { severity = "info" }, { severity = "warning" }, { severity = "warning" }, { severity = "error" } }
		check("the highest priority waits at the front, ties to the earliest", toasts.next_index(queue) == 4)
		table.remove(queue, 4)
		check("a tie keeps the earlier notice", toasts.next_index(queue) == 2)
		check("a newcomer replaces the first lower-priority waiting notice", toasts.evict_index(queue, { severity = "error" }) == 1)
		check("an equal newcomer replaces nothing", toasts.evict_index({ { severity = "warning" } }, { severity = "warning" }) == nil)
	end
end
