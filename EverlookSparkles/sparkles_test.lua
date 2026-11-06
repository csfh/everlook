local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookSparkles")

local CVAR = "outlineModeShowLootEffectWhenDisabled"
local cvars = { [CVAR] = "0" }
local writes = 0
GetCVar = function(name) return cvars[name] end
SetCVar = function(name, value) writes = writes + 1 cvars[name] = value return true end
GetCVarDefault = function(name) if name == CVAR then return "0" end end

t.load("EverlookSparkles")
t.fire("PLAYER_LOGIN")
local S = Everlook:GetAddon("EverlookSparkles")

check(not S.db.lootSparkles and writes == 0, "starts off and changes nothing at login")
check(t.has("checkbox lootSparkles"), "the page has its checkbox")

t.change("EverlookSparkles_lootSparkles", true)
check(cvars[CVAR] == "1", "on: loot sparkles show while outlines are off")

t.change("EverlookSparkles_lootSparkles", false)
check(cvars[CVAR] == "0", "off: the game's default is back")

-- Off when it never wrote the CVar: the player's own value stays.
cvars[CVAR] = "1"
writes = 0
S:Apply()
check(writes == 0 and cvars[CVAR] == "1", "off, it leaves a value it didn't write alone")

-- A client without the setting is left alone.
cvars[CVAR] = nil
t.change("EverlookSparkles_lootSparkles", true)
check(cvars[CVAR] == nil, "a client without the CVar is left alone")

-- A refused value isn't counted as written, so off doesn't reset anything.
cvars[CVAR] = "0"
SetCVar = function() return false end
t.change("EverlookSparkles_lootSparkles", false)
t.change("EverlookSparkles_lootSparkles", true)
writes = 0
SetCVar = function(name, value) writes = writes + 1 cvars[name] = value return true end
t.change("EverlookSparkles_lootSparkles", false)
check(writes == 0, "a value the game refused isn't reset when turned off")

t.done()
