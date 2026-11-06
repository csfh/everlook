-- Shows the sparkle effect on lootable corpses and objects while the game's outlines are off
-- (Graphics: Outline Mode set to off), through the CVar outlineModeShowLootEffectWhenDisabled. The
-- CVar is the client's own (Wow.exe, Forever); it isn't in Blizzard's UI source.
local Sparkles = Everlook:NewAddon("EverlookSparkles", {
	label = "Sparkles",
	defaults = {
		lootSparkles = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookSparkles", {
	"GetCVar",
	"SetCVar",
	"GetCVarDefault",
})

local CVAR = "outlineModeShowLootEffectWhenDisabled"

-- Whether this session wrote the CVar, so turning the setting off only resets a value we wrote.
local written = false

-- SetCVar answers false for a value it refused (CVarDocumentation.lua, wow-ui-source 12.0.0).
local function write(value)
	local ok, success = pcall(SetCVar, CVAR, value)
	return ok and success ~= false
end

local function read()
	local ok, value = pcall(GetCVar, CVAR)
	if ok then return value end
end

-- The game's own default, or off when the game gives none.
local function gameDefault()
	local ok, value = pcall(GetCVarDefault, CVAR)
	if ok and type(value) == "string" then return value end
	return "0"
end

function Sparkles:Apply()
	if self.db.lootSparkles then
		-- A client without the setting is left alone.
		if read() ~= nil and write("1") then written = true end
	elseif written then
		write(gameDefault())
		written = false
	end
end

function Sparkles:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Graphics")
	page:Checkbox("lootSparkles", "Loot sparkles without outlines",
		"Shows the sparkles on corpses and objects you can loot while the game's outlines are off "
			.. "(Graphics: Outline Mode). Turning this off puts the game's default back.")
end

function Sparkles:OnEnable()
	self:Apply()
end

function Sparkles:OnSettingChanged()
	self:Apply()
end
