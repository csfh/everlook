-- Island quests: which quest the island follows and suggests, the way to it, and how a quest shows in the pill and the open island.
return function(root, check, lib)
	local read_source, island_world, quest_world, secret_stat, notice_key = lib.read_source, lib.island_world, lib.quest_world, lib.secret_stat, lib.notice_key
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
	check("quest direction reads the waypoint and leaves tracking alone",
		read_source("island_quests.lua"):find("GetNextWaypoint", 1, true) ~= nil
		and not read_source("island_quests.lua"):find("SetSuperTrackedQuestID", 1, true)
		and not read_source("island_quests.lua"):find("C_Navigation", 1, true))
	do
		local addon, env, event, state, afters = island_world()
		local scans = 0
		env.C_QuestLog = {
			GetNumQuestLogEntries = function() scans = scans + 1; return 0 end,
			GetNumQuestWatches = function() return 0 end,
			GetInfo = function() end,
		}
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "quest_context", true)
		state.time = state.time + 10
		local baseline = scans
		for _ = 1, 6 do event("QUEST_LOG_UPDATE") end
		check("a quest event burst scans the log once at once", scans - baseline == 1)
		for _, after in ipairs(afters) do after.callback() end
		check("the rest of the burst scans once more when the window ends", scans - baseline == 2)
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		local objectives = {}
		for index = 1, 6 do objectives[index] = { text = "Objective " .. index, numFulfilled = 0, numRequired = 3, finished = false } end
		state.quests[2].objectives = objectives
		addon.module.set("island", "quest_context", true)
		env.everlook_island_key("down")
		local texts = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if type(region.text) == "string" and region.shown ~= false then texts[#texts + 1] = region.text end
			end
		end
		local joined = "\n" .. table.concat(texts, "\n") .. "\n"
		check("the open quest lists four objectives", joined:find("Objective 4", 1, true) and not joined:find("Objective 5", 1, true))
		check("the rest fold into one line", joined:find("+2 more objectives", 1, true) ~= nil)
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		state.quests[2].objectives = {
			{ text = "Collect things", numFulfilled = 1, numRequired = 6, finished = false },
			{ text = "Talk to someone", finished = false },
		}
		addon.module.set("island", "quest_context", true)
		env.everlook_island_key("down")
		-- A ring on each objective, in the pane: one filled to its count, and an empty one for the objective with none.
		local function in_expanded(frame)
			while frame do
				if frame.name == "EverlookIslandExpanded" then return true end
				frame = frame.parent
			end
			return false
		end
		local fills, bars = {}, 0
		for _, frame in ipairs(frames) do
			if frame.cooldown and frame.shown == true and frame.width == 14 and in_expanded(frame) then
				fills[#fills + 1] = (env.GetTime() - frame.cooldown.start) / frame.cooldown.duration
			end
			if frame.value and frame.shown == true and frame.height == 3 and frame.width and frame.width > 100 then bars = bars + 1 end
		end
		table.sort(fills)
		check("a countable objective gets a ring that fills to its progress, the other an empty one, and no bar",
			#fills == 2 and math.abs(fills[2] - 1 / 6) < 1e-9 and fills[1] < 0.001 and bars == 0)
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		state.quests[2].objectives = {
			{ text = "0/1 Stoneanvil's Rifle", numFulfilled = 0, numRequired = 1, finished = false },
			{ text = "Wolves slain", numFulfilled = 2, numRequired = 5, finished = false },
		}
		addon.module.set("island", "quest_context", true)
		env.everlook_island_key("down")
		local texts = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if type(region.text) == "string" and region.shown ~= false then texts[#texts + 1] = region.text end
			end
		end
		local joined = "\n" .. table.concat(texts, "\n") .. "\n"
		check("an objective that already shows its count does not repeat it", joined:find("\n0/1 Stoneanvil's Rifle\n", 1, true) ~= nil)
		check("one that does not gets the count added", joined:find("\nWolves slain  2/5\n", 1, true) ~= nil)
	end
	do
		local addon, env, _, _, _, _, frames = quest_world()
		local shown = {}
		env.GameTooltip = {
			SetOwner = function() end, Show = function() end, Hide = function() end,
			SetText = function(_, text) shown[#shown + 1] = text end,
		}
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "hover_preview", false)
		local island_frame
		for _, candidate in ipairs(frames) do if candidate.name == "EverlookIsland" then island_frame = candidate end end
		island_frame.scripts.OnEnter(island_frame)
		local while_closed = #shown
		island_frame.scripts.OnLeave(island_frame)
		env.everlook_island_key("down")
		island_frame.scripts.OnEnter(island_frame)
		check("the closed pill tooltips the quest and the open island does not", while_closed == 1 and #shown == 1)
	end
	do
		local addon, env, _, state, _, _, frames = quest_world()
		table.insert(state.quests, 1, { isHeader = true, title = "Elwynn Forest" })
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "quest_plan", true)
		env.everlook_island_key("down")
		local texts = {}
		for _, frame in ipairs(frames) do
			for _, region in ipairs(frame.regions or {}) do
				if type(region.text) == "string" and region.shown ~= false then texts[#texts + 1] = (region.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
			end
		end
		local joined = "\n" .. table.concat(texts, "\n") .. "\n"
		check("the route lists three quests after the current one",
			joined:find("\n1. Suitable farther\n", 1, true) and joined:find("\n2. Nearby dangerous\n", 1, true)
			and joined:find("\n3. Across the sea\n", 1, true) and not joined:find("4. ", 1, true))
		check("each says where it is: the zone from the log and the distance", joined:find("\nElwynn Forest, ~800 yd\n", 1, true) ~= nil)
		check("a row stays at two lines and leaves its reasoning to the tooltip", joined:find("Why:", 1, true) == nil)
		local tips = {}
		env.GameTooltip = { SetOwner = function() end, SetText = function(_, text) tips[#tips + 1] = text end, Show = function() end, Hide = function() end }
		for _, frame in ipairs(frames) do
			if frame.scripts and frame.scripts.OnEnter then frame.scripts.OnEnter(frame) end
		end
		local tooltips = table.concat(tips, "\n")
		check("the tooltip says why it was chosen", tooltips:find("Why: closest to you; level 18, 6 above you", 1, true) ~= nil
			and tooltips:find("Why: level 12, close to yours", 1, true) ~= nil)
	end
	do
		local addon, _, _, _, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		local function label(text)
			for _, frame in ipairs(frames) do
				for _, region in ipairs(frame.regions or {}) do
					if region.text == text and region.shown ~= false then return region end
				end
			end
		end
		local level = label("12")
		check("the quest capsule carries the level after its distance, in white", level ~= nil and math.abs(level.color[1] - 245 / 255) < 0.01 and label("45%") == nil)
		local held_width = addon.island.view().width
		addon.module.set("island", "closed_xp", true)
		local percent = label("45%")
		check("and the experience percent in the bar's purple when the pill shows it", percent ~= nil and math.abs(percent.color[1] - 173 / 255) < 0.01)
		check("the capsule holds its width when a part is added", addon.island.view().width == held_width)
	end
	do
		local addon, env, _, state = quest_world()
		local positions = { [21] = { 0.1, 0.1 }, [22] = { 0.9, 0.9 }, [23] = { 0.12, 0.1 }, [24] = { 0.5, 0.5 } }
		env.C_Map = env.C_Map or {}
		env.C_Map.GetBestMapForUnit = function() return 37 end
		env.C_Map.GetWorldPosFromMapPos = function(_, point) return 0, { x = point.x * 1000, y = point.y * 1000 } end
		env.C_QuestLog.GetNextWaypoint = function(quest_id)
			local at = positions[quest_id]
			return 37, at[1], at[2]
		end
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "quest_plan", true)
		local quests = addon.island_quests
		local view = quests.view()
		check("with no pin the island shows the best guess", view.reason == "Suggested" and view.current.id == 23)
		local route, from_pin = quests.route(view)
		check("with no pin the route follows the player's location", from_pin == false and #route == 3 and route[1].id == 22)
		addon.island.pin_quest(22)
		view = quests.view()
		check("a pinned quest is always the one shown", view.reason == "Pinned" and view.current.id == 22)
		route, from_pin = quests.route(view)
		local ids = {}
		for _, record in ipairs(route) do ids[#ids + 1] = record.id end
		check("with a pin the route builds out from the pinned quest", from_pin == true and table.concat(ids, ",") == "24,23,21")
		check("each stop says how far it is from the pin", route[1].from_pin and math.floor(route[1].from_pin) == 565
			and quests.why(route[1]):find("yd from your pinned quest", 1, true) ~= nil)
		addon.island.pin_quest(nil)
		_, from_pin = quests.route(quests.view())
		check("releasing the pin returns the route to the player's location", from_pin == false)
	end
	do
		local addon, env, event, state, _, _, frames = quest_world()
		addon.module.set("island", "quest_context", true)
		addon.module.set("island", "quest_plan", true)
		local function suggestion() return notice_key(addon, "pin-suggest") end
		local function button(label)
			for _, frame in ipairs(frames) do
				if frame.action_id and frame.label and frame.label.text == label and frame.shown ~= false then return frame end
			end
		end
		check("pin suggestions start on", addon.module.get("island", "feed_pin_suggest") == true)
		check("nothing is suggested before anything happens", suggestion() == nil)
		table.insert(state.quests, { questID = 25, title = "A fresh errand", level = 12, distance = 5000,
			objectives = { { text = "Fetch", numFulfilled = 0, numRequired = 3, finished = false } } })
		state.time = state.time + 100
		event("QUEST_ACCEPTED", 25)
		event("QUEST_LOG_UPDATE")
		check("accepting a quest offers to pin it", suggestion() and suggestion().text == "Pin A fresh errand?"
			and suggestion().detail:find("New quest", 1, true) ~= nil and #suggestion().actions == 2)
		button("Pin").scripts.OnClick(button("Pin"), "LeftButton")
		check("the Pin button pins that quest", addon.island_quests.pinned_id() == 25)
		check("and clears the offer", suggestion() == nil)
		state.quests[1].objectives[1].numFulfilled = 3
		state.time = state.time + 5
		event("QUEST_LOG_UPDATE")
		check("a second offer inside a minute waits", suggestion() == nil)
		state.time = state.time + 120
		state.quests[2].objectives[1].numFulfilled = 4
		event("QUEST_LOG_UPDATE")
		check("progress on a quest that is not pinned offers to pin it later",
			suggestion() and suggestion().detail:find("making progress", 1, true) ~= nil)
		state.time = state.time + 120
		table.remove(state.quests, #state.quests)
		event("QUEST_LOG_UPDATE")
		check("finishing the pinned quest offers the next best one",
			suggestion() and suggestion().detail:find("Your pinned quest is done", 1, true) ~= nil and addon.island_quests.pinned_id() == nil)
	end
end
