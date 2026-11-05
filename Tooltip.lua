local addonName, ns = ...

-- Tooltips in the KUI border and background (optional), with:
--   * item tooltips bordered in the item's quality color (green and up)
--   * player names in their class color
--   * a "Target:" line for units that have one
--   * the health bar in KUI's texture, colored like the unit frames
--   * unit tooltips optionally hidden in combat
--
-- Blizzard's NineSlice border is made invisible rather than removed: it
-- keeps getting reapplied, and the alpha is the one thing it doesn't reset.
--
-- The health bar handles secret values in a secure mixin that Blizzard warns
-- addon taint can break, so KUI only colors it once per unit and never hooks
-- its updates. Anything handed over as a secret (class, names, unit
-- comparisons in restricted content) is skipped.

local IsSecret = ns.IsSecret

local TOOLTIPS = {
	"GameTooltip", "ItemRefTooltip",
	"ShoppingTooltip1", "ShoppingTooltip2",
	"ItemRefShoppingTooltip1", "ItemRefShoppingTooltip2",
}

local backdrops = {} -- tooltip -> its KUI backdrop frame
local healthBar = GameTooltipStatusBar

local function Hex(c)
	return format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

local function ResetBorder(tt)
	local bd = backdrops[tt]
	if not bd then return end
	local c = ns.db.style.borderColor
	bd:SetBackdropBorderColor(c[1], c[2], c[3], 1)
end

-- Post-calls run for every tooltip, including ones KUI doesn't style
local function OnTooltipSetItem(tt)
	local bd = backdrops[tt]
	if not bd then return end
	local _, link = tt:GetItem()
	local quality = link and select(3, C_Item.GetItemInfo(link))
	local c = quality and quality >= 2 and ITEM_QUALITY_COLORS[quality]
	if c then
		bd:SetBackdropBorderColor(c.r, c.g, c.b, 1)
	else
		ResetBorder(tt)
	end
end

-- The unit frames' health color, or nil while what it's based on (class,
-- reaction) is secret
local function UnitColor(unit)
	local _, class = UnitClass(unit)
	if IsSecret(class) or IsSecret(UnitReaction(unit, "player")) then return nil end
	return ns.UnitColor(unit)
end

-- "Target: Name", or "Target: YOU" in red
local function AddTargetLine(tt, unit)
	local target = unit .. "target"
	if not UnitExists(target) then return end
	local isPlayer, name = UnitIsUnit(target, "player"), UnitName(target)
	if IsSecret(isPlayer) or IsSecret(name) then return end
	local text
	if isPlayer then
		text = "|cffff4040YOU|r"
	else
		local c = UnitColor(target)
		text = (c and Hex(c) or "|cffffffff") .. (name or "?") .. "|r"
	end
	tt:AddLine("Target: " .. text, 1, 1, 1)
end

local function OnTooltipSetUnit(tt)
	local _, unit = tt:GetUnit()
	if not unit or IsSecret(unit) then return end
	local T = ns.db.tooltip

	if T.hideInCombat and InCombatLockdown() then
		tt:Hide()
		return
	end

	if T.classColors and UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local c = class and not IsSecret(class) and ns:GetClassColor(class)
		local name = tt:GetName()
		local line = name and _G[name .. "TextLeft1"]
		if c and line then line:SetTextColor(c[1], c[2], c[3]) end
	end

	-- The bar's color is set once here (see the notes at the top)
	if tt == GameTooltip and healthBar and healthBar.bg then
		local c = UnitColor(unit)
		if c then healthBar:SetStatusBarColor(c[1], c[2], c[3]) end
	end

	if T.showTarget then
		AddTargetLine(tt, unit)
		tt:Show() -- resizes to fit the new line
	end
end

-- In its own small border just under the tooltip, the same width
local function StyleHealthBar()
	if not (healthBar and healthBar.bg) then return end
	ns.StyleBar(healthBar, ns.db.style.healthTexture)
	healthBar:SetHeight(6)
	local inset = ns.WrapBorder(healthBar.kuiBorder, healthBar, true)
	healthBar:ClearAllPoints()
	healthBar:SetPoint("TOPLEFT", GameTooltip, "BOTTOMLEFT", inset, -inset - 1)
	healthBar:SetPoint("TOPRIGHT", GameTooltip, "BOTTOMRIGHT", -inset, -inset - 1)
end

-- Border, background and health bar texture follow the KUI style
function ns:StyleTooltips()
	for tt, bd in pairs(backdrops) do
		ns:ApplyBackdrop(bd)
		ResetBorder(tt)
	end
	StyleHealthBar()
end

local function Restyle(tt)
	if tt.NineSlice then tt.NineSlice:SetAlpha(0) end
	local bd = CreateFrame("Frame", nil, tt, "BackdropTemplate")
	bd:SetAllPoints()
	-- Same level as the tooltip, so its background and border layers sit
	-- under the tooltip's text, as Blizzard's NineSlice did
	bd:SetUsingParentLevel(true)
	backdrops[tt] = bd

	if tt:HasScript("OnTooltipCleared") then
		tt:HookScript("OnTooltipCleared", ResetBorder)
	end
end

-- The unit tooltip additions follow their settings live; the restyle's
-- hooks can't be removed, so turning it off needs a /reload
function ns:InitTooltips()
	local restyle = ns.db.tooltip.enabled

	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnTooltipSetUnit)
	if restyle then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipSetItem)
	end

	if not restyle then return end
	for _, name in ipairs(TOOLTIPS) do
		local tt = _G[name]
		if tt then Restyle(tt) end
	end

	if healthBar then
		healthBar.bg = healthBar:CreateTexture(nil, "BACKGROUND")
		healthBar.bg:SetAllPoints()
		healthBar.kuiBorder = CreateFrame("Frame", nil, healthBar, "BackdropTemplate")
		healthBar.kuiBorder:SetFrameLevel(healthBar:GetFrameLevel() + 1)
	end

	ns:StyleTooltips()
end
