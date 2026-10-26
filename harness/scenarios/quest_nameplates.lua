-- The quest mark beside a nameplate, on real frames laid out the way the game lays out a friendly NPC plate: a health
-- bar, the name over it spanning the bar with a four unit inset (centred), and the level to the right.
harness.include("lib/game.lua")
harness.load_addon("Everlook")
harness.load_addon("Everlook_Nameplates")
harness.load_addon("Everlook_QuestNameplates")
game.login()
if EverlookMinimapButton then EverlookMinimapButton:Hide() end

local plate = CreateFrame("Frame", "TestNamePlate", UIParent)
plate:SetSize(144, 40)
plate:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
function plate:GetUnit() return "nameplate1" end
local unit_frame = CreateFrame("Frame", nil, plate)
unit_frame:SetAllPoints(plate)
plate.UnitFrame = unit_frame
local container = CreateFrame("Frame", nil, unit_frame)
container:SetSize(144, 12)
container:SetPoint("BOTTOM", unit_frame, "BOTTOM", 0, 4)
unit_frame.HealthBarsContainer = container
local bar = CreateFrame("StatusBar", nil, container)
bar:SetAllPoints(container)
bar:SetMinMaxValues(0, 1)
bar:SetValue(1)
bar:SetStatusBarColor(0.0, 0.65, 0.0)
unit_frame.healthBar = bar
local name = unit_frame:CreateFontString(nil, "OVERLAY")
name:SetFontObject(GameFontHighlight)
name:SetJustifyH("CENTER")
name:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 4, 2)
name:SetPoint("BOTTOMRIGHT", container, "TOPRIGHT", -4, 2)
name:SetHeight(14)
name:SetText("Foreman Oslow")
unit_frame.name = name
local level = unit_frame:CreateFontString(nil, "OVERLAY")
level:SetFontObject(GameFontNormal)
level:SetPoint("LEFT", container, "RIGHT", 6, 0)
level:SetText("20")

C_NamePlate = { GetNamePlateForUnit = function(unit) if unit == "nameplate1" then return plate end end, GetNamePlates = function() return { plate } end }
function UnitExists() return true end
function UnitIsPlayer() return false end
function UnitIsQuestBoss() return false end
function UnitCanAttack() return false end
function UnitIsUnit() return false end
C_QuestLog = C_QuestLog or {}
C_QuestLog.UnitIsRelatedToActiveQuest = function() return true end

harness.snapshot("Without the module")
Everlook.module.set("nameplates", "enabled", true)
Everlook.module.set("quest_nameplates", "enabled", true)
harness.advance(0.5)
harness.event("NAME_PLATE_UNIT_ADDED", "nameplate1")
harness.advance(0.1)

local function mark()
	for _, region in ipairs({ unit_frame:GetRegions() }) do
		if region:GetObjectType() == "Texture" and region:IsShown() then return region end
	end
end
local m = mark()
local c, n = harness.rect(container), harness.rect(name)
harness.check("a unit on a quest has a mark", m ~= nil)
local b = harness.rect(m)
harness.check("by default it sits just left of the health bar (" .. string.format("%.0f vs bar %.0f", b.right, c.left) .. ")", b.right <= c.left and c.left - b.right <= 3)
harness.check("and is as tall as the name and the health bar together (" .. string.format("%.0f vs %.0f", b.height, c.bottom - n.top) .. ")", math.abs(b.top - n.top) < 1.5 and math.abs(b.bottom - c.bottom) < 1.5)
harness.check("the name is left-aligned beside it", name:GetJustifyH() == "LEFT")
harness.snapshot("Both rows, name left-aligned")
Everlook.module.set("nameplates", "width", 34)
harness.snapshot("Wider (34)")
Everlook.module.set("nameplates", "width", 26)
Everlook.module.set("nameplates", "align_name", false)
harness.snapshot("Both rows, name centred")
Everlook.module.set("nameplates", "align_name", true)
Everlook.module.set("nameplates", "layout", "name_left")
harness.snapshot("Left of the name only")
Everlook.module.set("nameplates", "layout", "bar_left")
harness.snapshot("Left of the health bar only")
for _, e in ipairs(harness.errors()) do print("script error:", e) end

-- The anatomy probe reads a plate's parts without failing, and keeps what it found where a reload writes it out.
SlashCmdList.EVERLOOKPLATES()
local anatomy = EverlookDB and EverlookDB.plate_anatomy
harness.check("the anatomy probe keeps a report", anatomy ~= nil and #anatomy.lines > 5)
local joined = table.concat(anatomy and anatomy.lines or {}, "\n")
harness.check("it lists the plate's name, health bar container and level", joined:find("name = FontString", 1, true) ~= nil and joined:find("HealthBarsContainer = Frame", 1, true) ~= nil)
for _, e in ipairs(harness.errors()) do print("script error:", e) end
