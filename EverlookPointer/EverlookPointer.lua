local Pointer = Everlook:NewAddon("EverlookPointer", {
	label = "Pointer",
	defaults = {
		ring = false,
		ringSize = 48,
		ringOpacity = 0.8,
		reactionColor = false,
		combat = false,
		combatSize = 1.4,
		camera = false,
		cast = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookPointer", {
	"GetCursorPosition",
	"UIParent",
	"UnitExists",
	"UnitIsDead",
	"UnitSelectionColor",
	"InCombatLockdown",
}, {
	"IsMouselooking",
	"UnitCastingDuration",
	"UnitChannelDuration",
	"UnitCastingInfo",
	"UnitChannelInfo",
	"issecretvalue",
})

-- A plain white ring, tinted by SetVertexColor.
local RING = "Interface\\AddOns\\EverlookPointer\\assets\\ring.tga"
local WHITE = { 1, 1, 1 }
local DEAD = { 0.5, 0.5, 0.5 }
local CAST = { 1, 0.82, 0 } -- the gold of the game's cast bar
local CAST_SCALE = 1.3 -- the cast ring sits just outside the pointer ring

local frame, ring, cast, pulse
local lastX, lastY, centered
local inCombat = false

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

function Pointer:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "World & Camera")
	page:Checkbox("ring", "Ring around the pointer", "Draws a ring around the mouse pointer so it's easy to find.")
	page:Slider("ringSize", "Ring size", "How wide the ring is. Needs Ring around the pointer.",
		24, 128, 4, function(value) return value .. " px" end)
	page:Slider("ringOpacity", "Ring opacity", "How solid the ring is. Needs Ring around the pointer.",
		0.2, 1, 0.05, EverlookPreferences.Percent)
	page:Checkbox("reactionColor", "Color by what's under the pointer",
		"Tints the ring in the game's colors for the unit you point at: red hostile, yellow neutral, green friendly, gray dead. Needs Ring around the pointer.")
	page:Checkbox("combat", "Grow and pulse in combat",
		"Makes the ring bigger and pulse while you're in combat. Needs Ring around the pointer.")
	page:Slider("combatSize", "Combat size", "How much bigger the ring gets in combat. Needs Grow and pulse in combat.",
		1.1, 2, 0.1, EverlookPreferences.Percent)
	page:Checkbox("camera", "Center while turning the camera",
		"While you hold a mouse button to turn the camera, the ring moves to the middle of the screen. Needs Ring around the pointer.")
	page:Checkbox("cast", "Show cast progress",
		"A gold ring fills around the pointer as you cast. Needs Ring around the pointer.")
end

local function build()
	if frame then return end
	frame = CreateFrame("Frame", "EverlookPointerFrame", UIParent)
	frame:SetFrameStrata("TOOLTIP")
	frame:SetFrameLevel(9999)
	if frame.EnableMouse then frame:EnableMouse(false) end
	ring = frame:CreateTexture(nil, "OVERLAY")
	ring:SetTexture(RING)
	ring:SetAllPoints(frame)
	Pointer.ringTexture = ring

	pulse = frame:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.6)
	fade:SetSmoothing("IN_OUT")

	-- The game's cooldown swipe, drawn with the ring, fills it as the cast goes.
	cast = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
	cast:SetPoint("CENTER", frame, "CENTER")
	cast:SetSwipeTexture(RING, CAST[1], CAST[2], CAST[3], 1)
	cast:SetDrawEdge(false)
	cast:SetDrawBling(false)
	cast:SetHideCountdownNumbers(true)
	if cast.SetUseCircularEdge then cast:SetUseCircularEdge(true) end
	cast:Hide()

	frame:SetScript("OnUpdate", function() Pointer:Follow() end)
end

-- Where the ring goes this frame: the pointer, or the screen's middle while the camera turns.
function Pointer:Follow()
	local db = self.db
	if db.camera and IsMouselooking and IsMouselooking() then
		if not centered then
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "CENTER")
			centered, lastX, lastY = true, nil, nil
		end
	else
		local x, y = GetCursorPosition()
		if x ~= lastX or y ~= lastY or centered then
			local scale = UIParent:GetEffectiveScale()
			frame:ClearAllPoints()
			frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
			lastX, lastY, centered = x, y, false
		end
	end
	-- No event says the pointer left a unit, so a tinted ring checks each frame.
	if self.tinted and not UnitExists("mouseover") then self:Tint() end
