-- Tooltip cursor: when the game places its default tooltip, this moves that tooltip just off the mouse cursor, so the pointer stays visible, and it follows the cursor.
return function(check, lib)
	local load_all = lib.load_all
	local cursor, cursor_env, _, cursor_hooks = load_all()
	local owned = {}
	cursor_env.GameTooltip = { SetOwner = function(self, owner, anchor, x, y) owned[#owned + 1] = { self = self, owner = owner, anchor = anchor, x = x, y = y } end }
	cursor_env.GameTooltip_SetDefaultAnchor = function() end
	cursor.module.set("tooltip_cursor", "enabled", true)
	local default_anchor = cursor_hooks.GameTooltip_SetDefaultAnchor
	check("the cursor module hooks the default tooltip anchor", type(default_anchor) == "function")
	local parent = {}
	default_anchor(cursor_env.GameTooltip, parent)
	check("an enabled module follows the tooltip to the cursor", #owned == 1 and owned[1].owner == parent and owned[1].anchor == "ANCHOR_CURSOR" and owned[1].x == 16 and owned[1].y == 16)
	default_anchor({ SetOwner = function() error("another tooltip must stay where the game put it") end }, parent)
	cursor.module.set("tooltip_cursor", "enabled", true)
	check("enabling twice hooks the anchor once", cursor_hooks.GameTooltip_SetDefaultAnchor == default_anchor)
	cursor.module.set("tooltip_cursor", "enabled", false)
	default_anchor(cursor_env.GameTooltip, parent)
	check("a disabled module leaves the tooltip where the game put it", #owned == 1)
	local bare, bare_env, _, bare_hooks = load_all()
	bare_env.hooksecurefunc = nil
	bare_env.GameTooltip = { SetOwner = function() error("without the hook there is nothing to move") end }
	bare.module.set("tooltip_cursor", "enabled", true)
	check("without hooksecurefunc the module does nothing", next(bare_hooks) == nil)
	local missing, missing_env, _, missing_hooks = load_all()
	missing_env.GameTooltip_SetDefaultAnchor = nil
	missing.module.set("tooltip_cursor", "enabled", true)
	check("without the default anchor call the module does nothing", missing_hooks.GameTooltip_SetDefaultAnchor == nil)
end
