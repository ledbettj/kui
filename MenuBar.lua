local addonName, ns = ...

-- Trims the bottom-right corner: all bag buttons, only the backpack (the
-- four bag slots and the keyring hidden) or none, and optionally no micro
-- menu (character, spellbook, ... game menu with latency). Both stay where
-- Edit Mode puts them; hidden pieces come back when switched back.

ns.bagOptions = { "All", "Backpack only", "None" }

local BAG_SLOTS = {
	"CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot", "KeyRingButton",
}

-- Hides or restores each piece to match the settings
function ns:ApplyMenuBar()
	local M = KUIDB.menubar
	for _, name in ipairs(BAG_SLOTS) do
		ns.SetHidden(_G[name], M.bags ~= "All")
	end
	ns.SetHidden(MainMenuBarBackpackButton, M.bags == "None")
	ns.SetHidden(MicroMenuContainer, M.hideMicroMenu)
end