end

-- The game's selection color for the unit under the pointer, gray if it's dead, else white.
function Pointer:Tint()
	local color = WHITE
	self.tinted = false
	if self.db.reactionColor and UnitExists("mouseover") then
		local dead = UnitIsDead("mouseover")
		if not secret(dead) and dead then
			color = DEAD
		else
			local r, g, b = UnitSelectionColor("mouseover")
			if not (secret(r) or secret(g) or secret(b)) and r then color = { r, g, b } end
		end
		self.tinted = true
	end
	ring:SetVertexColor(color[1], color[2], color[3])
end

-- Size and pulse for the moment: bigger and pulsing in combat while that's on.
function Pointer:Shape()
	local db = self.db
	local fighting = db.combat and inCombat
	local size = db.ringSize * (fighting and db.combatSize or 1)
	frame:SetSize(size, size)
	cast:SetSize(size * CAST_SCALE, size * CAST_SCALE)
	if fighting then
		if not pulse:IsPlaying() then pulse:Play() end
	elseif pulse:IsPlaying() then
		pulse:Stop()
	end
end

-- The player's cast or channel as a cooldown on the cast ring. The duration objects keep the
-- timing usable when it's secret; older clients give milliseconds instead.
function Pointer:ShowCast()
	if not frame then return end
	if not self.db.cast then
		cast:Clear()
		cast:Hide()
		self.castShown = false
		return
	end
	local channel = false
	local duration = UnitCastingDuration and UnitCastingDuration("player")
	if not duration and UnitChannelDuration then
		duration, channel = UnitChannelDuration("player"), true
	end
	-- SetCooldownFromDurationObject refuses a secret duration from addon code (its arguments are
	-- AllowedWhenUntainted, FrameAPICooldownDocumentation.lua, 12.0.0), so a refusal hides the ring.
	if duration and cast.SetCooldownFromDurationObject then
		-- A cast fills the ring; a channel drains it.
		cast:SetReverse(not channel)
		if pcall(cast.SetCooldownFromDurationObject, cast, duration) then
			cast:Show()
			self.castShown = true
		else
			cast:Clear()
			cast:Hide()
			self.castShown = false
		end
		return
	end
	local startMs, endMs
	channel = false
	if UnitCastingInfo then startMs, endMs = select(4, UnitCastingInfo("player")) end
	if not startMs and UnitChannelInfo then
		startMs, endMs = select(4, UnitChannelInfo("player"))
		channel = true
	end
	if startMs and endMs and not secret(startMs) and not secret(endMs) and endMs > startMs then
		cast:SetReverse(not channel)
		cast:SetCooldown(startMs / 1000, (endMs - startMs) / 1000)
		cast:Show()
		self.castShown = true
	else
		cast:Clear()
		cast:Hide()
		self.castShown = false
	end
end

-- Builds the ring on first use and shows it with every choice as it stands; off hides it all.
function Pointer:Apply()
	if not self.db.ring then
		if frame then
			frame:Hide()
			pulse:Stop()
			cast:Clear()
			cast:Hide()
		end
		self.castShown = false
		return
	end
	build()
	ring:SetAlpha(self.db.ringOpacity)
	lastX, lastY, centered = nil, nil, nil
	self:Shape()
	self:Tint()
	self:ShowCast()
	frame:Show()
	self:Follow()
end

local CAST_EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
	"UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP",
}

function Pointer:OnEnable()
	inCombat = InCombatLockdown() and true or false
	self:RegisterEvent("PLAYER_REGEN_DISABLED", function()
		inCombat = true
		if frame and self.db.ring then self:Shape() end
	end)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		inCombat = false
		if frame and self.db.ring then self:Shape() end
	end)
	self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function()
		if frame and self.db.ring then self:Tint() end
	end)
	for _, event in ipairs(CAST_EVENTS) do
		self:RegisterEvent(event, function(_, unit)
			if unit == "player" and frame and self.db.ring then self:ShowCast() end
		end)
	end
	self:Apply()
end

function Pointer:OnSettingChanged()
	self:Apply()
end
