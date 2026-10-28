-- Where the mouse goes in the open island: every button must get a press where it sits.
harness.include("lib/game.lua")
game.quests()
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Island")
game.login()
Everlook.module.set("island", "enabled", true)
Everlook.module.set("island", "quest_context", true)
Everlook.module.set("island", "quest_plan", true)
harness.advance(1)

local function descends(frame, ancestor)
	while frame do
		if frame == ancestor then return true end
		frame = frame:GetParent()
	end
	return false
end

local function pressable()
	local list = {}
	for _, frame in ipairs(harness.frames()) do
		local info = harness.info(frame)
		if info.class == "Button" and info.visible and info.mouse_click and frame:GetScript("OnClick") then
			local rect = harness.rect(frame)
			if rect.width > 0 and rect.height > 0 then list[#list + 1] = frame end
		end
	end
	return list
end

local function lost(buttons)
	local found = {}
	for _, button in ipairs(buttons) do
		local x, y = harness.center(button)
		local top = harness.hit(x, y)
		if top ~= button and not descends(top, button) then found[#found + 1] = button end
	end
	return found
end

local island = harness.find("EverlookIsland")
Everlook.island.notify({ source = "Test", key = "one", text = "A notice", detail = "with detail",
	actions = { { id = "go", label = "Go", type = "callback", on_click = function() end },
		{ id = "later", label = "Later", type = "callback", on_click = function() end } } })
harness.advance(0.1)
local x, y = harness.center(island)
harness.click(x, y)
harness.advance(1)

local view = Everlook.island.view()
print("mode", view.mode, "size", view.width, view.height)
local buttons = pressable()
local gone = lost(buttons)
for _, button in ipairs(gone) do
	local x, y = harness.center(button)
	local top = harness.hit(x, y)
	print("lost", button:GetDebugName(), "under", top and top:GetDebugName() or "nothing")
end
harness.check("the island opened by a click is open", view.mode == "open")
harness.check("every button in it gets the mouse where it sits (" .. #buttons .. " checked)", #buttons > 3 and #gone == 0)
for _, e in ipairs(harness.errors()) do print("script error:", e) end
for _, m in ipairs(harness.missing()) do print("missing method:", m) end

-- The flow you do by hand: the pointer goes to the Pin button and presses it.
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

local pin = button_with_text("Pin quest")
harness.check("a Pin quest button is on the open island", pin ~= nil)
if pin then
	local px, py = harness.center(pin)
	harness.move(px, py)
	harness.advance(0.5)
	harness.check("the pointer on the Pin button leaves the island open", Everlook.island.view().mode == "open")
	harness.check("and the Pin button is what has the mouse", harness.hit(px, py) == pin)
	harness.click(px, py)
	harness.advance(0.3)
	harness.check("pressing it pins the quest", Everlook.island.view().quests.pinned ~= nil)
end
for _, e in ipairs(harness.errors()) do print("script error:", e) end

-- Clicking the header of a pinned island unpins it, as clicking the pill does.
local rect = harness.rect(island)
harness.click(rect.left + rect.width / 2, rect.top + 8)
harness.advance(0.3)
harness.check("a click on the open island's header unpins it", Everlook.island.view().pinned == false)
