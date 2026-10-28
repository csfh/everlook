local root = arg and arg[0] and arg[0]:match("(.+)[/\\]tests[/\\]run%.lua$") or "."
if root == "" then
	root = "."
end

local lib = dofile(root .. "/tests/lib/worlds.lua")(root)
local failed, checked = 0, 0

local function check(name, condition)
	checked = checked + 1
	if condition then
		return
	end
	failed = failed + 1
	print("FAIL " .. name)
end

-- Every suite, one per test file, each named for the core file, module, module part or Island extension it tests.
local suites = {
	"action_bar_slots",
	"action_shortcuts",
	"auto_loot",
	"auto_repair",
	"auto_responses",
	"bags",
	"blizzard_settings",
	"camera_distance",
	"chat_layout",
	"cinematic_skip",
	"combat",
	"compact_chat",
	"errors",
	"flight_time",
	"fonts",
	"friend_conveniences",
	"ground_effects",
	"hide_clutter",
	"install",
	"island",
	"island_actions",
	"island_capsule",
	"island_constants",
	"island_reaction",
	"island_reactions",
	"island_row",
	"island_section",
	"island_share",
	"island_summary",
	"minimap",
	"minimap_coordinates",
	"module",
	"nameplate_titles",
	"nameplates",
	"open_containers",
	"optimize",
	"overlaps",
	"quest_automation",
	"quest_levels",
	"quest_nameplates",
	"quest_text_size",
	"radial_menu",
	"reward_marks",
	"sched",
	"sell_junk",
	"settings",
	"swing_timers",
	"take_mail",
	"tooltip_cursor",
	"tooltips",
	"trace",
	"tracker_text_size",
	"unit_frame_names",
	"useful_tooltips",
	"world",
}
for _, name in ipairs(suites) do
	assert(loadfile(root .. "/tests/" .. name .. ".lua"))()(root, check, lib)
end

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("ok (" .. checked .. " checks)")
