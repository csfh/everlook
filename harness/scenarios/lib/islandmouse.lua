-- The diagnostic the addon carried while the open island's buttons did not answer (removed from the addon once
-- they did). The harness keeps it so the failure can still be reproduced: scenarios/island_dead_buttons.lua runs
-- it and its experiments the way the client did. It reads the island through its public view and its frames.
local function call(object, method, ...)
	local fn = object and object[method]
	if type(fn) == "function" then return fn(object, ...) end
end
local island = { view = function() return Everlook.smart_island.view() end }

-- /islandmouse: what the game says is under the pointer, for when a control does not answer. Hover the
-- control within three seconds of typing it. "/islandmouse click" presses the Clear history link without
-- the mouse, which tells a covered link from one whose click does nothing.
SLASH_EVERLOOKISLANDMOUSE1 = "/islandmouse"
SlashCmdList = SlashCmdList or {}
SlashCmdList.EVERLOOKISLANDMOUSE = function(argument)
	-- A missing method gives no value at all, which tostring refuses, and a restricted frame raises an error
	-- when it is measured, so every read goes through here.
	local function str(...) return tostring((...)) end
	local function try(target, method, ...)
		if type(target) ~= "table" or type(target[method]) ~= "function" then return nil end
		local results = { pcall(target[method], target, ...) }
		if not results[1] then return nil end
		return unpack(results, 2)
	end
	local function rect_of(target)
		local left, bottom, width, height = try(target, "GetRect")
		if type(left) ~= "number" then return "no rect" end
		return string.format("%d,%d %dx%d", left, bottom, width, height)
	end
	local function name_of(target)
		return str(try(target, "GetDebugName") or try(target, "GetName") or try(target, "GetObjectType") or "?")
	end
	local function describe(target)
		if not target then return "nothing" end
		return name_of(target) .. " L" .. str(try(target, "GetFrameLevel")) .. " " .. str(try(target, "GetFrameStrata"))
			.. " click=" .. str(try(target, "IsMouseClickEnabled")) .. " motion=" .. str(try(target, "IsMouseMotionEnabled"))
			.. " visible=" .. str(try(target, "IsVisible")) .. " alpha=" .. str(try(target, "GetEffectiveAlpha"))
			.. " over=" .. str(try(target, "IsMouseOver")) .. " scale=" .. str(try(target, "GetEffectiveScale"))
			.. " clips=" .. str(try(target, "DoesClipChildren")) .. " flat=" .. str(try(target, "GetEffectivelyFlattensRenderLayers"))
			.. " rect " .. rect_of(target)
	end
	local link = _G.EverlookIslandClearHistory
	-- One change at a time, for the three seconds it takes to put the pointer on a button, then put back.
	-- "noclip" stops the open panel clipping what is in it, "mouse" lets the panel take the mouse itself, and
	-- "noroot" takes the mouse from the island's own frame. What each does to what gets the mouse tells which
	-- of them is in the way.
	local named = (argument or ""):lower():match("^%s*(%a*)") or ""
	local was_level
	local experiments = {
		noclip = { apply = function() call(_G.EverlookIslandExpanded, "SetClipsChildren", false) end, restore = function() call(_G.EverlookIslandExpanded, "SetClipsChildren", true) end },
		mouse = { apply = function() call(_G.EverlookIslandExpanded, "EnableMouse", true) end, restore = function() call(_G.EverlookIslandExpanded, "EnableMouse", false) end },
		noroot = { apply = function() call(_G.EverlookSmartIsland, "EnableMouse", false) end, restore = function() call(_G.EverlookSmartIsland, "EnableMouse", true) end },
		-- The panel and the island's own frame are both level 50. "raise" puts the panel one level above it.
		raise = { apply = function() was_level = call(_G.EverlookIslandExpanded, "GetFrameLevel") or 51; call(_G.EverlookIslandExpanded, "SetFrameLevel", was_level + 1) end, restore = function() call(_G.EverlookIslandExpanded, "SetFrameLevel", was_level or 51) end },
	}
	local experiment = experiments[named]
	local label = experiment and named or "plain"
	if argument and argument:lower():find("click", 1, true) then
		print("Everlook island: pressing Clear history", describe(link))
		call(link, "Click")
		return
	end
	local read = island.view()
	local lines = {}
	local function say(text) lines[#lines + 1] = text end
	say("experiment: " .. label)
	say("mode " .. tostring(read.mode) .. ", pinned " .. tostring(read.pinned) .. ", shell " .. tostring(read.shell and read.shell.width) .. " x " .. tostring(read.shell and read.shell.height))
	say("Clear history is " .. describe(link))
	if experiment then experiment.apply() end
	print("Everlook island: " .. label .. ": hover the control now")
	local function report()
		local foci = _G.GetMouseFoci and _G.GetMouseFoci() or { _G.GetMouseFocus and _G.GetMouseFocus() or nil }
		if #foci == 0 then say("the pointer is over nothing") end
		for index = 1, math.min(#foci, 4) do say("GETS THE MOUSE " .. index .. ": " .. describe(foci[index])) end
		say("hit insets of the island: " .. str(try(_G.EverlookSmartIsland, "GetHitRectInsets")))
		-- Every mouse-enabled island frame whose area holds the pointer, wherever it ranks. The walk goes down the
		-- island's own tree, so no frame of Blizzard's, restricted ones included, is ever measured.
		say("the panel layer: " .. describe(_G.EverlookIslandExpanded))
		local held = {}
		local function visit(node, depth)
			if try(node, "IsMouseEnabled") and try(node, "IsMouseOver") then held[#held + 1] = node end
			if depth < 10 then
				for _, child in ipairs({ try(node, "GetChildren") }) do visit(child, depth + 1) end
			end
		end
		if _G.EverlookSmartIsland then visit(_G.EverlookSmartIsland, 0) end
		table.sort(held, function(left, right) return (try(left, "GetFrameLevel") or 0) > (try(right, "GetFrameLevel") or 0) end)
		say(#held .. " island frames hold the pointer, highest level first")
		for _, held_frame in ipairs(held) do say("INSIDE " .. describe(held_frame)) end
		-- The ancestors of the highest one, which is the button the pointer is on.
		local walker = held[1] and try(held[1], "GetParent")
		local depth = 0
		while walker and depth < 8 do
			say("ABOVE " .. describe(walker) .. " hit insets " .. str(try(walker, "GetHitRectInsets")))
			walker = try(walker, "GetParent")
			depth = depth + 1
		end
		if experiment then experiment.restore() end
		EverlookDB = EverlookDB or {}
		EverlookDB.island_mouse = type(EverlookDB.island_mouse) == "table" and EverlookDB.island_mouse or {}
		EverlookDB.island_mouse[label] = { when = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = lines }
		print("Everlook island: report of " .. #lines .. " lines saved; type /reload to write it to disk")
		for index = 1, math.min(#lines, 6) do print("Everlook island: " .. lines[index]) end
	end
	if C_Timer and C_Timer.After then C_Timer.After(3, report) else report() end
end

