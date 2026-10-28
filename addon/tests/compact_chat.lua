-- Compact chat: shows say, yell, party, raid, guild, officer, instance, and whisper lines as a short label (S, Y, P, PL, R, RL, RW, G, O, I, IL, W, or To), the name, then the message, with no brackets, and a numbered channel as its number.
return function(check, lib)
	local load_all = lib.load_all
	-- Blizzard builds a chat line as format(CHAT_<TYPE>_GET .. message, name).
	-- Replacing those format strings sets the prefix and the message color
	-- without touching message text, which can be secret in restricted content.
	local function chat_world()
		local chat, chat_env, chat_event = load_all()
		local added = {}
		local function frame()
			local window = {}
			function window:AddMessage(text, ...) added[#added + 1] = { text = text, extra = { ... } } end
			return window
		end
		chat_env.CHAT_FRAMES = { "ChatFrame1", "ChatFrame2" }
		chat_env.ChatFrame1, chat_env.ChatFrame2 = frame(), frame()
		chat_env.ChatTypeInfo = { GUILD = { r = 0.25, g = 1, b = 0.25 }, SAY = { r = 1, g = 1, b = 1 }, CHANNEL1 = { r = 1, g = 0.75, b = 0.75 } }
		chat_env.CHAT_GUILD_GET = "|Hchannel:Guild|h[Guild]|h %s: "
		chat_env.CHAT_SAY_GET = "%s says: "
		chat_env.CHAT_CHANNEL_GET = "%s: "
		return chat, chat_env, chat_event, added
	end
	local chat, chat_env, chat_event, chat_lines = chat_world()
	chat.module.set("compact_chat", "enabled", true)
	local guild_line = chat_env.CHAT_GUILD_GET:format("NAME") .. "hello there"
	check("a guild line reads abbreviation, name, then the message in its own color", guild_line:find("|cff40ff40G|r NAME hello there", 1, true) ~= nil)
	check("the line no longer says Guild or ends the name with a colon", not guild_line:find("Guild", 1, true) and not guild_line:find(":", 1, true))
	check("a say line gets its own abbreviation", chat_env.CHAT_SAY_GET:format("NAME"):find("|cffffffffS|r NAME", 1, true) ~= nil)
	check("the message is left in the color the game gives the line", guild_line:match("hello there$") ~= nil and guild_line:find("|cffffffffhello", 1, true) == nil and chat_env.CHAT_SAY_GET:match("NAME |c") == nil and chat_env.CHAT_SAY_GET:format("N"):match("|r N $") ~= nil)
	chat.module.set("compact_chat", "enabled", false)
	check("disabling puts the game's own formats back", chat_env.CHAT_GUILD_GET == "|Hchannel:Guild|h[Guild]|h %s: " and chat_env.CHAT_SAY_GET == "%s says: " and chat_env.CHAT_CHANNEL_GET == "%s: ")
	chat.module.set("compact_chat", "enabled", true)
	chat_env.ChatTypeInfo.GUILD = { r = 1, g = 0, b = 0 }
	chat_event("UPDATE_CHAT_COLOR")
	check("changing the chat color recolors the abbreviation", chat_env.CHAT_GUILD_GET:format("N"):find("|cffff0000G|r", 1, true) ~= nil)
	chat_env.ChatTypeInfo.GUILD = nil
	chat_event("UPDATE_CHAT_COLOR")
	check("a type with no chat color falls back to white", chat_env.CHAT_GUILD_GET:format("N"):find("|cffffffffG|r", 1, true) ~= nil)

	local mark = chat_env.CHAT_SAY_GET:match("^(|cff%x%x%x%x%x%x|r)")
	local say = chat_env.CHAT_SAY_GET:format("|Hplayer:Thrall:1:SAY|h[|cffc79c6eThrall|r]|h") .. "for the Horde"
	chat_env.ChatFrame1:AddMessage(say, 1, 1, 1, 7)
	check("the brackets around the sender go and its class color stays", chat_lines[1].text:find("|Hplayer:Thrall:1:SAY|h|cffc79c6eThrall|r|h", 1, true) ~= nil)
	check("no bracket is left in the line", chat_lines[1].text:find("[", 1, true) == nil)
	check("the invisible marker is removed before the line shows", chat_lines[1].text:find(mark, 1, true) == nil and chat_lines[1].text:find("for the Horde", 1, true) ~= nil)
	check("the other AddMessage arguments pass through", chat_lines[1].extra[1] == 1 and chat_lines[1].extra[4] == 7)
	local system = "|Hplayer:Jaina:2|h[Jaina]|h has come online."
	chat_env.ChatFrame2:AddMessage(system)
	check("a line the module did not format keeps its brackets", chat_lines[2].text == system)
	chat_env.issecretvalue = function(value) return value == "secret line" end
	chat_env.ChatFrame1:AddMessage("secret line")
	check("secret text passes through untouched", chat_lines[3].text == "secret line")
	chat_env.issecretvalue = nil
	chat_env.ChatFrame1:AddMessage(42)
	check("a value that is not text passes through", chat_lines[4].text == 42)
	local channel = "|Hchannel:channel:1|h[1. General]|h " .. chat_env.CHAT_CHANNEL_GET:format("|Hplayer:Thrall:1|h[Thrall]|h") .. "anyone around?"
	chat_env.ChatFrame1:AddMessage(channel)
	check("a numbered channel shrinks to its number in the channel's color", chat_lines[5].text:find("|cffffbfbf1|r Thrall", 1, true) == nil and chat_lines[5].text:find("|Hchannel:channel:1|h|cffffbfbf1|r|h ", 1, true) ~= nil)
	check("the channel line keeps sender and message after it", chat_lines[5].text:find("|Hplayer:Thrall:1|hThrall|h anyone around?", 1, true) ~= nil)
	chat.module.set("compact_chat", "enabled", false)
	check("a disabled module leaves the game's timestamps alone", chat_env.ChatFrameUtil == nil)
	chat_env.timestamps = "%H:%M "
	chat_env.GetCVar = function(name)
		if name == "showTimestamps" then return chat_env.timestamps end
	end
	chat_env.SetCVar = function(name, value)
		if name == "showTimestamps" then chat_env.timestamps = value end
	end
	chat_env.ChatFrameUtil = { GetTimestampFormat = function()
		if chat_env.timestamps ~= "none" then return chat_env.timestamps end
	end }
	local game_timestamps = chat_env.ChatFrameUtil.GetTimestampFormat
	chat.module.set("compact_chat", "enabled", true)
	check("the game's timestamps are hidden by default", chat_env.timestamps == "none" and game_timestamps() == nil and chat_env.ChatFrameUtil.GetTimestampFormat == game_timestamps)
	chat.module.set("compact_chat", "hide_timestamps", false)
	check("clearing the option brings the timestamps back", chat_env.timestamps == "%H:%M " and game_timestamps() == "%H:%M ")
	chat.module.set("compact_chat", "hide_timestamps", true)
	check("setting the option hides them again", chat_env.timestamps == "none" and game_timestamps() == nil)
	chat.module.set("compact_chat", "enabled", false)
	check("turning the module off restores the previous timestamp choice", chat_env.timestamps == "%H:%M " and game_timestamps() == "%H:%M ")
	chat_env.timestamps = "|cffff9900%H:%M|r "
	chat.module.set("compact_chat", "enabled", true)
	check("enabling again hides the timestamp choice the player has now", chat_env.timestamps == "none")
	chat.module.set("compact_chat", "enabled", false)
	check("turning it off restores that later choice", chat_env.timestamps == "|cffff9900%H:%M|r ")
	chat.module.set("compact_chat", "enabled", true)
	-- The player picks a format in Options, Social while the module has timestamps hidden.
	chat_env.timestamps = "%I:%M "
	chat.module.set("compact_chat", "enabled", false)
	check("a format the player picked meanwhile is kept, not overwritten", chat_env.timestamps == "%I:%M " and chat_env.EverlookSaved.compact_chat_before == nil)
	chat.module.set("compact_chat", "enabled", true)
	-- Picked again, then the chat windows change and the module hides timestamps once more before it lets go.
	chat_env.timestamps = "%H:%M:%S "
	chat_event("UPDATE_CHAT_WINDOWS")
	check("a chat window change hides the timestamps again", chat_env.timestamps == "none")
	chat.module.set("compact_chat", "enabled", false)
	check("and the format picked before that change is the one that comes back", chat_env.timestamps == "%H:%M:%S ")
	do
		-- A reload in the middle: a new session with the same saved variables, and the game still holding "none".
		chat_env.timestamps = "%H:%M "
		chat.module.set("compact_chat", "enabled", true)
		local reloaded, reloaded_env = load_all()
		reloaded_env.EverlookSaved.modules = chat_env.EverlookSaved.modules
		reloaded_env.EverlookSaved.compact_chat_before = chat_env.EverlookSaved.compact_chat_before
		reloaded_env.GetCVar = chat_env.GetCVar
		reloaded_env.SetCVar = chat_env.SetCVar
		reloaded.module.set("compact_chat", "enabled", false)
		check("turning timestamps back on after a reload restores the choice from before, not the none set here", chat_env.timestamps == "%H:%M ")
		chat.module.set("compact_chat", "enabled", false)
	end
	chat_env.timestamp_untouched = true
	chat_env.GetCVar = function() return nil end
	chat_env.SetCVar = function() chat_env.timestamp_untouched = false end
	chat_env.ChatFrameUtil = {}
	chat.module.set("compact_chat", "enabled", true)
	check("a client with no timestamp value is left alone", chat_env.timestamp_untouched and next(chat_env.ChatFrameUtil) == nil)
	chat.module.set("compact_chat", "enabled", false)
	chat_env.ChatFrame1:AddMessage(say)
	check("a disabled module leaves lines alone", chat_lines[6].text == say)
	local plain, plain_env = load_all()
	plain.module.set("compact_chat", "enabled", true)
	check("a client with none of the chat globals is left alone", plain_env.CHAT_GUILD_GET == nil)
end
