local addonName, ns = ...

-- Cosmetic restyle of Blizzard's player buff/debuff frames (top right):
-- square cropped icons in KUI's border, tinted by dispel type for debuffs,
-- and KUI fonts. Layout stays with Edit Mode, and Blizzard keeps handling
-- clicks (right-click to cancel), so nothing here replaces a script.

local TEMP_ENCHANT_COLOR = { 0.6, 0.3, 0.9 } -- weapon oils, poisons, stones

local buttons = {}

-- Forever marks debuff types with border atlases rather than a tint, but
-- shares its color table; nil on TBC, which tints
local debuffInfo = ns.isForever and AuraUtil.GetDebuffDisplayInfoTable()

-- The dispel type's color as r, g, b, or nil if there's nothing to go on
local function DebuffColor(b, buttonInfo)
	if not debuffInfo then
		-- TBC: Blizzard has just tinted its own (invisible) border by dispel
		-- type; its color table is file-local, so copy it from the texture
		return b.DebuffBorder:GetVertexColor()
	end
	local debuffType = buttonInfo and buttonInfo.debuffType
	if ns.IsSecret(debuffType) then return nil end
	local info = debuffInfo[debuffType] or debuffInfo.None
	if info and info.color then return info.color:GetRGB() end
end

-- Called after Blizzard's Update (with its buttonInfo on forever), which
-- re-shows its own border art
local function UpdateBorderColor(b, buttonInfo)
	if b.auraType == "Debuff" or b.auraType == "DeadlyDebuff" then
		local r, g, bl = DebuffColor(b, buttonInfo or b.buttonInfo)
		if r then
			b.kuiBorder:SetBackdropBorderColor(r, g, bl, 1)
			return
		end
	end
	local c = b.auraType == "TempEnchant" and TEMP_ENCHANT_COLOR or ns.db.style.borderColor
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
	if not ns.db.buffs.enabled then return end

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
