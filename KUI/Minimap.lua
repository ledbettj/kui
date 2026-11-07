local addonName, ns = ...

-- Optional square minimap in KUI's border: square mask, Blizzard's ring,
-- compass and top banner art faded out (the zone text stays). Reports the
-- shape through GetMinimapShape, which minimap button addons use to lay
-- their buttons along the edge. Switching back to Blizzard restores it all.
--
-- The buttons around the map (Blizzard's and other addons') carry round
-- ring art too. Rings that are their own texture are faded wherever they
-- turn up; the zoom buttons and day/night sun, whose ring is part of the
-- button art, are hidden, with the mouse wheel zooming instead.
--
-- The round mask is an atlas set by MinimapCluster:UpdateMinimapConfig (rerun
-- whenever the rotate setting changes, so the square mask goes back on after
-- it), and the zoom buttons appear on hover.

local SQUARE_MASK = "Interface\\Buttons\\WHITE8X8"

-- Ring and dark disc art used by minimap buttons, matched by file ID
local RING_FILES = {
	"Interface\\Minimap\\MiniMap-TrackingBorder",
	"Interface\\Minimap\\UI-Minimap-Background",
	"Interface\\TimeManager\\ClockBackground",
}
-- How deep to look below the minimap for button art
local SCAN_DEPTH = 3

local border
local blizzardArt = {} -- faded with alpha: the compass is shown/hidden by the rotate setting
local hiddenButtons = {}
local ringIDs = {}
local fadedRings = {} -- texture -> true
local squared -- only undo what was changed, so the default look is never touched

local function IsSquare()
	return ns.db.minimap.style == "Square"
end

---------------------------------------------------------------------------
-- Button rings
---------------------------------------------------------------------------

local function FadeRings(frame, depth)
	for _, region in ipairs({ frame:GetRegions() }) do
		-- The alarm glow shares the clock's art but only shows when it fires
		if region:IsObjectType("Texture") and region ~= TimeManagerAlarmFiredTexture
			and ringIDs[region:GetTextureFileID() or 0] then
			region:SetAlpha(0)
			fadedRings[region] = true
		end
	end
	if depth < SCAN_DEPTH then
		for _, child in ipairs({ frame:GetChildren() }) do
			FadeRings(child, depth + 1)
		end
	end
end

local function RestoreRings()
	for region in pairs(fadedRings) do
		region:SetAlpha(1)
	end
	wipe(fadedRings)
end

-- Buttons appear later too: the load-on-demand clock, other addons' icons
local function Rescan()
	if squared then FadeRings(Minimap, 0) end
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------

-- The round mask depends on the rotate setting, so Blizzard puts it back
local function SetMask(square)
	if square then
		Minimap:SetMaskTexture(SQUARE_MASK)
	else
		MinimapCluster:UpdateMinimapConfig()
	end
end

function ns:LayoutMinimap()
	if not border then return end
	local square = IsSquare()
	if square or squared then
		SetMask(square)
		for _, art in ipairs(blizzardArt) do
			art:SetAlpha(square and 0 or 1)
		end
		for _, button in ipairs(hiddenButtons) do
			ns.SetHidden(button, square)
		end
		squared = square
		if square then Rescan() else RestoreRings() end
	end

	border:SetShown(square)
	if square then ns.WrapBorder(border, Minimap) end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

function ns:InitMinimap()
	border = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
	border:SetFrameLevel(Minimap:GetFrameLevel())
	-- pairs skips any the client doesn't have
	local art = {
		MinimapCluster.BorderTop, MinimapCompassTexture, MinimapCompassTextureUnderlay,
	}
	for _, region in pairs(art) do
		blizzardArt[#blizzardArt + 1] = region
	end
	local buttons = { GameTimeFrame, Minimap.ZoomIn, Minimap.ZoomOut }
	for _, button in pairs(buttons) do
		hiddenButtons[#hiddenButtons + 1] = button
	end

	local probe = UIParent:CreateTexture()
	for _, path in ipairs(RING_FILES) do
		probe:SetTexture(path)
		local id = probe:GetTextureFileID()
		if id then ringIDs[id] = true end
	end
	probe:SetTexture(nil)

	-- Blizzard redoes the frame and mask when the rotate setting changes
	hooksecurefunc(MinimapCluster, "UpdateMinimapConfig", function()
		if IsSquare() then Minimap:SetMaskTexture(SQUARE_MASK) end
	end)

	-- Leave it alone if another addon already claims the shape
	if not GetMinimapShape then
		function GetMinimapShape()
			return IsSquare() and "SQUARE" or "ROUND"
		end
	end

	EventUtil.ContinueOnAddOnLoaded("Blizzard_TimeManager", Rescan)
	local dbIcon = LibStub and LibStub("LibDBIcon-1.0", true)
	if dbIcon then
		dbIcon.RegisterCallback(ns, "LibDBIcon_IconCreated", Rescan)
	end
	-- Addons that build their buttons once the world has loaded
	C_Timer.After(3, Rescan)

	ns:LayoutMinimap()
end
