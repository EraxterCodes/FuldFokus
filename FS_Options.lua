-- FS_Options.lua - FuldStonks options panel
-- Part of the FuldFokus addon

local COLOR_GREEN = "|cFF00FF00"
local COLOR_RESET = "|r"

-- Pretty print
local function ok(msg) print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " " .. tostring(msg)) end

-- --------------------------------------------------------------------
-- Panel + widgets
-- --------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "FuldStonks"
panel.parent = "FuldFokus"  -- Make it a child of the main addon panel

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("FuldStonks - Guild Betting")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
sub:SetText("Configure FuldStonks betting system.")

-- Debug mode checkbox
local debug = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
debug:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
debug.Text:SetText("Enable debug mode")
debug:SetScript("OnClick", function(self)
  if FuldStonksDB then
    FuldStonksDB.debug = self:GetChecked() and true or false
    ok("Debug mode " .. (FuldStonksDB.debug and "enabled" or "disabled") .. ".")
  end
end)

-- Info text
local infoLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
infoLabel:SetPoint("TOPLEFT", debug, "BOTTOMLEFT", 0, -24)
infoLabel:SetText("Use /fs or /FuldStonks to open the betting UI.")
infoLabel:SetTextColor(0.7, 0.7, 0.7)

local infoLabel2 = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
infoLabel2:SetPoint("TOPLEFT", infoLabel, "BOTTOMLEFT", 0, -8)
infoLabel2:SetText("Type /fs help for a list of commands.")
infoLabel2:SetTextColor(0.7, 0.7, 0.7)

-- Populate widgets from DB
local function RefreshPanel()
  if not FuldStonksDB then return end
  if FuldStonksDB.debug == nil then FuldStonksDB.debug = false end
  debug:SetChecked(FuldStonksDB.debug ~= false)
end

panel.refresh = RefreshPanel
panel:SetScript("OnShow", RefreshPanel)

-- Register panel as a subcategory
local category
if Settings and Settings.RegisterCanvasLayoutCategory then
  -- For TWW and beyond
  local mainCategory = Settings.GetCategory("FuldFokus")
  if not mainCategory then
    -- Create main category if it doesn't exist
    local mainPanel = CreateFrame("Frame")
    mainPanel.name = "FuldFokus"
    mainCategory = Settings.RegisterCanvasLayoutCategory(mainPanel, mainPanel.name)
    Settings.RegisterAddOnCategory(mainCategory)
  end
  category = Settings.RegisterCanvasLayoutSubcategory(mainCategory, panel, panel.name)
else
  -- For older versions
  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

-- Initialize on load
local init = CreateFrame("Frame")
init:RegisterEvent("ADDON_LOADED")
init:SetScript("OnEvent", function(_, ev, name)
  if name == "FuldFokus" then
    C_Timer.After(0.1, RefreshPanel)
  end
end)
