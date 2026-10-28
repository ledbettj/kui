local addonName, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8X8"

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function ShortValue(v)
	if v >= 1e6 then
		return format("%.1fm", v / 1e6)
	elseif v >= 1e4 then
		return format("%.1fk", v / 1e3)
	end
	return tostring(v)
end

-- Health color: grey when dead/offline, class color for players, grey when
-- tapped, otherwise by reaction (all configurable in the Colors section)
local function UnitColor(unit)
	if not UnitIsConnected(unit) or (UnitIsDead(unit) and not UnitIsPlayer(unit)) then
		return 0.5, 0.5, 0.5
	elseif UnitIsPlayer(unit) then
		local _, class = UnitClass(unit)
		local c = class and ns:GetClassColor(class)
		if c then return c[1], c[2], c[3] end
	elseif UnitIsTapDenied and UnitIsTapDenied(unit) then
		-- Near-white: the bar atlas darkens it to a neutral grey
		return 0.9, 0.9, 0.9
	end
	local c = ns:GetReactionColor(unit)
	return c[1], c[2], c[3]
end

-- Textures are applied later by StyleBar, so they can change at runtime
local function CreateBar(parent)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(FLAT)
	bar.bg = bar:CreateTexture(nil, "BACKGROUND")
	bar.bg:SetAllPoints()
	return bar
end

-- solidBg: keep the bar's own flat background instead of a darkened copy of
-- the bar texture (the power bar uses this).
local function StyleBar(bar, textureName, solidBg)
	local atlas, path = ns:GetStatusbar(textureName)
	if atlas then
		bar:GetStatusBarTexture():SetAtlas(atlas)
	else
		bar:SetStatusBarTexture(path)
	end

	if solidBg then return end

	-- Empty portion uses the same art, darkened, so the shading carries across
	if atlas then
		bar.bg:SetAtlas(atlas)
	else
		bar.bg:SetTexture(path)
		bar.bg:SetTexCoord(0, 1, 0, 1)
	end
	bar.bg:SetVertexColor(0.15, 0.15, 0.15)
end
ns.StyleBar = StyleBar

-- Shared font objects: changing one restyles every fontstring using it.
-- Styling (shadow, color) follows the nameplate font.
local function NewFont(name)
	local fo = CreateFont(name)
	fo:CopyFontObject(SystemFont_NamePlate or GameFontHighlightSmall)
	fo:SetTextColor(1, 1, 1)
	fo:SetShadowOffset(1, -1)
	fo:SetShadowColor(0, 0, 0, 1)
	return fo
end

ns.fonts = {
	normal = NewFont("KUIFontNormal"),
	small = NewFont("KUIFontSmall"),
	aura = NewFont("KUIFontAura"),
}

function ns:UpdateFonts()
	local path = ns:GetFontPath(KUIDB.style.font)
	local size = KUIDB.style.fontSize
	ns.fonts.normal:SetFont(path, size, "")
	ns.fonts.small:SetFont(path, size - 2, "")
	ns.fonts.aura:SetFont(path, size - 2, "")
end

