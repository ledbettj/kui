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

local function OnTooltipSetItem(tt)
	local _, link = tt:GetItem()
	local quality = link and select(3, GetItemInfo(link))
	local c = quality and quality >= 2 and ITEM_QUALITY_COLORS[quality]
	if c then
		backdrops[tt]:SetBackdropBorderColor(c.r, c.g, c.b, 1)
	else
		ResetBorder(tt)
	end
end

-- "Target: Name", or "Target: YOU" in red
local function AddTargetLine(tt, unit)
	local target = unit .. "target"
	if not UnitExists(target) then return end
	local text
	if UnitIsUnit(target, "player") then
		text = "|cffff4040YOU|r"
	else
		text = Hex(ns.UnitColor(target)) .. (UnitName(target) or "?") .. "|r"
	end
	tt:AddLine("Target: " .. text, 1, 1, 1)
end

local function OnTooltipSetUnit(tt)
	local _, unit = tt:GetUnit()
	if not unit then return end
	local T = ns.db.tooltip

	if T.hideInCombat and InCombatLockdown() then
		tt:Hide()
		return
	end

	if T.classColors and UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local c = class and ns:GetClassColor(class)
		local line = _G[tt:GetName() .. "TextLeft1"]
		if c and line then line:SetTextColor(c[1], c[2], c[3]) end
	end

	if T.showTarget then
		AddTargetLine(tt, unit)
		tt:Show() -- resizes to fit the new line
	end
end

-- Blizzard colors the bar green-to-red on every value change; this runs
-- after it
local function OnHealthChanged(bar)
	local _, unit = GameTooltip:GetUnit()
	if not unit then return end
	local c = ns.UnitColor(unit)
	bar:SetStatusBarColor(c[1], c[2], c[3])
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

	tt:HookScript("OnTooltipCleared", ResetBorder)
	if tt:HasScript("OnTooltipSetItem") then
		tt:HookScript("OnTooltipSetItem", OnTooltipSetItem)
	end
end

-- The unit tooltip additions follow their settings live; the restyle's
-- hooks can't be removed, so turning it off needs a /reload
function ns:InitTooltips()
	GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)

	if not ns.db.tooltip.enabled then return end
	for _, name in ipairs(TOOLTIPS) do
		local tt = _G[name]
		if tt then Restyle(tt) end
	end

	if healthBar then
		healthBar.bg = healthBar:CreateTexture(nil, "BACKGROUND")
		healthBar.bg:SetAllPoints()
		healthBar.kuiBorder = CreateFrame("Frame", nil, healthBar, "BackdropTemplate")
		healthBar.kuiBorder:SetFrameLevel(healthBar:GetFrameLevel() + 1)
		healthBar:HookScript("OnValueChanged", OnHealthChanged)
	end

	ns:StyleTooltips()
end
