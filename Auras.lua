local addonName, ns = ...

-- Buff/debuff icon grids for unit frames and nameplates. Debuffs come first
-- (nearest the frame), then buffs starting on a fresh row.

local SPACING = 2

-- size: icon size. growUp: rows stack upward from the container's bottom
-- edge (otherwise downward from its top). perRow: fixed icons per row,
-- else as many as fit the owner's width. debuffFilter: defaults to all
-- harmful auras. buffsByReaction: on enemies, only buffs the player's class
-- can remove; on friendly units, only the player's own buffs. noMouse: no
-- tooltips, so the icons don't block clicks.
local LAYOUTS = {
	above = { size = 22, maxBuffs = 32, maxDebuffs = 16, growUp = true },
	below = { size = 16, maxBuffs = 8, maxDebuffs = 8, perRow = 8 },
	nameplate = {
		size = 18, maxBuffs = 4, maxDebuffs = 6, growUp = true,
		debuffFilter = "HARMFUL|PLAYER", buffsByReaction = true, noMouse = true,
	},
}

-- Buff types each class can remove from enemies (TBC): Dispel Magic,
-- Purge, Spellsteal, and the Felhunter's Devour Magic
local PURGE_TYPES = {
	PRIEST = { Magic = true },
	SHAMAN = { Magic = true },
	MAGE = { Magic = true },
	WARLOCK = { Magic = true },
}

local purgeTypes -- the player's entry, looked up on first use
local function PlayerPurgeTypes()
	if purgeTypes == nil then
		local _, class = UnitClass("player")
		purgeTypes = PURGE_TYPES[class] or false
	end
	return purgeTypes
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
	local size = container.layout.size
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

local function Place(aura)
	if pass.types and not pass.types[aura.dispelName] then return false end

	local container, layout = pass.container, pass.container.layout
	pass.n = pass.n + 1
	local b = container.buttons[pass.n]
	if not b then
		b = CreateButton(container)
		container.buttons[pass.n] = b
	end

	b.unit, b.filter, b.isBuff = pass.unit, pass.filter, pass.isBuff
	b.auraInstanceID = aura.auraInstanceID
	b.icon:SetTexture(aura.icon)
	b.count:SetText(aura.applications > 1 and aura.applications or "")
	CooldownFrame_Set(b.cooldown, aura.expirationTime - aura.duration, aura.duration, aura.duration > 0, true)

	if pass.isBuff then
		b.border:SetVertexColor(0, 0, 0)
	else
		AuraUtil.SetAuraBorderColor(b.border, aura.dispelName)
	end

	if pass.col >= container.perRow then
		pass.col, pass.row = 0, pass.row + 1
	end
	local step = layout.size + SPACING
	b:ClearAllPoints()
	if layout.growUp then
		b:SetPoint("BOTTOMLEFT", pass.col * step, pass.row * step)
	else
		b:SetPoint("TOPLEFT", pass.col * step, -pass.row * step)
	end
	b:Show()
	pass.col = pass.col + 1

	pass.placed = pass.placed + 1
	return pass.placed >= pass.max -- true stops the iteration
end

-- types: optional set of dispel types to accept, others are skipped
local function PlaceAll(filter, isBuff, max, types)
	pass.filter, pass.isBuff, pass.max, pass.placed, pass.types = filter, isBuff, max, 0, types
	AuraUtil.ForEachAura(pass.unit, filter, max, Place, true)
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
	elseif PlayerPurgeTypes() then
		PlaceAll("HELPFUL", true, layout.maxBuffs, PlayerPurgeTypes())
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
	container:SetHeight(layout.size)
	owner.auras = container
	return container
end

-- Height of the container when full: the debuff rows plus the buff rows.
-- Needs a fixed perRow.
function ns.AurasMaxHeight(container)
	local layout = container.layout
	local rows = math.ceil(layout.maxDebuffs / layout.perRow) + math.ceil(layout.maxBuffs / layout.perRow)
	return rows * (layout.size + SPACING) - SPACING
end

-- Icons per row for an owner of the given width
function ns.SizeAuras(container, ownerWidth)
	local layout = container.layout
	local step = layout.size + SPACING
	container.perRow = layout.perRow or math.max(1, math.floor((ownerWidth + SPACING) / step))
	container:SetWidth(container.perRow * step)
end
