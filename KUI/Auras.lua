local addonName, ns = ...

-- Buff/debuff icon grids for unit frames and nameplates, plus the unit
-- frames' dispel highlight. In the grids, debuffs come first (nearest the
-- frame), then buffs starting on a fresh row.
--
-- Addon code can't read auras at all while they're secret: the query raises
-- an error. So each grid is Blizzard's CustomAuraContainerTemplate, whose
-- secure code reads the auras and fills in the regions KUI gives each button.
-- Those buttons can't be touched while auras are secret, except through it.

local SPACING = 2

-- size: icon size. scales: follows the unit frame aura size setting. growUp:
-- rows stack upward from the container's bottom edge (otherwise downward from
-- its top). perRow: fixed icons per row, else as many as fit the owner's
-- width. debuffFilter: defaults to all harmful auras. buffsByReaction: no
-- buffs on enemies; on friendly units, only the player's own. noMouse: no
-- tooltips, so the icons don't block clicks.
local LAYOUTS = {
	above = { size = 22, scales = true, maxBuffs = 32, maxDebuffs = 16, growUp = true },
	below = { size = 16, scales = true, maxBuffs = 8, maxDebuffs = 8, perRow = 8 },
	nameplate = {
		size = 18, maxBuffs = 4, maxDebuffs = 6, growUp = true,
		debuffFilter = "HARMFUL|PLAYER", buffsByReaction = true, noMouse = true,
	},
}

local GROUPS = { "debuffs", "buffs" }

local function IconSize(layout)
	if layout.scales then return math.floor(layout.size * ns.db.style.auraScale + 0.5) end
	return layout.size
end

---------------------------------------------------------------------------
-- Icons
---------------------------------------------------------------------------

-- Runs once per button, before it's locked down
local function InitButton(b, layout, isDebuff)
	local size = IconSize(layout)
	b:SetSize(size, size)
	b:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 15, -25)
	if layout.noMouse then b:EnableMouse(false) end

	-- 1px border behind the icon, tinted by dispel type on debuffs
	local border = b:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0, 0, 0)
	if isDebuff then
		local dispel = b:CreateTexture(nil, "BACKGROUND", nil, 1)
		dispel:SetAllPoints()
		dispel:SetColorTexture(1, 1, 1)
		b:AddDispelTypeTexture(dispel, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
			showWithoutDispelType = true,
		})
	end

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 1, -1)
	icon:SetPoint("BOTTOMRIGHT", -1, 1)
	ns.CropIcon(icon)
	b:SetIcon(icon)

	local cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	cooldown:SetAllPoints(icon)
	cooldown:SetReverse(true)
	cooldown:SetHideCountdownNumbers(true)
	b:SetDurationCooldown(cooldown)

	local count = cooldown:CreateFontString(nil, "OVERLAY")
	count:SetFontObject(ns.fonts.aura)
	count:SetPoint("BOTTOMRIGHT", 1, 0)
	b:SetApplicationCount(count)
end

---------------------------------------------------------------------------
-- Container
---------------------------------------------------------------------------

local function GroupLayout(group, layout)
	local size = IconSize(layout)
	return {
		elementWidth = size,
		elementHeight = size,
		elementSpacing = SPACING,
		lineSpacing = SPACING,
		groupLineSpacing = SPACING,
		forceNewLine = group == "buffs",
		layoutIndex = group == "buffs" and 2 or 1,
	}
end

-- Creates owner.auras: a plain frame for the caller to anchor, holding the
-- container, whose size Blizzard's code controls
function ns.CreateAuras(owner, layoutKey)
	local layout = LAYOUTS[layoutKey]
	local holder = CreateFrame("Frame", nil, owner)
	holder.layout = layout
	holder:SetHeight(IconSize(layout))

	local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	local anchor = layout.growUp and "BOTTOMLEFT" or "TOPLEFT"
	container:SetPoint(anchor)
	container:SetEditModePreviewEnabled(false)
	container:SetFlowLayoutAnchorPoint(anchor)
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right,
		layout.growUp and AnchorUtil.FlowDirection.Up or AnchorUtil.FlowDirection.Down)

	container:AddAuraGroup("debuffs", layout.debuffFilter or "HARMFUL", {
		maxFrameCount = layout.maxDebuffs,
		initializeFrame = function(b) InitButton(b, layout, true) end,
		layout = GroupLayout("debuffs", layout),
	})
	container:AddAuraGroup("buffs", layout.buffsByReaction and "HELPFUL|PLAYER" or "HELPFUL", {
		maxFrameCount = layout.maxBuffs,
		initializeFrame = function(b) InitButton(b, layout, false) end,
		layout = GroupLayout("buffs", layout),
	})

	if owner.unit then container:SetUnit(owner.unit) end
	container:SetEnabled(true)

	holder.container = container
	owner.auras = holder
	return holder
end

-- Height of the container when full: the debuff rows plus the buff rows.
-- Needs SizeAuras to have run.
function ns.AurasMaxHeight(holder)
	local layout = holder.layout
	local rows = math.ceil(layout.maxDebuffs / holder.perRow) + math.ceil(layout.maxBuffs / holder.perRow)
	return rows * (IconSize(layout) + SPACING) - SPACING
end

