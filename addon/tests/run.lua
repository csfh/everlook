-- Runs every suite against the addon folders beside tests/, or in the folder given as the first argument, such as an
-- unpacked release.
local addon = arg and arg[0] and arg[0]:match("(.+)[/\\]tests[/\\]run%.lua$") or "."
if addon == "" then
	addon = "."
end
local tests = addon .. "/tests"
local root = arg and arg[1] or addon
assert(io.open(root .. "/Everlook/Everlook.toc", "r"), "No addon at " .. root .. ": run.lua needs a folder that holds Everlook/"):close()

local lib = dofile(tests .. "/lib/worlds.lua")(tests, root)
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
	"island_buffs",
	"island_capsule",
	"island_constants",
	"island_experience",
	"island_history",
	"island_inbox",
	"island_invites",
	"island_mail",
	"island_notice",
	"island_quests",
	"island_reaction",
	"island_reactions",
	"island_recap",
	"island_reputation",
	"island_row",
	"island_scroll",
	"island_section",
	"island_share",
	"island_summary",
	"island_surface",
	"island_toasts",
	"island_vitals",
	"island_warnings",
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
	assert(loadfile(tests .. "/" .. name .. ".lua"))()(check, lib)
end

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("ok (" .. checked .. " checks)")
