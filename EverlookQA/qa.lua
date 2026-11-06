-- Checks that the game functions and frames each Everlook addon needs exist on this client.
-- Addons list what they need with
--   EverlookQA:Expect(name, { "C_Container.GetContainerItemInfo", ... }, { optional names })
-- Optional names are ones the addon has a fallback for: missing, they show yellow, not red.
local QA = Everlook:NewAddon("EverlookQA", {
	label = "QA",
	defaults = {
		reportAtLogin = true,
		taintLog = false,
	},
})
EverlookQA = QA

QA.expected = {} -- [addon name] = { "Global", "Table.Field", ... }
QA.optional = {} -- [addon name] = { ... }
local order = {}

function QA:Expect(owner, names, optional)
	if not self.expected[owner] then
		order[#order + 1] = owner
	end
	self.expected[owner] = names
	self.optional[owner] = optional or {}
end

-- "C_Container.GetContainerItemInfo" -> the value at that path, or nil.
local function resolve(path)
	local value = _G
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then return nil end
		value = value[part]
	end
	return value
end

-- { [owner] = { missing names } } for every addon with something missing, and the number checked.
function QA:Run()
	local missing, checked = {}, 0
	for _, owner in ipairs(order) do
		for _, name in ipairs(self.expected[owner]) do
			checked = checked + 1
			if resolve(name) == nil then
				missing[owner] = missing[owner] or {}
				table.insert(missing[owner], name)
			end
		end
	end
	return missing, checked
end

-- Every addon and every name it asked for, as the overview page shows them:
--   { { owner, status = "found"|"optional"|"missing", found, total, entries = { { name, state } } } }
-- An entry's state is "found", "missing", or "optional" (an optional name that's missing). A row's
-- status is its worst entry.
function QA:Overview()
	local rows = {}
	for _, owner in ipairs(order) do
		local row = { owner = owner, status = "found", found = 0, total = 0, entries = {} }
		local function add(name, optional)
			local state = "found"
			if resolve(name) == nil then
				state = optional and "optional" or "missing"
			end
			row.total = row.total + 1
			if state == "found" then
				row.found = row.found + 1
			elseif state == "missing" or row.status == "found" then
				row.status = state
			end
			row.entries[#row.entries + 1] = { name = name, state = state }
		end
		for _, name in ipairs(self.expected[owner]) do add(name, false) end
		for _, name in ipairs(self.optional[owner]) do add(name, true) end
		rows[#rows + 1] = row
	end
	return rows
end

-- Prints one line per addon with missing names; silent when everything is there.
function QA:Report()
	local missing = self:Run()
	for _, owner in ipairs(order) do
		if missing[owner] then
			self:Print(owner .. " is missing: " .. table.concat(missing[owner], ", "))
		end
	end
end

-- Everlook and EverlookPreferences load before this addon, so their lists live here.
QA:Expect("Everlook", {
	"CreateFrame",
	"SlashCmdList",
	"debugprofilestop",
	"GetFramerate",
	"GetTime",
	"InCombatLockdown",
	"geterrorhandler",
	"collectgarbage",
}, {
	"C_CurrencyInfo.GetCoinTextureString",
	"GetMoneyString",
})

QA:Expect("EverlookPreferences", {
	"SlashCmdList",
	"Settings.RegisterVerticalLayoutCategory",
	"Settings.RegisterAddOnCategory",
	"Settings.RegisterVerticalLayoutSubcategory",
	"Settings.RegisterAddOnSetting",
	"Settings.CreateCheckbox",
	"Settings.RegisterCanvasLayoutSubcategory",
	"CreateSettingsListSectionHeaderInitializer",
	"CreateSettingsButtonInitializer",
	"C_AddOns.GetAddOnMetadata",
	"Settings.CreateSlider",
	"Settings.CreateSliderOptions",
	"Settings.SetOnValueChangedCallback",
	"MinimalSliderWithSteppersMixin.Label.Right",
	"Settings.OpenToCategory",
	"Minimap",
	"GetCursorPosition",
	"GameTooltip",
})

QA:Expect("EverlookQA", {
	"GetCVar",
	"SetCVar",
}, {
	"issecurevariable", -- TEMP: the taint record
	"issecretvalue",
	"C_NamePlate.GetNamePlates",
})

-- The overview page ---------------------------------------------------------

local COLORS = {
	found = "ff44dd66",
	optional = "ffffcc33",
	missing = "ffff5555",
}

local function colored(state, text)
	return "|c" .. COLORS[state] .. text .. "|r"
end

-- One row's two lines: "EverlookSellJunk  10/10 found" and every name in its colour.
function QA:RowText(row)
	local header = colored(row.status, row.owner) .. ("  %d/%d found"):format(row.found, row.total)
	local names = {}
	for i, entry in ipairs(row.entries) do
		names[i] = colored(entry.state, entry.name)
	end
	return header, table.concat(names, ", ")
end

local LEGEND = colored("found", "Found") .. "    " .. colored("optional", "Missing, has a fallback")
	.. "    " .. colored("missing", "Missing")

local CHECKBOXES = {
	{ key = "reportAtLogin", label = "Report missing game functions at login",
		tooltip = "At login, list any game function an Everlook addon needs that this client doesn't have. Silent when all are there." },
	{ key = "taintLog", label = "Write the taint log",
		tooltip = "Has the game write Logs\\taint.log, which names the addon behind \"Interface action failed because of an AddOn\" and similar blocked actions. Turn it off again when you're done; the log grows while it's on." },
}

-- A checkbox drawn on the page, bound to QA.db[key]. The page is a canvas, so it can hold the list
-- below as well; these two aren't in Blizzard's settings list.
local function checkbox(frame, anchor, option)
	local button = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
	button:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
	local label = button.Text or button.text
	if label then label:SetText(option.label) end
	button:SetChecked(QA.db[option.key])
	button:SetScript("OnClick", function(clicked)
		QA.db[option.key] = clicked:GetChecked() and true or false
		QA:OnSettingChanged(option.key, QA.db[option.key])
	end)
	button:SetScript("OnEnter", function(hovered)
		GameTooltip:SetOwner(hovered, "ANCHOR_RIGHT")
		GameTooltip:AddLine(option.label, 1, 1, 1)
		GameTooltip:AddLine(option.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return button
end

local function buildPage(frame)
	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("QA")

	frame.checkboxes = {}
	local anchor = title
	for _, option in ipairs(CHECKBOXES) do
		anchor = checkbox(frame, anchor, option)
		frame.checkboxes[option.key] = anchor
	end

	local legend = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	legend:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -12)
	legend:SetText(LEGEND)

	-- A scroll frame when the client has the template; a plain frame otherwise.
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
	if not ok then scroll = CreateFrame("Frame", nil, frame) end
	scroll:SetPoint("TOPLEFT", legend, "BOTTOMLEFT", 0, -12)
	scroll:SetPoint("BOTTOMRIGHT", -32, 16)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	if ok then scroll:SetScrollChild(content) end

	frame.content, frame.lines = content, {}
end

-- Fills the page from a fresh check. Lines are reused between shows.
local function fillPage(frame)
	for key, button in pairs(frame.checkboxes) do button:SetChecked(QA.db[key]) end

	local content, lines = frame.content, frame.lines
	local width = math.max((frame:GetWidth() or 0) - 64, 300)
	content:SetWidth(width)
	local y, index = 0, 0
	local function line(font, text, gap)
		index = index + 1
		local fontString = lines[index]
		if not fontString then
			fontString = content:CreateFontString(nil, "OVERLAY", font)
			fontString:SetJustifyH("LEFT")
			lines[index] = fontString
		end
		fontString:SetWidth(width)
		fontString:ClearAllPoints()
		fontString:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		fontString:SetText(text)
		fontString:Show()
		y = y + (fontString:GetStringHeight() or 12) + gap
	end
	for _, row in ipairs(QA:Overview()) do
		local header, names = QA:RowText(row)
		line("GameFontNormal", header, 2)
		line("GameFontHighlightSmall", names, 12)
	end
	for i = index + 1, #lines do lines[i]:Hide() end
	content:SetHeight(math.max(y, 1))
end

-- One page in Developer: the two settings, then every game function each addon asked for.
-- Checked again every time it's shown, so anything the game loads later turns green.
function QA:OnInitialize()
	self:ApplyTaintLog()
	local frame = CreateFrame("Frame")
	frame:SetScript("OnShow", function(shown)
		if not shown.content then buildPage(shown) end
		fillPage(shown)
	end)
	self.overview = frame
	EverlookPreferences:NewCanvasPage(self, frame, "QA", "Developer")
end

-- The game's taintLog setting: 1 writes blocked actions and who caused them, 0 is off. With the box
-- off at login it's left as it is, so a log turned on with /console taintLog stays on.
function QA:ApplyTaintLog(changed)
	if not (GetCVar and SetCVar) or GetCVar("taintLog") == nil then return end
	if self.db.taintLog then
		SetCVar("taintLog", "1")
	elseif changed then
		SetCVar("taintLog", "0")
	end
end

function QA:OnSettingChanged(key)
	if key == "taintLog" then self:ApplyTaintLog(true) end
end

-- TEMP: on 2026-11-05 Blizzard's party frames, nameplates and Edit Mode ran "tainted by
-- EverlookPreferences" and failed on secret values. At each logout or reload this records which of
-- the game's own variables an addon wrote, and which addon, so a later session names the one at
-- fault. Only the path and the addon are saved, never a value (a secret can't be saved). The last
-- few records are kept, since a reload would otherwise replace the one that saw it. Remove once
-- the taint is settled.
local TAINT_ROOTS = { "DefaultCompactUnitFrameSetupOptions", "DefaultCompactUnitFrameOptions",
	"FramePositionDelegate", "CompactPartyFrame", "CompactRaidFrameContainer", "NamePlateDriverFrame",
	"EditModeManagerFrame", "Menu", "UIParent", "SettingsPanel" }
local ROOT_VISITS = 4000 -- entries looked at under each root
local ROOT_ENTRIES = 60 -- tainted entries kept for each root
local RECORDS = 5

local function secretValue(value)
	return issecurevariable ~= nil and issecretvalue ~= nil and issecretvalue(value) == true
end

-- One root, `depth` levels down: { visited, found, full, tainted = { "path <- addon" } }.
local function scanRoot(name, tbl, depth)
	local result = { visited = 0, found = 0, full = false, tainted = {} }
	local function note(path, taint)
		result.found = result.found + 1
		if #result.tainted < ROOT_ENTRIES then result.tainted[#result.tainted + 1] = path .. " <- " .. tostring(taint) end
	end
	local function scan(node, path, level)
		if type(node) ~= "table" or result.full then return end
		if type(node.IsForbidden) == "function" and node:IsForbidden() then return end
		for key, value in pairs(node) do
			result.visited = result.visited + 1
			if result.visited >= ROOT_VISITS then
				result.full = true
				return
			end
			if not secretValue(key) and (type(key) == "string" or type(key) == "number") then
				local secure, taint = issecurevariable(node, key)
				local here = path .. "." .. tostring(key)
				if not secure then note(here, taint) end
				if level > 0 and not secretValue(value) and type(value) == "table" then scan(value, here, level - 1) end
			end
		end
	end
	if type(name) == "string" then
		local secure, taint = issecurevariable(name)
		if not secure then note(name, taint) end
	end
	scan(tbl, tostring(name), depth)
	return result
end

-- Globals an addon wrote, other than Everlook's own names.
local function scanGlobals()
	local result = { visited = 0, found = 0, full = false, tainted = {} }
	for key in pairs(_G) do
		result.visited = result.visited + 1
		if type(key) == "string" and not key:find("^Everlook") and not key:find("EVERLOOK") then
			local secure, taint = issecurevariable(key)
			if not secure then
				result.found = result.found + 1
				if #result.tainted < ROOT_ENTRIES then result.tainted[#result.tainted + 1] = key .. " <- " .. tostring(taint) end
			end
		end
	end
	return result
end

-- Every root on its own, so one that fails doesn't lose the rest.
function QA.TaintScan()
	local roots = {}
	local function run(label, fn, ...)
		local ok, result = pcall(fn, ...)
		roots[label] = ok and result or { error = tostring(result) }
	end
	for _, name in ipairs(TAINT_ROOTS) do
		if _G[name] ~= nil then run(name, scanRoot, name, _G[name], 2) end
	end
	if C_NamePlate and C_NamePlate.GetNamePlates then
		local ok, plates = pcall(C_NamePlate.GetNamePlates)
		if ok and type(plates) == "table" then
			for index, plate in ipairs(plates) do
				if index > 3 then break end
				run("nameplate" .. index, scanRoot, nil, plate.UnitFrame, 1)
			end
		end
	end
	run("_G", scanGlobals)
	return roots
end

local function recordTaint()
	if not issecurevariable then return end
	local records = QA.db.tempTaint
	if type(records) ~= "table" then records = {} end
	table.insert(records, 1, { at = date and date("%Y-%m-%d %H:%M:%S") or "", roots = QA.TaintScan() })
	while #records > RECORDS do table.remove(records) end
	QA.db.tempTaint = records
end

-- PLAYER_LOGIN: every addon that depends on EverlookQA has loaded and listed its needs.
function QA:OnEnable()
	if self.db.reportAtLogin then
		self:Report()
	end
	self:RegisterEvent("PLAYER_LOGOUT", recordTaint) -- TEMP
	self.db.tempArt = nil -- the art record is read; this clears it from the saved settings
end
