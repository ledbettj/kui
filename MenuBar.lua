local addonName, ns = ...

-- Trims the bottom-right corner: all bag buttons, only the backpack (the
-- bag slots and the keyring hidden) or none, and optionally no micro menu
-- (character, spellbook, ... game menu with latency). Both stay where
-- Edit Mode puts them; hidden pieces come back when switched back.
--
-- The bag buttons sit in BagsBar, which lays the shown ones out in a row with
-- dividers between them. Reparenting a button away would leave its divider
-- floating, so the buttons are hidden, kept hidden, and the bar laid out
-- again; "None" hides the whole bar. The
-- bar's width counts hidden buttons too, so it's trimmed to stop its border
-- art framing the empty slots.

ns.bagOptions = { "All", "Backpack only", "None" }

local BAG_SLOTS = {
	"CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
	"CharacterReagentBag0Slot",
	"KeyRingButton",
}

---------------------------------------------------------------------------
-- Hiding buttons inside BagsBar
---------------------------------------------------------------------------

local hiddenByKUI = {} -- button -> whether it was shown before KUI hid it

local function KeepHidden(btn)
	if hiddenByKUI[btn] ~= nil then btn:Hide() end
end

local function SetBagButtonHidden(btn, hidden)
	if hidden then
		if hiddenByKUI[btn] ~= nil then return end
		if not btn.kuiKeepHidden then
			btn:HookScript("OnShow", KeepHidden)
			btn.kuiKeepHidden = true
		end
		hiddenByKUI[btn] = btn:IsShown()
		btn:Hide()
	elseif hiddenByKUI[btn] ~= nil then
		-- Blizzard decides some of these (keyring, reagent bag) are hidden
		-- anyway, so only what was showing comes back
		local wasShown = hiddenByKUI[btn]
		hiddenByKUI[btn] = nil
		btn:SetShown(wasShown)
	end
end

-- Hooks SetSize, not Layout: Blizzard's callbacks kept the original Layout
-- and would skip a hook on it
local function TrimBagsBar(bar)
	if ns.db.menubar.bags ~= "Backpack only" then return end
	if bar:IsHorizontal() then
		bar:SetWidth(MainMenuBarBackpackButton:GetWidth())
	else
		bar:SetHeight(MainMenuBarBackpackButton:GetHeight())
	end
end

local bagsBarHooked = false

local function ApplyBagsBar(M)
	if not bagsBarHooked then
		hooksecurefunc(BagsBar, "SetSize", TrimBagsBar)
		bagsBarHooked = true
	end
	ns.SetHidden(BagsBar, M.bags == "None")
	for _, name in ipairs(BAG_SLOTS) do
		local btn = _G[name]
		if btn then SetBagButtonHidden(btn, M.bags == "Backpack only") end
	end
	BagsBar:Layout()
end

---------------------------------------------------------------------------

-- Hides or restores each piece to match the settings
function ns:ApplyMenuBar()
	local M = ns.db.menubar
	ApplyBagsBar(M)
	ns.SetHidden(MicroMenuContainer, M.hideMicroMenu)
end
