local addonName, ns = ...

local UNIT_NAMES = {
	player = "Player",
	target = "Target",
	targettarget = "Focus / Target of Target",
	pet = "Pet",
	party1 = "Party",
}

local LABEL_WIDTH = 140
local CONTROL_WIDTH = 240
local ROW_HEIGHT = 30

local category
local rows = {}

local function RefreshAll()
	for _, row in ipairs(rows) do
		row:Refresh()
	end
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

local function CreateRow(parent, text)
	local row = CreateFrame("Frame", nil, parent)
	row:SetSize(LABEL_WIDTH + CONTROL_WIDTH + 60, ROW_HEIGHT)

	row.label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.label:SetPoint("LEFT")
	row.label:SetText(text)

	rows[#rows + 1] = row
	return row
end

local function CreateSlider(parent, text, minValue, maxValue, step, get, set)
	local row = CreateRow(parent, text)

	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	slider:SetPoint("LEFT", LABEL_WIDTH, 0)
	slider:SetWidth(CONTROL_WIDTH)
	slider:Init(get(), minValue, maxValue, (maxValue - minValue) / step, {
		[MinimalSliderWithSteppersMixin.Label.Right] = function(v) return tostring(math.floor(v + 0.5)) end,
	})
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
		value = math.floor(value + 0.5)
		if value ~= get() then set(value) end
	end, row)

	function row:Refresh()
		slider:SetValue(get())
	end
	return row
end

local function CreateDropdown(parent, text, listMedia, get, set)
	local row = CreateRow(parent, text)

	local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
	dropdown:SetPoint("LEFT", LABEL_WIDTH, 0)
	dropdown:SetWidth(CONTROL_WIDTH)
	dropdown:SetupMenu(function(_, root)
		-- LibSharedMedia packs can add dozens of entries
		if root.SetScrollMode then root:SetScrollMode(400) end
		for _, name in ipairs(listMedia()) do
			root:CreateRadio(name, function(n) return get() == n end, set, name)
		end
	end)

	function row:Refresh()
		dropdown:GenerateMenu()
	end
	return row
end

local function CreateCheckbox(parent, text, get, set)
	local row = CreateRow(parent, text)

	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	check:SetPoint("LEFT", LABEL_WIDTH - 4, 0)
	check:SetScript("OnClick", function(self)
		set(self:GetChecked())
	end)

	function row:Refresh()
		check:SetChecked(get())
	end
	return row
end

local function CreateColorSwatch(parent, text, get, set)
	local row = CreateRow(parent, text)

	local button = CreateFrame("Button", nil, row)
	button:SetPoint("LEFT", LABEL_WIDTH, 0)
	button:SetSize(22, 22)

	local frame = button:CreateTexture(nil, "BACKGROUND")
	frame:SetAllPoints()
	frame:SetColorTexture(1, 1, 1)

	local swatch = button:CreateTexture(nil, "ARTWORK")
	swatch:SetPoint("TOPLEFT", 2, -2)
	swatch:SetPoint("BOTTOMRIGHT", -2, 2)

	local function Apply(r, g, b)
		-- Always a fresh table: the saved value may be the shared default
		set({ r, g, b })
		swatch:SetColorTexture(r, g, b)
	end

	button:SetScript("OnClick", function()
		local r, g, b = unpack(get())
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b,
			hasOpacity = false,
			swatchFunc = function() Apply(ColorPickerFrame:GetColorRGB()) end,
			cancelFunc = function() Apply(r, g, b) end,
		})
	end)

	function row:Refresh()
		swatch:SetColorTexture(unpack(get()))
	end
	return row
end

local function CreateHeader(parent, text)
	local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	fs:SetText(text)
	return fs
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function SetWidth(unit, value)
	KUIDB.widths[unit] = value
	if InCombatLockdown() then
		ns.Print("frame sizes will update after combat.")
	end
	ns:ApplyLayout()
end

local function SetLayout(key, value)
	KUIDB.layout[key] = value
	if InCombatLockdown() then
		ns.Print("frame positions will update after combat.")
	end
	ns:ApplyLayout()
