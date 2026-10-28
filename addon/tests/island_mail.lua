-- Island mail: tells you when new mail arrives, and what is waiting once you open the mailbox.
return function(_, check, lib)
	local island_world, notice_key = lib.island_world, lib.notice_key
	do
		local addon, env, event = island_world()
		local waiting = false
		env.HasNewMail = function() return waiting end
		addon.module.set("island", "enabled", true)
		addon.module.set("island", "feed_mail", true)
		waiting = true
		event("UPDATE_PENDING_MAIL")
		check("new mail starts with the plain detail", notice_key(addon, "mail:new").detail == "Unread mail is waiting")
		local headers = { { money = 15000, has_item = 1 }, { money = 0, has_item = 0 }, { money = 0, has_item = 2 } }
		env.GetInboxNumItems = function() return #headers end
		env.GetInboxHeaderInfo = function(index)
			local row = headers[index]
			return nil, nil, "Sender", "Subject", row.money, 0, 30, row.has_item
		end
		event("MAIL_INBOX_UPDATE")
		local notice = notice_key(addon, "mail:new")
		check("opening the mailbox says what is waiting", notice.detail == "3 messages, 2 with attachments, 1g 50s")
		check("that update does not toast again", #addon.island.view().toasts == 0 or notice.presentation == "inbox")
		env.GetInboxNumItems = function() return 0 end
		event("MAIL_INBOX_UPDATE")
		check("an empty mailbox keeps the last summary", notice_key(addon, "mail:new").detail == "3 messages, 2 with attachments, 1g 50s")
	end
end
