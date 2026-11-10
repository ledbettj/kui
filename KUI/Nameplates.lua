local addonName, ns = ...

-- Nameplates in the unit frame style: a health bar with name and percent,
-- a threat-colored border and threat % while the player has aggro,
-- the player's own debuffs (and buffs on friendly units) above,
-- and a cast bar below that only shows while casting. KUI's frame sits on
-- Blizzard's nameplate base; the Blizzard unit frame stays alive but fully
-- transparent, so its own logic (and click handling on the base) is
-- untouched.

local IsSecret = ns.IsSecret

-- Side tables rather than fields on Blizzard's frames, which would taint them
local plates = {} -- unit token -> KUI plate
local plateForBase = {} -- Blizzard nameplate base -> KUI plate
local hooked = setmetatable({}, { __mode = "k" }) -- Blizzard unit frames with the alpha hook
local hidden = setmetatable({}, { __mode = "k" }) -- those currently under a KUI plate

---------------------------------------------------------------------------
-- Blizzard unit frame suppression
---------------------------------------------------------------------------

-- Blizzard's unit frames come from a pool and can move on to the player's
-- own plate, so only those under a KUI plate are kept transparent. Its code
-- can reset alpha (range fading), hence the hook.
local function KeepHidden(uf)
	if hidden[uf] and uf:GetAlpha() > 0 then uf:SetAlpha(0) end
end

local function HideBlizzardPlate(uf)
	if not hooked[uf] then
		hooksecurefunc(uf, "SetAlpha", KeepHidden)
		hooked[uf] = true
	end
	hidden[uf] = true
	uf:SetAlpha(0)
end

local function ReleaseBlizzardPlate(uf)
	if not hidden[uf] then return end
	hidden[uf] = nil
	uf:SetAlpha(1)
end

-- Whether a nameplate base shows the given unit. Comparing plates avoids
-- UnitIsUnit, whose answer can be secret.
local function PlateIsUnit(base, unit)
	return base ~= nil and C_NamePlate.GetNamePlateForUnit(unit) == base
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

-- The player's threat on a hostile unit: status 1 (about to pull), 2
-- (tanking, not securely) or 3 (tanking), with the threat percentage where
-- 100 pulls aggro. nil when not on its threat list or below the tank.
-- Nothing while the client keeps threat secret.
local function PlayerThreat(unit)
	local canAttack = UnitCanAttack("player", unit)
	if IsSecret(canAttack) or not canAttack then return end
	local _, status, percent = UnitDetailedThreatSituation("player", unit)
	if IsSecret(status) or IsSecret(percent) then return end
	if status and status > 0 then return status, percent end
	return nil, percent
end

-- Border: threat color while the player has or is pulling aggro (more
-- urgent than the target highlight), else the target color, else the
-- normal border
local function UpdateBorder(kp)
	local N = ns.db.nameplates
	local status = N.threatBorder and kp.threatStatus
	local c
	if status then
		c = ns:GetColor("threat", ns.threatOrder[status])
	elseif N.highlightTarget and PlateIsUnit(kp:GetParent(), "target") then
		c = N.targetColor
	else
		c = ns.db.style.borderColor
	end
	kp:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

-- Threat percentage outside the left edge, colored by status (white below
-- the tank)
local function UpdateThreat(kp)
	local status, percent = PlayerThreat(kp.unit)
	kp.threatStatus = status

	if ns.db.nameplates.threatPercent and percent and percent > 0 then
		local c = status and ns:GetColor("threat", ns.threatOrder[status])
		kp.threatText:SetFormattedText("%d%%", percent)
		if c then
			kp.threatText:SetTextColor(c[1], c[2], c[3])
		else
			kp.threatText:SetTextColor(1, 1, 1)
		end
		kp.threatText:Show()
	else
		kp.threatText:Hide()
	end
	UpdateBorder(kp)
end

-- Raid marker just outside the plate's right edge, sized to stand out
-- (unit frames put theirs inside the health bar instead). A secret marker
-- is drawn without knowing which, or whether, it is, as on the unit frames.
local function UpdateRaidMark(kp)
	local index = GetRaidTargetIndex(kp.unit)
	local secret = IsSecret(index)
	if secret or index then
		SetRaidTargetIconTexture(kp.raidMark, index)
	end
	kp.raidMark:SetShown(secret or (index and true or false))
end

local function UpdatePlate(kp)
	UpdateRaidMark(kp)
	ns.UpdateHealth(kp)
	ns.UpdateName(kp)
	ns.UpdateAuras(kp)
	UpdateThreat(kp) -- also sets the border
end

---------------------------------------------------------------------------
-- Layout / style
---------------------------------------------------------------------------

local function LayoutPlate(kp)
	local N = ns.db.nameplates

	kp:SetSize(N.width, N.height)
	kp.raidMark:SetSize(N.height + 8, N.height + 8)
	local inset = ns:ApplyBackdrop(kp, true)
	kp.health:ClearAllPoints()
	kp.health:SetPoint("TOPLEFT", inset, -inset)
	kp.health:SetPoint("BOTTOMRIGHT", -inset, inset)

	ns:LayoutDetachedCastbar(kp.castbar, kp, N.castHeight)

	ns.SizeAuras(kp.auras, N.width)

	-- Backdrop reapply resets the border color; threat sets it and the
	-- threat text, which the config toggles go through here
	if kp.unit then UpdateThreat(kp) end
end

local function StylePlate(kp)
	ns.StyleBar(kp.health, ns.db.style.healthTexture)
	ns:StyleCastbar(kp.castbar)
	if kp.unit then UpdatePlate(kp) end
