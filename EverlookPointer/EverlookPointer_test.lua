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
local mouselooking = false
IsMouselooking = function() return mouselooking end
local casting, channeling
UnitCastingDuration = function() return casting end
UnitChannelDuration = function() return channeling end

t.load("EverlookPointer")
t.fire("PLAYER_LOGIN")
local P = Everlook:GetAddon("EverlookPointer")
local function change(key, value) t.change("EverlookPointer_" .. key, value) end

check(not (P.db.ring or P.db.reactionColor or P.db.combat or P.db.camera or P.db.cast), "every effect starts off")
check(EverlookPointerFrame == nil, "no ring is made until it's turned on")

change("ring", true)
local frame = EverlookPointerFrame
check(frame and frame.shown and frame.width == 48, "on: a 48 px ring")
t.cursor = { 400, 300 }
frame.scripts.OnUpdate()
check(frame.point[1] == "CENTER" and frame.point[4] == 200 and frame.point[5] == 150,
	"it follows the pointer, in UI units")

change("ringSize", 64)
change("ringOpacity", 0.5)
check(frame.width == 64, "size changes with the slider")

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
t.fire("PLAYER_REGEN_ENABLED")
check(frame.width == 64, "out of combat: back to its size")

-- Camera turning.
mouselooking = true
frame.scripts.OnUpdate()
check(frame.point[2] == UIParent and frame.point[4] == 200, "centering off: the ring stays where the pointer is")
change("camera", true)
frame.scripts.OnUpdate()
check(frame.point[3] == "CENTER", "on: the ring moves to the middle while the camera turns")
mouselooking = false
frame.scripts.OnUpdate()
check(frame.point[3] == "BOTTOMLEFT", "and back to the pointer after")

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
