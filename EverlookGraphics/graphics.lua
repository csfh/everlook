local Graphics = Everlook:NewAddon("EverlookGraphics", {
	label = "Graphics",
	defaults = {
		optimize = false,
		preset = "balanced",
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookGraphics", {
	"GetCVar",
	"SetCVar",
	"GetCVarDefault",
	"InCombatLockdown",
}, {
	"GetGraphicsCVarValueForQualityLevel",
	"IsGraphicsSettingValueSupported",
})

-- Levels are the indexes of the game's own Graphics Quality dropdowns (Graphics.lua and
-- GraphicsOverrides.lua, wow-ui-source 12.0.0): shadows 0 Low, 1 Fair, 2 Good, 3 High; SSAO and
-- compute effects 0 Disabled, 2 Good; liquid detail 0 Low, 3 High; textures 2 High; spell density
-- 0 Essential; view distance and environment detail 0 is the slider's 1. Each graphics value is
-- written for raids too (raidGraphics...), so the raid settings can't undo it.
-- Ground clutter is left to Everlook Ground Effects, and the field of view is never touched.
-- Forever's Secondary Lighting (graphicsLightMode) isn't in wow-ui-source and its levels aren't
-- known, so neither preset sets it.
local PRESETS = {
	-- From Bellular's WoW Forever graphics tests (28 Oct 2026): Good is where the new shadows, fog
	-- and ambient occlusion stop paying for themselves; water and textures cost almost nothing.
	balanced = {
		label = "Balanced: keeps the new lighting, fog and water",
		graphics = {
			graphicsShadowQuality = 2,
			graphicsSSAO = 2,
			graphicsComputeEffects = 2,
			graphicsLiquidDetail = 3,
			graphicsTextureResolution = 2,
		},
	},
	-- From EllesmereUI's Optimize My FPS: everything that costs frames off or lowest, textures kept
	-- high and particles kept at Ultra so spell effects stay readable.
	performance = {
		label = "Performance: the most frames, a plainer world",
		graphics = {
			graphicsShadowQuality = 1,
			graphicsSSAO = 0,
			graphicsComputeEffects = 0,
			graphicsDepthEffects = 0,
			graphicsLiquidDetail = 0,
			graphicsOutlineMode = 0,
			graphicsTextureResolution = 2,
			graphicsParticleDensity = 5,
			graphicsSpellDensity = 0,
			graphicsProjectedTextures = 1,
			graphicsViewDistance = 0,
			graphicsEnvironmentDetail = 0,
		},
		other = {
			ResampleAlwaysSharpen = 1,
		},
	},
}
local ORDER = { "balanced", "performance" }

