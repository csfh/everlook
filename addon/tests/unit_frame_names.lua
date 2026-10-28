-- Unit frame names: adds the points on Extra points to the player and target names on the default unit frames, and grows each name's region so the larger text is not clipped.
return function(root, check, lib)
	local load_all = lib.load_all
	local names, name_env, name_event = load_all()
	local function name_font(size, height)
		local font = { path = "Fonts\\FRIZQT__.TTF", size = size, flags = "", height = height }
		function font:GetFont() return self.path, self.size, self.flags end
		function font:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
		function font:GetHeight() return self.height end
		function font:SetHeight(height) self.height = height end
		return font
	end
	local player_name = name_font(10, 12)
	local target_name = name_font(10, 12)
	local tot_name = name_font(10, 12)
	name_env.PlayerName = player_name
	name_env.TargetFrame = {
		TargetFrameContent = { TargetFrameContentMain = { Name = target_name } },
		totFrame = { Name = tot_name },
	}
	name_event("PLAYER_ENTERING_WORLD")
	check("unit names stay at the stock size while the module is off", player_name.size == 10 and target_name.size == 10 and tot_name.size == 10)
	name_env.InCombatLockdown = function() return true end
	names.module.set("unit_frame_names", "enabled", true)
	check("combat leaves the unit names alone", player_name.size == 10 and target_name.height == 12)
	name_env.InCombatLockdown = function() return false end
	name_event("PLAYER_REGEN_ENABLED")
	check("leaving combat enlarges the player and target names",
		player_name.size == 14 and player_name.height == 14 and target_name.size == 14 and target_name.height == 14 and tot_name.size == 10)
	names.module.set("unit_frame_names", "extra", 8)
	check("the name size slider updates both names", player_name.size == 18 and target_name.size == 18 and target_name.height == 18)
	names.module.set("unit_frame_names", "extra", 40)
	check("extra name size stays inside the slider", names.module.get("unit_frame_names", "extra") == 12 and player_name.size == 22)
	player_name:SetFont("Fonts\\Expressway.ttf", 11, "")
	names.module.set("unit_frame_names", "extra", 4)
	check("a font change from elsewhere stays, with the extra size added",
		player_name.path == "Fonts\\Expressway.ttf" and player_name.size == 15 and target_name.size == 14 and target_name.height == 14)
	names.module.set("unit_frame_names", "enabled", false)
	check("turning unit names off restores the sizes and heights",
		player_name.size == 11 and player_name.height == 12 and target_name.size == 10 and target_name.height == 12 and tot_name.size == 10)
	name_env.PlayerName = nil
	names.module.set("unit_frame_names", "enabled", true)
	check("a missing player name is skipped", target_name.size == 14 and target_name.height == 14)
	target_name:SetFont("external.ttf", 17, "OUTLINE")
	target_name:SetHeight(30)
	names.module.set("unit_frame_names", "enabled", false)
	check("disabling unit names preserves later font and height changes", target_name.size == 17 and target_name.height == 30 and target_name.path == "external.ttf")
	names.module.set("unit_frame_names", "enabled", true)
	target_name:SetHeight(36)
	name_event("PLAYER_ENTERING_WORLD")
	names.module.set("unit_frame_names", "enabled", false)
	check("unit names restore the latest external region height", target_name.size == 17 and target_name.height == 36)
	names.module.set("unit_frame_names", "enabled", true)
	name_env.TargetFrame.TargetFrameContent.TargetFrameContentMain.Name = name_font(10, 12)
	names.module.set("unit_frame_names", "enabled", false)
	check("a replaced unit name still has its owned size restored", target_name.size == 17 and target_name.height == 36)

	-- The default tooltip anchor is Blizzard's own call, so one hook on it moves
	-- every tooltip the game places, unit and item tooltips alike.
end
