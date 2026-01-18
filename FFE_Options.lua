-- FFE_Options.lua - Options panel for FuldFokus Emotes
-- Part of the FuldFokus addon

local ADDON_NAME = "FuldFokus"
FFE = FFE or {}

-- Pretty print
local function ok(msg) print("|cffe5a472FFE|r " .. tostring(msg)) end

-- --------------------------------------------------------------------
-- Main Category Panel (empty, just for organization)
-- --------------------------------------------------------------------
local mainPanel = CreateFrame("Frame")
mainPanel.name = "FuldFokus"

local mainTitle = mainPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
mainTitle:SetPoint("TOPLEFT", 16, -16)
mainTitle:SetText("FuldFokus")

local mainSub = mainPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
mainSub:SetPoint("TOPLEFT", mainTitle, "BOTTOMLEFT", 0, -8)
mainSub:SetText("Combined addon with emotes and guild betting system.")

local mainInfo = mainPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
mainInfo:SetPoint("TOPLEFT", mainSub, "BOTTOMLEFT", 0, -16)
mainInfo:SetText("• Use /ffe commands for emotes")
mainInfo:SetTextColor(0.7, 0.7, 0.7)

local mainInfo2 = mainPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
mainInfo2:SetPoint("TOPLEFT", mainInfo, "BOTTOMLEFT", 0, -4)
mainInfo2:SetText("• Use /fs commands for betting system")
mainInfo2:SetTextColor(0.7, 0.7, 0.7)

local mainInfo3 = mainPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
mainInfo3:SetPoint("TOPLEFT", mainInfo2, "BOTTOMLEFT", 0, -12)
mainInfo3:SetText("Select a subcategory on the left for specific settings.")
mainInfo3:SetTextColor(0.5, 0.5, 0.5)

-- --------------------------------------------------------------------
-- Emotes Subcategory Panel
-- --------------------------------------------------------------------
local emotesPanel = CreateFrame("Frame")
emotesPanel.name = "FuldFokus Emotes"
emotesPanel.parent = "FuldFokus"

local title = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("FuldFokus Emotes")

local sub = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
sub:SetText("Configure emote settings for FuldFokus Emotes.")

-- Easter eggs
local easter = CreateFrame("CheckButton", nil, emotesPanel, "InterfaceOptionsCheckButtonTemplate")
easter:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
easter.Text:SetText("Enable Easter eggs")
easter:SetScript("OnClick", function(self)
  FFE_DB.easter = self:GetChecked() and true or false
  ok("Easter eggs " .. (FFE_DB.easter and "enabled" or "disabled") .. ".")
end)

-- Info text
local infoLabel = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
infoLabel:SetPoint("TOPLEFT", easter, "BOTTOMLEFT", 0, -24)
infoLabel:SetText("Emotes are integrated into TwitchEmotes and accessible via the emote dropdown.")
infoLabel:SetTextColor(0.7, 0.7, 0.7)

-- Populate widgets from DB
local function RefreshPanel()
  if not FFE_DB then return end
  if FFE_DB.easter  == nil then FFE_DB.easter  = true end  -- default ON
  easter:SetChecked(FFE_DB.easter  ~= false)
end

emotesPanel.refresh = RefreshPanel
emotesPanel:SetScript("OnShow", RefreshPanel)

-- Register panels
local mainCategory, emotesCategory
if Settings and Settings.RegisterCanvasLayoutCategory then
  -- Register main category
  mainCategory = Settings.RegisterCanvasLayoutCategory(mainPanel, mainPanel.name)
  Settings.RegisterAddOnCategory(mainCategory)
  
  -- Register emotes as subcategory
  emotesCategory = Settings.RegisterCanvasLayoutSubcategory(mainCategory, emotesPanel, emotesPanel.name)
else
  -- For older versions
  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(mainPanel)
    InterfaceOptions_AddCategory(emotesPanel)
  end
end

FFE._mainPanel = mainPanel
FFE._emotesPanel = emotesPanel
FFE._mainCategory = mainCategory or nil
FFE._emotesCategory = emotesCategory or nil

function FFE.OpenOptions()
  if Settings and Settings.OpenToCategory and FFE._mainCategory then
    local id = FFE._mainCategory.ID or FFE._mainCategory
    Settings.OpenToCategory(id)
  elseif InterfaceOptionsFrame_OpenToCategory and FFE._mainPanel then
    InterfaceOptionsFrame_OpenToCategory(FFE._mainPanel)
    InterfaceOptionsFrame_OpenToCategory(FFE._mainPanel)
  else
    ok("Open via Game Menu → Options → AddOns → FuldFokus")
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
