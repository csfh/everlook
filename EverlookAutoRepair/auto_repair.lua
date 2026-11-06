local AutoRepair = Everlook:NewAddon("EverlookAutoRepair", {
	label = "Auto Repair",
	defaults = {
		repair = true,
		guildFunds = false,
	},
})

-- Game functions this addon needs; EverlookQA checks they exist.
EverlookQA:Expect("EverlookAutoRepair", {
	"CanMerchantRepair",
	"GetRepairAllCost",
	"RepairAllItems",
	"GetMoney",
	"CanGuildBankRepair",
	"GetGuildBankWithdrawMoney",
	"GetGuildBankMoney",
	"IsShiftKeyDown",
})

function AutoRepair:OnInitialize()
	local page = EverlookPreferences:NewPage(self, "Vendors & Mail")
	page:Checkbox("repair", "Repair automatically",
		"Repair all gear when a repair vendor opens. Hold Shift to skip.")
	page:Checkbox("guildFunds", "Use guild funds first",
		"Pay from the guild bank when your allowance and the bank both cover the cost. Needs Repair automatically.")
end

function AutoRepair:OnEnable()
	self:RegisterEvent("MERCHANT_SHOW")
end

local function guildCanPay(cost)
	if not (CanGuildBankRepair and CanGuildBankRepair() and GetGuildBankWithdrawMoney and GetGuildBankMoney) then
		return false
	end
	local allowance, funds = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
	return (allowance == -1 or allowance >= cost) and funds >= cost
end

function AutoRepair:MERCHANT_SHOW()
	if not self.db.repair or IsShiftKeyDown() then return end
	if not (CanMerchantRepair and CanMerchantRepair()) then return end

	local cost, needed = GetRepairAllCost()
	if not needed or not cost or cost <= 0 then return end

	if self.db.guildFunds and guildCanPay(cost) then
		RepairAllItems(true)
		self:Print("Repaired for " .. Everlook.FormatMoney(cost) .. " from guild funds.")
	elseif GetMoney() >= cost then
		RepairAllItems(false)
		self:Print("Repaired for " .. Everlook.FormatMoney(cost) .. ".")
	else
		self:Print("Not enough gold to repair.")
	end
end