local function CreateText(parent, fontObject, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFontObject(fontObject)
	fs:SetJustifyH(justify)
	fs:SetWordWrap(false)
	return fs
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------

local function UpdateHealth(self)
	local unit = self.unit
	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	if max == 0 then max = 1 end

	self.health:SetMinMaxValues(0, max)
	self.health:SetValue(cur)
	self.health:SetStatusBarColor(UnitColor(unit))

	if not UnitIsConnected(unit) then
		self.healthText:SetText("Offline")
	elseif UnitIsGhost(unit) then
		self.healthText:SetText("Ghost")
	elseif UnitIsDead(unit) then
		self.healthText:SetText("Dead")
	elseif self.small then
		self.healthText:SetFormattedText("%d%%", cur / max * 100)
	else
		self.healthText:SetFormattedText("%s / %s", ShortValue(cur), ShortValue(max))
	end
end

local function UpdateCombo(self)
	local cp = GetComboPoints("player", "target") or 0
	for i, pip in ipairs(self.combo) do
		pip:SetShown(i <= cp)
	end
end

local function UpdatePower(self)
	if self.combo then UpdateCombo(self) end
	if not self.power then return end

	local unit = self.unit
	local cur, max = UnitPower(unit), UnitPowerMax(unit)
	local ptype, ptoken = UnitPowerType(unit)
	local c = ns:GetPowerColor(ptoken, ptype)

	self.power:SetMinMaxValues(0, max > 0 and max or 1)
	self.power:SetValue(cur)
	self.power:SetStatusBarColor(c[1], c[2], c[3])

	if self.powerText and self.powerText:IsShown() then
		self.powerText:SetFormattedText("%d / %d", cur, max)
	end
end

-- Power text appears only while the mouse is over the power bar. The bar
-- itself doesn't take mouse input (that would swallow clicks meant for
-- targeting/Clique), so check IsMouseOver while the frame is hovered.
local function PowerHover_OnUpdate(bar)
	local f = bar:GetParent()
	local over = bar:IsMouseOver()
	if over ~= f.powerText:IsShown() then
		f.powerText:SetShown(over)
		if over then UpdatePower(f) end
	end
end

local function UpdateName(self)
	local unit = self.unit
	local name = UnitName(unit) or ""

	-- Compact frames skip the level unless they opt in (nameplates do)
	if unit == "player" or (self.small and not self.showLevel) then
		self.nameText:SetText(name)
		return
	end

	local level = UnitLevel(unit)
	local c = GetQuestDifficultyColor and GetQuestDifficultyColor(level > 0 and level or 99)
	local hex = c and format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255) or "|cffffffff"
	local classification = UnitClassification(unit)
	local suffix = (classification == "elite" or classification == "worldboss") and "+"
		or (classification == "rare" or classification == "rareelite") and "r"
		or ""

	self.nameText:SetFormattedText("%s%s%s|r %s", hex, level > 0 and level or "??", suffix, name)
end

local function UpdatePortrait(self)
	local portrait = self.portrait
	if not portrait then return end

	local unit = self.unit
	if UnitIsVisible(unit) and UnitIsConnected(unit) then
		portrait:SetUnit(unit)
		portrait:SetPortraitZoom(1)
	else
		-- Out of visual range the model can't load; leave the dark backdrop
		portrait:ClearModel()
	end
end

---------------------------------------------------------------------------
-- Auras
---------------------------------------------------------------------------

local AURA_SPACING = 2

-- "above": rows above the frame growing upward, as many per row as fit the
-- frame width. "right": compact rows beside the frame growing downward.
-- debuffFilter: defaults to all harmful auras. noMouse: no tooltips, so
-- the icons don't block clicks (nameplates).
local AURA_LAYOUTS = {
	above = { size = 22, maxBuffs = 32, maxDebuffs = 16, growUp = true },
	right = { size = 16, maxBuffs = 8, maxDebuffs = 8, perRow = 8 },
	nameplate = { size = 18, maxBuffs = 4, maxDebuffs = 6, growUp = true, debuffFilter = "HARMFUL|PLAYER", noMouse = true },
}
ns.AURA_LAYOUTS = AURA_LAYOUTS
ns.AURA_SPACING = AURA_SPACING

local function AuraButton_OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 15, -25)
	if self.isBuff then
		GameTooltip:SetUnitBuffByAuraInstanceID(self.unit, self.auraInstanceID, self.filter)
	else
		GameTooltip:SetUnitDebuffByAuraInstanceID(self.unit, self.auraInstanceID, self.filter)
	end
end

local function CreateAuraButton(container)
	local b = CreateFrame("Frame", nil, container)
	b:SetSize(container.layout.size, container.layout.size)
	if not container.layout.noMouse then
		b:EnableMouse(true)
		b:SetScript("OnEnter", AuraButton_OnEnter)
		b:SetScript("OnLeave", GameTooltip_Hide)
	end

	-- 1px border behind the icon; tinted by dispel type for debuffs
	b.border = b:CreateTexture(nil, "BACKGROUND")
	b.border:SetAllPoints()
	b.border:SetColorTexture(1, 1, 1)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	b.cooldown = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints(b.icon)
	b.cooldown:SetReverse(true)
	b.cooldown:SetHideCountdownNumbers(true)

	b.count = b.cooldown:CreateFontString(nil, "OVERLAY")
	b.count:SetFontObject(ns.fonts.aura)
	b.count:SetPoint("BOTTOMRIGHT", 1, 0)

	return b
