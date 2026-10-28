-- Island: a small pill at the top of the screen that shows your level, your quest and notices.
return function(root, check, lib)
	local source, load_all = lib.source, lib.load_all
	local island_world, fire_after, finish_animations = lib.island_world, lib.fire_after, lib.finish_animations
	local last_toast_text, shown_bar, secret_stat, quest_world = lib.last_toast_text, lib.shown_bar, lib.secret_stat, lib.quest_world
	do
		local addon, env, event, state, _, tickers = quest_world()
		check("quest context starts off", addon.island.view().quests == nil)
		addon.module.set("island", "quest_context", true)
		local view = addon.island.view().quests
		check("quest context follows native super tracking", view.current.id == 22 and view.current.distance == 800)
		check("native objectives retain readable counts", view.current.objectives[1].fulfilled == 1 and view.current.objectives[1].required == 6)
		local function held() return addon.island.view().background end
		check("the quest capsule is a background status of the quest source", held() ~= nil and held().source == "everlook.island_quests")
		addon.module.set("island", "enabled", false)
		check("turning the island off clears it", held() == nil)
		addon.module.set("island", "enabled", true)
		check("and it is back when the island is", held() ~= nil and held().source == "everlook.island_quests" and held().count == 1)
		addon.module.set("island", "quest_plan", true)
		view = addon.island.view().quests
		check("ready quests use distance without encounter difficulty", view.order[1].id == 23 and view.order[1].ready)
		check("level suitability outweighs a nearby dangerous quest", view.order[2].id == 22 and view.order[3].id == 21)
		check("another continent sorts after local quests", view.order[4].id == 24 and view.order[4].distance == nil)
		addon.island.pin_quest(21)
		check("manual pin overrides a recommendation without changing native tracking", addon.island.view().quests.current.id == 21 and state.selected == 22)
		addon.island.pin_quest(nil)
		check("releasing a quest pin restores the suggestion", addon.island.view().quests.current.id == 23)
		state.quests[3].distance = 1200
		event("QUEST_LOG_UPDATE")
		check("a better candidate replaces the recommendation", addon.island.view().quests.suggested == 22)
		state.quests[3].distance = 700
		event("QUEST_LOG_UPDATE")
		check("recommendation holds through a small score change", addon.island.view().quests.suggested == 22)
		state.quests[3].distance = 600
		event("QUEST_LOG_UPDATE")
		check("twenty percent improvement changes recommendation", addon.island.view().quests.suggested == 23)
		local prior = addon.island.view().quests.order[1].distance
		state.quests[3].distance = 550
		state.time = state.time + 1
		tickers[1].callback()
		check("current distance refreshes before the ordered plan", addon.island.view().quests.current.distance == 550 and addon.island.view().quests.order[1].distance == prior)
		state.time = state.time + 2
		tickers[1].callback()
		check("ordered plan refreshes at three seconds", addon.island.view().quests.order[1].distance == 550)
		addon.island.pin_quest(21)
		table.remove(state.quests, 1)
		event("QUEST_LOG_UPDATE")
		check("removing a quest releases its stale pin", addon.island.view().quests.pinned == nil)
		view.current.title = "Mutated copy"
		check("quest snapshots cannot mutate the display model", addon.island.view().quests.current.title ~= "Mutated copy")
	end
	do
		local addon, env, event, state = quest_world()
		state.quests[3].ready, state.quests[3].level = false, 12
		state.quests[3].distance = 800
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "quest_plan", true)
		check("equivalent quest costs have deterministic ID order", addon.island.view().quests.order[1].id == 22 and addon.island.view().quests.order[2].id == 23)
		addon.module.set("island", "quest_level_weight", 0)
		check("zero level weight still penalizes quests far above your level", addon.island.view().quests.order[3].id == 21)
		state.quests[1].level = 13
		event("QUEST_LOG_UPDATE")
		check("a close suitable quest becomes a suggestion", addon.island.view().quests.suggested == 21)
		state.quests[1].level, state.quests[1].distance = 13, 300
		state.quests[2].distance = 450
		event("QUEST_LOG_UPDATE")
		addon.module.set("island", "quest_level_weight", 2)
		check("level weighting can favor a farther matching quest", addon.island.view().quests.order[1].id == 22)
		addon.module.set("island", "quest_distance_weight", 4)
		check("distance weighting can favor a nearer suitable quest", addon.island.view().quests.order[1].id == 21)
	end

	do
		local addon, env, event, state = quest_world()
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "quest_recent", true)
		check("logging in does not imply objective progress", addon.island.view().quests.current.id == 22)
		state.quests[1].objectives[1].numFulfilled = 2
		event("QUEST_WATCH_UPDATE", 21)
		check("watched objective progress gets temporary attention", addon.island.view().quests.current.id == 21)
		state.time = state.time + 16
		event("QUEST_LOG_UPDATE")
		check("progress attention expires back to selected quest", addon.island.view().quests.current.id == 22)
		addon.module.set("island", "quest_nearby", true)
		check("nearby attention considers watched quests", addon.island.view().quests.current.id == 21)
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		env.C_QuestLog.GetDistanceSqToQuest = function() return secret, true end
		state.quests[1].level = secret
		state.quests[1].objectives[1].numFulfilled = secret
		state.quests[1].objectives[1].text = secret
		addon.module.set("island", "quest_plan", true)
		local view = addon.island.view().quests
		check("secret distances and objective counts are omitted", view.order[1].distance == nil and view.order[4].id == 21)
		addon.island.pin_quest(21)
		view = addon.island.view().quests
		check("secret levels and objectives never imply progress", view.current.level == nil and view.current.objectives[1].fulfilled == nil and view.current.objectives[1].text == "Objective unavailable")
		addon.module.set("island", "quest_context", false)
		check("disabling quest context clears its pin and view", addon.island.view().quests == nil)
	end

	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		local function label(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions) do if region.text == text and region.shown ~= false then return region end end
			end
		end
		check("wide quest capsule replaces the level chip", addon.island.view().width > 100 and label("Suitable farther"))
		addon.module.set("island", "quest_title", false)
		check("compact quest capsule keeps the native distance", addon.island.view().width < 130 and label("~800 yd"))
		addon.module.set("island", "quest_plan", true)
		env.everlook_island_key("down")
		check("expanded quest inspection shows objective counts", label("Collect things  1/6"))
		local function containing(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.shown ~= false and type(region.text) == "string" and region.text:find(text, 1, true) then return region end
				end
			end
		end
		check("expanded quest plan is headed Next up and explains its order", label("NEXT UP") and containing("Closest to you and matched to your level"))
		local current = addon.island.view().quests.current
		local lay = dofile(root .. "/tests/lib/layout.lua").new()
		local function pane_title()
			-- The quest's name is on the capsule too, so take the one that is down in the pane.
			local found
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == current.title and region.shown ~= false and lay.rectangle(region).top > 100 then found = region end
				end
			end
			return found
		end
		local title, count, explanation = pane_title(), label("Collect things  1/6"), containing(addon.island.view().quests.reason)
		local title_box, explanation_box, count_box = lay.rectangle(title), lay.rectangle(explanation), lay.rectangle(count)
		local island_top
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then island_top = lay.rectangle(frame) end end
		-- The title row is the first thing in the pane, 8 below its heading, with the arrow's room before the title.
		-- Its detail sits 4 below the row, the pin row 8 below that and the objectives 4 below it each.
		check("the card's lines follow the spacing scale: pane inset, a row, its detail close under it, then the next group",
			title_box.left - island_top.left == 34 and explanation_box.top - title_box.top > 0 and explanation_box.left - island_top.left == 12
			and count_box.left - island_top.left == 12)
		local function button_named(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then
						local button = region.parent and region.parent.parent
						if button and button.scripts and button.scripts.OnClick then
							local visible, walker = true, button
							while walker do
								if walker.shown == false then visible = false end
								walker = walker.parent
							end
							if visible then return button end
						end
					end
				end
			end
		end
		local pin, release_button = button_named("Pin quest"), button_named("Release pin")
		check("the pin action is a button in the card's pin row, and only the one that applies shows", pin ~= nil and release_button == nil)
		pin.scripts.OnClick(pin)
		check("native pin button changes only Island context", addon.island.view().quests.pinned == 23 and state.selected == 22)
		local release = button_named("Release pin")
		check("the card then offers to release the pin", release ~= nil and button_named("Pin quest") == nil and label("Pinned") ~= nil)
		release.scripts.OnClick(release)
		check("release button resumes quest suggestion", addon.island.view().quests.pinned == nil)
		event("QUEST_TURNED_IN", 22, 100, 123)
		check("quest completion feed starts off", #addon.island.view().notices == 0)
		addon.module.set("island", "source_quest_completion", true)
		event("QUEST_TURNED_IN", 23, 100, 123)
		local notice = addon.island.view().notices[1]
		check("native quest turn-in reports readable rewards", notice.kind == "quest" and notice.money == 123 and notice.detail == "Ready to return")
		addon.module.set("island", "quest_plan", false)
		event("QUEST_TURNED_IN", 21, 40, 0)
		notice = addon.island.view().notices[#addon.island.view().notices]
		check("a completed quest keeps its log title when it is not the selected one", notice.detail == "Nearby dangerous" and notice.money == 123 and notice.count == 2)
		addon.module.set("island", "quest_context", false)
		event("QUEST_TURNED_IN", 22, 10, 50)
		notice = addon.island.view().notices[#addon.island.view().notices]
		check("completed quests keep the log title while the capsule is off", addon.island.view().quests == nil and notice.detail == "Suitable farther" and notice.money == 173 and notice.count == 3)
	end

	do
		local addon, env, _, state, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		state.quests[2].objectives = {
			{ text = "Slay the first", numFulfilled = 8, numRequired = 8, finished = true },
			{ text = "Slay the second", numFulfilled = 2, numRequired = 5, finished = false },
		}
		addon.island_quests.refresh(true)
		env.everlook_island_key("down")
		local function shown(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do if region.shown ~= false and type(region.text) == "string" and region.text:find(text, 1, true) then return region end end
			end
		end
		local done, todo = shown("Slay the first"), shown("Slay the second")
		-- A ring on the right of each objective: full and green when it is done, gold and filled to its count while it is not.
		local green, gold = 0, 0
		for _, frame in ipairs(frames) do
			if frame.cooldown and frame.shown == true and frame.width == 14 and frame.swipe_color then
				local fraction = (env.GetTime() - frame.cooldown.start) / frame.cooldown.duration
				if math.abs(frame.swipe_color[1] - 0.5) < 0.02 and math.abs(frame.swipe_color[2] - 0.9) < 0.02 and fraction > 0.99 then green = green + 1 end
				if math.abs(frame.swipe_color[1] - 1) < 0.02 and math.abs(frame.swipe_color[2] - 0.82) < 0.02 and math.abs(fraction - 0.4) < 0.01 then gold = gold + 1 end
			end
		end
		for _, frame in ipairs(frames) do if false then print("RING", frame.width, frame.swipe_color and frame.swipe_color[1], frame.swipe_color and frame.swipe_color[2], (env.GetTime() - frame.cooldown.start) / frame.cooldown.duration) end end
		check("a finished objective takes a full green ring, and one still to do a gold ring filled to its count",
			done and todo and green >= 1 and gold == 1)
		local function pin_visible()
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == "Pin quest" and region.shown ~= false then
						local visible, walker = true, region.parent
						while walker do
							if walker.shown == false then visible = false end
							walker = walker.parent
						end
						if visible then return true end
					end
				end
			end
			return false
		end
		check("the pin action shows while a quest is followed", pin_visible())
		addon.module.set("island", "quest_context", false)
		check("turning quest tracking off takes the pin action away and narrows the island",
			not pin_visible() and addon.island.view().width == 432)
	end
	do
		local addon, env, _, state = quest_world()
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "quest_plan", true)
		env.everlook_island_key("down")
		local view = addon.island.view()
		check("the quest card starts at its top beside an empty notice list", #view.notices == 0 and view.quest_height > 0 and view.quest_offset == 0)
		check("a typical card with its route fits without scrolling", view.quest_height <= view.scroll_height)
		-- On a short screen the panes lose height and the card has to scroll.
		env.UIParent.GetHeight = function() return 330 end
		env.Everlook.island.notify({ text = "A notice" })
		view = addon.island.view()
		check("a tall card scrolls on its own, and the notices stay where they were",
			view.quest_height > view.scroll_height and view.quest_offset == 0 and view.scroll_offset == 0)
		addon.island.scroll_quests(80)
		view = addon.island.view()
		check("scrolling the quests moves only the quests", view.quest_offset == 80 and view.scroll_offset == 0)
		env.Everlook.island.notify({ text = "Another notice" })
		check("a new notice does not drag the card down", addon.island.view().quest_offset == 80)
		addon.island.scroll_quests(100000)
		check("the quest offset stops at the end of the card", addon.island.view().quest_offset == view.quest_height - view.scroll_height)
	end

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
		if os.getenv("ISLAND_LAYOUT_DIR") then
			local layout = dofile(root .. "/tests/lib/layout.lua")
			local top
			for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then top = frame end end
			layout.settle(frames)
			local handle = assert(io.open(os.getenv("ISLAND_LAYOUT_DIR") .. "/experience.json", "w"))
			handle:write(layout.export(frames, top, env.GetTime()))
			handle:close()
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
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		local function ring()
			for _, frame in ipairs(frames) do
				if frame.cooldown and frame.width == 14 and frame.shown == true then return frame end
			end
		end
		local seen = ring()
		check("rings keep addons that count cooldowns from printing a number on them", seen and seen.noCooldownCount == true)
		check("the closed quest capsule has a ring beside its title, filled to the quest's progress",
			seen and math.abs((env.GetTime() - seen.cooldown.start) / seen.cooldown.duration - 1 / 6) < 1e-9 and seen.swipe_color[1] == 1)
		state.selected = 23
		state.watched = { 23 }
		event("SUPER_TRACKING_CHANGED")
		addon.module.set("island", "quest_plan", true)
		event("QUEST_LOG_UPDATE")
		local done = ring()
		check("a quest ready to hand in fills its ring and turns it green",
			done and (env.GetTime() - done.cooldown.start) / done.cooldown.duration > 0.99 and done.swipe_color[1] < 0.6 and done.swipe_color[2] > 0.8)
	end
	do
		local addon = quest_world()
		local island_row = addon.island_row
		local function region()
			local r = { points = {}, shown = false }
			function r:ClearAllPoints() self.points = {} end
			function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
			function r:SetText(text) self.text = text end
			function r:GetStringWidth() return #(self.text or "") * 5 end
			function r:Show() self.shown = true end
			function r:Hide() self.shown = false end
			function r:SetSize() end
			function r:SetTextColor(...) self.color = { ... } end
			function r:SetMaxLines() end
			function r:CreateTexture() return region() end
			function r:SetAtlas() end
			function r:SetTexture() end
			function r:SetVertexColor() end
			function r:SetSnapToPixelGrid() end
			function r:SetTexelSnappingBias() end
			function r:SetRotation(angle) self.rotation = angle end
			return r
		end
		local parent = region()
		local rings = { made = 0 }
		function rings.make() local ring = { track = region(), fill = region() }; rings.ring = ring; return ring end
		function rings.set(ring, fraction, tone) rings.fraction, rings.tone = fraction, tone; ring.track:Show() end
		function rings.hide(ring) ring.track:Hide() end
		function rings.chain(ring, following, gap, point) ring.track.points = { { "RIGHT", following, point or "LEFT", -gap, 0 } } end
		local made = island_row.new(parent, { label = function() return region() end, rings = rings, ring_size = 14 })
		made:set({ icon = "quest", title = "Gathering Idols", ring = { fraction = 0.5, tone = { 1, 1, 1 } },
			labels = { "~32 yd", { text = "20", tone = { 1, 0.9, 0.2 } } }, badge = "73%" }, 0)
		local badge, second, first = made.badge, made.labels[2], made.labels[1]
		check("the badge hangs from the right edge and each label from the part after it",
			badge.points[1][2] == parent and badge.points[1][4] == -12 and second.points[1][2] == badge and first.points[1][2] == second
			and second.points[1][4] == -12)
		check("the ring hangs from the first label and the title is held between the lead and the ring",
			rings.ring.track.points[1][2] == first and made.title.points[1][3] == "LEFT" and made.title.points[1][4] == 34
			and made.title.points[2][2] == rings.ring.track and made.title.points[2][4] == -12)
		check("a label takes its own tone", second.color and second.color[2] == 0.9)
		made:set({ labels = { "a", "b" } }, 0)
		check("a label set without a tone leaves the last tone behind", made.labels[2].color[1] == 174 / 255)
		made:set({ icon = "quest", title = "Gathering Idols", badge = "73%" }, 14)
		check("a part the spec leaves out is hidden and the parts that stay close the gap",
			first.shown == false and second.shown == false and rings.ring.track.shown == false
			and badge.points[1][4] == -26 and made.title.points[2][2] == badge)
		made:aim(1.5)
		check("an aimed arrow turns and shows in place of the icon", made.arrow.rotation == 1.5 and made.arrow.shown and made.icon.shown == false)
		made:aim(nil)
		check("without an angle the arrow hides and the icon returns", made.arrow.shown == false and made.icon.shown == true)
		made:set({ title = "Alone" }, 0)
		check("a row with no lead starts its title at the edge and runs it to the other edge",
			made.title.points[1][4] == 12 and made.title.points[2][2] == parent and made.title.points[2][3] == "RIGHT")
	end
	do
		local function near(actual, expected)
			return type(actual) == "number" and math.abs(actual - expected) < 1e-4
		end
		local addon, env, event, state, _, _, frames = quest_world()
		local bearing = addon.island_quests.bearing
		-- GetWorldPosFromMapPos on Elwynn 37: x grows north, y grows west.
		check("facing north, a point due north is straight ahead", type(bearing) == "function" and near(bearing(-7939.580078125 + 0.5 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.5 * (-1935.4200439453 - 1535.4200439453), -7939.580078125 + 0.25 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.5 * (-1935.4200439453 - 1535.4200439453), 0), 0))
		check("facing north, a point due west points left", near(bearing(0, 0, 0, 10, 0), math.pi / 2))
		check("facing north, a point due east points right", near(bearing(0, 0, 0, -10, 0), -math.pi / 2))
		check("facing the point puts the arrow straight ahead", near(bearing(0, 0, 0, 10, math.pi / 2), 0))
		check("Elwynn east points right", near(bearing(-7939.580078125 + 0.5 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.5 * (-1935.4200439453 - 1535.4200439453), -7939.580078125 + 0.5 * (-10254.200195312 - -7939.580078125), 1535.4200439453 + 0.75 * (-1935.4200439453 - 1535.4200439453), 0), -math.pi / 2))
		check("a point within a yard has no direction", bearing(0, 0, 0.5, 0, 0) == nil)
		local secret = secret_stat()
		env.issecretvalue = function(value) return rawequal(value, secret) end
		check("a secret facing has no direction", bearing(0, 0, 0, 10, secret) == nil)
		state.player_map, state.px, state.py, state.facing = 37, 0.5, 0.5, 0
		state.maps = {
			[37] = { continent = 0, origin_x = 0, origin_y = 0, width = 100, height = 100 },
			[40] = { continent = 0, origin_x = 0, origin_y = 0, width = 100, height = 100 },
			[12] = { continent = 1, origin_x = 0, origin_y = 0, width = 100, height = 100 },
		}
		env.GetPlayerFacing = function() return state.facing end
		env.C_Map.GetBestMapForUnit = function() return state.player_map end
		env.C_Map.GetPlayerMapPosition = function() return { x = state.px, y = state.py } end
		env.C_Map.GetWorldPosFromMapPos = function(map_id, pos)
			local spot = state.maps[map_id]
			if not spot or type(pos) ~= "table" or type(pos.x) ~= "number" or type(pos.y) ~= "number" then return end
			return spot.continent, { x = spot.origin_x - pos.y * spot.height, y = spot.origin_y - pos.x * spot.width }
		end
		local asked = {}
		env.C_QuestLog.GetNextWaypoint = function(id)
			asked[#asked + 1] = id
			for _, quest in ipairs(state.quests) do
				if quest.questID == id and quest.waypoint then return quest.waypoint.map, quest.waypoint.x, quest.waypoint.y end
			end
		end
		env.C_SuperTrack.SetSuperTrackedQuestID = function() error("the arrow must leave tracking alone") end
		for _, quest in ipairs(state.quests) do quest.waypoint = { map = 37, x = 0.5, y = 0.25 } end
		addon.module.set("island", "quest_context", true)
		-- The closed capsule's arrow is in a slot of the face, turned by a frame of the face's. The open island's is in a
		-- row of the quests pane, turned by a frame of the panes'. Each is found when it is on show.
		local function arrows()
			-- Whether a frame is under `target` with nothing hidden between: a slot that is not showing has no arrow on show.
			local function inside(frame, target)
				while frame do
					if frame == target then return true end
					if frame.shown == false then return false end
					frame = frame.parent
				end
			end
			local face, expanded, capsule, driver, closed_arrow, open_arrow
			for _, frame in ipairs(frames) do
				if frame.name == "EverlookIslandFace" then face = frame end
				if frame.name == "EverlookIslandExpanded" then expanded = frame end
			end
			for _, frame in ipairs(frames) do
				if frame.name == nil and frame.scripts and frame.scripts.OnUpdate then
					if frame.parent == face then capsule = frame end
					if frame.parent == expanded then driver = frame end
				end
				for _, region in ipairs(frame.regions or {}) do
					if type(region.path) == "string" and region.path:find("island_arrow", 1, true) and region.shown == true then
						if inside(frame, face) then closed_arrow = closed_arrow or region
						elseif inside(frame, expanded) then open_arrow = open_arrow or region end
					end
				end
			end
			-- The quest's mark sits in the same row as the arrow and shows in its place.
			local icon
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.atlas == "questlog-questtypeicon-quest" and closed_arrow and frame == closed_arrow.parent then icon = region end
				end
			end
			return capsule, driver, closed_arrow, open_arrow, icon
		end
		local capsule, inspection, closed_arrow, open_arrow = arrows()
		check("the closed capsule points toward the selected quest", asked[#asked] == 22 and closed_arrow and closed_arrow.shown and near(closed_arrow.rotation, 0))
		check("turning the character waits a tenth of a second", (function()
			state.facing = math.pi / 2
			capsule.scripts.OnUpdate(capsule, 0.08)
			return near(closed_arrow.rotation, 0)
		end)())
		capsule.scripts.OnUpdate(capsule, 0.04)
		check("turning the character turns the arrow", near(closed_arrow.rotation, -math.pi / 2))
		state.facing = 0
		state.quests[2].waypoint = { map = 40, x = 0.25, y = 0.5 }
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("a waypoint on another map of this continent still aims", near(closed_arrow.rotation, math.pi / 2))
		addon.module.set("island", "quest_plan", true)
		check("the arrow follows the suggestion", asked[#asked] == 23 and state.selected == 22)
		addon.island.pin_quest(21)
		-- A new quest is a new capsule, and may be drawn in the other slot once its fade has played, so the arrow is found again.
		dofile(root .. "/tests/lib/layout.lua").settle(frames)
		capsule, inspection, closed_arrow, open_arrow = arrows()
		check("the arrow follows the pinned quest", asked[#asked] == 21 and state.selected == 22 and closed_arrow.shown)
		state.quests[1].waypoint = { map = 12, x = 0.5, y = 0.25 }
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("another continent hides the arrow", closed_arrow.shown == false)
		state.quests[1].waypoint = nil
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("a quest without a waypoint hides the arrow", closed_arrow.shown == false)
		state.quests[1].waypoint = { map = 37, x = 0.5, y = 0.25 }
		state.facing = nil
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("missing facing hides the arrow", closed_arrow.shown == false)
		state.facing = 0
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("the arrow comes back with the facing", closed_arrow.shown and near(closed_arrow.rotation, 0))
		state.facing = secret
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("a secret facing hides the arrow", closed_arrow.shown == false)
		state.facing = 0
		state.time = state.time + 2
		env.C_QuestLog.GetNextWaypoint = function() end
		state.pins = { [37] = { { questID = 21, x = 0.5, y = 0.25 } } }
		state.parents = {}
		env.C_QuestLog.GetQuestsOnMap = function(map_id) return state.pins[map_id] end
		env.C_Map.GetMapInfo = function(map_id) return { parentMapID = state.parents[map_id] } end
		capsule.scripts.OnUpdate(capsule, 0.1)
		local icon = select(5, arrows())
		check("a map pin aims when the client has no waypoint", closed_arrow.shown and near(closed_arrow.rotation, 0) and icon ~= nil and icon.shown == false and closed_arrow.point[1] == "LEFT")
		state.pins = { [37] = {}, [13] = { { questID = 21, x = 0.25, y = 0.5 } } }
		state.parents = { [37] = 13 }
		state.maps[13] = { continent = 0, origin_x = 0, origin_y = 0, width = 100, height = 100 }
		state.time = state.time + 2
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("a pin on the parent map still aims", near(closed_arrow.rotation, math.pi / 2))
		env.C_Map.GetWorldPosFromMapPos = function() end
		env.C_Map.GetMapWorldSize = function() return 1000, 1000 end
		env.C_QuestLog.GetNextWaypoint = function() return 37, 0.5, 0.25 end
		capsule.scripts.OnUpdate(capsule, 0.1)
		check("the same map aims when world positions are missing", near(closed_arrow.rotation, 0) and closed_arrow.path == "Interface\\AddOns\\Everlook_Island\\assets\\island_arrow.tga")
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
		local addon, env, event, state, afters = island_world()
		state.bags[0], state.bags[1], state.bags[5] = 8, 20, 100
		state.bag_families[1] = 32
		addon.module.set("island", "enabled", true)
		check("general free slots exclude specialty and reagent capacity", addon.island.view().bags == "8 free slots")
		state.bags[0] = 7
		event("BAG_UPDATE_DELAYED")
		check("ordinary bag changes stay quiet", #addon.island.view().notices == 0)
		state.bags[0] = 5
		event("BAG_UPDATE_DELAYED")
		local view = addon.island.view()
		local first = view.notices[1]
		check("low free slots produce one keyed warning", first and first.severity == "warning" and first.key == "free-slots")
		state.bags[0] = 0
		event("BAG_UPDATE_DELAYED")
		view = addon.island.view()
		check("full bags strengthen the same warning identity", #view.notices == 1 and view.notices[1].id == first.id and view.notices[1].severity == "error")
		state.bags[0] = 7
		event("BAG_UPDATE_DELAYED")
		check("bag warning retains its recovery margin", #addon.island.view().notices == 1)
		state.bags[0] = 8
		event("BAG_UPDATE_DELAYED")
		check("bag recovery resolves the condition without another notice", #addon.island.view().notices == 0)
		state.money = 22345
		event("PLAYER_MONEY")
		check("money updates quietly by default", #addon.island.view().notices == 0 and addon.island.view().money == "2g 23s 45c")
	end
	do
		local addon, _, event, state, afters = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		state.money = 12445
		event("PLAYER_MONEY")
		local stale = afters[#afters] and afters[#afters].callback
		state.time = 100.2
		state.money = 12645
		event("PLAYER_MONEY")
		check("routine money waits for a quiet window", #addon.island.view().notices == 0)
		if stale then stale() end
		check("an earlier batch deadline cannot publish a partial delta", #addon.island.view().notices == 0)
		local current = afters[#afters] and afters[#afters].callback
		if current then current() end
		local entry = addon.island.view().notices[1]
		check("routine money publishes one signed rich net amount", entry and entry.money == 300 and entry.text == "Money received")
		local before = #addon.island.view().notices
		state.money = 12646
		event("PLAYER_MONEY")
		if afters[#afters] then afters[#afters].callback() end
		check("tiny routine money deltas stay quiet", #addon.island.view().notices == before)
		state.money = 22646
		event("PLAYER_MONEY")
		local disabled = afters[#afters] and afters[#afters].callback
		addon.module.set("island", "source_money", false)
		if disabled then disabled() end
		check("turning off money delivery cancels pending batches", #addon.island.view().notices == before)
	end
	do
		local addon, _, event, state = island_world()
		addon.module.set("island", "enabled", true)
		event("PLAYER_LEVEL_UP", 13)
		event("PLAYER_LEVEL_UP", 13)
		check("a readable level event outruns a delayed getter exactly once", addon.island.view().level == 13 and #addon.island.view().notices == 1)
		state.level = 13
		event("PLAYER_XP_UPDATE", "player")
		check("the level getter catches up without another notice", addon.island.view().level == 13 and #addon.island.view().notices == 1)
	end
	do
		local addon, env, event, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		state.slots[1] = { 14, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		local handle = addon.island.view().notices[1].id
		check("weakest-item damage crosses a threshold despite healthier gear", addon.island.view().durability == "28%")
		state.slots[1] = { 4, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("severe damage updates one condition", #addon.island.view().notices == 1 and addon.island.view().notices[1].id == handle)
		state.slots[1] = { 0, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("a broken item strengthens the same condition", addon.island.view().notices[1].severity == "error")
		state.slots[1] = { 18, 50 }
		event("UPDATE_INVENTORY_DURABILITY")
		check("durability recovery resolves the retained warning", #addon.island.view().notices == 0)
		state.bags[0], state.bags[1] = 3, 1
		event("BAG_UPDATE_DELAYED")
		addon.module.set("island", "source_bags", false)
		check("disabling a condition source removes its warning immediately", #addon.island.view().notices == 0)
		finish_animations(frames)
		addon.module.set("island", "source_money", true)
		state.money = 12545
		event("BAG_UPDATE_DELAYED")
		event("PLAYER_MONEY")
		local maximum = afters[#afters - 1].callback
		state.time = 101
		state.money = 12745
		event("PLAYER_MONEY")
		maximum()
		check("other readouts preserve the money baseline and maximum-window total", addon.island.view().notices[1].money == 400)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		env.C_Container.GetContainerNumFreeSlots = function(bag) return 20, bag == 0 and 0 or secret end
		addon.module.set("island", "source_bags", true)
		event("BAG_UPDATE_DELAYED")
		check("secret bag classification leaves capacity unavailable without a warning", addon.island.view().bags == nil and #addon.island.view().notices == 1)
	end
	do
		local addon, env, event, state, afters = island_world()
		local requests, cost, needed = {}, 500, true
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function(guild) requests[#requests + 1] = guild end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("auto_repair", "enabled", true)
		event("MERCHANT_SHOW")
		check("requesting repair does not announce success", #requests == 1 and #addon.island.view().notices == 0)
		state.money = state.money - 500
		event("PLAYER_MONEY")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		local entry = addon.island.view().notices[1]
		check("confirmed personal repair reports rich cost and fund source", entry and entry.text == "Equipment repaired" and entry.money == -500 and entry.detail == "Paid from personal funds")
		fire_after(afters, 0.75)
		check("a matching confirmed cost consumes only its pending money summary", #addon.island.view().notices == 1)
		state.money = state.money - 300
		event("PLAYER_MONEY")
		cost, needed = 300, true
		env.CanGuildBankRepair = function() return true end
		env.GetGuildBankWithdrawMoney = function() return -1 end
		env.GetGuildBankMoney = function() return 1000 end
		addon.module.set("auto_repair", "guild_funds", true)
		event("MERCHANT_SHOW")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		local notices = addon.island.view().notices
		entry = notices[#notices]
		check("confirmed guild repair identifies guild payment", requests[2] == true and entry.detail == "Paid from guild funds" and entry.money == -800 and entry.count == 2)
		fire_after(afters, 0.75)
		entry = addon.island.view().notices
		check("a guild repair leaves an equal personal money batch", #entry == 2 and entry[1].detail == "Paid from guild funds" and entry[1].money == -800 and entry[2].text == "Money spent" and entry[2].money == -300)
		local count = #entry
		cost, needed = 100, true
		event("MERCHANT_SHOW")
		event("MERCHANT_CLOSED")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		check("closing the vendor cancels an unconfirmed repair notice", #addon.island.view().notices == count)
	end
	do
		local addon, env, event, state, afters = island_world()
		local cost, needed, requests = 100, true, 0
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function() requests = requests + 1 end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("island", "money_min_silver", 0)
		addon.module.set("auto_repair", "enabled", true)
		event("MERCHANT_SHOW")
		state.money = state.money - 75 -- Includes a separate 25-copper gain.
		event("PLAYER_MONEY")
		event("UPDATE_INVENTORY_DURABILITY")
		check("an unchanged repair cost cannot confirm an attempted repair", #addon.island.view().notices == 0)
		cost, needed = 0, false
		fire_after(afters, 0.1)
		fire_after(afters, 0.75)
		local notices = addon.island.view().notices
		check("a delayed getter confirms after the observed durability event", #notices == 2 and notices[1].text == "Equipment repaired")
		check("mixed money batches preserve unrelated activity", notices[#notices].money == -75)
		cost, needed = 50, true
		event("MERCHANT_SHOW")
		fire_after(afters, 3)
		fire_after(afters, 3)
		fire_after(afters, 3)
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		check("expired repair observation does not announce late success", #addon.island.view().notices == 2)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		cost, needed = secret, true
		local ok = pcall(event, "MERCHANT_SHOW")
		check("secret repair cost prevents spending and formatting", ok and requests == 2)
	end
	do
		local addon, env, event, state, afters, tickers = island_world()
		local items = { { itemID = 1, quality = 0, stackCount = 2 }, { itemID = 2, quality = 0, stackCount = 1 } }
		local reported, used = nil, 0
		env.NUM_BAG_SLOTS = 0
		env.C_Item = { GetItemInfo = function() return "Junk", nil, 0, 1, 0, "Miscellaneous", "Junk", 20, "", 1, 100, 15, 0, 0, 0, nil, false end }
		env.C_Container.GetContainerNumSlots = function() return 2 end
		env.C_Container.GetContainerItemInfo = function(_, slot) return items[slot] end
		env.C_Container.UseContainerItem = function(_, slot)
			used = used + 1
			state.money = state.money + items[slot].stackCount * 100
			items[slot] = nil
		end
		addon.say = function(text) reported = text end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("sell_junk", "enabled", true)
		event("MERCHANT_SHOW")
		local selling = tickers[#tickers]
		selling.callback()
		event("PLAYER_MONEY")
		check("an attempted junk sale has no island result", #addon.island.view().notices == 0)
		selling.callback()
		event("PLAYER_MONEY")
		selling.callback()
		local entry = addon.island.view().notices[1]
		check("confirmed junk proceeds reach the island before totals reset", entry and entry.text == "Junk sold" and entry.money == 300 and entry.severity == "success" and used == 2)
		check("the original junk chat report remains", reported and reported:find("300 copper", 1, true))
		fire_after(afters, 0.75)
		fire_after(afters, 0.75)
		check("a confirmed matching junk batch has one result", #addon.island.view().notices == 1)
		items[1] = { itemID = 1, quality = 0, stackCount = 2 }
		addon.module.set("island", "source_sell", false)
		event("MERCHANT_SHOW")
		selling = tickers[#tickers]
		selling.callback()
		selling.callback()
		check("disabling the sale feed preserves selling and its chat report", used == 3 and #addon.island.view().notices == 1 and reported:find("200 copper", 1, true))
		event("PLAYER_MONEY")
		fire_after(afters, 0.75)
		addon.module.set("island", "source_sell", true)
		local original, errors = env.Everlook.island.notify, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.sell_junk" then error("display failed") end
			return original(payload)
		end
		items[1] = { itemID = 1, quality = 0, stackCount = 1 }
		event("MERCHANT_SHOW")
		selling = tickers[#tickers]
		selling.callback()
		event("PLAYER_MONEY")
		selling.callback()
		fire_after(afters, 0.75)
		local money_notice = addon.island.view().notices[2]
		check("sale display errors preserve chat and the routine-money fallback", #errors == 1 and reported:find("100 copper", 1, true) and money_notice and money_notice.text == "Money received" and money_notice.money == 300 and money_notice.count == 2)
	end
	do
		local addon, env, event, state, afters = island_world()
		local cost, needed, requests, errors = 100, true, 0, {}
		env.CanMerchantRepair = function() return true end
		env.GetRepairAllCost = function() return cost, needed end
		env.RepairAllItems = function() requests = requests + 1 end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_money", true)
		addon.module.set("auto_repair", "enabled", true)
		local original = env.Everlook.island.notify
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.auto_repair" then error("display failed") end
			return original(payload)
		end
		event("MERCHANT_SHOW")
		state.money = state.money - 100
		event("PLAYER_MONEY")
		cost, needed = 0, false
		event("UPDATE_INVENTORY_DURABILITY")
		fire_after(afters, 0.75)
		local fallback = addon.island.view().notices[1]
		check("repair display failure leaves the completed action and money fallback", requests == 1 and #errors == 1 and fallback and fallback.money == -100)
	end
	do
		local addon, env, _, state, _, _, frames, hooks = island_world()
		local flying = false
		env.UnitOnTaxi = function() return flying end
		env.TakeTaxiNode = function() end
		env.NumTaxiNodes = function() return 2 end
		env.TaxiNodeGetType = function(index) return index == 1 and "CURRENT" or "REACHABLE" end
		env.TaxiNodeName = function(index) return index == 1 and "Crossroads" or "Ratchet" end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "source_flight", true)
		addon.module.set("flight_time", "enabled", true)
		local poller, timer
		for _, object in ipairs(frames) do
			if object.name == "EverlookFlightTimePoller" then poller = object end
			if object.name == "EverlookFlightTime" then timer = object end
		end
		check("flight time does not poll while you are on the ground", poller and poller.scripts.OnUpdate == nil)
		hooks.TakeTaxiNode(2)
		check("taking a flight starts one poller", poller.scripts.OnUpdate ~= nil)
		poller.scripts.OnUpdate(poller, 0.25)
		check("a flight request alone has no ongoing status", addon.island.view().status == nil)
		flying, state.time = true, 101
		poller.scripts.OnUpdate(poller, 0.25)
		local view = addon.island.view()
		local handle = view.status and view.status.id
		check("an unknown flight shows elapsed time without invented progress", handle and view.status.text == "Flying to Ratchet" and view.status.progress == nil and #view.toasts == 0)
		state.time = 102
		poller.scripts.OnUpdate(poller, 0.25)
		check("flight updates retain one status identity", addon.island.view().status and addon.island.view().status.id == handle and #addon.island.view().notices == 1)
		check("an unknown flight capsule shows elapsed time", addon.island.view().status.capsule and addon.island.view().status.capsule.text == "0:01" and addon.island.view().status.capsule.trailing == "Ratchet")
		flying, state.time = false, 161
		poller.scripts.OnUpdate(poller, 0.25)
		view = addon.island.view()
		check("arrival completes the existing status exactly once", view.status == nil and #view.toasts == 1 and view.toasts[1].id == handle and view.toasts[1].text == "Arrived at Ratchet")
		hooks.TakeTaxiNode(2)
		flying, state.time = true, 200
		poller.scripts.OnUpdate(poller, 0.25)
		state.time = 230
		poller.scripts.OnUpdate(poller, 0.25)
		check("a learned flight estimate produces measured progress", addon.island.view().status and addon.island.view().status.progress == 0.5)
		check("a learned flight capsule shows remaining time", addon.island.view().status.capsule and addon.island.view().status.capsule.text == "0:30")
		state.time = 230.25
		local updated_at = addon.island.view().status.updated_at
		poller.scripts.OnUpdate(poller, 0.25)
		check("flight status updates are limited to once per second", addon.island.view().status.updated_at == updated_at)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		flying = secret
		poller.scripts.OnUpdate(poller, 0.25)
		check("unreadable taxi state does not invent arrival", addon.island.view().status ~= nil and #addon.island.view().toasts == 1)
		flying, env.issecretvalue = true, nil
		addon.module.set("flight_time", "only_island", true)
		poller.scripts.OnUpdate(poller, 0.25)
		check("Island-only display is an explicit flight preference", not timer.shown)
		local original, errors = env.Everlook.island.notify, {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		env.Everlook.island.notify = function(payload)
			if payload.source == "everlook.flight_time" then error("display failed") end
			return original(payload)
		end
		state.time = 231.5
		poller.scripts.OnUpdate(poller, 0.25)
		check("a failed flight feed cleans up its status and keeps the ordinary timer", #errors == 1 and addon.island.view().status == nil and timer.shown)
		env.Everlook.island.notify = original
		state.time = 233
		poller.scripts.OnUpdate(poller, 0.25)
		addon.module.set("island", "source_flight", false)
		poller.scripts.OnUpdate(poller, 0.25)
		check("disabling the feed removes status and restores the ordinary timer", addon.island.view().status == nil and timer.shown)
		addon.module.set("flight_time", "enabled", false)
		check("disabling flight time clears its own display and poller", not timer.shown and poller.scripts.OnUpdate == nil)
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
		local addon, env = island_world()
		addon.module.set("island", "enabled", true)
		local payload = { text = "Equipment repaired", detail = "Personal funds", money = -21500,
			severity = "success", icon = "repair", progress = 0.5, presentation = "inbox" }
		local handle = env.Everlook.island.notify(payload)
		payload.detail, payload.money = "Changed by caller", 0
		local view = addon.island.view()
		local entry = view.notices[1]
		check("rich notifications copy accepted fields without showing an inbox-only card", handle and entry.detail == "Personal funds"
			and entry.money == -21500 and entry.severity == "success" and entry.icon == "repair" and entry.progress == 0.5
			and entry.presentation == "inbox" and #view.toasts == 0)
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		local cases = {
			{ "severity", "urgent" }, { "severity", secret }, { "severity", false },
			{ "detail", string.rep("x", 513) }, { "detail", secret }, { "detail", {} },
			{ "icon", {} }, { "icon", secret },
			{ "money", 1.5 }, { "money", math.huge }, { "money", 0 / 0 }, { "money", secret }, { "money", 9007199254740992 },
			{ "progress", -0.1 }, { "progress", 1.1 }, { "progress", math.huge }, { "progress", secret },
			{ "presentation", "modal" }, { "presentation", secret }, { "presentation", false },
		}
		for index, case in ipairs(cases) do
			local input = { text = "Safe" }
			input[case[1]] = case[2]
			local ok, accepted, reason = pcall(env.Everlook.island.notify, input)
			check("invalid rich field " .. index .. " is rejected safely", ok and accepted == nil and reason == "invalid_" .. case[1])
		end
		local fallback = env.Everlook.island.notify({ text = "Unknown icon", icon = "someone-elses-icon" })
		entry = addon.island.view().notices[2]
		check("unknown icon names fall back with legacy defaults", fallback and entry.icon == "generic" and entry.severity == "info" and entry.presentation == "toast")
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "Routine one" })
		api.notify({ text = "Routine two" })
		api.notify({ text = "Routine three" })
		for index = 1, 5 do api.notify({ text = "Warning " .. index, severity = "warning" }) end
		api.notify({ text = "Late routine" })
		local view = addon.island.view()
		check("a routine burst cannot evict queued warnings", #view.queue == 5 and view.queue[1].text == "Warning 1" and view.queue[5].text == "Warning 5")
		api.notify({ source = "Important", key = "error", text = "Equipment broken", severity = "error" })
		view = addon.island.view()
		check("an error releases the oldest routine card through its exit", view.toasts[1].id == first and view.toasts[1].phase == "exiting" and #view.toasts == 3)
		api.notify({ source = "Important", key = "error", text = "Equipment still broken", severity = "error" })
		check("a keyed error update cannot repeatedly preempt active cards", addon.island.view().toasts[2].phase ~= "exiting")
		finish_animations(frames)
		view = addon.island.view()
		check("errors promote ahead of warnings without erasing warning history", view.toasts[3].text == "Equipment still broken" and #view.queue == 4)
		api.dismiss(view.toasts[2].id)
		finish_animations(frames)
		check("warning promotion preserves FIFO within its severity", last_toast_text(addon) == "Warning 2")
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local missing, reason = api.notify({ text = "Activity", presentation = "status" })
		check("status requires an explicit source and key", missing == nil and reason == "invalid_status_source")
		missing, reason = api.notify({ source = "Flight", text = "Activity", presentation = "status" })
		check("status requires a stable key", missing == nil and reason == "invalid_status_key")
		local first = api.notify({ source = "Flight", key = "trip", text = "Flying to Ratchet", presentation = "status", progress = 0.1 })
		local old_deadline = afters[#afters].callback
		local second = api.notify({ source = "Quest", key = "active", text = "Smart Drinks", presentation = "status" })
		local view = addon.island.view()
		check("the newest status owns one row while earlier activity stays in history", view.status and view.status.id == second and #view.notices == 2 and #view.toasts == 0)
		local updated = api.notify({ source = "Flight", key = "trip", text = "Flying to Ratchet", presentation = "status", progress = 0.8 })
		old_deadline()
		view = addon.island.view()
		check("progress refreshes liveness without taking a newer status's row", updated == first and view.status.id == second and #view.notices == 2 and view.unread_count == 2)
		api.dismiss(second)
		check("dismissing the owner restores the earlier live activity", addon.island.view().status.id == first)
		local current_deadline = afters[#afters].callback
		api.notify({ source = "Flight", key = "trip", text = "Arrived at Ratchet", severity = "success", presentation = "toast" })
		current_deadline()
		view = addon.island.view()
		check("status completion keeps its handle and becomes one toast", view.status == nil and #view.toasts == 1 and view.toasts[1].id == first and #view.notices == 1)
		api.notify({ source = "Quest", key = "forgotten", text = "No more updates", presentation = "status" })
		afters[#afters].callback()
		check("abandoned activity falls back to retained history", addon.island.view().status == nil and #addon.island.view().notices == 2)
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
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local function finish_morph()
			local island, resting
			for _, object in ipairs(frames) do
				if object.name == "EverlookIsland" then island = object end
				if object.name == "EverlookIslandResting" then resting = object end
			end
			if island and island.scripts.OnUpdate and resting and resting.animation_groups and resting.animation_groups[1] then
				resting.animation_groups[1].animations[1].progress = 1
				island.scripts.OnUpdate()
			end
		end
		local function shown_text(needle)
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.text and region.text:find(needle, 1, true) then return region.text end
				end
			end
		end
		local payload = { source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status",
			capsule = { icon = "flight", text = "1:10", trailing = "Ratchet" } }
		local handle = api.notify(payload)
		payload.capsule.text = "9:99"
		local view = addon.island.view()
		check("a copied capsule survives mutation of the caller's table", handle and view.status.capsule.text == "1:10" and view.status.capsule.trailing == "Ratchet")
		check("a capsule morph starts from the resting width", view.shell.playing and view.shell.from == 64 and view.shell.to == view.width and view.width > 64)
		finish_morph()
		local settled = addon.island.view().shell.width
		api.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status", capsule = { icon = "clock", text = "1:10", trailing = "Ratchet" } })
		view = addon.island.view()
		check("an icon change starts from the current width", view.shell.playing and view.shell.from == settled)
		finish_morph()
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		for index = #afters, 1, -1 do
			if afters[index].delay == 0.75 then afters[index].callback() end
		end
		local pill = addon.island.view().shell.width
		api.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status", capsule = { icon = "clock", text = "1:09", trailing = "Ratchet" } })
		view = addon.island.view()
		check("a clock update keeps one read notice and the same pill width", view.unread_count == 0 and #view.notices == 1 and view.shell.width == pill and view.status.capsule.text == "1:09")
		local rejected, reason = api.notify({ source = "A", key = "toast", text = "Hello", capsule = { text = "1:10" } })
		check("a capsule on a toast is rejected", rejected == nil and reason == "invalid_capsule")
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		rejected, reason = api.notify({ source = "A", key = "secret", text = "Flying", presentation = "status", capsule = { text = secret } })
		check("a secret capsule is rejected", rejected == nil and reason == "invalid_capsule" and addon.island.view().status.capsule.text == "1:09")
		env.issecretvalue = nil
		rejected, reason = api.notify({ source = "A", key = "mark", text = "Flying", presentation = "status", capsule = { text = "1:10|T" } })
		check("markup in capsule text is rejected", rejected == nil and reason == "invalid_capsule")
		local runs = {}
		for index = 1, 7 do runs[index] = { text = "Run" } end
		rejected, reason = api.notify({ source = "A", key = "runs", text = "Too many", runs = runs })
		check("a seventh run is rejected", rejected == nil and reason == "invalid_runs")
		rejected, reason = api.notify({ source = "A", key = "atlas", text = "Bad atlas", runs = { { atlas = "Interface/Icons/Foo" } } })
		check("a path-like atlas is rejected", rejected == nil and reason == "invalid_atlas")
		env.GetMoneyString = function(amount) return "<coin:" .. amount .. ">" end
		handle = api.notify({ source = "A", key = "rich", text = "Paid", runs = {
			{ text = "Paid", tone = "primary" }, { money = -21500 }, { atlas = "Taxi_Frame_Gray" },
		} })
		local compiled = shown_text("|A:Taxi_Frame_Gray:16:16|a")
		check("compiled runs contain the coin color and the atlas escape", handle and compiled and compiled:find("|cffffd166", 1, true) and compiled:find("|A:Taxi_Frame_Gray:16:16|a", 1, true))
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "reduced_motion", true)
		env.Everlook.island.notify({ source = "A", key = "trip", text = "Flying to Ratchet", presentation = "status",
			capsule = { icon = "flight", text = "1:10", trailing = "Ratchet" } })
		local view = addon.island.view()
		check("reduced motion settles on the target width in one paint", view.shell.width == view.width and view.width > 64 and view.shell.playing)
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
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local handle = env.Everlook.island.notify({ text = "Keep this notice", duration = 4 })
		state.time = 100.5
		env.everlook_island_key("down")
		state.time = 100.6
		env.everlook_island_key("up")
		env.everlook_island_key("down")
		env.everlook_island_key("up")
		local view = addon.island.view()
		check("a short peek retains an unread notice", #view.notices == 1 and view.notices[1].id == handle and view.unread_count == 1)
		env.everlook_island_key("down")
		state.time = 110
		fire_after(afters, 4)
		finish_animations(frames)
		check("inspection pauses visible toast expiry", #addon.island.view().toasts == 1)
		afters[#afters].callback()
		check("visible rows become read after the dwell", addon.island.view().unread_count == 0)
		env.everlook_island_key("up")
		check("closing inspection retains its history", #addon.island.view().notices == 1)
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		env.UIParent.GetWidth = function() return 320 end
		env.UIParent.GetHeight = function() return 400 end
		addon.module.set("island", "enabled", true)
		for index = 1, 10 do env.Everlook.island.notify({ text = "History row " .. index }) end
		env.everlook_island_key("down")
		local controls = {}
		for _, button in ipairs(frames) do if button.name then controls[button.name] = button end end
		local island_scroll_to = addon.island.scroll_to
		local view = addon.island.view()
		check("the inbox exposes overflow inside a bounded viewport", view.scroll_height <= 240 and view.content_height > view.scroll_height and view.height <= 400)
		local function shown_fades()
			local fades = {}
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if region.gradient and region.shown ~= false then fades[#fades + 1] = region end
				end
			end
			return fades
		end
		check("each fade has a white base for the gradient to tint", #shown_fades() == 1 and shown_fades()[1].color ~= nil and shown_fades()[1].color[4] == 1)
		check("a list with more below fades out at its bottom edge", view.more_below and not view.more_above and #shown_fades() == 1
			and shown_fades()[1].gradient.low.a > 0.9 and shown_fades()[1].gradient.high.a == 0)
		island_scroll_to(view.scroll_height)
		check("a list scrolled into the middle fades at both edges", addon.island.view().more_below and addon.island.view().more_above and #shown_fades() == 2)
		island_scroll_to(0)
		view = addon.island.view()
		local function button_text()
			for _, region in ipairs(controls.EverlookIslandNewNotices.regions or {}) do
				if type(region.text) == "string" then return region.text end
			end
			for _, object in ipairs(frames) do
				for _, region in ipairs(object.regions or {}) do
					if type(region.text) == "string" and region.text:find(" new notice", 1, true) then return region.text end
				end
			end
		end
		check("the footer counts the unread rows below the visible ones", view.unread_below > 0 and view.unread_below < 10
			and button_text() == view.unread_below .. " new notices" and controls.EverlookIslandNewNotices.shown ~= false)
		local first_unread_below = view.unread_below
		controls.EverlookIslandNewNotices.scripts.OnClick()
		view = addon.island.view()
		check("the button brings the first of them to the top, not just the bottom", view.scroll_offset > 0 and view.scroll_offset < view.content_height - view.scroll_height + 1
			and view.unread_below < first_unread_below)
		check("new notices can be reached without growing the panel", view.scroll_offset > 0)
		for _ = 1, 10 do
			if addon.island.view().unread_below == 0 then break end
			controls.EverlookIslandNewNotices.scripts.OnClick()
		end
		island_scroll_to(addon.island.view().content_height)
		check("a list scrolled to its end fades only at its top", addon.island.view().more_above and not addon.island.view().more_below and #shown_fades() == 1
			and shown_fades()[1].gradient.high.a > 0.9 and shown_fades()[1].gradient.low.a == 0)
		check("with nothing unread below, the button goes away", controls.EverlookIslandNewNotices.shown == false)
		-- Room for one more, so the list grows and the new row starts below the old end.
		addon.module.set("island", "inbox_size", 30)
		local before_arrival = addon.island.view().content_height
		env.Everlook.island.notify({ text = "Arrives while you are at the end" })
		view = addon.island.view()
		check("a notice that arrives under your eyes is not counted as below them", view.content_height > before_arrival and view.unread_below == 0 and controls.EverlookIslandNewNotices.shown == false
			and view.scroll_offset == view.content_height - view.scroll_height)
		addon.module.set("island", "inbox_size", 10)
		controls.EverlookIslandClearHistory.scripts.OnClick()
		check("clear history acknowledges the inbox with Undo", #addon.island.view().notices == 0 and addon.island.view().can_undo)
		env.Everlook.island.notify({ source = "New arrival", text = "Arrived after clear" })
		controls.EverlookIslandUndo.scripts.OnClick()
		view = addon.island.view()
		check("Undo merges new arrivals without replaying toasts", #view.notices == 10 and view.notices[10].text == "Arrived after clear" and #view.toasts == 0 and not view.can_undo)
		controls.EverlookIslandClearHistory.scripts.OnClick()
		fire_after(afters, 5)
		-- The first clear's timeout is stale; the second clear owns the window.
		fire_after(afters, 5)
		check("Undo expires without restoring history", not addon.island.view().can_undo and #addon.island.view().notices == 0)
		state.time = 101
		env.everlook_island_key("up")
	end
	do
		local addon, env, _, state, afters = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "Read without a deadline", duration = 4 })
		state.time = 100.5
		env.everlook_island_key("down")
		state.time = 200
		fire_after(afters, 4)
		env.everlook_island_key("up")
		check("resuming preserves the remaining visible lifetime", afters[#afters].delay == 3.5 and #addon.island.view().toasts == 1)
		fire_after(afters, 3.5)
		check("the resumed timer expires its own toast", addon.island.view().toasts[1].phase == "exiting")
	end
	do
		local addon, env, _, _, afters = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ source = "Work", key = "one", text = "Before clear" })
		env.everlook_island_key("down")
		local stale_read = afters[#afters].callback
		addon.island.clear_history()
		addon.island.undo_clear()
		stale_read()
		check("Undo requires a fresh reading dwell", addon.island.view().unread_count == 1)
		afters[#afters].callback()
		check("a restored row becomes read after its new dwell", addon.island.view().unread_count == 0)
		env.Everlook.island.notify({ source = "Work", key = "one", text = "Changed after reading" })
		check("changed content rearms unread without duplicating history", addon.island.view().unread_count == 1 and #addon.island.view().notices == 1)
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
		env.GetMoney = nil
		env.GetInventoryItemDurability = nil
		env.C_Container = nil
		env.GetGameTime = nil
		addon.module.set("island", "enabled", true)
		local view = addon.island.view()
		check("a missing readout API leaves that field blank and keeps experience",
			view.level == 12 and view.xp == 450 and view.money == nil and view.durability == nil and view.bags == nil and view.clock == nil)
		env.issecretvalue = function(value) return value == 450 or value == 1000 end
		state.xp, state.xp_max = 450, 1000
		event("PLAYER_XP_UPDATE", "player")
		check("secret experience still updates the bar values", addon.island.view().xp == 450 and addon.island.view().xp_max == 1000)
		env.issecretvalue = function(value) return value == 20 or value == 50 end
		state.slots[1], state.slots[5] = { 20, 50 }, nil
		event("UPDATE_INVENTORY_DURABILITY")
		check("secret durability is not turned into a percent", addon.island.view().durability == nil or addon.island.view().durability == "")
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
		local addon, env, event, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local secret = secret_stat()
		env.issecretvalue = function(value) return value == secret end
		local cases = {
			{ secret, "invalid_notification" },
			{ "message", "invalid_notification" },
			{ { text = "   " }, "invalid_text" },
			{ { text = string.rep("x", 513) }, "invalid_text" },
			{ { text = secret }, "invalid_text" },
			{ { text = "Safe", source = secret }, "invalid_source" },
			{ { text = "Safe", key = secret }, "invalid_key" },
			{ { text = "Safe", kind = secret }, "invalid_kind" },
			{ { text = "Safe", duration = secret }, "invalid_duration" },
			{ { text = "Safe", duration = 0 / 0 }, "invalid_duration" },
			{ { text = "Safe", duration = math.huge }, "invalid_duration" },
			{ { text = "Safe", duration = 0 }, "invalid_duration" },
			{ { text = "Safe", duration = 31 }, "invalid_duration" },
			{ { text = "Safe", persist = secret }, "invalid_persist" },
			{ { text = "Safe", persist = "yes" }, "invalid_persist" },
			{ { text = "Safe", stack = secret }, "invalid_stack" },
			{ { text = "Safe", stack = "   " }, "invalid_stack" },
			{ { text = "Safe", stack = string.rep("s", 65) }, "invalid_stack" },
			{ setmetatable({}, { __index = function() error("foreign code") end }), "invalid_notification" },
		}
		for index, case in ipairs(cases) do
			local ok, handle, reason = pcall(api.notify, case[1])
			check("invalid notification " .. index .. " is rejected without inspecting secret values", ok and handle == nil and reason == case[2])
		end
		check("invalid input adds no notifications", #addon.island.view().notices == 0)
		check("secret handles cannot dismiss notifications or event subscriptions", not api.dismiss(secret) and not api.unregister_event(secret))
		local calls, removed = 0
		api.register_event("QUEST_TURNED_IN", function() api.unregister_event(removed) end)
		removed = api.register_event("QUEST_TURNED_IN", function() calls = calls + 1 end)
		event("QUEST_TURNED_IN")
		check("an adapter removed during dispatch is skipped", calls == 0)
		local handle, reason = api.register_event(secret, function() end)
		check("secret event names are rejected", handle == nil and reason == "invalid_event")
		handle, reason = api.register_event("QUEST_TURNED_IN", "callback")
		check("invalid event callbacks are rejected", handle == nil and reason == "invalid_callback")
		for _, frame in ipairs(frames) do
			if frame.events.QUEST_TURNED_IN then frame.RegisterEvent = function() return false end end
		end
		handle, reason = api.register_event("NOT_A_WOW_EVENT", function() end)
		check("a refused native event registration is not retained", handle == nil and reason == "invalid_event")
		local errors = {}
		env.geterrorhandler = function() return function(message) errors[#errors + 1] = message end end
		-- Use a fresh fixture because the native event stub above intentionally rejects registration.
		local other, other_env, other_event = island_world()
		other.module.set("island", "enabled", true)
		other_env.geterrorhandler = env.geterrorhandler
		other_env.Everlook.island.register_event("QUEST_TURNED_IN", function() return { text = "" } end)
		other_env.Everlook.island.register_event("QUEST_TURNED_IN", function() return nil end)
		other_event("QUEST_TURNED_IN")
		check("invalid adapter output is observable and nil means no notice", #errors == 1 and errors[1]:find("invalid_text", 1, true) and #other.island.view().notices == 0)
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
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "First notice", duration = 2 })
		local second = api.notify({ text = "Second notice", duration = 6 })
		local third = api.notify({ text = "Third notice", duration = 8 })
		local view = addon.island.view()
		check("three notices emerge together without resizing the island", #view.toasts == 3 and view.width == 64 and view.mode == "closed")
		check("concurrent notices keep their own text and handles", view.toasts[1].id == first and view.toasts[2].id == second and view.toasts[3].id == third and view.toasts[2].text == "Second notice")
		finish_animations(frames)
		view = addon.island.view()
		check("toast entrances settle into separate rows", view.toasts[1].alpha == 1 and view.toasts[1].y > view.toasts[2].y and view.toasts[2].y > view.toasts[3].y)
		fire_after(afters, 2)
		check("only the expired toast begins leaving", addon.island.view().toasts[1].phase == "exiting" and addon.island.view().toasts[2].phase == "visible")
		finish_animations(frames)
		view = addon.island.view()
		check("an expired toast leaves the other notices visible", #view.toasts == 2 and view.toasts[1].id == second and view.toasts[2].id == third)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		for index = 1, 4 do env.Everlook.island.notify({ text = "Burst " .. index, duration = index + 1 }) end
		local view = addon.island.view()
		check("a fourth toast waits for a visible slot", #view.toasts == 3 and #view.queue == 1 and view.queue[1].text == "Burst 4")
		check("queued notices do not start their reading timer", #afters == 3)
		finish_animations(frames)
		fire_after(afters, 2)
		finish_animations(frames)
		view = addon.island.view()
		check("a queued toast enters when an earlier toast finishes leaving", #view.toasts == 3 and #view.queue == 0 and view.toasts[3].text == "Burst 4" and afters[#afters].delay == 5)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = "First use", duration = 2 })
		finish_animations(frames)
		fire_after(afters, 2)
		finish_animations(frames)
		local frame_count = #frames
		env.Everlook.island.notify({ text = "Reuse the first slot" })
		finish_animations(frames)
		local view = addon.island.view()
		check("a reused toast frame becomes visible at the same position", #view.toasts == 1 and view.toasts[1].alpha == 1 and view.toasts[1].phase == "visible" and #frames == frame_count)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "reduced_motion", true)
		local handle = env.Everlook.island.notify({ text = "A quieter notice" })
		local view = addon.island.view()
		check("reduced motion fades a toast at its final position", view.toasts[1].y == -8 and view.toasts[1].alpha == 0)
		finish_animations(frames)
		addon.module.set("island", "reduced_motion", false)
		finish_animations(frames)
		env.Everlook.island.dismiss(handle)
		addon.module.set("island", "reduced_motion", true)
		view = addon.island.view()
		check("enabling reduced motion also settles a pending exit", view.toasts[1].y == 0)
		finish_animations(frames)
		check("a reduced-motion exit still cleans up the toast", #addon.island.view().toasts == 0)
	end

	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local active = api.notify({ source = "Producer", key = "work", text = "Working", duration = 2 })
		local old_timeout = afters[#afters].callback
		local handles = {}
		for index = 2, 14 do handles[index] = api.notify({ text = "Burst " .. index }) end
		local view = addon.island.view()
		check("burst limits keep three active and preserve five waiting peers", #view.toasts == 3 and #view.queue == 5 and view.queue[1].text == "Burst 4" and view.queue[5].text == "Burst 8")
		local updated = api.notify({ source = "Producer", key = "work", text = "Done", duration = 6 })
		check("a keyed toast stays stable even after its history row is evicted", updated == active and addon.island.view().toasts[1].text == "Done")
		old_timeout()
		check("the replaced timer cannot close an updated toast", addon.island.view().toasts[1].phase ~= "exiting")
		api.dismiss(handles[4])
		local queued = api.notify({ source = "Producer", key = "pending", text = "Queued" })
		local timer_count = #afters
		updated = api.notify({ source = "Producer", key = "pending", text = "Queued update", duration = 8 })
		view = addon.island.view()
		check("queued updates replace one row without consuming a slot or timer", queued == updated and #view.queue == 5 and view.queue[5].text == "Queued update" and #afters == timer_count)
		check("a queued notification can be dismissed before it appears", api.dismiss(queued) and #addon.island.view().queue == 4)
		finish_animations(frames)
		api.dismiss(active)
		check("dismissing a visible toast begins an individual exit", addon.island.view().toasts[1].phase == "exiting" and #addon.island.view().toasts == 3)
		finish_animations(frames)
		check("a dismissal makes room for the next queued notice", #addon.island.view().toasts == 3 and #addon.island.view().queue == 3)
	end
	do
		local addon, env, _, _, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local first = api.notify({ text = "A" })
		for index = 1, 3 do api.notify({ text = "More " .. index }) end
		local stale_timeout = afters[1].callback
		local stale_finished
		for _, card in ipairs(frames) do
			for _, group in ipairs(card.animation_groups or {}) do
				stale_finished = stale_finished or group.scripts.OnFinished
			end
		end
		addon.module.set("island", "enabled", false)
		check("disabling removes the active stack and waiting notices immediately", #addon.island.view().toasts == 0 and #addon.island.view().queue == 0)
		addon.module.set("island", "enabled", true)
		api.notify({ text = "Fresh" })
		stale_timeout()
		stale_finished()
		check("old timer and animation completions cannot affect reused frames", #addon.island.view().toasts == 1 and addon.island.view().toasts[1].text == "Fresh" and not api.dismiss(first))
		addon.module.set("island", "toasts", false)
		api.notify({ text = "History only" })
		check("toast controls preserve notifications in the expanded history", #addon.island.view().toasts == 0 and #addon.island.view().queue == 0 and addon.island.view().notices[#addon.island.view().notices].text == "History only")
	end
	do
		local addon, env, _, state, afters, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		for index = 1, 4 do env.Everlook.island.notify({ text = "Peek " .. index, duration = index + 1 }) end
		finish_animations(frames)
		env.everlook_island_key("down")
		check("opening the island hides the stack immediately", addon.island.view().mode == "open" and not addon.island.view().toasts[1].shown)
		fire_after(afters, 2)
		check("the queue and active lifetimes pause during inspection", #addon.island.view().toasts == 3 and #addon.island.view().queue == 1)
		state.time = state.time + 0.3
		env.everlook_island_key("up")
		check("closing a peek resumes the stack without consuming its queue", addon.island.view().mode == "closed" and #addon.island.view().toasts == 3 and #addon.island.view().queue == 1 and addon.island.view().toasts[1].shown)
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		env.UIParent.GetWidth = function() return 240 end
		addon.module.set("island", "enabled", true)
		env.Everlook.island.notify({ text = string.rep("Long notice ", 30) })
		local view = addon.island.view()
		check("long notices wrap inside the screen width", view.toasts[1].width == 208 and view.toasts[1].height > 34)
		for _, card in ipairs(frames) do
			if card.animation_groups then check("toast surfaces let clicks through to the game", card.mouse == false) end
		end
	end
	do
		local addon, env, _, _, _, _, frames = island_world()
		addon.module.set("island", "enabled", true)
		local api = env.Everlook.island
		local handle = api.notify({ source = "A", key = "a", text = "In flight" })
		for _, card in ipairs(frames) do
			for _, group in ipairs(card.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do animation.progress = 0.5 end
			end
		end
		local before = addon.island.view().toasts[1]
		api.notify({ source = "A", key = "a", text = "Updated in flight" })
		local after = addon.island.view().toasts[1]
		check("mid-animation updates keep the current position and opacity", before.y == after.y and before.alpha == after.alpha and after.id == handle)
		api.dismiss(handle)
		after = addon.island.view().toasts[1]
		check("an interrupted entrance starts its exit from the visible position", before.y == after.y and before.alpha == after.alpha and after.phase == "exiting")
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
		local closed_root
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then closed_root = frame end end
		if os.getenv("ISLAND_LAYOUT_DIR") then
			local handle = assert(io.open(os.getenv("ISLAND_LAYOUT_DIR") .. "/closed.json", "w"))
			handle:write(layout.export(frames, closed_root, env.GetTime()))
			handle:close()
		end
		local root_frame
		for _, frame in ipairs(frames) do if frame.name == "EverlookIsland" then root_frame = frame end end
		root_frame.scripts.OnClick(root_frame, "LeftButton")
		layout.settle(frames)
		-- Run with ISLAND_LAYOUT=1 to print every region's rectangle, relative to the island's corner.
		if os.getenv("ISLAND_LAYOUT") then print(layout.describe(frames, root_frame)) end
		-- ISLAND_LAYOUT_DIR=<dir> also writes open.json for scripts/island_layout_html.py.
		local dump_dir = os.getenv("ISLAND_LAYOUT_DIR")
		if dump_dir then
			local handle = assert(io.open(dump_dir .. "/open.json", "w"))
			handle:write(layout.export(frames, root_frame, env.GetTime()))
			handle:close()
		end
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
end
