local addonName, ns = ...

-- Small unit frame indicators: raid target marker, leader / master looter /
-- PvP / rest-combat status icons, and the party out-of-range fade.

local NAME_INSET = 4 -- name text's left inset in the health bar
ns.NAME_INSET = NAME_INSET

---------------------------------------------------------------------------
-- Raid marker
---------------------------------------------------------------------------

-- Inside the health bar before the name; the name shifts right to make
-- room while one is set
function ns.CreateRaidIcon(f)
	local size = f.small and 12 or 14
	f.raidIcon = f.health:CreateTexture(nil, "OVERLAY")
	f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	f.raidIcon:SetSize(size, size)
	f.raidIcon:SetPoint("LEFT", 3, 0)
	f.raidIcon:Hide()
end

function ns.UpdateRaidIcon(f)
	local icon = f.raidIcon
	local index = UnitExists(f.unit) and GetRaidTargetIndex(f.unit)
	if index then
		SetRaidTargetIconTexture(icon, index)
	end
	local shown = index and true or false
	if shown ~= icon:IsShown() or f.nameShifted == nil then
		icon:SetShown(shown)
		f.nameShifted = shown
		f.nameText:SetPoint("LEFT", shown and (NAME_INSET + icon:GetWidth() + 2) or NAME_INSET, 0)
	end
end

---------------------------------------------------------------------------
-- Status icons: leader / master looter (player, target, party), PvP flag
-- (player, target), resting / in combat (player)
---------------------------------------------------------------------------

local STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local STATE_COORDS = {
	rest = { 0, 0.5, 0, 0.421875 },
	combat = { 0.5, 1, 0, 0.484375 },
}
-- The PvP flag sits in the top-left of its 64px texture
local PVP_COORDS = { 0, 0.62, 0, 0.62 }

-- Events that can change any status icon; frames with status icons
-- register all of them
ns.STATUS_EVENTS = {
	PARTY_LEADER_CHANGED = true,
	GROUP_ROSTER_UPDATE = true,
	PARTY_LOOT_METHOD_CHANGED = true,
	PLAYER_FLAGS_CHANGED = true,
	PLAYER_UPDATE_RESTING = true,
	PLAYER_REGEN_DISABLED = true,
	PLAYER_REGEN_ENABLED = true,
}

-- Icons go in the portrait corners, or on the top-left border for frames
-- without a portrait. layer: frame drawn above the bars.
function ns.CreateStatusIcons(f, layer, opts)
	f.leaderIcon = layer:CreateTexture(nil, "OVERLAY")
	f.leaderIcon:SetTexture("Interface\\GroupFrame\\UI-Group-LeaderIcon")
	f.leaderIcon:SetSize(14, 14)
	if f.portrait then
		f.leaderIcon:SetPoint("TOPLEFT", f.portrait, "TOPLEFT", 1, -1)
	else
		f.leaderIcon:SetPoint("CENTER", f, "TOPLEFT", 9, 0)
	end

	-- Anchored by UpdateStatusIcons, next to or in place of the leader icon
	f.looterIcon = layer:CreateTexture(nil, "OVERLAY")
	f.looterIcon:SetTexture("Interface\\GroupFrame\\UI-Group-MasterLooter")
	f.looterIcon:SetSize(14, 14)

	if opts.pvp and f.portrait then
		f.pvpIcon = layer:CreateTexture(nil, "OVERLAY")
		f.pvpIcon:SetSize(18, 18)
		f.pvpIcon:SetPoint("BOTTOMLEFT", f.portrait, "BOTTOMLEFT", 0, 0)
	end
	if opts.state and f.portrait then
		f.stateIcon = layer:CreateTexture(nil, "OVERLAY")
		f.stateIcon:SetTexture(STATE_TEXTURE)
		f.stateIcon:SetSize(18, 18)
		f.stateIcon:SetPoint("BOTTOMRIGHT", f.portrait, "BOTTOMRIGHT", 0, 0)
	end

	for event in pairs(ns.STATUS_EVENTS) do
		pcall(f.RegisterEvent, f, event)
	end
end

-- 0 for the player, 1-4 for party members, nil otherwise; matches
-- C_PartyInfo.GetLootMethod's master looter index
local function PartyIndex(unit)
	if UnitIsUnit(unit, "player") then return 0 end
	for i = 1, 4 do
		if UnitIsUnit(unit, "party" .. i) then return i end
	end
end

local function IsMasterLooter(unit)
	if not (IsInGroup() and C_PartyInfo and C_PartyInfo.GetLootMethod) then return false end
	local _, lootMaster = C_PartyInfo.GetLootMethod()
	return lootMaster ~= nil and lootMaster == PartyIndex(unit)
end

local function UpdatePvP(icon, unit, exists)
	local faction = exists and UnitFactionGroup(unit)
	if exists and UnitIsPVPFreeForAll(unit) then
		icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-FFA")
	elseif faction and faction ~= "Neutral" and UnitIsPVP(unit) then
		icon:SetTexture("Interface\\TargetingFrame\\UI-PVP-" .. faction)
	else
		return icon:Hide()
	end
	icon:SetTexCoord(unpack(PVP_COORDS))
	icon:Show()
end

function ns.UpdateStatusIcons(f)
	if not f.leaderIcon then return end
	local unit = f.unit
	local exists = UnitExists(unit)

	local isLeader = exists and UnitIsGroupLeader(unit)
	f.leaderIcon:SetShown(isLeader)

	local isLooter = exists and IsMasterLooter(unit)
	f.looterIcon:ClearAllPoints()
	if isLeader then
		f.looterIcon:SetPoint("LEFT", f.leaderIcon, "RIGHT", 1, 0)
	else
		f.looterIcon:SetAllPoints(f.leaderIcon)
	end
	f.looterIcon:SetShown(isLooter)

	if f.pvpIcon then UpdatePvP(f.pvpIcon, unit, exists) end

	if f.stateIcon then
		local state = UnitAffectingCombat("player") and "combat" or IsResting() and "rest"
		if state then
			f.stateIcon:SetTexCoord(unpack(STATE_COORDS[state]))
			f.stateIcon:Show()
		else
			f.stateIcon:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Party range fade
---------------------------------------------------------------------------

local RANGE_INTERVAL = 0.25

-- SetAlpha is allowed on secure frames in combat. Units the client can't
-- range-check stay opaque.
function ns.UpdateRange(f)
	local inRange, checkedRange = UnitInRange(f.unit)
	f:SetAlpha((checkedRange and not inRange) and KUIDB.style.outOfRangeAlpha or 1)
end

-- OnUpdate script for party frames
function ns.OnUpdateRange(f, elapsed)
	f.rangeElapsed = (f.rangeElapsed or 0) + elapsed
	if f.rangeElapsed > RANGE_INTERVAL then
		f.rangeElapsed = 0
		ns.UpdateRange(f)
	end
end