end

-- Lays out debuffs first (nearest the frame), then buffs starting on a fresh
-- row.
local function UpdateAuras(self)
	local container = self.auras
	if not container then return end

	local unit = self.unit
	local layout = container.layout
	local step = layout.size + AURA_SPACING
	local perRow = container.perRow
	local n, row = 0, 0
	local col = 0

	local function Place(aura, filter, isBuff)
		n = n + 1
		local b = container.buttons[n]
		if not b then
			b = CreateAuraButton(container)
			container.buttons[n] = b
		end

		b.unit, b.filter, b.isBuff = unit, filter, isBuff
		b.auraInstanceID = aura.auraInstanceID
		b.icon:SetTexture(aura.icon)
		b.count:SetText(aura.applications > 1 and aura.applications or "")
		CooldownFrame_Set(b.cooldown, aura.expirationTime - aura.duration, aura.duration, aura.duration > 0, true)

		if isBuff then
			b.border:SetVertexColor(0, 0, 0)
		else
			AuraUtil.SetAuraBorderColor(b.border, aura.dispelName)
		end

		if col >= perRow then
			col, row = 0, row + 1
		end
		b:ClearAllPoints()
		if layout.growUp then
			b:SetPoint("BOTTOMLEFT", col * step, row * step)
		else
			b:SetPoint("TOPLEFT", col * step, -row * step)
		end
		b:Show()
		col = col + 1
	end

	local count = 0
	local debuffFilter = layout.debuffFilter or "HARMFUL"
	AuraUtil.ForEachAura(unit, debuffFilter, layout.maxDebuffs, function(aura)
		Place(aura, debuffFilter, false)
		count = count + 1
		return count >= layout.maxDebuffs
	end, true)

	if col > 0 then
		col, row = 0, row + 1
	end

	count = 0
	AuraUtil.ForEachAura(unit, "HELPFUL", layout.maxBuffs, function(aura)
		Place(aura, "HELPFUL", true)
		count = count + 1
		return count >= layout.maxBuffs
	end, true)

	for i = n + 1, #container.buttons do
		container.buttons[i]:Hide()
	end
end

local function HideAuras(self)
	if not self.auras then return end
	for _, b in ipairs(self.auras.buttons) do
		b:Hide()
	end
end

local RAID_ICON_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local NAME_INSET = 4

-- Raid marker inside the health bar, before the name; the name shifts right
-- to make room while one is set
local function UpdateRaidIcon(self)
	local icon = self.raidIcon
	local index = UnitExists(self.unit) and GetRaidTargetIndex(self.unit)
	if index then
		SetRaidTargetIconTexture(icon, index)
		icon:Show()
	else
		icon:Hide()
	end
	self.nameText:SetPoint("LEFT", index and (NAME_INSET + icon:GetWidth() + 2) or NAME_INSET, 0)
end

-- Party members out of range fade (SetAlpha is allowed on secure frames in
-- combat). Units the client can't range-check stay opaque.
local function UpdateRange(self)
	local inRange, checkedRange = UnitInRange(self.unit)
	self:SetAlpha((checkedRange and not inRange) and KUIDB.style.outOfRangeAlpha or 1)
end

local function OnUpdateRange(self, elapsed)
	self.rangeElapsed = (self.rangeElapsed or 0) + elapsed
	if self.rangeElapsed > 0.25 then
		self.rangeElapsed = 0
		UpdateRange(self)
	end
end

