-- Nameplates as the client builds them, one stand-in per kind, for the harness to lay the nameplate view over.
--
-- Shaped from what /everlook plates found in the client (2026-10-11):
--   a plate with a health bar: the name spans the whole group (the bar and the level box), the health bar is 168
--   wide and 16 high, the level box (PlayerLevelDiffFrame) is 35 wide and sits to its right, the cast bar container
--   is under the bar, and the name is centred over the group;
--   a name-only plate: the health bar is hidden and its container takes the width of the whole group.
-- The simplified, widgets-only, forbidden and personal plates are NOT seen in the client yet: they are drawn from
-- Blizzard's own code (retail 12.0.0) and marked so.
nameplate = {}

local GROUP, BAR_HEIGHT, LEVEL_WIDTH = 207.7, 16.3, 34.8
local plates = {}

function nameplate.install()
	C_NamePlate = {
		GetNamePlateForUnit = function(unit) return plates[unit] end,
		GetNamePlates = function()
			local list = {}
			for _, plate in pairs(plates) do list[#list + 1] = plate end
			table.sort(list, function(a, b) return a.sort < b.sort end)
			return list
		end,
	}
	function UnitExists() return true end
end

-- kind: enemy_npc, enemy_player, friendly_npc, friendly_player, name_only, simplified, widgets_only, forbidden, personal
function nameplate.make(kind, options)
	options = options or {}
	local unit = options.unit or ("nameplate" .. (#nameplate.list + 1))
	local plate = CreateFrame("Frame", "StandInNamePlate" .. unit, UIParent)
	plate.sort = #nameplate.list + 1
	plate:SetSize(237.5, 85)
	plate:SetPoint("CENTER", UIParent, "CENTER", options.x or 0, options.y or 0)
	function plate:GetUnit() return unit end
	if kind == "forbidden" then function plate:IsForbidden() return true end end
	local frame = CreateFrame("Button", nil, plate)
	frame:SetAllPoints(plate)
	plate.UnitFrame = frame
	frame.namePlateFrame = plate

	local friend = kind == "friendly_npc" or kind == "friendly_player" or kind == "name_only" or kind == "simplified" or kind == "personal"
	local player = kind == "enemy_player" or kind == "friendly_player" or kind == "name_only" or kind == "personal"
	local flags = { friend = friend, player = player, only_name = kind == "name_only", simplified = kind == "simplified" }
	function frame:IsFriend() return flags.friend end
	function frame:IsPlayer() return flags.player end
	function frame:IsShowOnlyName() return flags.only_name end
	function frame:IsSimplified() return flags.simplified end
	frame.widgetsOnlyMode = kind == "widgets_only" or nil

	local group_left = -GROUP / 2
	local container = CreateFrame("Frame", nil, frame)
	local with_bar = kind ~= "name_only" and kind ~= "widgets_only"
	container:SetHeight(BAR_HEIGHT)
	container:SetPoint("BOTTOMLEFT", frame, "CENTER", group_left, -6)
	container:SetWidth(with_bar and (GROUP - LEVEL_WIDTH - 5) or GROUP)
	frame.HealthBarsContainer = container
	local bar = CreateFrame("StatusBar", nil, container)
	bar:SetAllPoints(container)
	bar:SetMinMaxValues(0, 1)
	bar:SetValue(options.health or 1)
	local red = not friend
	bar:SetStatusBarColor(red and 0.65 or 0.0, red and 0.0 or 0.65, 0.0)
	if not with_bar then bar:Hide() end
	frame.healthBar = bar
	container.healthBar = bar

	local name = frame:CreateFontString(nil, "OVERLAY")
	name:SetFontObject(GameFontHighlight)
	name:SetJustifyH("CENTER")
	name:SetPoint("BOTTOMLEFT", container, "TOPLEFT", 0, 2)
	name:SetWidth(GROUP)
	name:SetHeight(17.5)
	name:SetText(options.name or kind)
	frame.name = name
	if kind == "widgets_only" or kind == "simplified" and not options.targeted then name:Hide() end

	local level = CreateFrame("Frame", nil, frame)
	level:SetSize(LEVEL_WIDTH, 19.9)
	level:SetPoint("LEFT", container, "RIGHT", 5, 0)
	local text = level:CreateFontString(nil, "OVERLAY")
	text:SetFontObject(GameFontNormal)
	text:SetAllPoints(level)
	text:SetText(options.level or "27")
	frame.PlayerLevelDiffFrame = level
	level.playerLevelDiffText = text
	if not with_bar then level:Hide() end

	local cast = CreateFrame("Frame", nil, frame)
	cast:SetSize(GROUP, 19.9)
	cast:SetPoint("TOPLEFT", container, "BOTTOMLEFT", 0, 0)
	frame.CastBarsContainer = cast

	-- Blizzard lays the plate out again from time to time and sets the name back to centred.
	function frame:UpdateAnchors() name:SetJustifyH("CENTER") end

	if kind == "simplified" then plate:SetScale(0.7) end
	plates[unit] = plate
	nameplate.list[#nameplate.list + 1] = plate
	return plate, unit
end

nameplate.list = {}
function nameplate.clear()
	for unit, plate in pairs(plates) do plate:Hide(); plates[unit] = nil end
	nameplate.list = {}
end
