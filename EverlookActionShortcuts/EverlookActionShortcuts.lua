local ActionShortcuts = Everlook:NewAddon("EverlookActionShortcuts", {
	label = "Action Shortcuts",
	defaults = {
		shorten = true,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookActionShortcuts", {
	"ActionBarButtonEventsFrame.ForEachFrame",
	"ActionBarButtonEventsFrame.RegisterFrame",
	"hooksecurefunc",
})

-- Blizzard_ActionBar/Shared/ActionButton.lua (12.0.0) registers each button with
-- ActionBarButtonEventsFrame and writes its HotKey text in UpdateHotkeys.
local hookedButtons = setmetatable({}, { __mode = "k" })
local managerHooked = false
local labels = setmetatable({}, { __mode = "k" }) -- [HotKey font string] = { original, applied }

local function readable(text)
	return not (issecretvalue and issecretvalue(text)) and type(text) == "string"
end

-- "s-a-4" -> "SA4", "s-4" -> "S4". Ctrl and labels without Shift or Alt stay as they are.
function ActionShortcuts.Shorten(text)
	local prefix, key = "", text
	while true do
		local modifier, rest = key:match("^([sSaA])%-(.+)$")
		if not modifier then break end
		prefix, key = prefix .. modifier:upper(), rest
	end
	return prefix .. key
end

local function compact(button)
	local font = button.HotKey
	if not font or type(font.GetText) ~= "function" or type(font.SetText) ~= "function" then return end
	local text = font:GetText()
	if not readable(text) then return end
	local short = ActionShortcuts.Shorten(text)
	if short == text then return end
	labels[font] = { original = text, applied = short }
	font:SetText(short)
end

local function attach(button)
	if type(button.UpdateHotkeys) ~= "function" then return end
	if not hookedButtons[button] then
		-- The mixin was copied onto existing buttons, so each button is hooked, keeping the
		-- short label through Blizzard's UPDATE_BINDINGS refresh.
		hooksecurefunc(button, "UpdateHotkeys", function(self)
			if ActionShortcuts.db.shorten then compact(self) end
		end)
		hookedButtons[button] = true
	end
	compact(button)
end

-- Puts back each label we shortened, unless something else changed it since.
local function restore()
	for font, state in pairs(labels) do
		local text = font:GetText()
		if readable(text) and text == state.applied then font:SetText(state.original) end
		labels[font] = nil
	end
end

function ActionShortcuts:Apply()
	if not self.db.shorten then
		restore()
		return
	end
	local manager = ActionBarButtonEventsFrame
	if not manager or type(manager.ForEachFrame) ~= "function" or type(manager.RegisterFrame) ~= "function" then return end
	if not managerHooked then
		hooksecurefunc(manager, "RegisterFrame", function(_, button)
			if self.db.shorten then attach(button) end
		end)
		managerHooked = true
	end
	manager:ForEachFrame(attach)
end

function ActionShortcuts:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Action Bars")
	page:Checkbox("shorten", "Shorten hotkey labels",
		"Show Shift and Alt on action bar hotkeys as S and A, so s-4 reads S4 and s-a-4 reads SA4.")
end

function ActionShortcuts:OnEnable()
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Apply")
	self:RegisterEvent("ADDON_LOADED", function(_, name)
		if name == "Blizzard_ActionBar" then self:Apply() end
	end)
	self:Apply()
end

function ActionShortcuts:OnSettingChanged()
	self:Apply()
end
