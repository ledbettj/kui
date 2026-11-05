local addonName, ns = ...

-- Buff/debuff icon grids for unit frames and nameplates. Debuffs come first
-- (nearest the frame), then buffs starting on a fresh row.
--
-- Aura details are secret in combat, so auras are read by instance ID and
-- Blizzard turns each secret into something drawable: the stack count as
-- text, the duration as an object the cooldown swipe takes, the dispel type
-- as a border color through a color curve.

local SPACING = 2

-- size: icon size. scales: follows the unit frame aura size setting. growUp:
-- rows stack upward from the container's bottom edge (otherwise downward from
-- its top). perRow: fixed icons per row,
-- else as many as fit the owner's width. debuffFilter: defaults to all
-- harmful auras. buffsByReaction: no buffs on enemies (which ones can be
-- removed is secret); on friendly units, only the player's own. noMouse: no
-- tooltips, so the icons don't block clicks.
local LAYOUTS = {
	above = { size = 22, scales = true, maxBuffs = 32, maxDebuffs = 16, growUp = true },
	below = { size = 16, scales = true, maxBuffs = 8, maxDebuffs = 8, perRow = 8 },
	nameplate = {
		size = 18, maxBuffs = 4, maxDebuffs = 6, growUp = true,
		debuffFilter = "HARMFUL|PLAYER", buffsByReaction = true, noMouse = true,
	},
}

local function IconSize(layout)
	if layout.scales then return math.floor(layout.size * ns.db.style.auraScale + 0.5) end
	return layout.size
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

local function Button_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 15, -25)
	if self.isBuff then
		GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID, self.filter)
	else
		GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID, self.filter)
	end
end

local function CreateButton(container)
	local size = IconSize(container.layout)
	local b = CreateFrame("Frame", nil, container)
	b:SetSize(size, size)
	if not container.layout.noMouse then
		b:EnableMouse(true)
		b:SetScript("OnEnter", Button_OnEnter)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end

	-- 1px border behind the icon; tinted by dispel type for debuffs
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetAllPoints()
	b.border:SetColorTexture(1, 1, 1)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	ns.CropIcon(b.icon)

	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b.icon)
	b.cooldown:SetReverse(true)
	b.cooldown:SetHideCountdownNumbers(true)

	b.count = b.cooldown:CreateFontString(nil, "OVERLAY")
	b.count:SetFontObject(ns.fonts.aura)
	b.count:SetPoint("BOTTOMRIGHT", 1, 0)

	return b
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

-- State for the pass in progress. UNIT_AURA is frequent (every nameplate in
-- combat), so the iteration callbacks are static functions sharing this
-- table rather than closures created per update.
local pass = {}

-- The next button in the container, set up for an aura of this pass
local function NextButton(auraInstanceID)
	local container = pass.container
	pass.n = pass.n + 1
	local b = container.buttons[pass.n]
	if not b then
		b = CreateButton(container)
		container.buttons[pass.n] = b
	end
	b.unit, b.filter, b.isBuff = pass.unit, pass.filter, pass.isBuff
	b.auraInstanceID = auraInstanceID
	return b
end

-- Puts b in the next grid cell and counts it; true once the pass is full
local function Position(b)
	local container, layout = pass.container, pass.container.layout
	if pass.col >= container.perRow then
		pass.col, pass.row = 0, pass.row + 1
	end
	local step = IconSize(layout) + SPACING
	b:ClearAllPoints()
	if layout.growUp then
		b:SetPoint("BOTTOMLEFT", pass.col * step, pass.row * step)
	else
		b:SetPoint("TOPLEFT", pass.col * step, -pass.row * step)
	end
	b:Show()
	pass.col = pass.col + 1

	pass.placed = pass.placed + 1
	return pass.placed >= pass.max
end

---------------------------------------------------------------------------
-- By aura instance, without reading secret details
---------------------------------------------------------------------------

-- Dispel type IDs (the x GetAuraDispelTypeColor evaluates the curve at)
-- and the debuff colors Blizzard uses for them
local DISPEL_TYPE_IDS = { None = 0, Magic = 1, Curse = 2, Disease = 3, Poison = 4, Bleed = 11 }

