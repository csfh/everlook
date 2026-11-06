local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookPerformance")

-- Widget methods the page uses beyond the stubs.
function t.Widget:SetColorTexture(r, g, b) self.color = { r, g, b } end
function t.Widget:SetHeight(height) self.height = height end
function t.Widget:SetWidth(width) self.width = width end
function t.Widget:SetAllPoints() end
function t.Widget:SetJustifyH() end

local canvas
Settings.RegisterCanvasLayoutSubcategory = function(_, frame, name)
	canvas = { frame = frame, name = name }
	return canvas
end

t.load("EverlookPerformance")
t.fire("PLAYER_LOGIN")
local P = Everlook:GetAddon("EverlookPerformance")

check(canvas and canvas.name == "Performance" and canvas.frame == P.page, "the page is a canvas page under Everlook")
check(not P:IsBuilt() and not P.page:IsShown(), "nothing is built before the page is first shown")

-- Chart bars.
local frames = {}
for i = 1, 70 do frames[i] = 0.5 end
frames[70] = 2 -- over the 1.5 ms budget
frames[69] = 10 -- far over: clamped to the top
local bars = P:Bars({ frames = frames, budget = 1.5 }, 60)
check(#bars == 60, "60 bars")
check(bars[60].over and bars[60].height == 40, "a frame over budget is red, scaled so 2× budget is full height")
check(bars[59].over and bars[59].height == 60, "and a big one is clamped to the top")
check(not bars[1].over and bars[1].height == 10, "a frame inside the budget is green")
local few = P:Bars({ frames = { 0.001, 1 }, budget = 1.5 }, 60)
check(few[58] == false and few[59].height == 1 and few[60].height == 20, "missing frames are empty; a tiny one is at least 1 px")

-- Header.
check(P:Header({ budget = 1.5, fps = 59.6, combat = false, queued = 0 }) == "Budget 1.5 ms · 60 fps", "header shows budget and fps")
check(P:Header({ budget = 0.75, fps = 25, combat = true, queued = 3 }):find("combat pauses tasks", 1, true)
	and P:Header({ budget = 0.75, fps = 25, combat = true, queued = 3 }):find("3 jobs queued", 1, true),
	"and says when combat pauses tasks and jobs are queued")

-- Summary from a fake trace.
local trace = {
	marks = {
		{ label = "core", ms = 100, kb = 1000 },
		{ label = "saved", ms = 112.5, kb = 1500 },
		{ label = "done", ms = 1400, kb = 23456 },
	},
	spans = { ["init:A"] = 2, ["enable:A"] = 1, ["init:B"] = 5, ["init:C"] = 0.5, ["init:D"] = 0.25 },
	reload = true,
}
local summary = P:Summarize(trace)
check(summary.saved == 12.5 and summary.done == 1300 and summary.modules == 8.75 and summary.reload,
	"summary: saved settings, loading screen and addon start times")
check(summary.slowest[1].name == "B" and summary.slowest[2].name == "A" and summary.slowest[2].ms == 3
	and #summary.slowest == 3, "the 3 slowest addons, init and enable added together")

local lines = P:SummaryLines(summary, { { done = 980, reload = false }, { done = 1300, reload = true } })
local byLabel = {}
for _, line in ipairs(lines) do byLabel[line[1]] = line[2] end
check(byLabel["Saved settings read"] == "12.5 ms" and byLabel["Loading screen ended"] == "1300 ms", "summary lines in ms")
check(byLabel["Addons starting"] == "8.75 ms (B 5, A 3, C 0.5)", "addons starting names the slowest")
check(byLabel["Lua memory"] == "1,500 KB at saved settings, 23,456 KB when loaded", "Lua memory")
check(byLabel["Collector held"] == "no", "collector held")
table.insert(trace.marks, 2, { label = "gc_hold", ms = 101, kb = 1100 })
check(P:Summarize(trace).held == true, "collector held is yes when EverlookOptimize marked the trace")
table.remove(trace.marks, 2)
check(byLabel["Recent loads, in ms"] == "980, 1,300 (reload)", "recent loads, reloads tagged")
check(byLabel["Busiest addons now"] == nil, "busiest addons is hidden without the profiler")

C_AddOnProfiler = {
	GetTopKAddOnsForMetric = function() return { { addOnName = "Everlook", metricValue = 2 } } end,
	GetApplicationMetric = function() return 8 end,
}
Enum = { AddOnProfilerMetric = { RecentAverageTime = 1 } }
for _, line in ipairs(P:SummaryLines(summary, {})) do byLabel[line[1]] = line[2] end
check(byLabel["Busiest addons now"] == "Everlook 25.0%", "busiest addons from the profiler")
C_AddOnProfiler = nil

-- History is saved on the first end of a loading screen and capped at 8.
Everlook.Trace.marks[#Everlook.Trace.marks + 1] = { label = "done", ms = (Everlook.Trace.marks[1].ms or 0) + 900, kb = 1 }
t.fire("LOADING_SCREEN_DISABLED")
check(#P.db.history == 1 and P.db.history[1].done == 900, "the load is saved when the loading screen ends")
t.fire("LOADING_SCREEN_DISABLED")
check(#P.db.history == 1, "only the first loading screen counts")
for i = 1, 10 do P:Remember({ done = i, reload = i % 2 == 0 }) end
check(#P.db.history == 8 and P.db.history[1].done == 3 and P.db.history[8].done == 10, "history keeps the last 8")

-- The page.
local task = Everlook.Schedule.Task("demo", { step = function() t.ms = t.ms + 2 return false end })
task:Wake()
Everlook.Schedule.Tick()
P.page:Show()
P.page.scripts.OnShow(P.page)
check(P:IsBuilt() and P.page.scripts.OnUpdate ~= nil, "showing the page builds it and starts refreshing")
P.page.scripts.OnUpdate(P.page, 0.3)
check(true, "a refresh while shown runs without errors")
P.page:Hide()
P.page.scripts.OnHide(P.page)
check(P.page.scripts.OnUpdate == nil, "hiding the page stops refreshing")

-- Hitches: a long frame is saved with what was going on.
local H = P.hitchFrame
check(H and H.allEvents and H.scripts.OnUpdate, "a frame counts every event and times every frame")
check(P.db.session == 1 and #P.db.hitches == 0, "a new session, nothing recorded yet")
Enum = { AddOnProfilerMetric = { LastTime = 3, CountTimeOver100Ms = 9, CountTimeOver500Ms = 10 } }
local profilerCalls = 0
C_AddOnProfiler = {
	GetOverallMetric = function(m) profilerCalls = profilerCalls + 1 return m == 3 and 480 or 2 end,
	GetApplicationMetric = function(m) return m == 3 and 510 or 4 end,
	GetTopKAddOnsForMetric = function() return { { addOnName = "EverlookUpgrades", metricValue = 470 } } end,
}
GetRealZoneText = function() return "Elwynn Forest" end
local heap = 100000
collectgarbage = function(what) return what == "count" and heap or 0 end
local function frame(seconds) H.scripts.OnUpdate(H, seconds) end
local function event(name) H.scripts.OnEvent(H, name) end

frame(0.016)
for _ = 1, 3 do event("BAG_UPDATE") end
event("UNIT_AURA")
heap = 60000 -- a collection cycle finished
t.now = 100
frame(0.52)
local hitch = P.db.hitches[1]
check(#P.db.hitches == 1 and hitch.ms == 520 and hitch.frames == 1, "a 520 ms frame is recorded")
check(hitch.events[1] == "BAG_UPDATE x3" and hitch.events[2] == "UNIT_AURA x1", "with the events before it, busiest first")
check(hitch.kbBefore == 100000 and hitch.kbAfter == 60000, "and the heap before and after, which shows a collection")
check(hitch.profiler.addons == 480 and hitch.profiler.game == 510 and hitch.profiler.top[1] == "EverlookUpgrades 470.0",
	"and the game's profiler: addon time, game time, the busiest addon")
check(hitch.zone == "Elwynn Forest" and hitch.combat == false and hitch.session == 1, "and where you were")
frame(0.3)
check(#P.db.hitches == 1 and hitch.frames == 2 and hitch.ms == 820, "a long frame right after is merged into the same entry")
frame(0.016)
check(hitch.nextFrame and hitch.nextFrame.addons == 480, "the profiler is read again a frame later")
event("BAG_UPDATE")
frame(0.016)
check(#P.db.hitches == 1, "normal frames aren't recorded")

t.now = 160
frame(0.25)
check(#P.db.hitches == 2 and P.db.hitches[2].sincePrevious == 60 and #P.db.hitches[2].events == 0,
	"the next hitch says how long since the last; events are counted per frame")

event("LOADING_SCREEN_ENABLED")
frame(3)
event("LOADING_SCREEN_DISABLED")
t.now = 162
frame(1)
check(#P.db.hitches == 2, "loading screens, and a few seconds after, aren't hitches")
t.now = 170
frame(0.016)
for i = 1, 60 do t.now = t.now + 10 frame(0.3) frame(0.016) end
check(#P.db.hitches == 50 and P.db.hitches[50].ms == 300, "only the last 50 are kept")

t.done()
