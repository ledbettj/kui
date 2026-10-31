local addonName, ns = ...

-- Building blocks shared by the unit frames, nameplates, cast bars, action
-- buttons and XP bars: status bars, text, fonts, icons, hiding Blizzard
-- frames and the bordered backdrop.

local FLAT = "Interface\\Buttons\\WHITE8X8"
ns.FLAT_TEXTURE = FLAT

---------------------------------------------------------------------------
-- Icons and numbers
---------------------------------------------------------------------------

-- Trims the built-in border off a spell/item icon texture so it can sit in
-- a square KUI border
function ns.CropIcon(texture)
	texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end

-- Compact number for bars and meters: 9876, 12.3k, 1.2m
function ns.ShortValue(v)
	if v >= 1e6 then
		return format("%.1fm", v / 1e6)
	elseif v >= 1e4 then
		return format("%.1fk", v / 1e3)
	end
	return format("%d", v)
end

---------------------------------------------------------------------------
-- Status bars
---------------------------------------------------------------------------

-- A StatusBar with a background texture (bar.bg). Textures are applied
-- later by StyleBar, so they can change at runtime.
function ns.CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	return bar
end

-- solidBg: leave bar.bg to the caller (a flat empty color) instead of a
-- darkened copy of the bar texture
function ns.StyleBar(bar, textureName, solidBg)
	local atlas, path = ns:GetStatusbar(textureName)
	if atlas then
		bar:GetStatusBarTexture():SetAtlas(atlas)
	else
		bar:SetStatusBarTexture(path)
	end

	if solidBg then return end

	-- Empty portion uses the same art, darkened, so the shading carries across
	if atlas then
		bar.bg:SetAtlas(atlas)
	else
		bar.bg:SetTexture(path)
		bar.bg:SetTexCoord(0, 1, 0, 1)
	end
	bar.bg:SetVertexColor(0.15, 0.15, 0.15)
end

-- r, g, b, a for the background of empty power bars and idle cast bars
function ns:GetEmptyColor()
	local c = ns.db.style.emptyColor
	return c[1], c[2], c[3], ns.db.style.emptyAlpha
end

---------------------------------------------------------------------------
-- Text
---------------------------------------------------------------------------

-- Shared font objects: changing one restyles every fontstring using it.
-- Styling (shadow, color) follows the nameplate font.
local function NewFont(name)
	local fo = CreateFont(name)
	fo:CopyFontObject(SystemFont_NamePlate or GameFontHighlightSmall)
	fo:SetTextColor(1, 1, 1)
	fo:SetShadowOffset(1, -1)
	fo:SetShadowColor(0, 0, 0, 1)
	return fo
end

ns.fonts = {
	normal = NewFont("KUIFontNormal"),
	small = NewFont("KUIFontSmall"),
	aura = NewFont("KUIFontAura"), -- stack counts
}

function ns:UpdateFonts()
	local path = ns:GetFontPath(ns.db.style.font)
	local size = ns.db.style.fontSize
	ns.fonts.normal:SetFont(path, size, "")
	ns.fonts.small:SetFont(path, size - 2, "")
	ns.fonts.aura:SetFont(path, size - 2, "")
end

-- Single-line fontstring on the OVERLAY layer
function ns.CreateText(parent, fontObject, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(fontObject)
	fs:SetJustifyH(justify)
	fs:SetWordWrap(false)
	return fs
end

---------------------------------------------------------------------------
-- Hiding Blizzard frames
---------------------------------------------------------------------------

local hider = CreateFrame("Frame")
hider:Hide()

local originalParents = {} -- frame -> parent before hiding

-- Reparenting to a hidden frame beats Blizzard's own Show calls (frame
-- locks, fades), and restoring the original parent undoes it. Only for
-- frames that aren't protected, or outside combat.
function ns.SetHidden(frame, hidden)
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

---------------------------------------------------------------------------
-- Border
---------------------------------------------------------------------------

-- Applies the configured border and background to any BackdropTemplate
-- frame; small frames get a proportionally thinner border. Returns the
-- inner inset (border + padding) where content starts. Resets the border
-- color, so callers with a custom one (highlights) reapply it after.
function ns:ApplyBackdrop(f, small)
	local style = ns.db.style

	local edge = style.borderSize
	if small then edge = math.max(1, math.floor(edge * 2 / 3 + 0.5)) end
	local path, insetScale = ns:GetBorder(style.border)
	local inset = edge * insetScale

	f:SetBackdrop({
		bgFile = FLAT,
		edgeFile = path,
		edgeSize = edge,
		insets = { left = inset, right = inset, top = inset, bottom = inset },
	})
	f:SetBackdropColor(0, 0, 0, style.bgAlpha)
	local c = style.borderColor
	f:SetBackdropBorderColor(c[1], c[2], c[3], 1)

	return math.floor(inset + 0.5) + style.padding
end

-- Draws the KUI border around target from the outside (target keeps its
-- size) with a see-through background. border: a BackdropTemplate frame.
-- Returns how far the border reaches out from target.
function ns.WrapBorder(border, target, small)
	local inset = ns:ApplyBackdrop(border, small)
	border:SetBackdropColor(0, 0, 0, 0)
	border:ClearAllPoints()
	border:SetPoint("TOPLEFT", target, "TOPLEFT", -inset, inset)
	border:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", inset, -inset)
	return inset
end
