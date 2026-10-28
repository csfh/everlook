-- Resolves the anchors that the fake frames record into rectangles, so a test
-- can check where things land and not only which anchor was set. It reads the
-- same anchor rules the game does for the cases the island uses: a point, a
-- relative region and point, an offset, two-sided anchors that give a size, and
-- SetAllPoints. Text takes the width and height the fake reports.
--
-- Rectangles are in screen units with y growing downward, so `top` is the
-- distance from the top of the screen.
local layout = {}

local SCREEN = { left = 0, top = 0, width = 1920, height = 1080 }

local function across(point)
	if point:find("LEFT", 1, true) then return 0 end
	if point:find("RIGHT", 1, true) then return 1 end
	return 0.5
end

local function down(point)
	if point:find("TOP", 1, true) then return 0 end
	if point:find("BOTTOM", 1, true) then return 1 end
	return 0.5
end

local function parse(point)
	local relative, relative_point, x, y
	local index = 2
	if type(point[index]) == "table" then relative, index = point[index], index + 1 end
	if type(point[index]) == "string" then relative_point, index = point[index], index + 1 end
	x, y = tonumber(point[index]) or 0, tonumber(point[index + 1]) or 0
	return { name = point[1], relative = relative, relative_point = relative_point or point[1], x = x, y = y }
end

local function rectangle(left, top, width, height)
	return { left = left, top = top, width = width, height = height, right = left + width, bottom = top + height }
end

function layout.new()
	local resolved, active = {}, {}
	local resolve

	local function natural(region)
		-- A width or height of 0 on text means "as large as the text".
		local width, height = region.width, region.height
		if (width == nil or width == 0) and region.GetStringWidth then width = region:GetStringWidth() end
		if (height == nil or height == 0) and region.GetStringHeight then height = region:GetStringHeight() end
		return width, height
	end

	local function anchor_rectangle(region, relative)
		if relative == nil or relative == true then relative = region.parent end
		if relative == nil or relative == region then return SCREEN end
		if type(relative) ~= "table" or (relative.points == nil and relative.all_points == nil and relative.width == nil and relative.parent == nil) then
			return SCREEN
		end
		return resolve(relative)
	end

	resolve = function(region)
		if resolved[region] then return resolved[region] end
		if active[region] then error("anchor cycle at " .. tostring(region.name or region.text)) end
		active[region] = true
		local rect
		if region.all_points then
			local target = region.all_points
			local box = anchor_rectangle(region, target)
			rect = rectangle(box.left, box.top, box.width, box.height)
		else
			local width, height = natural(region)
			local points = {}
			for _, raw in ipairs(region.points or {}) do points[#points + 1] = parse(raw) end
			local left_edge, right_edge, top_edge, bottom_edge
			for _, point in ipairs(points) do
				local box = anchor_rectangle(region, point.relative)
				local anchor_x = box.left + across(point.relative_point) * box.width + point.x
				local anchor_y = box.top + down(point.relative_point) * box.height - point.y
				if point.name:find("LEFT", 1, true) then left_edge = left_edge or anchor_x end
				if point.name:find("RIGHT", 1, true) then right_edge = right_edge or anchor_x end
				if point.name:find("TOP", 1, true) then top_edge = top_edge or anchor_y end
				if point.name:find("BOTTOM", 1, true) then bottom_edge = bottom_edge or anchor_y end
				point.x_anchor, point.y_anchor = anchor_x, anchor_y
			end
			if left_edge and right_edge then width = right_edge - left_edge end
			if top_edge and bottom_edge then height = bottom_edge - top_edge end
			width, height = width or 0, height or 0
			local first = points[1]
			local left, top = 0, 0
			if first then
				left = left_edge or (right_edge and right_edge - width) or (first.x_anchor - across(first.name) * width)
				top = top_edge or (bottom_edge and bottom_edge - height) or (first.y_anchor - down(first.name) * height)
			end
			rect = rectangle(left, top, width, height)
		end
		active[region], resolved[region] = nil, rect
		return rect
	end

	return { rectangle = resolve }
end

-- The fake frames cannot play an animation, so this plays every one to its end:
-- each animation reports full progress, then every frame's OnUpdate runs and
-- each group's OnFinished fires. What the island sized or faded is then final.
function layout.settle(frames)
	for _ = 1, 3 do
		for _, frame in ipairs(frames) do
			for _, group in ipairs(frame.animation_groups or {}) do
				for _, animation in ipairs(group.animations) do animation.progress = 1 end
			end
		end
		for _, frame in ipairs(frames) do
			if frame.scripts and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, 1) end
		end
	end
	for _, frame in ipairs(frames) do
		for _, group in ipairs(frame.animation_groups or {}) do
			if group.scripts and group.scripts.OnFinished then group.scripts.OnFinished(group) end
		end
	end
end

-- A frame is shown when it and every ancestor is not hidden.
local function visible(region)
	while region do
		if region.shown == false then return false end
		region = region.parent
	end
	return true
end

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

