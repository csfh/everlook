-- Nameplate titles: nPCs get the same name style as players, with their title under the name.
return function(root, check, lib)
	local load_all = lib.load_all
	do
		-- NPC titles give the nameplate view a subtitle line for a friendly NPC, and keep the game's settings.
		local titles, title_env, title_event, _, _, _, _ = load_all()
		local function made_plate(unit, title_row)
			local name = { justify = "CENTER" }
			function name:GetFont() return "Fonts\\Plate.ttf", 16, "OUTLINE" end
			function name:GetTextColor() return 0.1, 0.9, 0.2 end
			function name:GetJustifyH() return self.justify end
			function name:SetJustifyH(value) self.justify = value end
			local lines = {}
			local frame = { name = name, HealthBarsContainer = {}, IsFriend = function() return true end, IsPlayer = function() return false end,
				IsShowOnlyName = function() return false end, IsSimplified = function() return false end }
			function frame:CreateTexture() return { SetSize = function() end, SetWidth = function() end, SetPoint = function() end, ClearAllPoints = function() end, Show = function() end, Hide = function() end, SetTexture = function() end, SetVertexColor = function() end } end
			function frame:CreateFontString()
				local line = { points = {}, shown = false }
				function line:SetFont(path, size, flags) self.path, self.size, self.flags = path, size, flags end
				function line:SetTextColor(r, g, b) self.color = { r, g, b } end
				function line:ClearAllPoints() self.points = {} end
				function line:SetPoint(...) self.points[#self.points + 1] = { ... } end
				function line:SetText(text) self.text = text end
				function line:SetJustifyH() end
				function line:Show() self.shown = true end
				function line:Hide() self.shown = false end
				lines[#lines + 1] = line
				return line
			end
			return { GetUnit = function() return unit end, UnitFrame = frame }, lines
		end
		local plates, lines = {}, {}
		for _, unit in ipairs({ "nameplate1", "nameplate2", "nameplate3", "nameplate4", "nameplate5" }) do plates[unit], lines[unit] = made_plate(unit) end
		plates.nameplate5.UnitFrame.IsShowOnlyName = function() return true end
		plates.nameplate6, lines.nameplate6 = made_plate("nameplate6")
		local tooltips = {
			nameplate1 = { lines = { { leftText = "Thorgrum Borrelson" }, { leftText = "<Gryphon Master>" } } },
			nameplate2 = { lines = { { leftText = "A Player" }, { leftText = "<Some Guild>" } } },
			nameplate3 = { lines = { { leftText = "A Guard" }, { leftText = "<Defender>" } } },
			nameplate4 = { lines = { { leftText = "Plain Villager" }, { leftText = "Level 3 Human (NPC)" } } },
			nameplate5 = { lines = { { leftText = "Innkeeper Palaena" }, { leftText = "<Drink Vendor>" } } },
			nameplate6 = { lines = { { leftText = "Taldan" }, { leftText = "Drink Vendor" }, { leftText = "Level 16" }, { leftText = "Darnassus" }, { leftText = "PvP" } } },
			nameplate7 = { lines = { { leftText = "Plain Villager" }, { leftText = "Level 16" }, { leftText = "Darnassus" } } },
		}
		title_env.C_NamePlate = { GetNamePlateForUnit = function(unit) return plates[unit] end, GetNamePlates = function() return {} end }
		title_env.C_TooltipInfo = { GetUnit = function(unit) return tooltips[unit] end }
		title_env.UnitExists = function() return true end
		title_env.UnitIsPlayer = function(unit) return unit == "nameplate2" end
		title_env.UnitCanAttack = function(_, unit) return unit == "nameplate3" end
		title_env.UnitIsUnit = function() return false end
		local cvars, set_calls = { nameplateShowFriendlyNpcs = "0", UnitNameNPC = "1", UnitNameFriendlySpecialNPCName = "1" }, {}
		title_env.GetCVar = function(name) return cvars[name] end
		title_env.SetCVar = function(name, value) cvars[name] = value; set_calls[#set_calls + 1] = name end
		title_env.InCombatLockdown = function() return false end
		titles.module.set("nameplates", "enabled", true)
		titles.module.set("nameplate_titles", "use_nameplates", false)
		titles.module.set("nameplate_titles", "enabled", true)
		check("turning the module on without the setting leaves the game's settings alone", #set_calls == 0)
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate1")
		local line = lines.nameplate1[1]
		check("a friendly NPC's title goes in the subtitle line, under its health bar", line and line.shown and line.text == "<Gryphon Master>" and line.points[1][1] == "TOPLEFT")
		check("in the name's face and outline, a little smaller", line.path == "Fonts\\Plate.ttf" and line.size == 13 and line.flags == "OUTLINE")
		check("and in the name's colour", line.color[1] == 0.1 and line.color[2] == 0.9 and line.color[3] == 0.2)
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate2")
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate3")
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate4")
		check("players and NPCs without a title get no line", #lines.nameplate2 == 0 and #lines.nameplate4 == 0)
		check("a hostile NPC's title is shown too", lines.nameplate3[1] and lines.nameplate3[1].shown and lines.nameplate3[1].text == "<Defender>")
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate5")
		local only_name = lines.nameplate5[1]
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate6")
		check("a title the client writes without angle brackets is found by the level line after it", lines.nameplate6[1] and lines.nameplate6[1].shown and lines.nameplate6[1].text == "Drink Vendor")
		plates.nameplate7, lines.nameplate7 = made_plate("nameplate7")
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate7")
		check("a creature whose second line is its level has no title", #lines.nameplate7 == 0)
		check("a plate with only a name gets its NPC's title, centred under it", only_name and only_name.shown and only_name.text == "<Drink Vendor>" and only_name.points[1][1] == "TOP")
		title_event("NAME_PLATE_UNIT_REMOVED", "nameplate1")
		check("the line goes when the nameplate does", line.shown == false)
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate1")
		check("the same line is reused when the nameplate returns", #lines.nameplate1 == 1 and line.shown == true)
		local secret = {}
		title_env.issecretvalue = function(value) return rawequal(value, secret) end
		tooltips.nameplate1 = { lines = { { leftText = "x" }, { leftText = secret } } }
		title_event("NAME_PLATE_UNIT_ADDED", "nameplate1")
		check("a secret title is skipped", line.shown == false)
		title_env.issecretvalue = nil
		titles.module.set("nameplate_titles", "use_nameplates", true)
		check("the setting turns friendly NPC nameplates on and the game's NPC names off",
			cvars.nameplateShowFriendlyNpcs == "1" and cvars.UnitNameNPC == "0" and cvars.UnitNameFriendlySpecialNPCName == "0")
		titles.module.set("nameplate_titles", "enabled", false)
		check("turning the module off puts the game's settings back",
			cvars.nameplateShowFriendlyNpcs == "0" and cvars.UnitNameNPC == "1" and cvars.UnitNameFriendlySpecialNPCName == "1")
		title_env.InCombatLockdown = function() return true end
		titles.module.set("nameplate_titles", "enabled", true)
		check("combat leaves the game's settings alone", cvars.UnitNameNPC == "1")
		-- Options' NPC Names dropdown writes the two name settings together (Blizzard_SettingsDefinitions_Frame/
		-- Nameplates.lua:362-385 at 12.0.0): "All NPCs" is NPC 1 and special 0, "Friendly special" is NPC 0 and special 1.
		local function dropdown(npc, special) cvars.UnitNameNPC, cvars.UnitNameFriendlySpecialNPCName = npc, special end
		title_env.InCombatLockdown = function() return false end
		titles.module.set("nameplate_titles", "enabled", false)
		dropdown("1", "0")
		titles.module.set("nameplate_titles", "enabled", true)
		dropdown("0", "1")
		titles.module.set("nameplate_titles", "enabled", false)
		check("a dropdown pick made meanwhile is kept whole when the module lets go",
			cvars.UnitNameNPC == "0" and cvars.UnitNameFriendlySpecialNPCName == "1" and cvars.nameplateShowFriendlyNpcs == "0")
		dropdown("1", "0")
		titles.module.set("nameplate_titles", "enabled", true)
		dropdown("0", "1")
		title_event("PLAYER_REGEN_ENABLED")
		check("after combat the module sets its own values again", cvars.UnitNameNPC == "0" and cvars.UnitNameFriendlySpecialNPCName == "0")
		titles.module.set("nameplate_titles", "enabled", false)
		check("and the dropdown pick from before that comes back whole when it lets go",
			cvars.UnitNameNPC == "0" and cvars.UnitNameFriendlySpecialNPCName == "1")
	end
end
