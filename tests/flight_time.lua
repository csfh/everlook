-- Flight time: shows a timer at the top of the screen for a flight you take after this is on, with the destination and the elapsed time, and remembers the route when that flight lasts more than a second.
return function(check, lib)
	local load_all, island_world, secret_stat = lib.load_all, lib.island_world, lib.secret_stat
	local addon, env, _, hooks, _, frames = load_all()
	local time, flying = 0, false
	env.GetTime = function() return time end
	env.UnitOnTaxi = function() return flying end
	env.TakeTaxiNode = function() end
	env.NumTaxiNodes = function() return 2 end
	env.TaxiNodeGetType = function(i) return i == 1 and "CURRENT" or "REACHABLE" end
	env.TaxiNodeName = function(i) return i == 1 and "Origin" or "Destination" end
	addon.module.set("flight_time", "enabled", true)
	local ground_poller
	for _, frame in ipairs(frames) do
		if frame.name == "EverlookFlightTimePoller" then ground_poller = frame end
	end
	check("flight time stays idle until a flight is taken", ground_poller and ground_poller.scripts.OnUpdate == nil)
	hooks.TakeTaxiNode(2)
	check("taking a flight starts the poller", ground_poller.scripts.OnUpdate ~= nil)
	local function update()
		for _, frame in ipairs(frames) do
			if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.25) end
		end
	end
	update(); time = 1; flying = true; update(); time = 61; flying = false; update()
	local route = env.EverlookSaved.modules.flight_time.routes["::Origin>Destination"]
	check("flight duration learns while display starts hidden", route and route.seconds == 60 and route.samples == 1)
	check("landing stops the flight poller", ground_poller.scripts.OnUpdate == nil)
	do
		-- A reload in the air: a new session with the same saved variables, the same clock, and the player still on the taxi.
		time = 100
		hooks.TakeTaxiNode(2)
		flying = true
		update()
		check("a flight in the air is kept in the saved variables", env.EverlookSaved.modules.flight_time.current and env.EverlookSaved.modules.flight_time.current.started == 100)
		local resumed, resumed_env, _, resumed_hooks, _, resumed_frames = load_all()
		resumed_env.EverlookSaved.modules = env.EverlookSaved.modules
		resumed_env.GetTime = env.GetTime
		resumed_env.UnitOnTaxi = env.UnitOnTaxi
		resumed_env.TakeTaxiNode = function() end
		resumed.module.set("flight_time", "enabled", true)
		time = 160
		for _, frame in ipairs(resumed_frames) do
			if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.25) end
		end
		flying = false
		time = 220
		for _, frame in ipairs(resumed_frames) do
			if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 0.25) end
		end
		local after = env.EverlookSaved.modules.flight_time.routes["::Origin>Destination"]
		check("after a reload in the air the flight is timed from when it started", after and after.samples == 2 and after.seconds == 90)
		check("landing clears the saved flight", env.EverlookSaved.modules.flight_time.current == nil)
		flying = false
	end
	do
		local addon, env, _, state, _, _, frames, hooks = island_world()
		local flying = false
		env.UnitOnTaxi = function() return flying end
		env.TakeTaxiNode = function() end
		env.NumTaxiNodes = function() return 2 end
		env.TaxiNodeGetType = function(index) return index == 1 and "CURRENT" or "REACHABLE" end
		env.TaxiNodeName = function(index) return index == 1 and "Crossroads" or "Ratchet" end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_flight", true)
		addon.module.set("flight_time", "enabled", true)
		local poller, timer
		for _, object in ipairs(frames) do
			if object.name == "EverlookFlightTimePoller" then poller = object end
			if object.name == "EverlookFlightTime" then timer = object end
		end
		check("flight time does not poll while you are on the ground", poller and poller.scripts.OnUpdate == nil)
		hooks.TakeTaxiNode(2)
		check("taking a flight starts one poller", poller.scripts.OnUpdate ~= nil)
		poller.scripts.OnUpdate(poller, 0.25)
		check("a flight request alone has no ongoing status", addon.island.view().status == nil)
		flying, state.time = true, 101
		poller.scripts.OnUpdate(poller, 0.25)
		local view = addon.island.view()
		local handle = view.status and view.status.id
		check("an unknown flight shows elapsed time without invented progress", handle and view.status.text == "Flying to Ratchet" and view.status.progress == nil and #view.toasts == 0)
		state.time = 102
		poller.scripts.OnUpdate(poller, 0.25)
		check("flight updates retain one status identity", addon.island.view().status and addon.island.view().status.id == handle and #addon.island.view().notices == 1)
		check("an unknown flight capsule shows elapsed time", addon.island.view().status.capsule and addon.island.view().status.capsule.text == "0:01" and addon.island.view().status.capsule.trailing == "Ratchet")
		flying, state.time = false, 161
		poller.scripts.OnUpdate(poller, 0.25)
		view = addon.island.view()
		check("arrival completes the existing status exactly once", view.status == nil and #view.toasts == 1 and view.toasts[1].id == handle and view.toasts[1].text == "Arrived at Ratchet")
		hooks.TakeTaxiNode(2)
		flying, state.time = true, 200
		poller.scripts.OnUpdate(poller, 0.25)
		state.time = 230
		poller.scripts.OnUpdate(poller, 0.25)
		check("a learned flight estimate produces measured progress", addon.island.view().status and addon.island.view().status.progress == 0.5)
		check("a learned flight capsule shows remaining time", addon.island.view().status.capsule and addon.island.view().status.capsule.text == "0:30")
		state.time = 230.25
		local updated_at = addon.island.view().status.updated_at
		poller.scripts.OnUpdate(poller, 0.25)
		check("flight status updates are limited to once per second", addon.island.view().status.updated_at == updated_at)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		flying = secret
		poller.scripts.OnUpdate(poller, 0.25)
		check("unreadable taxi state does not invent arrival", addon.island.view().status ~= nil and #addon.island.view().toasts == 1)
		flying, env.issecretvalue = true, nil
		addon.module.set("flight_time", "only_island", true)
		poller.scripts.OnUpdate(poller, 0.25)
		check("Island-only display is an explicit flight preference", not timer.shown)
		local original, errors = env.Everlook.island.notify, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.flight_time" then error("display failed") end
			return original(payload)
		end
		state.time = 231.5
		poller.scripts.OnUpdate(poller, 0.25)
		check("a failed flight feed cleans up its status and keeps the ordinary timer", #errors == 1 and addon.island.view().status == nil and timer.shown)
		env.Everlook.island.notify = original
		state.time = 233
		poller.scripts.OnUpdate(poller, 0.25)
		addon.module.set("island", "source_flight", false)
		poller.scripts.OnUpdate(poller, 0.25)
		check("disabling the feed removes status and restores the ordinary timer", addon.island.view().status == nil and timer.shown)
		addon.module.set("flight_time", "enabled", false)
		check("disabling flight time clears its own display and poller", not timer.shown and poller.scripts.OnUpdate == nil)
	end
end
