local addonName, ns = ...

-- Buff/debuff icon grids for unit frames and nameplates. Debuffs come first
-- (nearest the frame), then buffs starting on a fresh row.
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
function ns.UpdateAuras(self)
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
end