end

local function SetStyle(key, value)
	KUIDB.style[key] = value
	ns:ApplyStyle()
end

-- Cast bar rows live inside the secure unit frames, so size/icon changes go
-- through the combat-deferred layout path
local function SetCastbar(key, value)
	KUIDB.castbar[key] = value
	if key == "texture" then
		ns:ApplyStyle()
	else
		ns:ApplyLayout()
	end
end

-- Border settings re-anchor bars inside the secure frame, so they go through
-- the combat-deferred layout path
local function SetBorder(key, value)
	KUIDB.style[key] = value
	ns:ApplyLayout()
end

local function ResetToDefaults()
	wipe(KUIDB.widths)
	wipe(KUIDB.style)
	wipe(KUIDB.layout)
	wipe(KUIDB.castbar)
	for k, v in pairs(ns.castbarDefaults) do
		KUIDB.castbar[k] = v
	end
	for k, v in pairs(ns.styleDefaults) do
		KUIDB.style[k] = v
	end
	for k, v in pairs(ns.layoutDefaults) do
		KUIDB.layout[k] = v
	end
	ns:ApplyStyle()
	ns:ApplyLayout()
	RefreshAll()
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function BuildPanel(panel)
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("KUI")

	local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	subtitle:SetText("Unit frame settings. Changes apply immediately; all frames are shown while this panel is open.")

	-- Simple top-down stacking
	local y = -64
	local function Place(region, extraGap)
		region:SetPoint("TOPLEFT", 16, y)
		y = y - (region.GetHeight and region:GetHeight() > 0 and region:GetHeight() or 16) - (extraGap or 0)
	end

	Place(CreateHeader(panel, "Layout"), 6)
	Place(CreateSlider(panel, "Vertical position", -600, 600, 2,
		function() return KUIDB.layout.y end,
		function(v) SetLayout("y", v) end))
	Place(CreateSlider(panel, "Distance from center", 0, 400, 1,
		function() return KUIDB.layout.centerGap end,
		function(v) SetLayout("centerGap", v) end))
	Place(CreateSlider(panel, "Focus / ToT spacing", 0, 100, 1,
		function() return KUIDB.layout.sideGap end,
		function(v) SetLayout("sideGap", v) end))

	y = y - 12
	Place(CreateHeader(panel, "Party"), 6)
	Place(CreateSlider(panel, "Horizontal position", 0, 1000, 2,
		function() return KUIDB.layout.partyX end,
		function(v) SetLayout("partyX", v) end))
	Place(CreateSlider(panel, "Vertical position", -1000, 0, 2,
		function() return KUIDB.layout.partyY end,
		function(v) SetLayout("partyY", v) end))
	Place(CreateSlider(panel, "Spacing", 0, 60, 1,
		function() return KUIDB.layout.partySpacing end,
		function(v) SetLayout("partySpacing", v) end))

	y = y - 12
	Place(CreateHeader(panel, "Frame width"), 6)
	for _, unit in ipairs(ns.order) do
		-- Units sharing another's width (focus) are covered by that slider
		if not ns.defaults[unit].widthFrom then
			Place(CreateSlider(panel, UNIT_NAMES[unit] or unit, 60, 400, 2,
				function() return ns:GetWidth(unit) end,
				function(v) SetWidth(unit, v) end))
		end
	end

	y = y - 12
	Place(CreateHeader(panel, "Text"), 6)
	Place(CreateDropdown(panel, "Font", function() return ns:ListMedia("font") end,
		function() return KUIDB.style.font end,
		function(v) SetStyle("font", v) end))
	Place(CreateSlider(panel, "Font size", 8, 16, 1,
		function() return KUIDB.style.fontSize end,
		function(v) SetStyle("fontSize", v) end))

	y = y - 12
	Place(CreateHeader(panel, "Bars"), 6)
	Place(CreateDropdown(panel, "Health bar", function() return ns:ListMedia("statusbar") end,
		function() return KUIDB.style.healthTexture end,
		function(v) SetStyle("healthTexture", v) end))
	Place(CreateDropdown(panel, "Power bar", function() return ns:ListMedia("statusbar") end,
		function() return KUIDB.style.powerTexture end,
		function(v) SetStyle("powerTexture", v) end))
	-- Resizes rows inside the secure frames, hence the deferred layout path
	Place(CreateSlider(panel, "Power bar height", 2, 20, 1,
		function() return KUIDB.style.powerHeight end,
		function(v) SetBorder("powerHeight", v) end))
	Place(CreateColorSwatch(panel, "Empty bar color",
		function() return KUIDB.style.emptyColor end,
		function(v) SetStyle("emptyColor", v) end))
	Place(CreateSlider(panel, "Empty bar opacity", 0, 100, 5,
		function() return math.floor(KUIDB.style.emptyAlpha * 100 + 0.5) end,
		function(v) SetStyle("emptyAlpha", v / 100) end))

	y = y - 12
	Place(CreateHeader(panel, "Cast bar"), 6)
	Place(CreateSlider(panel, "Height", 4, 24, 1,
		function() return KUIDB.castbar.height end,
		function(v) SetCastbar("height", v) end))
	Place(CreateDropdown(panel, "Texture", function() return ns:ListMedia("statusbar") end,
		function() return KUIDB.castbar.texture end,
		function(v) SetCastbar("texture", v) end))
	Place(CreateCheckbox(panel, "Show spell icon",
		function() return KUIDB.castbar.showIcon end,
		function(v) SetCastbar("showIcon", v) end))

	y = y - 12
	Place(CreateHeader(panel, "Border"), 6)
	Place(CreateDropdown(panel, "Style", function() return ns:ListMedia("border") end,
		function() return KUIDB.style.border end,
		function(v) SetBorder("border", v) end))
	Place(CreateSlider(panel, "Thickness", 1, 24, 1,
		function() return KUIDB.style.borderSize end,
		function(v) SetBorder("borderSize", v) end))
	Place(CreateColorSwatch(panel, "Color",
		function() return KUIDB.style.borderColor end,
		function(v) SetBorder("borderColor", v) end))
	Place(CreateSlider(panel, "Padding", 0, 6, 1,
		function() return KUIDB.style.padding end,
		function(v) SetBorder("padding", v) end))
	Place(CreateSlider(panel, "Background opacity", 0, 100, 5,
		function() return math.floor(KUIDB.style.bgAlpha * 100 + 0.5) end,
		function(v) SetBorder("bgAlpha", v / 100) end))

	y = y - 16
	local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	reset:SetSize(140, 24)
	Place(reset)
	reset:SetText("Reset to defaults")
	reset:SetScript("OnClick", ResetToDefaults)

	return -y + 16
end

function ns:InitConfig()
	local panel = CreateFrame("Frame")

	-- Settings doesn't scroll canvas panels itself, and ours is taller than
	-- the visible area
	local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -28, 4)

	local content = CreateFrame("Frame", nil, scroll)
	content:SetWidth(LABEL_WIDTH + CONTROL_WIDTH + 100)
	content:SetHeight(BuildPanel(content))
	scroll:SetScrollChild(content)

	-- Show every frame while the panel is open so the layout is visible
	panel:SetScript("OnShow", function()
		RefreshAll()
		if not InCombatLockdown() then ns:SetPreview(true) end
	end)
	panel:SetScript("OnHide", function()
		if not InCombatLockdown() then ns:SetPreview(false) end
	end)

	-- Hooks the Settings panel calls for canvas categories
	panel.OnRefresh = RefreshAll
	panel.OnDefault = ResetToDefaults

	category = Settings.RegisterCanvasLayoutCategory(panel, "KUI")
	Settings.RegisterAddOnCategory(category)
end

function ns:OpenConfig()
	if InCombatLockdown() then
		return ns.Print("can't open settings in combat.")
	end
	Settings.OpenToCategory(category:GetID())
end
