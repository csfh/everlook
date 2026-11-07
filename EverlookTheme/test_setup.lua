-- Shared setup for EverlookTheme's tests: stand-ins for the frames every surface restyles, then
-- the addon loaded and logged in. Not in the TOC.
--   local f = dofile(dir .. "/test_setup.lua")(dir, "<title>")
return function(dir, title)
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
t.out(title)

-- Widget methods the theme uses.
local W = t.Widget
function W:SetAtlas(atlas) self.atlas = atlas end
function W:SetAllPoints(target) self.allPoints = target or true end
function W:SetHeight(height) self.height = height end
function W:SetWidth(width) self.width = width end
function W:SetVertexColor(r, g, b, a) self.vertex = { r, g, b, a } end
function W:SetColorTexture(...) self.colorTexture = { ... } end
function W:SetAlpha(alpha) self.alpha = alpha end
function W:GetName() return self.name end
function W:GetFrameLevel() return self.level or 1 end
function W:SetFrameLevel(level) self.level = level end
function W:SetFontObject(font) self.fontObject = font end
function W:SetPoint(...)
	self.point = { ... }
	self.points = self.points or {}
	self.points[#self.points + 1] = { ... }
end
function W:SetUsingParentLevel(using) self.parentLevel = using end
function W:GetEffectiveScale() return 1 end
-- Frames remember their textures and children, so a test can find what the theme drew.
local created = {}
local createFrame = CreateFrame
CreateFrame = function(kind, name, parent)
	local frame = createFrame(kind, name, parent)
	frame.parent = parent
	created[#created + 1] = frame
	return frame
end
function W:CreateTexture()
	local texture = t.widget()
	texture.shown = true
	self.textures = self.textures or {}
	self.textures[#self.textures + 1] = texture
	return texture
end
function W:CreateFontString()
	local text = t.widget()
	self.texts = self.texts or {}
	self.texts[#self.texts + 1] = text
	return text
end

local function shownTexture(name)
	local texture = t.widget(name)
	texture.shown, texture.alpha = true, 1
	if name then _G[name] = texture end
	return texture
end

-- Hooks run after the function they hook, as hooksecurefunc does.
hooksecurefunc = function(target, name, fn)
	if type(target) == "string" then target, name, fn = _G, target, name end
	local original = target[name]
	target[name] = function(...)
		local a, b, c, d, e = original(...)
		fn(...)
		return a, b, c, d, e
	end
end

-- One chat window with its border, tab and input line, named as FloatingChatFrame.xml names them.
CHAT_FRAMES = { "ChatFrame1" }
CHAT_FRAME_TEXTURES = {}
local chat = t.widget("ChatFrame1")
chat.shown = true
ChatFrame1 = chat
-- The window's dark area, which reaches past the frame over the scroll bar.
local chatBackground = t.widget()
chatBackground.shown = true
chat.Background = chatBackground
local border = {}
for _, key in ipairs({ "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }) do
	border[#border + 1] = shownTexture("ChatFrame1" .. key)
end
local tab = t.widget("ChatFrame1Tab")
ChatFrame1Tab = tab
for _, key in ipairs({ "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
	"HighlightLeft", "HighlightMiddle", "HighlightRight" }) do
	tab[key] = shownTexture()
end
local edit = t.widget("ChatFrame1EditBox")
ChatFrame1EditBox = edit
local editArt = {}
for _, key in ipairs({ "Left", "Right", "Mid", "FocusLeft", "FocusRight", "FocusMid" }) do
	editArt[#editArt + 1] = shownTexture("ChatFrame1EditBox" .. key)
end
FCFTab_UpdateColors = function(self, selected)
	self.ActiveMiddle:SetShown(selected)
end
-- PixelUtil (PixelUtil.lua): here one screen pixel is half a unit.
PixelUtil = {
	SetWidth = function(region, width, minPixels) region:SetWidth(math.max(width, minPixels * 0.5)) end,
	SetHeight = function(region, height, minPixels) region:SetHeight(math.max(height, minPixels * 0.5)) end,
}

-- The bar containers (StatusTrackingBar.xml).
MainStatusTrackingBarContainer = t.widget("MainStatusTrackingBarContainer")
MainStatusTrackingBarContainer.BarFrameTexture = shownTexture()

-- The main action bar (MainActionBar.xml); action_bars_test.lua gives it buttons.
MainActionBar = t.widget("MainActionBar")
MainActionBar.BorderArt = shownTexture()
MainActionBar.EndCaps = { LeftEndCap = shownTexture(), RightEndCap = shownTexture() }

-- A tooltip, styled by SharedTooltip_SetBackdropStyle.
GameTooltip.NineSlice = t.widget()
GameTooltip.NineSlice.shown = true
local tooltipBorder = {}
for _, key in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
	"TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }) do
	GameTooltip.NineSlice[key] = shownTexture()
	tooltipBorder[key] = GameTooltip.NineSlice[key]
end
SharedTooltip_SetBackdropStyle = function() end

-- Unit frames: Forever's player frame has its own badge; a party member has none.
PlayerFrame = t.widget("PlayerFrame")
PlayerFrame.PlayerFrameContent = { PlayerFrameContentMain = { LevelBackgroundCircle = shownTexture() } }
PlayerFrame.unit = "player"
local member = t.widget("PartyMember1")
member.unit, member.shown, member.Portrait = "party1", true, shownTexture()
PartyFrame = { PartyMemberFramePool = { EnumerateActive = function()
	local done = false
	return function()
		if done then return nil end
		done = true
		return member
	end
end } }
local levels = { player = 20, party1 = 17 }
UnitExists = function(unit) return levels[unit] ~= nil end
UnitLevel = function(unit) return levels[unit] end

-- EventRegistry's callbacks (CallbackRegistry.lua): a test triggers them with EventRegistry:Trigger.
EventRegistry = { callbacks = {} }
function EventRegistry:RegisterCallback(event, fn, owner)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], { fn, owner })
end
function EventRegistry:Trigger(event, ...)
	for _, entry in ipairs(self.callbacks[event] or {}) do entry[1](entry[2], ...) end
end

t.load("EverlookTheme")
t.fire("PLAYER_LOGIN")
local Theme = Everlook:GetAddon("EverlookTheme")

-- The panel a surface drew on `parent`: only panels draw at their parent's level.
local function panelOn(parent)
	for _, frame in ipairs(created) do
		if frame.parentLevel and frame.parent == parent then return frame end
	end
end

return {
	t = t, check = t.check, Theme = Theme, created = created, panelOn = panelOn, shownTexture = shownTexture,
	chat = chat, chatBackground = chatBackground, border = border, tab = tab, edit = edit, editArt = editArt,
	tooltipBorder = tooltipBorder, member = member, levels = levels,
}
end
