local addonName, ns = ...

-- Cosmetic restyle of Blizzard's player buff/debuff frames (top right):
-- square cropped icons in KUI's border, tinted by dispel type for debuffs,
-- and KUI fonts. Layout stays with Edit Mode, and Blizzard keeps handling
-- clicks (right-click to cancel), so nothing here replaces a script.

local TEMP_ENCHANT_COLOR = { 0.6, 0.3, 0.9 } -- weapon oils, poisons, stones

local buttons = {}

-- Called after Blizzard's Update, which re-shows its own border art
local function UpdateBorderColor(b)
	if b.auraType == "Debuff" or b.auraType == "DeadlyDebuff" then
		-- Blizzard has just tinted its own (invisible) border by dispel type;
		-- its color table is file-local, so copy the color from the texture
		local r, g, bl = b.DebuffBorder:GetVertexColor()
		b.kuiBorder:SetBackdropBorderColor(r, g, bl, 1)
		return
	end
	local c = b.auraType == "TempEnchant" and TEMP_ENCHANT_COLOR or KUIDB.style.borderColor
	b.kuiBorder:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

local function StyleButton(b)
	ns.CropIcon(b.Icon)
	-- Blizzard shows/hides these per aura type; alpha keeps them invisible
	-- whatever it does
	b.DebuffBorder:SetAlpha(0)
	b.TempEnchantBorder:SetAlpha(0)

	-- Outside the icon, so the duration text below stays where Blizzard put it
	ns.WrapBorder(b.kuiBorder, b.Icon, true)
	UpdateBorderColor(b)

	-- Blizzard recolors the duration every tick, so only the font is ours
	b.Duration:SetFontObject(ns.fonts.small)
	b.Count:SetFontObject(ns.fonts.normal)
end

function ns:StyleBuffs()
	for b in pairs(buttons) do
		StyleButton(b)
	end
end

-- Only when enabled at login (see the lifecycle notes in Core.lua)
function ns:InitBuffs()
	if not KUIDB.buffs.enabled then return end

	-- Each frame creates its fixed pool of buttons at load
	for _, frame in ipairs({ BuffFrame, DebuffFrame }) do
		for _, b in ipairs(frame and frame.auraFrames or {}) do
			-- Private aura anchors share the list but aren't buttons
			if not b.isAuraAnchor and b.Icon then
				buttons[b] = true
				b.kuiBorder = CreateFrame("Frame", nil, b, "BackdropTemplate")
				b.kuiBorder:SetFrameLevel(b:GetFrameLevel() + 1)
				hooksecurefunc(b, "Update", UpdateBorderColor)
			end
		end
	end

	ns:StyleBuffs()
end
