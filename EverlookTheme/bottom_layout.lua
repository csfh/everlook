-- The bottom bars as one block, through the game's own Edit Mode, top to bottom: Action Bar 4 and 5,
-- Action Bar 2 and 3, the main bar, micro menu and bags, and the experience bar along the screen's
-- bottom edge, all with the same left and right edges, one gap between everything, and square
-- buttons of one size. Bars 4 and 5 show only when the player turns them on under Settings, Action
-- Bars; this never changes that. No frame is moved by this
-- addon. It keeps a character layout named Everlook, a copy of the layout in use with only the
-- bottom systems changed, and switches to it; the game places the frames from it.
--
-- The way in and out is the old ActionBarSlots module's (commit 2decb4c): C_EditMode as plain data,
-- out of combat and with Edit Mode closed, OnLayoutAdded for a new layout and SetActiveLayout for
-- an existing one. Turned off, it switches to the game's default layout, and only when the player
-- is still on Everlook's.
local _, ns = ...
local Theme = ns.Theme
local KEY = "bottomLayout"

local Layout = { NAME = "Everlook" }
Theme.BottomLayout = Layout

-- The one gap: inside the bars, between the main bar, micro menu and bags, between the rows, and
-- under the experience bar.
Theme.GAP = 4

-- One square size for action buttons and bags (user's call, 2026-11-06): 80%, where IconSize's 10%
-- steps and the bags' 5% steps meet. The action button is 45 units at 100% (ActionButtonTemplate.xml),
-- and so are the bag slots (Camelot/MainMenuBarBagButtons.xml).
local PERCENT = 80
local BUTTON = 45 * PERCENT / 100
local BUTTONS = 12
-- The status bars' full width at Size 100% (STATUS_BAR_CONTAINER_WIDTH, Camelot
-- StatusTrackingBarConstants.lua, forever 1.60.1).
local STATUS_WIDTH = 1192

-- How Edit Mode stores a size (EditModeSettingDisplayInfo.lua, ConvertValueDefault): as an index,
-- shown value = min + index * step. Paddings have no conversion and are stored as units.
local SIZES = {
	icon = { min = 50, step = 10 },
	micro = { min = 70, step = 5, max = 200 },
	bags = { min = 75, step = 5 },
	status = { min = 50, step = 5, max = 130 },
}
local function sizeIndex(kind, percent)
	local size = SIZES[kind]
	return (percent - size.min) / size.step
end

-- The bags' padding in their own units, so that scaled it is about GAP on screen.
function Layout.BagPadding()
	return math.floor(Theme.GAP / (PERCENT / 100) + 0.5)
end

-- An action bar's IconPadding for `units` on screen. IconSize scales each button's container
-- (EditModeActionBarSystemMixin:UpdateSystemSettingIconSize) and the grid spaces the containers
-- IconPadding apart in their own scaled units, so on screen it is IconPadding times the icon scale:
-- at 80% a stored 4 shows as 3.2 (measured in game, 2026-11-06).
function Layout.BarPadding(units)
	return math.floor(units / (PERCENT / 100) + 0.5)
end
local function onScreen(padding) return padding * PERCENT / 100 end

------------------------------------------------------------------------------------------------
-- The numbers, from the frames' own sizes. `geometry` is what measure() reads:
--   microCenters  each shown micro button's center, in the micro menu's own units, from its left
--   microHeight   the micro menu's height in its own units
--   bagWidths     each shown bag button's width at 100%, right to left as the bar lays them out
--   statusHeight  the status bar's height

