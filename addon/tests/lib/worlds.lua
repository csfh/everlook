-- The worlds the suites load the addon into: every module file on stand-ins for the game, and the
-- island and quest states on top of it. A suite gets these through the lib table run.lua hands it.
return function(root)
	local source = dofile(root .. "/tests/lib/source.lua")(root)
	local lib = { source = source, layout = dofile(root .. "/tests/lib/layout.lua") }

	local function load_all(left_out)
		left_out = left_out or {}
		local addon = { say = function() end }
		local frames, callbacks, hooks, tickers = {}, {}, {}, {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		-- world.lua shares the namespace as the global Everlook.
		env.Everlook = addon
		env.EverlookSaved = {}
		env.IsShiftKeyDown = function() return false end
		env.CreateColor = function(red, green, blue, alpha) return { r = red, g = green, b = blue, a = alpha } end
		env.InCombatLockdown = function() return false end
		env.EventUtil = {
			ContinueOnAddOnLoaded = function(_, callback) callbacks[#callbacks + 1] = callback end,
			ContinueOnPlayerLogin = function() end,
		}
		env.C_Timer = {
			After = function(_, callback) callback() end,
			NewTicker = function(_, callback)
				local ticker = { callback = callback, Cancel = function(self) self.cancelled = true end }
				tickers[#tickers + 1] = ticker
				return ticker
			end,
		}
		env.hooksecurefunc = function(target, method, callback)
			if type(target) ~= "table" then hooks[target] = method; return end
			local original = target[method]
			target[method] = function(self, ...)
				original(self, ...)
				callback(self, ...)
			end
		end
		env.CreateFrame = function(kind, name, parent, template)
			-- The game refuses an anchor that is a table and not a frame or a region, as "Wrong object type for function".
			local function check_anchor(_, relative)
				if type(relative) == "table" and relative.regions == nil and relative.parent == nil and relative.GetObjectType == nil then
					error("SetPoint(): Wrong object type for function", 3)
				end
			end
			local frame = { events = {}, scripts = {}, shown = true, name = name, parent = parent, template = template, attributes = {}, regions = {}, kind = kind,
				-- A button takes the mouse until told not to. A plain frame does not.
				mouse = kind == "Button",
				-- A frame starts in its parent's strata, one level above it. Creation order breaks a tie, the later on top.
				strata = parent and parent.strata or "MEDIUM", level = (parent and parent.level or 0) + 1, order = #frames + 1 }
			function frame:SetAttribute(key, value) self.attributes[key] = value end
			function frame:GetAttribute(key) return self.attributes[key] end
			function frame:RegisterForClicks(...) self.clicks = { ... } end
			function frame:EnableMouse(enabled) self.mouse = enabled end
			function frame:IsMouseEnabled() return self.mouse == true end
			function frame:SetPassThroughButtons(...) self.pass_through = { ... } end
			function frame:EnableMouseWheel(enabled) self.mouse_wheel = enabled end
			function frame:SetScrollChild(child) self.scroll_child = child end
			function frame:SetVerticalScroll(offset) self.scroll_offset = offset end
			function frame:SetEnabled(enabled) self.enabled = enabled end
			-- A ring is a cooldown held at a percentage: started that share of 100 seconds ago.
			function frame:SetCooldown(start, duration) self.cooldown = { start = start, duration = duration } end
			function frame:SetSwipeColor(...) self.swipe_color = { ... } end
			function frame:Pause() self.paused = true end
			function frame:SetAlpha(alpha) self.alpha = alpha end
			function frame:RegisterEvent(event) self.events[event] = true; return true end
			function frame:UnregisterEvent(event) self.events[event] = nil end
			function frame:UnregisterEvent(event) self.events[event] = nil end
			function frame:SetScript(name, callback) self.scripts[name] = callback end
			function frame:SetSize(width, height) self.width, self.height = width, height end
			function frame:SetScale(scale) self.scale = scale end
			function frame:SetWidth(width) self.width = width end
			function frame:SetHeight(height) self.height = height end
			function frame:GetWidth() return self.width end
			function frame:GetHeight() return self.height end
			function frame:SetHitRectInsets(...) self.hit_insets = { ... } end
			-- point keeps the last anchor, points all of them since the last clear.
			function frame:SetPoint(...) check_anchor(...); self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end
			function frame:GetPoint(index) local point = self.points and self.points[index or 1]; if point then return unpack(point) end end
			function frame:ClearAllPoints() self.point, self.points = nil, {} end
			function frame:SetFrameStrata(strata) self.strata = strata end
			-- A frame's level moves the levels of everything under it by the same amount, as the client does
			-- (read in the client: raising the island's panel one level raised its buttons one level).
			function frame:SetFrameLevel(level)
				local delta = level - self.level
				self.level = level
				if delta == 0 then return end
				for _, other in ipairs(frames) do
					local walker = other.parent
					while walker do
						if walker == self then other.level = other.level + delta; break end
						walker = walker.parent
					end
				end
			end
			function frame:GetFrameLevel() return self.level end
			function frame:GetFrameStrata() return self.strata end
			function frame:SetClampedToScreen() end
			function frame:SetClipsChildren(enabled) self.clips = enabled and true or false end
			function frame:SetAllPoints(target) self.all_points = target or true end
			function frame:SetMinMaxValues(min_value, max_value) self.min, self.max = min_value, max_value end
			function frame:SetValue(value) self.value = value end
			function frame:SetStatusBarColor(...) self.bar_color = { ... } end
			function frame:SetStatusBarTexture(texture) self.status_texture = texture end
			function frame:Hide() self.shown = false end
			function frame:IsShown() return self.shown ~= false end
			function frame:GetChildren()
				local list = {}
				for _, other in ipairs(frames) do
					if other.parent == self and other.kind ~= nil and other.name ~= "" then list[#list + 1] = other end
				end
				return unpack(list)
			end
			function frame:Show() self.shown = true end
			function frame:CreateTexture(_, layer)
				local texture = {
					parent = self, layer = layer,
					SetAllPoints = function(texture, target) texture.all_points = target or true end, SetColorTexture = function(self, ...) self.color = { ... } end,
					SetTexture = function(self, path) self.path = path end, SetTexCoord = function() end,
					SetAtlas = function(self, atlas) self.atlas = atlas end,
					SetVertexColor = function(self, ...) self.color = { ... } end,
					SetGradient = function(self, orientation, low, high) self.gradient = { orientation = orientation, low = low, high = high } end,
					SetPoint = function(self, ...) check_anchor(...); self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end,
					ClearAllPoints = function(self) self.point, self.points = nil, {} end,
					SetSize = function(self, width, height) self.width, self.height = width, height end,
					SetRotation = function(self, radians) self.rotation = radians end,
					Show = function(self) self.shown = true end, Hide = function(self) self.shown = false end,
				}
				self.regions[#self.regions + 1] = texture
				return texture
			end
			function frame:CreateAnimationGroup()
				local group = { animations = {}, scripts = {} }
				self.animation_groups = self.animation_groups or {}
				self.animation_groups[#self.animation_groups + 1] = group
				function group:SetScript(name, callback) self.scripts[name] = callback end
				function group:SetToFinalAlpha() end
				function group:Stop() self.playing = false end
				function group:Play()
					self.playing = true
					for _, animation in ipairs(self.animations) do animation.progress = 0 end
				end
				function group:CreateAnimation(kind)
					local animation = { kind = kind, progress = 0 }
					function animation:SetOffset(x, y) self.x, self.y = x, y end
					function animation:SetFromAlpha(value) self.from = value end
					function animation:SetToAlpha(value) self.to = value end
					function animation:SetDuration(value) self.duration = value end
					function animation:SetSmoothing(value) self.smoothing = value end
					function animation:SetTarget(target) self.target = target end
					function animation:GetSmoothProgress() return self.progress end
					self.animations[#self.animations + 1] = animation
					return animation
				end
				return group
			end
			function frame:CreateFontString(_, _, font)
				local label = {
					font = font, parent = self,
					SetPoint = function(self, ...) check_anchor(...); self.point = { ... }; self.points = self.points or {}; self.points[#self.points + 1] = self.point end,
					ClearAllPoints = function(self) self.point, self.points = nil, {} end,
					SetJustifyH = function(self, justify) self.justify = justify end, SetFontObject = function(self, font) self.font = font end, SetWordWrap = function(self, enabled) self.wrap = enabled end,
					SetText = function(self, text) self.text = text end,
					SetWidth = function(self, width) self.width = width end, SetHeight = function(self, height) self.height = height end,
					SetTextColor = function(self, ...) self.color = { ... } end, SetSpacing = function(self, spacing) self.spacing = spacing end,
					SetMaxLines = function(self, lines) self.max_lines = lines end, GetLineHeight = function() return 14 end,
					GetStringWidth = function(self) return #(self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "OO") * 7 end,
					SetNonSpaceWrap = function() end, SetAlpha = function(self, alpha) self.alpha = alpha end,
					GetStringHeight = function(self)
						-- Colour codes draw nothing, so they take no room.
						local shown_length = #((self.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
						local lines = self.wrap and math.max(1, math.ceil(shown_length / math.max(1, math.floor((self.width and self.width > 0 and self.width or 300) / 7)))) or 1
						if self.max_lines and self.max_lines > 0 then lines = math.min(lines, self.max_lines) end
						return lines * 14 + (lines - 1) * (self.spacing or 0)
					end,
					Hide = function(self) self.shown = false end, Show = function(self) self.shown = true end,
					SetShown = function(self, value) self.shown = value end,
				}
				self.regions[#self.regions + 1] = label
				return label
			end
			function frame:SetParent(next_parent)
				self.parent = next_parent
				if next_parent then self.strata, self.level = next_parent.strata or self.strata, (next_parent.level or 0) + 1 end
			end
			local guarded_methods = { "SetAttribute", "SetPoint", "ClearAllPoints", "SetScale", "SetSize", "Hide", "Show", "SetParent", "SetScript" }
			for method_index = 1, #guarded_methods do
				local method = guarded_methods[method_index]
				local original = frame[method]
				frame[method] = function(self, ...)
					if type(self.template) == "string" and self.template:find("Secure", 1, true) and env.InCombatLockdown() then
						error("protected " .. method .. " during combat")
					end
					if original then return original(self, ...) end
				end
			end
			frames[#frames + 1] = frame
			return frame
		end
		for _, file in ipairs({ "world", "module", "tooltips", "blizzard_settings", "quest_text_size", "flight_time", "friend_conveniences", "useful_tooltips", "auto_loot", "quest_automation", "auto_repair", "sell_junk", "open_containers", "fonts", "hide_clutter", "auto_responses", "chat_layout", "minimap_coordinates", "quest_levels", "reward_marks", "cinematic_skip", "camera_distance", "swing_timers", "unit_frame_names", "nameplates_kinds", "nameplates", "nameplate_titles", "quest_nameplates", "tracker_text_size", "take_mail", "tooltip_cursor", "compact_chat", "radial_menu_wheel", "radial_menu", "island_capsule", "island_row", "island_grid", "island_section", "island_blocks", "island_reaction", "island_summary", "island_quests", "island_actions", "island_vitals", "island_history", "island_surface", "island_scroll", "island_notice", "island_inbox", "island_toasts", "island_constants", "island", "island_feed_kit", "island_share", "island_quest_notices", "island_loot", "island_hearth", "island_reputation", "island_professions", "island_mail", "island_invites", "island_buffs", "island_recap", "island_experience", "island_reactions", "island_warnings", "action_shortcuts", "bags_layout", "bags_item_level", "bags_junk", "bags_categories", "bags_pins", "bags_assign", "bags_alts", "bags_recent", "bags_folds", "bags_headers", "bags_chips", "bags_search", "bags_marker", "bags", "action_bar_slots_layouts", "action_bar_slots" }) do
			if not left_out[file] then
				local chunk = assert(loadfile(source(file)))
				setfenv(chunk, env)
				chunk("Everlook", addon)
			end
		end
		for _, callback in ipairs(callbacks) do callback() end
		local function event(name, ...)
			for _, frame in ipairs(frames) do
				if frame.events[name] and frame.scripts.OnEvent then frame.scripts.OnEvent(frame, name, ...) end
			end
		end
		return addon, env, event, hooks, tickers, frames
	end
	lib.load_all = load_all

	-- Only the files given, on lighter stand-ins than load_all's, with tickers kept on env.tickers.
	local function load_files(files)
		local addon = {}
		local frames, callbacks, tickers = {}, {}, {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.tickers = tickers
		function addon.say(text)
			addon.said = text
		end
		env.EventUtil = {
			ContinueOnAddOnLoaded = function(_, callback)
				callbacks[#callbacks + 1] = callback
			end,
			ContinueOnPlayerLogin = function() end,
		}
		env.IsShiftKeyDown = function()
			return false
		end
		env.C_Timer = {
			After = function(_, callback)
				callback()
			end,
			NewTicker = function(_, callback)
				local ticker = {
					callback = callback,
					Cancel = function(self)
						self.cancelled = true
					end,
				}
				tickers[#tickers + 1] = ticker
				return ticker
			end,
		}
		env.CreateFrame = function()
			local frame = { events = {}, scripts = {} }
			function frame:RegisterEvent(event)
				self.events[event] = true
			end
			function frame:UnregisterEvent(event)
				self.events[event] = nil
			end
			function frame:SetScript(name, callback)
				self.scripts[name] = callback
			end
			function frame:SetSize() end
			function frame:SetPoint() end
			function frame:Hide()
				self.hidden = true
			end
			function frame:Show()
				self.hidden = false
			end
			function frame:CreateFontString()
				return {
					SetPoint = function() end,
					SetText = function(self, text)
						self.text = text
					end,
					Hide = function(self)
						self.hidden = true
					end,
					Show = function(self)
						self.hidden = false
					end,
				}
			end
			frames[#frames + 1] = frame
			return frame
		end
		for index = 1, #files do
			local chunk = assert(loadfile(source(files[index])))
			setfenv(chunk, env)
			chunk("Everlook", addon)
		end
		for index = 1, #callbacks do
			callbacks[index]()
		end
		local function fire(name, ...)
			for index = 1, #frames do
				local frame = frames[index]
				if frame.events[name] and frame.scripts.OnEvent then
					frame.scripts.OnEvent(frame, name, ...)
				end
			end
		end
		return addon, env, fire
	end
	lib.load_files = load_files

	local function island_world()
		local addon, env, event, hooks, tickers, frames = load_all()
		local afters, state = {}, {
			xp = 450, xp_max = 1000, level = 12, money = 12345,
			hour = 14, minute = 5, time = 100,
			slots = { [1] = { 40, 50 }, [5] = { 10, 20 } },
			bags = { [0] = 6, [1] = 2 }, bag_families = {},
			health_reads = 0, name_reads = 0, power_reads = 0,
		}
		local function forbidden(kind)
			return function()
				state[kind] = (state[kind] or 0) + 1
				error(kind .. " is not a safe island readout")
			end
		end
		env.C_Timer.After = function(delay, callback)
			afters[#afters + 1] = { delay = delay, callback = callback }
		end
		env.UIParent = { regions = {} }
		env.BACKPACK_CONTAINER = 0
		env.NUM_BAG_SLOTS = 1
		env.INVSLOT_FIRST_EQUIPPED = 1
		env.INVSLOT_LAST_EQUIPPED = 19
		env.UnitXP = function() return state.xp end
		env.UnitXPMax = function() return state.xp_max end
		env.UnitLevel = function() return state.level end
		env.GetMoney = function() return state.money end
		env.GetGameTime = function() return state.hour, state.minute end
		env.GetTime = function() return state.time end
		env.GetInventoryItemDurability = function(slot)
			local pair = state.slots[slot]
			if pair then return pair[1], pair[2] end
		end
		env.C_Container = {
			GetContainerNumFreeSlots = function(bag) return state.bags[bag] or 0, state.bag_families[bag] or 0 end,
		}
		env.C_Map = {
			GetBestMapForUnit = function() return 37 end,
			GetPlayerMapPosition = function()
				return { GetXY = function() return 0.5, 0.25 end }
			end,
		}
		env.UnitHealth = forbidden("health_reads")
		env.UnitHealthMax = forbidden("health_reads")
		env.UnitPower = forbidden("power_reads")
		env.UnitName = forbidden("name_reads")
		env.MainMenuExpBar = { Hide = function() error("the default experience bar must stay") end }
		env.StatusTrackingBarManager = { Hide = function() error("the default experience bar must stay") end }
		env.EverlookMinimapButton = { SetParent = function() error("the minimap button must stay") end }
		-- The geometry tests measure the plain level chip. The wider pill has its own tests.
		addon.module.set("island", "closed_xp", false)
		return addon, env, event, state, afters, tickers, frames, hooks
	end
	local function fire_after(afters, delay)
		for index = 1, #afters do
			if afters[index].delay == delay and not afters[index].done then
				afters[index].done = true
				afters[index].callback()
				return true
			end
		end
	end
	local function finish_animations(frames)
		local pending = {}
		for _, frame in ipairs(frames) do
			for _, group in ipairs(frame.animation_groups or {}) do
				if group.playing then pending[#pending + 1] = group end
			end
		end
		for _, group in ipairs(pending) do
			group.playing = false
			for _, animation in ipairs(group.animations) do animation.progress = 1 end
			if group.scripts.OnFinished then group.scripts.OnFinished(group) end
		end
	end
	local function last_toast_text(addon)
		local toasts = addon.island.view().toasts
		return toasts[#toasts] and toasts[#toasts].text
	end
	-- A bar is a status bar that is showing. The island draws none of its own now.
	local function shown_bar(frames)
		for index = 1, #frames do
			if frames[index].value ~= nil and frames[index].shown == true then return frames[index] end
		end
	end
	local function secret_stat()
		local value = newproxy(true)
		local meta = getmetatable(value)
		meta.__add = function() error("arithmetic on a secret value") end
		meta.__sub = function() error("arithmetic on a secret value") end
		meta.__mul = function() error("arithmetic on a secret value") end
		meta.__div = function() error("arithmetic on a secret value") end
		meta.__unm = function() error("arithmetic on a secret value") end
		meta.__lt = function() error("comparison on a secret value") end
		meta.__le = function() error("comparison on a secret value") end
		return value
	end
	local function quest_world()
		local addon, env, event, state, afters, tickers, frames = island_world()
		state.quests, state.watched, state.selected = {
			{ questID = 21, title = "Nearby dangerous", level = 18, distance = 100 },
			{ questID = 22, title = "Suitable farther", level = 12, distance = 800 },
			{ questID = 23, title = "Ready to return", level = 40, distance = 400, ready = true },
			{ questID = 24, title = "Across the sea", level = 12, distance = 1, remote = true },
		}, { 21, 22 }, 22
		for _, quest in ipairs(state.quests) do quest.objectives = { { text = "Collect things", numFulfilled = 1, numRequired = 6, finished = false } } end
		local function find(id)
			for _, quest in ipairs(state.quests) do if quest.questID == id then return quest end end
		end
		env.C_QuestLog = {
			GetNumQuestLogEntries = function() return #state.quests end,
			GetInfo = function(index) return state.quests[index] end,
			GetNumQuestWatches = function() return #state.watched end,
			GetQuestIDForQuestWatchIndex = function(index) return state.watched[index] end,
			GetQuestObjectives = function(id) return find(id).objectives end,
			GetDistanceSqToQuest = function(id)
				local quest = find(id)
				return quest.distance and quest.distance * quest.distance, not quest.remote
			end,
			ReadyForTurnIn = function(id) return find(id).ready or false end,
		}
		env.C_SuperTrack = { GetSuperTrackedQuestID = function() return state.selected end }
		addon.module.set("island", "enabled", true)
		-- The older quest tests exercise the fallbacks that apply without a suggestion. The suggestion has its own tests.
		addon.module.set("island", "quest_plan", false)
		-- Quest events collapse inside half a second. These tests treat each event as its own moment.
		local burst_event = event
		event = function(name, ...)
			if name:find("^QUEST_") or name == "SUPER_TRACKING_CHANGED" then state.time = state.time + 1 end
			return burst_event(name, ...)
		end
		return addon, env, event, state, afters, tickers, frames
	end
	lib.island_world, lib.fire_after, lib.finish_animations = island_world, fire_after, finish_animations
	lib.last_toast_text, lib.shown_bar, lib.secret_stat, lib.quest_world = last_toast_text, shown_bar, secret_stat, quest_world
	return lib
end