end

---------------------------------------------------------------------------
-- Creation and lifecycle
---------------------------------------------------------------------------

local function CreatePlate(base)
	local kp = CreateFrame("Frame", nil, base, "BackdropTemplate")
	kp:SetPoint("CENTER")
	kp.small = true -- percent health text
	kp.showLevel = true -- difficulty-colored level before the name, like the target frame

	kp.health = ns.CreateBar(kp)
	kp.nameText = ns.CreateText(kp.health, ns.fonts.small, "LEFT")
	kp.nameText:SetPoint("LEFT", 3, 0)
	kp.healthText = ns.CreateText(kp.health, ns.fonts.small, "RIGHT")
	kp.healthText:SetPoint("RIGHT", -3, 0)
	kp.nameText:SetPoint("RIGHT", kp.healthText, "LEFT", -3, 0)

	kp.raidMark = kp:CreateTexture(nil, "OVERLAY")
	kp.raidMark:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	kp.raidMark:SetPoint("LEFT", kp, "RIGHT", 4, 0)
	kp.raidMark:Hide()

	kp.threatText = ns.CreateText(kp, ns.fonts.small, "RIGHT")
	kp.threatText:SetPoint("RIGHT", kp, "LEFT", -4, 0)
	kp.threatText:Hide()

	-- Own debuffs, plus own buffs on friendly units, above
	ns.CreateAuras(kp, "nameplate")
	kp.auras:SetPoint("BOTTOMLEFT", kp, "TOPLEFT", 0, 3)

	-- Cast bar below, hidden when idle
	kp.castbar = ns:CreateDetachedCastbar(kp)
	-- Plates have their own bar sizes, so not the unit frames' bar text size
	kp.castbar.text:SetFontObject(ns.fonts.small)
	kp.castbar.time:SetFontObject(ns.fonts.small)

	plateForBase[base] = kp
	LayoutPlate(kp)
	StylePlate(kp)
	return kp
end

local function OnPlateAdded(unit)
	-- Forbidden plates (friendly plates in instances) return nil to addons
	local base = C_NamePlate.GetNamePlateForUnit(unit)
	-- The player's own plate is the personal resource display; left as is
	if not base or PlateIsUnit(base, "player") then return end

	local kp = plateForBase[base] or CreatePlate(base)
	if kp.blizzardFrame and kp.blizzardFrame ~= base.UnitFrame then
		ReleaseBlizzardPlate(kp.blizzardFrame)
	end
	kp.blizzardFrame = base.UnitFrame
	if base.UnitFrame then HideBlizzardPlate(base.UnitFrame) end
	kp.unit = unit
	plates[unit] = kp
	ns:SetCastbarUnit(kp.castbar, unit)
	ns:RefreshCastbar(kp.castbar)
	UpdatePlate(kp)
	kp:Show()
end

-- Runs after Blizzard has released its unit frame back to the pool, so
-- the plate remembers which one it hid
local function OnPlateRemoved(unit)
	local kp = plates[unit]
	if not kp then return end
	if kp.blizzardFrame then
		ReleaseBlizzardPlate(kp.blizzardFrame)
		kp.blizzardFrame = nil
	end
	plates[unit] = nil
	kp.unit = nil
	ns:SetCastbarUnit(kp.castbar, nil)
	kp:Hide()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local unitHandlers = {
	UNIT_HEALTH = ns.UpdateHealth,
	UNIT_MAXHEALTH = ns.UpdateHealth,
	-- Reaction decides the health color and which buffs show
	UNIT_FACTION = UpdatePlate,
	UNIT_CONNECTION = ns.UpdateHealth,
	UNIT_NAME_UPDATE = ns.UpdateName,
	UNIT_THREAT_LIST_UPDATE = UpdateThreat,
}

-- Events that can change the player's threat on any plate
local allPlateEvents = {
	PLAYER_TARGET_CHANGED = UpdateBorder,
	RAID_TARGET_UPDATE = UpdateRaidMark,
	UNIT_THREAT_SITUATION_UPDATE = UpdateThreat,
	PLAYER_REGEN_ENABLED = UpdateThreat,
	PLAYER_REGEN_DISABLED = UpdateThreat,
}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
	local handler = allPlateEvents[event]
	if handler then
		for _, kp in pairs(plates) do handler(kp) end
		return
	end
	local kp = plates[unit]
	if kp then unitHandlers[event](kp) end
end)

---------------------------------------------------------------------------
-- Public
---------------------------------------------------------------------------

function ns:LayoutNameplates()
	for _, kp in pairs(plates) do LayoutPlate(kp) end
end

function ns:StyleNameplates()
	for _, kp in pairs(plates) do StylePlate(kp) end
end

-- Only when enabled at login (see the lifecycle notes in Core.lua)
function ns:InitNameplates()
	if not ns.db.nameplates.enabled or not NamePlateDriverFrame then return end

	-- After Blizzard has acquired and set up its unit frame for the plate
	hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit) OnPlateAdded(unit) end)
	hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit) OnPlateRemoved(unit) end)

	for event in pairs(unitHandlers) do
		pcall(events.RegisterEvent, events, event)
	end
	for event in pairs(allPlateEvents) do
		pcall(events.RegisterEvent, events, event)
	end

	-- Plates already on screen (e.g. after /reload)
	for _, base in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = base.GetUnit and base:GetUnit()
		if unit then OnPlateAdded(unit) end
	end
end