local function UpdateAll(self)
	if not UnitExists(self.unit) then
		-- Only reachable in preview mode: show a placeholder
		if self.portrait then self.portrait:ClearModel() end
		UpdateRaidIcon(self)
		HideAuras(self)
		if self.castbar then ns:PreviewCastbar(self.castbar) end
		self.nameText:SetText(self.label)
		self.healthText:SetText("")
		self.health:SetMinMaxValues(0, 1)
		self.health:SetValue(1)
		self.health:SetStatusBarColor(0.3, 0.3, 0.3)
		if self.power then
			self.power:SetMinMaxValues(0, 1)
			self.power:SetValue(0)
		end
		return
	end

	UpdateHealth(self)
	UpdatePower(self)
	UpdateName(self)
	UpdatePortrait(self)
	UpdateRaidIcon(self)
	UpdateAuras(self)
	if self.castbar then ns:RefreshCastbar(self.castbar) end
end
ns.UpdateAll = UpdateAll

-- Shared with the nameplates, which reuse these pieces on their own frames
ns.CreateBar = CreateBar
ns.CreateText = CreateText
ns.UpdateHealth = UpdateHealth
ns.UpdateName = UpdateName
ns.UpdateAuras = UpdateAuras

local eventHandlers = {
	UNIT_HEALTH = UpdateHealth,
	UNIT_MAXHEALTH = UpdateHealth,
	UNIT_CONNECTION = UpdateHealth,
	UNIT_FACTION = UpdateHealth,
	UNIT_POWER_FREQUENT = UpdatePower,
	UNIT_MAXPOWER = UpdatePower,
	UNIT_DISPLAYPOWER = UpdatePower,
	UNIT_NAME_UPDATE = UpdateName,
	UNIT_LEVEL = UpdateName,
	UNIT_MODEL_CHANGED = UpdatePortrait,
	UNIT_PORTRAIT_UPDATE = UpdatePortrait,
	UNIT_AURA = UpdateAuras,
}

local function OnEvent(self, event, ...)
	if event == "RAID_TARGET_UPDATE" then
		return UpdateRaidIcon(self)
	end
	local handler = eventHandlers[event]
	if handler then
		handler(self)
	else
		-- Target/focus/pet changed: unit is a different entity now
		UpdateAll(self)
	end
end

