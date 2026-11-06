-- Minimap button with the Everlook logo: click opens the settings, drag moves it around the minimap.
local Preferences = EverlookPreferences

local ICON = "Interface\\AddOns\\Everlook\\assets\\logo.tga"

-- Point on a circle just outside the minimap's edge.
local function position(angle)
	local radius = math.max(Minimap:GetWidth(), Minimap:GetHeight()) / 2 + 5
	local radians = math.rad(angle)
	return math.cos(radians) * radius, math.sin(radians) * radius
end

function Preferences:PlaceMinimapButton()
	local x, y = position(self.db.minimapAngle)
	self.button:ClearAllPoints()
	self.button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- While dragging: the angle from the minimap's centre to the cursor.
local function followCursor()
	local mx, my = Minimap:GetCenter()
	if not mx then return end
	local cx, cy = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	Preferences.db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
	Preferences:PlaceMinimapButton()
end

function Preferences:CreateMinimapButton()
	local button = CreateFrame("Button", "EverlookMinimapButton", Minimap)
	self.button = button
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 7, -5)

	button:SetScript("OnEnter", function(frame)
		GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
		GameTooltip:AddLine("Everlook")
		GameTooltip:AddLine("Click to open the settings. Drag to move.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function() GameTooltip:Hide() end)

	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function() self:Open() end)

	button:RegisterForDrag("LeftButton")
	button:SetScript("OnDragStart", function(frame)
		GameTooltip:Hide()
		frame:SetScript("OnUpdate", followCursor)
	end)
	button:SetScript("OnDragStop", function(frame)
		frame:SetScript("OnUpdate", nil)
		self:PlaceMinimapButton()
	end)

	self:PlaceMinimapButton()
end
