-- Hitch recorder: every frame that takes 200 ms or more is saved to EverlookDB.EverlookPerformance.hitches
-- (the last 50, across sessions), with what was going on, so a stutter can be traced after a reload.
-- The question each entry answers: was the time spent in addon Lua (and which addon), in Lua's garbage
-- collector, or in the game itself? Per frame it only reads the heap size and counts events, into a
-- table it reuses; an entry is built only when a frame is long.
local Performance = Everlook:GetAddon("EverlookPerformance")

local THRESHOLD = 0.2 -- seconds
local SETTLE = 5 -- seconds after a loading screen ends before frames count
local MAX_HITCHES = 50
local TOP_EVENTS = 12
local TOP_ADDONS = 5

local counts = {} -- [event] = times it fired since the last frame; reset to 0, never replaced
local loading, settleUntil = false, 0
local lastKB
local current -- the entry a run of long frames is merged into
local followUp -- the entry whose profiler figures are read again on the next frame
local lastHitchAt

local function metric(name)
	return Enum and Enum.AddOnProfilerMetric and Enum.AddOnProfilerMetric[name]
end

-- The game's own addon profiler: ms in the most recent tick for all addons, for the whole game, and
-- the busiest addons; plus how many ticks so far went over 100 and 500 ms.
local function profile()
	local profiler = C_AddOnProfiler
	local last = metric("LastTime")
	if not (profiler and profiler.GetOverallMetric and last) then return nil end
	local out = {}
	pcall(function()
		out.addons = profiler.GetOverallMetric(last)
		out.game = profiler.GetApplicationMetric(last)
		out.addonsOver100, out.gameOver100 = profiler.GetOverallMetric(metric("CountTimeOver100Ms")), profiler.GetApplicationMetric(metric("CountTimeOver100Ms"))
		out.addonsOver500, out.gameOver500 = profiler.GetOverallMetric(metric("CountTimeOver500Ms")), profiler.GetApplicationMetric(metric("CountTimeOver500Ms"))
		out.top = {}
		for _, result in ipairs(profiler.GetTopKAddOnsForMetric(last, TOP_ADDONS) or {}) do
			out.top[#out.top + 1] = string.format("%s %.1f", result.addOnName, result.metricValue)
		end
	end)
	return out
end

-- The busiest events since the last frame, as "EVENT xN", most first.
local function topEvents()
	local list = {}
	for event, count in pairs(counts) do
		if count > 0 then list[#list + 1] = { event, count } end
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	local out = {}
	for i = 1, math.min(#list, TOP_EVENTS) do
		out[i] = list[i][1] .. " x" .. list[i][2]
	end
	return out
end

local function context(entry)
	pcall(function()
		entry.zone = GetRealZoneText and GetRealZoneText()
		entry.subzone = GetSubZoneText and GetSubZoneText()
		entry.instance = IsInInstance and IsInInstance() or false
		entry.combat = InCombatLockdown() or false
		entry.taxi = UnitOnTaxi and UnitOnTaxi("player") or false
		entry.mounted = IsMounted and IsMounted() or false
		entry.flying = IsFlying and IsFlying() or false
		entry.speed = GetUnitSpeed and GetUnitSpeed("player")
		entry.fps = GetFramerate and GetFramerate()
		local frames = Everlook.Schedule.Snapshot().frames
		entry.everlookMs = frames[#frames] -- Everlook's scheduled work in its last frame
	end)
end

function Performance:RecordFrame(elapsed)
	local kb = collectgarbage("count")
	if followUp then
		followUp.nextFrame = profile()
		followUp = nil
	end
	local now = GetTime()
	if elapsed >= THRESHOLD and not loading and now >= settleUntil then
		if current then
			current.frames = current.frames + 1
			current.ms = current.ms + math.floor(elapsed * 1000 + 0.5)
			current.kbAfter = kb
		else
			current = {
				session = self.db.session,
				time = date and date("%Y-%m-%d %H:%M:%S"),
				ms = math.floor(elapsed * 1000 + 0.5),
				frames = 1,
				sincePrevious = lastHitchAt and math.floor(now - lastHitchAt + 0.5) or nil,
				-- A heap that shrank over the frame means a garbage collection cycle finished in it.
				kbBefore = lastKB and math.floor(lastKB), kbAfter = math.floor(kb),
				events = topEvents(),
				profiler = profile(),
			}
			context(current)
			local hitches = self.db.hitches
			hitches[#hitches + 1] = current
			while #hitches > MAX_HITCHES do table.remove(hitches, 1) end
			followUp = current
		end
		current.kbAfter = math.floor(kb)
		lastHitchAt = now
	else
		current = nil
	end
	lastKB = kb
	for event in pairs(counts) do counts[event] = 0 end
end

function Performance:StartHitches()
	self.db.session = (self.db.session or 0) + 1
	local frame = CreateFrame("Frame")
	self.hitchFrame = frame
	frame:RegisterAllEvents()
	frame:SetScript("OnEvent", function(_, event)
		counts[event] = (counts[event] or 0) + 1
		if event == "LOADING_SCREEN_ENABLED" then
			loading = true
		elseif event == "LOADING_SCREEN_DISABLED" then
			loading, settleUntil = false, GetTime() + SETTLE
		end
	end)
	frame:SetScript("OnUpdate", function(_, elapsed) self:RecordFrame(elapsed) end)
end
