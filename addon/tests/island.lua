-- Island: a small pill at the top of the screen that shows your level, your quest and notices.
return function(root, check, lib)
	local read_source, load_all = lib.read_source, lib.load_all
	local island_world, fire_after, finish_animations = lib.island_world, lib.fire_after, lib.finish_animations
	local last_toast_text, shown_bar, secret_stat, quest_world = lib.last_toast_text, lib.shown_bar, lib.secret_stat, lib.quest_world
	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		state.guid, state.server = "Player-1-UI", 2000000
		env.GetServerTime = function() return state.server end
		env.UnitGUID = function() return state.guid end
		env.GetXPExhaustion = function() return nil end
		env.GetMaxPlayerLevel = function() return 60 end
		state.xp = 600
		event("PLAYER_XP_UPDATE")
		addon.module.set("island", "feed_experience", true)
		env.everlook_island_key("down")
		local status, quests_heading, notices_heading, hour, quest_pane, notice_pane
		for _, object in ipairs(frames) do
			for _, region in ipairs(object.regions or {}) do
				if region.shown ~= false then
					if region.text == "STATUS" then status = region end
					if region.text == "QUESTS" then quests_heading = region end
					if region.text == "NOTIFICATIONS" then notices_heading = region end
					if region.text == "HOUR" then hour = region end
				end
			end
			if object.scroll_child and object.point then
				if object.point[4] == 0 then quest_pane = object else notice_pane = object end
			end
		end
		-- 720 wide on the 12-column grid: pane A is five columns, so the divider is at 12 + 276 + 12 = 300.
		check("the island is two columns wide when there is a quest to show", addon.island.view().width == 720)
		check("Status and the quests share the left edge, and the notifications start at the divider and the inset", status and quests_heading
			and status.point[4] == 12 and quests_heading.point[4] == 12 and notices_heading and notices_heading.point[4] == 300 + 12)
		check("the experience table is a section in the notifications pane, with the summary's two and the quest card", hour ~= nil and addon.island.view().sections == 4)
		check("the two panes share a top and a height, and the left ends where the right begins",
			quest_pane and notice_pane and quest_pane.point[5] == notice_pane.point[5] and quest_pane.height == notice_pane.height
			and quest_pane.width == notice_pane.point[4] and quest_pane.width + notice_pane.width == 720)
	end
	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		env.everlook_island_key("down")
		check("with a quest the island is wide", addon.island.view().width == 720)
		state.quests, state.watched, state.selected = {}, {}, nil
		event("QUEST_LOG_UPDATE")
		check("with no quest to follow or suggest it narrows to the notifications alone", addon.island.view().width == 432)
		local pane
		for _, object in ipairs(frames) do
			-- The quests list is made before the notifications list.
			if object.scroll_child and not pane then pane = object end
		end
		check("and the quests column is hidden", pane and pane.shown == false)
		state.quests, state.watched, state.selected = { { questID = 21, title = "Back again", level = 12, distance = 100 } }, { 21 }, 21
		state.quests[1].objectives = { { text = "Return", finished = false } }
		event("QUEST_LOG_UPDATE")
		check("a quest brings the column and the width back", addon.island.view().width == 720 and pane.shown ~= false)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		env.UIParent.GetWidth = function() return 320 end
		env.UIParent.GetHeight = function() return 480 end
		addon.module.set("island", "enabled", true)
		local root_frame
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then root_frame = frame end end
		check("island placement defaults to twelve below the top", root_frame.point[5] == -12)
		addon.module.set("island", "size", 150)
		addon.module.set("island", "position_x", 600)
		addon.module.set("island", "position_top", 300)
		check("scaled capsule is clamped inside a narrow screen", root_frame.scale == 1.5 and root_frame.point[4] < 100 and root_frame.point[5] > -300)
		env.everlook_island_key("down")
		check("expanded width accounts for the island scale", addon.island.view().width <= 320 / 1.5)
		addon.island.reset_position()
		check("reset changes placement without changing size", addon.module.get("island", "position_x") == 0 and addon.module.get("island", "position_top") == 12 and addon.module.get("island", "size") == 150)
		state.time = state.time + 1
		env.everlook_island_key("up")
		addon.module.set("island", "hover_preview", false)
		root_frame.scripts.OnEnter(root_frame)
		check("hover preview can be disabled without losing click opening", addon.island.view().mode == "closed")
		root_frame.scripts.OnClick(root_frame)
		check("click still pins with hover disabled", addon.island.view().pinned)
		root_frame.scripts.OnClick(root_frame)
		addon.module.set("island", "read_time", 7)
		env.Everlook.island.notify({ text = "Default read time" })
		check("read time controls the implicit notification duration", addon.island.view().notices[1].duration == 7)
		env.Everlook.island.notify({ text = "Explicit duration", duration = 2 })
		check("producer duration overrides the read time", addon.island.view().notices[2].duration == 2)
		local before = #addon.island.view().toasts
		env.InCombatLockdown = function() return true end
		env.Everlook.island.notify({ text = "Routine combat notice" })
		check("routine combat notices remain in the inbox", #addon.island.view().toasts == before and #addon.island.view().queue == 0 and #addon.island.view().notices == 3)
		env.Everlook.island.notify({ text = "Combat warning", severity = "warning" })
		check("combat warnings can still toast", #addon.island.view().toasts == before + 1)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		check("combat ends without replaying routine arrivals", #addon.island.view().queue == 0)
		env.EverlookSaved.modules.island.size = 0 / 0
		env.EverlookSaved.modules.island.position_x = math.huge
		env.EverlookSaved.modules.island.position_top = -1000
		event("UI_SCALE_CHANGED")
		check("corrupt numeric preferences use finite bounded values", root_frame.scale == 1 and root_frame.point[4] == 0 and root_frame.point[5] == -8)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.UIParent.GetWidth = function() return 400 end
		addon.module.set("island", "enabled", true)
		check("the resting island is a readable capsule", addon.island.view().width == 64 and addon.island.view().height == 36)
		env.everlook_island_key("down")
		local before = addon.island.view()
		check("the expanded summary fits the available screen", before.width == 368)
		env.Everlook.island.notify({ text = string.rep("A wrapped history message ", 12) })
		local after = addon.island.view()
		check("long history rows grow below a stable summary", before.summary_height ~= nil and before.summary_height == after.summary_height and after.height > before.height + 16)
		check("experience draws no rail under the level", shown_bar(frames) == nil)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.GetMoneyString = function(amount) return "<coin:" .. amount .. ">" end
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ source = "Repair", key = "result", text = "Equipment repaired",
			detail = "Personal funds", severity = "success", money = -21500, progress = 1 })
		local title, detail, label, progress
		for _, object in ipairs(frames) do
			if object.max == 1 and object.value == 1 then progress = object end
			for _, region in ipairs(object.regions) do
				if region.text == "Equipment repaired" then title = region end
				if region.text and region.text:find("Personal funds", 1, true) and region.text:find("<coin:20000>", 1, true) then detail = region end
				if region.text and region.text:find("Success", 1, true) then label = region end
			end
		end
		check("rich cards render a primary title, supporting detail, colored native coins and a severity label", title and detail and detail.text:find("|cffffd166", 1, true) and label)
		check("readable notification progress uses a native rail", progress and progress.height == 3)
		env.Everlook.island.notify({ source = "Quest", key = "active", kind = "quest", text = "Smart Drinks", presentation = "status" })
		check("an active status without a capsule of its own keeps an icon beside the level in the pill", addon.island.view().width > 64 and addon.island.view().width < 88)
		env.everlook_island_key("down")
		local view = addon.island.view()
		check("expanded activity occupies its own row above the inbox", view.status_height and view.status_height >= 44)
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local handle = api.notify({ source = "Flight", key = "trip", text = "Flying", detail = "1 second", presentation = "status", progress = 0.1 })
		env.everlook_island_key("down")
		afters[#afters].callback()
		api.notify({ source = "Flight", key = "trip", text = "Flying", detail = "2 seconds", presentation = "status", progress = 0.2 })
		check("reading activity stays acknowledged through numeric updates", addon.island.view().unread_count == 0 and #addon.island.view().notices == 1)
		local deadline = afters[#afters].callback
		addon.module.set("island", "enabled", false)
		addon.module.set("island", "enabled", true)
		local next_handle = api.notify({ source = "Flight", key = "trip", text = "New flight", presentation = "status" })
		deadline()
		check("a disabled status deadline cannot affect a new session", next_handle ~= handle and addon.island.view().status.id == next_handle)
		api.notify({ source = "Flight", key = "trip", text = "Keep in history", presentation = "inbox" })
		check("moving status to inbox removes live activity", addon.island.view().status == nil and #addon.island.view().toasts == 0)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "Visible before preview" })
		finish_animations(frames)
		local pill
		for _, object in ipairs(frames) do if object.name == "EverlookIsland" then pill = object end end
		pill.scripts.OnEnter(pill)
		local view = addon.island.view()
		check("pointer opening makes the inbox available with a short reveal", view.mode == "open" and view.preview and view.preview.phase == "opening" and view.preview.duration == 0.15)
		check("visible cards hand off through a fade without exiting their identity", view.toasts[1].phase == "handoff" and view.toasts[1].shown)
		finish_animations(frames)
		check("a completed handoff hides cards while retaining their history", not addon.island.view().toasts[1].shown and #addon.island.view().notices == 1)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		view = addon.island.view()
		check("pointer close fades a visual layer while restoring capsule input bounds", view.mode == "closed" and view.width == 64 and view.preview.phase == "closing" and view.preview.duration == 0.125)
		pill.scripts.OnEnter(pill)
		check("pointer reopening interrupts the close without waiting", addon.island.view().mode == "open" and addon.island.view().preview.phase == "opening")
		env.everlook_island_key("down")
		check("keyboard inspection immediately settles a pointer transition", addon.island.view().preview.phase == "settled" and addon.island.view().preview.alpha == 1)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local pill
		for _, object in ipairs(frames) do if object.name == "EverlookIsland" then pill = object end end
		pill.scripts.OnEnter(pill)
		local original_targets = {}
		for _, object in ipairs(frames) do
			for _, group in ipairs(object.animation_groups or {}) do
				if group.playing then
					for _, animation in ipairs(group.animations) do
						animation.progress = 0.5
						if animation.kind == "Translation" then original_targets[#original_targets + 1] = animation.target end
					end
				end
			end
		end
		check("preview motion samples native progress", addon.island.view().preview.alpha == 0.5 and addon.island.view().preview.y == -3)
		local controller_motion = false
		for _, target in ipairs(original_targets) do if target and target.mouse ~= false then controller_motion = true end end
		check("preview translations target visuals rather than mouse controls", #original_targets > 0 and not controller_motion)
		addon.module.set("island", "reduced_motion", true)
		check("reduced motion removes translation during an interrupted reveal", addon.island.view().preview.y == 0 and addon.island.view().preview.alpha == 0.5)
		finish_animations(frames)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		local old_finish
		for _, object in ipairs(frames) do
			for _, group in ipairs(object.animation_groups or {}) do
				if group.playing then old_finish = group.scripts.OnFinished end
			end
		end
		addon.module.set("island", "enabled", false)
		addon.module.set("island", "enabled", true)
		if old_finish then old_finish() end
		check("an old preview completion cannot reopen a new session", addon.island.view().mode == "closed" and addon.island.view().preview.alpha == 0)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local pill, resting, expanded, face
		local function find_island()
			pill, resting, expanded, face = nil, nil, nil, nil
			for _, object in ipairs(frames) do
				if object.name == "EverlookIsland" then pill = object end
				if object.name == "EverlookIslandResting" then resting = object end
				if object.name == "EverlookIslandExpanded" then expanded = object end
				if object.name == "EverlookIslandFace" then face = object end
			end
		end
		local function preview_fade(object)
			for _, group in ipairs(object.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do
					if animation.kind == "Alpha" then return animation end
				end
			end
		end
		find_island()
		pill.scripts.OnEnter(pill)
		local view = addon.island.view()
		check("pointer open starts from the resting pill", view.shell.width == 64 and view.shell.height == 36 and view.width > view.shell.width)
		check("the chrome stays opaque while the open page is clipped to it", resting.shown and resting.alpha == 1 and expanded.clips and expanded.width == view.shell.width and face.alpha == 1)
		local fade = preview_fade(expanded)
		fade.progress = 0.5
		pill.scripts.OnUpdate()
		view = addon.island.view()
		check("halfway the chrome is between the pill and the island", view.shell.width > 64 and view.shell.width < view.width and expanded.width == view.shell.width)
		addon.module.set("island", "reduced_motion", true)
		view = addon.island.view()
		check("reduced motion snaps the open chrome while the fade continues", view.shell.width == view.width and view.preview.alpha == 0.5 and view.preview.y == 0)
		env.everlook_island_key("down")
		view = addon.island.view()
		check("a keyboard open leaves the chrome at the island size", view.preview.phase == "settled" and view.preview.alpha == 1 and view.shell.width == view.width)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "Keep this card" })
		finish_animations(frames)
		local pill
		for _, object in ipairs(frames) do if object.name == "EverlookIsland" then pill = object end end
		pill.scripts.OnEnter(pill)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		finish_animations(frames)
		local view = addon.island.view()
		check("closing during a handoff restores the live card instead of hiding it", view.mode == "closed" and #view.toasts == 1 and view.toasts[1].shown and view.toasts[1].alpha == 1)
		local api = env.Everlook.island
		api.notify({ source = "Trip", key = "one", text = "Flying", presentation = "status" })
		api.notify({ source = "Trip", key = "one", text = "Arrived", presentation = "toast", severity = "success" })
		local completion_fade
		for _, object in ipairs(frames) do
			for _, group in ipairs(object.animation_groups or {}) do
				if group.playing then
					for _, animation in ipairs(group.animations) do
						if animation.kind == "Alpha" and animation.to == 1 and animation.duration == 0.15 then completion_fade = animation end
					end
				end
			end
		end
		check("status completion reveals success once with a short fade", completion_fade ~= nil)
	end
	do
		local island, island_env = load_all()
		local found
		for _, module in ipairs(island.module.modules) do
			if module.id == "island" then found = module end
		end
		check("the island is on its own settings page", found and found.page == "island" and found.keybinding == "EVERLOOK_ISLAND")
		local names, seen, missing = {}, {}, false
		for _, section in ipairs(found and island.module.sections(found) or {}) do
			names[#names + 1] = section.name
			for _, key in ipairs(section.keys) do
				if seen[key] or not found.options[key] then missing = true end
				seen[key] = true
			end
		end
		for key in pairs(found and found.options or {}) do
			if key ~= "enabled" and not seen[key] then missing = true end
		end
		check("island sections name every option once",
			found and not missing and table.concat(names, ",") == "Presets,Placement,Opening,Closed pill,Quest display,Notices,Activity")
		check("the island starts disabled", not island.module.enabled("island"))
		check("the island key is not the radial menu key",
			found.keybinding ~= "CLICK EverlookRadialMenuButton:LeftButton" and island_env.BINDING_NAME_EVERLOOK_ISLAND == "Open the island")
		check("money formats gold, silver and copper",
			island.island_vitals.money(1234567) == "123g 45s 67c"
			and island.island_vitals.money(0) == "0c"
			and island.island_vitals.delta(10000) == "+1g"
			and island.island_vitals.delta(-45) == "-45c"
			and island.island_vitals.rich(10000) == "1g")
		do
			local original = island_env.GetMoneyString
			island_env.GetMoneyString = function(amount)
				if amount >= 10000 then return math.floor(amount / 10000) .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" end
				if amount >= 100 then return math.floor(amount / 100) .. "|TInterface\\MoneyFrame\\UI-SilverIcon:14:14|t" end
				return amount .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
			end
			local rich = island.island_vitals.rich(30000 + 6000 + 83)
			island_env.GetMoneyString = original
			check("coins are seated on the text's baseline, whichever offsets the client wrote",
				rich:find("UI-GoldIcon:0:0:2:-3|t", 1, true) and rich:find("UI-SilverIcon:14:14:2:-3|t", 1, true)
				and rich:find("UI-CopperIcon:0:0:2:-3|t", 1, true) and not rich:find(":2:0|t", 1, true))
		end
		check("durability and bags format as a glance",
			island.island_vitals.percent(50, 70) == "71%"
			and island.island_vitals.bags(1) == "1 free slot"
			and island.island_vitals.bags(8) == "8 free slots"
			and island.island.format_clock(14, 5) == "14:05"
			and island.island.format_level(12) == "12")
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		check("the closed chip draws no bar", shown_bar(frames) == nil)
		env.everlook_island_key("down")
		local heading, metric, clear, undo, clock, experience, status
		for _, object in ipairs(frames) do
			if object.name == "EverlookIslandClearHistory" then clear = object end
			if object.name == "EverlookIslandUndo" then undo = object end
			for _, region in ipairs(object.regions) do
				if region.text == "Level 12" then heading = region end
				if region.text == "STATUS" then status = region end
				if region.text == "14:05" then clock = region end
				if region.text == "|cffad76ef45%|r" or region.text == "45%" then experience = region end
				if region.text == "Money" then metric = region end
			end
		end
		local lay = dofile(root .. "/tests/lib/layout.lua").new()
		check("the open bar shows the time and the experience percent beside the level", clock ~= nil and experience ~= nil
			and lay.rectangle(clock).top == lay.rectangle(heading).top + (lay.rectangle(heading).height - lay.rectangle(clock).height) / 2)
		check("the first section clears the level text by a section gap", lay.rectangle(status).top >= lay.rectangle(heading).bottom + 16 - 4)
		check("expanded metrics begin below the Status heading", lay.rectangle(metric).top >= lay.rectangle(status).bottom + 6)
		check("empty history has no disabled Clear button", clear.shown == false)
		check("an empty island holds its panes to the height of its empty message", addon.island.view().scroll_height >= 48 and addon.island.view().scroll_height <= 80)
		local empty_height = addon.island.view().height
		env.Everlook.island.notify({ text = "A notice to clear" })
		check("history controls return when there is a notice", clear.shown ~= false and #addon.island.view().notices == 1)
		local row_label
		for _, object in ipairs(frames) do
			for _, region in ipairs(object.regions or {}) do
				if region.text == "A notice to clear" and region.font == "GameFontHighlight" then row_label = region end
			end
		end
		check("a row is set in text type, smaller than the toast it came from, and bright while unread",
			row_label and row_label.shown ~= false and row_label.color[1] > 0.9)
		fire_after(afters, 0.75)
		check("a row you have read steps back from one you have not", addon.island.view().unread_count == 0 and row_label.color[1] < 0.75)
		addon.island.clear_history()
		check("clearing history keeps Undo without a disabled Clear button", clear.shown == false and undo.shown)
		check("Undo takes the right end of the notifications heading when Clear is gone", undo.point and undo.point[1] == "TOPRIGHT" and undo.point[2] == clear.parent and undo.point[5] == -4 and clear.point[5] == -4)
		fire_after(afters, 5)
		check("expired Undo returns to the compact empty state", clear.shown == false and undo.shown == false and addon.island.view().height == empty_height)
		state.time = state.time + 1
		env.everlook_island_key("up")
		env.everlook_island_key("down")
		heading.GetStringHeight = function() return 28 end
		addon.module.set("island", "size", 150)
		check("larger native text keeps clear space above the first section", -status.point[5] >= -heading.point[5] + heading:GetStringHeight() + 6)
	end
	do
		local addon, env, event, state, afters, tickers, frames = island_world()
		event("PLAYER_LEVEL_UP", 13)
		event("PLAYER_MONEY")
		check("a disabled island ignores notices", addon.island.view().mode == "closed" and #addon.island.view().notices == 0)
		addon.module.set("island", "enabled", true)
		local view = addon.island.view()
		check("enabling shows a closed experience chip",
			view.mode == "closed" and view.shown and view.level == 12 and view.xp == 450 and view.xp_max == 1000
			and view.width == 64 and view.height == 36)
		check("the closed chip already knows the safe readouts",
			view.money == "1g 23s 45c" and view.durability == "50%" and view.bags == "8 free slots" and view.clock == "14:05" and view.coords == nil)
		state.xp = 600
		event("PLAYER_XP_UPDATE", "player")
		check("experience updates the fill without a notice", addon.island.view().xp == 600 and addon.island.view().mode == "closed" and #addon.island.view().notices == 0)
		state.level = 13
		event("PLAYER_LEVEL_UP", 13)
		check("a level-up emerges below a steady island",
			addon.island.view().mode == "closed" and last_toast_text(addon) == "Level 13" and addon.island.view().width == 64)
		fire_after(afters, 4)
		finish_animations(frames)
		check("the level toast leaves with its inbox row", addon.island.view().mode == "closed" and last_toast_text(addon) == nil and #addon.island.view().notices == 0)
		addon.module.set("island", "enabled", false)
		check("turning the island off hides it and drops notices",
			addon.island.view().shown == false and #addon.island.view().notices == 0 and tickers[#tickers].cancelled)
	end
	do
		local addon, _, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local pill
		for index = 1, #frames do
			if frames[index].name == "EverlookIsland" then
				pill = frames[index]
			end
		end
		check("the island is its own mouse frame", pill ~= nil)
		pill.scripts.OnEnter(pill)
		check("hover opens a preview of the data bar", addon.island.view().mode == "open" and addon.island.view().hovering and addon.island.view().width == 432)
		pill.scripts.OnLeave(pill)
		fire_after(afters, 0.1)
		check("leaving a hover closes the island", addon.island.view().mode == "closed" and not addon.island.view().hovering)
		pill.scripts.OnClick(pill)
		check("a click pins the island open", addon.island.view().pinned and addon.island.view().mode == "open")
		pill.scripts.OnLeave(pill)
		check("leaving a pinned island keeps it open", addon.island.view().mode == "open")
		pill.scripts.OnClick(pill)
		check("a second click lets the island close", not addon.island.view().pinned and addon.island.view().mode == "closed")
	end
	do
		local addon, _, _, state, _, tickers, frames = island_world()
		addon.module.set("island", "enabled", true)
		local root
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookIsland" then root = frame end
		end
		local placements = 0
		local place = root.SetPoint
		function root:SetPoint(...)
			placements = placements + 1
			return place(self, ...)
		end
		local tick = tickers[#tickers].callback
		tick()
		tick()
		check("a quiet closed island keeps its layout between seconds", placements == 0)
		root.scripts.OnClick(root)
		placements = 0
		tick()
		check("an open bar with the same minute stays still", placements == 0 and addon.island.view().clock == "14:05" and addon.island.view().mode == "open")
		state.minute = 6
		tick()
		check("the open bar updates when the minute changes", placements == 1 and addon.island.view().clock == "14:06")
		root.scripts.OnClick(root)
		placements = 0
		state.minute = 7
		tick()
		check("a closed chip does not relayout for the clock", placements == 0 and addon.island.view().mode == "closed")
	end
	do
		local addon, _, _, state, _, tickers, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		local root
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookIsland" then root = frame end
		end
		local placements = 0
		local place = root.SetPoint
		function root:SetPoint(...)
			placements = placements + 1
			return place(self, ...)
		end
		local tick = tickers[#tickers].callback
		tick()
		check("an unchanged quest chip stays still", placements == 0)
		state.quests[2].distance = 700
		state.time = state.time + 1
		tick()
		check("a new quest distance redraws the closed chip", placements == 1 and addon.island.view().quests.current.distance == 700)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		check("a disabled island leaves the key alone", addon.island.view().mode == "closed" and not addon.island.view().pinned)
		addon.module.set("island", "enabled", true)
		env.everlook_island_key("down")
		check("the key peeks while it is down", addon.island.view().holding and addon.island.view().mode == "open")
		env.everlook_island_key("up")
		check("a tap pins the island", addon.island.view().pinned and addon.island.view().mode == "open" and not addon.island.view().holding)
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		check("a second tap unpins the island", not addon.island.view().pinned and addon.island.view().mode == "closed")
		env.everlook_island_key("down")
		state.time = 100.3
		env.everlook_island_key("up")
		check("holding the key peeks and releasing leaves it closed", not addon.island.view().pinned and addon.island.view().mode == "closed")
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		check("a tap after a hold pins it", addon.island.view().pinned)
		env.everlook_island_key("down")
		state.time = 100.6
		env.everlook_island_key("up")
		check("holding while pinned restores the pin", addon.island.view().pinned and addon.island.view().mode == "open")
		for _, frame in ipairs(frames) do
			if frame.name == "EverlookRadialMenuButton" then
				frame.scripts.PreClick(frame, "LeftButton", true)
				frame.scripts.PostClick(frame, "LeftButton", true)
				frame.scripts.PreClick(frame, "LeftButton", false)
				frame.scripts.PostClick(frame, "LeftButton", false)
			end
		end
		check("the island key does not reuse the radial menu binding", addon.island.view().pinned)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		state.money = 22345
		event("PLAYER_MONEY")
		fire_after(afters, 0.75)
		check("an open island keeps a money notice in the list",
			addon.island.view().mode == "open" and addon.island.view().notices[1].money == 10000 and last_toast_text(addon) == nil)
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		check("closing the island keeps the notice until its clock ends", #addon.island.view().notices == 1)
		state.slots[1] = { 10, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("a low durability threshold creates a toast", last_toast_text(addon) == "Equipment at 20%" and addon.island.view().mode == "closed")
		fire_after(afters, 4)
		state.bags[0], state.bags[1] = 1, 0
		event("BAG_UPDATE_DELAYED")
		check("low bag slots create a toast", last_toast_text(addon) == "Only 1 free slot")
		addon.module.set("minimap_coordinates", "enabled", true)
		event("PLAYER_ENTERING_WORLD")
		env.everlook_island_key("down")
		check("coordinates join the open bar only when that module is on", addon.island.view().coords == "50.0, 25.0")
		do
			local position, money_cell
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text == "Position" and region.shown ~= false then position = region.parent end
					if region.text == "Money" and region.shown ~= false then money_cell = region.parent end
				end
			end
			local lay = dofile(root .. "/tests/lib/layout.lua").new()
			local position_box, money_box = lay.rectangle(position), lay.rectangle(money_cell)
			check("the position cell shares money's row, to its right",
				position_box.top == money_box.top and position_box.left == money_box.right + 24)
		end
		addon.module.set("minimap_coordinates", "enabled", false)
		event("PLAYER_ENTERING_WORLD")
		check("clearing coordinates removes them from the island", addon.island.view().coords == nil)
		env.InCombatLockdown = function() return true end
		local ok = pcall(function()
			event("PLAYER_XP_UPDATE", "player")
			event("PLAYER_MONEY")
			event("UPDATE_INVENTORY_DURABILITY")
			event("BAG_UPDATE_DELAYED")
		end)
		check("combat still paints the safe readouts and never reads health, power or names",
			ok and state.health_reads == 0 and state.power_reads == 0 and state.name_reads == 0
			and addon.island.view().money ~= nil)
		addon.module.set("island", "enabled", false)
		check("disabling removes only the island", addon.island.view().shown == false)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		check("the closed pill draws no experience bar, with a numeric reading or a secret one",
			addon.island.view().xp == 450 and shown_bar(frames) == nil)
		local xp, xp_max = secret_stat(), secret_stat()
		check("a secret experience reading is not a number", type(xp) ~= "number" and type(xp_max) ~= "number")
		env.issecretvalue = function(value) return value == xp or value == xp_max end
		state.xp, state.xp_max = xp, xp_max
		event("PLAYER_XP_UPDATE", "player")
		check("a secret reading is kept as it arrived and draws nothing",
			addon.island.view().xp == xp and addon.island.view().xp_max == xp_max and shown_bar(frames) == nil)
		env.everlook_island_key("down")
		local open = addon.island.view()
		check("the open island still reads its other figures, and draws no bar either",
			open.mode == "open" and shown_bar(frames) == nil
			and open.money == "1g 23s 45c" and open.durability == "50%" and open.bags == "8 free slots" and open.clock == "14:05")
		local function status_top()
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text == "STATUS" and region.shown ~= false then return dofile(root .. "/tests/lib/layout.lua").new().rectangle(region).top - 12 end
				end
			end
		end
		check("the Status heading is a section gap under the level row: edge, row, section", status_top() == 12 + 20 + 16)
		state.xp, state.xp_max = 700, 2000
		env.issecretvalue = nil
		event("PLAYER_XP_UPDATE", "player")
		check("a numeric reading after a secret one is read again", addon.island.view().xp == 700)
	end
	do
		local addon, env = island_world()
		addon.module.set("island", "enabled", true)
		env.everlook_island_key("down")
		addon.module.set("island", "enabled", false)
		env.everlook_island_key("up")
		check("turning the island off mid-press still releases the hold", not addon.island.view().holding and addon.island.view().shown == false)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		local api = env.Everlook.island
		check("addon modules and other addons share Everlook.island", type(api) == "table" and type(api.notify) == "function" and addon.island == api)
		local handle, reason = api.notify({ text = "Repair complete", source = "TestAddon" })
		check("disabled notifications are rejected without retaining history", handle == nil and reason == "disabled" and #addon.island.view().notices == 0)
		addon.module.set("island", "enabled", true)
		local payload = { text = "Repair complete", source = "TestAddon", kind = "repair", duration = 6 }
		handle = api.notify(payload)
		payload.text = "Caller changed its table"
		local view = addon.island.view()
		check("external notifications reach the island and own their payload",
			type(handle) == "number" and view.toasts[1].text == "Repair complete" and view.notices[1].id == handle
			and view.notices[1].source == "TestAddon" and view.notices[1].kind == "repair")
		view.notices[1].text = "Caller changed its snapshot"
		check("notification snapshots cannot change the displayed message", addon.island.view().notices[1].text == "Repair complete")
		fire_after(afters, 6)
		check("the requested duration starts the toast's exit", addon.island.view().toasts[1].phase == "exiting")
		finish_animations(frames)
		check("a notification duration removes the toast and the inbox row", #addon.island.view().toasts == 0 and #addon.island.view().notices == 0)
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ source = "RepairAddon", key = "repair", text = "Repair started" })
		local updated = api.notify({ source = "RepairAddon", key = "repair", text = "Repair complete" })
		check("a source key updates one notification with a stable handle", first == updated and #addon.island.view().notices == 1 and last_toast_text(addon) == "Repair complete")
		fire_after(afters, 4)
		check("the earlier timeout cannot expire an updated notification", last_toast_text(addon) == "Repair complete")
		local other = api.notify({ source = "OtherAddon", key = "repair", text = "Other notice" })
		check("notification keys belong to their source", other ~= first and #addon.island.view().notices == 2)
		check("dismissing an older notice leaves the other toast", api.dismiss(first) and last_toast_text(addon) == "Other notice")
		check("dismissing the active notice closes its history row", api.dismiss(other) and addon.island.view().mode == "closed" and #addon.island.view().notices == 0)
		check("dismiss reports an unknown handle", not api.dismiss(other))
		local old = api.notify({ text = "Old session" })
		local old_timeout = afters[#afters].callback
		addon.module.set("island", "enabled", false)
		addon.module.set("island", "enabled", true)
		local fresh = api.notify({ text = "New session" })
		check("handles are not reused after disabling", fresh ~= old and not api.dismiss(old))
		old_timeout()
		check("pending timeouts from before disable leave the new toast", last_toast_text(addon) == "New session")
		for index = 1, 14 do api.notify({ text = "Notice " .. index }) end
		local notices = addon.island.view().notices
		check("notification history remains bounded", #notices == 10 and notices[1].text == "Notice 5" and notices[10].text == "Notice 14")
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		local api = env.Everlook.island
		local calls = 0
		local hook = api.register_event("QUEST_TURNED_IN", function(name, quest_id, xp, money)
			calls = calls + 1
			check("event adapters receive the original WoW arguments", name == "QUEST_TURNED_IN" and quest_id == 42 and xp == 50 and money == 100)
			return { source = "TestAddon", text = "Quest turned in" }
		end)
		local adapter_frame = frames[#frames]
		event("QUEST_TURNED_IN", 42, 50, 100)
		check("disabled islands do not run registered event adapters", calls == 0)
		addon.module.set("island", "enabled", true)
		event("QUEST_TURNED_IN", 42, 50, 100)
		check("a WoW event can feed an external notification", calls == 1 and last_toast_text(addon) == "Quest turned in")
		local optional = api.register_event("QUEST_WATCH_LIST_CHANGED", function(name, quest_id, added)
			check("event adapters preserve optional nil arguments", name == "QUEST_WATCH_LIST_CHANGED" and quest_id == nil and added == true)
		end)
		event("QUEST_WATCH_LIST_CHANGED", nil, true)
		api.unregister_event(optional)
		local second = api.register_event("QUEST_TURNED_IN", function() return { text = "Second addon" } end)
		check("unregister reports an existing event subscription", api.unregister_event(hook))
		event("QUEST_TURNED_IN", 42, 50, 100)
		check("removing one event adapter leaves another active", calls == 1 and last_toast_text(addon) == "Second addon")
		api.unregister_event(second)
		check("removing the last adapter releases its native event subscription", not adapter_frame.events.QUEST_TURNED_IN and not api.unregister_event(second))
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		api.register_event("QUEST_TURNED_IN", function() error("broken producer") end)
		api.register_event("QUEST_TURNED_IN", function() return { text = "Still delivered" } end)
		event("QUEST_TURNED_IN")
		check("one faulty producer reports an error without blocking another", #errors == 1 and errors[1]:find("QUEST_TURNED_IN", 1, true) and errors[1]:find("broken producer", 1, true) and last_toast_text(addon) == "Still delivered")
		addon.module.set("island", "enabled", false)
		addon.module.set("island", "enabled", true)
		event("QUEST_TURNED_IN")
		check("event subscriptions survive a disable and re-enable", last_toast_text(addon) == "Still delivered")
	end
	do
		local addon, env, event = island_world()
		addon.module.set("island", "enabled", true)
		local api, calls = env.Everlook.island, 0
		api.register_event("QUEST_TURNED_IN", function() addon.module.set("island", "enabled", false) end)
		api.register_event("QUEST_TURNED_IN", function() calls = calls + 1 end)
		event("QUEST_TURNED_IN")
		check("disabling during an event stops remaining producers", calls == 0)
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		local api = env.Everlook.island
		local handle = api.notify({ text = "Delivered while open" })
		local view = addon.island.view()
		check("an external notice respects an open island", view.mode == "open" and #view.toasts == 0 and view.notices[1].id == handle and #afters == 1 and afters[1].delay == 0.75)
		check("default notification fields are applied", view.notices[1].source == "everlook" and view.notices[1].kind == "info" and view.notices[1].duration == 4)
		check("dismissing an open row preserves the pin", api.dismiss(handle) and addon.island.view().pinned and #addon.island.view().notices == 0)
	end
	do
		local feeds = {}
		for _, file in ipairs({ "island_share", "island_quest_notices", "island_loot", "island_hearth", "island_reputation", "island_professions",
			"island_mail", "island_invites", "island_buffs", "island_recap", "island_experience", "island_warnings" }) do
			feeds[file] = true
		end
		local addon, env, event = load_all(feeds)
		addon.module.set("island", "enabled", true)
		check("the island runs with its feed addons turned off", addon.island.apply_preset("Informative")
			and addon.module.get("island", "closed_clock") == true and addon.module.get("island", "feed_loot") == nil)
		event("CHAT_MSG_LOOT", "You receive loot: [Thing].")
		event("BAG_UPDATE_DELAYED")
		event("QUEST_TURNED_IN", 5, 0, 0)
		local handle = env.Everlook.island.notify({ text = "Still delivered" })
		check("notices still reach the island without its feeds", handle ~= nil and #addon.island.view().notices == 1)
		local names, island = {}, nil
		for _, module in ipairs(addon.module.modules) do
			if module.id == "island" then island = module end
		end
		for _, section in ipairs(addon.module.sections(island)) do names[#names + 1] = section.name end
		check("the island keeps its own sections without its feeds", table.concat(names, ",") == "Presets,Placement,Opening,Closed pill,Quest display,Notices,Activity")
	end
	do
		local addon, env = load_all()
		check("the island's one table sits on the shared namespace, with its public calls", env.Everlook.island == addon.island and type(env.Everlook.island.notify) == "function" and type(env.Everlook.island.view) == "function")
	end
	do
		-- Resolves the recorded anchors to rectangles, so these checks read where parts land.
		local layout = dofile(root .. "/tests/lib/layout.lua")
		local addon, _, _, _, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "reduced_motion", true)
		layout.settle(frames)
		local function find(name)
			for _, frame in ipairs(frames) do if frame.name == name then return frame end end
		end
		-- The resting frame's surface draws its rounded border a few units beyond the frame on purpose.
		local function surface_border(frame) return frame.name == "EverlookIslandResting" end
		local problems = layout.lint(frames, { skip = surface_border })
		check("no part of the island sits outside the frame that holds it, and no two lines of text overlap", #problems == 0)
		if #problems > 0 then print(table.concat(problems, "\n")) end

		local measure = layout.new()
		-- The capsule is the face, and its parts are on the slot that is showing.
		local face = find("EverlookIslandFace")
		local capsule = measure.rectangle(face)
		local slot
		for _, frame in ipairs(frames) do
			if frame.parent == face and frame.name == nil and frame.shown ~= false and frame.regions and #frame.regions > 0 then slot = frame end
		end
		local parts = {}
		for _, region in ipairs(slot.regions) do
			if region.shown ~= false then parts[#parts + 1] = { region = region, rect = measure.rectangle(region) } end
		end
		local function part(match)
			for _, item in ipairs(parts) do
				local key = item.region.text or item.region.atlas or item.region.path or ""
				if key:find(match, 1, true) then return item.rect end
			end
		end
		local icon, title, ring, distance, badge = part("questtypeicon"), part("Suitable"), part("island_ring"), part("yd"), part("12")
		check("the capsule's lead, title, ring, distance and badge are all laid out", icon and title and ring and distance and badge)
		local function centre(rect) return rect.top + rect.height / 2 end
		check("every part on the capsule shares one centre line",
			math.abs(centre(icon) - centre(title)) < 0.5 and math.abs(centre(title) - centre(distance)) < 0.5
			and math.abs(centre(ring) - centre(badge)) < 0.5 and math.abs(centre(icon) - (capsule.top + capsule.height / 2)) < 0.5)
		check("the lead is inset 9 from the left edge and the badge 12 from the right edge",
			icon.left - capsule.left == 9 and capsule.right - badge.right == 12)
		check("the ring sits 6 before the distance, the distance 12 before the badge and the title 12 before the ring",
			distance.left - ring.right == 6 and badge.left - distance.right == 12 and ring.left - title.right == 12)
		check("the title starts at the text column, 34 from the left edge", title.left - capsule.left == 34)
	end
	do
		local layout = dofile(root .. "/tests/lib/layout.lua")
		local addon, env, _, _, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		-- Reduced motion snaps the closed pill and the open panel to their final size, which the fake frames cannot animate.
		addon.module.set("island", "reduced_motion", true)
		layout.settle(frames)
		local root_frame
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then root_frame = frame end end
		root_frame.scripts.OnClick(root_frame, "LeftButton")
		layout.settle(frames)
		local problems = layout.lint(frames, { skip = function(frame) return frame.name == "EverlookIslandResting" end })
		check("nothing in the open island sits outside the frame that holds it, and no two lines of text overlap", #problems == 0)
		if #problems > 0 then print(table.concat(problems, "\n")) end
		local measure = layout.new()
		local island = measure.rectangle(root_frame)
		check("the open island is centred on the screen and sized to its two panes", island.left == (1920 - 720) / 2 and island.width == 720)
		local function text_rect(text, minimum_top)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false and measure.rectangle(region).top >= (minimum_top or 0) then return measure.rectangle(region) end
				end
			end
		end
		local quests_heading, objective, empty = text_rect("QUESTS"), text_rect("Collect things  1/6"), text_rect("No notifications yet")
		local band_bottom = quests_heading.top + quests_heading.height / 2 + 16
		local card_title = text_rect("Suitable farther", band_bottom)
		-- The card's title row starts 8 below the band, and its 14 high words sit in the middle of its 20.
		check("a pane's content starts 8 below its heading band, in the quests and the notifications alike",
			card_title.top - band_bottom == 8 + 3 and empty.top - band_bottom == 8)
		check("a card's title takes the arrow's room, 22 on from the inset, and an objective's text starts on the inset itself",
			card_title.left - island.left == 12 + 22 and objective.left - island.left == 12)
		local island_grid = addon.island_grid
		check("the grid's columns are whole pixels at both panel widths: 36 wide at 720 and 12 wide at 432",
			island_grid.column(720) == 36 and island_grid.column(432) == 12)
		check("pane A is five columns, 276 wide, and pane B seven, 396, with the divider in the 24 gutter between them",
			island_grid.span(720, 5) == 276 and island_grid.span(720, 7) == 396 and island_grid.panes(720, true) == 300)
		check("two panes fit from 720 up and one pane from 432 up, and a narrower screen keeps what is left",
			select(2, island_grid.fit(true, 720)) == true and island_grid.fit(true, 719) == 432 and island_grid.fit(true, 300) == 300)
		local function cell_rect(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return measure.rectangle(region.parent) end
				end
			end
		end
		local money, gear, bags = cell_rect("Money"), cell_rect("Gear"), cell_rect("Bags")
		check("four metric cells across are 156 wide, three columns each, on the 24 gutter",
			money.width == 156 and gear.left - money.left == 156 + 24 and bags.left - gear.left == 156 + 24 and money.left - island.left == 12)
	end
	do
		local named = false
		for _, feed in ipairs({ "island_share", "island_quest_notices", "island_loot", "island_hearth", "island_reputation", "island_professions",
			"island_mail", "island_invites", "island_buffs", "island_recap", "island_warnings" }) do
			named = named or read_source("island.lua"):find(feed, 1, true) ~= nil
		end
		check("the island chunk does not name its feed addons", not named)
	end
	check("the island does not read the player map",
		not read_source("island.lua"):find("GetPlayerMapPosition", 1, true)
		and not read_source("island.lua"):find("GetBestMapForUnit", 1, true))
	check("the island does not resolve item or spell icons",
		not read_source("island.lua"):find("GetItemIconByID", 1, true)
		and not read_source("island.lua"):find("GetSpellTexture", 1, true))
	check("activity thresholds stay out of the island chunk",
		not read_source("island.lua"):find("free-slots", 1, true)
		and not read_source("island.lua"):find("Paid from personal funds", 1, true)
		and not read_source("island.lua"):find("The bags are full", 1, true))
	check("figure phrasing stays behind vitals",
		not read_source("island.lua"):find("format_money", 1, true)
		and not read_source("island.lua"):find("format_bags", 1, true)
		and not read_source("island.lua"):find("format_percent", 1, true)
		and not read_source("island_vitals.lua"):find("format_bags", 1, true)
		and not read_source("island_vitals.lua"):find("format_percent", 1, true)
		and not read_source("island_vitals.lua"):find(".format_", 1, true))
	do
		local addon, _, _, state, _, tickers, frames = island_world()
		addon.module.set("island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		local placements = 0
		local place = island_frame.SetPoint
		island_frame.SetPoint = function(...) placements = placements + 1; return place(...) end
		for _ = 1, 3 do state.time = state.time + 1; tickers[1].callback() end
		check("an idle closed pill does not repaint on the timer", placements == 0)
	end
	do
		local addon = island_world()
		local age = addon.island.age_text
		check("notice ages step from seconds to minutes to hours",
			age(5) == "Just now" and age(125) == "2m ago" and age(3600) == "1h ago" and age(3900) == "1h 5m ago")
	end
	do
		local addon = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "size", 120)
		check("an unknown preset changes nothing", addon.island.apply_preset("Loud") == false)
		check("the Informative preset turns the feeds on", addon.island.apply_preset("Informative") == true
			and addon.module.get("island", "feed_loot") == true and addon.module.get("island", "quest_context") == true)
		check("the Quiet preset turns them off and keeps the warnings", addon.island.apply_preset("Quiet") == true
			and addon.module.get("island", "feed_loot") == false and addon.module.get("island", "source_bags") == true)
		check("presets leave placement and size alone", addon.module.get("island", "size") == 120)
	end
	do
		local addon, env, _, state, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		local shift, cursor = false, { 500, 500 }
		env.IsShiftKeyDown = function() return shift end
		env.GetCursorPosition = function() return cursor[1], cursor[2] end
		island_frame.scripts.OnDragStart(island_frame)
		cursor = { 600, 400 }
		island_frame.scripts.OnDragStop(island_frame)
		check("a drag without Shift leaves the placement alone",
			addon.module.get("island", "position_x") == 0 and addon.module.get("island", "position_top") == 12)
		shift, cursor = true, { 500, 500 }
		island_frame.scripts.OnDragStart(island_frame)
		cursor = { 600, 400 }
		island_frame.scripts.OnDragStop(island_frame)
		check("Shift and drag writes the placement options",
			addon.module.get("island", "position_x") == 100 and addon.module.get("island", "position_top") == 112)
		island_frame.scripts.OnClick(island_frame)
		check("the click that ends a drag does not pin the island", addon.island.view().pinned == false)
		state.time = state.time + 1
		island_frame.scripts.OnClick(island_frame)
		check("a later click still pins it", addon.island.view().pinned == true)
	end
	do
		local addon, _, _, state, afters, tickers, frames = island_world()
		addon.module.set("island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		addon.module.set("island", "hide_when_idle", true)
		check("the pill stays through the first quiet seconds", island_frame.alpha ~= 0)
		state.time = state.time + 6
		for _, after in ipairs(afters) do after.callback() end
		check("an idle pill fades out", island_frame.alpha == 0)
		addon.island.notify({ source = "Test", key = "back", text = "Hello" })
		check("a notice brings the pill back", island_frame.alpha == 1)
		addon.module.set("island", "hide_when_idle", false)
		check("turning the option off keeps it visible", island_frame.alpha == 1)
	end
	do
		-- Turned off and on again from the settings page while the pill had faded.
		local addon, _, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		addon.module.set("island", "hide_when_idle", true)
		state.time = state.time + 6
		for _, after in ipairs(afters) do after.callback() end
		check("a quiet pill has faded before it is turned off", island_frame.alpha == 0)
		addon.module.set("island", "enabled", false)
		addon.module.set("island", "enabled", true)
		check("turned off and on again while quiet, the pill is back for its quiet seconds", island_frame.alpha == 1)
		state.time = state.time + 6
		for _, after in ipairs(afters) do after.callback() end
		check("and fades once those seconds are up", island_frame.alpha == 0)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		local island_frame
		local shown = true
		env.UIParent = env.UIParent or {}
		env.UIParent.GetTop = function() return 1080 end
		env.UIWidgetTopCenterContainerFrame = { IsShown = function() return shown end, GetBottom = function() return 1000 end }
		addon.module.set("island", "enabled", true)
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		check("the pill drops below a showing top widget", island_frame.point[5] == -88)
		addon.module.set("island", "avoid_top_widgets", false)
		check("the option puts it back at its own distance", island_frame.point[5] == -12)
		addon.module.set("island", "avoid_top_widgets", true)
		shown = false
		addon.module.set("island", "position_top", 16)
		check("a hidden widget leaves the placement alone", island_frame.point[5] == -16)
	end
	do
		local addon, _, event, state, _, tickers = island_world()
		local stats = addon.island_quests.stats
		addon.module.set("island", "enabled", true)
		local paints = stats.paint
		for _ = 1, 10 do state.time = state.time + 1; tickers[1].callback() end
		check("ten idle seconds repaint a closed pill zero times", stats.paint == paints)
		local scans = stats.quest_scan
		check("the counters are plain numbers for /dump", type(scans) == "number" and type(stats.aim) == "number" and type(stats.feed_tick) == "number")
	end
	do
		local addon, _, _, state, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local function face() for _, f in ipairs(frames) do if f.name == "EverlookIslandFace" then return f end end end
		-- The text on the pill that shows now: a region of a visible frame under the face.
		local layout_tests = dofile(root .. "/tests/lib/layout.lua")
		local function shown(text)
			layout_tests.settle(frames)
			for _, frame in ipairs(frames) do
				local visible, walker = true, frame
				while walker do
					if walker.shown == false or (walker.alpha or 1) == 0 then visible = false end
					walker = walker.parent
				end
				for _, region in ipairs(frame.regions or {}) do
					if visible and region.text == text and region.shown ~= false then return region end
				end
			end
		end
		local function near(color, red, green, blue) return color and math.abs(color[1] - red / 255) < 0.01 and math.abs(color[2] - green / 255) < 0.01 and math.abs(color[3] - blue / 255) < 0.01 end
		check("the closed pill is the level chip by default in these tests", face().width == 64 and shown("Level 12") == nil and shown("12") ~= nil)
		addon.module.set("island", "closed_xp", true)
		check("the experience percent widens the pill", face().width > 64 and shown("45%") ~= nil)
		check("on the level chip too the percent is purple and the level white", near(shown("45%").color, 173, 118, 239) and near(shown("12").color, 245, 247, 250))
		addon.module.set("island", "closed_clock", true)
		check("the clock joins it", shown("14:05") ~= nil)
		state.bags = { [0] = 1, [1] = 1 }
		addon.island.pull()
		addon.module.set("island", "low_slots", 5)
		check("low bags warn on the pill without a setting, in the warning color", shown("Bags 2") ~= nil and shown("Bags 2").color[1] > shown("Bags 2").color[3])
		addon.module.set("island", "closed_xp", false)
		addon.module.set("island", "closed_clock", false)
		state.bags = { [0] = 6, [1] = 8 }
		addon.island.pull()
		addon.module.set("island", "low_slots", 1)
		check("with every extra off and nothing wrong it is the level chip again", face().width == 64)
	end
	do
		local addon, _, _, _, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "closed_xp", true)
		local function badge_point()
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == "45%" and region.shown ~= false then return region.point end
				end
			end
		end
		local quiet_offset = badge_point()[4]
		addon.island.notify({ source = "Test", key = "unread", text = "Something new" })
		check("an unread count moves the capsule badge left to clear it", badge_point()[4] < quiet_offset)
		local measure = dofile(root .. "/tests/lib/layout.lua").new()
		local function region_for(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return region end
				end
			end
		end
		local capsule, count = measure.rectangle(region_for("45%").parent), measure.rectangle(region_for("1"))
		local badge = measure.rectangle(region_for("45%"))
		check("the unread count sits on the same 12 inset as everything else, and the badge keeps 8 clear of it",
			capsule.right - count.right == 12 and count.left - badge.right == 8)
		local ring = measure.rectangle(region_for("~800 yd"))
		check("a label's box is a whole number of pixels wide, so what hangs from it lands on whole pixels",
			ring.left == math.floor(ring.left) and ring.width == math.floor(ring.width) and badge.width == math.floor(badge.width))
	end
	do
		local addon = island_world()
		check("the edge bars are gone as options", not pcall(addon.module.set, "island", "rim_top", "experience")
			and not pcall(addon.module.set, "island", "rim_bottom", "quest"))
		check("and so is their module", addon.island_rim == nil)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local function marks()
			local found = 0
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.path == "Interface\\Icons\\XP_Icon" and region.shown == true then found = found + 1 end
				end
			end
			return found
		end
		check("the closed pill has no corner mark", marks() == 0)
		env.everlook_island_key("down")
		check("the open island has none either, so nothing sits on the level text", marks() == 0)
	end
	do
		local addon, _, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		local over = true
		island_frame.IsMouseOver = function() return over end
		island_frame.scripts.OnEnter(island_frame)
		check("hovering opens the island", addon.island.view().mode == "open")
		island_frame.scripts.OnLeave(island_frame)
		local function fire_pending()
			for _, after in ipairs(afters) do
				if not after.done and after.delay == 0.1 then after.done = true; after.callback(); return true end
			end
		end
		fire_pending()
		check("moving onto a control inside the island does not close it", addon.island.view().mode == "open")
		fire_pending()
		check("and it keeps checking while the pointer stays inside", addon.island.view().mode == "open")
		over = false
		fire_pending()
		check("it closes once the pointer is really outside", addon.island.view().mode == "closed")
	end
	do
		local addon, env, event, state, _, _, frames = quest_world()
		env.QuestMapFrame_OpenToQuestDetails = function() end
		env.GetXPExhaustion = function() return 0 end
		env.GetServerTime = function() return 4000000 end
		env.UnitGUID = function() return "Player-1-00000005" end
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "quest_plan", true)
		addon.module.set("island", "feed_quest_ready", true)
		addon.module.set("island", "feed_experience", true)
		for index = 1, 4 do
			addon.island.notify({ source = "Test", key = "row" .. index, text = "Row " .. index, persist = index == 1,
				actions = { { id = "act", label = "Act", type = "callback", on_click = function() end } } })
		end
		state.xp = state.xp + 100
		event("PLAYER_XP_UPDATE")
		env.everlook_island_key("down")
		local clicked, failed = 0, {}
		local list = {}
		for _, frame in ipairs(frames) do
			if frame.scripts.OnClick and frame.shown ~= false then list[#list + 1] = frame end
		end
		for _, frame in ipairs(list) do
			for _, button in ipairs({ "LeftButton", "RightButton" }) do
				local ok, err = pcall(frame.scripts.OnClick, frame, button)
				clicked = clicked + 1
				if not ok then failed[#failed + 1] = tostring(frame.name or "?") .. ": " .. tostring(err) end
			end
		end
		check("there are buttons to click in a full island", #list >= 8)
		check("every button in a full island answers both clicks without an error", #failed == 0)
		if #failed > 0 then print(table.concat(failed, "\n")) end
	end
	do
		local addon, _, _, state, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		island_frame.scripts.OnClick(island_frame)
		check("a click pins the island open", addon.island.view().pinned == true)
		local cell
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if region.text == "Money" then cell = region.parent end
			end
		end
		state.time = state.time + 1
		cell.scripts.OnClick(cell)
		check("a click on a gauge cell does what a click beside it does", addon.island.view().pinned == false)
	end
	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = addon.island
		local function button(label)
			for _, frame in ipairs(frames) do
				if frame.action_id and frame.label and frame.label.text == label and frame.shown ~= false then return frame end
			end
		end
		local handle = api.notify({ source = "Test", text = "Plain" })
		check("a notice made without a key can still be updated", api.update(handle, { text = "Changed", detail = "More" }) == handle)
		local view = addon.island.view()
		check("an update changes the notice in place", #view.notices == 1 and view.notices[1].text == "Changed" and view.notices[1].detail == "More")
		local clicks = 0
		check("set_actions puts buttons on a showing notice", api.set_actions(handle, {
			{ id = "go", label = "Go", type = "callback", on_click = function() clicks = clicks + 1 end } }) == handle)
		check("the buttons appear and answer clicks", button("Go") ~= nil and (function()
			local go = button("Go"); go.scripts.OnClick(go, "LeftButton"); return clicks == 1 end)())
		check("a notice with buttons now defaults to the buttons interaction", addon.island.view().notices[1].interaction == "buttons")
		check("set_action_enabled greys a button out", api.set_action_enabled(handle, "go", false) == true
			and addon.island.view().notices[1].actions[1].enabled == false)
		local go = button("Go")
		go.scripts.OnClick(go, "LeftButton")
		check("a disabled button does not run", clicks == 1)
		check("and turning it on again lets it run", api.set_action_enabled(handle, "go", true) == true and (function()
			local again = button("Go"); again.scripts.OnClick(again, "LeftButton"); return clicks == 2 end)())
		check("setting the same state again reports no change", api.set_action_enabled(handle, "go", true) == false)
		check("an empty list clears the buttons", api.set_actions(handle, {}) == handle
			and #addon.island.view().notices[1].actions == 0 and addon.island.view().notices[1].interaction == nil)
		local _, reason = api.update(handle, { key = "other" })
		check("the key cannot be changed", reason == "invalid_update")
		_, reason = api.update(handle, { source = "Elsewhere" })
		check("nor the source", reason == "invalid_update")
		_, reason = api.update(9999, { text = "Nobody" })
		check("an unknown handle is named", reason == "unknown_handle")
		_, reason = api.update(handle, { text = "  " })
		check("an update goes through the same checks as a new notice", reason == "invalid_text")
		_, reason = api.set_action_enabled(handle, "missing", false)
		check("an unknown action is named", reason == "unknown_action")
		api.set_actions(handle, { { id = "go", label = "Go", type = "callback", on_click = function() end } })
		_, reason = api.set_action_enabled(handle, "go", "no")
		check("the enabled state must be a boolean", reason == "invalid_enabled")
	end
	do
		-- What the game does that the fake frames do not. The fakes keep their state in plain fields (.mouse,
		-- .point, .scripts and the like) that a real frame does not have, so production code that reads one of
		-- them works in the tests and silently does nothing in the game.
		local island_world = lib.island_world
		local layout = dofile(root .. "/tests/lib/layout.lua")

		do
			local listing = io.popen("cd " .. root .. " && ls Everlook*/*.lua")
			local fields = { "mouse", "point", "points", "clicks", "scripts", "regions", "animation_groups", "pass_through", "attributes", "scroll_child", "scroll_offset" }
			local offences = {}
			for path in listing:lines() do
				local handle = assert(io.open(root .. "/" .. path, "r"))
				local number = 0
				for line in handle:lines() do
					number = number + 1
					local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""')
					for _, field in ipairs(fields) do
						if code:find("[%w_%)%]]%." .. field .. "%f[^%w_]") then offences[#offences + 1] = path .. ":" .. number .. " ." .. field end
					end
				end
				handle:close()
			end
			listing:close()
			check("no addon code reads a field only the test frames have" .. (#offences > 0 and (": " .. table.concat(offences, ", ")) or ""), #offences == 0)
		end

		do
			local addon, _, _, _, _, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			local resting
			for _, frame in ipairs(frames) do if frame.name == "EverlookIslandResting" then resting = frame end end
			local kinds = {}
			for _, group in ipairs(resting and resting.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do kinds[#kinds + 1] = animation.kind end
			end
			local alpha = false
			for _, kind in ipairs(kinds) do alpha = alpha or kind == "Alpha" end
			check("the pill's body has a clock for its motion and no alpha animation that would fade it", #kinds > 0 and not alpha)
		end

		do
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			env.Everlook.island.notify({ source = "Test", key = "right", text = "Right click me", duration = 4,
				actions = { { id = "go", label = "Go", type = "callback", on_click = function() end } } })
			layout.settle(frames)
			local card
			for _, frame in ipairs(frames) do if frame.bound_entry and frame.scripts.OnMouseUp then card = frame end end
			check("a toast takes a right click to dismiss itself", card ~= nil and card.clicks ~= nil)
			local dismissed
			if card then
				card.scripts.OnMouseUp(card, "RightButton")
				dismissed = #addon.island.view().toasts == 0 or addon.island.view().toasts[1].phase == "exiting"
			end
			check("and the right click dismisses it", dismissed == true)
		end

		do
			-- A frame has no `shown` field. The pill's arrows turn only while their capsule is on screen.
			local addon, env, _, _, _, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			addon.module.set("island", "reduced_motion", true)
			local calls = 0
			env.Everlook.island.notify({ source = "A", key = "a", presentation = "status", text = "x", capsule = { arrow = function() calls = calls + 1; return 0 end } })
			layout.settle(frames)
			env.Everlook.island.notify({ source = "B", key = "b", presentation = "status", text = "y", capsule = { text = "y" } })
			layout.settle(frames)
			local driver
			for _, frame in ipairs(frames) do
				if frame.scripts and frame.scripts.OnUpdate and frame.parent and frame.parent.name == "EverlookIslandFace" then driver = frame end
			end
			calls = 0
			driver.scripts.OnUpdate(driver, 0.2)
			check("a capsule that has left the pill is not asked for its arrow", driver ~= nil and calls == 0)
		end
	end
	do
		-- Where the mouse goes. The fake frames know their strata, level, rectangle and whether they take the
		-- mouse, so a test can ask what is under a point the way the game does, and find a button that
		-- something else covers or clips.
		local island_world, quest_world = lib.island_world, lib.quest_world
		local layout = dofile(root .. "/tests/lib/layout.lua")

		local function inside(frame, ancestor)
			while frame do
				if frame == ancestor then return true end
				frame = frame.parent
			end
			return false
		end

		local function shown(frame)
			while frame do
				if frame.shown == false then return false end
				frame = frame.parent
			end
			return true
		end

		-- Every button that is on screen and takes clicks.
		local function pressable(frames)
			local list = {}
			for _, frame in ipairs(frames) do
				if frame.kind == "Button" and frame.mouse == true and frame.scripts.OnClick and shown(frame) then
					local rect = layout.new().rectangle(frame)
					if rect.width > 0 and rect.height > 0 then list[#list + 1] = frame end
				end
			end
			return list
		end

		-- The buttons the mouse would not reach at their middle.
		local function unreachable(frames, buttons)
			local lost = {}
			for _, button in ipairs(buttons) do
				local x, y = layout.center(button)
				local top = layout.hit(frames, x, y)
				if top ~= button and not inside(top, button) then lost[#lost + 1] = button end
			end
			return lost
		end

		local function open_world(how)
			local addon, env, _, _, afters, _, frames = quest_world()
			addon.module.set("island", "quest_context", true)
			addon.module.set("island", "quest_plan", true)
			addon.module.set("island", "reduced_motion", how.reduced)
			-- A notice changes the capsule, and its ease is still playing when the island opens.
			env.Everlook.island.notify({ source = "Test", key = "one", text = "A notice", detail = "with detail",
				actions = { { id = "go", label = "Go", type = "callback", on_click = function() end },
					{ id = "later", label = "Later", type = "callback", on_click = function() end } } })
			local island_frame
			for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then island_frame = frame end end
			if how.click then
				island_frame.IsMouseOver = function() return true end
				island_frame.scripts.OnClick(island_frame, "LeftButton")
			elseif how.pointer then
				island_frame.IsMouseOver = function() return true end
				island_frame.scripts.OnEnter(island_frame)
			else
				env.everlook_island_key("down")
			end
			layout.settle(frames)
			return addon, env, frames, afters
		end

		do
			-- A frame that takes the mouse and does nothing with it is a dead spot on the island.
			local _, _, frames = open_world({ reduced = true, click = true })
			local idle = {}
			for _, frame in ipairs(frames) do
				if frame.kind == "Button" and frame.mouse == true and shown(frame) and not frame.scripts.OnClick and not frame.scripts.OnMouseDown and not frame.scripts.OnMouseUp then
					local rect = layout.new().rectangle(frame)
					if rect.width > 0 and rect.height > 0 then idle[#idle + 1] = (frame.name or "button") .. " " .. rect.width .. "x" .. rect.height end
				end
			end
			check("every button that takes the mouse on the open island does something with a click" .. (#idle > 0 and (": " .. table.concat(idle, ", ")) or ""), #idle == 0)
		end

		do
			-- The buttons now outrank the island, so a pane that takes the mouse has to do what the island would have.
			local addon, _, frames = open_world({ reduced = true, click = true })
			local tested = 0
			local all_do = true
			for _, frame in ipairs(frames) do
				if frame.scroll_child and frame.mouse == true and shown(frame) then
					tested = tested + 1
					local before = addon.island.view().pinned
					local script = frame.scripts.OnMouseUp
					if script then script(frame, "LeftButton") end
					if addon.island.view().pinned == before then all_do = false end
					if script then script(frame, "LeftButton") end
				end
			end
			check("a click on empty space in a pane that takes the mouse toggles the pin, as the island does (" .. tested .. " panes)", tested >= 2 and all_do)
		end

		for _, how in ipairs({ { name = "by key", reduced = true }, { name = "by key, with motion", reduced = false },
			{ name = "by clicking", reduced = true, click = true }, { name = "by clicking, with motion", reduced = false, click = true },
			{ name = "by hovering", reduced = true, pointer = true }, { name = "by hovering, with motion", reduced = false, pointer = true } }) do
			local addon, _, frames = open_world(how)
			local view = addon.island.view()
			check("the island opened " .. how.name .. " is open and as large as its panes", view.mode == "open" and view.shell.width == view.width and view.shell.height == view.height)
			local buttons = pressable(frames)
			local lost = unreachable(frames, buttons)
			check("every button in the island opened " .. how.name .. " gets the mouse where it sits (" .. #buttons .. " checked, " .. #lost .. " lost)", #buttons > 5 and #lost == 0)
		end

		do
			local _, env, frames = open_world({ reduced = true })
			local buttons = pressable(frames)
			local island_frame
			for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then island_frame = frame end end
			local cover = env.CreateFrame("Frame", nil, nil)
			cover:SetFrameStrata("HIGH")
			cover:SetFrameLevel(90)
			cover:SetAllPoints(island_frame)
			cover:EnableMouse(true)
			check("a mouse-enabled frame laid over the buttons takes the mouse from them", #unreachable(frames, buttons) == #buttons)
			cover:EnableMouse(false)
			check("and with its mouse off the buttons have it back", #unreachable(frames, buttons) == 0)
		end
	end
end
