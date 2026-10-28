-- Settings: the native settings page: its subpages, rows, sliders and the /everlook command.
return function(root, check, lib)
	local source, load_all = lib.source, lib.load_all
	local addon2, env2, event2, hooks, tickers, frames = load_all()
	local registered, pages, headers, rows = {}, 0, {}, {}
	local root_category = { GetID = function() return 42 end }
	local layout = { AddInitializer = function(_, row) rows[#rows + 1] = row end }
	local subpages, canvas_pages, page_of_variable = {}, {}, {}
	local children, settings_buttons, sliders = {}, {}, {}
	local function control()
		return { SetParentInitializer = function(self, parent, predicate)
			self.parent, self.predicate = parent, predicate; children[#children + 1] = self
		end, AddSearchTags = function(self, ...) self.tags = { ... } end }
	end
	local opened = nil
	addon2.sched = { frame = {}, page = function() return addon2.sched.frame end }
	local scanned = 0
	addon2.scan = { now = function() scanned = scanned + 1 end }
	env2.Settings = {
		RegisterVerticalLayoutCategory = function(name)
			assert(name == "Everlook"); pages = pages + 1; return root_category, layout
		end,
		RegisterVerticalLayoutSubcategory = function(parent, name)
			assert(parent == root_category, "a subpage must hang under the Everlook page")
			local page = { GetID = function() return 100 + #subpages end, name = name }
			subpages[#subpages + 1] = page
			return page, { AddInitializer = function(_, row) headers[#headers + 1] = row.name; if row.click then settings_buttons[row.name] = row end end }
		end,
		RegisterCanvasLayoutSubcategory = function(parent, frame, name)
			assert(parent == root_category, "a canvas subpage must hang under the Everlook page")
			local page = { GetID = function() return 200 + #canvas_pages end, name = name, frame = frame }
			canvas_pages[#canvas_pages + 1] = page
			return page, {}
		end,
		RegisterAddOnCategory = function(page) assert(page == root_category) end,
		RegisterProxySetting = function(page, variable, _, _, default, get, set)
			assert(page ~= root_category, "module settings belong on a subpage, not the Everlook page")
			assert(not registered[variable], "duplicate setting variable")
			registered[variable] = { get = get, set = set, default = default }; page_of_variable[variable] = page.name; return { variable = variable }
		end,
		CreateCheckbox = control,
		CreateControlTextContainer = function()
			local data = {}
			return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end, GetData = function() return data end }
		end,
		CreateDropdown = control,
		CreateSliderOptions = function(minimum, maximum, step)
			local options = { minimum = minimum, maximum = maximum, step = step }
			function options:SetLabelFormatter(_, format) self.format = format end
			return options
		end,
		CreateSlider = function(_, proxy, options) sliders[proxy.variable] = options; return control() end,
		OpenToCategory = function(id) opened = id end,
	}
	env2.CreateSettingsListSectionHeaderInitializer = function(name)
		return { name = name }
	end
	env2.CreateSettingsButtonInitializer = function(name, _, click, _, search)
		assert(search ~= nil); return { name = name, click = click }
	end
	env2.EventUtil.ContinueOnAddOnLoaded = function(_, callback) callback() end
	env2.EventUtil.ContinueOnPlayerLogin = function(callback) callback() end
	env2.MinimalSliderWithSteppersMixin = { Label = { Right = "right" } }
	local settings = assert(loadfile(source("settings"))); setfenv(settings, env2); settings("Everlook", addon2)
	check("native settings register one Everlook page", pages == 1)
	check("every option carries its module's name as a search tag", (function()
		local tagged_count = 0
		for _, row in ipairs(children) do
			if row.tags and type(row.tags[1]) == "string" and row.tags[1] ~= "" then tagged_count = tagged_count + 1 end
		end
		return tagged_count == #children and #children > 0
	end)())
		check("modules can add native settings buttons after their options", settings_buttons["Preview notifications"] and settings_buttons["Reset Island position"])
	check("preview has no effect when the module is off", settings_buttons["Preview notifications"].click() == false and #addon2.island.view().notices == 0)
	addon2.module.set("island", "enabled", true)
	settings_buttons["Preview notifications"].click()
	local preview_notices = addon2.island.view().notices
	check("native preview adds warning, coins and longer local examples", #preview_notices == 3 and preview_notices[1].severity == "warning" and preview_notices[2].money == 12345 and preview_notices[3].detail)
	addon2.module.set("island", "position_x", 103)
	addon2.module.set("island", "position_top", 13)
	check("dragging the Island lands on the pixel it was dropped on", addon2.module.get("island", "position_x") == 103 and addon2.module.get("island", "position_top") == 13)
	settings_buttons["Reset Island position"].click()
	check("native reset restores the position preferences", addon2.module.get("island", "position_x") == 0 and addon2.module.get("island", "position_top") == 12)
	addon2.module.set("island", "enabled", false)
	local subpage_names = {}
	for index = 1, #subpages do subpage_names[index] = subpages[index].name end
	check("each subject gets its own subpage on the left", table.concat(subpage_names, ",") == "Quests,Vendors,Loot and mail,Social,Chat,Tooltips,Map,Action bars,Bags,Nameplates,Text and names,Combat,Screen and camera,Island,Radial menu")
	check("performance is the canvas subpage and hosts the scheduler's frame", #canvas_pages == 1 and canvas_pages[1].name == "Performance" and canvas_pages[1].frame == addon2.sched.frame)
	local count, expected = 0, 0
	for _ in pairs(registered) do count = count + 1 end
	for _, module in ipairs(addon2.module.modules) do
		for _ in pairs(module.options) do expected = expected + 1 end
	end
	check("the subpages include each module option exactly once", count == expected)
	check("an option sits on its subject's page",
		page_of_variable.Everlook_flight_time_enabled == "Map" and page_of_variable.Everlook_useful_tooltips_enabled == "Tooltips"
		and page_of_variable.Everlook_sell_junk_enabled == "Vendors" and page_of_variable.Everlook_fonts_size_offset == "Text and names"
		and page_of_variable.Everlook_bags_enabled == "Bags" and page_of_variable.Everlook_action_bar_slots_enabled == "Action bars"
		and page_of_variable.Everlook_nameplates_enabled == "Nameplates" and page_of_variable.Everlook_swing_timers_enabled == "Combat"
		and page_of_variable.Everlook_camera_distance_enabled == "Screen and camera"
		and page_of_variable.Everlook_quest_automation_enabled == "Quests" and page_of_variable.Everlook_island_enabled == "Island"
		and page_of_variable.Everlook_take_mail_enabled == "Loot and mail")
	local module_count = #addon2.module.modules
	local last = addon2.module.modules[module_count]
	local function has_header(name)
		for index = 1, #headers do
			if headers[index] == name then return index end
		end
	end
	check("a subpage titles each module with a section heading", has_header("Flight time") and has_header("Useful tooltips") and has_header(last.name))
	check("island sections keep placement, notices and their buttons in order",
		(has_header("Reset Island position") or 0) > (has_header("Placement") or 0)
		and (has_header("Opening") or 0) > (has_header("Placement") or 0)
		and (has_header("Quest display") or 0) > (has_header("Opening") or 0)
		and (has_header("Notices") or 0) > (has_header("Quest display") or 0)
		and (has_header("Preview notifications") or 0) > (has_header("Notices") or 0)
		and (has_header("Session recap") or 0) > (has_header("Preview notifications") or 0)
		and (has_header("Activity") or 0) > (has_header("Session recap") or 0))
	count = 0
	for _, module in ipairs(addon2.module.modules) do
		if page_of_variable["Everlook_" .. module.id .. "_enabled"] then count = count + 1 end
	end
	check("every module appears on exactly one page", count == module_count)
	check("module options are grouped under their enable toggle", #children == expected - module_count)
	local sample = children[1]
	registered.Everlook_quest_text_size_enabled.set(false)
	check("disabled module options cannot be changed in the UI", not sample.predicate())
	registered.Everlook_quest_text_size_enabled.set(true)
	check("enabling a module makes its options available", sample.predicate())
	check("subpage toggles retain saved preferences", registered.Everlook_quest_text_size_enabled.get())
	registered.Everlook_fonts_size_offset.set(100)
	check("settings clamp font size to supported range", addon2.module.get("fonts", "size_offset") == 8)
	check("a slider that counts things shows its number", sliders.Everlook_island_toast_count.format(3) == "3")
	check("every text size is in points", sliders.Everlook_fonts_size_offset.format(3) == "3 pt" and sliders.Everlook_unit_frame_names_extra.format(4) == "4 pt"
		and sliders.Everlook_quest_text_size_text_size.format(16) == "16 pt" and sliders.Everlook_tracker_text_size_text_size.format(16) == "16 pt")
	check("the Island's position is in pixels", sliders.Everlook_island_position_x.format(-103) == "-103 px" and sliders.Everlook_island_position_top.format(12) == "12 px")
	check("a slider with a unit shows it after the number", sliders.Everlook_island_size.format(105) == "105%" and sliders.Everlook_chat_layout_fade_seconds.format(120) == "120 s")
	check("a label shows the step the value will be stored on", sliders.Everlook_island_size.format(97) == "95%" and sliders.Everlook_island_size.format(98) == "100%")
	local scale = sliders.Everlook_swing_timers_scale
	check("a percentage label shows the step too", scale.format(83) == "80%" and scale.format(87) == "90%")
	check("a fraction shown as a percentage runs in whole percents", scale.minimum == 50 and scale.maximum == 100 and scale.step == 10 and scale.format(80) == "80%")
	check("a percentage slider starts from the stored fraction", registered.Everlook_swing_timers_scale.default == 50 and registered.Everlook_swing_timers_scale.get() == 50)
	registered.Everlook_swing_timers_scale.set(80)
	check("a percentage slider stores the fraction", addon2.module.get("swing_timers", "scale") == 0.8 and registered.Everlook_swing_timers_scale.get() == 80)
	registered.Everlook_island_quest_distance_weight.set(150)
	check("a quarter step shows as a whole percentage", addon2.module.get("island", "quest_distance_weight") == 1.5 and registered.Everlook_island_quest_distance_weight.get() == 150)
	addon2.settings.toggle()
	check("the toggle opens the Everlook page", opened == 42)
	local hidden_panels = 0
	env2.SettingsPanel = { shown = true, IsShown = function(self) return self.shown end, GetCurrentCategory = function() return root_category end }
	env2.HideUIPanel = function(panel) hidden_panels = hidden_panels + 1; panel.shown = false end
	opened = nil
	addon2.settings.toggle()
	check("the toggle closes the page while it is showing", hidden_panels == 1 and opened == nil)
	env2.SettingsPanel.shown = true
	env2.SettingsPanel.GetCurrentCategory = function() return subpages[2] end
	addon2.settings.toggle()
	check("the toggle closes the window from any Everlook subpage", hidden_panels == 2 and opened == nil)
	env2.SettingsPanel.shown = true
	env2.SettingsPanel.GetCurrentCategory = function() return canvas_pages[1] end
	addon2.settings.toggle()
	check("the toggle closes the window from the performance subpage", hidden_panels == 3 and opened == nil)
	do
		-- A client that refuses to close the panel is not an error for the player, and it is tried again after combat.
		local real_hide, later = env2.HideUIPanel, nil
		env2.HideUIPanel = function() error("blocked") end
		addon2.after_combat = function(key, work) later = { key = key, work = work } end
		env2.SettingsPanel.shown = true
		env2.SettingsPanel.GetCurrentCategory = function() return root_category end
		local ok = pcall(addon2.settings.toggle)
		check("a refused close raises nothing and is queued for after combat", ok and later and later.key == "settings:close")
		env2.HideUIPanel = real_hide
		later.work()
		check("the queued close runs when combat ends", hidden_panels == 4)
		addon2.after_combat = nil
	end
	env2.SettingsPanel.shown = true
	env2.SettingsPanel.GetCurrentCategory = function() return {} end
	addon2.settings.toggle()
	check("the toggle switches to Everlook from another settings page", opened == 42 and hidden_panels == 4)
	env2.SettingsPanel.shown = false
	opened = nil
	addon2.settings.toggle()
	check("the toggle opens the page when the panel is closed", opened == 42 and hidden_panels == 4)
	check("/everlook and its short form /el are the only commands, one handler for both",
		env2.SLASH_EVERLOOK1 == "/everlook" and env2.SLASH_EVERLOOK2 == "/el" and env2.SLASH_EVERLOOK3 == nil
		and env2.SLASH_EVERLOOKQOL1 == nil and env2.SlashCmdList.EVERLOOKQOL == nil)
	opened = nil
	env2.SettingsPanel.shown = false
	env2.SlashCmdList.EVERLOOK("")
	check("/everlook with nothing after it toggles the page", opened == 42)
	opened = nil
	opened = nil
	env2.SlashCmdList.EVERLOOK(" Where ")
	check("/everlook with words after it still toggles the page", opened == 42)
	check("the Everlook page has no collection controls", rows[1] == nil)
end
