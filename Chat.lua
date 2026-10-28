local addonName, ns = ...

-- Hides the button column beside each chat window (scroll up/down/bottom,
-- plus the chat menu, channel and friends buttons that live in
-- ChatFrame1's column) and the text-to-speech button. Reparenting to a
-- hidden frame beats Blizzard's own Show calls (frame locks, fades), and
-- restoring the original parent undoes it.

local hider = CreateFrame("Frame")
hider:Hide()

local originalParents = {} -- frame -> parent before hiding

local function SetHidden(frame, hidden)
	if not frame then return end
	if hidden then
		if not originalParents[frame] then
			originalParents[frame] = frame:GetParent()
			frame:SetParent(hider)
		end
	elseif originalParents[frame] then
		frame:SetParent(originalParents[frame])
		originalParents[frame] = nil
	end
end

-- Covers temporary (whisper) windows too, which are created on demand
function ns:ApplyChat()
	local hidden = KUIDB.chat.hideButtons
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
