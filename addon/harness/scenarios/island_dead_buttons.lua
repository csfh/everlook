-- The open island's buttons did not answer in the client. This scenario holds the failure and the success side by
-- side, from what the client reported with /islandmouse (island open, pinned, pointer on a Pin button, panel layer at
-- level 50, the same as the island's own frame):
--
--   plain  : EverlookSmartIsland gets the mouse        (the Pin button, L54, holds the pointer and loses)
--   noroot : the Pin button gets it                    (island's own mouse off)
--   noclip : the Pin button gets it                    (panel stops clipping)
--   raise  : the Pin button gets it, now at L55        (panel one level up; its buttons rose with it)
--   mouse  : EverlookSmartIsland gets the mouse again  (panel takes the mouse itself)
--
-- The rule that fits all five (docs/engine-facts.md, row 19): a clipping frame's subtree is ordered as one unit at the
-- clipping frame's level, and a frame outside it at the same level wins if it is an ancestor.
-- The fix: the panel keeps the level a child starts with, one above the island.
harness.include("lib/game.lua")
harness.include("lib/islandmouse.lua")
game.quests()
harness.load_addon("Everlook")
harness.load_addon("Everlook_Island")
game.login()
Everlook.module.set("smart_island", "enabled", true)
Everlook.module.set("smart_island", "quest_context", true)
Everlook.module.set("smart_island", "quest_plan", true)
harness.advance(1)

local island = harness.find("EverlookSmartIsland")
local panel = harness.find("EverlookIslandExpanded")
local rect = harness.rect(island)
harness.click(rect.left + rect.width / 2, rect.top + 8)
harness.advance(1)
if not Everlook.smart_island.view().pinned then
	harness.click(rect.left + rect.width / 2, rect.top + 8)
	harness.advance(1)
end
assert(Everlook.smart_island.view().pinned, "the island is pinned for these tests")

local function button_with_text(text)
	for _, frame in ipairs(harness.frames()) do
		if harness.info(frame).visible then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.GetText and region:GetText() == text then
					local walker = frame
					while walker and not walker:GetScript("OnClick") do walker = walker:GetParent() end
					if walker then return walker end
				end
			end
		end
	end
end

local pin = button_with_text("Pin")
local x, y = harness.center(pin)
local shipped_level = panel:GetFrameLevel()

local function tail(name) return name and tostring(name):match("([^.]+)$") end
local function kind_of(name)
	if name == nil or not tostring(name):find("Everlook", 1, true) then return "none" end
	local last = tail(name)
	if last == "EverlookSmartIsland" then return "root" end
	if last == "EverlookIslandExpanded" then return "panel" end
	return "pin"
end

local function report_for(experiment)
	harness.move(x, y)
	island_mouse(experiment)
	harness.advance(3.1)
	local kept = EverlookDB.island_mouse[experiment == "" and "plain" or experiment]
	local gets, level
	for _, line in ipairs(kept.lines) do
		local first, found_level = line:match("^GETS THE MOUSE 1: (.-) L(%d+)")
		if first then gets, level = first, tonumber(found_level) end
	end
	return kind_of(gets), level
end

-- 1. The failure, reproduced: the panel back at level 50, as it was. Each experiment gives what the client reported.
panel:SetFrameLevel(50)
local observed = { [""] = "root", noroot = "pin", noclip = "pin", raise = "pin", mouse = "root" }
for _, experiment in ipairs({ "", "noroot", "noclip", "raise", "mouse" }) do
	local got, level = report_for(experiment)
	harness.check("failure, panel at 50, experiment " .. (experiment == "" and "(plain)" or experiment) .. ": " .. observed[experiment] .. " gets the mouse, as the client reported (" .. got .. (level and (" L" .. level) or "") .. ")", got == observed[experiment])
end
local _, raised_level = report_for("raise")
harness.check("and raising the panel raised the Pin button with it, to the L55 the client reported", raised_level == 55)
harness.move(x, y)
harness.click(x, y)
harness.advance(0.3)
harness.check("failure: pressing Pin pins nothing, and the press lands on the island, which unpins itself", Everlook.smart_island.view().quests.pinned == nil and Everlook.smart_island.view().pinned == false)
harness.click(rect.left + rect.width / 2, rect.top + 8)
harness.advance(0.5)

-- The guess that did not survive: a clipping frame with its mouse off hides its children. The client's noroot
-- answer was the Pin button; this rule says nothing of the island would get it.
harness.rules({ clip_needs_mouse = true, flatten_clips = false })
do
	local got = report_for("noroot")
	harness.check("clip_needs_mouse is ruled out: it predicts nothing gets the mouse under noroot, the client said the Pin button (" .. got .. ")", got == "none" and observed.noroot == "pin")
end
harness.rules({})
panel:SetFrameLevel(shipped_level)

-- 2. The success: the panel at the level it now keeps, one above the island.
do
	harness.check("the panel keeps a level one above the island's (" .. shipped_level .. ")", shipped_level == island:GetFrameLevel() + 1)
	harness.check("the island is pinned again for the success checks", Everlook.smart_island.view().pinned == true)
	local got, level = report_for("")
	harness.check("success: the Pin button gets the mouse (" .. got .. ")", got == "pin")
	harness.move(x, y)
	harness.click(x, y)
	harness.advance(0.3)
	harness.check("success: pressing it pins the quest and leaves the island pinned", Everlook.smart_island.view().quests.pinned ~= nil and Everlook.smart_island.view().pinned == true)
	local release = button_with_text("Release pin")
	if release then local rx, ry = harness.center(release); harness.click(rx, ry); harness.advance(0.3) end

	-- A pane that takes the mouse does what a click beside it does, since nothing under it reaches the island now.
	local pane
	for _, frame in ipairs(harness.frames()) do
		local info = harness.info(frame)
		if info.class == "ScrollFrame" and info.visible and info.mouse_click and frame:GetScript("OnMouseUp") then pane = frame end
	end
	harness.check("a pane takes clicks and has a handler for them", pane ~= nil)
	if pane then
		local before = Everlook.smart_island.view().pinned
		local pr = harness.rect(pane)
		harness.click(pr.left + pr.width - 6, pr.top + pr.height - 6)
		harness.advance(0.3)
		harness.check("a click on empty space in a pane toggles the pin, as the island does", Everlook.smart_island.view().pinned == (not before))
	end
end
harness.rules({})
for _, e in ipairs(harness.errors()) do print("script error:", e) end

-- Hover code that never ran in the client runs now that the buttons have the mouse. It repaints when the pointer
-- crosses into a control; holding still must not keep repainting, and moving along the list must not close the island.
do
	local stats = Everlook.island_stats
	local function open_state() return Everlook.smart_island.view().mode == "open" end
	harness.move(5, 5)
	harness.advance(0.5)
	local r = harness.rect(island)
	harness.click(r.left + r.width / 2, r.top + 8)
	harness.advance(1)
	local pin_now = button_with_text("Pin")
	local px, py = harness.center(pin_now)
	harness.move(px, py)
	harness.advance(0.3)
	local before = stats.paint
	harness.advance(5)
	harness.check("holding the pointer still on a button for five seconds does not keep repainting (" .. (stats.paint - before) .. " paints)", stats.paint - before <= 5)
	local entered = stats.paint
	local crossings = 0
	for step = 0, 40 do
		harness.move(r.left + 40 + step * 8, r.top + 160 + (step % 5) * 40)
		harness.advance(0.05)
		crossings = crossings + 1
	end
	harness.advance(0.3)
	harness.check("moving over the panel for two seconds keeps the island open", open_state())
	harness.check("and repaints at most about once a crossing (" .. (stats.paint - entered) .. " paints over " .. crossings .. " moves)", stats.paint - entered <= crossings * 2)
end
for _, e in ipairs(harness.errors()) do print("script error:", e) end
