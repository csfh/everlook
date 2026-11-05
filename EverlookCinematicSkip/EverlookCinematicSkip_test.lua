local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has

t.out("EverlookCinematicSkip")

local inScene, canCancelScene = false, false
StopCinematic = function() t.log("StopCinematic") end
IsInCinematicScene = function() return inScene end
CanCancelScene = function() return canCancelScene end
CancelScene = function() t.log("CancelScene") end
-- As on the Forever client: the handler is on the frame, with no global MovieFrame_OnMovieFinished.
MovieFrame = t.widget("MovieFrame")
MovieFrame:SetScript("OnMovieFinished", function(frame, userCanceled)
	t.log("movie finished " .. tostring(frame == MovieFrame) .. " " .. tostring(userCanceled))
end)

t.load("EverlookCinematicSkip")
t.fire("PLAYER_LOGIN")
local C = Everlook:GetAddon("EverlookCinematicSkip")
local function fire(...) t.reset() t.fire(...) end

check(C.db.skip, "skipping starts on")

fire("CINEMATIC_START", true)
check(has("StopCinematic"), "stops a cinematic you may skip")

inScene, canCancelScene = true, true
fire("CINEMATIC_START", false)
check(has("CancelScene") and not has("StopCinematic"), "cancels a cinematic scene")

inScene, canCancelScene = false, false
fire("CINEMATIC_START", false)
check(#t.calls == 0, "a vehicle cinematic keeps playing")

MovieFrame:Show()
fire("PLAY_MOVIE", 1)
check(has("movie finished true true"), "closes a movie through the frame's own handler, as if the player cancelled")
MovieFrame:Hide()
fire("PLAY_MOVIE", 1)
check(#t.calls == 0, "leaves a movie whose frame isn't up")

t.shift = true
MovieFrame:Show()
fire("CINEMATIC_START", true)
t.fire("PLAY_MOVIE", 1)
check(#t.calls == 0, "Shift leaves it playing")
t.shift = false

C.db.skip = false
fire("CINEMATIC_START", true)
t.fire("PLAY_MOVIE", 1)
check(#t.calls == 0, "off means off")

t.done()
