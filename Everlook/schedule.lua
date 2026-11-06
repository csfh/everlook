-- Background work on a per-frame time budget, so no addon ever makes the game hitch.
--
--   local task = Everlook.Schedule.Task("name", {
--       step = function(limitMs) ... end, -- true: more work; false/nil: done; a number: sleep that many seconds
--       combat = "pause",                 -- the default; "run" keeps going in combat
--   })
--   task:Wake()   -- start, or start again after it finished
--   task:Stop()
--
--   Everlook.Schedule.Defer("key", fn)  -- one-shot; a newer job under the same key replaces a waiting one
--
-- Every frame the budget is shared between the tasks that have work: each gets what is left divided
-- by the tasks still to run, and the first task rotates so none starves. A step should do a slice of
-- work, check how long it has taken, and return before its limit.
local Schedule = {}
Everlook.Schedule = Schedule

local BUDGET_MS = 1.5
local SLOW_BUDGET_MS = 0.75 -- below SLOW_FPS the game has less to spare
local SLOW_FPS = 30
local MAX_ERRORS = 3 -- errors in a row before a task rests
local ERROR_REST = 5 -- seconds
local MAX_JOBS = 2000
local HISTORY = 60 -- frames kept for the Performance chart

local tasks, order = {}, {}
local history = {}
local turn = 0
local driver

local function clock() return debugprofilestop and debugprofilestop() end

function Schedule.Budget()
	local fps = GetFramerate and GetFramerate() or 0
	if fps > 0 and fps < SLOW_FPS then return SLOW_BUDGET_MS end
	return BUDGET_MS
end

local function anyAwake()
	for _, name in ipairs(order) do
		if tasks[name].awake then return true end
	end
	return false
end

local Task = {}
Task.__index = Task

function Task:Wake()
	self.awake, self.sleepUntil, self.resting = true, 0, false
	if not driver then driver = CreateFrame("Frame") end
	driver:SetScript("OnUpdate", Schedule.Tick)
end

function Task:Stop()
	self.awake = false
end

-- A task with this name already there keeps its stats and takes the new step.
function Schedule.Task(name, options)
	local task = tasks[name]
	if not task then
		task = setmetatable({ name = name, awake = false, sleepUntil = 0, runs = 0, ms = 0, worst = 0, errors = 0, streak = 0 }, Task)
		tasks[name] = task
		order[#order + 1] = name
	end
	task.step = options.step
	task.combat = options.combat or "pause"
	return task
end

local function report(message)
	local handler = geterrorhandler and geterrorhandler()
	if handler then pcall(handler, message) end
end

local function runStep(task, limit, now)
	local began = clock()
	local ok, result = pcall(task.step, limit)
	local spent = began and (clock() - began) or 0
	task.runs = task.runs + 1
	task.ms = task.ms + spent
	if spent > task.worst then task.worst = spent end

	if not ok then
		task.errors = task.errors + 1
		task.streak = task.streak + 1
		-- Only a task's first error pops up; the rest are counted on the Performance page.
		if task.errors == 1 then report(result) end
		if task.streak >= MAX_ERRORS then
			task.sleepUntil, task.resting, task.streak = now + ERROR_REST, true, 0
		end
		return
	end
	task.streak, task.resting = 0, false
	if result == true then
		return
	elseif type(result) == "number" then
		task.sleepUntil = now + result
	else
		task.awake = false
	end
end

local function remember(ms)
	history[#history + 1] = ms
	if #history > HISTORY then table.remove(history, 1) end
end

-- One frame's worth of work. The driver frame calls this from OnUpdate while any task is awake.
function Schedule.Tick()
	local now = GetTime()
	local combat = InCombatLockdown()
	local ready = {}
	local count = #order
	if count > 0 then
		turn = turn % count + 1
		for i = 0, count - 1 do
			local task = tasks[order[(turn + i - 1) % count + 1]]
			if task.awake and task.sleepUntil <= now and not (combat and task.combat == "pause") then
				ready[#ready + 1] = task
			end
		end
	end
	if #ready == 0 then
		if driver and not anyAwake() then driver:SetScript("OnUpdate", nil) end
		return
	end

	local budget = Schedule.Budget()
	local began = clock()
	for i, task in ipairs(ready) do
		local remaining = budget - (began and (clock() - began) or 0)
		if began and remaining <= 0 then break end
		runStep(task, remaining / (#ready - i + 1), now)
	end
	if began then remember(clock() - began) end
end

-- One-shot jobs --------------------------------------------------------------

local jobs, waiting = {}, {} -- queue of { key, fn }; waiting[key] = job
local dropped = 0

local deferred = Schedule.Task("defer", {
	step = function(limit)
		local began = clock()
		while #jobs > 0 do
			local job = table.remove(jobs, 1)
			if job.key then waiting[job.key] = nil end
			local ok, message = pcall(job.fn)
			if not ok then report(message) end
			-- Without a clock, one job per frame.
			if not began or clock() - began >= limit then return #jobs > 0 end
		end
		return false
	end,
})

function Schedule.Defer(key, fn)
	local job = key and waiting[key]
	if job then
		job.fn = fn
	else
		job = { key = key, fn = fn }
		jobs[#jobs + 1] = job
		if key then waiting[key] = job end
		if #jobs > MAX_JOBS then
			local oldest = table.remove(jobs, 1)
			if oldest.key then waiting[oldest.key] = nil end
			dropped = dropped + 1
		end
	end
	deferred:Wake()
end

-- What the Performance page shows. Cheap enough to ask for several times a second.
function Schedule.Snapshot()
	local now, combat = GetTime(), InCombatLockdown()
	local snapshot = {
		budget = Schedule.Budget(),
		fps = GetFramerate and GetFramerate() or nil,
		combat = combat,
		queued = #jobs,
		dropped = dropped,
		frames = {},
		order = {},
		tasks = {},
	}
	for i, ms in ipairs(history) do snapshot.frames[i] = ms end
	for i, name in ipairs(order) do
		local task = tasks[name]
		local state = "idle"
		if task.awake then
			if task.resting then state = "resting"
			elseif task.sleepUntil > now then state = "sleeping"
			elseif combat and task.combat == "pause" then state = "paused"
			else state = "working" end
		end
		snapshot.order[i] = name
		snapshot.tasks[name] = { state = state, runs = task.runs, ms = task.ms, worst = task.worst, errors = task.errors }
	end
	return snapshot
end
