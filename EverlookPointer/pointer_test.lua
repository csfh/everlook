local dir = arg[0]:match("^(.*)/[^/]+$") or "."
local t = dofile(dir .. "/../EverlookQA/stubs.lua")(dir .. "/..")
local check = t.check

t.out("EverlookPointer")

-- Widget methods the ring uses.
local W = t.Widget
function W:EnableMouse() end
function W:SetAllPoints() end
function W:SetAlpha(alpha) self.alpha = alpha end
function W:SetVertexColor(r, g, b) self.vertex = { r, g, b } end
function W:SetSwipeTexture(texture) self.swipe = texture end
function W:SetDrawEdge() end
function W:SetDrawBling() end
function W:SetHideCountdownNumbers() end
function W:SetUseCircularEdge() end
function W:SetReverse(reverse) self.reverse = reverse end
function W:SetCooldownFromDurationObject(duration) self.duration = duration end
function W:SetCooldown(start, length) self.cooldown = { start, length } end
function W:Clear() self.duration, self.cooldown = nil, nil end
function W:GetEffectiveScale() return 2 end
function W:CreateAnimationGroup()
	local group = { playing = false }
	function group:SetLooping() end
	function group:CreateAnimation()
		local animation = {}
		function animation:SetFromAlpha() end
		function animation:SetToAlpha() end
		function animation:SetDuration() end
		function animation:SetSmoothing() end
		return animation
	end
	function group:Play() self.playing = true end
	function group:Stop() self.playing = false end
	function group:IsPlaying() return self.playing end
	return group
end

UIParent = t.widget("UIParent")
local mouseover -- nil, or { r, g, b, dead }
UnitExists = function(unit) return unit == "mouseover" and mouseover ~= nil end
UnitIsDead = function() return mouseover and mouseover.dead or false end
UnitSelectionColor = function() return mouseover[1], mouseover[2], mouseover[3], 1 end
local casting, channeling
UnitCastingDuration = function() return casting end
UnitChannelDuration = function() return channeling end

t.load("EverlookPointer")
t.fire("PLAYER_LOGIN")
local P = Everlook:GetAddon("EverlookPointer")
local function change(key, value) t.change("EverlookPointer_" .. key, value) end

check(not (P.db.ring or P.db.reactionColor or P.db.combat or P.db.cast), "every effect starts off")
check(P.db.hideDragging, "except hiding while dragging the camera, which starts on")
check(EverlookPointerFrame == nil, "no ring is made until it's turned on")

change("ring", true)
local frame = EverlookPointerFrame
check(frame and frame.shown and frame.width == 48, "on: a 48 px ring")
t.cursor = { 400, 300 }
frame.scripts.OnUpdate()
check(frame.point[1] == "CENTER" and frame.point[4] == 200 and frame.point[5] == 150,
	"it follows the pointer, in UI units")

local RING = "Interface\\AddOns\\EverlookPointer\\assets\\ring%d.tga"
check(P.ringTexture.texture == RING:format(5), "a 3 px band on a 48 px ring")
check(P.RingFile(24, 1) == RING:format(3) and P.RingFile(128, 1) == RING:format(1)
	and P.RingFile(24, 16) == RING:format(12), "the nearest ring for each size and width, thinnest to thickest")

change("ringSize", 64)
change("ringOpacity", 0.5)
check(frame.width == 64, "size changes with the slider")
change("ringWidth", 8)
check(P.ringTexture.texture == RING:format(8), "width changes with the slider")
change("ringWidth", 3)

-- What's under the pointer.
mouseover = { 1, 0, 0 }
t.fire("UPDATE_MOUSEOVER_UNIT")
local function color() return table.concat(P.ringTexture.vertex, ",") end
check(color() == "1,1,1", "reaction color off: the ring stays white over a unit")
check(P.ringTexture.alpha == 0.5, "opacity changes with the slider")
change("reactionColor", true)
t.fire("UPDATE_MOUSEOVER_UNIT")
check(color() == "1,0,0", "on: the ring takes the game's color for the unit")
mouseover = { 1, 0, 0, dead = true }
t.fire("UPDATE_MOUSEOVER_UNIT")
check(color() == "0.5,0.5,0.5", "a dead unit: gray")
mouseover = nil
frame.scripts.OnUpdate()
check(color() == "1,1,1", "the pointer leaves the unit: white again")

