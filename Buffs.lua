local addonName, ns = ...

-- Cosmetic restyle of Blizzard's player buff/debuff frames (top right):
-- square cropped icons in KUI's border, tinted by dispel type for debuffs,
-- and KUI fonts. Layout stays with Edit Mode, and Blizzard keeps handling
-- clicks (right-click to cancel), so nothing here replaces a script.

local TEMP_ENCHANT_COLOR = { 0.6, 0.3, 0.9 } -- weapon oils, poisons, stones

local buttons = {}

-- Blizzard marks debuff types with border atlases rather than a tint, but
-- shares its color table
local debuffInfo = AuraUtil.GetDebuffDisplayInfoTable()

-- The dispel type's color as r, g, b, or nil if there's nothing to go on
local function DebuffColor(buttonInfo)
	local debuffType = buttonInfo and buttonInfo.debuffType
	if ns.IsSecret(debuffType) then return nil end
	local info = debuffInfo[debuffType] or debuffInfo.None
	if info and info.color then return info.color:GetRGB() end
end

-- Called after Blizzard's Update (with its buttonInfo), which
-- re-shows its own border art
local function UpdateBorderColor(b, buttonInfo)
	if b.auraType == "Debuff" or b.auraType == "DeadlyDebuff" then
		local r, g, bl = DebuffColor(buttonInfo or b.buttonInfo)
		if r then
			b.kuiBorder:SetBackdropBorderColor(r, g, bl, 1)
			return
		end
	end
	local c = b.auraType == "TempEnchant" and TEMP_ENCHANT_COLOR or ns.db.style.borderColor
	b.kuiBorder:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

-- BackdropTemplate's own handler does math on the size, but the border follows
-- Blizzard's icon, whose size can be secret in combat. The art catches up on
-- the next readable change.
local function OnBorderSizeChanged(border)
	if not ns.IsSecret(border:GetWidth()) and not ns.IsSecret(border:GetHeight()) then
		border:SetupTextureCoordinates()
	end
end

local function StyleButton(b)
	ns.CropIcon(b.Icon)
	-- Blizzard shows/hides these per aura type; alpha keeps them invisible
	-- whatever it does
	b.DebuffBorder:SetAlpha(0)
	b.TempEnchantBorder:SetAlpha(0)

	-- Outside the icon, so the duration text below stays where Blizzard put it.
	-- Setting a backdrop measures the frame, which can't be done while secret.
	if ns.IsSecret(b.kuiBorder:GetWidth()) then
		ns.pendingLayout = true -- ns:ApplyLayout restyles these when combat ends
	else
		ns.WrapBorder(b.kuiBorder, b.Icon, true)
	end
	UpdateBorderColor(b)

	-- Blizzard recolors the duration every tick, so only the font is ours
	b.Duration:SetFontObject(ns.fonts.small)
	b.Count:SetFontObject(ns.fonts.normal)
end

function ns:StyleBuffs()
	if not next(buttons) then return end -- restyling is off
	for b in pairs(buttons) do
		StyleButton(b)
	end
	if InCombatLockdown() then
		ns.pendingLayout = true -- ns:ApplyLayout restyles these when combat ends
		return
	end
	BuffFrame:SetScale(ns.db.buffs.scale)
	DebuffFrame:SetScale(ns.db.buffs.scale)
end

-- Only when enabled at login (see the lifecycle notes in Core.lua)
function ns:InitBuffs()
	if not ns.db.buffs.enabled then return end

	-- Each frame creates its fixed pool of buttons at load
	for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
		for _, b in ipairs(frame and frame.auraFrames or {}) do
			-- Private aura anchors share the list but aren't buttons
			if not b.isAuraAnchor and b.Icon then
				buttons[b] = true
				b.kuiBorder = CreateFrame("Frame", nil, b, "BackdropTemplate")
				b.kuiBorder:SetFrameLevel(b:GetFrameLevel() + 1)
				b.kuiBorder:SetScript("OnSizeChanged", OnBorderSizeChanged)
				hooksecurefunc(b, "Update", UpdateBorderColor)
			end
		end
	end

	ns:StyleBuffs()
end
