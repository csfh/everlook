local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local secret = Everlook.secret
local id = "cinematic_skip"

-- The game's own way out of a cinematic (CinematicFrame_CancelCinematic), without its last resort:
-- a cinematic that is neither one the player may skip nor a scene that can be cancelled is a
-- vehicle's, and the game ends that by taking the player out of the vehicle. That one keeps playing.
local function cancel_cinematic(can_be_cancelled)
	if not secret(can_be_cancelled) and can_be_cancelled == true then
		if type(StopCinematic) == "function" then StopCinematic() end
		return
	end
	if type(IsInCinematicScene) == "function" and type(CanCancelScene) == "function" and type(CancelScene) == "function"
		and IsInCinematicScene() and CanCancelScene() then
		CancelScene()
	end
end

-- What Yes on the movie's close dialog does. Only a movie whose frame is up has started.
local function cancel_movie()
	local frame = MovieFrame
	if type(MovieFrame_OnMovieFinished) ~= "function" or type(frame) ~= "table" or type(frame.IsShown) ~= "function" or not frame:IsShown() then
		return
	end
	MovieFrame_OnMovieFinished(frame, true)
end

module.register({
	addon = addon_name, page = "screen", order = 80,
	id = id,
	name = "Cinematic skip",
	description = "Closes a cinematic or a movie when it starts. One already playing stays up, a cinematic that only ends when you leave a vehicle keeps playing, holding Shift leaves the new one playing, nothing happens when the client has no cancel function, and turning this off leaves the next one.",
	events = { "CINEMATIC_START", "PLAY_MOVIE" },
	on_event = function(event, ...)
		if module.paused() then return end
		if event == "CINEMATIC_START" then
			cancel_cinematic((...))
		elseif event == "PLAY_MOVIE" then
			cancel_movie()
		end
	end,
})
