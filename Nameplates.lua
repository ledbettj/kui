local addonName, ns = ...

-- Nameplates in the unit frame style: a health bar with name and percent,
-- buffs and the player's own debuffs above, and a cast bar below that only
-- shows while casting. KUI's frame sits on Blizzard's nameplate base; the
-- Blizzard unit frame stays alive but fully transparent, so its own logic
-- (and click handling on the base) is untouched.

local plates = {} -- unit token -> KUI plate

---------------------------------------------------------------------------
-- Blizzard unit frame suppression
---------------------------------------------------------------------------

-- CompactUnitFrame code can reset alpha (range fading), so pin it at 0
local function KeepHidden(uf)
	if uf:GetAlpha() > 0 then uf:SetAlpha(0) end
end

local function HideBlizzardPlate(uf)
	if not uf.kuiHooked then
		hooksecurefunc(uf, "SetAlpha", KeepHidden)
		uf.kuiHooked = true
	end
	uf:SetAlpha(0)
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local function UpdateTargetHighlight(kp)
	local N = KUIDB.nameplates
	local isTarget = N.highlightTarget and UnitIsUnit(kp.unit, "target")
	local c = isTarget and N.targetColor or KUIDB.style.borderColor
	kp:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

local function UpdatePlate(kp)
	ns.UpdateHealth(kp)
	ns.UpdateName(kp)
	ns.UpdateAuras(kp)
	UpdateTargetHighlight(kp)
end

---------------------------------------------------------------------------
-- Layout / style
---------------------------------------------------------------------------

local function LayoutPlate(kp)
	local N = KUIDB.nameplates

	kp:SetSize(N.width, N.height)
	local inset = ns:ApplyBackdrop(kp, true)
	kp.health:ClearAllPoints()
	kp.health:SetPoint("TOPLEFT", inset, -inset)
	kp.health:SetPoint("BOTTOMRIGHT", -inset, inset)

	local holder = kp.castHolder
	holder:SetSize(N.width, N.castHeight)
	holder:ClearAllPoints()
	holder:SetPoint("TOP", kp, "BOTTOM", 0, -2)
	inset = ns:ApplyBackdrop(holder, true)
	-- Explicit height: LayoutCastbar sizes the icon from it, and the holder
	-- is usually hidden when this runs
	kp.castbar:ClearAllPoints()
	kp.castbar:SetPoint("TOPLEFT", inset, -inset)
	kp.castbar:SetPoint("TOPRIGHT", -inset, -inset)
	kp.castbar:SetHeight(math.max(1, N.castHeight - inset * 2))
	ns:LayoutCastbar(kp.castbar)

	local layout = kp.auras.layout
	kp.auras.perRow = math.max(1, math.floor((N.width + ns.AURA_SPACING) / (layout.size + ns.AURA_SPACING)))
	kp.auras:SetWidth(kp.auras.perRow * (layout.size + ns.AURA_SPACING))

	-- Backdrop reapply resets the border color
	if kp.unit then UpdateTargetHighlight(kp) end
end

local function StylePlate(kp)
	ns.StyleBar(kp.health, KUIDB.style.healthTexture)
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

	-- Buffs and own debuffs above
	kp.auras = CreateFrame("Frame", nil, kp)
	kp.auras.layout = ns.AURA_LAYOUTS.nameplate
	kp.auras.buttons = {}
	kp.auras:SetHeight(kp.auras.layout.size)
	kp.auras:SetPoint("BOTTOMLEFT", kp, "TOPLEFT", 0, 3)

	-- Cast bar below, in its own bordered holder that hides when idle
	kp.castHolder = CreateFrame("Frame", nil, kp, "BackdropTemplate")
	kp.castbar = ns:CreateCastbar(kp.castHolder)
	kp.castbar.container = kp.castHolder
	kp.castHolder:Hide()

	base.kui = kp
	LayoutPlate(kp)
	StylePlate(kp)
	return kp
end

local function OnPlateAdded(unit)
	-- Forbidden plates (friendly plates in instances) return nil to addons
	local base = C_NamePlate.GetNamePlateForUnit(unit)
	if not base or UnitIsUnit(unit, "player") then return end

	if base.UnitFrame then HideBlizzardPlate(base.UnitFrame) end

	local kp = base.kui or CreatePlate(base)
	kp.unit = unit
	plates[unit] = kp
	ns:SetCastbarUnit(kp.castbar, unit)
	ns:RefreshCastbar(kp.castbar)
	UpdatePlate(kp)
	kp:Show()
end

local function OnPlateRemoved(unit)
	local kp = plates[unit]
	if not kp then return end
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
	UNIT_FACTION = ns.UpdateHealth,
	UNIT_CONNECTION = ns.UpdateHealth,
	UNIT_NAME_UPDATE = ns.UpdateName,
	UNIT_AURA = ns.UpdateAuras,
}

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then
		for _, kp in pairs(plates) do
			UpdateTargetHighlight(kp)
		end
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

function ns:InitNameplates()
	if not KUIDB.nameplates.enabled or not NamePlateDriverFrame then return end

	-- After Blizzard has acquired and set up its unit frame for the plate
	hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit) OnPlateAdded(unit) end)
	hooksecurefunc(NamePlateDriverFrame, "OnNamePlateRemoved", function(_, unit) OnPlateRemoved(unit) end)

	for event in pairs(unitHandlers) do
		pcall(events.RegisterEvent, events, event)
	end
	events:RegisterEvent("PLAYER_TARGET_CHANGED")

	-- Plates already on screen (e.g. after /reload)
	for _, base in ipairs(C_NamePlate.GetNamePlates()) do
		local unit = base.GetUnit and base:GetUnit()
		if unit then OnPlateAdded(unit) end
	end
end
