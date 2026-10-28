-- Fonts: sets chat and player names in Manrope and the rest of the interface in Expressway, and waits while you are in combat.
return function(root, check, lib)
	local load_all = lib.load_all
	local addon, env, event, hooks, _, frames = load_all()
	local font
	do
		local expressway = "Interface\\AddOns\\Everlook_Fonts\\assets\\expressway.ttf"
		local manrope = "Interface\\AddOns\\Everlook_Fonts\\assets\\manrope.ttf"
		local function font_object(path, size, flags)
			local object = { path = path, size = size, flags = flags or "" }
			function object:GetObjectType() return "Font" end
			function object:GetFont() return self.path, self.size, self.flags end
			function object:SetFont(next_path, next_size, next_flags) self.path, self.size, self.flags = next_path, next_size, next_flags end
			return object
		end
		-- A text region that inherits a font object reports that object's font
		-- until SetFont gives it one of its own.
		local function following_text(parent)
			local text = { parent = parent }
			function text:GetObjectType() return "FontString" end
			function text:GetFontObject() return self.parent end
			function text:GetFont()
				if self.path then return self.path, self.size, self.flags end
				return self.parent:GetFont()
			end
			function text:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
			return text
		end
		font = font_object("original.ttf", 12, "OUTLINE")
		local region = { path = "chat.ttf", size = 10 }
		region.GetFont, region.SetFont = font.GetFont, font.SetFont
		function region:GetObjectType() return "FontString" end
		local protected_region = { path = "protected.ttf", size = 10 }
		protected_region.GetFont, protected_region.SetFont = font.GetFont, font.SetFont
		function protected_region:GetObjectType() return "FontString" end
		function protected_region:IsForbidden() return true end
		-- A chat window copies ChatFontNormal into a font of its own the first time
		-- SetFont runs, and CreateFont lists that copy among the globals.
		local chat_font = font_object("Fonts\\ARIALN.TTF", 14)
		local chat_frame = { fontObject = chat_font }
		function chat_frame:GetFontObject() return self.fontObject end
		function chat_frame:GetFont() return self.fontObject:GetFont() end
		function chat_frame:SetFont(path, size, flags)
			if self.fontObject == chat_font then
				self.fontObject = font_object(chat_font:GetFont())
				env["table: chat frame"] = self.fontObject
			end
			self.fontObject:SetFont(path, size, flags)
		end
		chat_frame:SetFont("Fonts\\ARIALN.TTF", 16, "")
		local chat_line = following_text(chat_frame:GetFontObject())
		local nameplate_font = font_object("Fonts\\FRIZQT__.TTF", 9)
		local nameplate_name = following_text(nameplate_font)
		local unit_font = font_object("Fonts\\FRIZQT__.TTF", 10)
		local player_name = following_text(unit_font)
		local level_text = following_text(unit_font)
		local party_member = { Name = following_text(unit_font), PetFrame = { Name = following_text(unit_font) } }
		local compact_frame = { name = following_text(font_object("Fonts\\FRIZQT__.TTF", 10)) }
		local tooltip_header = font_object("Fonts\\FRIZQT__.TTF", 14)
		local tooltip_name = following_text(tooltip_header)
		local regions = { region, protected_region, chat_line, nameplate_name, player_name, level_text, tooltip_name }
		local font_frame = { GetRegions = function() return unpack(regions) end }
		env.EnumerateFrames = function(previous) if not previous then return font_frame end end
		env.TestFont = font
		env.ChatFontNormal = chat_font
		env.ChatFrame1 = chat_frame
		env.CHAT_FRAMES = { "ChatFrame1" }
		env.SystemFont_NamePlate = nameplate_font
		env.GameTooltipHeaderText = tooltip_header
		env.GameFontNormalSmall = unit_font
		env.PlayerName = player_name
		env.PartyFrame = {
			active = {},
			PartyMemberFramePool = { EnumerateActive = function() return pairs(env.PartyFrame.active) end },
			InitializePartyMemberFrames = function(self) self.active[party_member] = true end,
		}
		env.DefaultCompactUnitFrameSetup = function() end
		env.STANDARD_TEXT_FONT = "original.ttf"
		env.DAMAGE_TEXT_FONT = "original.ttf"
		env.UNIT_NAME_FONT = "Fonts\\FRIZQT__.TTF"
		env.UNIT_NAME_FONT_ROMAN = "Fonts\\FRIZQT__.TTF"
		env.NAMEPLATE_FONT = "GameFontWhite"
		addon.module.set("fonts", "enabled", true)
		check("Expressway sets interface text and skips forbidden regions", region.path == expressway and protected_region.path == "protected.ttf")
		check("Expressway replaces the interface fonts and their globals",
			font.path == expressway and unit_font.path == expressway and env.STANDARD_TEXT_FONT == expressway and env.DAMAGE_TEXT_FONT == expressway)
		check("chat windows and the chat font use Manrope at the window's size",
			select(1, chat_frame:GetFont()) == manrope and select(2, chat_frame:GetFont()) == 16 and chat_font.path == manrope)
		check("nameplates and names on unit frames use Manrope", nameplate_font.path == manrope and player_name.path == manrope)
		check("the name at the top of a tooltip uses Manrope and keeps following its font", tooltip_header.path == manrope and tooltip_name.path == nil)
		check("names drawn in the world use Manrope", env.UNIT_NAME_FONT == manrope and env.UNIT_NAME_FONT_ROMAN == manrope)
		check("NAMEPLATE_FONT names a font object, so it stays", env.NAMEPLATE_FONT == "GameFontWhite")
		check("chat lines and nameplate text keep following their fonts", chat_line.path == nil and nameplate_name.path == nil)
		addon.module.set("fonts", "size_offset", 2)
		check("font size adjustment avoids compounding", font.size == 14)
		check("text that follows a replaced font gets the adjustment once", player_name.size == 12 and level_text.size == 12)
		check("chat windows keep the size set on their tab", select(2, chat_frame:GetFont()) == 16)
		event("ADDON_LOADED")
		check("font refresh preserves configured size", font.size == 14 and player_name.size == 12 and select(2, chat_frame:GetFont()) == 16)
		local late_text = following_text(unit_font)
		regions[#regions + 1] = late_text
		event("ADDON_LOADED")
		check("text that appears later gets Expressway with the adjustment once", late_text.path == expressway and late_text.size == 12)
		do
			local walks, enumerate = 0, env.EnumerateFrames
			env.EnumerateFrames = function(previous)
				if not previous then walks = walks + 1 end
				return enumerate(previous)
			end
			addon.module.set("fonts", "size_offset", 2)
			event("PLAYER_ENTERING_WORLD", false, false)
			event("PLAYER_ENTERING_WORLD", false, false)
			check("a zone change walks no frames again", walks == 0)
			event("PLAYER_ENTERING_WORLD", true, false)
			check("a login or a reload walks them once", walks == 1)
			walks = 0
			env.InCombatLockdown = function() return true end
			event("ADDON_LOADED")
			check("a pass in combat waits", walks == 0)
			env.InCombatLockdown = function() return false end
			event("PLAYER_REGEN_ENABLED")
			check("the pass blocked by combat runs when it ends", walks == 1)
			walks = 0
			event("PLAYER_REGEN_ENABLED")
			event("PLAYER_REGEN_ENABLED")
			check("a combat end with nothing blocked walks no frames", walks == 0)
			local sets = 0
			local font_set, region_set = font.SetFont, region.SetFont
			font.SetFont = function(...) sets = sets + 1; return font_set(...) end
			region.SetFont = function(...) sets = sets + 1; return region_set(...) end
			event("PLAYER_ENTERING_WORLD", true, false)
			check("a second pass sets no font that is already right", sets == 0)
			font.SetFont, region.SetFont = font_set, region_set
			-- Loads in one burst are answered by one pass, a slice at a time.
			walks = 0
			local steps, wakes, step = 0, 0, nil
			local sched_before, profile_before, frame_before = addon.sched, env.debugprofilestop, env.CreateFrame
			addon.sched = { task = function(_, opts) step = opts.step return { wake = function() wakes = wakes + 1 end } end }
			env.debugprofilestop = function() steps = steps + 1 return steps * 5 end
			env.CreateFrame = env.CreateFrame or function() end
			local many, index_of = {}, {}
			for index = 1, 100 do
				many[index] = { GetRegions = function() end }
				index_of[many[index]] = index
			end
			local counted = env.EnumerateFrames
			env.EnumerateFrames = function(previous)
				if not previous then walks = walks + 1 end
				return many[previous and index_of[previous] + 1 or 1]
			end
			for index = 1, 300 do env["junk_global_" .. index] = { GetObjectType = function() return "Frame" end } end
			event("ADDON_LOADED")
			event("ADDON_LOADED")
			event("ADDON_LOADED")
			check("a burst of loaded addons wakes the task and walks nothing yet", wakes == 3 and walks == 0 and step ~= nil)
			local slices = 0
			while step(1.5) and slices < 100 do slices = slices + 1 end
			check("the pass is cut into slices, in the globals as well as the frames, and walks the frames once", slices >= 6 and walks == 1)
			check("and nothing is left to do after it", step(1.5) == false and walks == 1)
			addon.sched, env.debugprofilestop, env.CreateFrame = sched_before, profile_before, frame_before
			env.EnumerateFrames = counted
			for index = 1, 300 do env["junk_global_" .. index] = nil end
			env.EnumerateFrames = enumerate
		end
		env.PartyFrame:InitializePartyMemberFrames()
		check("a party member's name uses Manrope", party_member.Name.path == manrope and party_member.PetFrame.Name.path == manrope)
		hooks.DefaultCompactUnitFrameSetup(compact_frame)
		check("a raid-style frame's name uses Manrope", compact_frame.name.path == manrope and compact_frame.name.size == 12)
		env.InCombatLockdown = function() return true end
		addon.module.set("fonts", "enabled", false)
		check("font restoration waits for combat to end", font.path ~= "original.ttf")
		env.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		check("font restoration restores anonymous text regions", region.path == "chat.ttf" and region.size == 10)
		check("font restoration restores size and path after combat",
			font.path == "original.ttf" and font.size == 12 and env.STANDARD_TEXT_FONT == "original.ttf" and env.DAMAGE_TEXT_FONT == "original.ttf")
		check("font restoration puts chat back at the window's size",
			select(1, chat_frame:GetFont()) == "Fonts\\ARIALN.TTF" and select(2, chat_frame:GetFont()) == 16 and chat_font.path == "Fonts\\ARIALN.TTF" and chat_font.size == 14)
		local function game_font(text)
			local path, size = text:GetFont()
			return path == "Fonts\\FRIZQT__.TTF" and size == 10
		end
		check("font restoration puts the game's font back on names and later text",
			game_font(player_name) and game_font(level_text) and game_font(late_text) and game_font(party_member.Name) and game_font(compact_frame.name)
			and nameplate_font.path == "Fonts\\FRIZQT__.TTF" and env.UNIT_NAME_FONT == "Fonts\\FRIZQT__.TTF" and env.UNIT_NAME_FONT_ROMAN == "Fonts\\FRIZQT__.TTF")
		env.GetLocale = function() return "koKR" end
		addon.module.set("fonts", "enabled", true)
		check("Fonts leaves a Korean or Chinese client's fonts, which neither font can draw",
			font.path == "original.ttf" and env.STANDARD_TEXT_FONT == "original.ttf" and select(1, chat_frame:GetFont()) == "Fonts\\ARIALN.TTF")
		addon.module.set("fonts", "enabled", false)
		env.GetLocale = nil
		env.PartyFrame, env.DefaultCompactUnitFrameSetup = nil, nil
	end

	do
		local typography, typography_env, typography_event = load_all()
		local function inherited_font(parent, size, kind)
			local object = { parent = parent, size = size, path = size and "original.ttf" or nil }
			function object:GetObjectType() return kind or "Font" end
			function object:GetFontObject() return self.parent end
			function object:GetFont()
				if self.path then return self.path, self.size, "" end
				return self.parent:GetFont()
			end
			function object:SetFont(path, size) self.path, self.size = path, size end
			function object:SetFontObject(parent)
				self.parent, self.path, self.size = parent, nil, nil
			end
			return object
		end
		local line_base = inherited_font(nil, 12)
		local header_base = inherited_font(nil, 14)
		local line_large = inherited_font(nil, 18)
		local header_large = inherited_font(nil, 20)
		typography_env.ObjectiveTrackerFont12 = line_base
		typography_env.ObjectiveTrackerFont14 = header_base
		typography_env.ObjectiveTrackerFont18 = line_large
		typography_env.ObjectiveTrackerFont20 = header_large
		local line_font = inherited_font(line_base)
		local header_font = inherited_font(header_base)
		typography_env.ObjectiveTrackerLineFont = line_font
		typography_env.ObjectiveTrackerHeaderFont = header_font
		local line_text = inherited_font(line_font, nil, "FontString")
		local header_text = inherited_font(header_font, nil, "FontString")
		local tracker = {
			IsInitialized = function() return true end,
			HasSetting = function() return true end,
			UpdateSystem = function() end,
			UpdateSystemSettingTextSize = function() end,
			GetRegions = function() return line_text, header_text end,
		}
		typography_env.Enum = { EditModeObjectiveTrackerSetting = { TextSize = 4 } }
		typography_env.ObjectiveTrackerFrame = tracker
		typography_env.EnumerateFrames = function(previous) if not previous then return tracker end end
		typography_env.ObjectiveTrackerManager = { SetTextSize = function(_, size)
			line_font:SetFontObject(typography_env["ObjectiveTrackerFont" .. size])
			header_font:SetFontObject(typography_env["ObjectiveTrackerFont" .. (size + 2)])
		end }
		typography.module.set("fonts", "enabled", true)
		typography.module.set("tracker_text_size", "text_size", 18)
		typography.module.set("tracker_text_size", "enabled", true)
		local path, line_size = line_text:GetFont()
		local _, header_size = header_text:GetFont()
		check("Expressway tracker text follows the chosen objective and header sizes", line_size == 18 and header_size == 20 and path:find("expressway.ttf", 1, true))
		typography_event("PLAYER_ENTERING_WORLD")
		local _, refreshed = line_text:GetFont()
		check("Expressway refresh keeps tracker font inheritance", refreshed == 18 and line_text.path == nil)
		typography.module.set("tracker_text_size", "enabled", false)
		local _, restored = line_text:GetFont()
		check("tracker restoration reaches Expressway text regions", restored == 12)
	end
end