-- Every frame that takes the mouse at a point, the one that gets it first: a shown frame with the mouse
-- enabled, whose rectangle (as its hit insets leave it) holds the point and that no clipping ancestor has
-- cut off there. Higher strata go first, then higher levels, then later creation. Alpha does not matter:
-- a faded frame still takes the mouse. A frame with the mouse off is never in the list.
function layout.hits(frames, x, y)
	local measure = layout.new()
	local function holds(frame)
		local rect = measure.rectangle(frame)
		local inset = frame.hit_insets or {}
		-- A positive inset pulls the edge in, a negative one pushes it out, as SetHitRectInsets does.
		local left, right, top, bottom = rect.left + (inset[1] or 0), rect.right - (inset[2] or 0), rect.top + (inset[3] or 0), rect.bottom - (inset[4] or 0)
		return rect.width > 0 and rect.height > 0 and x >= left and x < right and y >= top and y < bottom
	end
	local found = {}
	for _, frame in ipairs(frames) do
		if frame.mouse == true and visible(frame) and holds(frame) then
			local cut, walker = false, frame.parent
			while walker do
				if (walker.clips or walker.scroll_child) and not holds(walker) then cut = true end
				walker = walker.parent
			end
			if not cut then found[#found + 1] = frame end
		end
	end
	-- A frame that clips has everything under it ordered as one unit, at its own strata and level. Inside the unit
	-- the frames keep their own levels. Against a frame outside it at the same level, an ancestor wins. (Read in
	-- the client: the island and its clipping panel were both level 50, and the island took the mouse from every
	-- button in the panel until the panel was raised one level.)
	local function group_of(frame)
		local group = frame.clips and frame or nil
		local walker = frame.parent
		while walker do
			if walker.clips then group = walker end
			walker = walker.parent
		end
		return group
	end
	local function ancestor(first, second)
		local walker = second.parent
		while walker do
			if walker == first then return true end
			walker = walker.parent
		end
		return false
	end
	table.sort(found, function(a, b)
		if a.strata ~= b.strata then return (STRATA[a.strata] or 3) > (STRATA[b.strata] or 3) end
		local group_a, group_b = group_of(a), group_of(b)
		local level_a, level_b = group_a and group_a.level or a.level, group_b and group_b.level or b.level
		if level_a ~= level_b then return level_a > level_b end
		if group_a and group_a == group_b then
			if a.level ~= b.level then return a.level > b.level end
			return (a.order or 0) > (b.order or 0)
		end
		if ancestor(a, b) then return true end
		if ancestor(b, a) then return false end
		if a.level ~= b.level then return a.level > b.level end
		return (a.order or 0) > (b.order or 0)
	end)
	return found
end

-- The frame that gets the mouse at a point, or nil.
function layout.hit(frames, x, y)
	return layout.hits(frames, x, y)[1]
end

-- The middle of a frame, where a person would press it.
function layout.center(frame)
	local rect = layout.new().rectangle(frame)
	return rect.left + rect.width / 2, rect.top + rect.height / 2
end

local function children(frame)
	local list = {}
	for _, region in ipairs(frame.regions or {}) do list[#list + 1] = region end
	return list
end

-- Walks every shown region under `frames` (a list of frames) and reports the
-- breaks of the layout rules that do not need a picture to see: a part outside
-- the frame that holds it, and two pieces of text that overlap.
function layout.lint(frames, options)
	options = options or {}
	local measure = layout.new()
	local found = {}
	local function label(region)
		return tostring(region.name or region.text or region.atlas or region.path or "region")
	end
	for _, frame in ipairs(frames) do
		if visible(frame) then
			local box = measure.rectangle(frame)
			local texts = {}
			for _, region in ipairs(children(frame)) do
				-- Text with nothing to draw takes no room, so it cannot break a rule.
				if visible(region) and not (region.GetStringWidth and (region.text or "") == "") then
					local rect = measure.rectangle(region)
					local inside = rect.left >= box.left - 0.5 and rect.right <= box.right + 0.5
						and rect.top >= box.top - 0.5 and rect.bottom <= box.bottom + 0.5
					if not inside and not frame.clips and not (options.skip and options.skip(frame, region)) then
						found[#found + 1] = string.format("%s leaves %s: [%g..%g, %g..%g] outside [%g..%g, %g..%g]", label(region), label(frame),
							rect.left, rect.right, rect.top, rect.bottom, box.left, box.right, box.top, box.bottom)
					end
					if region.GetStringWidth and (region.text or "") ~= "" then texts[#texts + 1] = { region = region, rect = rect } end
				end
			end
			for first = 1, #texts do
				for second = first + 1, #texts do
					local a, b = texts[first].rect, texts[second].rect
					local overlap = math.min(a.right, b.right) - math.max(a.left, b.left) > 0.5
						and math.min(a.bottom, b.bottom) - math.max(a.top, b.top) > 0.5
					if overlap then
						found[#found + 1] = string.format("%q overlaps %q in %s", texts[first].region.text, texts[second].region.text, label(frame))
					end
				end
			end
		end
	end
	return found
end

return layout