-- Target-of-target gets no reliable events, so poll it while shown
local function OnUpdatePoll(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed > 0.2 then
		self.elapsed = 0
		UpdateAll(self)
	end
end

-- Some events may not exist on every client build; don't let one bad
-- registration take the whole addon down.
local function SafeRegisterUnitEvent(f, event, ...)
	pcall(f.RegisterUnitEvent, f, event, ...)
end

---------------------------------------------------------------------------
-- Runtime styling / layout (driven by the config panel)
---------------------------------------------------------------------------

function ns:StyleFrame(f)
	StyleBar(f.health, KUIDB.style.healthTexture)
	if f.power then
		StyleBar(f.power, KUIDB.style.powerTexture, true)
		f.power.bg:SetColorTexture(ns:GetEmptyColor())
	end
	if f.castbar then
		ns:StyleCastbar(f.castbar)
	end
	-- Swapping textures drops vertex colors, so recolor
	UpdateAll(f)
end

-- Width changes touch a secure frame; callers handle combat deferral
-- r, g, b, a for the background of empty power bars and idle cast bars
function ns:GetEmptyColor()
	local c = KUIDB.style.emptyColor
	return c[1], c[2], c[3], KUIDB.style.emptyAlpha
end

-- Applies the configured border and background to any BackdropTemplate
-- frame. Returns the inner inset (border + padding) where content starts.
function ns:ApplyBackdrop(f, small)
	local style = KUIDB.style

	-- Small frames get a proportionally thinner border
	local edge = style.borderSize
	if small then edge = math.max(1, math.floor(edge * 2 / 3 + 0.5)) end
	local path, insetScale = ns:GetBorder(style.border)
	local inset = edge * insetScale

	f:SetBackdrop({
		bgFile = FLAT,
		edgeFile = path,
		edgeSize = edge,
		insets = { left = inset, right = inset, top = inset, bottom = inset },
	})
	f:SetBackdropColor(0, 0, 0, style.bgAlpha)
	local c = style.borderColor
	f:SetBackdropBorderColor(c[1], c[2], c[3], 1)

	return math.floor(inset + 0.5) + style.padding
end

-- Border, background and everything inside it. The border's inset decides
-- where the portrait and bars sit, so they're anchored here too.
local function LayoutContents(f)
	local cfg = f.cfg
	local inset = ns:ApplyBackdrop(f, f.small)
	local powerHeight = 0
	if cfg.powerFromSettings then
		powerHeight = KUIDB.style.powerHeight
	elseif cfg.power then
		powerHeight = cfg.powerHeight or math.floor(cfg.h * 0.25)
	end
	local gap = 1
	local left = inset

	-- 3D portrait, square, filling the inner height on the left
	if f.portrait then
		local size = cfg.h - inset * 2
		f.portrait:ClearAllPoints()
		f.portrait:SetPoint("TOPLEFT", inset, -inset)
		f.portrait:SetSize(size, size)
		left = inset + size + gap
	end

	-- Stacked bottom-up beside the portrait: cast bar, power, then health
	-- takes whatever height is left
	local bottom = inset

	if f.castbar and not f.castHolder then
		f.castbar:ClearAllPoints()
		f.castbar:SetPoint("BOTTOMLEFT", left, bottom)
		f.castbar:SetPoint("BOTTOMRIGHT", -inset, bottom)
		f.castbar:SetHeight(KUIDB.castbar.height)
		ns:LayoutCastbar(f.castbar)
		bottom = bottom + KUIDB.castbar.height + gap
	end

	if f.power then
		f.power:ClearAllPoints()
		f.power:SetPoint("BOTTOMLEFT", left, bottom)
		f.power:SetPoint("BOTTOMRIGHT", -inset, bottom)
		f.power:SetHeight(powerHeight)
		bottom = bottom + powerHeight + gap
	end

	f.health:ClearAllPoints()
	f.health:SetPoint("TOPLEFT", left, -inset)
	f.health:SetPoint("TOPRIGHT", -inset, -inset)
	f.health:SetPoint("BOTTOM", 0, bottom)

	-- Detached cast bar (focus): own bordered holder under the frame, only
	-- shown while casting
	if f.castHolder then
		local holder, h = f.castHolder, KUIDB.castbar.focusHeight
		holder:ClearAllPoints()
		holder:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -2)
		holder:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -2)
		holder:SetHeight(h)
		local holderInset = ns:ApplyBackdrop(holder, true)
		f.castbar:ClearAllPoints()
		f.castbar:SetPoint("TOPLEFT", holderInset, -holderInset)
		f.castbar:SetPoint("TOPRIGHT", -holderInset, -holderInset)
		f.castbar:SetHeight(math.max(1, h - holderInset * 2))
		ns:LayoutCastbar(f.castbar)
	end
end

function ns:LayoutFrame(f)
	local w = ns:GetWidth(f.unit)
	f:SetWidth(w)
	LayoutContents(f)
	if f.auras then
		local layout = f.auras.layout
		f.auras.perRow = layout.perRow
			or math.max(1, math.floor((w + AURA_SPACING) / (layout.size + AURA_SPACING)))
		f.auras:SetWidth(f.auras.perRow * (layout.size + AURA_SPACING))
		UpdateAuras(f)
	end
end

---------------------------------------------------------------------------
-- Frame factory
---------------------------------------------------------------------------