-- Combat.
t.fire("PLAYER_REGEN_DISABLED")
check(frame.width == 64, "combat changes nothing until Grow and pulse is on")
change("combat", true)
check(math.abs(frame.width - 64 * 1.4) < 0.01, "in combat with it on: the ring grows")
check(P.ringTexture.texture == P.RingFile(64 * 1.4, 3), "and its band keeps its width")
t.fire("PLAYER_REGEN_ENABLED")
check(frame.width == 64, "out of combat: back to its size")

-- Red in combat.
check(P.db.combatRed == false, "red in combat starts off")
mouseover = { 0, 1, 0 }
t.fire("UPDATE_MOUSEOVER_UNIT")
t.fire("PLAYER_REGEN_DISABLED")
check(color() == "0,1,0", "off: in combat the ring keeps the unit's color")
change("combatRed", true)
check(color() == "1,0,0", "on: in combat the ring is red over a friendly unit")
t.fire("UPDATE_MOUSEOVER_UNIT")
mouseover = nil
frame.scripts.OnUpdate()
check(color() == "1,0,0", "and stays red as the pointer moves on and off units")
t.fire("PLAYER_REGEN_ENABLED")
check(color() == "1,1,1", "out of combat: back to white")
t.fire("PLAYER_REGEN_DISABLED")
change("combatRed", false)
check(color() == "1,1,1", "turned off in combat: white again")
t.fire("PLAYER_REGEN_ENABLED")

-- Dragging the camera.
local mouselooking = false
IsMouselooking = function() return mouselooking end
local body = P.body
t.cursor = { 400, 300 }
frame.scripts.OnUpdate()
mouselooking = true
frame.scripts.OnUpdate()
check(not body.shown, "the ring hides while you drag")
mouselooking = false
frame.scripts.OnUpdate()
check(not body.shown, "letting go: hidden while the game still reports where the drag began")
t.now = t.now + 0.1
t.cursor = { 500, 400 }
frame.scripts.OnUpdate()
check(body.shown and frame.point[4] == 250, "the report moves: shown on the pointer")
mouselooking = true
frame.scripts.OnUpdate()
mouselooking = false
frame.scripts.OnUpdate()
t.now = t.now + 0.35
frame.scripts.OnUpdate()
check(body.shown, "the pointer really is where the drag began: shown after 0.3 s")
mouselooking = true
frame.scripts.OnUpdate()
change("hideDragging", false)
frame.scripts.OnUpdate()
check(body.shown, "turning it off mid-drag shows the ring")
mouselooking = false
frame.scripts.OnUpdate()

-- Casting.
casting = "duration"
t.fire("UNIT_SPELLCAST_START", "player")
check(not P.castShown, "cast progress off: no cast ring")
change("cast", true)
t.fire("UNIT_SPELLCAST_START", "player")
check(P.castShown == true, "on: the cast ring shows while you cast")
casting = nil
t.fire("UNIT_SPELLCAST_STOP", "player")
check(P.castShown == false, "and clears when the cast ends")
channeling = "channel"
t.fire("UNIT_SPELLCAST_CHANNEL_START", "player")
check(P.castShown == true, "a channel shows too")
channeling = nil
t.fire("UNIT_SPELLCAST_CHANNEL_STOP", "target")
check(P.castShown == true, "another unit's cast events are ignored")

casting = "secret"
local set = W.SetCooldownFromDurationObject
function W:SetCooldownFromDurationObject(duration)
	if duration == "secret" then error("secret argument") end
	self.duration = duration
end
t.fire("UNIT_SPELLCAST_START", "player")
check(P.castShown == false, "a duration the game won't take from an addon hides the cast ring, no error")
W.SetCooldownFromDurationObject = set
casting = nil

-- Off.
change("ring", false)
check(not frame.shown and not P.castShown, "ring off: everything hides")
change("ring", true)
change("cast", false)
check(not P.castShown, "cast progress off clears the cast ring")

t.done()
