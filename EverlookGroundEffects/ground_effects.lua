local GroundEffects = Everlook:NewAddon("EverlookGroundEffects", {
	label = "Ground Effects",
	defaults = {
		density = false,
		densityValue = 256,
		distance = false,
		distanceValue = 500,
		fade = false,
		fadeValue = 500,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookGroundEffects", {
	"GetCVar",
	"SetCVar",
	"GetCVarDefault",
})

-- Each checkbox sets one ground clutter CVar to the slider beneath it.
local CVARS = {
	{ key = "density", cvar = "groundEffectDensity" },
	{ key = "distance", cvar = "groundEffectDist" },
	{ key = "fade", cvar = "groundEffectFade" },
}

-- The CVars this session wrote, so turning a checkbox off only resets a value we wrote.
local written = {}

-- SetCVar answers false for a value it refused (CVarDocumentation.lua, wow-ui-source 12.0.0).
local function write(cvar, value)
	local ok, success = pcall(SetCVar, cvar, value)
	return ok and success ~= false
end

local function read(cvar)
	local ok, value = pcall(GetCVar, cvar)
	if ok then return value end
end

-- The game's own default, or this addon's when the game gives none.
local function gameDefault(entry)
	local ok, value = pcall(GetCVarDefault, entry.cvar)
	if ok and type(value) == "string" then return value end
	return tostring(GroundEffects.defaults[entry.key .. "Value"])
end

function GroundEffects:Apply()
	for _, entry in ipairs(CVARS) do
		if self.db[entry.key] then
			-- A setting this client doesn't have is left alone.
			if read(entry.cvar) ~= nil and write(entry.cvar, tostring(self.db[entry.key .. "Value"])) then
				written[entry.cvar] = true
			end
		elseif written[entry.cvar] then
			write(entry.cvar, gameDefault(entry))
			written[entry.cvar] = nil
		end
	end
end

function GroundEffects:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Graphics")
	page:Checkbox("density", "Change ground clutter density",
		"Set how much ground clutter, such as grass, the game draws. Turning this off puts the game's default back.")
	page:Slider("densityValue", "Ground clutter density", "A higher number draws more.", 0, 512, 16)
	page:Checkbox("distance", "Change ground clutter distance",
		"Set how far from you ground clutter is drawn. Turning this off puts the game's default back.")
	page:Slider("distanceValue", "Ground clutter distance", "A higher number draws it farther out.", 0, 1000, 25)
	page:Checkbox("fade", "Change ground clutter fade",
		"Set how far out ground clutter fades away. Turning this off puts the game's default back.")
	page:Slider("fadeValue", "Ground clutter fade", "A higher number fades it farther out.", 0, 1000, 25)
end

function GroundEffects:OnEnable()
	self:Apply()
end

function GroundEffects:OnSettingChanged()
	self:Apply()
end
