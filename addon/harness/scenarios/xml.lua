-- XML as the addons use it: a virtual template applied by CreateFrame.
harness.include("lib/game.lua")
harness.load_addon("Everlook")
game.login()

harness.load_xml_text([[<Ui>
	<Button name="EverlookSampleTemplate" virtual="true" enableMouse="true">
		<Size x="14" y="14"/>
		<Layers>
			<Layer level="ARTWORK">
				<Texture parentKey="texture" file="Interface\AddOns\Everlook\assets\logo.tga"/>
				<FontString parentKey="text" inherits="GameFontHighlight"/>
			</Layer>
		</Layers>
	</Button>
</Ui>]])

local pin = CreateFrame("Button", nil, UIParent, "EverlookSampleTemplate")
local rect = harness.rect(pin)
harness.check("the template gives the button its size", rect.width == 14 and rect.height == 14 or (pin:GetWidth() == 14 and pin:GetHeight() == 14))
harness.check("it takes the mouse, as enableMouse says", pin:IsMouseEnabled())
harness.check("its texture is reached by the parentKey", pin.texture ~= nil)
harness.check("and shows the file the XML names", pin.texture and select(1, pin.texture:GetTexture()) ~= nil and pin.texture:GetTexture():find("logo", 1, true) ~= nil)
harness.check("its text is reached by the parentKey", pin.text ~= nil)

local ok, err = pcall(function()
	harness.load_xml_text([[<Ui><Frame name="X" virtual="true" clampedToScreen="true"/></Ui>]])
end)
harness.check("an attribute outside the supported set is a named gap" .. (ok and "" or ": " .. tostring(err):sub(1, 120)), not ok and tostring(err):find("HARNESS GAP", 1, true) ~= nil and tostring(err):find("clampedToScreen", 1, true) ~= nil)
