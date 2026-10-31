local addonName, ns = ...

-- Optionally puts one font on the whole UI: every Font object Blizzard (or
-- another addon) has registered globally gets the new font file, keeping
-- its own size and outline, plus the in-world font globals. Font objects
-- copy their settings when created, so each one is set individually, and
-- Blizzard's load-on-demand parts are rescanned as they load. Switching
-- it off restores the original files.
--
-- Names over heads and floating combat text read their font at login, so
-- those follow after a relog. On forever they keep Blizzard's font: they
-- come from globals, and Blizzard code reading a global an addon wrote
-- runs tainted there, which breaks it on secret values.

local WORLD_FONT_GLOBALS = { "STANDARD_TEXT_FONT", "UNIT_NAME_FONT", "DAMAGE_TEXT_FONT", "NAMEPLATE_FONT" }

local originals = {} -- font object -> its font file before replacing
local originalGlobals = {} -- global name -> value before replacing
local ownFonts = {} -- KUI's font objects, which follow style.font instead

local function IsFontObject(value)
	if type(value) ~= "table" or type(value.GetObjectType) ~= "function" then return false end
	local ok, objectType = pcall(value.GetObjectType, value)
	return ok and objectType == "Font"
end

-- path: the font file to use, or nil to restore the originals
local function SetFontObjects(path)
	for _, value in pairs(_G) do
		if IsFontObject(value) and not ownFonts[value] then
			local file, size, flags = value:GetFont()
			if file then
				originals[value] = originals[value] or file
				local target = path or originals[value]
				if file ~= target then value:SetFont(target, size, flags) end
			end
		end
	end
end

local function SetWorldFonts(path)
	if ns.hasSecrets then return end
	for _, name in ipairs(WORLD_FONT_GLOBALS) do
		if originalGlobals[name] == nil then originalGlobals[name] = _G[name] end
		_G[name] = path or originalGlobals[name]
	end
end

local function Enabled()
	return ns.db.uifont.enabled
end

-- Called from ADDON_LOADED, before the world fonts are first read
function ns:InitWorldFonts()
	for _, fo in pairs(ns.fonts) do ownFonts[fo] = true end
	if Enabled() then SetWorldFonts(ns:GetFontPath(ns.db.uifont.font)) end
end

-- Replaces or restores the fonts to match the settings
function ns:ApplyUIFont()
	if Enabled() then
		local path = ns:GetFontPath(ns.db.uifont.font)
		SetWorldFonts(path)
		SetFontObjects(path)
	elseif next(originals) then
		-- Only undo what was replaced
		SetWorldFonts(nil)
		SetFontObjects(nil)
	end
end

function ns:InitUIFont()
	ns:ApplyUIFont()

	-- Blizzard's load-on-demand UI (auction house, talents, ...) brings its
	-- own font objects
	local watcher = CreateFrame("Frame")
	watcher:RegisterEvent("ADDON_LOADED")
	watcher:SetScript("OnEvent", function()
		if Enabled() then ns:ApplyUIFont() end
	end)
end
