-- Flight time: shows a timer at the top of the screen for a flight you take after this is on, with the destination and the elapsed time, and remembers the route when that flight lasts more than a second.
return function(root, check, lib)
	local load_all = lib.load_all
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
end
