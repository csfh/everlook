-- Cinematic skip: closes a cinematic or a movie when it starts.
return function(root, check, lib)
	local load_files = lib.load_files
	local addon, play, fire = load_files({ "world", "module", "cinematic_skip" })
	-- The game's own CinematicFrame_CancelCinematic, as Shared/CinematicFrame.lua:133-141 has it at
	-- 12.0.0, with isRealCinematic set from the event's first argument as its OnEvent does (:86):
	-- this stands for Blizzard's frame handling the event before Everlook's.
	local calls = { stop = 0, scene = 0, vehicle = 0, finished = {} }
	local in_scene, scene_cancellable, movie_up = false, false, false
	play.CinematicFrame = { isRealCinematic = false }
	play.CinematicFrame_CancelCinematic = function()
		if play.CinematicFrame.isRealCinematic then
			play.StopCinematic()
		elseif play.CanCancelScene() then
			play.CancelScene()
		else
			play.VehicleExit()
		end
	end
	play.StopCinematic = function() calls.stop = calls.stop + 1 end
	play.CancelScene = function() calls.scene = calls.scene + 1 end
	play.VehicleExit = function() calls.vehicle = calls.vehicle + 1 end
	play.CanCancelScene = function() return scene_cancellable end
	play.IsInCinematicScene = function() return in_scene end
	-- MovieFrame.xml's close dialog: Yes calls MovieFrame_OnMovieFinished(MovieFrame, true).
	play.MovieFrame = { IsShown = function() return movie_up end }
	play.MovieFrame_OnMovieFinished = function(frame, user_canceled)
		calls.finished[#calls.finished + 1] = { frame = frame, user_canceled = user_canceled }
	end
	local function cinematic(can_be_cancelled)
		play.CinematicFrame.isRealCinematic = can_be_cancelled
		fire("CINEMATIC_START", can_be_cancelled, false)
	end
	addon.module.set("cinematic_skip", "enabled", true)
	cinematic(true)
	check("a cinematic the player may skip is stopped", calls.stop == 1 and calls.vehicle == 0)
	cinematic(false)
	check("a vehicle's cinematic keeps playing, and the player stays in the vehicle", calls.vehicle == 0 and calls.stop == 1)
	in_scene, scene_cancellable = true, true
	cinematic(false)
	check("a cinematic scene the game lets the player cancel is cancelled", calls.scene == 1 and calls.vehicle == 0)
	in_scene, scene_cancellable = false, false
	movie_up = true
	fire("PLAY_MOVIE", 16)
	check("a movie is finished as the player's own Yes finishes it, and nothing else is cancelled",
		#calls.finished == 1 and calls.finished[1].frame == play.MovieFrame and calls.finished[1].user_canceled == true
		and calls.vehicle == 0 and calls.stop == 1 and calls.scene == 1)
	movie_up = false
	fire("PLAY_MOVIE", 16)
	check("a movie whose frame is not up yet is left alone", #calls.finished == 1)
	play.IsShiftKeyDown = function()
		return true
	end
	movie_up = true
	cinematic(true)
	fire("PLAY_MOVIE", 16)
	check("Shift leaves a cinematic and a movie playing", calls.stop == 1 and #calls.finished == 1)
	play.IsShiftKeyDown = function()
		return false
	end
	movie_up = false
	play.StopCinematic = nil
	cinematic(true)
	check("a client without StopCinematic stops nothing and leaves no vehicle", calls.vehicle == 0 and calls.scene == 1)
end
