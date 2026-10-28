-- Island notice: how a producer's payload is read into a notice, and which payloads are refused.
return function(_, check, lib)
	local island_world, secret_stat = lib.island_world, lib.secret_stat
	do
		local addon, env = island_world()
		addon.module.set("island", "enabled", true)
		local payload = { text = "Equipment repaired", detail = "Personal funds", money = -21500,
			severity = "success", icon = "repair", progress = 0.5, presentation = "inbox" }
		local handle = env.Everlook.island.notify(payload)
		payload.detail, payload.money = "Changed by caller", 0
		local view = addon.island.view()
		local entry = view.notices[1]
		check("rich notifications copy accepted fields without showing an inbox-only card", handle and entry.detail == "Personal funds"
			and entry.money == -21500 and entry.severity == "success" and entry.icon == "repair" and entry.progress == 0.5
			and entry.presentation == "inbox" and #view.toasts == 0)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		local cases = {
			{ "severity", "urgent" }, { "severity", secret }, { "severity", false },
			{ "detail", string.rep("x", 513) }, { "detail", secret }, { "detail", {} },
			{ "icon", {} }, { "icon", secret },
			{ "money", 1.5 }, { "money", math.huge }, { "money", 0 / 0 }, { "money", secret }, { "money", 9007199254740992 },
			{ "progress", -0.1 }, { "progress", 1.1 }, { "progress", math.huge }, { "progress", secret },
			{ "presentation", "modal" }, { "presentation", secret }, { "presentation", false },
		}
		for index, case in ipairs(cases) do
			local input = { text = "Safe" }
			input[case[1]] = case[2]
			local ok, accepted, reason = pcall(env.Everlook.island.notify, input)
			check("invalid rich field " .. index .. " is rejected safely", ok and accepted == nil and reason == "invalid_" .. case[1])
		end
		local fallback = env.Everlook.island.notify({ text = "Unknown icon", icon = "someone-elses-icon" })
		entry = addon.island.view().notices[2]
		check("unknown icon names fall back with legacy defaults", fallback and entry.icon == "generic" and entry.severity == "info" and entry.presentation == "toast")
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local missing, reason = api.notify({ text = "Activity", presentation = "status" })
		check("status requires an explicit source and key", missing == nil and reason == "invalid_status_source")
		missing, reason = api.notify({ source = "Flight", text = "Activity", presentation = "status" })
		check("status requires a stable key", missing == nil and reason == "invalid_status_key")
		local first = api.notify({ source = "Flight", key = "trip", text = "Flying to Ratchet", presentation = "status", progress = 0.1 })
		local old_deadline = afters[#afters].callback
		local second = api.notify({ source = "Quest", key = "active", text = "Smart Drinks", presentation = "status" })
		local view = addon.island.view()
		check("the newest status owns one row while earlier activity stays in history", view.status and view.status.id == second and #view.notices == 2 and #view.toasts == 0)
		local updated = api.notify({ source = "Flight", key = "trip", text = "Flying to Ratchet", presentation = "status", progress = 0.8 })
		old_deadline()
		view = addon.island.view()
		check("progress refreshes liveness without taking a newer status's row", updated == first and view.status.id == second and #view.notices == 2 and view.unread_count == 2)
		api.dismiss(second)
		check("dismissing the owner restores the earlier live activity", addon.island.view().status.id == first)
		local current_deadline = afters[#afters].callback
		api.notify({ source = "Flight", key = "trip", text = "Arrived at Ratchet", severity = "success", presentation = "toast" })
		current_deadline()
		view = addon.island.view()
		check("status completion keeps its handle and becomes one toast", view.status == nil and #view.toasts == 1 and view.toasts[1].id == first and #view.notices == 1)
		api.notify({ source = "Quest", key = "forgotten", text = "No more updates", presentation = "status" })
		afters[#afters].callback()
		check("abandoned activity falls back to retained history", addon.island.view().status == nil and #addon.island.view().notices == 2)
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		local cases = {
			{ secret, "invalid_notification" },
			{ "message", "invalid_notification" },
			{ { text = "   " }, "invalid_text" },
			{ { text = string.rep("x", 513) }, "invalid_text" },
			{ { text = secret }, "invalid_text" },
			{ { text = "Safe", source = secret }, "invalid_source" },
			{ { text = "Safe", key = secret }, "invalid_key" },
			{ { text = "Safe", kind = secret }, "invalid_kind" },
			{ { text = "Safe", duration = secret }, "invalid_duration" },
			{ { text = "Safe", duration = 0 / 0 }, "invalid_duration" },
			{ { text = "Safe", duration = math.huge }, "invalid_duration" },
			{ { text = "Safe", duration = 0 }, "invalid_duration" },
			{ { text = "Safe", duration = 31 }, "invalid_duration" },
			{ { text = "Safe", persist = secret }, "invalid_persist" },
			{ { text = "Safe", persist = "yes" }, "invalid_persist" },
			{ { text = "Safe", stack = secret }, "invalid_stack" },
			{ { text = "Safe", stack = "   " }, "invalid_stack" },
			{ { text = "Safe", stack = string.rep("s", 65) }, "invalid_stack" },
			{ setmetatable({}, { __index = function() error("foreign code") end }), "invalid_notification" },
		}
		for index, case in ipairs(cases) do
			local ok, handle, reason = pcall(api.notify, case[1])
			check("invalid notification " .. index .. " is rejected without inspecting secret values", ok and handle == nil and reason == case[2])
		end
		check("invalid input adds no notifications", #addon.island.view().notices == 0)
		check("secret handles cannot dismiss notifications or event subscriptions", not api.dismiss(secret) and not api.unregister_event(secret))
		local calls, removed = 0
		api.register_event("QUEST_TURNED_IN", function() api.unregister_event(removed) end)
		removed = api.register_event("QUEST_TURNED_IN", function() calls = calls + 1 end)
		event("QUEST_TURNED_IN")
		check("an adapter removed during dispatch is skipped", calls == 0)
		local handle, reason = api.register_event(secret, function() end)
		check("secret event names are rejected", handle == nil and reason == "invalid_event")
		handle, reason = api.register_event("QUEST_TURNED_IN", "callback")
		check("invalid event callbacks are rejected", handle == nil and reason == "invalid_callback")
		for _, frame in ipairs(frames) do
			if frame.events.QUEST_TURNED_IN then frame.RegisterEvent = function() return false end end
		end
		handle, reason = api.register_event("NOT_A_WOW_EVENT", function() end)
		check("a refused native event registration is not retained", handle == nil and reason == "invalid_event")
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		-- Use a fresh fixture because the native event stub above intentionally rejects registration.
		local other, other_env, other_event = island_world()
		other.module.set("island", "enabled", true)
		other_env.geterrorhandler = env.geterrorhandler
		other_env.Everlook.island.register_event("QUEST_TURNED_IN", function() return { text = "" } end)
		other_env.Everlook.island.register_event("QUEST_TURNED_IN", function() return nil end)
		other_event("QUEST_TURNED_IN")
		check("invalid adapter output is observable and nil means no notice", #errors == 1 and errors[1]:find("invalid_text", 1, true) and #other.island.view().notices == 0)
	end
	do
		local addon = island_world()
		local read = addon.island_notice.read
		local record = read({ text = "Hello", kind = "mail", severity = "warning" }, 4)
		check("a plain payload reads into a record with defaults",
			record and record.source == "everlook" and record.duration == 4 and record.icon == "mail" and record.presentation == "toast")
		local bad, reason = read({ text = "  " }, 4)
		check("blank text is refused with its reason", bad == nil and reason == "invalid_text")
		bad, reason = read({ text = "x", progress = 2 }, 4)
		check("progress outside zero to one is refused", bad == nil and reason == "invalid_progress")
		bad, reason = read({ text = "x", presentation = "status" }, 4)
		check("a status needs a source", bad == nil and reason == "invalid_status_source")
		check("an unknown icon falls back to the kind then generic",
			addon.island_notice.icon_for("nope", "x") == "generic" and addon.island_notice.icon_for(nil, "durability") == "repair")
	end
end
