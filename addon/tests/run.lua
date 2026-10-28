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

local kept = {
	"world", "trace", "sched", "optimize", "module", "action_shortcuts", "swing_timers", "quest_automation", "auto_loot", "friend_conveniences", "auto_repair", "sell_junk", "open_containers", "nameplate_titles", "unit_frame_names", "tooltip_cursor", "compact_chat", "flight_time", "fonts", "quest_text_size", "tracker_text_size", "useful_tooltips", "hide_clutter", "auto_responses", "chat_layout", "minimap", "settings", "radial_menu", "island", "island_actions", "island_section", "island_reaction", "island_capsule", "island_summary", "nameplates", "quest_nameplates", "island_reactions", "island_share", "bags", "blizzard_settings",
	"action_bar_slots", "minimap_coordinates", "quest_levels", "cinematic_skip", "camera_distance", "ground_effects", "take_mail", "tooltips", "combat", "install", "errors", "island_row", "overlaps",
	"reward_marks", "island_constants",
}
for _, name in ipairs(kept) do
	assert(loadfile(root .. "/tests/" .. name .. ".lua"))()(root, check, lib)
end

if failed > 0 then
	print(failed .. " failed")
	os.exit(1)
end
print("ok (" .. checked .. " checks)")