local dispelCurve
local function DispelCurve()
	if not dispelCurve then
		local info = AuraUtil.GetDebuffDisplayInfoTable()
		dispelCurve = C_CurveUtil.CreateColorCurve()
		dispelCurve:SetType(Enum.LuaCurveType.Step)
		-- Every ID up to the highest gets a point, so a type with no color
		-- of its own (enrage) snaps to None's rather than its neighbor's
		local byID = {}
		for name, id in pairs(DISPEL_TYPE_IDS) do byID[id] = info[name] and info[name].color end
		for id = 0, DISPEL_TYPE_IDS.Bleed do
			dispelCurve:AddPoint(id, byID[id] or info.None.color)
		end
	end
	return dispelCurve
end

local function PlaceByInstance(auraInstanceID)
	local unit = pass.unit
	local b = NextButton(auraInstanceID)

	-- The icon goes straight to the texture: it may be secret, so it's never
	-- tested (not even with and/or)
	local aura = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, auraInstanceID)
	local icon
	if aura and (not canaccesstable or canaccesstable(aura)) then icon = aura.icon end
	b.icon:SetTexture(icon)
	b.count:SetText(C_UnitAuras.GetAuraApplicationDisplayCount(unit, auraInstanceID, 2))
	local duration = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
	if duration then
		b.cooldown:SetCooldownFromDurationObject(duration)
	else
		b.cooldown:Clear()
	end

	if pass.isBuff then
		b.border:SetVertexColor(0, 0, 0)
	else
		local color = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, DispelCurve())
		if color then b.border:SetVertexColor(color:GetRGBA()) end
	end

	return Position(b)
end

local function PlaceAll(filter, isBuff, max)
	pass.filter, pass.isBuff, pass.max, pass.placed = filter, isBuff, max, 0
	for _, auraInstanceID in ipairs(C_UnitAuras.GetUnitAuraInstanceIDs(pass.unit, filter, max)) do
		if PlaceByInstance(auraInstanceID) then break end
	end
end

-- self: any frame with .unit and .auras (from ns.CreateAuras)
function ns.UpdateAuras(self)
	local container = self.auras
	if not container then return end
	local layout = container.layout

	pass.container, pass.unit = container, self.unit
	pass.n, pass.row, pass.col = 0, 0, 0

	PlaceAll(layout.debuffFilter or "HARMFUL", false, layout.maxDebuffs)
	if pass.col > 0 then
		pass.col, pass.row = 0, pass.row + 1
	end
	if not layout.buffsByReaction then
		PlaceAll("HELPFUL", true, layout.maxBuffs)
	elseif not UnitCanAttack("player", pass.unit) then
		PlaceAll("HELPFUL|PLAYER", true, layout.maxBuffs)
	end

	for i = pass.n + 1, #container.buttons do
		container.buttons[i]:Hide()
	end
	pass.container = nil
end

-- Hides every icon (placeholder frames in preview have no unit to read)
function ns.HideAuras(self)
	if not self.auras then return end
	for _, b in ipairs(self.auras.buttons) do
		b:Hide()
	end
end

---------------------------------------------------------------------------
-- Container
---------------------------------------------------------------------------

-- Creates owner.auras; the caller anchors it
function ns.CreateAuras(owner, layoutKey)
	local layout = LAYOUTS[layoutKey]
	local container = CreateFrame("Frame", nil, owner)
	container.layout = layout
	container.buttons = {}
	container:SetHeight(IconSize(layout))
	owner.auras = container
	return container
end

-- Height of the container when full: the debuff rows plus the buff rows.
-- Needs a fixed perRow.
function ns.AurasMaxHeight(container)
	local layout = container.layout
	local rows = math.ceil(layout.maxDebuffs / layout.perRow) + math.ceil(layout.maxBuffs / layout.perRow)
	return rows * (IconSize(layout) + SPACING) - SPACING
end

-- Icons per row for an owner of the given width, and the icon size
function ns.SizeAuras(container, ownerWidth)
	local layout = container.layout
	local size = IconSize(layout)
	local step = size + SPACING
	container.perRow = layout.perRow or math.max(1, math.floor((ownerWidth + SPACING) / step))
	container:SetWidth(container.perRow * step)
	container:SetHeight(size)
	for _, b in ipairs(container.buttons) do
		b:SetSize(size, size)
	end
end
