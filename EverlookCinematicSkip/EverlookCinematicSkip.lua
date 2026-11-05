local CinematicSkip = Everlook:NewAddon("EverlookCinematicSkip", {
	label = "Cinematic Skip",
	defaults = {
		skip = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookCinematicSkip", {
	"StopCinematic",
	"IsInCinematicScene",
	"CanCancelScene",
	"CancelScene",
	"MovieFrame",
	"MovieFrame.GetScript",
	"C_Timer.After",
	"IsShiftKeyDown",
}, {
	"MovieFrame_OnMovieFinished",
})

function CinematicSkip:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "World & Camera")
	page:Checkbox("skip", "Skip cinematics and movies",
		"Close a cinematic or movie as it starts. Vehicle cinematics keep playing. Hold Shift to watch.")
end

function CinematicSkip:OnEnable()
	self:RegisterEvent("CINEMATIC_START")
	self:RegisterEvent("PLAY_MOVIE")
end

-- The game's own way out (CinematicFrame_CancelCinematic), without its last resort: a cinematic
-- that is neither skippable nor a cancellable scene belongs to a vehicle, and the game ends that
-- by taking you out of the vehicle. That one keeps playing.
function CinematicSkip:CINEMATIC_START(_, canBeCancelled)
	if IsShiftKeyDown() or not self.db.skip then return end
	if not (issecretvalue and issecretvalue(canBeCancelled)) and canBeCancelled == true then
		if StopCinematic then StopCinematic() end
		return
	end
	if IsInCinematicScene and CanCancelScene and CancelScene and IsInCinematicScene() and CanCancelScene() then
		CancelScene()
	end
end

-- What Yes on the movie's close dialog does: the frame's own OnMovieFinished handler with
-- userCanceled = true. The Forever client has no global MovieFrame_OnMovieFinished (EverlookQA,
-- 2026-11-05), so take the handler from the frame. Only a movie whose frame is up has started.
local function finishMovie()
	if not (MovieFrame and MovieFrame:IsShown()) then return end
	local finished = MovieFrame:GetScript("OnMovieFinished") or MovieFrame_OnMovieFinished
	if finished then finished(MovieFrame, true) end
end

function CinematicSkip:PLAY_MOVIE()
	if IsShiftKeyDown() or not self.db.skip then return end
	-- The movie frame shows itself on this same event; let it go first.
	C_Timer.After(0, finishMovie)
end
