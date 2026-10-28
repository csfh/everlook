-- Radial menu: hold the key over a player, a hostile unit, an object, the ground, or your own character, flick toward an action, and let go.
return function(check, lib)
	local load_all = lib.load_all
	-- Radial wheel: geometry and drawing.
	do
		local radial_addon = load_all()
		local wheel = radial_addon.radial_menu_wheel
		check("the first wedge is straight up", wheel.sector(4, 0, 100) == 1)
		check("wedges run clockwise from the top", wheel.sector(4, 100, 0) == 2 and wheel.sector(4, 0, -100) == 3 and wheel.sector(4, -100, 0) == 4)
		check("a cursor close to the centre chooses nothing", wheel.sector(4, 5, 5) == nil)
		check("a wedge owns the angles around its own direction", wheel.sector(8, 40, 100) == 1 and wheel.sector(8, 60, 100) == 2 and wheel.sector(8, 100, 100) == 2)
		check("the first wedge reaches across the top to the left", wheel.sector(8, -10, 100) == 1 and wheel.sector(8, -60, 100) == 8)
		check("one wedge takes every direction", wheel.sector(1, -50, -50) == 1)
		check("no wedges choose nothing", wheel.sector(0, 0, 100) == nil)
		local x1, y1 = wheel.position(1, 4)
		local x2, y2 = wheel.position(2, 4)
		local x3, y3 = wheel.position(3, 4)
		local x4, y4 = wheel.position(4, 4)
		check("labels sit on the ring in wedge order", math.abs(x1) < 1e-6 and y1 > 0 and x2 > 0 and math.abs(y2) < 1e-6 and math.abs(x3) < 1e-6 and y3 < 0 and x4 < 0 and math.abs(y4) < 1e-6)
		local xa, ya = wheel.position(2, 8)
		check("a label sits along its own direction", xa > 0 and ya > 0 and math.abs(xa / ya - 1) < 1e-6)
	end
	local function drawn_wheel(radial_addon, radial_env)
		if not radial_addon then radial_addon, radial_env = load_all() end
		local made = {}
		local function fake(kind, name)
			local object = { kind = kind, name = name, points = {}, shown = false }
			made[#made + 1] = object
			function object:SetScript(event, fn) self.scripts = self.scripts or {}; self.scripts[event] = fn end
			function object:SetPoint(...) self.points[#self.points + 1] = { ... } end
			function object:ClearAllPoints() self.points = {} end
			function object:Show() self.shown = true end
			function object:Hide() self.shown = false end
			function object:IsShown() return self.shown end
			function object:SetText(text) self.text = text end
			function object:GetStringWidth() return 50 end
			function object:SetSize(width, height) self.width, self.height = width, height end
			function object:SetWidth(width) self.width = width end
			function object:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
			function object:SetTextColor(r, g, b, a) self.text_color = { r, g, b, a } end
			function object:CreateFontString() return fake("fontstring") end
			function object:CreateTexture() return fake("texture") end
			function object:CreateMaskTexture() return fake("mask") end
			for _, method in ipairs({ "SetFrameStrata", "SetFontObject", "EnableMouse", "SetAllPoints", "SetTexture", "AddMaskTexture", "SetJustifyH", "SetVertexColor", "SetAlpha", "SetDrawLayer" }) do
				object[method] = function() end
			end
			return object
		end
		radial_env.CreateFrame = function(_, name) return fake("frame", name) end
		radial_env.UIParent = { GetWidth = function() return 1920 end, GetHeight = function() return 1080 end, GetEffectiveScale = function() return 1 end }
		local cursor = { x = 0, y = 0 }
		radial_env.GetCursorPosition = function() return cursor.x, cursor.y end
		return radial_addon.radial_menu_wheel, radial_env, made, cursor
	end
	do
		local wheel, env_w, made, cursor = drawn_wheel()
		check("the wheel builds nothing until it opens", #made == 0 and not wheel.is_open())
		cursor.x, cursor.y = 960, 540
		wheel.open({ "Attack", "Warning", "On my way" }, 960, 540)
		local root
		for _, object in ipairs(made) do if object.name == "EverlookRadialMenuWheel" then root = object end end
		check("opening shows the wheel", wheel.is_open() and root and root.shown)
		local texts = {}
		for _, object in ipairs(made) do if object.kind == "fontstring" and object.text then texts[#texts + 1] = object.text end end
		check("each wedge is drawn with its text", table.concat(texts, ",") == "Attack,Warning,On my way")
		local point = root.points[#root.points]
		check("the wheel is centred where it opened", point[1] == "CENTER" and point[2] == env_w.UIParent and point[3] == "BOTTOMLEFT" and point[4] == 960 and point[5] == 540)
		check("nothing is chosen before the cursor moves", wheel.selected() == nil)
		cursor.x, cursor.y = 960, 640
		root.scripts.OnUpdate(root, 0.016)
		check("the cursor above the centre chooses the first wedge", wheel.selected() == 1)
		cursor.x, cursor.y = 1060, 440
		root.scripts.OnUpdate(root, 0.016)
		check("the cursor to the lower right chooses the next wedge clockwise", wheel.selected() == 2)
		cursor.x, cursor.y = 960, 545
		root.scripts.OnUpdate(root, 0.016)
		check("moving back to the centre cancels the choice", wheel.selected() == nil)
		cursor.x, cursor.y = 960, 640
		root.scripts.OnUpdate(root, 0.016)
		wheel.close()
		check("closing hides the wheel and forgets the choice", not wheel.is_open() and not root.shown and wheel.selected() == nil)
		local built = #made
		wheel.open({ "Attack", "Warning" }, 960, 540)
		check("a second opening with fewer wedges builds nothing new", #made == built)
		wheel.close()
		wheel.open({ "A" }, 4, 4)
		local clamped = root.points[#root.points]
		check("a wheel opened at the screen edge is moved to fit", clamped[4] > 100 and clamped[5] > 100)
		wheel.close()
		wheel.open({ "A" }, 1919, 1079)
		clamped = root.points[#root.points]
		check("and so is one opened at the opposite corner", clamped[4] < 1819 and clamped[5] < 979)
		wheel.close()
	end

	-- Radial menu: what is under the cursor decides the wheel, and the secure button fires the choice.
	local function radial_fixture(real_wheel)
		local radial_addon, radial_env, event, _, _, frames = load_all()
		local button
		for _, frame in ipairs(frames) do if frame.name == "EverlookRadialMenuButton" then button = frame end end
		local hover = { exists = false, is_self = false, is_player = false, can_attack = false, guid = "Player-1-0A", name = "Thrall", realm = "Orgrimmar",
			in_party = false, in_group = false, in_raid = false, leader = false, assistant = false, over = nil }
		local seen = { calls = {}, closed = 0 }
		local function log(name) return function(...) seen.calls[#seen.calls + 1] = { name = name, ... } end end
		radial_env.UIParent = { GetEffectiveScale = function() return 2 end }
		radial_env.GetCursorPosition = function() return 400, 600 end
		radial_env.GetMouseFoci = function() return { hover.over } end
		radial_env.UnitIsUnit = function(unit, other) return unit == "mouseover" and other == "player" and hover.is_self end
		radial_env.UnitIsPlayer = function() return hover.is_player end
		radial_env.UnitCanAttack = function() return hover.can_attack end
		radial_env.UnitGUID = function(unit)
			if unit == "mouseover" and hover.exists then return hover.mouse_guid or hover.guid end
			if unit == (hover.token or "party1") then return hover.token_guid or hover.guid end
		end
		radial_env.UnitExists = function(unit) return radial_env.UnitGUID(unit) ~= nil end
		radial_env.UnitFullName = function() return hover.name, hover.realm end
		radial_env.UnitTokenFromGUID = function(guid) if guid == hover.guid and not hover.gone then return hover.token or "party1" end end
		radial_env.GetNormalizedRealmName = function() return "Stormrage" end
		-- Blizzard's name helper omits your realm and preserves native surname formatting.
		radial_env.NameUtil = { GetUnmodifiedUnitFullName = function()
			if hover.native_name then return hover.native_name end
			if hover.realm and hover.realm ~= "" and hover.realm ~= "Stormrage" then return hover.name .. "-" .. hover.realm end
			return hover.name
		end }
		radial_env.CanGuildInvite = function() return true end
		radial_env.UnitInParty = function(unit) return unit == "mouseover" and hover.in_party end
		radial_env.UnitInRaid = function() return false end
		radial_env.IsInGroup = function() return hover.in_group end
		radial_env.IsInRaid = function() return hover.in_raid end
		radial_env.UnitIsGroupLeader = function() return hover.leader end
		radial_env.UnitIsGroupAssistant = function() return hover.assistant end
		radial_env.GetRaidTargetIndex = function(unit)
			if unit == "mouseover" or unit == (hover.token or "party1") then return hover.marked end
		end
		radial_env.FollowUnit = log("follow")
		radial_env.FocusUnit = log("focus")
		radial_env.SetRaidTarget = log("mark")
		radial_env.InitiateTrade = log("trade")
		radial_env.InspectUnit = log("inspect")
		radial_env.InitiateRolePoll = log("role_check")
		radial_env.RemoveRaidTargets = log("clear_marks")
		radial_env.ChatFrameUtil = { SendTell = log("whisper") }
		if real_wheel then
			local _, _, made, cursor = drawn_wheel(radial_addon, radial_env)
			seen.cursor = cursor
			cursor.x, cursor.y = 960, 540
			seen.render = function()
				for _, object in ipairs(made) do
					if object.name == "EverlookRadialMenuWheel" then object.scripts.OnUpdate(object, 0.016) end
				end
			end
		else
			radial_addon.radial_menu_wheel.open = function(texts, x, y) seen.opened = { texts = texts, x = x, y = y } end
			radial_addon.radial_menu_wheel.selected = function() return seen.index end
			radial_addon.radial_menu_wheel.close = function() seen.opened = nil; seen.closed = seen.closed + 1 end
		end
		radial_addon.module.set("radial_menu", "enabled", true)
		local function press() button.scripts.PreClick(button, "LeftButton", true); button.scripts.PostClick(button, "LeftButton", true) end
		-- Letting go chooses a wedge by number, or nothing. The macro is read between the two click scripts,
		-- which is when the secure handler would run it.
		local function release(index)
			seen.index = index
			button.scripts.PreClick(button, "LeftButton", false)
			local fired = { type = button.attributes.type, macrotext = button.attributes.macrotext,
				unit = button.attributes.unit, marker = button.attributes.marker, action = button.attributes.action }
			-- Relevant native handlers from Blizzard's SlashCommands and SecureTemplates:
			-- /follow passes its argument to FollowUnit; /tm resolves its conditional unit.
			if fired.macrotext then
				local name = fired.macrotext:match("^/follow (.+)$")
				if name then radial_env.FollowUnit(name) end
				local marker = fired.macrotext:match("^/tm %[@mouseover,exists%] (%d+)$")
				if marker and radial_env.UnitExists("mouseover") then radial_env.SetRaidTarget("mouseover", tonumber(marker)) end
				if fired.macrotext == "/focus [@mouseover,exists]" and radial_env.UnitExists("mouseover") then radial_env.FocusUnit("mouseover") end
			elseif fired.type == "focus" and radial_env.UnitExists(fired.unit) then radial_env.FocusUnit(fired.unit)
			elseif fired.type == "raidtarget" and radial_env.UnitExists(fired.unit) then
				if fired.action == "clear" then radial_env.SetRaidTarget(fired.unit, 0)
				elseif fired.action == "set" and radial_env.GetRaidTargetIndex(fired.unit) ~= fired.marker then radial_env.SetRaidTarget(fired.unit, fired.marker) end
			end
			button.scripts.PostClick(button, "LeftButton", false)
			return fired
		end
		local function words(list) return table.concat(list or {}, ",") end
		return radial_env, hover, seen, radial_addon, button, press, release, words, event
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate1"
		press()
		seen.render()
		hover.exists = false
		seen.cursor.y = 640
		release()
		check("focus follows a flick completed between the last rendered frame and key release",
			#seen.calls == 1 and seen.calls[1].name == "focus" and seen.calls[1][1] == "nameplate1")
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate1"
		press()
		seen.cursor.y = 640
		seen.render()
		seen.cursor.y = 540
		release()
		check("returning to the centre before release cancels a previously highlighted focus", #seen.calls == 0)
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.is_player, hover.realm = true, true, nil
		press()
		seen.render()
		local angle = 2 * math.pi * 6 / 8
		seen.cursor.x, seen.cursor.y = 960 + math.sin(angle) * 100, 540 + math.cos(angle) * 100
		hover.exists = false
		release()
		check("follow also uses the cursor at release instead of the last painted selection",
			#seen.calls == 1 and seen.calls[1].name == "follow" and seen.calls[1][1] == "Thrall")
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture(true)
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate1"
		press()
		seen.render()
		seen.cursor.y = 440
		hover.exists = false
		release()
		check("skull uses the final cursor position when released between frames",
			#seen.calls == 1 and seen.calls[1].name == "mark" and seen.calls[1][1] == "nameplate1" and seen.calls[1][2] == 8)
	end
	do
		local env_r, hover, seen, radial_addon, button, press = radial_fixture()
		check("the radial button is one secure action button", button and button.template == "SecureActionButtonTemplate")
		check("it is clicked on key down and key up", button.clicks and button.clicks[1] == "AnyDown" and button.clicks[2] == "AnyUp")
		check("its action waits for the key to come up", button.attributes.useOnKeyDown == false and button.attributes.type == nil)
		check("it is a live button that no one can see or click", button.mouse == false and button.alpha == 0 and button.shown == true and button.width == 1 and button.height == 1)
		local radial_module
		for _, module in ipairs(radial_addon.module.modules) do
			if module.id == "radial_menu" then radial_module = module end
		end
		check("the page asks for the button's own binding", radial_module and radial_module.keybinding == "CLICK EverlookRadialMenuButton:LeftButton")
		radial_addon.module.set("radial_menu", "enabled", false)
		press()
		check("a disabled module opens nothing", seen.opened == nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		press()
		check("the ground gets the four pings", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		check("the wheel opens at the cursor in interface units", seen.opened.x == 200 and seen.opened.y == 300)
		local fired = release(3)
		check("a ping is a secure macro and nothing else", fired.type == "macro" and fired.macrotext == "/ping 3" and #seen.calls == 0)
		check("the wheel closes and the button is cleared", seen.closed == 1 and button.attributes.type == nil and button.attributes.macrotext == nil)
		press()
		check("letting go on the centre fires nothing", release(nil).type == nil and seen.closed == 2)
		press()
		check("a second press while open is ignored", (function() local before = seen.opened; press(); return seen.opened == before end)())
		release(nil)
		hover.exists = true
		press()
		check("a friendly creature gets the pings too", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		hover.over = {}
		seen.opened = nil
		press()
		check("interface under the cursor opens nothing", seen.opened == nil)
		check("and nothing is waiting to be released", release(1).type == nil)
		env_r.GetMouseFoci = function() return {} end
		hover.exists = false
		press()
		check("no frame under the cursor is the world", seen.opened ~= nil)
		release(nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.is_player = true, true
		press()
		check("a player gets the player wedges", words(seen.opened.texts) == "Trade,Invite,Guild invite,Whisper,Add friend,Inspect,Follow,Duel")
		local function pick(index)
			press()
			return release(index)
		end
		release(nil)
		hover.exists = false
		local names = { [2] = "/invite ", [3] = "/ginvite ", [5] = "/friend ", [8] = "/duel " }
		hover.exists = true
		for index, command in pairs(names) do
			local fired = pick(index)
			check("wedge " .. index .. " is the macro " .. command .. "with the full name", fired.type == "macro" and fired.macrotext == command .. "Thrall-Orgrimmar")
		end
		seen.calls = {}
		check("trade is a call on the unit token", pick(1).type == nil and seen.calls[1].name == "trade" and seen.calls[1][1] == "party1")
		check("whisper opens a tell to the full name", pick(4).type == nil and seen.calls[2].name == "whisper" and seen.calls[2][1] == "Thrall-Orgrimmar")
		check("inspect is a call on the unit token", pick(6).type == nil and seen.calls[3].name == "inspect" and seen.calls[3][1] == "party1")
		hover.realm = nil
		check("a player on your realm gets your realm", pick(2).macrotext == "/invite Thrall-Stormrage")
		hover.realm = "Orgrimmar"
		env_r.CanGuildInvite = function() return false end
		press()
		check("guild invite is left out without the permission", words(seen.opened.texts) == "Trade,Invite,Whisper,Add friend,Inspect,Follow,Duel")
		release(nil)
		env_r.CanGuildInvite = nil
		press()
		check("guild invite is left out when the permission check is missing", words(seen.opened.texts) == "Trade,Invite,Whisper,Add friend,Inspect,Follow,Duel")
		release(nil)
		env_r.CanGuildInvite = function() return true end
		seen.calls = {}
		hover.gone = true
		pick(1); pick(6)
		check("a unit with no token gets no trade or inspect", #seen.calls == 0)
		hover.gone = false
		env_r.InitiateTrade = nil
		check("a missing game function does nothing and raises nothing", pcall(pick, 1) and #seen.calls == 0)
		env_r.InitiateTrade = function() end
		env_r.issecretvalue = function(value) return value == "Thrall" end
		press()
		check("a secret name leaves the wedges that need no name", words(seen.opened.texts) == "Trade,Inspect")
		release(nil)
		env_r.issecretvalue = function(value) return value == "Player-1-0A" end
		press()
		check("a secret guid gives the ground wheel", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		env_r.issecretvalue = nil
		hover.exists = true
		seen.calls = {}
		press()
		env_r.issecretvalue = function(value) return value == "Player-1-0A" end
		check("a guid that turns secret before the key comes up does not trade", release(1).type == nil and #seen.calls == 0)
		env_r.issecretvalue = nil
	end
	do
		local _, hover, seen, _, button, press, release = radial_fixture()
		hover.exists, hover.is_player = true, true
		press()
		hover.exists, hover.name, hover.realm = false, "Other", "OtherRealm"
		release(7)
		check("follow uses the captured full name with the native menu's exact lookup",
			#seen.calls == 1 and seen.calls[1].name == "follow" and seen.calls[1][1] == "Thrall-Orgrimmar" and seen.calls[1][2] == true)
	end
	do
		local _, hover, seen, _, _, press, release = radial_fixture()
		hover.exists, hover.is_player, hover.realm = true, true, nil
		press()
		hover.exists = false
		release(7)
		check("follow does not append your realm to a local player's name", #seen.calls == 1 and seen.calls[1][1] == "Thrall")
		hover.exists, hover.realm = true, "Stormrage"
		press()
		hover.exists = false
		release(7)
		check("follow omits an explicitly returned same realm too", #seen.calls == 2 and seen.calls[2][1] == "Thrall")
		hover.exists, hover.native_name = true, "Thrall-Surname"
		press()
		hover.exists = false
		release(7)
		check("follow preserves the native helper's full name", #seen.calls == 3 and seen.calls[3][1] == "Thrall-Surname")
	end
	do
		local env_r, hover, seen, _, _, press, release, words = radial_fixture()
		hover.exists, hover.is_player = true, true
		env_r.NameUtil = nil
		env_r.GetUnitName = function(unit, show_realm)
			check("the older native name helper receives the captured mouseover", unit == "mouseover" and show_realm == true)
			return "Thrall"
		end
		press()
		hover.exists = false
		release(7)
		check("the older name helper also leaves the local realm off", #seen.calls == 1 and seen.calls[1][1] == "Thrall")
		hover.exists = true
		env_r.GetUnitName = nil
		press()
		check("no name helper leaves follow out", words(seen.opened.texts) == "Trade,Invite,Guild invite,Whisper,Add friend,Inspect,Duel")
		release(nil)
		env_r.NameUtil = { GetUnmodifiedUnitFullName = function() return "secret-name" end }
		env_r.issecretvalue = function(value) return value == "secret-name" end
		press()
		check("a secret native name leaves follow out", words(seen.opened.texts) == "Trade,Invite,Guild invite,Whisper,Add friend,Inspect,Duel")
		release(nil)
	end
	do
		local env_r, hover, seen, _, button, press, release = radial_fixture()
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate7"
		press()
		hover.exists = false
		release(1)
		check("focus reaches the captured enemy after the cursor leaves it", #seen.calls == 1 and seen.calls[1].name == "focus" and seen.calls[1][1] == "nameplate7")
		check("focus attributes are cleared after release", button.attributes.type == nil and button.attributes.unit == nil)
		hover.exists = true
		press()
		hover.mouse_guid = "Creature-other"
		seen.calls = {}
		release(1)
		check("moving onto another enemy keeps focus on the captured one", #seen.calls == 1 and seen.calls[1][1] == "nameplate7")
		hover.mouse_guid = nil
		press()
		hover.token_guid = "Creature-other"
		seen.calls = {}
		check("focus skips a reused unit token", release(1).type == nil and #seen.calls == 0)
	end
	do
		local env_r, hover, seen, _, button, press, release = radial_fixture()
		hover.exists, hover.can_attack, hover.token = true, true, "nameplate7"
		press()
		hover.exists = false
		release(4)
		check("a skull reaches the captured enemy after the cursor leaves it",
			#seen.calls == 1 and seen.calls[1].name == "mark" and seen.calls[1][1] == "nameplate7" and seen.calls[1][2] == 8)
		check("the marker attributes are cleared after release", button.attributes.unit == nil and button.attributes.marker == nil and button.attributes.action == nil)
		seen.calls = {}
		hover.exists, hover.marked = true, 8
		press()
		hover.exists = false
		release(7)
		check("clear mark also reaches the captured enemy", #seen.calls == 1 and seen.calls[1][1] == "nameplate7" and seen.calls[1][2] == 0)
		hover.exists, hover.marked = true, nil
		press()
		hover.mouse_guid = "Creature-other"
		seen.calls = {}
		release(5)
		check("moving onto another enemy still marks the original one", #seen.calls == 1 and seen.calls[1][1] == "nameplate7" and seen.calls[1][2] == 7)
		hover.mouse_guid = nil
		press()
		hover.token_guid = "Creature-other"
		seen.calls = {}
		check("a reused token cannot mark a different enemy", release(4).type == nil and #seen.calls == 0)
		hover.token_guid = nil
		press()
		hover.gone = true
		check("a captured token is kept when GUID lookup stops resolving it", release(6).unit == "nameplate7")
		hover.gone = false
		press()
		local unit_guid = env_r.UnitGUID
		env_r.UnitGUID = function() return nil end
		seen.calls = {}
		check("an enemy with no matching token is skipped", release(4).type == nil and #seen.calls == 0)
		env_r.UnitGUID = unit_guid
		press()
		release(4)
		hover.exists = false
		press()
		check("a later ping has no unit or marker left over", release(1).macrotext == "/ping 1" and button.attributes.unit == nil and button.attributes.marker == nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.is_player, hover.in_party = true, true, true
		press()
		check("a group member gets their own wedges", words(seen.opened.texts) == "Whisper,Trade,Inspect,Follow,Set focus,Assist")
		local focused = release(5)
		check("a group member's focus uses the captured token", focused.type == "focus" and focused.unit == "party1")
		press()
		check("an assist ping is the plain ping macro", release(6).macrotext == "/ping 4")
		press()
		hover.exists = false
		seen.calls = {}
		release(4)
		check("a group member's follow uses the same captured full name", #seen.calls == 1 and seen.calls[1].name == "follow" and seen.calls[1][1] == "Thrall-Orgrimmar" and seen.calls[1][2] == true)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.can_attack = true, true
		press()
		check("a hostile creature gets focus, pings and marks", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square")
		local focused = release(1)
		check("a hostile unit's focus uses the captured token", focused.type == "focus" and focused.unit == "party1")
		press()
		check("attack is the plain ping macro", release(2).macrotext == "/ping 1")
		local marks = { [4] = 8, [5] = 7, [6] = 6 }
		for index, mark in pairs(marks) do
			press()
			local fired = release(index)
			check("wedge " .. index .. " marks the captured unit with " .. mark,
				fired.type == "raidtarget" and fired.unit == "party1" and fired.marker == mark and fired.action == "set")
		end
		hover.marked = 8
		press()
		check("a marked unit offers to clear its mark", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square,Clear mark")
		local cleared = release(7)
		check("clearing is the native clear action on the captured unit", cleared.type == "raidtarget" and cleared.unit == "party1" and cleared.action == "clear")
		hover.marked = nil
		hover.is_player = true
		press()
		check("a hostile player can also be inspected", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square,Inspect")
		seen.calls = {}
		local fired = release(7)
		check("inspect stays a call on the unit token", fired.type == nil and seen.calls[1].name == "inspect" and seen.calls[1][1] == "party1")
		hover.is_player = false
		hover.in_group, hover.in_raid = true, true
		press()
		check("a raid member without lead or assist cannot mark", words(seen.opened.texts) == "Set focus,Attack,Assist")
		release(nil)
		hover.assistant = true
		press()
		check("a raid assistant can mark", words(seen.opened.texts) == "Set focus,Attack,Assist,Skull,Cross,Square")
		release(nil)
	end
	do
		local env_r, hover, seen, _, button, press, release, words = radial_fixture()
		hover.exists, hover.is_self = true, true
		press()
		check("your own character outside a group gets the pings", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		hover.in_group = true
		press()
		check("a member who does not lead gets the pings", words(seen.opened.texts) == "Attack,Warning,On my way,Assist")
		release(nil)
		hover.leader = true
		press()
		check("the leader gets the group tools", words(seen.opened.texts) == "Ready check,Role check,Pull timer,Clear marks")
		check("ready check is a macro", release(1).macrotext == "/readycheck")
		press()
		seen.calls = {}
		check("role check is a call", release(2).type == nil and seen.calls[1].name == "role_check")
		press()
		check("the pull timer is a ten second macro", release(3).macrotext == "/countdown 10")
		press()
		check("clear marks is a call", release(4).type == nil and seen.calls[2].name == "clear_marks")
		hover.leader, hover.assistant = false, true
		press()
		check("an assistant gets the group tools too", #seen.opened.texts == 4)
		release(nil)
	end
	do
		local env_r, hover, seen, radial_addon, button, press, release, words, event = radial_fixture()
		env_r.InCombatLockdown = function() return true end
		press()
		check("in combat nothing opens", seen.opened == nil)
		env_r.InCombatLockdown = function() return false end
		press()
		env_r.InCombatLockdown = function() return true end
		check("a wedge chosen after combat starts fires nothing", release(1).type == nil)
		env_r.InCombatLockdown = function() return false end
		press()
		seen.index = 1
		button.scripts.PreClick(button, "LeftButton", false)
		env_r.InCombatLockdown = function() return true end
		button.scripts.PostClick(button, "LeftButton", false)
		check("a macro left on the button by a fight is kept until the fight ends", button.attributes.type == "macro")
		env_r.InCombatLockdown = function() return false end
		event("PLAYER_REGEN_ENABLED")
		check("and cleared when it ends", button.attributes.type == nil and button.attributes.macrotext == nil)
		press()
		radial_addon.module.set("radial_menu", "enabled", false)
		seen.index = 1
		button.scripts.PreClick(button, "LeftButton", false)
		check("turning the module off mid-press fires nothing but still closes the wheel", button.attributes.type == nil and seen.opened == nil)
	end
end
