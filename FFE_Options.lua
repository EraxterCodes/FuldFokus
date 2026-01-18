-- FFE_Options.lua - Options panel for FuldFokusEmotes
local ADDON_NAME = ...
FFE = FFE or {}

-- Pretty print
local function ok(msg) print("|cffe5a472FFE|r " .. tostring(msg)) end

-- --------------------------------------------------------------------
-- Panel + widgets
-- --------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "FuldFokus Emotes"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("FuldFokus Emotes")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
sub:SetText("Configure emote settings for FuldFokusEmotes.")

-- Easter eggs
local easter = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
easter:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
easter.Text:SetText("Enable Easter eggs")
easter:SetScript("OnClick", function(self)
  FFE_DB.easter = self:GetChecked() and true or false
  ok("Easter eggs " .. (FFE_DB.easter and "enabled" or "disabled") .. ".")
end)

-- Info text
local infoLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
infoLabel:SetPoint("TOPLEFT", easter, "BOTTOMLEFT", 0, -24)
infoLabel:SetText("Emotes are integrated into TwitchEmotes and accessible via the emote dropdown.")
infoLabel:SetTextColor(0.7, 0.7, 0.7)

-- Populate widgets from DB
local function RefreshPanel()
  if not FFE_DB then return end
  if FFE_DB.easter  == nil then FFE_DB.easter  = true end  -- default ON
  easter:SetChecked(FFE_DB.easter  ~= false)
end

panel.refresh = RefreshPanel
panel:SetScript("OnShow", RefreshPanel)

-- Register panel
local category
if Settings and Settings.RegisterCanvasLayoutCategory then
  category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
  Settings.RegisterAddOnCategory(category)
else
  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end
end

FFE._optionsPanel = panel
FFE._settingsCategory = category or nil

function FFE.OpenOptions()
  if Settings and Settings.OpenToCategory and FFE._settingsCategory then
    local id = FFE._settingsCategory.ID or FFE._settingsCategory
    Settings.OpenToCategory(id)
  elseif InterfaceOptionsFrame_OpenToCategory and FFE._optionsPanel then
    InterfaceOptionsFrame_OpenToCategory(FFE._optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(FFE._optionsPanel)
  else
    ok("Open via Game Menu → Options → AddOns → " .. (panel.name or "FuldFokus Emotes"))
  end
end

-- Initialize on load
local init = CreateFrame("Frame")
init:RegisterEvent("ADDON_LOADED")
init:SetScript("OnEvent", function(_, ev, name)
  if name == ADDON_NAME then
    C_Timer.After(0.1, RefreshPanel)
  end
end)
