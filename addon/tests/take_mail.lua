-- Take mail: takes the money and the attached items from the open mailbox, one letter at a time, and that letter leaves the inbox.
return function(root, check, lib)
	local load_files = lib.load_files
	local addon, play, fire = load_files({ "world", "module", "take_mail" })
	local taken = {}
	local mails = {
		{ money = 5, cod = 0, items = 1 },
		{ money = 2, cod = 0, items = 0 },
	}
	local function compact()
		local kept = {}
		for index = 1, #mails do
			if not mails[index].taken then
				kept[#kept + 1] = mails[index]
			end
		end
		mails = kept
	end
	play.GetInboxNumItems = function()
		compact()
		return #mails
	end
	play.GetInboxHeaderInfo = function(index)
		local mail = mails[index]
		if not mail then
			return
		end
		return nil, nil, nil, nil, mail.money, mail.cod, 1, mail.items
	end
	play.TakeInboxMoney = function(index)
		taken[#taken + 1] = mails[index].money
		mails[index].money = 0
		if mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	play.TakeInboxItem = function(index)
		taken[#taken + 1] = "item"
		mails[index].items = mails[index].items - 1
		if mails[index].money <= 0 and mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	addon.module.set("take_mail", "enabled", true)
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("one tick takes the money and leaves the attached item", taken[1] == 5 and #taken == 1)
	play.tickers[#play.tickers].callback()
	check("the next tick takes the item that was still attached", taken[2] == "item" and #taken == 2)
	play.tickers[#play.tickers].callback()
	check("plain mail is taken again after the inbox compacts", taken[3] == 2 and #taken == 3)
	mails = { { money = 9, cod = 4, items = 0 }, { money = 3, cod = 0, items = 0 } }
	taken = {}
	play.tickers[#play.tickers].callback()
	check("cash on delivery stays in the mailbox", taken[1] == 3 and #taken == 1)
	play.IsShiftKeyDown = function()
		return true
	end
	local before_shift = #taken
	play.tickers[#play.tickers].callback()
	check("Shift stops taking mail", #taken == before_shift and play.tickers[#play.tickers].cancelled)
	play.IsShiftKeyDown = function()
		return false
	end
	taken = {}
	fire("MAIL_SHOW")
	fire("MAIL_CLOSED")
	play.tickers[#play.tickers].callback()
	check("closing the mailbox stops taking mail", #taken == 0)
	mails = { { money = 0, cod = 0, items = 2 } }
	taken = {}
	local slots = {}
	play.TakeInboxItem = function(index, slot)
		slots[#slots + 1] = slot
		mails[index].items = mails[index].items - 1
		if mails[index].items <= 0 then
			mails[index].taken = true
		end
	end
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("one attachment is taken per tick", #slots == 1 and slots[1] == 1 and mails[1].items == 1)
	play.tickers[#play.tickers].callback()
	check("the next tick takes the attachment that slid forward", #slots == 2 and slots[2] == 1)
	mails = { { money = 4, cod = 0, items = 0 } }
	taken = {}
	local pending = true
	local secret_pending = {}
	play.C_Mail = {
		IsCommandPending = function()
			return pending
		end,
	}
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("a pending mail command waits", #taken == 0 and not play.tickers[#play.tickers].cancelled)
	pending = false
	play.tickers[#play.tickers].callback()
	check("the money is taken once the command finishes", taken[1] == 4 and #taken == 1)
	mails = { { money = 7, cod = 0, items = 0 } }
	taken = {}
	play.issecretvalue = function(value)
		return rawequal(value, secret_pending)
	end
	play.C_Mail.IsCommandPending = function()
		return secret_pending
	end
	fire("MAIL_SHOW")
	play.tickers[#play.tickers].callback()
	check("a secret mail command state waits", #taken == 0 and not play.tickers[#play.tickers].cancelled)
	play.issecretvalue = nil
	play.C_Mail = nil
end
