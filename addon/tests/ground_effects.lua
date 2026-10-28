-- Ground effects: sets how much ground clutter, such as grass, the game draws, how far away, and how far it fades out.
return function(check, lib)
	local load_files = lib.load_files
	local addon, play, fire = load_files({ "world", "module", "ground_effects" })
	-- Ground effects set three of the game's settings, remember each one, and put each back.
	local ground = { groundEffectDensity = "16", groundEffectDist = "70", groundEffectFade = "70" }
	local writes = {}
	play.GetCVar = function(name)
		return ground[name]
	end
	play.SetCVar = function(name, value)
		writes[#writes + 1] = name
		if ground[name] == nil then error("Unknown CVar " .. name) end
		ground[name] = value
	end
	addon.module.set("ground_effects", "enabled", true)
	check("ground effects set density, distance and fade to the saved numbers", ground.groundEffectDensity == "256" and ground.groundEffectDist == "500" and ground.groundEffectFade == "500")
	addon.module.set("ground_effects", "distance", 300)
	check("a changed number is applied at once", ground.groundEffectDist == "300" and ground.groundEffectDensity == "256")
	-- A reload in the middle: a new session with the same saved variables and the game's settings as they were left.
	do
		local reloaded, reloaded_env = load_files({ "world", "module", "ground_effects" })
		reloaded_env.EverlookSaved.modules = play.EverlookSaved.modules
		reloaded_env.EverlookSaved.ground_effects_before = play.EverlookSaved.ground_effects_before
		reloaded_env.GetCVar = play.GetCVar
		reloaded_env.SetCVar = play.SetCVar
		reloaded.module.set("ground_effects", "enabled", false)
		check("turning ground effects off after a reload still puts back what the game had at first, not the numbers set here",
			ground.groundEffectDensity == "16" and ground.groundEffectDist == "70" and ground.groundEffectFade == "70")
		reloaded.module.set("ground_effects", "enabled", true)
	end
	addon.module.set("ground_effects", "enabled", false)
	check("turning ground effects off puts each setting back as it was before", ground.groundEffectDensity == "16" and ground.groundEffectDist == "70" and ground.groundEffectFade == "70")
	ground.groundEffectFade = nil
	writes = {}
	addon.module.set("ground_effects", "enabled", true)
	check("a setting this client does not have is left alone, and the others still apply", ground.groundEffectFade == nil and ground.groundEffectDensity == "256" and #writes == 2)
	addon.module.set("ground_effects", "enabled", false)
	play.GetCVar = nil
	play.SetCVar = nil
	addon.module.set("ground_effects", "enabled", true)
	check("with no way to set them, ground effects do nothing and do not fail", true)
	addon.module.set("ground_effects", "enabled", false)
end
