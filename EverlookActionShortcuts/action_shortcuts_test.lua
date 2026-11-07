local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookActionShortcuts")

local hooks = {}
hooksecurefunc = function(target, method, fn)
	if type(target) == "string" then target, method, fn = _G, target, method end
	hooks[#hooks + 1] = { target = target, method = method, fn = fn }
	-- Hooks on Everlook's own functions run for real, after the function.
	if target == Everlook then
		local original = target[method]
		target[method] = function(...)
			local a, b, c = original(...)
			fn(...)
			return a, b, c
		end
	end
end
local function runHook(method, target, ...)
	for _, hook in ipairs(hooks) do
		if hook.method == method and (target == nil or hook.target == target) then hook.fn(...) end
	end
end

local ARIAL = "Fonts\\ARIALN.TTF"
-- The labels' font: Arial Narrow 12, outlined, no shadow (Blizzard_Fonts_Shared, 12.0.0).
NumberFontNormalSmallGray = {
	GetFont = function() return ARIAL, 12, "OUTLINE" end,
	GetShadowOffset = function() return 0, 0 end,
	GetShadowColor = function() return 0, 0, 0, 0 end,
}
RANGE_INDICATOR = "●"

-- A HotKey font string: it follows its font object until SetFont gives it one of its own.
local function label(text)
	local l = { text = text, object = NumberFontNormalSmallGray, sets = 0, draws = 0, shadow = { 0, 0 }, alpha = 0 }
	function l:GetText() return self.text end
	function l:SetText(value) self.text = value self.draws = self.draws + 1 end
	function l:GetFont()
		if self.path then return self.path, self.size, self.flags end
		return self.object.GetFont()
	end
	function l:SetFont(path, size, flags)
		self.path, self.size, self.flags = path, size, flags
		self.sets = self.sets + 1
	end
	function l:SetFontObject(object) self.object, self.path, self.size, self.flags = object, nil, nil, nil end
	function l:SetShadowOffset(x, y) self.shadow = { x, y } end
	function l:SetShadowColor(_, _, _, a) self.alpha = a end
	return l
end

local function button(text)
	local b = { HotKey = label(text) }
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
runHook("UpdateHotkeys", buttons[1], buttons[1])
check(text(1) == "S9", "a binding refresh keeps the short form")

-- A button registered later is shortened too.
local late = button("a-1")
runHook("RegisterFrame", nil, ActionBarButtonEventsFrame, late)
check(late.HotKey:GetText() == "A1", "a new button is shortened")

buttons[2].HotKey:SetText("custom")
t.change("EverlookActionShortcuts_shorten", false)
check(text(1) == "s-9" and text(3) == "s-a-6", "turning it off puts the labels back")
check(text(2) == "custom", "a label something else changed is left alone")

check(A.Shorten("S-a-F1") == "SAF1", "Shorten handles either case and multi-character keys")

-- Styling the labels: off at first, and then the labels are the game's.
local hotkey = buttons[1].HotKey
check(A.db.style == false and hotkey.sets == 0, "styling starts off and leaves the labels alone")
local order = {}
for _, variable in ipairs({ "shorten", "style", "font", "size", "outline", "shadow" }) do
	order[#order + 1] = t.settings["EverlookActionShortcuts_" .. variable] and variable or "-"
end
check(table.concat(order, " ") == "shorten style font size outline shadow", "the switch and its four controls exist")

t.change("EverlookActionShortcuts_style", true)
check(hotkey.path == ARIAL and hotkey.size == 12 and hotkey.flags == "OUTLINE",
	"on with every control at its default: the game's font, size and outline")
local draws = hotkey.draws
t.change("EverlookActionShortcuts_size", 16)
t.change("EverlookActionShortcuts_outline", "thick")
t.change("EverlookActionShortcuts_shadow", "strong")
check(hotkey.size == 16 and hotkey.flags == "THICKOUTLINE" and hotkey.shadow[1] == 2 and hotkey.shadow[2] == -2
	and hotkey.alpha == 1, "size, thick outline and a strong shadow")
check(hotkey.draws > draws and hotkey.text == "s-9", "each change sets the text again, so the label redraws")
t.change("EverlookActionShortcuts_outline", "none")
check(hotkey.flags == "", "no outline")

local EXPRESSWAY = "Interface\\AddOns\\EverlookFonts\\assets\\expressway.ttf"
Everlook.SetFontToken("Number", EXPRESSWAY)
t.change("EverlookActionShortcuts_font", "Number")
check(hotkey.path == EXPRESSWAY and hotkey.size == 16, "a token's font, at the chosen size")
draws = hotkey.draws
Everlook.SetFontToken("Number", "Interface\\AddOns\\EverlookFonts\\assets\\inter.ttf")
check(hotkey.path:find("inter.ttf") and hotkey.draws > draws, "the token's new font shows at once, and the label redraws")

-- The range dot shows only in the game's font.
hotkey:SetText(RANGE_INDICATOR)
runHook("UpdateHotkeys", buttons[1], buttons[1])
check(hotkey.path == ARIAL and hotkey.size == 16, "the range dot keeps the game's font, at the chosen size")
hotkey:SetText("S4")
runHook("UpdateHotkeys", buttons[1], buttons[1])
check(hotkey.path:find("inter.ttf"), "a key bound again: the token's font is back")

-- Combat holds changes back until it ends.
t.combat = true
t.change("EverlookActionShortcuts_size", 10)
check(hotkey.size == 16, "in combat a change waits")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(hotkey.size == 10, "and shows once combat ends")

-- Off: the labels follow the game's font object again, redrawn.
draws = hotkey.draws
t.change("EverlookActionShortcuts_style", false)
check(hotkey.path == nil and hotkey.object == NumberFontNormalSmallGray and hotkey:GetFont() == ARIAL
	and select(2, hotkey:GetFont()) == 12 and hotkey.shadow[1] == 0 and hotkey.draws > draws,
	"off: every label has the game's font, size, outline and shadow back, redrawn")
local sets = hotkey.sets
runHook("UpdateHotkeys", buttons[1], buttons[1])
Everlook.SetFontToken("Number", nil)
check(hotkey.sets == sets, "and stays untouched by bindings and tokens")

t.done()
