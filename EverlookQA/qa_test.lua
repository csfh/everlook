local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check, printed = t.check, t.printed

t.out("EverlookQA")

check(EverlookQA == Everlook:GetAddon("EverlookQA"), "EverlookQA is a global and an Everlook addon")
check(EverlookQA.db.reportAtLogin, "login report starts on")

PresentTable = { present = function() end, zero = 0, flag = false }
EverlookQA:Expect("Fake", {
	"PresentTable.present",
	"PresentTable.zero",
	"PresentTable.flag",
	"PresentTable.absent",
	"AbsentTable.anything",
	"PresentTable.zero.deeper",
})

local missing, checked = EverlookQA:Run()
check(checked >= 6, "counts every expected name")
local fake = table.concat(missing.Fake or {}, ",")
check(fake == "PresentTable.absent,AbsentTable.anything,PresentTable.zero.deeper",
	"0 and false count as present; missing fields, tables and paths through non-tables don't")
check(missing.Everlook == nil, "Everlook's own needs are met by the stubs")

t.reset()
t.fire("PLAYER_LOGIN")
check(printed("Fake is missing: PresentTable.absent, AbsentTable.anything, PresentTable.zero.deeper"),
	"login report names the addon and what it's missing")
check(not printed("Everlook is missing"), "addons with nothing missing stay silent")

