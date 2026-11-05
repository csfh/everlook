local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookActionShortcuts")

local hooks = {}
hooksecurefunc = function(target, method, fn)
	hooks[#hooks + 1] = { target = target, method = method, fn = fn }
end

local function button(text)
	local hotkey = t.widget()
	hotkey:SetText(text)
	local b = { HotKey = hotkey }
	function b:UpdateHotkeys() end
	return b
end
local buttons = { button("s-4"), button("a-5"), button("s-a-6"), button("c-7"), button("8") }
ActionBarButtonEventsFrame = {
	ForEachFrame = function(_, fn) for _, b in ipairs(buttons) do fn(b) end end,
	RegisterFrame = function() end,
}

t.load("EverlookActionShortcuts")
t.fire("PLAYER_LOGIN")
local A = Everlook:GetAddon("EverlookActionShortcuts")

local function text(i) return buttons[i].HotKey:GetText() end
check(A.db.shorten == true, "starts on")
check(text(1) == "S4" and text(2) == "A5" and text(3) == "SA6", "Shift and Alt are shortened")
check(text(4) == "c-7" and text(5) == "8", "Ctrl and plain keys stay as they are")

-- Blizzard rewrites the label on a binding refresh; the hook shortens it again.
buttons[1].HotKey:SetText("s-9")
for _, hook in ipairs(hooks) do
	if hook.method == "UpdateHotkeys" and hook.target == buttons[1] then hook.fn(buttons[1]) end
end
check(text(1) == "S9", "a binding refresh keeps the short form")

-- A button registered later is shortened too.
local late = button("a-1")
for _, hook in ipairs(hooks) do
	if hook.method == "RegisterFrame" then hook.fn(ActionBarButtonEventsFrame, late) end
end
check(late.HotKey:GetText() == "A1", "a new button is shortened")

buttons[2].HotKey:SetText("custom")
t.change("EverlookActionShortcuts_shorten", false)
check(text(1) == "s-9" and text(3) == "s-a-6", "turning it off puts the labels back")
check(text(2) == "custom", "a label something else changed is left alone")

check(A.Shorten("S-a-F1") == "SAF1", "Shorten handles either case and multi-character keys")

t.done()
