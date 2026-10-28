local addon_name, Everlook = ...

local ICON = "Interface\\AddOns\\Everlook\\assets\\logo.tga"
local DEFAULT_ANGLE = 160

local button

local function minimap_settings()
	local minimap = EverlookSaved and EverlookSaved.minimap
	if type(minimap) == "table" then
		return minimap
	end
end

local function saved_angle()
	local minimap = minimap_settings()
	local angle = minimap and minimap.angle
	if type(angle) == "number" then
		return angle
	end
	return DEFAULT_ANGLE
end

local function place()
	if button:GetParent() ~= Minimap then
		return
	end
	local angle = math.rad(saved_angle())
	local radius = (math.max(Minimap:GetWidth(), Minimap:GetHeight()) / 2) + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function drag_on_update(self)
	if self:GetParent() ~= Minimap then
		self:SetScript("OnUpdate", nil)
		return
	end
	local mx, my = Minimap:GetCenter()
	if not mx or not my then
		return
	end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	cx, cy = cx / scale, cy / scale
	EverlookSaved.minimap = minimap_settings() or {}
	EverlookSaved.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
	place()
end

local function create_button()
	button = CreateFrame("Button", "EverlookMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetClampedToScreen(true)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local overlay = button:CreateTexture(nil, "OVERLAY")
	overlay:SetSize(53, 53)
	overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	overlay:SetPoint("TOPLEFT")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetTexture(ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -5)
	button.icon = icon

	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Everlook")
		GameTooltip:AddLine("Click to open the settings.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function()
		if Everlook.settings then Everlook.settings.toggle() end
	end)

	button:SetMovable(true)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(self)
		GameTooltip:Hide()
		self:SetScript("OnUpdate", drag_on_update)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		place()
	end)

	place()
	button:Show()
end

-- The client hands the saved variables to Lua when ADDON_LOADED fires for this addon, after its files have run,
-- so this is the first place EverlookSaved can be read, and it is still nil on a new install. The client writes it to
-- WTF/Account/<account>/SavedVariables/Everlook.lua on /reload, logout, disconnect or quit.
EventUtil.ContinueOnAddOnLoaded(addon_name, function()
	EverlookSaved = EverlookSaved or {}

	local minimap = EverlookSaved.minimap
	if type(minimap) == "table" then
		minimap.icon = nil
	else
		EverlookSaved.minimap = nil
	end

	create_button()
	EventUtil.ContinueOnPlayerLogin(place)
end)

-- The last file of the core: what happens before the addon loads is the engine's.
if Everlook.trace then Everlook.trace.stamp("core_files") end
