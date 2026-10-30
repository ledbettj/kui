local addonName, ns = ...

-- Hides the button column beside each chat window (scroll up/down/bottom,
-- plus the chat menu, channel and friends buttons that live in
-- ChatFrame1's column) and the text-to-speech button.

local SetHidden = ns.SetHidden

-- Covers temporary (whisper) windows too, which are created on demand
function ns:ApplyChat()
	local hidden = ns.db.chat.hideButtons
	for _, name in ipairs(CHAT_FRAMES) do
		local chatFrame = _G[name]
		if chatFrame then SetHidden(chatFrame.buttonFrame, hidden) end
	end
	SetHidden(TextToSpeechButtonFrame, hidden)
end

function ns:InitChat()
	hooksecurefunc("FCF_OpenTemporaryWindow", function() ns:ApplyChat() end)
	ns:ApplyChat()
end
