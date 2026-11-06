-- Test world for Everlook addons: stand-ins for the game API that Everlook and EverlookQA need.
-- For the offline *_test.lua files only. Never list this in a TOC: it replaces game globals.
--
--   local dir = arg[0]:match("^(.*)/[^/]+$") or "."
--   local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
--   -- set the globals your addon uses, then:
--   t.load("MyAddon"); t.fire("PLAYER_LOGIN")

-- Inside the game the real CreateFrame exists; refuse to replace it.
if CreateFrame then
	error("EverlookQA/stubs.lua is for offline tests and must not load in the game")
end

return function(root)
	local t = { calls = {}, shift = false, combat = false, tickers = {} }

	function t.log(entry) t.calls[#t.calls + 1] = entry end
	function t.reset() t.calls = {} end

	function t.has(entry)
		for _, call in ipairs(t.calls) do
			if call == entry then return true end
		end
		return false
	end

	-- Substring match, for chat lines that carry color codes.
	function t.printed(text)
		for _, call in ipairs(t.calls) do
			if call:find(text, 1, true) then return true end
		end
		return false
	end

	local failures = 0
	function t.check(ok, name)
		if ok then
			t.out("  ok   " .. name)
		else
			failures = failures + 1
			t.out("  FAIL " .. name)
		end
	end

	function t.done()
		if failures > 0 then
			t.out(failures .. " failed")
			os.exit(1)
		end
	end

	t.out = print
	print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		t.log(table.concat(parts, " "))
	end

	-- Frames and textures, with only the methods listed here.
	local Widget = {}
	function Widget:RegisterEvent(event) self.events[event] = true end
	function Widget:UnregisterEvent(event) self.events[event] = nil end
	function Widget:RegisterAllEvents() self.allEvents = true end
	function Widget:SetScript(name, handler) self.scripts[name] = handler end
	function Widget:GetScript(name) return self.scripts[name] end
	function Widget:SetPoint(...) self.point = { ... } end
	function Widget:ClearAllPoints() self.point = nil end
	function Widget:SetSize(width, height) self.width, self.height = width, height end
	function Widget:SetTexture(texture) self.texture = texture end
	function Widget:CreateTexture() return t.widget() end
	function Widget:SetFrameStrata() end
	function Widget:SetFrameLevel() end
	function Widget:SetHighlightTexture() end
	function Widget:RegisterForClicks() end
	function Widget:RegisterForDrag() end
	function Widget:Show() self.shown = true end
	function Widget:Hide() self.shown = false end
	function Widget:IsShown() return self.shown == true end
	function Widget:SetShown(shown) self.shown = shown and true or false end
	function Widget:CreateFontString() return t.widget() end
	function Widget:SetText(text) self.text = text end
	function Widget:GetText() return self.text end
	function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
	-- A test that needs more methods adds them here: function t.Widget:Name() ... end
	t.Widget = Widget
	-- A field nobody set reads nil, as in the game; calling a method that isn't listed fails
	-- as a call to nil, so a typo still can't pass.
	local widgetMeta = { __index = Widget }
	function t.widget(name)
		return setmetatable({ name = name, events = {}, scripts = {}, shown = false }, widgetMeta)
	end

	-- A font object: CopyFontObject takes another's file, size and flags.
	CreateFont = function(name)
		local font = { name = name, path = nil, size = nil, flags = "" }
		function font:GetFont() return self.path, self.size, self.flags end
		function font:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
		function font:CopyFontObject(other) self.path, self.size, self.flags = other:GetFont() end
		function font:GetObjectType() return "Font" end
		function font:GetName() return self.name end
		if name then _G[name] = font end
		return font
	end

	CreateFrame = function(_, name)
		local widget = t.widget(name)
		if name then _G[name] = widget end
		t.frame = t.frame or widget -- the first frame is Everlook's event frame
		return widget
	end

	function t.fire(event, ...)
		t.frame.scripts.OnEvent(t.frame, event, ...)
	end

	Minimap = t.widget("Minimap")
	function Minimap.GetWidth() return 140 end
	function Minimap.GetHeight() return 140 end
	function Minimap.GetCenter() return 1000, 500 end
	function Minimap.GetEffectiveScale() return 1 end

	t.cursor = { 0, 0 }
	GetCursorPosition = function() return t.cursor[1], t.cursor[2] end

	GameTooltip = t.widget("GameTooltip")
	function GameTooltip.SetOwner() end
	function GameTooltip.AddLine() end

	SettingsPanel = t.widget("SettingsPanel")
	HideUIPanel = function(panel) t.log("close " .. panel.name) panel:Hide() end

	SlashCmdList = {}
	Settings = {
		RegisterVerticalLayoutCategory = function(name)
			return t.category(name), t.layout(name)
		end,
		RegisterAddOnCategory = function() end,
		RegisterVerticalLayoutSubcategory = function(parent, name)
			t.log("page " .. name)
			return t.category(name, parent), t.layout(name)
		end,
		RegisterAddOnSetting = function(_, variable, key, tbl, varType, label, default)
			local setting = { variable = variable, key = key, tbl = tbl, varType = varType, default = default }
			t.settings[variable] = setting
			return setting
		end,
		CreateCheckbox = function(_, setting) t.log("checkbox " .. setting.key) end,
		CreateSliderOptions = function(min, max, step)
			local options = { min = min, max = max, step = step }
			function options:SetLabelFormatter(_, format) self.format = format end
			return options
		end,
		CreateSlider = function(_, setting, options)
			setting.slider = options
			t.log("slider " .. setting.key)
		end,
		CreateDropdown = function(_, setting, options)
			setting.options = options
			t.log("dropdown " .. setting.key)
		end,
		CreateControlTextContainer = function()
			local container = { data = {} }
			function container:Add(value, label) table.insert(self.data, { value = value, label = label }) end
			function container:GetData() return self.data end
			return container
		end,
		SetOnValueChangedCallback = function(variable, callback)
			t.settings[variable].onChange = callback
		end,
		RegisterCanvasLayoutSubcategory = function(_, frame, name)
			t.log("canvas " .. name)
			return t.category(name)
		end,
		OpenToCategory = function(id) t.log("open " .. id) end,
	}
	MinimalSliderWithSteppersMixin = { Label = { Left = 1, Right = 2 } }

	-- Categories remember their parent and have an ID each, from 1 (the Everlook page); layouts log
	-- the headers added to them.
	local lastID = 0
	function t.category(name, parent)
		lastID = lastID + 1
		local id = lastID
		local category = { name = name, parent = parent, GetID = function() return id end }
		function category:SetShouldSortAlphabetically(should) self.sorted = should end
		return category
	end
	t.headers = {} -- [page name] = { header texts in order }
	t.rows = {} -- [page name] = { every initializer in order }
	function t.layout(name)
		t.headers[name] = t.headers[name] or {}
		t.rows[name] = t.rows[name] or {}
		return { AddInitializer = function(_, initializer)
			if initializer.header then table.insert(t.headers[name], initializer.header) end
			table.insert(t.rows[name], initializer)
		end }
	end
	CreateSettingsListSectionHeaderInitializer = function(text, tooltip) return { header = text, tooltip = tooltip } end
	CreateSettingsButtonInitializer = function(name, buttonText, buttonClick, tooltip, addSearchTags)
		assert(addSearchTags ~= nil, "CreateSettingsButtonInitializer needs addSearchTags")
		return { button = name, buttonText = buttonText, click = buttonClick, tooltip = tooltip, search = addSearchTags }
	end
	C_AddOns = { GetAddOnMetadata = function(name, field)
		if field == "Version" then return "0.1.0" end
		if field == "Notes" then return "Notes of " .. name end
	end }

	-- Settings by variable name ("AddonName_key"). t.change does what the Options window does
	-- when the player changes one: stores the value and fires the change callback.
	t.settings = {}
	function t.change(variable, value)
		local setting = assert(t.settings[variable], "no setting " .. variable)
		setting.tbl[setting.key] = value
		if setting.onChange then setting.onChange(nil, setting, value) end
	end

	IsShiftKeyDown = function() return t.shift end
	InCombatLockdown = function() return t.combat end

	-- Clocks. GetTime is seconds (t.now); debugprofilestop is milliseconds (t.ms) and moves on by
	-- t.clockStep every time it's read, so a test can make work "cost" time.
	t.now, t.ms, t.clockStep, t.fps = 0, 0, 0, 60
	GetTime = function() return t.now end
	debugprofilestop = function()
		t.ms = t.ms + t.clockStep
		return t.ms
	end
	GetFramerate = function() return t.fps end

	-- Game settings (CVars), as strings like the game keeps them. Tests may replace these.
	t.cvars = {}
	GetCVar = function(name) return t.cvars[name] end
	SetCVar = function(name, value) t.cvars[name] = tostring(value) end
	geterrorhandler = function() return function(message) t.log("error " .. tostring(message)) end end

	-- Runs the scheduler frame by frame until nothing is awake (or `frames` frames have passed).
	-- Returns the number of frames it took.
	function t.runSchedule(frames)
		for frame = 1, frames or 1000 do
			Everlook.Schedule.Tick()
			local awake = false
			for _, task in pairs(Everlook.Schedule.Snapshot().tasks) do
				if task.state == "working" then awake = true end
			end
			if not awake then return frame end
		end
		return frames or 1000
	end

	C_Timer = {
		After = function(_, fn) fn() end,
		NewTicker = function(_, fn)
			local ticker = { fn = fn }
			function ticker:Cancel() self.cancelled = true end
			t.tickers[#t.tickers + 1] = ticker
			return ticker
		end,
	}

	-- Runs the newest ticker until it cancels itself.
	function t.runTicker(limit)
		local ticker = t.tickers[#t.tickers]
		if not ticker then return end
		for _ = 1, limit or 100 do
			if ticker.cancelled then return end
			ticker.fn()
		end
	end


	-- Loads an addon the way the game does: each .lua file its TOC lists, in order, sharing one
	-- namespace table, then ADDON_LOADED.
	function t.load(name)
		local folder = root .. "/" .. name .. "/"
		local ns = {}
		for line in io.lines(folder .. name .. ".toc") do
			line = line:gsub("\r", "")
			if line ~= "" and not line:find("^#") and line:find("%.lua$") then
				assert(loadfile(folder .. line:gsub("\\", "/")))(name, ns)
			end
		end
		t.fire("ADDON_LOADED", name)
	end

	t.load("Everlook")
	t.load("EverlookPreferences")
	t.load("EverlookQA")
	return t
end
