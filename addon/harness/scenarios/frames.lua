-- The frame model on its own: anchors, strata and levels, the mouse.
local root = CreateFrame("Frame", "Root")
root:SetSize(400, 300)
root:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -50)

local back = CreateFrame("Button", "Back", root)
back:SetAllPoints(root)
local front = CreateFrame("Button", "Front", root)
front:SetSize(100, 40)
front:SetPoint("TOPLEFT", root, "TOPLEFT", 10, -10)

local r = harness.rect(front)
harness.check("an offset anchor puts a frame 10 right and 10 down of its parent", r.left == 110 and r.top == 60 and r.width == 100 and r.height == 40)
harness.check("a child is one level above its parent, in the same strata", front:GetFrameLevel() == root:GetFrameLevel() + 1 and front:GetFrameStrata() == root:GetFrameStrata())
harness.check("a table that is not a frame is refused as an anchor", not pcall(front.SetPoint, front, "TOP", {}, "TOP"))
harness.check("a method the type has not is nil", front.SetFoo == nil and root.SetText == nil)

local cx, cy = harness.center(front)
harness.check("the later sibling takes the mouse over the one it covers", harness.hit(cx, cy) == front)
front:EnableMouse(false)
harness.check("with the mouse off it falls through to the one below", harness.hit(cx, cy) == back)
front:EnableMouse(true)
front:SetFrameLevel(1)
harness.check("a lower level goes below", harness.hit(cx, cy) == back)

local clicks = 0
back:SetScript("OnClick", function() clicks = clicks + 1 end)
harness.click(300, 200)
harness.check("a click on a button runs its OnClick", clicks == 1)

local entered, left = 0, 0
back:SetScript("OnEnter", function() entered = entered + 1 end)
back:SetScript("OnLeave", function() left = left + 1 end)
harness.move(5, 5)
entered, left = 0, 0
harness.move(300, 200)
harness.move(5, 5)
harness.check("moving the pointer in and out runs OnEnter and OnLeave once each", entered == 1 and left == 1)

root:SetClipsChildren(true)
local overflow = CreateFrame("Button", "Overflow", root)
overflow:SetSize(50, 50)
overflow:SetPoint("TOPLEFT", root, "TOPLEFT", 500, 0)
harness.check("a child outside a clipping parent takes no mouse", harness.hit(650, 75) == nil)

local group = root:CreateAnimationGroup()
local fade = group:CreateAnimation("Alpha")
fade:SetFromAlpha(1)
fade:SetToAlpha(0)
fade:SetDuration(1)
local finished = false
group:SetScript("OnFinished", function() finished = true end)
group:Play()
harness.advance(0.5)
harness.check("half way through an alpha animation the frame is half shown", math.abs(root:GetEffectiveAlpha() - 0.5) < 0.05)
harness.advance(0.6)
harness.check("when it ends it is finished, and the frame is back to its own alpha", finished and root:GetEffectiveAlpha() == 1)

local fired = 0
C_Timer.After(2, function() fired = fired + 1 end)
harness.advance(1.9)
harness.check("a timer does not fire early", fired == 0)
harness.advance(0.2)
harness.check("and does at its time", fired == 1)
