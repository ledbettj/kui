local addonName, ns = ...

-- Incoming heal prediction: translucent segments extending the health fill,
-- the player's own heals first, then everyone else's. Uses the client's
-- native heal data, so no LibHealComm needed. KUI has its own toggle rather
-- than Blizzard's unitFramesDisplayIncomingHeals CVar. Never extends past
-- full health.
--
-- Health and heals are secret, so nothing can be sized from them. Each
-- segment is a status bar as wide as the health bar, starting where
-- the previous fill ends, and the engine draws the secret amount as its
-- fill; Blizzard's heal prediction calculator splits the player's heals
-- from others' and clamps them to missing health, and the health bar
-- clips anything past its edge.

local ALPHA = 0.6

local function CreateSegment(bar)
	local seg = CreateFrame("StatusBar", nil, bar)
	seg:SetStatusBarTexture(ns.FLAT_TEXTURE)
	-- At the health bar's own level, so its fill (ARTWORK) stays under the
	-- name and health text (OVERLAY) rather than covering them
	seg:SetUsingParentLevel(true)
	seg:Hide()
	return seg
end

function ns.CreateHealPrediction(f)
	f.healPrediction = {
		mine = CreateSegment(f.health),
		others = CreateSegment(f.health),
	}
	f.health:SetClipsChildren(true)
	local calc = CreateUnitHealPredictionCalculator()
	calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
	calc:SetIncomingHealOverflowPercent(1) -- a multiplier: 1 stops at full health, 0 hides all heals
	f.healCalculator = calc
end

-- Matches the health bar's texture so the segments carry the same shading
function ns.StyleHealPrediction(f)
	local hp = f.healPrediction
	if not hp then return end
	local atlas, path = ns:GetStatusbar(ns.db.style.healthTexture)
	for key, seg in pairs(hp) do
		local c = ns:GetColor("heal", key)
		if atlas then
			seg:GetStatusBarTexture():SetAtlas(atlas)
		else
			seg:SetStatusBarTexture(path)
		end
		seg:SetStatusBarColor(c[1], c[2], c[3], ALPHA)
	end
end

local function HideSegments(hp)
	hp.mine:Hide()
	hp.others:Hide()
end

-- A full-width bar after previous, filled to amount of maxHealth;
-- returns its fill for the next segment to follow
local function PlaceSegment(seg, previous, width, maxHealth, amount)
	seg:ClearAllPoints()
	seg:SetPoint("TOPLEFT", previous, "TOPRIGHT")
	seg:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT")
	seg:SetWidth(width)
	seg:SetMinMaxValues(0, maxHealth)
	seg:SetValue(amount)
	seg:Show()
	return seg:GetStatusBarTexture()
end

-- Called from ns.UpdateHealth, on UNIT_HEAL_PREDICTION, and after layout
-- changes the bar's width
function ns.UpdateHealPrediction(f)
	local hp = f.healPrediction
	if not hp then return end

	local unit = f.unit
	if not ns.db.healPrediction.enabled or not UnitExists(unit) or UnitIsDeadOrGhost(unit) then
		return HideSegments(hp)
	end

	local calc = f.healCalculator
	UnitGetDetailedHealPrediction(unit, "player", calc)
	local _, mine, others = calc:GetIncomingHeals()
	local maxHealth, width = UnitHealthMax(unit), f.health:GetWidth()

	-- Anchored fresh each time: swapping the bar texture can replace the
	-- fill texture object
	local previous = PlaceSegment(hp.mine, f.health:GetStatusBarTexture(), width, maxHealth, mine)
	PlaceSegment(hp.others, previous, width, maxHealth, others)
end
