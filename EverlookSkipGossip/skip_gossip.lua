local SkipGossip = Everlook:NewAddon("EverlookSkipGossip", {
	label = "Skip Gossip",
	defaults = {
		skip = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookSkipGossip", {
	"C_GossipInfo.GetOptions",
	"C_GossipInfo.GetNumAvailableQuests",
	"C_GossipInfo.GetNumActiveQuests",
	"C_GossipInfo.ForceGossip",
	"C_GossipInfo.SelectOptionByIndex",
	"Enum.GossipOptionStatus.Available",
	"GetTime",
	"IsShiftKeyDown",
	"bit.band",
}, {
	"issecretvalue",
})

-- An option that leads back to the same window is taken once, not again and again.
local REPEAT_SECONDS = 2

local last -- { name, at } of the option taken last

-- GossipOptionRecFlags (GossipConstantsDocumentation.lua, 12.0.0): QuestLabelPrepend = 1,
-- PlayMovieLabelPrepend = 4.
local QUEST_OR_MOVIE = 1 + 4

local function secret(value)
	return issecretvalue and issecretvalue(value)
end

function SkipGossip:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Quests")
	page:Checkbox("skip", "Skip single-option gossip",
		"When an NPC has one option and no quests, such as a vendor's shop or a flight master's map, go straight to it. Quests, locked options and NPCs that insist on talking are left to you. Hold Shift to read the window.")
end

function SkipGossip:OnEnable()
	self:RegisterEvent("GOSSIP_SHOW")
end

-- The test GossipFrameSharedMixin:HandleShow (Blizzard_UIPanels_Game/Shared/GossipFrameShared.lua,
-- 12.0.0) makes before going straight to an option the server flags selectOptionWhenOnlyOption,
-- without needing the flag. Anything the client can't report leaves the window open.
function SkipGossip.OnlyOption()
	local gossip = C_GossipInfo
	if not (gossip and gossip.GetOptions and gossip.GetNumAvailableQuests and gossip.GetNumActiveQuests
		and gossip.ForceGossip and gossip.SelectOptionByIndex) then return nil end
	if not (Enum and Enum.GossipOptionStatus and Enum.GossipOptionStatus.Available) then return nil end
	if gossip.GetNumAvailableQuests() ~= 0 or gossip.GetNumActiveQuests() ~= 0 or gossip.ForceGossip() ~= false then
		return nil
	end
	local options = gossip.GetOptions()
	if type(options) ~= "table" or #options ~= 1 then return nil end
	local option = options[1]
	if secret(option.status) or option.status ~= Enum.GossipOptionStatus.Available then return nil end
	if option.failureDescription or secret(option.orderIndex) or type(option.orderIndex) ~= "number" then return nil end
	-- The game's own frame already takes an option flagged like this.
	if option.selectOptionWhenOnlyOption ~= false then return nil end
	-- Options the game labels as a quest step or a movie are left to you.
	local flags = option.flags
	if secret(flags) or type(flags) ~= "number" or not (bit and bit.band) then return nil end
	if bit.band(flags, QUEST_OR_MOVIE) ~= 0 then return nil end
	return option
end

function SkipGossip:GOSSIP_SHOW()
	if not self.db.skip or IsShiftKeyDown() then return end
	local option = SkipGossip.OnlyOption()
	if not option then return end
	local name = not secret(option.name) and option.name or nil
	local now = GetTime()
	if last and last.name == name and now - last.at < REPEAT_SECONDS then return end
	last = { name = name, at = now }
	C_GossipInfo.SelectOptionByIndex(option.orderIndex)
end
