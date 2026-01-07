-- FF_Options.lua - Options panel for FuldFokus addon
-- This version:
--  - Keeps Set/Clear (Clear next to Set), no Select or Sync
--  - Adds "Enable Easter eggs" (default ON)
--  - Enter in the edit box applies (same as Set)

local ADDON_NAME = ...
FF = FF or {}

-- Pretty print
local function ok(msg) print("|cffe5a472FF|r " .. tostring(msg)) end

-- Apply the typed key (used by Set button and Enter in the edit box)
local function ApplyEditBoxSelection(keyEdit, previewFS)
  local k = keyEdit:GetText() or ""
  if FF.SetSelectedEmote then FF.SetSelectedEmote(k) end
  if previewFS then
    previewFS:SetText((FF.TextureStringForKey and FF.TextureStringForKey(FF_DB.selected, FF_DB.iconSize)) or "")
  end
end

-- --------------------------------------------------------------------
-- Panel + widgets
-- --------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "FuldFokus"

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("FuldFokus")

local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
sub:SetText("Configure Details icons for FuldFokusEmotes.")

-- Enable
local enable = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
enable:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -12)
enable.Text:SetText("Enable icons in Details")
enable:SetScript("OnClick", function(self)
  FF_DB.enabled = self:GetChecked() and true or false
  ok("Icons " .. (FF_DB.enabled and "enabled" or "disabled") .. ".")
  if FF.RefreshAllDisplayNames then FF.RefreshAllDisplayNames() end
  if FF.RefreshDetails then FF.RefreshDetails() end
  if FF.UpdateTicker then FF.UpdateTicker() end
end)

-- Animate
local animate = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
animate:SetPoint("TOPLEFT", enable, "BOTTOMLEFT", 0, -12)
animate.Text:SetText("Animate emotes in Details (OBS: this will increase Details update interval)")
animate:SetScript("OnClick", function(self)
  FF_DB.animate = self:GetChecked() and true or false
  ok("Details emote animation " .. (FF_DB.animate and "enabled" or "disabled") .. ".")
  if FF.RefreshAllDisplayNames then FF.RefreshAllDisplayNames() end
  if FF.RefreshDetails then FF.RefreshDetails() end
  if FF.UpdateTicker then FF.UpdateTicker() end
end)

-- Easter eggs (NEW)
local easter = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
easter:SetPoint("TOPLEFT", animate, "BOTTOMLEFT", 0, -12)
easter.Text:SetText("Enable Easter eggs")
easter:SetScript("OnClick", function(self)
  FF_DB.easter = self:GetChecked() and true or false
  ok("Easter eggs " .. (FF_DB.easter and "enabled" or "disabled") .. ".")
  if FF.RefreshAllDisplayNames then FF.RefreshAllDisplayNames() end
  if FF.RefreshDetails then FF.RefreshDetails() end
  if FF.UpdateTicker then FF.UpdateTicker() end
end)

-- Size slider
local size = CreateFrame("Slider", "FFE_SizeSlider", panel, "OptionsSliderTemplate")
size:SetPoint("TOPLEFT", easter, "BOTTOMLEFT", 0, -24)  -- moved under Easter eggs
size:SetMinMaxValues(8, 64)
size:SetValueStep(1)
size:SetObeyStepOnDrag(true)
size:SetWidth(240)
FFE_SizeSliderLow:SetText("8")
FFE_SizeSliderHigh:SetText("64")
FFE_SizeSliderText:SetText("Icon Size")

size:SetScript("OnValueChanged", function(self, v)
  if FF.SetIconSize then FF.SetIconSize(v) end
  if _G.FFE_Preview then
    _G.FFE_Preview:SetText((FF.TextureStringForKey and FF.TextureStringForKey(FF_DB.selected, FF_DB.iconSize)) or "")
  end
end)

-- Emote key label + editbox
local keyLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
keyLabel:SetPoint("TOPLEFT", size, "BOTTOMLEFT", 0, -18)
keyLabel:SetText("Emote:")

local keyEdit = CreateFrame("EditBox", "FFE_KeyEditBox", panel, "InputBoxTemplate")
keyEdit:SetPoint("TOPLEFT", keyLabel, "BOTTOMLEFT", 0, -6)
keyEdit:SetSize(220, 24)
keyEdit:SetAutoFocus(false)

-- Pressing Enter applies (same as Set)
keyEdit:SetScript("OnEnterPressed", function(self)
  ApplyEditBoxSelection(self, _G.FFE_Preview)
  self:ClearFocus()
end)

-- Set button (applies current edit box value)
local setBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
setBtn:SetPoint("LEFT", keyEdit, "RIGHT", 8, 0)
setBtn:SetSize(80, 22)
setBtn:SetText("Set")
setBtn:SetScript("OnClick", function()
  ApplyEditBoxSelection(keyEdit, _G.FFE_Preview)
end)

-- Clear button (next to Set)
local clearBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
clearBtn:SetPoint("LEFT", setBtn, "RIGHT", 8, 0)
clearBtn:SetSize(100, 22)
clearBtn:SetText("Clear")
clearBtn:SetScript("OnClick", function()
  if FF.Clear then FF.Clear() end
  keyEdit:SetText("")
  if _G.FFE_Preview then
    _G.FFE_Preview:SetText((FF.TextureStringForKey and FF.TextureStringForKey(FF_DB.selected, FF_DB.iconSize)) or "")
  end
end)

-- Preview
local previewLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
previewLabel:SetPoint("TOPLEFT", keyEdit, "BOTTOMLEFT", 0, -16)
previewLabel:SetText("Preview:")

local preview = panel:CreateFontString("FFE_Preview", "ARTWORK", "GameFontHighlightLarge")
preview:SetPoint("LEFT", previewLabel, "RIGHT", 8, 0)
preview:SetText("")



-- Populate widgets from DB
local function RefreshPanel()
  if not FF_DB then return end
  if FF_DB.enabled == nil then FF_DB.enabled = true end
  if FF_DB.animate == nil then FF_DB.animate = true end
  if FF_DB.easter  == nil then FF_DB.easter  = true end  -- default ON
  enable:SetChecked(FF_DB.enabled ~= false)
  animate:SetChecked(FF_DB.animate ~= false)
  easter:SetChecked(FF_DB.easter  ~= false)
  size:SetValue(FF_DB.iconSize or 16)
  keyEdit:SetText(FF_DB.selected or "")
  preview:SetText((FF.TextureStringForKey and FF.TextureStringForKey(FF_DB.selected, FF_DB.iconSize)) or "")
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

FF._optionsPanel = panel
FF._settingsCategory = category or nil

function FF.OpenOptions()
  if Settings and Settings.OpenToCategory and FF._settingsCategory then
    local id = FF._settingsCategory.ID or FF._settingsCategory
    Settings.OpenToCategory(id)
  elseif InterfaceOptionsFrame_OpenToCategory and FF._optionsPanel then
    InterfaceOptionsFrame_OpenToCategory(FF._optionsPanel)
    InterfaceOptionsFrame_OpenToCategory(FF._optionsPanel)
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
