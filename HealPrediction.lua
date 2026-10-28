local addonName, ns = ...

-- Incoming heal prediction: translucent segments extending the health fill,
-- the player's own heals first, then everyone else's. Uses the client's
-- native UnitGetIncomingHeals, so no LibHealComm needed. KUI has its own
-- toggle rather than Blizzard's unitFramesDisplayIncomingHeals CVar.
-- Never extends past full health.

local ALPHA = 0.6

local function CreateSegment(bar)
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
end

-- Matches the health bar's texture so the segments carry the same shading
function ns.StyleHealPrediction(f)
	local hp = f.healPrediction
	if not hp then return end
	local atlas, path = ns:GetStatusbar(KUIDB.style.healthTexture)
	for key, seg in pairs(hp) do
		if atlas then
			seg:SetAtlas(atlas)
		else
			seg:SetTexture(path)
			seg:SetTexCoord(0, 1, 0, 1)
		end
		local c = ns:GetColor("heal", key)
		seg:SetVertexColor(c[1], c[2], c[3], ALPHA)
	end
end

-- Places seg after the previous region; returns what the next segment
-- should follow
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

-- Called from ns.UpdateHealth, on UNIT_HEAL_PREDICTION, and after layout
-- changes the bar's width
function ns.UpdateHealPrediction(f)
	local hp = f.healPrediction
	if not hp then return end

	local unit = f.unit
	local maxHealth = UnitHealthMax(unit)
	if not KUIDB.healPrediction.enabled or not UnitExists(unit) or UnitIsDeadOrGhost(unit) or maxHealth <= 0 then
		hp.mine:Hide()
		hp.others:Hide()
		return
	end

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
