-- The Performance page under /el: what Everlook.Schedule is doing right now, as a timing chart and a
-- task table, and how long the last loads took. Nothing is built until the page is first shown, and
-- it only reads while it's shown.
local Performance = Everlook:NewAddon("EverlookPerformance", {
	label = "Performance",
	defaults = {
		history = {}, -- the last loads, oldest first
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
-- C_AddOnProfiler is optional: the "Busiest addons now" line is hidden when the client lacks it.
EverlookQA:Expect("EverlookPerformance", {
	"CreateFrame",
	"GetFramerate",
}, {
	"C_AddOnProfiler.GetTopKAddOnsForMetric",
	"C_AddOnProfiler.GetApplicationMetric",
	"Enum.AddOnProfilerMetric.RecentAverageTime",
})

local MAX_HISTORY = 8
local REFRESH = 0.25 -- seconds between refreshes while the page is shown
local BARS = 60
local CHART_WIDTH, CHART_HEIGHT = 360, 56
local BAR_GAP = 1
local ROW_HEIGHT = 20
local TABLE_TOP = 176

local OVER = { 1, 0.4, 0.35 }
local UNDER = { 0.45, 0.85, 0.5 }

local NAMES = {
	defer = "Queued jobs",
	fonts = "Fonts",
	["upgrades.bags"] = "Upgrades in bags",
}

local STATES = {
	working = { "Working", 0.45, 0.85, 0.5 },
	idle = { "Idle", 0.55, 0.55, 0.55 },
	paused = { "Waiting for combat", 1, 0.82, 0.3 },
	sleeping = { "Sleeping", 0.55, 0.7, 0.9 },
	resting = { "Resting after errors", 1, 0.4, 0.35 },
}

local COLUMNS = {
	{ key = "name", label = "Task", x = 8, width = 150, justify = "LEFT" },
	{ key = "state", label = "State", x = 164, width = 140, justify = "LEFT" },
	{ key = "runs", label = "Runs", x = 310, width = 60, justify = "RIGHT" },
	{ key = "average", label = "Avg ms", x = 376, width = 60, justify = "RIGHT" },
	{ key = "worst", label = "Worst ms", x = 442, width = 66, justify = "RIGHT" },
	{ key = "errors", label = "Errors", x = 514, width = 56, justify = "RIGHT" },
}

-- Text ------------------------------------------------------------------------

local function number(value)
	value = math.floor(value * 100 + 0.5) / 100
	if value == math.floor(value) then return tostring(value) end
	return (string.format("%.2f", value):gsub("0+$", ""))
end

local function ms(value)
	return value and (number(value) .. " ms") or "not measured"
end

local function whole(value)
	return (tostring(math.floor(value + 0.5)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function find(trace, label)
	for _, mark in ipairs(trace.marks or {}) do
		if mark.label == label then return mark end
	end
end

local function between(trace, from, to)
	local a, b = find(trace, from), find(trace, to)
	if a and b and a.ms and b.ms then return b.ms - a.ms end
end

-- Whether EverlookOptimize actually held the garbage collector during this load: it marks the trace
-- when it does.
local function collectorHeld(trace)
	for _, mark in ipairs(trace.marks or {}) do
		if mark.label == "gc_hold" then return true end
	end
	return false
end

-- What a load took, from Everlook.Trace: { done, saved, modules, reload, kbSaved, kbDone, held, slowest }.
function Performance:Summarize(trace)
	local byAddon = {}
	local modules = 0
	for label, spent in pairs(trace.spans or {}) do
		local name = label:match("^%a+:(.+)$") or label
		byAddon[name] = (byAddon[name] or 0) + spent
		modules = modules + spent
	end
	local slowest = {}
	for name, spent in pairs(byAddon) do slowest[#slowest + 1] = { name = name, ms = spent } end
	table.sort(slowest, function(a, b) return a.ms > b.ms end)
	while #slowest > 3 do table.remove(slowest) end

	local saved, done = find(trace, "saved"), find(trace, "done")
	return {
		done = between(trace, "core", "done"),
		saved = between(trace, "core", "saved"),
		modules = modules,
		reload = trace.reload == true,
		kbSaved = saved and saved.kb,
		kbDone = done and done.kb,
		held = collectorHeld(trace),
		slowest = slowest,
	}
end

-- The "Busiest addons now" text, or nil when the client has no addon profiler.
local function busiest()
	local profiler = C_AddOnProfiler
	if not (profiler and profiler.GetTopKAddOnsForMetric and profiler.GetApplicationMetric and Enum and Enum.AddOnProfilerMetric) then
		return nil
	end
	local metric = Enum.AddOnProfilerMetric.RecentAverageTime
	local ok, results = pcall(profiler.GetTopKAddOnsForMetric, metric, 3)
	local app = ok and profiler.GetApplicationMetric(metric)
	if not (ok and type(results) == "table" and type(app) == "number" and app > 0) then return nil end
	local busy = {}
	for index, result in ipairs(results) do
		busy[index] = result.addOnName .. " " .. string.format("%.1f", result.metricValue / app * 100) .. "%"
	end
	return table.concat(busy, ", ")
end

-- The load summary as { label, value } lines.
function Performance:SummaryLines(summary, history)
	local lines = {}
	local function line(label, value) lines[#lines + 1] = { label, value } end

	line("Saved settings read", ms(summary.saved))
	local names = {}
	for index, entry in ipairs(summary.slowest or {}) do names[index] = entry.name .. " " .. number(entry.ms) end
	line("Addons starting", ms(summary.modules) .. (#names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))
	line("Loading screen ended", ms(summary.done))
	if summary.kbSaved and summary.kbDone then
		line("Lua memory", whole(summary.kbSaved) .. " KB at saved settings, " .. whole(summary.kbDone) .. " KB when loaded")
	end
	line("Collector held", summary.held and "yes" or "no")

	local loads = {}
	for _, entry in ipairs(history or {}) do
		if entry.done then loads[#loads + 1] = whole(entry.done) .. (entry.reload and " (reload)" or "") end
	end
	if #loads > 0 then line("Recent loads, in ms", table.concat(loads, ", ")) end

	local busy = busiest()
	if busy then line("Busiest addons now", busy) end
	return lines
end

-- The chart: BARS entries, newest on the right, each { height, over } or false for no frame yet.
-- Twice the budget fills the chart, so a frame inside the budget is at most half height.
function Performance:Bars(snapshot, height)
	local frames, budget = snapshot.frames, snapshot.budget
	local scale = height / (budget * 2)
	local bars = {}
	for index = 1, BARS do
		local used = frames[#frames - BARS + index]
		if used then
			bars[index] = { height = math.min(height, math.max(1, used * scale)), over = used > budget }
		else
			bars[index] = false
		end
	end
	return bars
end

function Performance:Header(snapshot)
	local fps = snapshot.fps and snapshot.fps > 0 and string.format("%d fps", snapshot.fps + 0.5) or "fps unknown"
	local text = "Budget " .. number(snapshot.budget) .. " ms · " .. fps
	if snapshot.combat then text = text .. " · combat pauses tasks" end
	if snapshot.queued and snapshot.queued > 0 then text = text .. " · " .. snapshot.queued .. " jobs queued" end
	return text
end

-- History ----------------------------------------------------------------------

function Performance:Remember(summary)
	local history = self.db.history
	history[#history + 1] = {
		done = summary.done, reload = summary.reload, saved = summary.saved,
		modules = summary.modules, kb = summary.kbDone, held = summary.held,
	}
	while #history > MAX_HISTORY do table.remove(history, 1) end
end

-- The page ----------------------------------------------------------------------

local built
local bars, rows, texts = {}, {}, {}
local summaryLines = {}

local function fontString(panel, template, justify, width)
	local line = panel:CreateFontString(nil, "OVERLAY", template)
	if width then line:SetWidth(width) end
	line:SetJustifyH(justify or "LEFT")
	return line
end

local function rowAt(panel, index)
	if rows[index] then return rows[index] end
	local row = {}
	for _, column in ipairs(COLUMNS) do
		local line = fontString(panel, "GameFontHighlight", column.justify, column.width)
		line:SetPoint("TOPLEFT", column.x, -(TABLE_TOP + index * ROW_HEIGHT))
		row[column.key] = line
	end
	rows[index] = row
	return row
end

local function build(panel)
	local heading = fontString(panel, "GameFontNormalHuge")
	heading:SetPoint("TOPLEFT", 8, -8)
	heading:SetText("Performance")

	texts.header = fontString(panel, "GameFontDisable")
	texts.header:SetPoint("TOPLEFT", 8, -40)

	local chartLabel = fontString(panel, "GameFontNormal")
	chartLabel:SetPoint("TOPLEFT", 8, -68)
	chartLabel:SetText("Time spent in recent frames that had background work")

	local chart = CreateFrame("Frame", nil, panel)
	chart:SetPoint("TOPLEFT", 8, -88)
	chart:SetSize(CHART_WIDTH, CHART_HEIGHT)
	local floor = chart:CreateTexture(nil, "BACKGROUND")
	floor:SetAllPoints()
	floor:SetColorTexture(1, 1, 1, 0.05)
	-- Half the chart is the budget.
	local budgetLine = chart:CreateTexture(nil, "ARTWORK")
	budgetLine:SetPoint("LEFT", chart, "BOTTOMLEFT", 0, CHART_HEIGHT / 2)
	budgetLine:SetPoint("RIGHT", chart, "BOTTOMRIGHT", 0, CHART_HEIGHT / 2)
	budgetLine:SetHeight(1)
	budgetLine:SetColorTexture(1, 0.82, 0.3, 0.6)
	texts.budgetLine = budgetLine
	local budgetLabel = fontString(panel, "GameFontDisable")
	budgetLabel:SetPoint("LEFT", chart, "RIGHT", 8, 0)
	budgetLabel:SetText("Budget")

	local width = (CHART_WIDTH - BAR_GAP * (BARS - 1)) / BARS
	for index = 1, BARS do
		local bar = chart:CreateTexture(nil, "OVERLAY")
		bar:SetPoint("BOTTOMLEFT", (index - 1) * (width + BAR_GAP), 0)
		bar:SetWidth(width)
		bar:SetHeight(1)
		bar:Hide()
		bars[index] = bar
	end

	for _, column in ipairs(COLUMNS) do
		local label = fontString(panel, "GameFontNormal", column.justify, column.width)
		label:SetPoint("TOPLEFT", column.x, -TABLE_TOP)
		label:SetText(column.label)
	end

	local last = fontString(panel, "GameFontNormal")
	last:SetPoint("TOPLEFT", 8, -(TABLE_TOP + 6 * ROW_HEIGHT + 24))
	last:SetText("The last time the game loaded")
	texts.summaryAnchor = last

	local note = fontString(panel, "GameFontDisable")
	note:SetPoint("BOTTOMLEFT", 8, 8)
	note:SetText("Work that can wait is queued and done a little each frame. Most of it stops in combat.")
	built = true
end

local function summaryLineAt(panel, index)
	if summaryLines[index] then return summaryLines[index] end
	local label = fontString(panel, "GameFontDisable", "LEFT", 160)
	label:SetPoint("TOPLEFT", texts.summaryAnchor, "BOTTOMLEFT", 0, -6 - (index - 1) * 16)
	local value = fontString(panel, "GameFontHighlight", "LEFT")
	value:SetPoint("LEFT", label, "RIGHT", 8, 0)
	summaryLines[index] = { label = label, value = value }
	return summaryLines[index]
end

function Performance:Refresh()
	if not built then return end
	local panel = self.page
	local snapshot = Everlook.Schedule.Snapshot()
	texts.header:SetText(self:Header(snapshot))

	for index, bar in ipairs(self:Bars(snapshot, CHART_HEIGHT)) do
		local texture = bars[index]
		if bar then
			local color = bar.over and OVER or UNDER
			texture:SetHeight(bar.height)
			texture:SetColorTexture(color[1], color[2], color[3], 0.9)
			texture:Show()
		else
			texture:Hide()
		end
	end

	for index, name in ipairs(snapshot.order) do
		local task = snapshot.tasks[name]
		local row = rowAt(panel, index)
		local state = STATES[task.state] or STATES.idle
		row.name:SetText(NAMES[name] or name)
		row.state:SetText(state[1])
		row.state:SetTextColor(state[2], state[3], state[4])
		row.runs:SetText(tostring(task.runs))
		row.average:SetText(task.runs > 0 and number(task.ms / task.runs) or "0")
		row.worst:SetText(number(task.worst))
		row.errors:SetText(tostring(task.errors))
		if task.errors > 0 then
			row.errors:SetTextColor(1, 0.4, 0.35)
		else
			row.errors:SetTextColor(0.55, 0.55, 0.55)
		end
		for _, line in pairs(row) do line:Show() end
	end
	for index = #snapshot.order + 1, #rows do
		for _, line in pairs(rows[index]) do line:Hide() end
	end

	local lines = self:SummaryLines(self:Summarize(Everlook.Trace), self.db.history)
	for index, entry in ipairs(lines) do
		local line = summaryLineAt(panel, index)
		line.label:SetText(entry[1])
		line.value:SetText(entry[2])
		line.label:Show()
		line.value:Show()
	end
	for index = #lines + 1, #summaryLines do
		summaryLines[index].label:Hide()
		summaryLines[index].value:Hide()
	end
end

function Performance:IsBuilt()
	return built == true
end

function Performance:OnInitialize()
	local panel = CreateFrame("Frame", "EverlookPerformancePage")
	panel:Hide()
	self.page = panel
	local waited = 0
	panel:SetScript("OnShow", function(frame)
		if not built then build(frame) end
		waited = 0
		self:Refresh()
		frame:SetScript("OnUpdate", function(_, elapsed)
			waited = waited + elapsed
			if waited >= REFRESH then
				waited = 0
				self:Refresh()
			end
		end)
	end)
	-- Nothing reads the scheduler while the page is closed.
	panel:SetScript("OnHide", function(frame) frame:SetScript("OnUpdate", nil) end)
	self.category = EverlookPreferences:NewCanvasPage(self, panel, nil, "Developer")
end

function Performance:OnEnable()
	-- The core marks the end of the loading screen before this runs, so the trace is complete.
	self:RegisterEvent("LOADING_SCREEN_DISABLED", function()
		self:UnregisterEvent("LOADING_SCREEN_DISABLED")
		self:Remember(self:Summarize(Everlook.Trace))
	end)
end
