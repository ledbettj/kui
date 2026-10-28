local addonName, ns = ...

ns.frames = {}

-- Unit layout defaults. Frames are positioned by ApplyPositions from the
-- layout settings below rather than individually.
-- widthFrom: share another unit's width setting so the pair always matches.
ns.order = { "player", "target", "targettarget", "pet", "focus", "party1", "party2", "party3", "party4" }
ns.defaults = {
	player       = { label = "Player", w = 234, h = 56, power = true, powerFromSettings = true, portrait = true, auras = "above", castbar = true },
	target       = { label = "Target", w = 234, h = 56, power = true, powerFromSettings = true, portrait = true, auras = "above", castbar = true, combo = true },
	targettarget = { label = "ToT",    w = 108, h = 22, poll = true },
	pet          = { label = "Pet",    w = 108, h = 22, power = true },
	focus        = { label = "Focus",  w = 108, h = 22, widthFrom = "targettarget", detachedCastbar = true },
}
-- Party: the other four members (like Blizzard's classic party frames, the
-- player isn't included). All share party1's width.
for i = 1, 4 do
	ns.defaults["party" .. i] = {
		label = "Party " .. i, w = 150, h = 36, power = true, powerHeight = 8, auras = "right",
		party = true, widthFrom = i > 1 and "party1" or nil,
	}
end

ns.styleDefaults = {
	font = "Arial Narrow",
	fontSize = 11,
	healthTexture = "Modern",
	powerTexture = "Modern",
	border = "Rounded",
	borderSize = 12, -- small frames use 2/3 of this
	borderColor = { 0.5, 0.5, 0.5 },
	bgAlpha = 0.8,
	padding = 1, -- gap between the border and the bars/portrait
	powerHeight = 10, -- player/target only; party and pet keep fixed sizes
	outOfRangeAlpha = 0.45, -- party members out of range
	-- Background of empty power bars and idle cast bars
	emptyColor = { 0, 0, 0 },
	emptyAlpha = 0.5,
}

--   [focus] [player] - - | - - [target] [tot]
-- y: vertical offset of the whole row from screen center
-- centerGap: distance from the center line to player's right / target's left edge
-- sideGap: distance between player-focus and target-tot (always symmetric)
ns.layoutDefaults = {
	y = -200,
	centerGap = 120,
	sideGap = 8,
	-- Party column, top-left anchored, the classic spot
	partyX = 20,
	partyY = -180,
	partySpacing = 14,
}

-- Restyling of Blizzard's action buttons (layout stays with Edit Mode)
ns.actionbarDefaults = {
	enabled = true,
	showHotkeys = true,
	showMacroNames = true,
	rangeColor = true,
	activeColor = { 1, 0.82, 0 }, -- border color while an action is active
}

ns.nameplateDefaults = {
	enabled = true,
	width = 130,
	height = 14,
	castHeight = 12,
	highlightTarget = true,
	targetColor = { 1, 0.82, 0 }, -- border color on the current target's plate
}

-- Cast bar row inside the player/target frames, under the power bar
ns.castbarDefaults = {
	height = 12,
	focusHeight = 12, -- detached bar under the focus frame
	texture = "Modern",
	showIcon = true,
}

function ns:GetWidth(unit)
	local key = ns.defaults[unit].widthFrom or unit
	return KUIDB.widths[key] or ns.defaults[key].w
end

local function Print(...)
	print("|cff33ff99KUI|r:", ...)
end
ns.Print = Print

---------------------------------------------------------------------------
-- Positioning
---------------------------------------------------------------------------

function ns:ApplyPositions()
	local L, F = KUIDB.layout, ns.frames
	for _, f in pairs(F) do
		f:ClearAllPoints()
	end

	F.player:SetPoint("RIGHT", UIParent, "CENTER", -L.centerGap, L.y)
	F.target:SetPoint("LEFT", UIParent, "CENTER", L.centerGap, L.y)
	F.focus:SetPoint("RIGHT", F.player, "LEFT", -L.sideGap, 0)
	F.targettarget:SetPoint("LEFT", F.target, "RIGHT", L.sideGap, 0)
	F.pet:SetPoint("TOPLEFT", F.player, "BOTTOMLEFT", 0, -4)

	F.party1:SetPoint("TOPLEFT", UIParent, "TOPLEFT", L.partyX, L.partyY)
	for i = 2, 4 do
		F["party" .. i]:SetPoint("TOPLEFT", F["party" .. (i - 1)], "BOTTOMLEFT", 0, -L.partySpacing)
	end
end

-- Secure visibility. Party frames hide in raids (Grid handles those);
-- everything else just follows unit existence.
function ns:WatchFrame(f)
	if f.cfg.party then
		RegisterStateDriver(f, "visibility", "[group:raid] hide; [@" .. f.unit .. ",exists] show; hide")
	else
		RegisterUnitWatch(f)
	end
end

function ns:UnwatchFrame(f)
	if f.cfg.party then
		UnregisterStateDriver(f, "visibility")
	else
		UnregisterUnitWatch(f)
	end
end

-- Preview shows every frame, even for units that don't exist, so the
-- layout can be judged while configuring.
function ns:SetPreview(on)
	if on == ns.preview then return end
	if InCombatLockdown() then
		-- Secure frames can't be shown/hidden manually in combat
		return Print("can't toggle preview in combat.")
	end
	ns.preview = on
	for _, f in pairs(ns.frames) do
		if on then
			ns:UnwatchFrame(f)
			f:Show()
		else
			ns:WatchFrame(f)
		end
		ns.UpdateAll(f)
	end
end

---------------------------------------------------------------------------
-- Applying settings
---------------------------------------------------------------------------

function ns:ApplyStyle()
	ns:UpdateFonts()
	for _, f in pairs(ns.frames) do
		ns:StyleFrame(f)
	end
	ns:StyleActionBars()
	ns:StyleNameplates()
end

function ns:ApplyLayout()
	if InCombatLockdown() then
		-- Moving/resizing secure frames is blocked in combat; catch up afterwards
		ns.pendingLayout = true
		return
	end
	ns.pendingLayout = false
	for _, f in pairs(ns.frames) do
		ns:LayoutFrame(f)
	end
	ns:ApplyPositions()
	ns:StyleActionBars()
	ns:LayoutNameplates()
end

---------------------------------------------------------------------------
-- Blizzard frames
---------------------------------------------------------------------------

local hider = CreateFrame("Frame")
hider:Hide()

function ns:HideBlizzard()
	-- ComboFrame is parented to UIParent, not TargetFrame, so it needs hiding on its own
	-- PartyFrame is the container for all four Blizzard party member frames
	for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "ComboFrame", "PartyFrame" }) do
		local f = _G[name]
		if f then
			f:UnregisterAllEvents()
			f:Hide()
			f:SetParent(hider)
		end
	end

	-- Cast bars are Edit Mode-managed; clearing the unit unregisters their
	-- events so they never show, without reparenting them
	for _, name in ipairs({ "PlayerCastingBarFrame", "PetCastingBarFrame" }) do
		local f = _G[name]
		if f and f.SetUnit then
			f:SetUnit(nil)
			f:Hide()
		end
	end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------

