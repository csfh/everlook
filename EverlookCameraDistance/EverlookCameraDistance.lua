local CameraDistance = Everlook:NewAddon("EverlookCameraDistance", {
	label = "Camera Distance",
	defaults = {
		change = true,
		distance = 2.6,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookCameraDistance", {
	"GetCVar",
	"SetCVar",
	"GetCVarDefault",
})

local CVAR = "cameraDistanceMaxZoomFactor"

-- Whether this session set the factor, so turning this off only resets a value we wrote.
local written = false

-- SetCVar answers false for a value it refused (CVarDocumentation.lua, wow-ui-source 12.0.0).
local function write(value)
	local ok, success = pcall(SetCVar, CVAR, value)
	return ok and success ~= false
end

-- The game's own default, or this addon's when the game gives none.
local function gameDefault()
	local ok, value = pcall(GetCVarDefault, CVAR)
	if ok and type(value) == "string" then return value end
	return tostring(CameraDistance.defaults.distance)
end

function CameraDistance:Apply()
	if self.db.change then
		-- A setting this client doesn't have is left alone.
		if GetCVar(CVAR) == nil then return end
		if write(tostring(self.db.distance)) then written = true end
	elseif written then
		write(gameDefault())
		written = false
	end
end

function CameraDistance:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "World & Camera")
	page:Checkbox("change", "Change maximum camera distance",
		"Let the camera zoom out to the distance below. Turning this off puts the game's default back.")
	page:Slider("distance", "Maximum camera distance", "How far out the camera can zoom, from 100% to 400%.",
		1, 4, 0.1, EverlookPreferences.Percent)
end

function CameraDistance:OnEnable()
	self:Apply()
end

function CameraDistance:OnSettingChanged()
	self:Apply()
end
