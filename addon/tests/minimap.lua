-- Minimap: the minimap button: where it sits, what a click and the tooltip do.
return function(root, check, lib)
	local source = lib.source
	local minimap_scripts, toggles, tooltip_lines = {}, 0, {}
	local env9 = setmetatable({}, { __index = _G })
	env9._G = env9
	local function widget()
		return setmetatable({}, { __index = function(_, key)
			if key == "SetScript" then return function(_, name, callback) minimap_scripts[name] = callback end end
			if key == "CreateTexture" then return function() return widget() end end
			if key == "GetParent" then return function() return env9.Minimap end end
			-- Only the methods the minimap button calls, each a real widget method; another one is a mistake and fails.
			local known = { ClearAllPoints = true, RegisterForClicks = true, RegisterForDrag = true, SetClampedToScreen = true,
				SetFrameLevel = true, SetFrameStrata = true, SetHighlightTexture = true, SetMovable = true, SetPoint = true,
				SetSize = true, SetTexCoord = true, SetTexture = true, Show = true }
			if not known[key] then error("the widget stand-in has no method " .. tostring(key), 2) end
			return function() end
		end })
	end
	env9.Minimap = { GetWidth = function() return 140 end, GetHeight = function() return 140 end }
	env9.CreateFrame = function() return widget() end
	env9.GameTooltip = { SetOwner = function() end, Show = function() end, Hide = function() end,
		AddLine = function(_, line) tooltip_lines[#tooltip_lines + 1] = line end }
	env9.MenuUtil = { CreateButtonContextMenu = function() error("the minimap icon must not open a menu") end }
	local minimap_load
	env9.EventUtil = { ContinueOnAddOnLoaded = function(_, callback) minimap_load = callback end, ContinueOnPlayerLogin = function() end }
	local minimap_addon = { settings = { toggle = function() toggles = toggles + 1 end } }
	local minimap_chunk = assert(loadfile(source("minimap"))); setfenv(minimap_chunk, env9); minimap_chunk("Everlook", minimap_addon)
	minimap_load()
	local minimap_button = widget()
	minimap_scripts.OnClick(minimap_button, "LeftButton")
	minimap_scripts.OnClick(minimap_button, "RightButton")
	check("clicking the minimap icon toggles the settings page, with either button", toggles == 2)
	minimap_scripts.OnEnter(minimap_button)
	check("the minimap tooltip says what a click does", tooltip_lines[1] == "Everlook" and tooltip_lines[#tooltip_lines]:find("settings", 1, true))
end
