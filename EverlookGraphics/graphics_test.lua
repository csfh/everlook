local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookGraphics")

-- A client at Graphics Quality 7 whose implied level for every graphics option is 4.
local cvars = {
	graphicsQuality = "7", raidGraphicsQuality = "5", ResampleAlwaysSharpen = "0",
}
local NAMES = { "ShadowQuality", "SSAO", "ComputeEffects", "DepthEffects", "LiquidDetail", "OutlineMode",
	"TextureResolution", "ParticleDensity", "SpellDensity", "ProjectedTextures", "ViewDistance", "EnvironmentDetail" }
for _, name in ipairs(NAMES) do
	cvars["graphics" .. name] = "4"
	cvars["raidGraphics" .. name] = "3"
end
local writes = {}
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) writes[#writes + 1] = name .. "=" .. value cvars[name] = value return true end
GetCVarDefault = function() return "0" end
local asked = {}
GetGraphicsCVarValueForQualityLevel = function(cvar, level, raid)
	asked[#asked + 1] = cvar .. ":" .. level .. ":" .. tostring(raid)
	return raid and 3 or 4
end

t.load("EverlookGraphics")
t.fire("PLAYER_LOGIN")
local G = Everlook:GetAddon("EverlookGraphics")

check(G.db.optimize == false and G.db.preset == "balanced", "starts off, on Balanced")
check(#writes == 0, "off at login: nothing is written")
check(t.has("checkbox optimize") and t.has("dropdown preset"), "page has the switch and the preset list")
local list = G.Presets()
check(#list == 2 and list[1][1] == "balanced" and list[2][1] == "performance", "two presets, Balanced first")

t.change("EverlookGraphics_optimize", true)
check(cvars.graphicsShadowQuality == "2" and cvars.graphicsSSAO == "2" and cvars.graphicsComputeEffects == "2"
	and cvars.graphicsLiquidDetail == "3" and cvars.graphicsTextureResolution == "2", "Balanced: Good effects, High water and textures")
check(cvars.raidGraphicsShadowQuality == "2" and cvars.raidGraphicsLiquidDetail == "3", "raids get the same values")
check(cvars.graphicsViewDistance == "4" and cvars.graphicsDepthEffects == "4" and cvars.ResampleAlwaysSharpen == "0",
	"Balanced leaves view distance, depth effects and sharpening alone")
check(cvars.graphicsGroundClutter == nil and cvars.graphicsLightMode == nil, "never ground clutter or secondary lighting")

t.change("EverlookGraphics_preset", "performance")
check(cvars.graphicsShadowQuality == "1" and cvars.graphicsSSAO == "0" and cvars.graphicsComputeEffects == "0"
	and cvars.graphicsDepthEffects == "0" and cvars.graphicsLiquidDetail == "0" and cvars.graphicsViewDistance == "0"
	and cvars.graphicsEnvironmentDetail == "0" and cvars.graphicsParticleDensity == "5" and cvars.graphicsSpellDensity == "0"
	and cvars.graphicsTextureResolution == "2" and cvars.ResampleAlwaysSharpen == "1", "Performance: effects off, view short, textures high")
check(cvars.raidGraphicsViewDistance == "0", "Performance covers raids too")

t.change("EverlookGraphics_preset", "balanced")
check(cvars.graphicsDepthEffects == "4" and cvars.raidGraphicsDepthEffects == "3" and cvars.graphicsViewDistance == "4",
	"back to Balanced: Performance-only options go to the Graphics Quality level")
check(cvars.ResampleAlwaysSharpen == "0", "and sharpening goes back to its default")
check(cvars.graphicsShadowQuality == "2", "while Balanced's own values stay")

t.change("EverlookGraphics_optimize", false)
check(cvars.graphicsShadowQuality == "4" and cvars.raidGraphicsShadowQuality == "3" and cvars.graphicsLiquidDetail == "4",
	"off: every option goes back to the Graphics Quality level")
local sawRaid = false
for _, entry in ipairs(asked) do if entry == "raidGraphicsShadowQuality:5:true" then sawRaid = true end end
check(sawRaid, "raid options ask with the raid Graphics Quality")

writes = {}
t.change("EverlookGraphics_optimize", false)
check(#writes == 0, "values this session didn't write are never reset")

GetGraphicsCVarValueForQualityLevel = nil
t.change("EverlookGraphics_optimize", true)
t.change("EverlookGraphics_optimize", false)
check(cvars.graphicsShadowQuality == "0", "without the quality lookup: the CVar default")

t.combat = true
writes = {}
t.change("EverlookGraphics_optimize", true)
check(#writes == 0, "nothing changes in combat")
t.combat = false
t.fire("PLAYER_REGEN_ENABLED")
check(cvars.graphicsShadowQuality == "2", "the held change lands when combat ends")

t.change("EverlookGraphics_optimize", false)
cvars.graphicsSpellDensity, cvars.raidGraphicsSpellDensity = nil, nil
t.change("EverlookGraphics_preset", "performance")
t.change("EverlookGraphics_optimize", true)
check(cvars.graphicsSpellDensity == nil, "an option this client doesn't have is left alone")

t.change("EverlookGraphics_optimize", false)
IsGraphicsSettingValueSupported = function(cvar, value) if cvar == "graphicsLiquidDetail" and value == 0 then return 2 end return 0 end
cvars.graphicsLiquidDetail, cvars.raidGraphicsLiquidDetail = "4", "3"
t.change("EverlookGraphics_optimize", true)
check(cvars.graphicsLiquidDetail == "4", "a level the game doesn't offer here is left to the player")
check(cvars.raidGraphicsLiquidDetail == "0", "while levels it offers are still set")

check(G.db.tempProbe and G.db.tempProbe.graphicsLightMode ~= nil, "TEMP: login records what the game says about secondary lighting")

t.done()
