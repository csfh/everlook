-- Things a player does with the island, done with the pointer, the key and the clock.
harness.include("lib/game.lua")
game.quests()
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Island")
game.login()
if EverlookMinimapButton then EverlookMinimapButton:Hide() end
Everlook.module.set("island", "enabled", true)
harness.advance(1)

local island = harness.find("EverlookIsland")
local function view() return Everlook.island.view() end

local function frame_with_text(text, wanted)
	local found
	for _, frame in ipairs(harness.frames()) do
		if harness.info(frame).visible then
			for _, region in ipairs({ frame:GetRegions() }) do
				if region.GetText and region:GetText() == text then
					local walker = frame
					while walker and wanted and not wanted(walker) do walker = walker:GetParent() end
					if walker then found = walker end
				end
			end
		end
	end
	return found
end
local function has_script(name) return function(frame) return frame:GetScript(name) ~= nil end end

-- A toast takes a right click to go away.
do
	local fired = 0
	Everlook.island.notify({ source = "Flows", key = "toast", text = "Right click me", duration = 20,
		actions = { { id = "go", label = "Go", type = "callback", on_click = function() fired = fired + 1 end } } })
	harness.advance(1)
	harness.check("a toast is up", #view().toasts == 1)
	local card = frame_with_text("Right click me", has_script("OnMouseUp"))
	harness.check("the toast card takes the mouse", card ~= nil)
	if card then
		local x, y = harness.center(card)
		harness.click(x, y, "RightButton")
		harness.advance(1.5)
		harness.check("a right click on it takes it away", #view().toasts == 0)
	end
	-- Its action is a button of its own.
	Everlook.island.notify({ source = "Flows", key = "toast2", text = "Press my button", duration = 20,
		actions = { { id = "go", label = "Go", type = "callback", on_click = function() fired = fired + 1 end } } })
	harness.advance(1)
	local go = frame_with_text("Go", has_script("OnClick"))
	harness.check("the toast's action is a button", go ~= nil)
	if go then
		local x, y = harness.center(go)
		harness.click(x, y)
		harness.advance(0.5)
		harness.check("pressing it runs the producer's callback once", fired == 1)
	end
	Everlook.island.dismiss(Everlook.island.notify({ source = "Flows", key = "end", text = "x", duration = 1 }))
	harness.advance(25)
end

-- Hovering opens it, moving onto what is inside keeps it open, leaving closes it.
do
	local rect = harness.rect(island)
	local x, y = rect.left + rect.width / 2, rect.top + rect.height / 2
	harness.move(5, 5)
	harness.advance(0.5)
	harness.check("with the pointer away the island is closed", view().mode == "closed")
	harness.move(x, y)
	harness.advance(0.5)
	harness.check("the pointer on the pill opens it", view().mode == "open")
	local open = harness.rect(island)
	harness.move(open.left + open.width / 2, open.top + open.height - 20)
	harness.advance(0.5)
	harness.check("moving deeper into the open island keeps it open", view().mode == "open")
	harness.move(5, 5)
	harness.advance(0.5)
	harness.check("moving away closes it", view().mode == "closed")
end

-- A capsule that is still easing when the island is opened by its key does not leave it pill-sized.
do
	Everlook.island.notify({ source = "Flows", key = "ease", presentation = "status", text = "Easing", capsule = { text = "Easing", icon = "flight" } })
	harness.advance(0.05)
	everlook_island_key("down")
	harness.advance(1)
	local v = view()
	harness.check("opened by its key mid-ease it is as large as its panes", v.mode == "open" and v.shell.width == v.width and v.shell.height == v.height)
	everlook_island_key("up")
	harness.advance(1)
end

-- A section from another addon: its row shows, and its action runs when pressed.
do
	local ran = 0
	Everlook.island.section({ source = "Flows", key = "bosses", region = "pane_b", title = "Bosses",
		blocks = { { kind = "row", row = { title = "Ragnaros", labels = { "3/8" } },
			action = { id = "mark", label = "Mark", on_click = function() ran = ran + 1 end } } } })
	local rect = harness.rect(island)
	harness.click(rect.left + rect.width / 2, rect.top + 8)
	harness.advance(1)
	harness.check("the section's row is on the open island", frame_with_text("Ragnaros") ~= nil)
	local mark = frame_with_text("Mark", has_script("OnClick"))
	harness.check("its action is a button", mark ~= nil)
	if mark then
		local x, y = harness.center(mark)
		harness.move(x, y)
		harness.advance(0.2)
		harness.check("with the pointer on it the island stays open", view().mode == "open")
		harness.click(x, y)
		harness.advance(0.2)
		harness.check("pressing it runs the action once", ran == 1)
	end
end

for _, e in ipairs(harness.errors()) do print("script error:", e) end
