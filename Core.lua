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
--   Apply*           a module's on/off state and settings in one go
--
-- Lifecycle (see the loader at the bottom):
--   ADDON_LOADED     saved variables and profile, unit frames, config panel
--   PLAYER_LOGIN     everything restyling Blizzard UI, which exists by then
--   Init*            runs once. Modules that restyle Blizzard frames are
--                    only built if enabled at login; toggling them later
--                    asks for a /reload.
--   Layout/Style/Apply  rerun whenever settings change, so they must be
--                    safe to call repeatedly (and before Init: they return
--                    early while their frames don't exist)
--   ns.supported     features that run on this client (Compat.lua); the
--                    rest are never initialized

ns.frames = {} -- unit -> unit frame

function ns.Print(...)
	print("|cff33ff99KUI|r:", ...)
end

---------------------------------------------------------------------------
-- Saved variables and profiles
--
-- KUIDB (account-wide) holds named profiles and which one each character
-- uses: { profiles = { name -> settings }, chars = { "Name - Realm" -> name } }.
-- ns.db is the current character's profile; everything else reads its
-- settings there, fresh on every use, so switching profiles is just
-- pointing ns.db elsewhere and reapplying.
---------------------------------------------------------------------------

local DEFAULT_PROFILE = "Default"
local charKey -- this character's key in KUIDB.chars

-- Tables are copied so saved settings never alias the defaults
local function FillDefaults(t, defaults)
	for k, v in pairs(defaults) do
		if t[k] == nil then
			t[k] = type(v) == "table" and CopyTable(v) or v
		end
	end
end

-- Brings a profile up to date: old settings migrated, missing ones filled in
local function InitProfile(db)
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

local function InitDB()
	KUIDB = KUIDB or {}
	-- Before profiles, the settings sat at the top level: they become the
	-- Default profile
	if not KUIDB.profiles then
		KUIDB = { profiles = { [DEFAULT_PROFILE] = KUIDB } }
	end
	KUIDB.chars = KUIDB.chars or {}

	charKey = UnitName("player") .. " - " .. GetRealmName()
	ns.charKey = charKey
	local name = KUIDB.chars[charKey]
	if not KUIDB.profiles[name] then name = DEFAULT_PROFILE end
	KUIDB.chars[charKey] = name
	KUIDB.profiles[name] = KUIDB.profiles[name] or {}
	ns.db = KUIDB.profiles[name]
	InitProfile(ns.db)
end

-- Settings only read when KUI starts; changing them asks for a /reload.
-- section, key, what to call it, the feature it belongs to
local LOGIN_ONLY = {
	{ "statusbars", "enabled", "XP/reputation bar", "statusbars" },
	{ "nameplates", "enabled", "nameplate", "nameplates" },
	{ "buffs", "enabled", "buff bar styling", "buffs" },
	{ "actionbars", "enabled", "action bar styling", "actionbars" },
	{ "tooltip", "enabled", "tooltip styling", "tooltips" },
}

local function LoginOnlyValues()
	local values = {}
	for i, entry in ipairs(LOGIN_ONLY) do
		values[i] = ns.db[entry[1]][entry[2]]
	end
	return values
end

-- Applies settings that all changed at once (a reset or a different
-- profile). before: LoginOnlyValues() from ahead of the change.
local function ApplyAll(before)
	ns:ApplyStyle()
	if not ns:ApplyLayout() then
		ns.Print("frame layout will update after combat.")
	end
	-- These change Blizzard frames directly rather than KUI's own
	if ns.supported.chat then ns:ApplyChat() end
	if ns.supported.uifont then ns:ApplyUIFont() end
	if ns.supported.menubar then ns:ApplyMenuBar() end
	ns:ApplyMeter()
	for i, entry in ipairs(LOGIN_ONLY) do
		if ns.supported[entry[4]] and ns.db[entry[1]][entry[2]] ~= before[i] then
			ns.Print(entry[3] .. " change takes effect after /reload.")
		end
	end
end

-- Every setting in the current profile back to its default, including
-- widths and color overrides, then reapplied
function ns:ResetSettings()
	local before = LoginOnlyValues()
	wipe(ns.db.widths)
	for section, defaults in pairs(ns.settingsDefaults) do
		wipe(ns.db[section])
		FillDefaults(ns.db[section], defaults)
	end
	for _, kind in ipairs(ns.colorKinds) do
		wipe(ns.db.colors[kind])
	end
	ns.db.colors.palette = "Default"
	ApplyAll(before)
end

function ns:ProfileName()
	return KUIDB.chars[charKey]
end

local profileNames = {}
-- Every profile's name, alphabetically; the table is reused
function ns:ProfileList()
	wipe(profileNames)
	for name in pairs(KUIDB.profiles) do profileNames[#profileNames + 1] = name end
	table.sort(profileNames)
	return profileNames
end

-- This character switches to an existing profile
function ns:SetProfile(name)
	if not KUIDB.profiles[name] or name == ns:ProfileName() then return end
	local before = LoginOnlyValues()
	KUIDB.chars[charKey] = name
	ns.db = KUIDB.profiles[name]
	InitProfile(ns.db)
	ApplyAll(before)
end

-- A new profile starting as a copy of the current one, which this
-- character switches to. Returns an error message if it can't.
function ns:CreateProfile(name)
	name = strtrim(name or "")
	if name == "" then return "the profile needs a name." end
	if KUIDB.profiles[name] then return "there's already a profile called " .. name .. "." end
	KUIDB.profiles[name] = CopyTable(ns.db)
	ns:SetProfile(name)
end

-- Replaces the current profile's settings with a copy of another's
function ns:CopyProfile(from)
	local source = KUIDB.profiles[from]
	if not source or source == ns.db then return end
	local before = LoginOnlyValues()
	-- Filled in place: ns.db stays the same table
	wipe(ns.db)
	for k, v in pairs(CopyTable(source)) do ns.db[k] = v end
	InitProfile(ns.db)
	ApplyAll(before)
end

-- Profiles other than the current one and Default can be deleted;
-- characters that used it go back to Default
function ns:CanDeleteProfile(name)
	return KUIDB.profiles[name] ~= nil and name ~= DEFAULT_PROFILE and name ~= ns:ProfileName()
end

function ns:DeleteProfile(name)
	if not ns:CanDeleteProfile(name) then return end
	KUIDB.profiles[name] = nil
	for char, profile in pairs(KUIDB.chars) do
		if profile == name then KUIDB.chars[char] = DEFAULT_PROFILE end
	end
end

-- Character keys using a profile, for showing in the settings
function ns:ProfileUsers(name)
	local users = {}
	for char, profile in pairs(KUIDB.chars) do
		if profile == name then users[#users + 1] = char end
	end
	table.sort(users)
	return users
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
	ns:StyleTooltips()
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
	if ns.supported.unitframes then
		for _, f in pairs(ns.frames) do
			ns:LayoutFrame(f)
		end
		ns:ApplyPositions()
	end
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

-- Runs at ADDON_LOADED, before combat lockdown can apply
local function HideBlizzard()
	-- ComboFrame is parented to UIParent, not TargetFrame, so it needs hiding
	-- on its own. PartyFrame holds all four Blizzard party member frames.
	-- Unregistering their events stops them doing work while hidden.
	for _, name in ipairs({ "PlayerFrame", "TargetFrame", "FocusFrame", "PetFrame", "ComboFrame", "PartyFrame" }) do
		local f = _G[name]
		if f then
			f:UnregisterAllEvents()
			f:Hide()
			ns.SetHidden(f, true)
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

-- Set up at PLAYER_LOGIN, in this order: feature, function
local LOGIN_INITS = {
	{ "uifont", "InitUIFont" },
	{ "actionbars", "InitActionBars" },
	{ "buffs", "InitBuffs" },
	{ "nameplates", "InitNameplates" },
	{ "infobar", "InitInfoBar" },
	{ "statusbars", "InitStatusBars" },
	{ "chat", "InitChat" },
	{ "menubar", "ApplyMenuBar" },
	{ "minimap", "InitMinimap" },
	{ "meter", "InitMeter" },
	{ "tooltips", "InitTooltips" },
	{ "vendor", "InitVendor" },
}

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
		if ns.supported.uifont then ns:InitWorldFonts() end
		if ns.supported.unitframes then
			HideBlizzard()
			for _, unit in ipairs(ns.unitOrder) do
				ns.frames[unit] = ns:CreateUnitFrame(unit, ns.units[unit])
			end
		end
		ns:ApplyLayout()
		ns:InitConfig()
	elseif event == "PLAYER_LOGIN" then
		-- Blizzard's action buttons, nameplate driver and status bars exist by
		-- now. Styling again also picks up saved media from LibSharedMedia
		-- packs that registered after us.
		for _, entry in ipairs(LOGIN_INITS) do
			if ns.supported[entry[1]] then ns[entry[2]](ns) end
		end
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
		if not ns.supported.unitframes then
			return ns.Print("unit frames aren't available on this game client yet.")
		end
		ns:SetPreview(not ns.preview)
	else
		ns.Print("commands: |cffffff00config|r, |cffffff00preview|r")
	end
end
