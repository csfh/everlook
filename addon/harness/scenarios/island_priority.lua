-- Which notice gets a toast first when several wait: an error before a warning before a routine notice, a newer
-- notice outranking only what is lower, and the order kept among equals. Nothing here depends on the clock's speed.
harness.include("lib/game.lua")
game.quests()
harness.load_addon("Everlook")
harness.load_addon("Everlook_Fonts")
harness.load_addon("Everlook_Island")
game.login()
if EverlookMinimapButton then EverlookMinimapButton:Hide() end
Everlook.module.set("island", "enabled", true)
Everlook.module.set("island", "toast_count", 1)
harness.advance(1)

local function view() return Everlook.island.view() end
local function texts(list)
	local names = {}
	for index, entry in ipairs(list) do names[index] = entry.text end
	return table.concat(names, ",")
end
local function notify(text, severity)
	Everlook.island.notify({ source = "Priority", key = text, text = text, severity = severity, duration = 8 })
end

notify("A routine")
harness.advance(0.5)
harness.check("the first notice takes the only toast", texts(view().toasts) == "A routine")

notify("B routine")
notify("C warning", "warning")
notify("D routine")
harness.advance(0.2)
harness.check("notices that wait for the toast keep the order they came in", texts(view().queue) == "B routine,C warning,D routine")
harness.check("a routine notice does not push out the one showing", texts(view().toasts) == "A routine")

notify("E error", "error")
harness.advance(1)
harness.check("an error takes the toast from a routine notice that is showing", texts(view().toasts) == "E error")

harness.advance(10)
harness.check("when it ends the warning is next, ahead of the routine notice that waited longer", texts(view().toasts) == "C warning")

-- Fill the queue to its limit, then send notices that outrank only some of it.
harness.advance(30)
notify("Showing")
harness.advance(0.5)
for _, name in ipairs({ "Q1", "Q2", "Q3", "Q4", "Q5" }) do notify(name) end
harness.advance(0.2)
harness.check("the queue holds five", texts(view().queue) == "Q1,Q2,Q3,Q4,Q5")
notify("Q6")
harness.advance(0.2)
harness.check("a routine notice that finds the queue full of routine notices waits only in the inbox", texts(view().queue) == "Q1,Q2,Q3,Q4,Q5")
notify("W warning", "warning")
harness.advance(0.2)
harness.check("a warning takes the place of the first routine notice waiting", texts(view().queue) == "Q2,Q3,Q4,Q5,W warning")
