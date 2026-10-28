-- Text that does not fit its box, on every Everlook frame that is showing. A line of text that is set to one line and
-- is wider than the width it was given is cut with an ellipsis in the game, so a label or a number loses its end.
-- The harness measures a font by the widths of its letters, and the client may render a face a little wider, so a
-- line has to fit with SLACK to spare. SLACK is a guess until the client's own widths are measured (I4 in the polestar
-- backlog); change it here when they are.
harness.include("lib/game.lua")
local SLACK = 1.05

local names = { "Everlook", "Everlook_Fonts", "Everlook_Island" }
for _, name in ipairs({ "ActionBarSlots", "ActionShortcuts", "AutoLoot", "AutoRepair", "AutoResponses", "Bags", "CameraDistance", "ChatLayout", "CinematicSkip", "CompactChat",
	"FlightTime", "FriendConveniences", "GroundEffects", "HideClutter", "IslandBuffs", "IslandExperience", "IslandHearth", "IslandInvites", "IslandLoot",
	"IslandMail", "IslandProfessions", "IslandQuestNotices", "IslandReactions", "IslandRecap", "IslandReputation", "IslandShare", "IslandWarnings",
	"MinimapCoordinates", "Nameplates", "NameplateTitles", "OpenContainers", "QuestAutomation", "QuestLevels", "QuestNameplates", "QuestTextSize", "RadialMenu", "RewardMarks", "SellJunk",
	"SwingTimers", "TakeMail", "TooltipCursor", "TrackerTextSize", "UnitFrameNames", "UsefulTooltips" }) do
	names[#names + 1] = "Everlook_" .. name
end
local ids = {}
local register
for index, name in ipairs(names) do
	if index == 2 then
		register = Everlook.module.register
		Everlook.module.register = function(module) ids[#ids + 1] = module.id; return register(module) end
	end
	harness.check(name .. " loads", pcall(harness.load_addon, name))
end
game.login()
harness.advance(1)
for _, id in ipairs(ids) do pcall(Everlook.module.set, id, "enabled", true) end
harness.advance(3)

-- Whether anything of the frame can be seen: not faded out, here or in a parent.
local function seen(frame)
	local alpha = 1
	local up = frame
	while up do
		alpha = alpha * (up:GetAlpha() or 1)
		up = up:GetParent()
	end
	return alpha > 0.01
end

-- The strings that are showing and were given a width, with the text they hold.
local function cut_off()
	local found = {}
	for _, frame in ipairs(harness.frames()) do
		if harness.info(frame).visible and seen(frame) then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.GetStringWidth and region:IsShown() and region.GetText then
					local text = region:GetText()
					local width = region:GetWidth()
					local lines = region.GetMaxLines and region:GetMaxLines() or 0
					local wraps = region.CanWordWrap and region:CanWordWrap()
					if type(text) == "string" and text ~= "" and width and width > 0 and (lines == 1 or wraps == false) then
						local raw = region:GetStringWidth()
						local needed = raw * SLACK
						-- A label sized from its own measured width (the row code does this) takes the client's own
						-- measure at run time, so the harness's slack does not apply to it.
						local sized_by_itself = width == math.ceil(raw)
						if raw > width + 0.5 or (needed > width + 0.5 and not sized_by_itself) then
							found[#found + 1] = { text = text, width = width, needed = needed, owner = (frame:GetName() or tostring(frame:GetObjectType())) .. " in " .. ((frame:GetParent() and frame:GetParent():GetName()) or "?") .. " " .. tostring(select(1, region:GetFont())) }
						end
					end
				end
			end
		end
	end
	return found
end

local function report(label, offenders)
	local said = {}
	for _, item in ipairs(offenders) do
		said[#said + 1] = ("%q needs %.1f of %.1f on %s"):format(item.text:sub(1, 40), item.needed, item.width, item.owner)
	end
	harness.check("no line of text is wider than its box, " .. label .. (#said > 0 and (": " .. table.concat(said, "; ")) or ""), #offenders == 0)
end

report("with every module on and the island resting", cut_off())

-- The island open and pinned shows its panes, tables and summary.
local island = harness.find("EverlookSmartIsland")
if island then
	if EverlookMinimapButton then EverlookMinimapButton:Hide() end
	local x, y = harness.center(island)
	harness.click(x, y)
	harness.advance(1)
	report("with the island open", cut_off())
else
	harness.check("the island is there to open", false)
end

-- A change of size alone, with nothing turned off, lays the open island out again.
if Everlook.module.set then
	Everlook.module.set("fonts", "size_offset", 8)
	harness.advance(3)
	report("with the island open when the Fonts addon changes size", cut_off())
	Everlook.module.set("fonts", "size_offset", 0)
	harness.advance(3)
end

-- The Fonts addon can add points to every face. The island lays its text out again when it is turned off and on,
-- and the layout is then to keep every line inside its box at the largest adjustment.
if Everlook.module.set then
	Everlook.module.set("fonts", "size_offset", 8)
	harness.advance(2)
	Everlook.module.set("island", "enabled", false)
	harness.advance(1)
	Everlook.module.set("island", "enabled", true)
	harness.advance(2)
	local again = harness.find("EverlookSmartIsland")
	if again then
		local x, y = harness.center(again)
		harness.click(x, y)
		harness.advance(1)
	end
	report("with the Fonts addon at its largest size adjustment and the island laid out again", cut_off())
	Everlook.module.set("fonts", "size_offset", 0)
	harness.advance(2)
end

local offenders = {}
-- The audit itself: a label that is too long for its box is found, and one that fits is not.
local probe = CreateFrame("Frame")
probe:SetSize(60, 20)
probe:SetPoint("CENTER")
local label = probe:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
label:SetWidth(60)
label:SetMaxLines(1)
label:SetPoint("CENTER")
label:SetText("A label far too long for sixty units")
local found = cut_off()
local flagged = false
for _, item in ipairs(found) do if item.text:find("far too long", 1, true) then flagged = true end end
harness.check("a deliberately long label is found", flagged)
label:SetText("Short")
local still = false
for _, item in ipairs(cut_off()) do if item.text == "Short" then still = true end end
harness.check("a short one is not", not still)