-- Icons per row for an owner of the given width, and the icon size
function ns.SizeAuras(holder, ownerWidth)
	local layout, container = holder.layout, holder.container
	local size = IconSize(layout)
	local step = size + SPACING
	holder.perRow = layout.perRow or math.max(1, math.floor((ownerWidth + SPACING) / step))
	holder:SetSize(holder.perRow * step, size)
	container:SetFlowLayoutMaximumLineSize(holder.perRow * step)

	for _, group in ipairs(GROUPS) do
		container:SetAuraGroupLayout(group, GroupLayout(group, layout))
	end
	-- Locked while auras are secret
	if C_Secrets.ShouldAurasBeSecret() then
		ns.pendingLayout = true
		return
	end
	for _, group in ipairs(GROUPS) do
		for i = 1, container:GetAuraGroupFrameCount(group) do
			container:GetAuraGroupFrame(group, i):SetSize(size, size)
		end
	end
end

---------------------------------------------------------------------------
-- Update
---------------------------------------------------------------------------

-- The container follows UNIT_AURA itself; this is for when the frame's unit
-- changes. self: any frame with .unit and .auras (from ns.CreateAuras)
-- and/or .dispel (from ns.CreateDispelHighlight)
function ns.UpdateAuras(self)
	local dispel = self.dispel
	if dispel then
		dispel:SetShown(ns.db.dispel.enabled)
		-- On enemies "HARMFUL|RAID" still matches (the player's own debuffs
		-- on them), so it only shows on units the player can help. A secret
		-- answer can still drive the alpha.
		local canAssist = UnitCanAssist("player", self.unit)
		if ns.IsSecret(canAssist) then
			dispel:SetAlphaFromBoolean(canAssist, 1, 0)
		else
			dispel:SetAlpha(canAssist and 1 or 0)
		end
		dispel.container:SetUnit(self.unit)
		dispel.container:UpdateAllAuras()
	end
	local holder = self.auras
	if not holder then return end
	local container = holder.container
	container:SetUnit(self.unit)
	if holder.layout.buffsByReaction then
		local canAttack = UnitCanAttack("player", self.unit)
		if not ns.IsSecret(canAttack) then container:SetAuraGroupEnabled("buffs", not canAttack) end
	end
	holder:Show()
	container:UpdateAllAuras()
end

-- Hides every icon (placeholder frames in preview have no unit to read)
function ns.HideAuras(self)
	if self.auras then self.auras:Hide() end
	if self.dispel then self.dispel:Hide() end
end

---------------------------------------------------------------------------
-- Dispel highlight
---------------------------------------------------------------------------

-- A border and health bar tint in the dispel type's color while the unit has
-- a debuff the player can remove. The "RAID" filter only matches those, and
-- the client works out what the player's class and spec can dispel, so no
-- spell list is needed. Like the icons, it's a CustomAuraContainer, since
-- auras can be secret: a single 1px button whose dispel type textures are
-- anchored to the frame instead of the button.

local DISPEL_BORDER = 2
local DISPEL_TINT_ALPHA = 0.3
local DISPEL_TEXTURE_OPTIONS = { style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset }

-- A white texture on parent (b or a frame inside it) that b's aura colors
local function DispelTexture(parent, b, layer)
	local t = parent:CreateTexture(nil, layer)
	t:SetColorTexture(1, 1, 1)
	b:AddDispelTypeTexture(t, DISPEL_TEXTURE_OPTIONS)
	return t
end

local function InitDispelButton(b, f)
	b:SetSize(1, 1)
	b:EnableMouse(false)

	-- The container takes over the texture's own alpha (and draws it opaque),
	-- so the translucency comes from a child frame's alpha instead
	local tintFrame = CreateFrame("Frame", nil, b)
	tintFrame:SetAllPoints(f.health)
	tintFrame:SetAlpha(DISPEL_TINT_ALPHA)
	DispelTexture(tintFrame, b, "ARTWORK"):SetAllPoints()

	-- Over the frame's own border, so it wins over the aggro color
	local top, bottom = DispelTexture(b, b, "OVERLAY"), DispelTexture(b, b, "OVERLAY")
	local left, right = DispelTexture(b, b, "OVERLAY"), DispelTexture(b, b, "OVERLAY")
	top:SetPoint("TOPLEFT", f)
	top:SetPoint("TOPRIGHT", f)
	top:SetHeight(DISPEL_BORDER)
	bottom:SetPoint("BOTTOMLEFT", f)
	bottom:SetPoint("BOTTOMRIGHT", f)
	bottom:SetHeight(DISPEL_BORDER)
	left:SetPoint("TOPLEFT", f)
	left:SetPoint("BOTTOMLEFT", f)
	left:SetWidth(DISPEL_BORDER)
	right:SetPoint("TOPRIGHT", f)
	right:SetPoint("BOTTOMRIGHT", f)
	right:SetWidth(DISPEL_BORDER)
end

-- Creates f.dispel. Its textures draw above the bars but below f.overlay's
-- icons and pips. ns.UpdateAuras keeps its unit current.
function ns.CreateDispelHighlight(f)
	local holder = CreateFrame("Frame", nil, f)
	holder:SetAllPoints()
	holder:SetFrameLevel(f:GetFrameLevel() + 2)

	local container = CreateFrame("AuraContainer", nil, holder, "CustomAuraContainerTemplate")
	container:SetPoint("TOPLEFT")
	container:SetEditModePreviewEnabled(false)
	container:SetFlowLayoutAnchorPoint("TOPLEFT")
	container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
	container:SetFlowLayoutMaximumLineSize(1)
	container:AddAuraGroup("dispel", "HARMFUL|RAID", {
		maxFrameCount = 1,
		initializeFrame = function(b) InitDispelButton(b, f) end,
		layout = {
			elementWidth = 1, elementHeight = 1, elementSpacing = 0,
			lineSpacing = 0, groupLineSpacing = 0, layoutIndex = 1,
		},
	})

	if f.unit then container:SetUnit(f.unit) end
	container:SetEnabled(true)

	holder.container = container
	f.dispel = holder
	return holder
end
