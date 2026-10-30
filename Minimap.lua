local addonName, ns = ...

-- Optional square minimap in KUI's border: square mask, Blizzard's ring,
-- compass and top banner art faded out (the zone text stays). Reports the
-- shape through GetMinimapShape, which minimap button addons use to lay
-- their buttons along the edge. Switching back to Blizzard restores it all.

local ROUND_MASK = "Textures\\MinimapMask"
local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

local border
local blizzardArt = {} -- faded with alpha: the compass is shown/hidden by the rotate setting
local squared -- only undo what was changed, so the default look is never touched

local function IsSquare()
	return KUIDB.minimap.style == "Square"
end

function ns:LayoutMinimap()
	if not border then return end
	local square = IsSquare()
	if square or squared then
		Minimap:SetMaskTexture(square and SQUARE_MASK or ROUND_MASK)
		for _, art in ipairs(blizzardArt) do
			art:SetAlpha(square and 0 or 1)
		end
		squared = square
	end

	border:SetShown(square)
	if square then
		-- Wraps the map from outside so the map keeps its size
		local inset = ns:ApplyBackdrop(border)
		border:SetBackdropColor(0, 0, 0, 0)
		border:ClearAllPoints()
		border:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -inset, inset)
		border:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", inset, -inset)
	end
end

function ns:InitMinimap()
	if not Minimap or not MinimapCluster then return end

	border = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
	border:SetFrameLevel(Minimap:GetFrameLevel())
	for _, art in pairs({ MinimapBorder, MinimapCluster.BorderTop, MinimapNorthTag, MinimapCompassTexture }) do
		blizzardArt[#blizzardArt + 1] = art
	end

	-- Leave it alone if another addon already claims the shape
	if not GetMinimapShape then
		function GetMinimapShape()
			return IsSquare() and "SQUARE" or "ROUND"
		end
	end

	ns:LayoutMinimap()
end