-- Every CVar a preset sets, as cvar -> { value, raid } per preset, built once.
local values = {} -- [preset][cvar] = value
local raidOf = {} -- [cvar] = true for the raid copies
local all = {} -- every cvar any preset touches, in a fixed order
do
	local seen = {}
	local function add(preset, cvar, value, raid)
		values[preset][cvar] = value
		if raid then raidOf[cvar] = true end
		if not seen[cvar] then
			seen[cvar] = true
			all[#all + 1] = cvar
		end
	end
	for _, name in ipairs(ORDER) do
		values[name] = {}
		local preset = PRESETS[name]
		local graphics = {}
		for cvar in pairs(preset.graphics) do graphics[#graphics + 1] = cvar end
		table.sort(graphics)
		for _, cvar in ipairs(graphics) do
			add(name, cvar, preset.graphics[cvar], false)
			add(name, "raidG" .. cvar:sub(2), preset.graphics[cvar], true)
		end
		local other = {}
		for cvar in pairs(preset.other or {}) do other[#other + 1] = cvar end
		table.sort(other)
		for _, cvar in ipairs(other) do add(name, cvar, preset.other[cvar], false) end
	end
end

-- The CVars this session wrote, so turning this off only resets values we wrote.
local written = {}
-- A change combat held back; PLAYER_REGEN_ENABLED applies it.
local pending = false

-- SetCVar answers false for a value it refused (CVarDocumentation.lua, wow-ui-source 12.0.0).
local function write(cvar, value)
	local ok, success = pcall(SetCVar, cvar, tostring(value))
	return ok and success ~= false
end

local function read(cvar)
	local ok, value = pcall(GetCVar, cvar)
	if ok then return value end
end

-- Whether the game offers this level on this machine. Its own dropdowns grey out a level when
-- IsGraphicsSettingValueSupported names an error (ErrorMessages[error] in Graphics.lua); a level
-- the game rules out, or one it can't vouch for, is left to the player.
local function supported(cvar, value)
	if not (cvar:find("^graphics") or cvar:find("^raidGraphics")) then return true end
	if not IsGraphicsSettingValueSupported then return true end
	local ok, problem = pcall(IsGraphicsSettingValueSupported, cvar, value, raidOf[cvar] == true)
	if not ok then return false end
	return not (type(problem) == "number" and problem > 0)
end

-- What the game itself would use: for a graphics setting, the level the Graphics Quality slider
-- implies (OnGCChanged in Graphics.lua does the same); else the CVar's default.
local function gameValue(cvar)
	if cvar:find("^graphics") or cvar:find("^raidGraphics") then
		local raid = raidOf[cvar] == true
		local quality = tonumber(read(raid and "raidGraphicsQuality" or "graphicsQuality"))
		if quality and GetGraphicsCVarValueForQualityLevel then
			local ok, value = pcall(GetGraphicsCVarValueForQualityLevel, cvar, quality, raid)
			if ok and value ~= nil then return value end
		end
	end
	local ok, value = pcall(GetCVarDefault, cvar)
	if ok and type(value) == "string" then return value end
end

function Graphics:Apply()
	-- Graphics changes wait for combat to end, as EllesmereUI's do, so a frame drop never lands mid-fight.
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	local chosen = self.db.optimize and (values[self.db.preset] or values.balanced) or {}
	for _, cvar in ipairs(all) do
		local value = chosen[cvar]
		if value ~= nil then
			-- A setting this client doesn't have is left alone. While on, every value the preset
			-- names is this addon's to reset, even one that already matched.
			local current = read(cvar)
			if current ~= nil and (tostring(current) == tostring(value)
				or (supported(cvar, value) and write(cvar, value))) then
				written[cvar] = true
			end
		elseif written[cvar] then
			local default = gameValue(cvar)
			if default ~= nil then write(cvar, default) end
			written[cvar] = nil
		end
	end
end

function Graphics.Presets()
	local list = {}
	for _, name in ipairs(ORDER) do list[#list + 1] = { name, PRESETS[name].label } end
	return list
end

function Graphics:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Graphics")
	page:Checkbox("optimize", "Use optimized graphics settings",
		"Set the game's graphics options to the preset below while this is on, for raids too. "
			.. "Turning this off puts each option back where your Graphics Quality slider sets it.")
	page:Dropdown("preset", "Optimized preset",
		"Balanced puts shadows, ambient occlusion and fog on Good and keeps water and textures on High. "
			.. "Performance turns those effects off and shortens the view distance for the most frames. "
			.. "Neither changes ground clutter, the field of view or render scale.",
		Graphics.Presets)
end

-- TEMP: Forever's Secondary Lighting and new water aren't in wow-ui-source. This records what the
-- game says about them so a later preset can set them: current values, which levels 0-5 it accepts,
-- and what each Graphics Quality level (1-10) puts them at.
local PROBE = { "graphicsLightMode", "giQuality", "graphicsLiquidDetail", "graphicsPBRLiquidDetail", "pbrLiquidDetail" }
local function probe()
	local record = {}
	for _, cvar in ipairs(PROBE) do
		local entry = { current = read(cvar), accepts = {}, byQuality = {} }
		if IsGraphicsSettingValueSupported then
			for level = 0, 5 do
				local ok, problem = pcall(IsGraphicsSettingValueSupported, cvar, level, false)
				entry.accepts[level + 1] = ok and tostring(problem) or "error"
			end
		end
		if GetGraphicsCVarValueForQualityLevel then
			for quality = 1, 10 do
				local ok, value = pcall(GetGraphicsCVarValueForQualityLevel, cvar, quality, false)
				entry.byQuality[quality] = ok and tostring(value) or "error"
			end
		end
		record[cvar] = entry
	end
	return record
end

function Graphics:OnEnable()
	self.db.tempProbe = probe()
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if pending then self:Apply() end
	end)
	self:Apply()
end

function Graphics:OnSettingChanged()
	self:Apply()
end