-- The best micro menu size and bar 2/3 padding for both rows to share their edges. The micro
-- tiles' centres are the buttons', so a tile and the gap after it always add up to one button step;
-- what the 5% size steps leave over is shared between the gaps between the tiles and the two gaps
-- around them, a third each way, so each stays close to GAP. The user chose a tight top row and a
-- slim micro menu (2026-11-06): bars 2 and 3 get no more padding than GAP and the micro menu no more
-- than its 100%, unless nothing fits that way.
local function search(geometry, maxPadding, maxPercent)
	local gap = Theme.GAP
	local centers = geometry.microCenters
	local count = #centers
	if count < 2 then return nil end
	local step = (centers[count] - centers[1]) / (count - 1)
	-- The bags' Size scales the whole bar, its padding too.
	local bagScale = PERCENT / 100
	local bags = (#geometry.bagWidths - 1) * Layout.BagPadding() * bagScale
	for _, width in ipairs(geometry.bagWidths) do bags = bags + width * bagScale end
	local main = BUTTONS * BUTTON + (BUTTONS - 1) * onScreen(Layout.BarPadding(gap))

	local best
	for padding = 2, maxPadding do
		local top = BUTTONS * BUTTON + (BUTTONS - 1) * onScreen(padding)
		local width = 2 * top + gap
		for percent = SIZES.micro.min, maxPercent, SIZES.micro.step do
			local scale = percent / 100
			-- With a gap g between tiles, the two outer gaps are (extra + g) / 2.
			local extra = width - main - bags - count * step * scale
			local miss = (extra - gap) / 3
			local microGap = gap - miss
			local outerGap = gap + miss
			local tile = step * scale - microGap
			if tile > 0 and outerGap > 0 and microGap > 0 then
				local cost = math.abs(miss) + math.abs(percent - 100) / 10000 + math.abs(padding - gap) / 10000
				if not best or cost < best.cost then
					best = { cost = cost, padding = padding, percent = percent, scale = scale, width = width,
						tile = tile, microGap = microGap, outerGap = outerGap, main = main, top = top, bags = bags,
						barGap = onScreen(padding),
						step = step }
				end
			end
		end
	end
	return best
end

function Layout.Plan(geometry)
	if #geometry.microCenters < 2 then return nil end
	local best = search(geometry, Layout.BarPadding(Theme.GAP), 100) or search(geometry, 10, SIZES.micro.max)
	if not best then return nil end
	local gap, centers = Theme.GAP, geometry.microCenters
	local main = best.main

	local half = best.width / 2
	local row = gap + geometry.statusHeight + gap
	local above = row + BUTTON + gap
	local top = above + BUTTON + gap
	-- The micro menu sits so its first tile starts one outer gap after the main bar.
	local firstTile = -half + main + best.outerGap
	best.microX = firstTile + best.tile / 2 - centers[1] * best.scale
	best.microY = row + (BUTTON - geometry.microHeight * best.scale) / 2
	best.row, best.above, best.top, best.half = row, above, top, half
	best.button = BUTTON
	best.statusPercent = math.max(SIZES.status.min, math.min(SIZES.status.max,
		SIZES.status.min + SIZES.status.step * math.floor((best.width / STATUS_WIDTH * 100 - SIZES.status.min) / SIZES.status.step + 0.5)))
	return best
end

------------------------------------------------------------------------------------------------
-- The layout as data. A system is { system, systemIndex, anchorInfo, settings = { { setting,
-- value } }, isInDefaultPosition } (EditModePresetLayoutSystemUtils.lua).

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, inner in pairs(value) do result[key] = copy(inner) end
	return result
end

local function systemOf(layout, system, index)
	for _, item in ipairs(layout.systems or {}) do
		if item.system == system and item.systemIndex == index then return item end
	end
end

-- Sets one setting; true when it changed.
local function set(item, setting, value)
	item.settings = item.settings or {}
	for _, row in ipairs(item.settings) do
		if row.setting == setting then
			if row.value == value then return false end
			row.value = value
			return true
		end
	end
	item.settings[#item.settings + 1] = { setting = setting, value = value }
	return true
end

-- The game may hand offsets back rounded, so a tenth of a unit counts as the same place.
local function near(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 0.1 end

-- Puts a system at a point of UIParent's bottom edge, out of the default position; true when it changed.
local function place(item, point, x, y)
	local anchor = item.anchorInfo or {}
	local same = item.isInDefaultPosition == false and anchor.point == point and anchor.relativeTo == "UIParent"
		and anchor.relativePoint == "BOTTOM" and near(anchor.offsetX, x) and near(anchor.offsetY, y)
		and (item.anchorInfo2 == nil or next(item.anchorInfo2) == nil)
	if same then return false end
	item.anchorInfo = { point = point, relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = x, offsetY = y }
	item.anchorInfo2 = nil
	item.isInDefaultPosition = false
	return true
end

-- Writes the plan into a layout's bottom systems; true when anything changed. A system the
-- layout lacks is left out.
function Layout.Write(layout, plan, c)
	local changed = false
	local function mark(value) changed = changed or value end
	local gap, half = Theme.GAP, plan.half
	local bars, setting = c.barIndex, c.barSetting

	local function bar(index, padding)
		local item = systemOf(layout, c.actionBar, index)
		if not item then return end
		mark(set(item, setting.IconSize, sizeIndex("icon", PERCENT)))
		if c.horizontal and setting.Orientation then mark(set(item, setting.Orientation, c.horizontal)) end
		mark(set(item, setting.IconPadding, padding))
		mark(set(item, setting.NumRows, 1))
		mark(set(item, setting.NumIcons, BUTTONS))
		return item
	end
	local main = bar(bars.MainBar, Layout.BarPadding(gap))
	if main then mark(place(main, "BOTTOMLEFT", -half, plan.row)) end
	local second = bar(bars.Bar2, plan.padding)
	if second then mark(place(second, "BOTTOMLEFT", -half, plan.above)) end
	local third = bar(bars.Bar3, plan.padding)
	if third then mark(place(third, "BOTTOMRIGHT", half, plan.above)) end
	-- Action Bar 4 and 5 (RightBar1 and 2), turned to rows, on top.
	local fourth = bar(bars.RightBar1, plan.padding)
	if fourth then mark(place(fourth, "BOTTOMLEFT", -half, plan.top)) end
	local fifth = bar(bars.RightBar2, plan.padding)
	if fifth then mark(place(fifth, "BOTTOMRIGHT", half, plan.top)) end
	-- The game stacks these on whatever bottom bar is still in the default position, which would
	-- be the rows above now (UpdateBottomActionBarPositions), so they get a place above the block.
	local higher = plan.top + BUTTON + gap
	for _, index in ipairs({ bars.StanceBar, bars.PossessActionBar }) do
		local item = systemOf(layout, c.actionBar, index)
		if item then mark(place(item, "BOTTOMLEFT", -half, higher)) end
	end
	local pet = systemOf(layout, c.actionBar, bars.PetActionBar)
	if pet then mark(place(pet, "BOTTOMRIGHT", half, higher)) end
	local vehicle = systemOf(layout, c.vehicle, nil)
	if vehicle then mark(place(vehicle, "BOTTOM", 0, higher)) end
	-- The totem bar (MultiCastActionBarFrame) is in the same stack (Camelot EditModeUtil.lua).
	local totems = c.totems and systemOf(layout, c.totems, nil)
	if totems then mark(place(totems, "BOTTOMLEFT", -half, higher)) end

	local micro = systemOf(layout, c.microMenu, nil)
	if micro then
		mark(set(micro, c.microSetting.Size, sizeIndex("micro", plan.percent)))
		mark(place(micro, "BOTTOMLEFT", plan.microX, plan.microY))
	end
	local bags = systemOf(layout, c.bags, nil)
	if bags then
		mark(set(bags, c.bagsSetting.Size, sizeIndex("bags", PERCENT)))
		mark(set(bags, c.bagsSetting.BagSlotPadding, Layout.BagPadding()))
		mark(place(bags, "BOTTOMRIGHT", half, plan.row))
	end
	-- Both status bars on the same spot along the bottom: the game puts the highest-priority bar
	-- in the main container (StatusTrackingManager:UpdateBarsShown), so a watched reputation takes
	-- the experience bar's place, and status_bars.lua draws only the main one.
	for _, index in ipairs({ c.statusIndex.StatusTrackingBar1, c.statusIndex.StatusTrackingBar2 }) do
		local item = systemOf(layout, c.status, index)
		if item then
			mark(set(item, c.statusSetting.Size, sizeIndex("status", plan.statusPercent)))
			mark(place(item, "BOTTOM", 0, gap))
		end
	end
	return changed
end

-- The game's numbers for what this writes, or nothing when this client lacks one of them.
function Layout.Constants()
	local enum = Enum or {}
	local system = enum.EditModeSystem
	local limit = Constants and Constants.EditModeConsts and Constants.EditModeConsts.EditModeMaxLayoutsPerType
	local character = enum.EditModeLayoutType and enum.EditModeLayoutType.Character
	if type(system) ~= "table" or type(limit) ~= "number" or type(character) ~= "number"
		or type(enum.EditModeActionBarSystemIndices) ~= "table" or type(enum.EditModeActionBarSetting) ~= "table"
		or type(enum.EditModeMicroMenuSetting) ~= "table" or type(enum.EditModeBagsSetting) ~= "table"
		or type(enum.EditModeStatusTrackingBarSetting) ~= "table"
		or type(enum.EditModeStatusTrackingBarSystemIndices) ~= "table" then
		return nil
	end
	return {
		actionBar = system.ActionBar, microMenu = system.MicroMenu, bags = system.Bags,
		status = system.StatusTrackingBar, vehicle = system.VehicleLeaveButton, totems = system.TotemActionBar,
		barIndex = enum.EditModeActionBarSystemIndices, barSetting = enum.EditModeActionBarSetting,
		microSetting = enum.EditModeMicroMenuSetting, bagsSetting = enum.EditModeBagsSetting,
		statusSetting = enum.EditModeStatusTrackingBarSetting,
		statusIndex = enum.EditModeStatusTrackingBarSystemIndices,
		character = character, max = limit,
		horizontal = enum.ActionBarOrientation and enum.ActionBarOrientation.Horizontal,
	}
end

-- The saved layout named Everlook and its number, presets counted first.
function Layout.Ours(info, presets)
	for position, item in ipairs(info.layouts or {}) do
		if item.layoutName == Layout.NAME then return item, #presets + position end
	end
end

------------------------------------------------------------------------------------------------
-- Reading the frames.

local function shownMicroButtons()
	local list = {}
	if not (MicroMenu and MicroMenu.GetChildren) then return list end
	for _, child in ipairs({ MicroMenu:GetChildren() }) do
		if Theme.Usable(child) and type(child.layoutIndex) == "number" and child:IsShown() then
			list[#list + 1] = child
		end
	end
	table.sort(list, function(a, b) return a.layoutIndex < b.layoutIndex end)
	return list
end

-- What Plan needs, or nothing while the frames haven't been laid out yet.
function Layout.Measure()
	if not (MicroMenu and BagsBar and MainStatusTrackingBarContainer) then return nil end
	local left = MicroMenu:GetLeft()
	if type(left) ~= "number" then return nil end
	local centers = {}
	for _, button in ipairs(shownMicroButtons()) do
		local x = button.GetCenter and button:GetCenter()
		if type(x) ~= "number" then return nil end
		centers[#centers + 1] = x - left
	end
	local bagWidths, listed = {}, {}
	if MainMenuBarBagManager and MainMenuBarBagManager.EnumerateBagButtons then
		for _, button in MainMenuBarBagManager:EnumerateBagButtons() do
			listed[button] = true
			if Theme.Usable(button) and button:IsShown() then bagWidths[#bagWidths + 1] = button:GetWidth() end
		end
	end
	-- The keyring sits on the bar beside the reagent bag (Camelot/MainMenuBarBagButtons.xml), whether
	-- or not the bag manager lists it.
	if Theme.Usable(KeyRingButton) and not listed[KeyRingButton] and KeyRingButton:IsShown() then
		bagWidths[#bagWidths + 1] = KeyRingButton:GetWidth()
	end
	if #bagWidths == 0 then return nil end
	return {
		microCenters = centers,
		microHeight = MicroMenu:GetHeight(),
		bagWidths = bagWidths,
		statusHeight = MainStatusTrackingBarContainer:GetHeight(),
	}
end

------------------------------------------------------------------------------------------------
-- Switching.

-- The plan in use while Everlook's layout is the active one, for the tiles and the track to follow.
local active

-- Everlook's micro tile width and scale, and the row's width, while its layout is in use; else nil.
function Theme.BottomRow()
	return active
end

local function ready()
	if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts and C_EditMode.SetActiveLayout
		and C_EditMode.OnLayoutAdded and C_EditMode.GetEditModeDefaultLayout) then return nil end
	if InCombatLockdown() then return nil end
	if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
		return nil
	end
	if not (EditModePresetLayoutManager and EditModePresetLayoutManager.GetCopyOfPresetLayouts) then return nil end
	local c = Layout.Constants()
	local info = C_EditMode.GetLayouts()
	if not c or type(info) ~= "table" or type(info.layouts) ~= "table" or type(info.activeLayout) ~= "number" then
		return nil
	end
	return c, info, EditModePresetLayoutManager:GetCopyOfPresetLayouts()
end

-- What the tiles and the track should follow now: the plan when Everlook's layout is in use.
local function follow(plan, info, presets)
	local _, index = Layout.Ours(info, presets)
	local now = (Theme:IsOn(KEY) and index and info.activeLayout == index) and plan or nil
	if now ~= active then
		active = now
		Theme:BottomRowChanged()
	end
end

-- Once each session the player is put on Everlook's layout; another layout they pick after that
-- is left alone.
local ensured = false
local warnedFull = false
local written -- the numbers this session last wrote
local writes, MAX_WRITES = 0, 3

local function switchOn()
	local c, info, presets = ready()
	if not c then return false end
	local geometry = Layout.Measure()
	if not geometry then return false, "unmeasured" end
	local plan = Layout.Plan(geometry)
	if not plan then return true end
	local ours, index = Layout.Ours(info, presets)
	if ensured and (not ours or info.activeLayout ~= index) then
		follow(plan, info, presets)
		return true
	end
	local created = false
	if not ours then
		local characters = 0
		for _, item in ipairs(info.layouts) do
			if item.layoutType == c.character then characters = characters + 1 end
		end
		if characters >= c.max then
			if not warnedFull then
				warnedFull = true
				Theme:Print("Edit Mode has no room for another character layout, so the bottom bars stay as they are.")
			end
			return true
		end
		local current = info.activeLayout
		local source = current <= #presets and presets[current] or info.layouts[current - #presets]
		if type(source) ~= "table" then return true end
		ours = copy(source)
		ours.layoutName, ours.layoutType, ours.layoutIndex = Layout.NAME, c.character, nil
		info.layouts[#info.layouts + 1] = ours
		index = #presets + #info.layouts
		created = true
	end
	-- Once this session has written the layout, it writes again only when its own numbers change,
	-- never because the game hands back what was saved a little differently, and a few times at
	-- most: each save makes the game send EDIT_MODE_LAYOUTS_UPDATED, which comes back here.
	local signature = string.format("%d %d %.1f %.1f %.1f", plan.padding, plan.percent, plan.width, plan.microX, plan.microY)
	if not created and (signature == written or writes >= MAX_WRITES) then
		ensured = true
		if info.activeLayout ~= index then
			C_EditMode.SetActiveLayout(index)
			info.activeLayout = index
		end
		follow(plan, info, presets)
		return true
	end
	local changed = Layout.Write(ours, plan, c)
	written, writes = signature, writes + 1
	ensured = true
	if created then
		C_EditMode.SaveLayouts(info)
		C_EditMode.OnLayoutAdded(index, true, false)
	elseif changed then
		C_EditMode.SaveLayouts(info)
		C_EditMode.SetActiveLayout(index)
	elseif info.activeLayout ~= index then
		C_EditMode.SetActiveLayout(index)
	end
	info.activeLayout = index
	follow(plan, info, presets)
	return true
end

-- Off: back to the game's default layout, only from Everlook's own.
local function switchOff()
	local c, info, presets = ready()
	if not c then return false end
	ensured = false
	local _, index = Layout.Ours(info, presets)
	if index and info.activeLayout == index then
		C_EditMode.SetActiveLayout(C_EditMode.GetEditModeDefaultLayout())
		info.activeLayout = C_EditMode.GetEditModeDefaultLayout()
	end
	follow(nil, info, presets)
	return true
end

-- What couldn't be done yet waits for the end of combat, Edit Mode closing, or the frames being laid
-- out (a second later).
local pending = false
local retries = 0
local RETRIES = 10

-- Off runs only when asked: the setting turned off, the first login of the session, or an off
-- that was waiting. A player who picks Everlook's layout by hand later keeps it.
local offAsked = true

function Layout.Apply(asked)
	local done, why
	if Theme:IsOn(KEY) then
		done, why = switchOn()
	elseif asked or offAsked or pending then
		done, why = switchOff()
		if done then offAsked = false end
	else
		done = true
		follow(nil, { layouts = {}, activeLayout = 0 }, {})
	end
	pending = not done
	if done then retries = 0 end
	-- Frames not laid out yet: a few tries, a second apart. Combat and Edit Mode have events.
	if why == "unmeasured" and retries < RETRIES and C_Timer and C_Timer.After then
		retries = retries + 1
		C_Timer.After(1, function()
			if pending then Layout.Apply() end
		end)
	end
end

-- The tiles and track that follow the row: Theme:BottomRowChanged runs each surface's apply again.
function Theme:BottomRowChanged()
	for _, key in ipairs({ "microMenu", "statusBars" }) do
		if self:IsOn(key) then self:Apply(key) end
	end
end

function Layout.Enable()
	Theme:On("PLAYER_ENTERING_WORLD", function() Layout.Apply() end) -- offAsked starts true: once
	Theme:On("PLAYER_REGEN_ENABLED", function() if pending then Layout.Apply() end end)
	-- The game's answer to a switch, or the player saving in Edit Mode: the plan is checked again,
	-- and the tiles follow whichever layout is now in use.
	Theme:On("EDIT_MODE_LAYOUTS_UPDATED", function() Layout.Apply() end)
	-- Closing Edit Mode without saving sends no EDIT_MODE_LAYOUTS_UPDATED (12.0.0).
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("EditMode.Exit", function() Layout.Apply() end, Layout)
	end
end

Layout.KEY = KEY
Layout.NEEDS = { "C_EditMode.GetLayouts", "C_EditMode.SaveLayouts", "C_EditMode.SetActiveLayout",
	"C_EditMode.OnLayoutAdded", "C_EditMode.GetEditModeDefaultLayout",
	"EditModePresetLayoutManager.GetCopyOfPresetLayouts", "Constants.EditModeConsts.EditModeMaxLayoutsPerType",
	"Enum.EditModeLayoutType.Character", "Enum.EditModeSystem.ActionBar", "Enum.EditModeSystem.MicroMenu",
	"Enum.EditModeSystem.Bags", "Enum.EditModeSystem.StatusTrackingBar", "Enum.EditModeActionBarSystemIndices",
	"Enum.EditModeActionBarSetting.IconPadding", "Enum.EditModeMicroMenuSetting.Size",
	"Enum.EditModeBagsSetting.BagSlotPadding", "Enum.EditModeStatusTrackingBarSetting.Size",
	"Enum.EditModeStatusTrackingBarSystemIndices", "MicroMenu", "BagsBar", "MainMenuBarBagManager.EnumerateBagButtons",
	"MainStatusTrackingBarContainer", "EditModeManagerFrame.IsEditModeActive" }
