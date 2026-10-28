-- Island actions: the buttons and secure item and spell actions on a notice, notice lifetimes, and the built-in feeds that use them.
return function(check, lib)
	local source, island_world, quest_world, fire_after, finish_animations, secret_stat, notice_key = lib.source, lib.island_world, lib.quest_world, lib.fire_after, lib.finish_animations, lib.secret_stat, lib.notice_key
	local function button_named(frames, label)
		for index = 1, #frames do
			local frame = frames[index]
			if frame.action_id and frame.label and frame.label.text == label and frame.shown ~= false then return frame end
		end
	end
	local function callback(record, name)
		return function(handle, action_id) record[#record + 1] = { name = name, handle = handle, action = action_id } end
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api, seen = env.Everlook.island, {}
		local payload = { text = "Hearthstone ready", source = "everlook.hearth", key = "ready",
			actions = { { id = "look", label = "Inspect", type = "callback", on_click = callback(seen, "look") } } }
		local handle = api.notify(payload)
		payload.actions[1].label = "Changed"
		local notice = addon.island.view().notices[1]
		check("actions default to buttons and stay copied", handle and notice.interaction == "buttons" and notice.actions[1].label == "Inspect")
		local button = button_named(frames, "Inspect")
		check("a callback button is on the toast", button ~= nil)
		button.scripts.OnEnter(button)
		check("an action hover leaves the island preview closed", addon.island.view().mode == "closed" and addon.island.view().hovering == false)
		button.scripts.OnClick(button, "LeftButton")
		check("a callback receives the notice handle and action id", seen[1].handle == handle and seen[1].action == "look")
		local stale = button.scripts.OnClick
		api.notify({ text = "Hearthstone ready", source = "everlook.hearth", key = "ready",
			actions = { { id = "look", label = "Inspect", type = "callback", on_click = callback(seen, "next") } } })
		stale(button, "LeftButton")
		button = button_named(frames, "Inspect")
		button.scripts.OnClick(button, "LeftButton")
		check("a replaced callback ignores the previous click", #seen == 2 and seen[2].name == "next")
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Stay visible", duration = 4, interaction = "buttons",
			actions = { { id = "keep", label = "Keep", type = "callback", on_click = function() end } } })
		local button = button_named(frames, "Keep")
		state.time = state.time + 1
		button.scripts.OnEnter(button)
		fire_after(afters, 4)
		check("hovering an action pauses that toast", #addon.island.view().toasts == 1)
		state.time = state.time + 10
		button.scripts.OnLeave(button)
		check("leaving an action restarts the full lifetime", afters[#afters].delay == 4)
		fire_after(afters, 4)
		finish_animations(frames)
		check("the restarted lifetime still dismisses the toast", #addon.island.view().toasts == 0)
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "Leaving", duration = 4, interaction = "buttons",
			actions = { { id = "keep", label = "Keep", type = "callback", on_click = function() end } } })
		local button = button_named(frames, "Keep")
		state.time = state.time + 4
		fire_after(afters, 4)
		check("a toast whose clock ran out is leaving", addon.island.view().toasts[1].phase == "exiting")
		button.scripts.OnEnter(button)
		finish_animations(frames)
		check("the pointer reaching a leaving toast brings it back", #addon.island.view().toasts == 1
			and addon.island.view().toasts[1].phase == "visible")
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "Hovered", duration = 4, interaction = "buttons",
			actions = { { id = "keep", label = "Keep", type = "callback", on_click = function() end } } })
		local function pending(delay)
			local count = 0
			for index = 1, #afters do
				if afters[index].delay == delay and not afters[index].done then count = count + 1 end
			end
			return count
		end
		state.time = state.time + 1
		button_named(frames, "Keep").scripts.OnEnter(button_named(frames, "Keep"))
		local before = pending(4)
		env.everlook_island_key("down")
		state.time = state.time + 0.3
		env.everlook_island_key("up")
		check("opening the island releases a hover pause", addon.island.view().mode == "closed" and pending(4) == before + 1)
		fire_after(afters, 4)
		fire_after(afters, 4)
		finish_animations(frames)
		check("the released hover still dismisses the toast", #addon.island.view().toasts == 0)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local handle = api.notify({ text = "Session recap", detail = "One hour", interaction = "expand" })
		local card
		for index = 1, #frames do
			if frames[index].animation_groups and frames[index].scripts.OnClick then card = frames[index] end
		end
		card.scripts.OnClick(card, "LeftButton")
		local view = addon.island.view()
		check("click to expand opens that notice", view.mode == "open" and view.notices[1].id == handle and view.notices[1].detail == "One hour")
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api, seen = env.Everlook.island, {}
		api.notify({ text = "Mail is waiting", interaction = "inbox",
			actions = { { id = "later", label = "Later", type = "callback", on_click = callback(seen, "later") } } })
		local toast_mouse = true
		for index = 1, #frames do
			if frames[index].animation_groups then toast_mouse = frames[index].mouse end
		end
		check("inbox actions leave the toast click-through", toast_mouse == false and button_named(frames, "Later") == nil)
		env.everlook_island_key("down")
		local button = button_named(frames, "Later")
		button.scripts.OnClick(button, "LeftButton")
		check("inbox actions run from the open notice", seen[1].action == "later")
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api, seen, errors = env.Everlook.island, {}, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		api.notify({ text = "Quiet in combat", actions = { { id = "go", label = "Go", type = "callback", on_click = callback(seen, "go"), allow_in_combat = true },
			{ id = "stop", label = "Stop", type = "callback", on_click = callback(seen, "stop") } } })
		local go, stop = button_named(frames, "Go"), button_named(frames, "Stop")
		env.InCombatLockdown = function() return true end
		go.scripts.OnClick(go)
		stop.scripts.OnClick(stop)
		check("combat blocks ordinary callbacks and keeps the marked ones", #seen == 1 and seen[1].name == "go")
		env.InCombatLockdown = function() return false end
		api.notify({ text = "Broken action", actions = { { id = "fail", label = "Fail", type = "callback", on_click = function() error("boom") end } } })
		button_named(frames, "Fail").scripts.OnClick(button_named(frames, "Fail"))
		check("callback failures reach the error handler", type(errors[1]) == "string" and errors[1]:find("action fail", 1, true) and errors[1]:find("boom", 1, true))
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api, first_seen, second_seen = env.Everlook.island, {}, {}
		local first = api.notify({ text = "First card", actions = { { id = "one", label = "One", type = "callback", on_click = callback(first_seen, "one") } } })
		local stale = button_named(frames, "One").scripts.OnClick
		api.dismiss(first)
		finish_animations(frames)
		api.notify({ text = "Second card", actions = { { id = "two", label = "Two", type = "callback", on_click = callback(second_seen, "two") } } })
		stale()
		button_named(frames, "Two").scripts.OnClick(button_named(frames, "Two"))
		check("a reused toast cannot run the action from its previous notice", #first_seen == 0 and second_seen[1].name == "two")
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api, secret = env.Everlook.island, secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		local samples = {
			{ { text = "Bad mode", interaction = "popup" }, "invalid_interaction" },
			{ { text = "Secret mode", interaction = secret }, "invalid_interaction" },
			{ { text = "Too many", actions = { { id = "a", label = "A", type = "callback", on_click = function() end },
				{ id = "b", label = "B", type = "callback", on_click = function() end },
				{ id = "c", label = "C", type = "callback", on_click = function() end } } }, "invalid_actions" },
			{ { text = "Same id", actions = { { id = "a", label = "A", type = "callback", on_click = function() end },
				{ id = "a", label = "B", type = "item", item_id = 6948 } } }, "invalid_action_id" },
			{ { text = "Mixed", actions = { { id = "a", label = "A", type = "item", item_id = 6948, on_click = function() end } } }, "invalid_action" },
			{ { text = "Bad item", actions = { { id = "a", label = "A", type = "item", item_id = 0 } } }, "invalid_action_item" },
			{ { text = "Bad spell", actions = { { id = "a", label = "A", type = "spell", spell_id = secret } } }, "invalid_action" },
			{ { text = "Bad icon", item_id = secret }, "invalid_item_id" },
		}
		for index = 1, #samples do
			local ok, handle, reason = pcall(api.notify, samples[index][1])
			check("action payload " .. index .. " is rejected", ok and handle == nil and reason == samples[index][2] and #addon.island.view().notices == 0)
		end
		env.C_Item = { GetItemIconByID = function(item_id) return item_id == 6948 and 136535 or nil end }
		local handle = api.notify({ text = "Hearthstone ready", item_id = 6948 })
		local notice = addon.island.view().notices[1]
		local painted = false
		for index = 1, #frames do
			for _, region in ipairs(frames[index].regions or {}) do
				if region.path == 136535 then painted = true end
			end
		end
		check("item metadata is stored for the native icon", handle and notice.item_id == 6948 and notice.interaction == nil)
		check("a generic notice paints the item icon through the capsule", painted)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api, seen = env.Everlook.island, {}
		local handle = api.notify({ text = "Pinned action", actions = { { id = "go", label = "Go", type = "callback", on_click = callback(seen, "go") } } })
		local stale = button_named(frames, "Go").scripts.OnClick
		addon.module.set("island", "enabled", false)
		stale()
		check("disabling the island drops the notice and its click", #addon.island.view().notices == 0 and #seen == 0 and handle ~= nil)
	end

	local function attribute_frame(frames, key, value)
		for index = 1, #frames do
			local frame = frames[index]
			if frame.attributes and frame.attributes[key] == value then return frame end
		end
	end
	local function region_text(frames, snippet)
		for index = 1, #frames do
			for _, region in ipairs(frames[index].regions or {}) do
				if type(region.text) == "string" and region.text:find(snippet, 1, true) then return region.text end
			end
		end
	end
	local function under_named(frame, name)
		local guard = 0
		while frame and guard < 12 do
			if frame.name == name then return true end
			frame = frame.parent
			guard = guard + 1
		end
		return false
	end
	local function secure_point(card)
		local point = card.point
		return point and table.concat({ tostring(point[1]), tostring(point[4]), tostring(point[5]) }, ":")
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Hearthstone ready", actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
		api.notify({ text = "Blink ready", actions = { { id = "cast", label = "Blink", type = "spell", spell_id = 1953 } } })
		finish_animations(frames)
		local view = addon.island.view()
		local island
		for index = 1, #frames do
			if frames[index].name == "EverlookIsland" then island = frames[index] end
		end
		local item = attribute_frame(frames, "item", "item:6948")
		local spell = attribute_frame(frames, "spell", 1953)
		local top = -(island.point[5] or 0)
		local item_y = -(top + island.height - view.toasts[1].y)
		local spell_y = -(top + island.height - view.toasts[2].y)
		check("item and spell cards are secure roots under UIParent",
			item and spell and item.scripts.OnClick == nil and spell.scripts.OnClick == nil
			and item.template:find("SecureActionButtonTemplate", 1, true) == 1 and spell.template:find("SecureActionButtonTemplate", 1, true) == 1
			and item.parent.parent == env.UIParent and spell.parent.parent == env.UIParent
			and not under_named(item, "EverlookIsland") and not under_named(spell, "EverlookIsland")
			and item.parent.scale == 1 and spell.parent.scale == 1
			and item.parent.point[1] == "TOP" and item.parent.point[2] == env.UIParent and item.parent.point[5] == item_y
			and spell.parent.point[5] == spell_y and item.parent.width == view.toasts[1].width)
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Hearthstone ready", source = "everlook.hearth", key = "ready",
			actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
		env.InCombatLockdown = function() return true end
		local ok, err = pcall(function()
			event("PLAYER_REGEN_DISABLED")
			finish_animations(frames)
			addon.module.set("island", "position_x", 80)
			env.everlook_island_key("down")
			env.everlook_island_key("up")
			addon.island.scroll_to(40)
			env.everlook_island_key("down")
			env.everlook_island_key("up")
			finish_animations(frames)
		end)
		check("combat during entrance, scrolling and placement does not touch secure frames",
			ok == true and attribute_frame(frames, "item", "item:6948") == nil and err == nil)
		check("a protected notice waits until combat ends",
			addon.island.view().notices[1].deferred == true and region_text(frames, "Available after combat.") ~= nil)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:6948")
		check("the item card arms after combat without clicking itself",
			item ~= nil and item.shown ~= false and item.scripts.OnClick == nil and item.parent.shown ~= false)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local handle = api.notify({ text = "Hearthstone ready", source = "everlook.hearth", key = "ready", duration = 6,
			actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:6948")
		local card, before = item.parent, secure_point(item.parent)
		local label = region_text(frames, "Hearthstone ready")
		env.InCombatLockdown = function() return true end
		local blocked, message = pcall(function() card:SetPoint("TOP", env.UIParent, "TOP", 9, -9) end)
		event("PLAYER_REGEN_DISABLED")
		addon.module.set("island", "position_x", 80)
		env.everlook_island_key("down")
		addon.island.scroll_to(24)
		local dismissed, reason = api.dismiss(handle)
		local replaced, replace_reason = api.notify({ text = "Hearthstone moved", source = "everlook.hearth", key = "ready",
			actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
		local clicks = 0
		local original = card.scripts.OnMouseUp
		card.scripts.OnMouseUp = function(...)
			clicks = clicks + 1
			return original(...)
		end
		card.scripts.OnMouseUp(card, "RightButton")
		check("a frozen card rejects programmatic changes and keeps its secure click",
			blocked == false and type(message) == "string" and message:find("protected", 1, true)
			and dismissed == nil and reason == "combat_locked" and replaced == nil and replace_reason == "combat_locked"
			and secure_point(card) == before and region_text(frames, "Hearthstone ready") == label
			and card.shown ~= false and clicks == 1 and addon.island.view().notices[1].text == "Hearthstone ready"
			and addon.island.view().notices[1].frozen == true and #addon.island.view().toasts == 1)
		state.time = state.time + 1
		fire_after(afters, 6)
		check("a frozen card ignores the timer that was running", card.shown ~= false and #addon.island.view().toasts == 1)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		finish_animations(frames)
		check("the player's combat dismiss removes the card when combat ends",
			clicks == 1 and card.shown == false and #addon.island.view().notices == 0)
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		env.InCombatLockdown = function() return true end
		event("PLAYER_REGEN_DISABLED")
		local handle = api.notify({ text = "Soulstone", actions = { { id = "use", label = "Use", type = "item", item_id = 16892 } } })
		finish_animations(frames)
		check("a new protected notice during combat is visible and unarmed",
			handle and attribute_frame(frames, "item", "item:16892") == nil
			and region_text(frames, "Available after combat.") ~= nil and #addon.island.view().toasts == 1)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:16892")
		check("that notice arms only after combat", item ~= nil and item.scripts.OnClick == nil)
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Frozen loot", actions = { { id = "use", label = "Inspect", type = "item", item_id = 17182 } } })
		api.notify({ text = "Ordinary one" })
		api.notify({ text = "Ordinary two" })
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:17182")
		env.InCombatLockdown = function() return true end
		event("PLAYER_REGEN_DISABLED")
		api.notify({ text = "Incoming damage", severity = "error" })
		local phases = {}
		for _, toast in ipairs(addon.island.view().toasts) do phases[toast.text] = toast.phase end
		check("an error toast leaves a frozen protected card in its slot",
			item.parent.shown ~= false and phases["Frozen loot"] ~= "exiting" and phases["Ordinary one"] == "exiting"
			and addon.island.view().notices[1].frozen == true)
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Hearthstone ready", actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:6948")
		env.InCombatLockdown = function() return true end
		event("PLAYER_REGEN_DISABLED")
		addon.module.set("island", "enabled", false)
		check("disabling during combat keeps the secure card",
			addon.island.view().shown == false and item.parent.shown ~= false and #addon.island.view().notices == 1)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		finish_animations(frames)
		check("combat exit clears a card whose module is off", item.parent.shown == false and #addon.island.view().notices == 0)
	end
	do
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Frozen loot", source = "loot", key = "frozen", actions = { { id = "use", label = "Inspect", type = "item", item_id = 17182 } } })
		api.notify({ text = "Ordinary note", source = "notes", key = "one" })
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:17182")
		env.InCombatLockdown = function() return true end
		event("PLAYER_REGEN_DISABLED")
		local cleared = addon.island.clear_history()
		local texts = {}
		for _, notice in ipairs(addon.island.view().notices) do texts[#texts + 1] = notice.text end
		local again = addon.island.clear_history()
		check("clear history skips a frozen card",
			cleared == true and again == false and texts[1] == "Frozen loot" and #texts == 1 and item.parent.shown ~= false)
		env.InCombatLockdown = function() return false end
		addon.island.undo_clear()
		local restored
		for _, notice in ipairs(addon.island.view().notices) do
			if notice.text == "Ordinary note" then restored = true end
		end
		check("undo restores only the notices clear history removed", restored == true and item.parent.shown ~= false)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Short hearth", duration = 2, actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:6948")
		env.InCombatLockdown = function() return true end
		event("PLAYER_REGEN_DISABLED")
		state.time = state.time + 5
		fire_after(afters, 2)
		check("expiry waits while the card is frozen", item.parent.shown ~= false and #addon.island.view().toasts == 1)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		finish_animations(frames)
		check("an expired frozen card leaves when combat ends", item.parent.shown == false and #addon.island.view().notices == 0)
	end
	do
		local addon, env, event, state, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Stay armed", duration = 8, actions = { { id = "use", label = "Hearth", type = "item", item_id = 6948 } } })
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:6948")
		local before = secure_point(item.parent)
		env.InCombatLockdown = function() return true end
		event("PLAYER_REGEN_DISABLED")
		addon.module.set("island", "position_x", 40)
		check("combat movement leaves an armed card where it was", secure_point(item.parent) == before and item.parent.shown ~= false)
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		state.time = state.time + 1
		check("combat exit keeps the card armed and lets it follow the island",
			item.parent.shown ~= false and item.attributes.item == "item:6948" and item.scripts.OnClick == nil
			and secure_point(item.parent) ~= before and item.parent.point[4] == 40
			and #addon.island.view().toasts == 1 and addon.island.view().notices[1].frozen ~= true)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		api.notify({ text = "Item first", actions = {
			{ id = "use", label = "Hearth", type = "item", item_id = 6948 },
			{ id = "look", label = "Inspect", type = "callback", on_click = function() end },
		} })
		api.notify({ text = "Callback first", actions = {
			{ id = "look", label = "Details", type = "callback", on_click = function() end },
			{ id = "cast", label = "Blink", type = "spell", spell_id = 1953 },
		} })
		finish_animations(frames)
		local item = attribute_frame(frames, "item", "item:6948")
		local spell = attribute_frame(frames, "spell", 1953)
		local inspect = button_named(frames, "Inspect")
		local details = button_named(frames, "Details")
		check("mixed actions keep their order on one row",
			item and spell and inspect and details
			and item.point[4] == 40 and inspect.point[4] == 168
			and details.point[4] == 40 and spell.point[4] == 168)
	end
	local function feed_tests()
		local function listed(order, id)
			for index = 1, #(order or {}) do
				if order[index].id == id then return true end
			end
		end
		do
			local addon, env, event, state, _, _, frames = quest_world()
			check("quest feeds start off", addon.module.get("island", "feed_quest_ready") == false and addon.island.view().quests == nil)
			state.quests[1].ready = true
			event("QUEST_LOG_UPDATE")
			check("a ready quest stays quiet while the feed is off", #addon.island.view().notices == 0)
			local opened = {}
			env.QuestMapFrame_OpenToQuestDetails = function(quest_id) opened[#opened + 1] = quest_id end
			addon.module.set("island", "feed_quest_ready", true)
			check("the first ready scan keeps quests that were already ready", #addon.island.view().notices == 0)
			state.quests[2].ready = true
			event("QUEST_LOG_UPDATE")
			local notice = notice_key(addon, "ready")
			check("a newly ready quest is announced once", notice and notice.text == "Suitable farther" and notice.detail == "Ready to turn in"
				and notice.persist == true and notice.actions[1].label == "View quest" and notice.actions[2].label == "Pin" and notice_key(addon, "ready:23") == nil)
			button_named(frames, "View quest").scripts.OnClick(button_named(frames, "View quest"))
			check("view quest opens the native details", opened[1] == 22)
			button_named(frames, "Pin").scripts.OnClick(button_named(frames, "Pin"))
			addon.module.set("island", "quest_context", true)
			local quests = addon.island.view().quests
			check("pin keeps that quest when the capsule is turned on", quests.current.id == 22 and quests.pinned == 22)
			state.quests[2].ready = false
			event("QUEST_LOG_UPDATE")
			check("leaving turn-in dismisses that notice", notice_key(addon, "ready") == nil)
			state.quests[2].ready = true
			event("QUEST_LOG_UPDATE")
			check("becoming ready again announces a new transition", notice_key(addon, "ready") ~= nil)
			state.quests[1].ready = false
			event("QUEST_LOG_UPDATE")
			state.quests[1].ready = true
			event("QUEST_LOG_UPDATE")
			notice = notice_key(addon, "ready")
			check("several ready quests share one notice", notice and notice.text == "2 quests ready" and notice.persist == true and #addon.island.view().notices == 1)
			button_named(frames, "View quest").scripts.OnClick(button_named(frames, "View quest"))
			check("view quest follows the latest ready quest", opened[#opened] == 21)
			state.quests[1].ready = false
			event("QUEST_LOG_UPDATE")
			check("a smaller ready set keeps the remaining quest", notice_key(addon, "ready").text == "Suitable farther")
			state.quests[2].ready = false
			event("QUEST_LOG_UPDATE")
			check("the ready notice leaves when none of this session remain", notice_key(addon, "ready") == nil)
		end
		do
			local addon, env, event, state, _, _, frames = quest_world()
			check("next quest starts off and leaves the capsule alone", addon.module.get("island", "feed_quest_next") == false and addon.island.view().quests == nil)
			addon.module.set("island", "feed_quest_next", true)
			check("the first planner scan is quiet", #addon.island.view().notices == 0 and addon.island.view().quests == nil)
			state.quests[3].distance = 1200
			event("QUEST_LOG_UPDATE")
			local first = notice_key(addon, "next-quest")
			check("a planner change toasts once", first and first.text == "Suitable farther" and first.presentation == "toast" and first.detail == "Suggested next")
			state.quests[1].level, state.quests[1].distance = 12, 50
			event("QUEST_LOG_UPDATE")
			local second = notice_key(addon, "next-quest")
			check("a second change within 30 seconds stays in the inbox", second and second.id == first.id and second.text == "Nearby dangerous" and second.presentation == "inbox")
			state.time = state.time + 30
			state.quests[2].distance = 10
			event("QUEST_LOG_UPDATE")
			local third = notice_key(addon, "next-quest")
			check("a later planner change can toast again", third and third.text == "Suitable farther" and third.presentation == "toast")
			button_named(frames, "Pin").scripts.OnClick(button_named(frames, "Pin"))
			addon.module.set("island", "quest_context", true)
			local quests = addon.island.view().quests
			check("pin from the next-quest notice sticks", quests.pinned == 22 and quests.current.id == 22)
		end
		-- A new quest is offered once. The pin offer, the suggestion and the ready notice
		-- all point at the same quest, so only the first of them speaks.
		local function new_quest_world(ready, distance)
			local addon, env, event, state = quest_world()
			state.quests[3].ready = false
			for _, name in ipairs({ "feed_quest_ready", "feed_quest_next", "quest_context", "quest_plan" }) do
				addon.module.set("island", name, true)
			end
			table.insert(state.quests, { questID = 25, title = "A fresh errand", level = 12, distance = distance or 5, ready = ready,
				objectives = { { text = "Fetch", numFulfilled = 0, numRequired = 3, finished = false } } })
			state.time = state.time + 100
			event("QUEST_ACCEPTED", 25)
			event("QUEST_LOG_UPDATE")
			return addon
		end
		do
			local addon = new_quest_world(false, 5000)
			local offer = notice_key(addon, "pin-suggest")
			check("a new quest the island is not showing is offered for pinning", offer and offer.text == "Pin A fresh errand?")
			check("and is not suggested next as well", notice_key(addon, "next-quest") == nil)
		end
		do
			local addon = new_quest_world(false, 5)
			check("a new quest the island already shows is not offered for pinning", addon.island.view().quests.current.id == 25
				and notice_key(addon, "pin-suggest") == nil)
			check("nor suggested next, which the island already shows", notice_key(addon, "next-quest") == nil)
		end
		do
			local addon, _, event, state = quest_world()
			for _, name in ipairs({ "feed_quest_next", "quest_context", "quest_plan" }) do
				addon.module.set("island", name, true)
			end
			addon.island.pin_quest(21)
			state.quests[3].distance = 1200
			event("QUEST_LOG_UPDATE")
			check("a suggestion the island is not showing, because another quest is pinned, is announced",
				addon.island.view().quests.current.id == 21 and notice_key(addon, "next-quest") ~= nil)
		end
		do
			local addon = new_quest_world(true)
			local ready = notice_key(addon, "ready")
			check("a new quest that is already ready says so", ready and ready.text == "A fresh errand")
			check("and is not offered for pinning as well", notice_key(addon, "pin-suggest") == nil)
			check("nor suggested next as well", notice_key(addon, "next-quest") == nil)
		end
		do
			local addon, env, event, state, _, _, frames = quest_world()
			addon.module.set("island", "feed_quest_next", true)
			state.quests[3].distance = 1200
			event("QUEST_LOG_UPDATE")
			button_named(frames, "Skip").scripts.OnClick(button_named(frames, "Skip"))
			local skipped = notice_key(addon, "next-quest")
			check("skip leaves the current suggestion immediately", skipped and skipped.text == "Ready to return")
			addon.module.set("island", "quest_context", true)
			addon.module.set("island", "quest_plan", true)
			local quests = addon.island.view().quests
			check("a skipped quest stays in the planned order", quests.suggested ~= 22 and listed(quests.order, 22))
			state.quests[2].distance = 10
			event("QUEST_LOG_UPDATE")
			check("a skipped quest stays out after a large score change", notice_key(addon, "next-quest").text == "Ready to return")
			local removed = table.remove(state.quests, 2)
			event("QUEST_LOG_UPDATE")
			table.insert(state.quests, 2, removed)
			removed.distance = 10
			event("QUEST_LOG_UPDATE")
			check("removing a quest from the log clears its skip", addon.island.view().quests.suggested == 22)
			check("and the island, now showing it, drops the notice", notice_key(addon, "next-quest") == nil)
		end
		do
			local addon, _, event, state, _, _, frames = quest_world()
			addon.module.set("island", "feed_quest_next", true)
			state.quests[3].distance = 1200
			event("QUEST_LOG_UPDATE")
			button_named(frames, "Skip").scripts.OnClick(button_named(frames, "Skip"))
			addon.module.set("island", "enabled", false)
			addon.module.set("island", "enabled", true)
			check("ending the session clears a skip without announcing the baseline", #addon.island.view().notices == 0)
			state.quests[2].distance = 5000
			event("QUEST_LOG_UPDATE")
			check("the previously skipped quest can be suggested again", notice_key(addon, "next-quest").text == "Ready to return")
		end
		do
			local addon, env, event, state, _, tickers, frames = island_world()
			addon.module.set("island", "enabled", true)
			local qualities = {}
			local function link(item_id, name)
				return "|cff0070dd|Hitem:" .. item_id .. "::::::::|h[" .. name .. "]|h|r"
			end
			local function receive(item_id, name, count)
				local item = link(item_id, name)
				if count then return "You receive loot: " .. item .. "x" .. count .. "." end
				return "You receive loot: " .. item .. "."
			end
			env.C_Item = { GetItemQualityByID = function(item_id) return qualities[item_id] end }
			addon.module.set("island", "feed_loot", true)
			qualities[19019] = 3
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			check("loot without the self formats stays quiet", #addon.island.view().notices == 0)
			env.LOOT_ITEM_SELF = "You receive loot: %s."
			env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
			addon.module.set("island", "feed_loot", false)
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			check("rare loot stays quiet while the feed is off", #addon.island.view().notices == 0)
			addon.module.set("island", "feed_loot", true)
			qualities[19019] = 2
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			qualities[19019] = nil
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			local secret = secret_stat()
			env.issecretvalue = function(value) return rawequal(value, secret) end
			qualities[19019] = secret
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			event("CHAT_MSG_LOOT", secret)
			event("CHAT_MSG_LOOT", "Grom receives loot: " .. link(19019, "Thunderfury") .. ".")
			check("common, missing, secret and other players' loot are omitted", #addon.island.view().notices == 0)
			qualities[19019] = 3
			local inspected = {}
			env.GameTooltip = {
				SetOwner = function() end,
				SetItemByID = function(_, item_id) inspected[#inspected + 1] = item_id end,
				Show = function() end,
			}
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			local loot = notice_key(addon, "loot:19019:1")
			check("confirmed rare loot is announced", loot and loot.text == "Thunderfury" and loot.detail == "Rare loot" and loot.item_id == 19019)
			button_named(frames, "Inspect").scripts.OnClick(button_named(frames, "Inspect"))
			check("inspect shows the item tooltip", inspected[1] == 19019)
			state.time = state.time + 1
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			loot = notice_key(addon, "loot:19019:1")
			check("the same item within two seconds stays one notice", loot and loot.text == "Thunderfury x2" and notice_key(addon, "loot:19019:2") == nil)
			state.time = state.time + 3
			event("CHAT_MSG_LOOT", receive(19019, "Thunderfury"))
			loot = notice_key(addon, "loot:19019:2")
			check("the same item after two seconds joins the live loot notice", loot and loot.text == "Thunderfury" and loot.count == 2 and notice_key(addon, "loot:19019:1") == nil)
			env.Enum = { ItemQuality = { Rare = 4 } }
			qualities[12345] = 3
			event("CHAT_MSG_LOOT", receive(12345, "Blue Gem"))
			check("quality below the rare enum is omitted", notice_key(addon, "loot:12345:1") == nil)
			qualities[12345] = 4
			event("CHAT_MSG_LOOT", receive(12345, "Blue Gem"))
			check("quality at the rare enum joins the live loot notice", notice_key(addon, "loot:12345:1").text == "Blue Gem" and notice_key(addon, "loot:12345:1").count == 3 and #addon.island.view().notices == 1)
			env.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
			env.LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
			env.LOOT_ITEM_BONUS_ROLL_SELF = "You receive bonus loot: %s."
			env.LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d."
			qualities[19020] = 4
			event("CHAT_MSG_LOOT", "You receive item: " .. link(19020, "Bag Rare") .. ".")
			local pushed = notice_key(addon, "loot:19020:1")
			check("direct-to-bag rare loot is announced", pushed and pushed.text == "Bag Rare")
			event("CHAT_MSG_LOOT", "You receive item: " .. link(19020, "Bag Rare") .. "x3.")
			pushed = notice_key(addon, "loot:19020:1")
			check("direct-to-bag stacks combine", pushed and pushed.text == "Bag Rare x4")
			qualities[19021] = 4
			event("CHAT_MSG_LOOT", "You receive bonus loot: " .. link(19021, "Bonus Gem") .. ".")
			local bonus = notice_key(addon, "loot:19021:1")
			check("bonus rare loot is announced", bonus and bonus.text == "Bonus Gem")
			event("CHAT_MSG_LOOT", "You create: " .. link(19021, "Bonus Gem") .. ".")
			event("CHAT_MSG_LOOT", "Grom receives item: " .. link(19022, "Other Rare") .. ".")
			bonus = notice_key(addon, "loot:19021:1")
			check("crafted items and another player's pushed item stay quiet", bonus and bonus.text == "Bonus Gem" and notice_key(addon, "loot:19022:1") == nil)
			env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %1$sx%2$d."
			qualities[19023] = 4
			event("CHAT_MSG_LOOT", "You receive loot: " .. link(19023, "Positional") .. "x2.")
			local positional = notice_key(addon, "loot:19023:1")
			check("positional loot counts are announced", positional and positional.text == "Positional x2")
			env.LOOT_ITEM_SELF_MULTIPLE = nil
			qualities[19024] = 4
			event("CHAT_MSG_LOOT", receive(19024, "Single Only"))
			local single = notice_key(addon, "loot:19024:1")
			check("a missing multiple format still announces one item", single and single.text == "Single Only")
		end
		do
			local addon, env, event, state, _, tickers, frames = island_world()
			addon.module.set("island", "enabled", true)
			local count, cooldown = 0, { 0, 0, true }
			env.C_Item = {
				GetItemCount = function(item_id) return item_id == 6948 and count or 0 end,
				GetItemCooldown = function(item_id)
					if item_id == 6948 then return cooldown[1], cooldown[2], cooldown[3] end
				end,
			}
			addon.module.set("island", "feed_hearth", true)
			check("an empty hearth bag stays quiet", #addon.island.view().notices == 0)
			count = 1
			event("BAG_UPDATE_DELAYED")
			check("a hearthstone that is already ready stays quiet", notice_key(addon, "hearth:ready") == nil)
			cooldown[1], cooldown[2], cooldown[3] = state.time, 1.5, true
			tickers[1].callback()
			cooldown[1], cooldown[2], cooldown[3] = 0, 0, true
			tickers[1].callback()
			check("a global cooldown does not announce the hearthstone", notice_key(addon, "hearth:ready") == nil)
			cooldown[1], cooldown[2] = state.time, 60
			tickers[1].callback()
			check("a hearthstone going on cooldown stays quiet", notice_key(addon, "hearth:ready") == nil)
			local restore = env.C_Item.GetItemCooldown
			env.C_Item.GetItemCooldown = function() end
			tickers[1].callback()
			check("an unreadable cooldown does not count as ready", notice_key(addon, "hearth:ready") == nil)
			env.C_Item.GetItemCooldown = restore
			cooldown[1], cooldown[2], cooldown[3] = 0, 0, false
			tickers[1].callback()
			cooldown[3] = 0
			tickers[1].callback()
			check("a disabled cooldown timer stays quiet", notice_key(addon, "hearth:ready") == nil)
			cooldown[3] = true
			tickers[1].callback()
			finish_animations(frames)
			local item = attribute_frame(frames, "item", "item:6948")
			local notice = notice_key(addon, "hearth:ready")
			check("a finished hearth cooldown announces a secure hearth", notice and notice.text == "Hearthstone ready" and notice.item_id == 6948
				and item and item.attributes.item == "item:6948" and item.scripts.OnClick == nil)
			button_named(frames, "Inspect").scripts.OnClick(button_named(frames, "Inspect"))
			cooldown[1], cooldown[2], cooldown[3] = state.time, 30, true
			tickers[1].callback()
			finish_animations(frames)
			check("going on cooldown dismisses the hearth notice", notice_key(addon, "hearth:ready") == nil)
			cooldown[1], cooldown[2], cooldown[3] = 0, 0, 1
			tickers[1].callback()
			finish_animations(frames)
			item = attribute_frame(frames, "item", "item:6948")
			check("a numeric cooldown enable still arms the hearth", notice_key(addon, "hearth:ready") ~= nil and item and item.attributes.item == "item:6948")
			env.InCombatLockdown = function() return true end
			event("PLAYER_REGEN_DISABLED")
			addon.module.set("island", "feed_hearth", false)
			check("turning hearth off during combat leaves the armed card", item.parent.shown ~= false and notice_key(addon, "hearth:ready") ~= nil)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			tickers[1].callback()
			finish_animations(frames)
			check("the hearth card leaves once combat ends", item.parent.shown == false and notice_key(addon, "hearth:ready") == nil)
		end
	end
	local function later_feed_tests()
		do
			local addon, env, event, _, _, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			local factions = {
				{ factionID = 47, name = "Stormwind", reaction = 5, isHeader = false },
				{ factionID = 9, name = "Classic", reaction = 4, isHeader = true },
				{ factionID = 72, name = "Alliance", reaction = 4, isHeader = true, isHeaderWithRep = true },
			}
			env.C_Reputation = {
				GetNumFactions = function() return #factions end,
				GetFactionDataByIndex = function(index) return factions[index] end,
			}
			local opened
			env.ToggleCharacter = function(name) opened = name end
			env.FACTION_STANDING_LABEL6 = "Honored"
			check("reputation starts off", addon.module.get("island", "feed_reputation") == false)
			addon.module.set("island", "feed_reputation", true)
			check("the first reputation scan is quiet", #addon.island.view().notices == 0)
			factions[1].reaction = 6
			factions[2].reaction = 6
			event("UPDATE_FACTION")
			local notice = notice_key(addon, "rep:47")
			check("a standing increase is announced once", notice and notice.text == "Stormwind" and notice.detail == "Honored" and notice_key(addon, "rep:9") == nil)
			button_named(frames, "Open reputation").scripts.OnClick(button_named(frames, "Open reputation"))
			check("open reputation uses the character pane", opened == "ReputationFrame")
			factions[3].reaction = 5
			event("UPDATE_FACTION")
			check("a header that tracks reputation can increase", notice_key(addon, "rep:72").text == "Alliance" and notice_key(addon, "rep:72").detail == "Standing increased")
			local secret = secret_stat()
			env.issecretvalue = function(value) return rawequal(value, secret) end
			factions[1].reaction = secret
			event("UPDATE_FACTION")
			factions[1].reaction = 6
			factions[1].currentStanding = 9999
			event("UPDATE_FACTION")
			check("secret or same-rank reputation does not add a standing", notice_key(addon, "rep:72").text == "Alliance" and notice_key(addon, "rep:72").detail == "Standing increased" and notice_key(addon, "rep:72").count == 2 and notice_key(addon, "rep:47") == nil and #addon.island.view().notices == 1)
		end
		do
			local addon, env, event, state, _, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			local skills = { name = "Blacksmithing", skill = 20, line = 164 }
			env.GetProfessions = function() return 1 end
			env.GetProfessionInfo = function() return skills.name, nil, skills.skill, 300, 0, 0, skills.line end
			local opened
			env.ToggleProfessionsBook = function() opened = true end
			addon.module.set("island", "feed_professions", true)
			check("the first profession scan is quiet", #addon.island.view().notices == 0)
			skills.skill = 24
			event("SKILL_LINES_CHANGED")
			check("skill below the next 25 is quiet", #addon.island.view().notices == 0)
			skills.skill = 60
			event("SKILL_LINES_CHANGED")
			local first = notice_key(addon, "professions:1")
			check("a skill jump announces the highest 25-point milestone", first and first.text == "Blacksmithing reached 50")
			state.time = state.time + 1
			event("NEW_RECIPE_LEARNED", 333)
			first = notice_key(addon, "professions:1")
			check("a recipe in the same burst updates that notice", first and first.text == "Blacksmithing reached 50. New recipe" and notice_key(addon, "professions:2") == nil)
			local secret = secret_stat()
			env.issecretvalue = function(value) return rawequal(value, secret) end
			event("NEW_RECIPE_LEARNED", secret)
			check("a secret recipe is omitted", notice_key(addon, "professions:1").text == "Blacksmithing reached 50. New recipe")
			state.time = state.time + 3
			skills.skill = 80
			event("SKILL_LINES_CHANGED")
			check("a later milestone joins the craft notice", notice_key(addon, "professions:2").text == "Blacksmithing reached 75" and notice_key(addon, "professions:2").count == 2 and notice_key(addon, "professions:1") == nil and #addon.island.view().notices == 1)
			button_named(frames, "Open professions").scripts.OnClick(button_named(frames, "Open professions"))
			check("open professions uses the profession book", opened == true)
		end
		do
			-- GetProfessions gives nil for an empty slot: here one primary profession and fishing,
			-- with no second primary, no archaeology and no cooking.
			local addon, env, event = island_world()
			addon.module.set("island", "enabled", true)
			local skills = { [1] = { "Blacksmithing", 20, 164 }, [4] = { "Fishing", 20, 356 } }
			env.GetProfessions = function() return 1, nil, nil, 4, nil end
			env.GetProfessionInfo = function(slot)
				local row = skills[slot]
				return row[1], nil, row[2], 300, 0, 0, row[3]
			end
			addon.module.set("island", "feed_professions", true)
			skills[4][2] = 60
			event("SKILL_LINES_CHANGED")
			local notice = notice_key(addon, "professions:1")
			check("a profession after an empty slot is still followed", notice and notice.text == "Fishing reached 50")
		end
		do
			local addon, env, event, state, _, tickers, frames = island_world()
			addon.module.set("island", "enabled", true)
			local pending = true
			env.HasNewMail = function() return pending end
			addon.module.set("island", "feed_mail", true)
			check("mail that is already waiting stays quiet", notice_key(addon, "mail:new") == nil)
			pending = false
			event("UPDATE_PENDING_MAIL")
			pending = true
			event("UPDATE_PENDING_MAIL")
			local mail = notice_key(addon, "mail:new")
			check("new mail becomes one notice", mail and mail.text == "New mail" and #addon.island.view().notices == 1)
			button_named(frames, "Remind in five minutes").scripts.OnClick(button_named(frames, "Remind in five minutes"))
			check("remind dismisses the mail notice", notice_key(addon, "mail:new") == nil)
			state.time = state.time + 299
			tickers[1].callback()
			check("the reminder waits five minutes", notice_key(addon, "mail:new") == nil)
			state.time = state.time + 1
			tickers[1].callback()
			check("the reminder returns while mail is still waiting", notice_key(addon, "mail:new") ~= nil)
			pending = false
			event("UPDATE_PENDING_MAIL")
			check("read mail dismisses the notice", notice_key(addon, "mail:new") == nil)
		end
		do
			local addon, env, event, state, _, tickers, frames = island_world()
			addon.module.set("island", "enabled", true)
			local buttons = {}
			env.CreateSettingsButtonInitializer = function(name, _, click)
				return { name = name, click = click }
			end
			local module
			for _, candidate in ipairs(addon.module.modules) do
				if candidate.id == "island" then module = candidate end
			end
			for _, section in ipairs(addon.module.sections(module)) do
				if section.after then section.after({ AddInitializer = function(_, row) buttons[row.name] = row end }) end
			end
			check("session recap starts off", buttons["Session recap"] and buttons["Session recap"].click() == false and #addon.island.view().notices == 0)
			addon.module.set("island", "feed_recap", true)
			check("turning on the recap does not announce the baseline", #addon.island.view().notices == 0)
			state.time = state.time + 1799
			tickers[1].callback()
			check("the recap waits thirty minutes", #addon.island.view().notices == 0)
			state.time = state.time + 1
			tickers[1].callback()
			local recap = notice_key(addon, "session-recap")
			check("the half-hour recap expands a zero summary", recap and recap.interaction == "expand" and recap.text == "Session recap"
				and recap.detail:find("Quests completed: 0", 1, true) and recap.detail:find("XP gained: 0", 1, true)
				and recap.detail:find("Net money: 0c", 1, true) and recap.detail:find("Elapsed: 30 minutes", 1, true))
			state.xp = 600
			event("PLAYER_XP_UPDATE")
			state.level, state.xp, state.xp_max = 13, 10, 2000
			event("PLAYER_LEVEL_UP", 13)
			state.money = 22345
			event("PLAYER_MONEY")
			event("QUEST_TURNED_IN", 55)
			state.time = state.time + 1800
			tickers[1].callback()
			recap = notice_key(addon, "session-recap")
			check("the next recap keeps one row and records the gains", recap and recap.detail:find("Quests completed: 1", 1, true)
				and recap.detail:find("XP gained: 560", 1, true) and recap.detail:find("Net money: +1g", 1, true) and recap.money == nil)
			check("show recap publishes the current summary", buttons["Session recap"].click() == true and notice_key(addon, "session-recap") ~= nil)
		end
	end
	local function experience_ledger()
		local function open_world(setup)
			local addon, env, _, state = island_world()
			state.level, state.xp, state.xp_max = 10, 0, 1000
			state.guid, state.server, state.exhaustion = "Player-1-ABC", 1000800, nil
			env.GetServerTime = function() return state.server end
			env.UnitGUID = function() return state.guid end
			env.GetXPExhaustion = function() return state.exhaustion end
			env.GetMaxPlayerLevel = function() return 60 end
			env.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
			env.COMBATLOG_XPGAIN_FIRSTPERSON_GROUP = "%s dies, you gain %d experience. (+%d group bonus)"
			env.COMBATLOG_XPGAIN_EXHAUSTION1 = "%s dies, you gain %d experience. (%s exp %s bonus)"
			env.COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED = "You gain %d experience."
			if setup then setup(state, env) end
			addon.module.set("island", "enabled", true)
			return addon, env, state
		end
		local function joined(report)
			return table.concat(report.lines, "\n")
		end
		local addon, env, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		local report = addon.island_experience.report()
		check("the first plain reading stores a baseline and adds 0",
			report.ready and report.hour.total == 0 and report.day.total == 0
			and env.EverlookSaved.island_experience["Player-1-ABC"].baseline.xp == 0
			and joined(report):find("Hour  0", 1, true) and not joined(report):find("XP incomplete", 1, true))
		state.xp = 250
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a same-level gain lands in the hour and the day",
			report.hour.total == 250 and report.day.total == 250 and report.hour.other == 250
			and report.hour.quest == 0 and report.hour.kill == 0
			and env.EverlookSaved.island_experience["Player-1-ABC"].buckets["1000800"].total == 250)

		addon, env, state = open_world(function(state)
			state.xp, state.xp_max = 900, 1000
		end)
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.level, state.xp = 11, 10
		addon.island_experience.on_event("PLAYER_LEVEL_UP", 11)
		report = addon.island_experience.report()
		check("a one-level wrap counts the rest of the old bar and one level",
			report.day.total == 110 and report.day.levels == 1 and joined(report):find("Day  110   1 level", 1, true))

		addon, _, state = open_world(function(state)
			state.xp = 100
		end)
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.level, state.xp = 12, 0
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a two-level jump marks the window incomplete and adds nothing",
			report.hour.total == 0 and report.hour.gap and joined(report):find("Hour  0   XP incomplete", 1, true))

		addon, _, state = open_world(function(state)
			state.xp = 100
		end)
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 40
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a drop in experience marks the window incomplete and adds nothing",
			report.hour.total == 0 and report.hour.gap and joined(report):find("XP incomplete", 1, true))

		addon, _, state = open_world(function(state)
			state.level, state.xp, state.xp_max = 60, 0, 0
		end)
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("an empty bar at the level cap adds nothing and stays complete",
			report.hour.total == 0 and not report.hour.gap and not joined(report):find("XP incomplete", 1, true))

		addon, env, state = open_world(function(state)
			state.xp = 100
		end)
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		local hidden = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, hidden) end
		state.xp = hidden
		local ok = pcall(function() addon.island_experience.on_event("PLAYER_XP_UPDATE") end)
		state.xp = 200
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a secret bar waits, then counts the gain as unsorted",
			ok and report.hour.total == 100 and report.hour.unsorted == 100 and report.hour.split
			and joined(report):find("Unsorted 100   XP incomplete", 1, true))

		addon, _, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		addon.island_experience.on_event("QUEST_TURNED_IN", 10, 1000, 0)
		state.xp = 1000
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a quest amount followed by the same bar move is all quests",
			report.hour.total == 1000 and report.hour.quest == 1000 and report.hour.kill == 0
			and report.hour.other == 0 and not report.hour.split)

		addon, _, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 1000
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		addon.island_experience.on_event("QUEST_TURNED_IN", 10, 1000, 0)
		report = addon.island_experience.report()
		check("a quest amount just after the bar move is all quests",
			report.hour.total == 1000 and report.hour.quest == 1000 and report.hour.other == 0)

		addon, _, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		addon.island_experience.on_event("QUEST_TURNED_IN", 10, 5000, 0)
		state.xp = 1000
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a quest amount larger than the bar does not raise the total",
			report.hour.total == 1000 and report.hour.quest == 1000 and report.hour.split)

		addon, _, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 44 experience.")
		state.xp = 44
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a named kill line labels the bar move as kills",
			report.hour.total == 44 and report.hour.kill == 44 and report.hour.other == 0)
		addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 40 experience. (+10 group bonus)")
		state.xp = 84
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		check("the first number in a group kill line is the kill amount",
			addon.island_experience.report().hour.kill == 84)
		addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "Wolf dies, you gain 44 experience. (22 exp Rested bonus)")
		state.xp = 128
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		check("a rested kill line keeps the gain and not the parenthetical",
			addon.island_experience.report().hour.kill == 128 and addon.island_experience.report().hour.total == 128)

		addon, _, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", "You gain 44 experience.")
		state.xp = 44
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("an unnamed experience line is not a kill",
			report.hour.kill == 0 and report.hour.other == 44 and report.hour.total == 44)

		addon, env, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		hidden = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, hidden) end
		ok = pcall(function() addon.island_experience.on_event("CHAT_MSG_COMBAT_XP_GAIN", hidden) end)
		state.xp = 44
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a secret kill line leaves the bar move unsorted",
			ok and report.hour.total == 44 and report.hour.unsorted == 44 and report.hour.kill == 0 and report.hour.split)

		addon, env, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 100
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.server = 1000800 + 7200
		report = addon.island_experience.report()
		check("a gain from two hours ago stays in the day and leaves the hour",
			report.hour.total == 0 and report.day.total == 100)
		state.server = 1000800 + 26 * 3600
		state.xp = 101
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		report = addon.island_experience.report()
		check("a gain older than 25 hours is dropped on the next commit",
			report.day.total == 1 and env.EverlookSaved.island_experience["Player-1-ABC"].buckets["1000800"] == nil)

		addon, env, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 250
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		-- A reload runs every file again into a new registry. Running only this
		-- one again leaves its extension registered once.
		local function reload_experience(world_env, world)
			local chunk = assert(loadfile(source("island_experience")))
			setfenv(chunk, world_env)
			local extend = world.module.extend
			world.module.extend = function() end
			chunk("Everlook_Island", world)
			world.module.extend = extend
		end
		reload_experience(env, addon)
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		check("loading the saved ledger does not count the baseline again",
			addon.island_experience.report().hour.total == 250)
		local again, again_env, again_state = open_world()
		again.island_experience.on_event("PLAYER_XP_UPDATE")
		again_state.xp = 250
		again.island_experience.on_event("PLAYER_XP_UPDATE")
		reload_experience(again_env, again)
		again_state.xp = 300
		again.island_experience.on_event("PLAYER_XP_UPDATE")
		report = again.island_experience.report()
		check("experience gained across a reload is unsorted",
			report.hour.total == 300 and report.hour.unsorted == 50 and report.hour.split)

		addon, env, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 100
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.guid, state.xp = "Player-2-DEF", 0
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 50
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		check("a second character keeps a separate total",
			addon.island_experience.report().hour.total == 50
			and env.EverlookSaved.island_experience["Player-2-DEF"].buckets["1000800"].total == 50)
		state.guid, state.xp = "Player-1-ABC", 100
		addon.island_experience.on_event("PLAYER_ENTERING_WORLD")
		check("returning to the first character restores that ledger",
			addon.island_experience.report().hour.total == 100
			and env.EverlookSaved.island_experience["Player-1-ABC"].buckets["1000800"].total == 100)

		addon, env, state = open_world(function(state, env)
			local hidden_guid = secret_stat()
			env.issecretvalue = function(value) return rawequal(value, hidden_guid) end
			state.guid = hidden_guid
		end)
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 10
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		check("a secret character id keeps the hour in memory and writes nothing",
			addon.island_experience.report().hour.total == 10 and env.EverlookSaved.island_experience == nil)

		addon, env, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 80
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		addon.module.set("island", "enabled", false)
		check("disabling Island leaves the saved ledger in place",
			addon.island_experience.report() == nil
			and env.EverlookSaved.island_experience["Player-1-ABC"].buckets["1000800"].total == 80)

		addon, _, state = open_world()
		state.xp_max = 2000
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.xp = 1000
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		state.server = 1000800 + 59
		check("the pace line waits until a minute of gains",
			not joined(addon.island_experience.report()):find("to this level", 1, true))
		state.server = 1000800 + 60
		check("one minute of gains at this pace is about a minute",
			joined(addon.island_experience.report()):find("About a minute to this level", 1, true))
		state.server = 1000800 + 3600
		state.xp, state.xp_max = 3600, 6000
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		check("forty minutes of this pace stays in minutes",
			joined(addon.island_experience.report()):find("About 40 minutes to this level", 1, true))
		state.xp_max = 10800
		check("two hours of this pace is about two hours",
			joined(addon.island_experience.report()):find("About 2 hours to this level", 1, true))

		addon, _, state = open_world()
		addon.island_experience.on_event("PLAYER_XP_UPDATE")
		check("no exhaustion reads as not rested",
			joined(addon.island_experience.report()):find("Not rested", 1, true))
		state.exhaustion = 0
		check("zero exhaustion reads as not rested",
			joined(addon.island_experience.report()):find("Not rested", 1, true))
		state.xp_max, state.exhaustion = 10000, 14200
		check("rested leftover names one level and the remainder",
			joined(addon.island_experience.report()):find("Rested 1 level and 4,200", 1, true))
		state.exhaustion = 20000
		check("rested leftover names whole levels",
			joined(addon.island_experience.report()):find("Rested 2 levels", 1, true)
			and not joined(addon.island_experience.report()):find("and", 1, true))

		local ui, ui_env, ui_event, ui_state, _, _, ui_frames = island_world()
		ui_state.guid, ui_state.server = "Player-1-UI", 2000000
		ui_state.level, ui_state.xp, ui_state.xp_max = 12, 450, 1000
		ui_env.GetServerTime = function() return ui_state.server end
		ui_env.UnitGUID = function() return ui_state.guid end
		ui_env.GetXPExhaustion = function() return nil end
		ui_env.GetMaxPlayerLevel = function() return 60 end
		ui.module.set("island", "enabled", true)
		ui_state.xp = 600
		ui_event("PLAYER_XP_UPDATE")
		local view = ui.island.view()
		check("experience detail stays off the island until the option is on",
			view.sections == 2 and view.mode == "closed" and view.level == 12
			and ui.island_experience.report().hour.total == 150)
		ui.module.set("island", "feed_experience", true)
		view = ui.island.view()
		local function hour_label()
			for _, object in ipairs(ui_frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text == "HOUR" and region.shown ~= false then return region end
				end
			end
		end
		local function text_shown(text)
			for _, object in ipairs(ui_frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text == text and region.shown ~= false then return region end
				end
			end
		end
		check("the closed capsule stays a level chip while the hour is recorded, and the experience is a section",
			view.mode == "closed" and view.level == 12 and view.sections == 3 and ui.island_experience.report().hour.total == 150)
		ui_env.everlook_island_key("down")
		local label = hour_label()
		check("the open island shows the table in the notifications pane, with the hour and the total",
			label and label.shown ~= false and label.text == "HOUR" and text_shown("150") ~= nil and text_shown("Total") ~= nil
			and text_shown("NOTIFICATIONS") ~= nil)
		ui.module.set("island", "size", 150)
		check("a larger island keeps the table", ui.island_experience.report().hour.total == 150 and hour_label() ~= nil)
		ui.module.set("island", "size", 100)
		local notices = #ui.island.view().notices
		ui_event("QUEST_TURNED_IN", 9, 100, 0)
		ui_state.xp = 700
		ui_event("PLAYER_XP_UPDATE")
		view = ui.island.view()
		local report = ui.island_experience.report()
		check("a turned-in quest labels the next bar move on the open island",
			report.hour.quest == 100 and report.hour.total == 250 and #view.notices == notices)
		ui.module.set("island", "feed_experience", false)
		check("turning experience detail off removes the section and keeps the hour",
			ui.island.view().sections == 2 and hour_label() == nil and ui.island_experience.report().hour.total == 250)
	end
	experience_ledger()
	local function lifetime_tests()
		local function visible_marks(frames, text)
			local function shown_frame(frame)
				local current = frame
				while type(current) == "table" do
					if current.shown == false then return false end
					current = current.parent
				end
				return true
			end
			local count = 0
			for index = 1, #frames do
				for _, region in ipairs(frames[index].regions) do
					if region.text == text and region.shown ~= false and shown_frame(region.parent) then count = count + 1 end
				end
			end
			return count
		end
		do
			local addon, env, _, state, afters, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Read me", duration = 4 })
			state.time = state.time + 1
			env.everlook_island_key("down")
			state.time = state.time + 0.5
			env.everlook_island_key("up")
			check("closing the island resumes the remaining lifetime", addon.island.view().mode == "closed" and #addon.island.view().notices == 1 and afters[#afters].delay == 3)
			fire_after(afters, 3)
			finish_animations(frames)
			check("the resumed clock removes the card and the row together", #addon.island.view().toasts == 0 and #addon.island.view().notices == 0)
		end
		do
			local addon, env, _, _, afters, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			local api = env.Everlook.island
			local first = api.notify({ source = "Coins", stack = "gain", text = "Money received", money = 100, duration = 4 })
			local restarted = #afters
			local second = api.notify({ source = "Coins", stack = "gain", text = "Money received", money = 250, duration = 4 })
			local view = addon.island.view()
			local counted
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions) do
					if region.text == "Money received ×2" then counted = true end
				end
			end
			check("the same source and stack join one notice", second == first and #view.notices == 1 and view.notices[1].count == 2 and view.notices[1].money == 350 and view.notices[1].text == "Money received" and counted)
			check("a timed stack restarts its full lifetime", #afters == restarted + 1 and afters[#afters].delay == 4)
			fire_after(afters, 4)
			check("the earlier stack timeout cannot remove the joined notice", #addon.island.view().notices == 1 and #addon.island.view().toasts == 1)
			local other = api.notify({ source = "Other", stack = "gain", text = "Other coins", money = 10 })
			check("a different source stays its own notice", other ~= first and #addon.island.view().notices == 2)
			local keyed = api.notify({ source = "Work", key = "job", stack = "gain", text = "Job", money = 20 })
			local updated = api.notify({ source = "Work", key = "job", stack = "gain", text = "Job done", money = 5 })
			local job
			for _, notice in ipairs(addon.island.view().notices) do
				if notice.id == keyed then job = notice end
			end
			check("a matching key updates that notice without adding a count", updated == keyed and job.text == "Job done" and job.money == 5 and job.count == 1)
			local huge = api.notify({ source = "Vault", stack = "gain", text = "Money received", money = 9007199254740991 })
			local rejected, reason = api.notify({ source = "Vault", stack = "gain", text = "Money received", money = 1 })
			local vault
			for _, notice in ipairs(addon.island.view().notices) do
				if notice.id == huge then vault = notice end
			end
			check("stacked money past the display bound is rejected", rejected == nil and reason == "invalid_money" and vault.money == 9007199254740991 and vault.count == 1)
		end
		do
			local addon, env, _, _, afters, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Ordinary news", duration = 4 })
			check("a timed row has no close mark", visible_marks(frames, "×") == 0)
			fire_after(afters, 4)
			finish_animations(frames)
			local handle = api.notify({ source = "Bags", text = "The bags are full", persist = true, severity = "warning", duration = 4,
				actions = { { id = "pin", label = "Pin", type = "callback", on_click = function() end } } })
			check("a persistent notice has no close mark", handle and visible_marks(frames, "×") == 0 and addon.island.view().notices[1].persist == true)
			local dismissed = false
			for index = 1, #frames do
				local handler = frames[index].scripts and frames[index].scripts.OnMouseUp
				if not dismissed and handler and frames[index].shown ~= false and frames[index].mouse then
					handler(frames[index], "RightButton")
					dismissed = #addon.island.view().notices == 0
				end
			end
			check("right-click dismisses a notice", dismissed)
			local staying = api.notify({ source = "Bags", key = "later", text = "Still full", persist = true, duration = 4 })
			while fire_after(afters, 4) do end
			finish_animations(frames)
			check("the read clock removes the card and leaves the row", staying and #addon.island.view().notices == 1 and #addon.island.view().toasts == 0)
			check("dismissing a persistent notice removes its row", api.dismiss(staying) and #addon.island.view().notices == 0)
		end
		do
			local addon, env, _, _, afters, _, frames = island_world()
			addon.module.set("island", "enabled", true)
			local api = env.Everlook.island
			api.notify({ text = "Stay one", persist = true })
			api.notify({ text = "Stay two", persist = true })
			api.notify({ text = "Stay three", persist = true })
			local waiting = api.notify({ text = "Waiting", duration = 4 })
			local view = addon.island.view()
			check("a timed notice can wait behind persistent cards", #view.toasts == 3 and #view.queue == 1 and view.queue[1].id == waiting)
			api.notify({ text = "Broken axle", severity = "error" })
			local exiting = false
			for _, toast in ipairs(addon.island.view().toasts) do
				if toast.phase == "exiting" then exiting = true end
			end
			check("an error leaves a persistent card in place", not exiting and #addon.island.view().toasts == 3)
			while fire_after(afters, 4) do end
			finish_animations(frames)
			view = addon.island.view()
			check("the read clock clears persistent cards and the waiting row", #view.notices == 3 and #view.queue == 0 and #view.toasts == 0)
		end
	end
	lifetime_tests()
	feed_tests()
	later_feed_tests()
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.island.notify({ source = "Test", key = "hovered", text = "Stay", duration = 4,
			actions = { { id = "go", label = "Go", type = "callback", on_click = function() end } } })
		local card
		for _, frame in ipairs(frames) do if frame.bound_entry and frame.scripts.OnMouseUp then card = frame end end
		check("a toast with buttons keeps its left clicks", card and card.pass_through ~= nil and #card.pass_through == 0)
		local quiet
		for _, frame in ipairs(frames) do if frame.action_id == "go" and frame.quiet then quiet = frame end end
		local function fill_red() return quiet.quiet.fill.pieces[5].color[1] end
		check("an action button is Stormwind blue: a thin gold outline over a bright blue fill, with near white words",
			quiet and math.abs(quiet.label.color[1] - 235 / 255) < 0.01 and math.abs(fill_red() - 44 / 255) < 0.01
			and quiet.quiet.edge.pieces[5].color[4] == 0.9 and quiet.quiet.edge.pieces[5].color[1] > quiet.quiet.edge.pieces[5].color[3]
			and quiet.quiet.fill.pieces[5].color[3] > quiet.quiet.fill.pieces[5].color[1] * 2 and quiet.quiet.fill.pieces[5].color[3] > 0.8)
		quiet.scripts.OnEnter(quiet)
		check("it lights under the pointer and its words turn white", quiet.label.color[1] == 1 and math.abs(fill_red() - 52 / 255) < 0.01)
		quiet.scripts.OnMouseDown(quiet)
		check("and darkens while pressed", math.abs(fill_red() - 32 / 255) < 0.01)
		quiet.scripts.OnLeave(quiet)
		check("and rests again when the pointer leaves", math.abs(quiet.label.color[1] - 235 / 255) < 0.01 and math.abs(fill_red() - 44 / 255) < 0.01)
		state.time = state.time + 3
		card.scripts.OnEnter(card)
		for _, after in ipairs(afters) do if not after.done then after.done = true; after.callback() end end
		check("a hovered toast does not close when its clock runs out", #addon.island.view().toasts == 1)
		state.time = state.time + 60
		card.scripts.OnLeave(card)
		local restarted
		for _, after in ipairs(afters) do if not after.done then restarted = after.delay end end
		check("leaving it restarts the full time", restarted == 4)
	end
	do
		local addon, _, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.island.notify({ source = "Test", key = "two", text = "Two choices", duration = 4, interaction = "buttons",
			actions = { { id = "yes", label = "Yes", type = "callback", on_click = function() end },
				{ id = "later", label = "Not now", type = "callback", on_click = function() end } } })
		local yes, later
		for _, frame in ipairs(frames) do
			if frame.action_id == "yes" and frame.quiet then yes = frame end
			if frame.action_id == "later" and frame.quiet then later = frame end
		end
		check("the first of two actions is the blue one to press, and the other is bright silver",
			yes and later and yes.quiet.style == "accent" and later.quiet.style == "silver"
			and math.abs(yes.quiet.fill.pieces[5].color[1] - 44 / 255) < 0.01 and math.abs(later.quiet.fill.pieces[5].color[1] - 196 / 255) < 0.01)
	end
	-- Where the game can draw its gold tooltip border, the first button has it, scaled to fit.
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.NineSliceUtil = {
			GetLayout = function() return {} end,
			ApplyLayoutByName = function(frame)
				frame.TopLeftCorner = { GetHeight = function() return 33 end }
				frame.Center = { Hide = function(self) self.hidden = true end }
			end,
		}
		addon.island.notify({ source = "Test", key = "gold", text = "Two choices", duration = 4, interaction = "buttons",
			actions = { { id = "yes", label = "Yes", type = "callback", on_click = function() end },
				{ id = "later", label = "Not now", type = "callback", on_click = function() end } } })
		local yes, later
		for _, frame in ipairs(frames) do
			if frame.action_id == "yes" and frame.quiet then yes = frame end
			if frame.action_id == "later" and frame.quiet then later = frame end
		end
		local border_of = function(button) return button.quiet.border end
		check("the first button has the game's border over its fill, scaled to fit the button, and its middle left out",
			yes and border_of(yes) and border_of(yes).shown ~= false and border_of(yes).Center.hidden == true
			and math.abs(border_of(yes).scale - 22 / (33 * 2 + 2)) < 1e-9)
		check("the silver one has none, and its own thin line is kept", later and border_of(later).shown == false)
		check("the thin gold line steps aside under the game's border",
			yes.quiet.edge.pieces[5].color[4] == 0 and later.quiet.edge.pieces[5].color[4] == 0.9)
	end
end
