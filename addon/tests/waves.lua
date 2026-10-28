return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(files)
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

	local addon, play, fire = load({
		"world", "module", "tooltips", "useful_tooltips", "chat_layout", "minimap_coordinates", "quest_levels", "cinematic_skip", "camera_distance", "ground_effects", "take_mail",
	})
	play.TooltipDataProcessor = {
		AddTooltipPostCall = function(kind, callback)
			play.tooltip_calls = play.tooltip_calls or {}
			play.tooltip_calls[kind] = callback
		end,
	}
	play.Enum = { TooltipDataType = { Item = 0, Unit = 2 }, GossipOption = { Vendor = 1, Gossip = 2, Taxi = 3, Trainer = 4, Binder = 5 } }
	-- Tooltips install on enable, after the processor exists. Reload the module's apply by setting enabled.
	addon.module.set("useful_tooltips", "enabled", true)
	local lines = {}
	local tooltip = {
		AddLine = function(_, text)
			lines[#lines + 1] = text
		end,
		HasScript = function()
			return true
		end,
		HookScript = function() end,
	}
	play.tooltip_calls[0](tooltip, { id = 20 })
	local joined = table.concat(lines, "|")
	check("the item tooltip shows the item id", joined:find("Item ID: 20", 1, true) ~= nil)
	lines = {}
	play.issecretvalue = function(value)
		return value == "secret"
	end
	play.tooltip_calls[0](tooltip, { id = "secret" })
	check("a secret tooltip id adds no line", #lines == 0)
	play.issecretvalue = nil

	check("coordinates format a map position", addon.minimap_coordinates.format(0.5, 0.25) == "50.0, 25.0")
	check("coordinates stay blank without a position", addon.minimap_coordinates.format(nil, 0.2) == "")
	play.C_Map = {}
	check("coordinates stay blank without a map position", addon.minimap_coordinates.player_text() == "")
	play.C_Map = {
		GetBestMapForUnit = function() return 37 end,
		GetPlayerMapPosition = function()
			return { x = 0.5, y = 0.25 }
		end,
	}
	check("coordinates read a table position", addon.minimap_coordinates.player_text() == "50.0, 25.0")
	play.C_Map.GetPlayerMapPosition = function()
		return { GetXY = function() return 0.2, 0.4 end }
	end
	check("coordinates read a vector position", addon.minimap_coordinates.player_text() == "20.0, 40.0")
	play.C_Map.GetPlayerMapPosition = function() return nil end
	check("coordinates are blank when the client gives no position", addon.minimap_coordinates.player_text() == "")
	play.C_Map.GetPlayerMapPosition = function()
		return { GetXY = function() return nil, nil end }
	end
	check("coordinates are blank when the position has no numbers", addon.minimap_coordinates.player_text() == "")
	play.C_Map = nil
	play.Minimap = {}
	addon.module.set("minimap_coordinates", "enabled", true)
	addon.module.set("minimap_coordinates", "enabled", false)
	check("turning coordinates off stops the ticker", play.tickers[#play.tickers].cancelled)

	-- Quest levels: the level goes on the quest log list after the game has drawn it, and nothing of the game's is replaced.
	local function region(initial)
		local r = { text = initial, height = #initial > 25 and 28 or 14 }
		function r:GetText() return self.text end
		function r:SetText(value) self.text = value; self.height = #value > 25 and 28 or 14 end
		function r:GetHeight() return self.height end
		return r
	end
	local function log_button(quest_id, text)
		local b = { questID = quest_id, Text = region(text), height = 30 }
		function b:GetHeight() return self.height end
		function b:SetHeight(value) self.height = value end
		return b
	end
	local first, second, third = log_button(1, "Wolves"), log_button(2, "[2] Murloc Menace"), log_button(3, "A Quite Long Quest Title")
	local dirty = 0
	play.QuestScrollFrame = { titleFramePool = { EnumerateActive = function()
		local list, index = { first, second, third }, 0
		return function() index = index + 1; return list[index], true end
	end }, Contents = { MarkDirty = function() dirty = dirty + 1 end } }
	local gets_title = function() return "untouched" end
	play.C_QuestLog = { GetTitleForQuestID = gets_title, GetQuestDifficultyLevel = function(quest_id) return quest_id == 3 and 9 or 8 end }
	local hooks = {}
	play.hooksecurefunc = function(name, fn) hooks[#hooks + 1] = { name = name, fn = fn } end
	play.QuestLogQuests_Update = function() end
	addon.module.set("quest_levels", "enabled", true)
	check("the quest log list is hooked once, by name, after the game draws it", #hooks == 1 and hooks[1].name == "QuestLogQuests_Update")
	check("a quest title gains its level", first.Text:GetText() == "[8] Wolves")
	check("a title that already starts with a bracketed number is left alone", second.Text:GetText() == "[2] Murloc Menace")
	check("a button grows when the longer title needs another line", third.Text:GetText() == "[9] A Quite Long Quest Title" and third.height == 44 and dirty >= 1)
	check("the lookup the game and the tracker call is not replaced", play.C_QuestLog.GetTitleForQuestID == gets_title)
	first.Text:SetText("Wolves")
	hooks[1].fn()
	check("a list the game draws again is decorated again", first.Text:GetText() == "[8] Wolves")
	hooks[1].fn()
	check("a title already decorated is not decorated twice", first.Text:GetText() == "[8] Wolves")
	play.issecretvalue = function(value) return value == "secret" end
	first.Text:SetText("secret")
	hooks[1].fn()
	check("a secret title is left as it is", first.Text:GetText() == "secret")
	play.issecretvalue = nil
	first.Text:SetText("Wolves of the North")
	addon.module.set("quest_levels", "enabled", false)
	check("turning quest levels off puts back the text it changed", third.Text:GetText() == "A Quite Long Quest Title" and third.height == 30)
	check("and leaves a text the game has written since", first.Text:GetText() == "Wolves of the North" and second.Text:GetText() == "[2] Murloc Menace")
	hooks[1].fn()
	check("a list drawn while it is off is not decorated", third.Text:GetText() == "A Quite Long Quest Title")
	play.QuestScrollFrame, play.hooksecurefunc, play.QuestLogQuests_Update = nil, nil, nil
	play.C_QuestLog = { GetTitleForQuestID = function() return "Wolves" end }
	check("a client without the quest log list is left alone", pcall(addon.module.set, "quest_levels", "enabled", true))
	addon.module.set("quest_levels", "enabled", false)
	play.C_QuestLog.GetTitleForQuestID = function() return "Wolves" end
	local title = "Wolves"

	-- The game's own CinematicFrame_CancelCinematic, as Shared/CinematicFrame.lua:133-141 has it at
	-- 12.0.0, with isRealCinematic set from the event's first argument as its OnEvent does (:86):
	-- this stands for Blizzard's frame handling the event before Everlook's.
	local calls = { stop = 0, scene = 0, vehicle = 0, finished = {} }
	local in_scene, scene_cancellable, movie_up = false, false, false
	play.CinematicFrame = { isRealCinematic = false }
	play.CinematicFrame_CancelCinematic = function()
		if play.CinematicFrame.isRealCinematic then
			play.StopCinematic()
		elseif play.CanCancelScene() then
			play.CancelScene()
		else
			play.VehicleExit()
		end
	end
	play.StopCinematic = function() calls.stop = calls.stop + 1 end
	play.CancelScene = function() calls.scene = calls.scene + 1 end
	play.VehicleExit = function() calls.vehicle = calls.vehicle + 1 end
	play.CanCancelScene = function() return scene_cancellable end
	play.IsInCinematicScene = function() return in_scene end
	-- MovieFrame.xml's close dialog: Yes calls MovieFrame_OnMovieFinished(MovieFrame, true).
	play.MovieFrame = { IsShown = function() return movie_up end }
	play.MovieFrame_OnMovieFinished = function(frame, user_canceled)
		calls.finished[#calls.finished + 1] = { frame = frame, user_canceled = user_canceled }
	end
	local function cinematic(can_be_cancelled)
		play.CinematicFrame.isRealCinematic = can_be_cancelled
		fire("CINEMATIC_START", can_be_cancelled, false)
	end
	addon.module.set("cinematic_skip", "enabled", true)
	cinematic(true)
	check("a cinematic the player may skip is stopped", calls.stop == 1 and calls.vehicle == 0)
	cinematic(false)
	check("a vehicle's cinematic keeps playing, and the player stays in the vehicle", calls.vehicle == 0 and calls.stop == 1)
	in_scene, scene_cancellable = true, true
	cinematic(false)
	check("a cinematic scene the game lets the player cancel is cancelled", calls.scene == 1 and calls.vehicle == 0)
	in_scene, scene_cancellable = false, false
	movie_up = true
	fire("PLAY_MOVIE", 16)
	check("a movie is finished as the player's own Yes finishes it, and nothing else is cancelled",
		#calls.finished == 1 and calls.finished[1].frame == play.MovieFrame and calls.finished[1].user_canceled == true
		and calls.vehicle == 0 and calls.stop == 1 and calls.scene == 1)
	movie_up = false
	fire("PLAY_MOVIE", 16)
	check("a movie whose frame is not up yet is left alone", #calls.finished == 1)
	play.IsShiftKeyDown = function()
		return true
	end
	movie_up = true
	cinematic(true)
	fire("PLAY_MOVIE", 16)
	check("Shift leaves a cinematic and a movie playing", calls.stop == 1 and #calls.finished == 1)
	play.IsShiftKeyDown = function()
		return false
	end
	movie_up = false
	play.StopCinematic = nil
	cinematic(true)
	check("a client without StopCinematic stops nothing and leaves no vehicle", calls.vehicle == 0 and calls.scene == 1)

	local distance = "1.0"
	play.GetCVar = function()
		return distance
	end
	play.SetCVar = function(_, value)
		distance = value
	end
	addon.module.set("camera_distance", "enabled", true)
	check("camera distance uses the saved setting", distance == "2.6")
	addon.module.set("camera_distance", "distance", 3)
	-- A reload in the middle: a new session with the same saved variables, and the game still holding the number set here.
	do
		local reloaded, reloaded_env = load({ "world", "module", "camera_distance" })
		reloaded_env.EverlookDB.qol = play.EverlookDB.qol
		reloaded_env.EverlookDB.cameraBefore = play.EverlookDB.cameraBefore
		reloaded_env.GetCVar = play.GetCVar
		reloaded_env.SetCVar = play.SetCVar
		reloaded.module.set("camera_distance", "enabled", false)
		check("turning the camera off after a reload puts back the distance from before, not the one set here", distance == "1.0")
		reloaded.module.set("camera_distance", "enabled", true)
	end
	addon.module.set("camera_distance", "enabled", false)
	check("turning the camera off restores the previous distance", distance == "1.0")

	-- Ground effects set three of the game's settings, remember each one, and put each back.
	local ground = { groundEffectDensity = "16", groundEffectDist = "70", groundEffectFade = "70" }
	local writes = {}
	play.GetCVar = function(name)
		return ground[name]
	end
	play.SetCVar = function(name, value)
		writes[#writes + 1] = name
		if ground[name] == nil then error("Unknown CVar " .. name) end
		ground[name] = value
	end
	addon.module.set("ground_effects", "enabled", true)
	check("ground effects set density, distance and fade to the saved numbers", ground.groundEffectDensity == "256" and ground.groundEffectDist == "500" and ground.groundEffectFade == "500")
	addon.module.set("ground_effects", "distance", 300)
	check("a changed number is applied at once", ground.groundEffectDist == "300" and ground.groundEffectDensity == "256")
	-- A reload in the middle: a new session with the same saved variables and the game's settings as they were left.
	do
		local reloaded, reloaded_env = load({ "world", "module", "ground_effects" })
		reloaded_env.EverlookDB.qol = play.EverlookDB.qol
		reloaded_env.EverlookDB.groundEffectsBefore = play.EverlookDB.groundEffectsBefore
		reloaded_env.GetCVar = play.GetCVar
		reloaded_env.SetCVar = play.SetCVar
		reloaded.module.set("ground_effects", "enabled", false)
		check("turning ground effects off after a reload still puts back what the game had at first, not the numbers set here",
			ground.groundEffectDensity == "16" and ground.groundEffectDist == "70" and ground.groundEffectFade == "70")
		reloaded.module.set("ground_effects", "enabled", true)
	end
	addon.module.set("ground_effects", "enabled", false)
	check("turning ground effects off puts each setting back as it was before", ground.groundEffectDensity == "16" and ground.groundEffectDist == "70" and ground.groundEffectFade == "70")
	ground.groundEffectFade = nil
	writes = {}
	addon.module.set("ground_effects", "enabled", true)
	check("a setting this client does not have is left alone, and the others still apply", ground.groundEffectFade == nil and ground.groundEffectDensity == "256" and #writes == 2)
	addon.module.set("ground_effects", "enabled", false)
	play.GetCVar = nil
	play.SetCVar = nil
	addon.module.set("ground_effects", "enabled", true)
	check("with no way to set them, ground effects do nothing and do not fail", true)
	addon.module.set("ground_effects", "enabled", false)

	local taken = {}
	local mails = {
		{ money = 5, cod = 0, items = 1 },
		{ money = 2, cod = 0, items = 0 },
	}
	local function compact()
		local kept = {}
		for index = 1, #mails do
			if not mails[index].taken then
				kept[#kept + 1] = mails[index]
			end
		end
		mails = kept
	end
	play.GetInboxNumItems = function()
		compact()
		return #mails
	end
	play.GetInboxHeaderInfo = function(index)
		local mail = mails[index]
		if not mail then
			return
		end
		return nil, nil, nil, nil, mail.money, mail.cod, 1, mail.items
	end
	play.TakeInboxMoney = function(index)
		taken[#taken + 1] = mails[index].money
		mails[index].money = 0
		if mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	play.TakeInboxItem = function(index)
		taken[#taken + 1] = "item"
		mails[index].items = mails[index].items - 1
		if mails[index].money <= 0 and mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	addon.module.set("take_mail", "enabled", true)
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("one tick takes the money and leaves the attached item", taken[1] == 5 and #taken == 1)
	play.tickers[#play.tickers].callback()
	check("the next tick takes the item that was still attached", taken[2] == "item" and #taken == 2)
	play.tickers[#play.tickers].callback()
	check("plain mail is taken again after the inbox compacts", taken[3] == 2 and #taken == 3)
	mails = { { money = 9, cod = 4, items = 0 }, { money = 3, cod = 0, items = 0 } }
	taken = {}
	play.tickers[#play.tickers].callback()
	check("cash on delivery stays in the mailbox", taken[1] == 3 and #taken == 1)
	play.IsShiftKeyDown = function()
		return true
	end
	local before_shift = #taken
	play.tickers[#play.tickers].callback()
	check("Shift stops taking mail", #taken == before_shift and play.tickers[#play.tickers].cancelled)
	play.IsShiftKeyDown = function()
		return false
	end
	taken = {}
	fire("MAIL_SHOW")
	fire("MAIL_CLOSED")
	play.tickers[#play.tickers].callback()
	check("closing the mailbox stops taking mail", #taken == 0)
	mails = { { money = 0, cod = 0, items = 2 } }
	taken = {}
	local slots = {}
	play.TakeInboxItem = function(index, slot)
		slots[#slots + 1] = slot
		mails[index].items = mails[index].items - 1
		if mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("one attachment is taken per tick", #slots == 1 and slots[1] == 1 and mails[1].items == 1)
	play.tickers[#play.tickers].callback()
	check("the next tick takes the attachment that slid forward", #slots == 2 and slots[2] == 1)
	mails = { { money = 4, cod = 0, items = 0 } }
	taken = {}
	local pending = true
	local secret_pending = {}
	play.C_Mail = {
		IsCommandPending = function()
			return pending
		end,
	}
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("a pending mail command waits", #taken == 0 and not play.tickers[#play.tickers].cancelled)
	pending = false
	play.tickers[#play.tickers].callback()
	check("the money is taken once the command finishes", taken[1] == 4 and #taken == 1)
	mails = { { money = 7, cod = 0, items = 0 } }
	taken = {}
	play.issecretvalue = function(value)
		return rawequal(value, secret_pending)
	end
	play.C_Mail.IsCommandPending = function()
		return secret_pending
	end
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("a secret mail command state waits", #taken == 0 and not play.tickers[#play.tickers].cancelled)
	play.issecretvalue = nil
	play.C_Mail = nil

	play.GetGameTime = function()
		return 9, 5
	end
	local filters = {}
	play.ChatFrame_AddMessageEventFilter = function(event, callback)
		filters[event] = callback
	end
	play.ChatFrame_RemoveMessageEventFilter = function(event)
		filters[event] = nil
	end
	play.CHAT_FRAMES = {}
	addon.module.set("chat_layout", "enabled", true)
	addon.module.set("chat_layout", "timestamps", true)
	check("a plain chat line gains a timestamp", addon.chat_layout.stamp("Hello") == "09:05 Hello")
	-- Same rule as ChatFrameUtil.ProcessMessageEventFilters: a truthy first
	-- return drops the line, and a new message replaces the arguments that follow.
	local function shown_line(filter, message, author, extra)
		local discard, new_message, new_author, new_extra = filter(nil, "CHAT_MSG_SAY", message, author, extra)
		if discard then
			return nil
		end
		if new_message then
			return new_message, new_author, new_extra
		end
		return message, author, extra
	end
	local text, author, channel = shown_line(filters.CHAT_MSG_SAY, "Hello", "Thrall", "1")
	check("a timestamped line stays in chat with its sender", text == "09:05 Hello" and author == "Thrall" and channel == "1")
	play.issecretvalue = function(value)
		return value == "secret"
	end
	local secret_text, secret_author = shown_line(filters.CHAT_MSG_SAY, "secret", "Thrall")
	check("secret chat text stays in place", secret_text == "secret" and secret_author == "Thrall" and addon.chat_layout.stamp("secret") == "secret")
	play.issecretvalue = nil
	addon.module.set("chat_layout", "timestamps", false)
	check("turning timestamps off removes the prefix", addon.chat_layout.stamp("Hello") == "Hello" and filters.CHAT_MSG_SAY == nil)
	local util_filters = {}
	play.ChatFrameUtil = {
		AddMessageEventFilter = function(event, callback)
			util_filters[event] = callback
		end,
		RemoveMessageEventFilter = function(event)
			util_filters[event] = nil
		end,
	}
	addon.module.set("chat_layout", "timestamps", true)
	text, author = shown_line(util_filters.CHAT_MSG_SAY, "Hello", "Thrall", "1")
	check("timestamps register on ChatFrameUtil and keep the sender", text == "09:05 Hello" and author == "Thrall" and filters.CHAT_MSG_SAY == nil)
	addon.module.set("chat_layout", "timestamps", false)
	check("turning timestamps off removes the ChatFrameUtil filter", util_filters.CHAT_MSG_SAY == nil)
	play.ChatFrameUtil = nil
end