function ns:CreateUnitFrame(unit, cfg)
	local f = CreateFrame("Button", "KUI_" .. unit, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
	f.unit = unit
	f.cfg = cfg
	f.label = cfg.label
	f.small = cfg.h < 30

	f:SetHeight(cfg.h)

	-- Secure click handling: left = target, right = unit menu
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")

	f:SetScript("OnEnter", UnitFrame_OnEnter)
	f:SetScript("OnLeave", UnitFrame_OnLeave)

	-- Portrait and bars; positioned by LayoutContents
	if cfg.portrait then
		f.portrait = CreateFrame("PlayerModel", nil, f)
	end

	f.health = CreateBar(f)

	if cfg.power then
		f.power = CreateBar(f)
	end

	if cfg.castbar then
		f.castbar = ns:CreateCastbar(f)
	elseif cfg.detachedCastbar then
		f.castHolder = CreateFrame("Frame", nil, f, "BackdropTemplate")
		f.castHolder.unit = unit
		f.castbar = ns:CreateCastbar(f.castHolder)
		f.castbar.container = f.castHolder
		f.castHolder:Hide()
	end

	-- Buffs/debuffs
	if cfg.auras then
		local layout = AURA_LAYOUTS[cfg.auras]
		f.auras = CreateFrame("Frame", nil, f)
		f.auras.layout = layout
		f.auras.buttons = {}
		f.auras:SetHeight(layout.size)
		if layout.growUp then
			f.auras:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 0, 4)
		else
			f.auras:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
		end
	end

	-- Child frame above the bars for combo pips; textures on f itself would
	-- render underneath the bars.
	f.overlay = CreateFrame("Frame", nil, f)
	f.overlay:SetAllPoints()
	f.overlay:SetFrameLevel(f:GetFrameLevel() + 5)

	-- Text
	local font = f.small and ns.fonts.small or ns.fonts.normal
	f.nameText = CreateText(f.health, font, "LEFT")
	f.nameText:SetPoint("LEFT", NAME_INSET, 0)

	f.raidIcon = f.health:CreateTexture(nil, "OVERLAY")
	f.raidIcon:SetTexture(RAID_ICON_TEXTURE)
	f.raidIcon:SetSize(f.small and 12 or 14, f.small and 12 or 14)
	f.raidIcon:SetPoint("LEFT", 3, 0)
	f.raidIcon:Hide()

	f.healthText = CreateText(f.health, font, "RIGHT")
	f.healthText:SetPoint("RIGHT", -4, 0)
	f.nameText:SetPoint("RIGHT", f.healthText, "LEFT", -4, 0)

	if unit == "player" and f.power then
		f.powerText = CreateText(f.power, ns.fonts.small, "CENTER")
		f.powerText:SetPoint("CENTER")
		f.powerText:Hide()
		f:HookScript("OnEnter", function(self)
			self.power:SetScript("OnUpdate", PowerHover_OnUpdate)
		end)
		f:HookScript("OnLeave", function(self)
			self.power:SetScript("OnUpdate", nil)
			self.powerText:Hide()
		end)
	end

	-- Combo points (target only)
	if cfg.combo then
		f.combo = {}
		for i = 1, 5 do
			local pip = f.overlay:CreateTexture(nil, "OVERLAY")
			pip:SetTexture(FLAT)
			pip:SetVertexColor(1, 0.8, 0.1)
			pip:SetSize(12, 4)
			pip:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 4 + (i - 1) * 14, -1)
			pip:Hide()
			f.combo[i] = pip
		end
	end

	-- Events
	for event in pairs(eventHandlers) do
		if cfg.combo and event == "UNIT_POWER_FREQUENT" then
			SafeRegisterUnitEvent(f, event, unit, "player")
		else
			SafeRegisterUnitEvent(f, event, unit)
		end
	end
	if unit == "target" then
		f:RegisterEvent("PLAYER_TARGET_CHANGED")
		pcall(f.RegisterEvent, f, "COMBO_TARGET_CHANGED")
	elseif unit == "focus" then
		pcall(f.RegisterEvent, f, "PLAYER_FOCUS_CHANGED")
	elseif unit == "pet" then
		f:RegisterUnitEvent("UNIT_PET", "player")
	elseif cfg.party then
		-- partyN can point at a different player after roster changes
		f:RegisterEvent("GROUP_ROSTER_UPDATE")
	end
	f:RegisterEvent("RAID_TARGET_UPDATE")
	f:SetScript("OnEvent", OnEvent)
	f:SetScript("OnShow", UpdateAll)
	if cfg.poll then
		f:SetScript("OnUpdate", OnUpdatePoll)
	elseif cfg.party then
		f:SetScript("OnUpdate", OnUpdateRange)
	end

	ns:LayoutFrame(f)
	ns:StyleFrame(f)
	ns:WatchFrame(f)

	-- Click-cast support (Clique et al). Must come after OnEnter/OnLeave are
	-- set, since Clique hooks those rather than replacing them.
	ClickCastFrames = ClickCastFrames or {}
	ClickCastFrames[f] = true

	return f
end
