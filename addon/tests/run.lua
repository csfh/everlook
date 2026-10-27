local root = arg and arg[0] and arg[0]:match("(.+)[/\\]tests[/\\]run%.lua$") or "."
if root == "" then
	root = "."
end

local source = dofile(root .. "/tests/suite.lua")(root)
local failed = 0

local function check(name, condition)
	if condition then
		return
	end
	failed = failed + 1
	print("FAIL " .. name)
end

local function load_core(extra)
	local Everlook = {}
	local env = setmetatable(extra or {}, { __index = _G })
	env.EventUtil = { ContinueOnAddOnLoaded = function() end }
	for _, file in ipairs({ "world", "migrations" }) do
		local chunk = assert(loadfile(source(file)))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
	end
	return Everlook, env
end

do
	local addon = load_core()
	check("the namespace is the global Everlook, for module addons", rawget(_G, "Everlook") == addon)
	check("creature id is the entry field", addon.npcs.creature_id("Creature-0-1-0-2-448-abc") == 448)
	check("creature id can end on the entry", addon.npcs.creature_id("Creature-0-1-0-2-448") == 448)
	check("a vehicle id is read the same way", addon.npcs.creature_id("Vehicle-0-1-0-2-69") == 69)
	check("players are not creatures", addon.npcs.creature_id("Player-1-2") == nil)
	check("the same guid is read once", addon.npcs.creature_id("Creature-0-1-0-2-448-abc") == 448)
	check("an item link gives its id", addon.items.id_from_link("item:2589") == 2589)
	check("a coloured item link gives its id", addon.items.id_from_link("|cff9d9d9d|Hitem:2589::::::::1:::::::::|h[Linen Cloth]|h|r") == 2589)
	check("a link that is not an item has no id", addon.items.id_from_link("spell:133") == nil)
	local said = {}
	local talking = load_core({
		DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) said[#said + 1] = text end },
	})
	talking.say("Sold junk.")
	talking.say("")
	check("say writes one chat line with the Everlook prefix", #said == 1 and said[1] == "Everlook: Sold junk.")
	local hidden = load_core({ issecretvalue = function(value) return value == "hidden" end })
	check("a hidden value is secret", hidden.secret("hidden") == true and hidden.public("hidden") == nil)
	check("a public value comes back", hidden.public(7) == 7 and hidden.secret(7) == false)
	check("a hidden guid is not a creature", hidden.npcs.creature_id("hidden") == nil)
	check("a hidden link is not an item", hidden.items.id_from_link("hidden") == nil)
	local masked = load_core({ issecretvalue = function(value) return value == 42 end })
	check("a public number that is neither NaN nor infinite is finite",
		masked.finite(7) == true and masked.finite(0) == true and masked.finite(-2.5) == true)
	check("nil, a hidden number, NaN, the infinities and a numeric string are not finite",
		masked.finite(nil) == false and masked.finite(42) == false and masked.finite(0 / 0) == false
		and masked.finite(math.huge) == false and masked.finite(-math.huge) == false and masked.finite("7") == false)
	check("a value that is there and public is readable, false included",
		masked.readable(7) == true and masked.readable("text") == true and masked.readable(false) == true)
	check("nil and a hidden value are not readable", masked.readable(nil) == false and masked.readable(42) == false)
	local widget = { size = 3 }
	function widget:Grow(by, times) self.size = self.size + by * times; return self.size, "grown" end
	local size, word = masked.call(widget, "Grow", 2, 3)
	check("call runs a method the object has, with its arguments, and gives back what it returns", size == 9 and word == "grown")
	check("call does nothing for a method the object lacks, a value that is not a method, or no object",
		masked.call(widget, "Shrink") == nil and masked.call(widget, "size") == nil and masked.call(nil, "Grow", 1, 1) == nil and widget.size == 9)
end

do
	local addon = load_core()
	local db = {
		world = { npcs = {} }, pages = {}, journey = {}, secret = "x",
		qol = { fonts = { enabled = true }, journey = { on = true } },
		minimap = { angle = 1 }, experience = { gained = 2 }, schema = 1,
	}
	addon.migrations.run(db)
	check("the purge drops collection keys and keeps quality-of-life settings",
		db.world == nil and db.pages == nil and db.journey == nil and db.secret == nil
		and db.qol.fonts.enabled == true and db.qol.journey == nil
		and db.minimap.angle == 1 and db.experience.gained == 2)
	check("a purged file is at the current schema", db.schema == addon.migrations.current)
	addon.migrations.run(db)
	check("purging again changes nothing", db.qol.fonts.enabled == true and db.schema == addon.migrations.current)
	local newer = { schema = addon.migrations.current + 3, world = {}, qol = { fonts = {} } }
	local qol = newer.qol
	addon.migrations.run(newer)
	check("a newer file keeps its schema and its settings, and still loses the collection",
		newer.schema == addon.migrations.current + 3 and newer.qol == qol and newer.world == nil)
end

local kept = {
	"trace", "sched", "optimize", "settings_build", "module", "qol", "bags", "blizzard_settings",
	"bar_slots", "waves", "tooltips", "combat", "install", "errors", "title_fit", "overlaps",
	"quest_decide", "reward_marks", "island_contrast",
}
for _, name in ipairs(kept) do
	assert(loadfile(root .. "/tests/" .. name .. ".lua"))()(root, check)
end

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("ok")
