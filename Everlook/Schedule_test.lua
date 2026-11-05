local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, has = t.check, t.has
local Schedule = Everlook.Schedule

t.out("Everlook.Schedule")

local driver
local createFrame = CreateFrame
CreateFrame = function(...)
	local frame = createFrame(...)
	driver = driver or frame
	return frame
end

check(Schedule.Budget() == 1.5, "budget is 1.5 ms a frame")
t.fps = 25
check(Schedule.Budget() == 0.75, "and 0.75 ms below 30 fps")
t.fps = 60

-- A task that spends 0.5 ms per unit of work and has `units` to do.
local function worker(name, units, combat)
	local log = { done = 0, limits = {} }
	log.task = Schedule.Task(name, {
		combat = combat,
		step = function(limit)
			log.limits[#log.limits + 1] = limit
			local began = debugprofilestop()
			while log.done < units do
				log.done = log.done + 1
				t.ms = t.ms + 0.5
				if debugprofilestop() - began >= limit then break end
			end
			return log.done < units
		end,
	})
	return log
end

-- Budget is shared and work spreads over frames.
local a = worker("a", 12)
a.task:Wake()
local frames = t.runSchedule()
check(a.done == 12 and frames == 4, "12 × 0.5 ms of work takes 4 frames at 1.5 ms each")
check(a.limits[1] == 1.5, "a lone task gets the whole budget")
local snap = Schedule.Snapshot()
check(snap.tasks.a.state == "idle" and snap.tasks.a.runs == 4, "a finished task goes idle, with its runs counted")
check(#snap.frames == 4 and snap.frames[1] >= 1.5, "each frame's time is recorded")

local b, c = worker("b", 100), worker("c", 100)
b.task:Wake(); c.task:Wake()
Schedule.Tick()
check(b.limits[1] == 0.75 or c.limits[1] == 0.75, "two tasks split the budget")
Schedule.Tick()
check(#b.limits == 2 and #c.limits == 2, "and both run every frame")
local firstB = b.limits[1] == 0.75
check((b.limits[2] == 0.75) ~= firstB, "the task that goes first rotates")
b.task:Stop(); c.task:Stop()

-- Combat.
local paused = worker("paused", 10)
local running = worker("running", 10, "run")
paused.task:Wake(); running.task:Wake()
t.combat = true
Schedule.Tick()
check(paused.done == 0 and running.done > 0, "combat pauses tasks unless they ask to run")
check(Schedule.Snapshot().tasks.paused.state == "paused", "and the snapshot says so")
t.combat = false
t.runSchedule()
check(paused.done == 10, "paused work carries on after combat")

-- Sleeping and errors.
local naps = 0
local sleeper = Schedule.Task("sleeper", { step = function() naps = naps + 1 return naps < 2 and 10 or false end })
sleeper:Wake()
Schedule.Tick()
check(Schedule.Snapshot().tasks.sleeper.state == "sleeping", "a number sleeps that many seconds")
Schedule.Tick()
check(naps == 1, "and it doesn't run while asleep")
t.now = t.now + 10
Schedule.Tick()
check(naps == 2 and Schedule.Snapshot().tasks.sleeper.state == "idle", "it wakes when the time is up")

t.reset()
local broken = Schedule.Task("broken", { step = function() error("boom") end })
broken:Wake()
Schedule.Tick(); Schedule.Tick(); Schedule.Tick()
local state = Schedule.Snapshot().tasks.broken
check(state.errors == 3 and state.state == "resting", "three errors in a row rest a task")
check(#t.calls == 1 and t.printed("boom"), "the first error is reported")
Schedule.Tick()
check(Schedule.Snapshot().tasks.broken.errors == 3, "a resting task doesn't run")
t.now = t.now + 5
Schedule.Tick(); Schedule.Tick(); Schedule.Tick()
check(Schedule.Snapshot().tasks.broken.errors == 6 and #t.calls == 1,
	"after its rest it fails again without another popup")
broken:Stop()

-- Defer.
local ran = {}
Schedule.Defer("same", function() ran[#ran + 1] = "first" end)
Schedule.Defer("same", function() ran[#ran + 1] = "second" end)
Schedule.Defer(nil, function() ran[#ran + 1] = "other" end)
t.runSchedule()
check(#ran == 2 and ran[1] == "second" and ran[2] == "other", "a newer job replaces a waiting one under the same key")

for i = 1, 2005 do Schedule.Defer(nil, function() end) end
check(Schedule.Snapshot().queued == 2000 and Schedule.Snapshot().dropped == 5, "the queue holds 2000 jobs, dropping the oldest")
t.runSchedule()
check(Schedule.Snapshot().queued == 0, "and empties over frames")

-- The driver stops when nothing is awake.
Schedule.Tick()
local driverFrames = 0
for _, task in pairs(Schedule.Snapshot().tasks) do
	if task.state ~= "idle" then driverFrames = driverFrames + 1 end
end
check(driverFrames == 0, "nothing is left awake")
check(driver ~= nil and driver:GetScript("OnUpdate") == nil, "and the driver frame stops running every frame")

-- History holds 60 frames.
local long = worker("long", 1000)
long.task:Wake()
for _ = 1, 80 do Schedule.Tick() end
check(#Schedule.Snapshot().frames == 60, "the frame history holds the last 60")
long.task:Stop()

-- Load trace.
check(Everlook.Trace.Find("core") and Everlook.Trace.Find("saved"), "the trace marks the core files and saved settings")
t.fire("PLAYER_ENTERING_WORLD", false, true)
t.fire("LOADING_SCREEN_DISABLED")
check(Everlook.Trace.reload == true and Everlook.Trace.Find("enter") and Everlook.Trace.Find("done"),
	"and entering the world and the end of the loading screen")
check(Everlook.Trace.spans["init:EverlookQA"] ~= nil, "and how long each addon took to start")

t.done()
