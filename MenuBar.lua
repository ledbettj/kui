local addonName, ns = ...

-- Trims the bottom-right corner: optionally only the backpack button
-- (the four bag slots and the keyring hidden), and optionally no micro
-- menu (character, spellbook, ... game menu with latency). Both stay where
-- Edit Mode puts them; hidden pieces come back when unchecked.

local BAG_SLOTS = { "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton" }

function ns:ApplyMenuBar()
	local M = KUIDB.menubar
	for _, name in ipairs(BAG_SLOTS) do
		ns.SetHidden(_G[name], M.singleBag)
	end
	ns.SetHidden(MicroMenuContainer, M.hideMicroMenu)
end
