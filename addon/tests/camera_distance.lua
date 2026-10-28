-- Camera distance: sets the farthest the camera can zoom out, using the factor on Maximum camera distance, from 1 to 4.
return function(root, check, lib)
	local load_files = lib.load_files
	local addon, play, fire = load_files({ "world", "module", "camera_distance" })
	local distance = "1.0"
	play.GetCVar = function()
		return distance
	end
	play.SetCVar = function(_, value)
		distance = value
	end
	addon.module.set("camera_distance", "enabled", true)
	check("camera distance uses the saved setting", distance == "2.6")
	addon.module.set("camera_distance", "distance", 3)
	-- A reload in the middle: a new session with the same saved variables, and the game still holding the number set here.
	do
		local reloaded, reloaded_env = load_files({ "world", "module", "camera_distance" })
		reloaded_env.EverlookSaved.modules = play.EverlookSaved.modules
		reloaded_env.EverlookSaved.camera_distance_before = play.EverlookSaved.camera_distance_before
		reloaded_env.GetCVar = play.GetCVar
		reloaded_env.SetCVar = play.SetCVar
		reloaded.module.set("camera_distance", "enabled", false)
		check("turning the camera off after a reload puts back the distance from before, not the one set here", distance == "1.0")
		reloaded.module.set("camera_distance", "enabled", true)
	end
	addon.module.set("camera_distance", "enabled", false)
	check("turning the camera off restores the previous distance", distance == "1.0")
end