local function FillDefaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then t[k] = v end
	end
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		KUIDB = KUIDB or {}
		KUIDB.positions = nil -- per-frame drag positions, replaced by layout
		KUIDB.widths = KUIDB.widths or {}
		KUIDB.widths.focus = nil -- focus now shares the ToT width
		KUIDB.style = KUIDB.style or {}
		KUIDB.layout = KUIDB.layout or {}
		KUIDB.castbar = KUIDB.castbar or {}
		KUIDB.actionbars = KUIDB.actionbars or {}
		KUIDB.nameplates = KUIDB.nameplates or {}
		FillDefaults(KUIDB.nameplates, ns.nameplateDefaults)
		KUIDB.colors = KUIDB.colors or {}
		KUIDB.colors.class = KUIDB.colors.class or {}
		KUIDB.colors.power = KUIDB.colors.power or {}
		KUIDB.colors.reaction = KUIDB.colors.reaction or {}
		KUIDB.colors.cast = KUIDB.colors.cast or {}
		KUIDB.colors.palette = KUIDB.colors.palette or "Default"
		FillDefaults(KUIDB.actionbars, ns.actionbarDefaults)
		FillDefaults(KUIDB.style, ns.styleDefaults)
		FillDefaults(KUIDB.layout, ns.layoutDefaults)
		KUIDB.castbar.width = nil -- from the old standalone cast bar
		FillDefaults(KUIDB.castbar, ns.castbarDefaults)

		ns:UpdateFonts()
		ns:HideBlizzard()
		for _, unit in ipairs(ns.order) do
			ns.frames[unit] = ns:CreateUnitFrame(unit, ns.defaults[unit])
		end
		ns:ApplyLayout()
		ns:InitConfig()
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_LOGIN" then
		-- Re-apply once every addon has loaded, in case saved media comes
		-- from a LibSharedMedia pack that wasn't registered yet
		ns:InitActionBars()
		ns:InitNameplates()
		ns:ApplyStyle()
	elseif event == "PLAYER_REGEN_DISABLED" and ns.preview then
		ns:SetPreview(false)
	elseif event == "PLAYER_REGEN_ENABLED" and ns.pendingLayout then
		ns:ApplyLayout()
	end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_KUI1 = "/kui"
SlashCmdList.KUI = function(msg)
	local cmd = strlower(strtrim(msg or ""))
	if cmd == "" or cmd == "config" then
		ns:OpenConfig()
	elseif cmd == "preview" then
		ns:SetPreview(not ns.preview)
	else
		Print("commands: |cffffff00config|r, |cffffff00preview|r")
	end
end
