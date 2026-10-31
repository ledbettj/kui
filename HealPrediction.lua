local addonName, ns = ...

-- Incoming heal prediction: translucent segments extending the health fill,
-- the player's own heals first, then everyone else's. Uses the client's
-- native heal data, so no LibHealComm needed. KUI has its own toggle rather
-- than Blizzard's unitFramesDisplayIncomingHeals CVar. Never extends past
-- full health.
--
-- TBC: the segments are textures sized from the heal amounts.
-- Forever: health and heals are secret, so nothing can be sized from them.
-- Each segment is a status bar as wide as the health bar, starting where
-- the previous fill ends, and the engine draws the secret amount as its
-- fill; Blizzard's heal prediction calculator splits the player's heals
-- from others' and clamps them to missing health, and the health bar
-- clips anything past its edge.

local ALPHA = 0.6

local function CreateSegment(bar)
	if ns.hasSecrets then
		local seg = CreateFrame("StatusBar", nil, bar)
		seg:SetStatusBarTexture(ns.FLAT_TEXTURE)
		-- At the health bar's own level, so its fill (ARTWORK) stays under
		-- the name and health text (OVERLAY) rather than covering them
		seg:SetUsingParentLevel(true)
		seg:Hide()
		return seg
	end
	-- Above the health fill (ARTWORK 0), below the name/health text (OVERLAY)
	local seg = bar:CreateTexture(nil, "ARTWORK", nil, 1)
	seg:Hide()
	return seg
end

function ns.CreateHealPrediction(f)
	f.healPrediction = {
		mine = CreateSegment(f.health),
		others = CreateSegment(f.health),
	}
	if ns.hasSecrets then
		f.health:SetClipsChildren(true)
		local calc = CreateUnitHealPredictionCalculator()
		calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MissingHealth)
		calc:SetIncomingHealOverflowPercent(0)
		f.healCalculator = calc
	end
end

-- Matches the health bar's texture so the segments carry the same shading
function ns.StyleHealPrediction(f)
	local hp = f.healPrediction
	if not hp then return end
	local atlas, path = ns:GetStatusbar(ns.db.style.healthTexture)
	for key, seg in pairs(hp) do
		local c = ns:GetColor("heal", key)
		if ns.hasSecrets then
			if atlas then
				seg:GetStatusBarTexture():SetAtlas(atlas)
			else
				seg:SetStatusBarTexture(path)
			end
			seg:SetStatusBarColor(c[1], c[2], c[3], ALPHA)
		else
			if atlas then
				seg:SetAtlas(atlas)
			else
				seg:SetTexture(path)
				seg:SetTexCoord(0, 1, 0, 1)
			end
			seg:SetVertexColor(c[1], c[2], c[3], ALPHA)
		end
	end
end

local function HideSegments(hp)
	hp.mine:Hide()
	hp.others:Hide()
end

-- TBC: places seg after the previous region; returns what the next
-- segment should follow
local function PlaceSegment(seg, previous, width)
	if width < 1 then
		seg:Hide()
		return previous
	end
	seg:ClearAllPoints()
	seg:SetPoint("TOPLEFT", previous, "TOPRIGHT")
	seg:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT")
	seg:SetWidth(width)
	seg:Show()
	return seg
end

-- Forever: a full-width bar after previous, filled to amount of maxHealth;
-- returns its fill for the next segment to follow
local function PlaceSecretSegment(seg, previous, width, maxHealth, amount)
	seg:ClearAllPoints()
	seg:SetPoint("TOPLEFT", previous, "TOPRIGHT")
	seg:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT")
	seg:SetWidth(width)
	seg:SetMinMaxValues(0, maxHealth)
	seg:SetValue(amount)
	seg:Show()
	return seg:GetStatusBarTexture()
end

local function UpdateSecret(f, hp)
	local unit = f.unit
	local calc = f.healCalculator
	UnitGetDetailedHealPrediction(unit, "player", calc)
	local _, mine, others = calc:GetIncomingHeals()
	local maxHealth, width = UnitHealthMax(unit), f.health:GetWidth()

	-- Anchored fresh each time: swapping the bar texture can replace the
	-- fill texture object
	local previous = PlaceSecretSegment(hp.mine, f.health:GetStatusBarTexture(), width, maxHealth, mine)
	PlaceSecretSegment(hp.others, previous, width, maxHealth, others)
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
	if f.healCalculator then return UpdateSecret(f, hp) end

	local maxHealth = UnitHealthMax(unit)
	if maxHealth <= 0 then return HideSegments(hp) end

	local missing = math.max(0, maxHealth - UnitHealth(unit))
	local all = UnitGetIncomingHeals(unit) or 0
	local mine = math.min(UnitGetIncomingHeals(unit, "player") or 0, all, missing)
	local others = math.min(all - mine, missing - mine)

	local scale = f.health:GetWidth() / maxHealth
	-- Anchored fresh each time: swapping the bar texture can replace the
	-- fill texture object
	local previous = PlaceSegment(hp.mine, f.health:GetStatusBarTexture(), mine * scale)
	PlaceSegment(hp.others, previous, others * scale)
end