EverlookQA:Expect("Fake", { "PresentTable.present" })
t.reset()
EverlookQA:Report()
check(#t.calls == 0, "silent when everything is there; Expect replaces an addon's list")

-- Overview: green found, yellow optional and missing, red missing.
EverlookQA:Expect("Mixed", { "PresentTable.present", "AbsentTable.needed" }, { "PresentTable.flag", "AbsentTable.nice" })
EverlookQA:Expect("Fallbacks", { "PresentTable.present" }, { "AbsentTable.nice" })
local rows = {}
for _, row in ipairs(EverlookQA:Overview()) do rows[row.owner] = row end
local mixed = rows.Mixed
check(mixed.status == "missing" and mixed.found == 2 and mixed.total == 4, "a row counts what was found, and is red when a needed name is missing")
local states = {}
for _, entry in ipairs(mixed.entries) do states[entry.name] = entry.state end
check(states["PresentTable.present"] == "found" and states["AbsentTable.needed"] == "missing"
	and states["PresentTable.flag"] == "found" and states["AbsentTable.nice"] == "optional",
	"each name is found, missing, or optional-and-missing")
check(rows.Fallbacks.status == "optional", "a row missing only optional names is yellow")
check(rows.Fake.status == "found" and rows.Everlook ~= nil, "a row with everything is green, and every addon is listed")

local header, names = EverlookQA:RowText(mixed)
check(header:find("|cffff5555Mixed|r", 1, true) and header:find("2/4 found", 1, true), "the row header is coloured by its status")
check(names:find("|cff44dd66PresentTable.present|r", 1, true) and names:find("|cffff5555AbsentTable.needed|r", 1, true)
	and names:find("|cffffcc33AbsentTable.nice|r", 1, true), "each name is in its own colour")

t.reset()
EverlookQA:Report()
check(printed("Mixed is missing: AbsentTable.needed") and not printed("AbsentTable.nice") and not printed("Fallbacks"),
	"the login report names only what's needed, not optional names")

-- The page: built on first show, filled again on every show.
function t.Widget:SetWidth(width) self.width = width end
function t.Widget:SetHeight(height) self.height = height end
function t.Widget:GetWidth() return self.width or 600 end
function t.Widget:SetJustifyH() end
function t.Widget:GetStringHeight() return 12 end
function t.Widget:SetScrollChild(child) self.child = child end
function t.Widget:SetChecked(checked) self.checked = checked and true or false end
function t.Widget:GetChecked() return self.checked end
local page = EverlookQA.overview
check(t.settings.EverlookQA_taintLog == nil and t.settings.EverlookQA_reportAtLogin == nil, "QA is one page, with no separate settings list")
check(page.content == nil, "the page isn't built until it's shown")
page.scripts.OnShow(page)
local texts = {}
for _, line in ipairs(page.lines) do
	if line.shown then texts[#texts + 1] = line.text end
end
check(#texts == #EverlookQA:Overview() * 2, "two lines per addon")
local joined = table.concat(texts, "\n")
check(joined:find("Mixed", 1, true) and joined:find("AbsentTable.nice", 1, true), "every name is on the page")
check(page.checkboxes.reportAtLogin.checked == true and page.checkboxes.taintLog.checked == false,
	"its two checkboxes sit at the top, showing the saved settings")

AbsentTable = { needed = true }
page.scripts.OnShow(page)
local refreshed = false
for _, line in ipairs(page.lines) do
	if line.shown and line.text:find("|cff44dd66AbsentTable.needed|r", 1, true) then refreshed = true end
end
check(refreshed, "showing it again checks again, so something loaded later turns green")

-- The taint log setting.
local cvars = { taintLog = "0" }
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) cvars[name] = value end
check(EverlookQA.db.taintLog == false, "the taint log starts off")
local box = page.checkboxes.taintLog
box:SetChecked(true)
box.scripts.OnClick(box)
check(EverlookQA.db.taintLog == true and cvars.taintLog == "1", "ticking it turns the game's taint log on")
box:SetChecked(false)
box.scripts.OnClick(box)
check(EverlookQA.db.taintLog == false and cvars.taintLog == "0", "and unticking turns it off")
cvars.taintLog = "2"
EverlookQA:ApplyTaintLog()
check(cvars.taintLog == "2", "at login with the box off, a log turned on by hand stays on")

-- TEMP: the taint record names what an addon wrote among the game's variables, and never a value.
local tainted = {}
issecurevariable = function(tbl, key)
	if key == nil then tbl, key = _G, tbl end
	local who = tainted[tbl] and tainted[tbl][key]
	return who == nil, who
end
FramePositionDelegate = { shown = { area = {} }, clean = 1 }
tainted[FramePositionDelegate] = { shown = "EverlookPreferences" }
tainted[FramePositionDelegate.shown] = { area = "EverlookPreferences" }
tainted[_G] = { SomeGameGlobal = "EverlookUIScale", EverlookThing = "EverlookQA" }
SomeGameGlobal, EverlookThing = true, true
local scan = EverlookQA.TaintScan()
local delegate = table.concat(scan.FramePositionDelegate.tainted, "\n")
check(delegate:find("FramePositionDelegate.shown <- EverlookPreferences", 1, true)
	and delegate:find("FramePositionDelegate.shown.area <- EverlookPreferences", 1, true)
	and not delegate:find("clean", 1, true), "the taint record lists tainted fields of the game's frames, two levels down")
local globals = table.concat(scan._G.tainted, "\n")
check(globals:find("SomeGameGlobal <- EverlookUIScale", 1, true) and not globals:find("EverlookThing", 1, true),
	"and globals an addon wrote, leaving out Everlook's own names")
-- A root that fails is noted; the others are still scanned.
DefaultCompactUnitFrameOptions = setmetatable({}, { __pairs = function() error("boom") end })
CompactPartyFrame = { IsForbidden = function() error("forbidden check failed") end }
scan = EverlookQA.TaintScan()
check(scan.CompactPartyFrame.error and scan.FramePositionDelegate.found == 2, "one root failing doesn't lose the others")
CompactPartyFrame, DefaultCompactUnitFrameOptions = nil, nil
for _ = 1, 7 do t.fire("PLAYER_LOGOUT") end
local records = EverlookQA.db.tempTaint
check(type(records) == "table" and #records == 5 and records[1].roots.FramePositionDelegate.found == 2,
	"each logout or reload adds a record, and the last five are kept")
issecurevariable = nil

local ok = pcall(dofile, dir .. "/stubs.lua")
check(not ok, "stubs.lua refuses to load where CreateFrame already exists")

t.done()
