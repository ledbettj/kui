local addonName, ns = ...

-- Addon bootstrap: saved variable setup, the two "apply settings" entry
-- points every module hooks into, Blizzard frame suppression, and slash
-- commands.
--
-- Conventions used across the files:
--   ns:Verb(...)     module API (InitX, LayoutX, StyleX, ...)
--   ns.Verb(frame)   per-frame functions shared between modules; plain
--                    functions so they can sit directly in event tables
--   Layout*          sizes/anchors; touches secure frames, so it is
--                    deferred while in combat
--   Style*           textures/colors/fonts; safe at any time

ns.frames = {} -- unit -> unit frame

function ns.Print(...)
	print("|cff33ff99KUI|r:", ...)
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

-- Tables are copied so saved settings never alias the defaults
local function FillDefaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then
			t[k] = type(v) == "table" and CopyTable(v) or v
		end
	end
end

local function InitDB()
	KUIDB = KUIDB or {}
	local db = KUIDB

	-- Settings from earlier versions
	db.positions = nil -- per-frame drag positions, replaced by layout
	if db.widths then db.widths.focus = nil end -- focus shares the ToT width
	if db.castbar then db.castbar.width = nil end -- old standalone cast bar
	if db.menubar and db.menubar.singleBag ~= nil then -- checkbox before the bags dropdown
		db.menubar.bags = db.menubar.singleBag and "Backpack only" or "All"
		db.menubar.singleBag = nil
	end

	db.widths = db.widths or {}
	for section, defaults in pairs(ns.settingsDefaults) do
		db[section] = db[section] or {}
		FillDefaults(db[section], defaults)
	end

	-- Per-entry color overrides on top of the selected palette
	db.colors = db.colors or {}
	for _, kind in ipairs(ns.colorKinds) do
		db.colors[kind] = db.colors[kind] or {}
	end
	db.colors.palette = db.colors.palette or "Default"
end

function ns:ResetSettings()
	wipe(KUIDB.widths)
	for section, defaults in pairs(ns.settingsDefaults) do
		wipe(KUIDB[section])
		FillDefaults(KUIDB[section], defaults)
	end
	for _, kind in ipairs(ns.colorKinds) do
		wipe(KUIDB.colors[kind])
	end
	KUIDB.colors.palette = "Default"

	ns:ApplyStyle()
	ns:ApplyLayout()
	ns:ApplyChat()
	ns:ApplyMenuBar()
	ns:ApplyMeter()
end

---------------------------------------------------------------------------
-- Applying settings
---------------------------------------------------------------------------

-- Textures, colors and fonts everywhere
function ns:ApplyStyle()
	ns:UpdateFonts()
	for _, f in pairs(ns.frames) do
		ns:StyleFrame(f)
	end
	ns:StyleActionBars()
	ns:StyleBuffs()
	ns:StyleNameplates()
	ns:StyleStatusBars()
	ns:StyleMeter()
	ns:LayoutInfoBar() -- readout widths follow the font
end

-- Sizes, borders and positions everywhere. Moving/resizing secure frames
-- is blocked in combat, so it catches up when combat ends. Returns false
-- when deferred.
function ns:ApplyLayout()
	if InCombatLockdown() then
		ns.pendingLayout = true
		return false
	end
	ns.pendingLayout = false
	for _, f in pairs(ns.frames) do
		ns:LayoutFrame(f)
	end
	ns:ApplyPositions()
	-- Border size/inset changes
	ns:StyleActionBars()
	ns:StyleBuffs()
	ns:LayoutNameplates()
	ns:LayoutInfoBar()
	ns:LayoutStatusBars()
	ns:LayoutMinimap()
	ns:LayoutMeter()
	return true
end

---------------------------------------------------------------------------
-- Blizzard frames
---------------------------------------------------------------------------

local hider = CreateFrame("Frame")
hider:Hide()

local function HideBlizzard()
	-- ComboFrame is parented to UIParent, not TargetFrame, so it needs hiding
	-- on its own. PartyFrame holds all four Blizzard party member frames.
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

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_DISABLED")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == addonName then
		self:UnregisterEvent("ADDON_LOADED")
		InitDB()
		ns:UpdateFonts()
		HideBlizzard()
		for _, unit in ipairs(ns.unitOrder) do
			ns.frames[unit] = ns:CreateUnitFrame(unit, ns.units[unit])
		end
		ns:ApplyLayout()
		ns:InitConfig()
	elseif event == "PLAYER_LOGIN" then
		-- Blizzard's action buttons, nameplate driver and status bars exist by
		-- now. Styling again also picks up saved media from LibSharedMedia
		-- packs that registered after us.
		ns:InitActionBars()
		ns:InitBuffs()
		ns:InitNameplates()
		ns:InitInfoBar()
		ns:InitStatusBars()
		ns:InitChat()
		ns:ApplyMenuBar()
		ns:InitMinimap()
		ns:InitMeter()
		ns:ApplyStyle()
	elseif event == "PLAYER_REGEN_DISABLED" then
		-- Fires just before lockdown, the last chance to restore secure
		-- visibility drivers
		if ns.preview then ns:SetPreview(false) end
	elseif event == "PLAYER_REGEN_ENABLED" then
		if ns.pendingLayout then ns:ApplyLayout() end
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
		ns.Print("commands: |cffffff00config|r, |cffffff00preview|r")
	end
end
