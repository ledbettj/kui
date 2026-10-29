local addonName, ns = ...

-- XP and reputation bars replacing Blizzard's segmented status tracking
-- bars, centered at the top or bottom edge of the screen. Colors come from
-- the palette: class Warlock purple for XP, mana for pending rested XP,
-- friendly green for rep.

local GAP = 2
local EDGE_OFFSET = 2

local holder
local bars = {}

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

local function CanShowXP()
	if GameRulesUtil and GameRulesUtil.CanShowExperienceBar then
		return GameRulesUtil.CanShowExperienceBar()
	end
	return not IsPlayerAtEffectiveMaxLevel() and not IsXPUserDisabled()
end

local function WatchedFaction()
	local data = C_Reputation.GetWatchedFactionData()
	if data and data.name and data.name ~= "" then return data end
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local function SetColor(statusbar, c, alpha)
	statusbar:SetStatusBarColor(c[1], c[2], c[3], alpha or 1)
end

local function UpdateXP()
	local bar = bars.xp
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if max <= 0 then max = 1 end
	local rested = GetXPExhaustion() or 0

	bar.status:SetMinMaxValues(0, max)
	bar.status:SetValue(cur)
	-- Rested bonus shows as a mana-colored stretch ahead of current XP
	bar.rested:SetMinMaxValues(0, max)
	bar.rested:SetValue(math.min(cur + rested, max))

	if rested > 0 then
		bar.text:SetFormattedText("%d / %d (%.1f%%)  +%d rested", cur, max, cur / max * 100, rested)
	else
		bar.text:SetFormattedText("%d / %d (%.1f%%)", cur, max, cur / max * 100)
	end
end

local function UpdateRep()
	local bar = bars.rep
	local data = WatchedFaction()
	if not data then return end

	local min, max, value = data.currentReactionThreshold, data.nextReactionThreshold, data.currentStanding
	local span = math.max(1, max - min)
	bar.status:SetMinMaxValues(0, span)
	bar.status:SetValue(value - min)

	local standing = _G["FACTION_STANDING_LABEL" .. (data.reaction or 0)] or ""
	bar.text:SetFormattedText("%s - %s  %d / %d", data.name, standing, value - min, span)
end

-- Shows whichever bars apply and stacks them away from the screen edge:
-- XP against the edge, reputation just inside it
local function Arrange()
	local S = KUIDB.statusbars
	local showXP, showRep = CanShowXP(), WatchedFaction() ~= nil

	bars.xp:SetShown(showXP)
	bars.rep:SetShown(showRep)

	local atTop = S.position == "Top"
	local point = atTop and "TOP" or "BOTTOM"
	local direction = atTop and -1 or 1
	local offset = 0
	for _, key in ipairs({ "xp", "rep" }) do
		local bar = bars[key]
		if bar:IsShown() then
			bar:ClearAllPoints()
			bar:SetPoint(point, holder, point, 0, offset * direction)
			offset = offset + S.height + GAP
		end
	end

	if showXP then UpdateXP() end
	if showRep then UpdateRep() end
end

---------------------------------------------------------------------------
-- Layout / style
---------------------------------------------------------------------------

function ns:LayoutStatusBars()
	if not holder then return end
	local S = KUIDB.statusbars
	holder:SetSize(S.width, S.height)
	holder:ClearAllPoints()
	if S.position == "Top" then
		holder:SetPoint("TOP", UIParent, "TOP", 0, -EDGE_OFFSET)
	else
		holder:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, EDGE_OFFSET)
	end

	for _, bar in pairs(bars) do
		bar:SetSize(S.width, S.height)
		local inset = ns:ApplyBackdrop(bar, true)
		bar.status:ClearAllPoints()
		bar.status:SetPoint("TOPLEFT", inset, -inset)
		bar.status:SetPoint("BOTTOMRIGHT", -inset, inset)
		if bar.rested then bar.rested:SetAllPoints(bar.status) end
	end
	Arrange()
end

function ns:StyleStatusBars()
	if not holder then return end
	local texture = KUIDB.statusbars.texture

	ns.StyleBar(bars.xp.status, texture)
	ns.StyleBar(bars.xp.rested, texture, true)
	ns.StyleBar(bars.rep.status, texture)

	SetColor(bars.xp.status, ns:GetColor("class", "WARLOCK"))
	SetColor(bars.xp.rested, ns:GetColor("power", "MANA"), 0.6)
	SetColor(bars.rep.status, ns:GetColor("reaction", "friendly"))
end

---------------------------------------------------------------------------
-- Creation
---------------------------------------------------------------------------

local function CreateStatusBar(withRested)
	local bar = CreateFrame("Frame", nil, holder, "BackdropTemplate")
	bar:EnableMouse(true)

	bar.status = ns.CreateBar(bar)
	if withRested then
		-- Drawn under the XP fill; its own background stays empty so the
		-- XP bar's background shows through
		bar.rested = CreateFrame("StatusBar", nil, bar)
		bar.rested:SetStatusBarTexture(ns.FLAT_TEXTURE)
		bar.rested:SetFrameLevel(bar.status:GetFrameLevel())
		bar.status:SetFrameLevel(bar.rested:GetFrameLevel() + 1)
		bar.status.bg:SetParent(bar.rested)
		bar.status.bg:SetDrawLayer("BACKGROUND")
	end

	-- Numbers only on hover, to keep the screen edge quiet
	bar.text = ns.CreateText(bar.status, ns.fonts.small, "CENTER")
	bar.text:SetPoint("CENTER")
	bar.text:Hide()
	bar:SetScript("OnEnter", function(self) self.text:Show() end)
	bar:SetScript("OnLeave", function(self) self.text:Hide() end)

	return bar
end

local function HideBlizzard()
	local manager = StatusTrackingBarManager
	if not manager then return end
	manager:Hide()
	-- Blizzard re-shows it on various updates
	hooksecurefunc(manager, "Show", manager.Hide)
end

function ns:InitStatusBars()
	if not KUIDB.statusbars.enabled then return end

	HideBlizzard()

	holder = CreateFrame("Frame", "KUI_StatusBars", UIParent)

	bars.xp = CreateStatusBar(true)
	bars.rep = CreateStatusBar(false)

	for _, event in ipairs({
		"PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION",
		"PLAYER_ENTERING_WORLD", "ENABLE_XP_GAIN", "DISABLE_XP_GAIN",
	}) do
		pcall(holder.RegisterEvent, holder, event)
	end
	holder:SetScript("OnEvent", Arrange)

	ns:LayoutStatusBars()
	ns:StyleStatusBars()
end
