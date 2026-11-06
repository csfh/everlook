local UIScale = Everlook:NewAddon("EverlookUIScale", {
	label = "UI Scale",
	defaults = {
		pixelPerfect = false,
		pixels = 0, -- screen pixels per interface pixel; 0 follows the game's slider
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookUIScale", {
	"GetCVar",
	"GetPhysicalScreenSize",
	"InCombatLockdown",
	"UIParent.SetScale",
	"UIParent.GetScale",
})

-- The interface is laid out 768 units tall, so at 768 / screen height one unit is one pixel
-- (ConvertPixelsToUI in PixelUtilSecure.lua, wow-ui-source 12.0.0). The game's own slider
-- stops at 65% (Graphics.lua) and the uiscale CVar is held to the same range, so this sets
-- UIParent's scale directly and leaves the CVar alone.

-- The scale the game itself last gave UIParent, and the one this addon last set. The game picks its
-- own scale (0.64 with "Use UI Scale" off on a 6K screen, not 1), so this reads it rather than
-- working it out: whenever UIParent's scale isn't ours, the game set it.
local engineScale, lastSet

local function noteGameScale()
	local scale = UIParent:GetScale()
	if not lastSet or math.abs(scale - lastSet) > 0.0001 then engineScale = scale end
end

-- The scale the game itself would use, from the uiscale CVar until the game has set one.
local function gameScale()
	if engineScale then return engineScale end
	if GetCVar("useUiScale") == "1" then
		local value = tonumber(GetCVar("uiscale"))
		if value and value > 0 then return value end
	end
	return 1
end

-- Interface units per screen pixel, or nil when the game can't say how tall the screen is.
local function unitScale()
	local _, height = GetPhysicalScreenSize()
	if type(height) ~= "number" or height <= 0 then return nil end
	return 768 / height
end

-- The sizes offered: from 40% to 150%, or one pixel per unit when no multiple lands in that range.
local SMALLEST, LARGEST = 0.4, 1.5
local NAMES = { { 0.55, "Tiny" }, { 0.8, "Small" }, { 1.0, "Medium" }, { 1.2, "Large" }, { math.huge, "Huge" } }

local function offered(unit, pixels)
	local scale = unit * pixels
	return (scale >= SMALLEST and scale <= LARGEST) or (pixels == 1 and scale > LARGEST)
end

local function nameFor(scale)
	for _, band in ipairs(NAMES) do
		if scale < band[1] then return band[2] end
	end
end

-- The Size choices: following the game's slider, then each sharp size this screen can show.
function UIScale.Sizes()
	local list = { { 0, "Follow the game's UI Scale" } }
	local unit = unitScale()
	if not unit then return list end
	for pixels = 1, math.floor(LARGEST / unit) + 1 do
		if offered(unit, pixels) then
			local scale = unit * pixels
			list[#list + 1] = { pixels, ("%s, %s (%d %s per pixel)"):format(nameFor(scale),
				EverlookPreferences.Percent(scale), pixels, pixels == 1 and "screen pixel" or "screen pixels") }
		end
	end
	return list
end

-- One interface unit covers a whole number of screen pixels, so lines stay sharp at any size: the
-- chosen number, or the one closest to the game's own scale. On a tall screen one pixel per unit is
-- tiny (23% on a 3384-pixel 6K panel). A choice this screen doesn't offer, after a screen change,
-- follows the game's scale too.
local function pixelPerfect(pixels)
	local unit = unitScale()
	if not unit then return nil end
	if pixels and pixels > 0 and offered(unit, pixels) then return unit * pixels end
	return unit * math.max(1, math.floor(gameScale() / unit + 0.5))
end

-- Whether this session set UIParent's scale, so turning this off only resets a scale we wrote.
local written = false
-- A change combat held back; PLAYER_REGEN_ENABLED applies it.
local pending = false

local function setScale(scale)
	if math.abs(UIParent:GetScale() - scale) > 0.0001 then UIParent:SetScale(scale) end
	lastSet = scale
end

function UIScale:Apply()
	-- UIParent holds the action bars, so its scale waits for combat to end.
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	noteGameScale()
	if self.db.pixelPerfect then
		local scale = pixelPerfect(self.db.pixels)
		if not scale then return end
		setScale(scale)
		written = true
	elseif written then
		setScale(gameScale())
		written = false
	end
end

function UIScale:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Interface")
	page:Checkbox("pixelPerfect", "Pixel-perfect UI scale",
		"Scale the interface so each of its pixels covers a whole number of screen pixels, which keeps borders "
			.. "and lines sharp. Turning this off puts the game's scale back.")
	page:Dropdown("pixels", "Pixel-perfect size",
		"The sharp sizes this screen can show. Following the game's UI Scale picks the one closest to its slider.",
		UIScale.Sizes)
end

function UIScale:OnEnable()
	-- The game sets UIParent's scale again when the window or the UI Scale option changes; dragging
	-- the window edge sends a burst of these, so only the last one rescales.
	local function reapply()
		noteGameScale()
		if self.db.pixelPerfect then
			Everlook.Schedule.Defer("EverlookUIScale", function() self:Apply() end)
		end
	end
	self:RegisterEvent("UI_SCALE_CHANGED", reapply)
	self:RegisterEvent("DISPLAY_SIZE_CHANGED", reapply)
	self:RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if pending then self:Apply() end
	end)
	self:Apply()
end

function UIScale:OnSettingChanged()
	self:Apply()
end
