-- Options.lua - Combined options panel for FuldFokus addon
-- Contains both FuldFokus Emotes and FuldStonks settings

local ADDON_NAME = "FuldFokus"
FFE = FFE or {}

-- Color constants
local COLOR_GREEN = "|cFF00FF00"
local COLOR_RESET = "|r"

-- Pretty print functions
local function ok(msg) print("|cffe5a472FFE|r " .. tostring(msg)) end
local function okFS(msg) print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " " .. tostring(msg)) end

-- --------------------------------------------------------------------
-- Main Category Panel (overview)
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
-- FuldFokus Emotes Subcategory Panel
-- --------------------------------------------------------------------
local emotesPanel = CreateFrame("Frame")
emotesPanel.name = "FuldFokus Emotes"
emotesPanel.parent = "FuldFokus"

local emotesTitle = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
emotesTitle:SetPoint("TOPLEFT", 16, -16)
emotesTitle:SetText("FuldFokus Emotes")

local emotesSub = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
emotesSub:SetPoint("TOPLEFT", emotesTitle, "BOTTOMLEFT", 0, -8)
emotesSub:SetText("Configure emote settings for FuldFokus Emotes.")

-- Info text explaining the removal of options
local emotesInfo = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
emotesInfo:SetPoint("TOPLEFT", emotesSub, "BOTTOMLEFT", 0, -12)
emotesInfo:SetText("All of the options were related to the Details emotes which is now gone. RIP.")
emotesInfo:SetTextColor(0.7, 0.7, 0.7)

local emotesInfo2 = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
emotesInfo2:SetPoint("TOPLEFT", emotesInfo, "BOTTOMLEFT", 0, -4)
emotesInfo2:SetText("Don't have anything to put here now but I don't wanna remake it in case I ever do.")
emotesInfo2:SetTextColor(0.7, 0.7, 0.7)

local emotesInfo3 = emotesPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
emotesInfo3:SetPoint("TOPLEFT", emotesInfo2, "BOTTOMLEFT", 0, -4)
emotesInfo3:SetText("Now stop reading this.")
emotesInfo3:SetTextColor(0.7, 0.7, 0.7)

-- Populate emotes panel from DB
local function RefreshEmotesPanel()
  -- No settings to refresh anymore
end

emotesPanel.refresh = RefreshEmotesPanel
emotesPanel:SetScript("OnShow", RefreshEmotesPanel)

-- --------------------------------------------------------------------
-- FuldStonks Subcategory Panel
-- --------------------------------------------------------------------
local stonksPanel = CreateFrame("Frame")
stonksPanel.name = "FuldStonks"
stonksPanel.parent = "FuldFokus"

local stonksTitle = stonksPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
stonksTitle:SetPoint("TOPLEFT", 16, -16)
stonksTitle:SetText("FuldStonks - Guild Betting")

local stonksSub = stonksPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
stonksSub:SetPoint("TOPLEFT", stonksTitle, "BOTTOMLEFT", 0, -8)
stonksSub:SetText("Configure FuldStonks betting system.")

-- Debug mode checkbox
local debug = CreateFrame("CheckButton", nil, stonksPanel, "InterfaceOptionsCheckButtonTemplate")
debug:SetPoint("TOPLEFT", stonksSub, "BOTTOMLEFT", 0, -12)
debug.Text:SetText("Enable debug mode")
debug:SetScript("OnClick", function(self)
  if FuldStonksDB then
    FuldStonksDB.debug = self:GetChecked() and true or false
    okFS("Debug mode " .. (FuldStonksDB.debug and "enabled" or "disabled") .. ".")
  end
end)

-- Info text
local stonksInfo = stonksPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
stonksInfo:SetPoint("TOPLEFT", debug, "BOTTOMLEFT", 0, -24)
stonksInfo:SetText("Use /fs or /FuldStonks to open the betting UI.")
stonksInfo:SetTextColor(0.7, 0.7, 0.7)

local stonksInfo2 = stonksPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
stonksInfo2:SetPoint("TOPLEFT", stonksInfo, "BOTTOMLEFT", 0, -8)
stonksInfo2:SetText("Type /fs help for a list of commands.")
stonksInfo2:SetTextColor(0.7, 0.7, 0.7)

-- Populate stonks panel from DB
local function RefreshStonksPanel()
  if not FuldStonksDB then return end
  if FuldStonksDB.debug == nil then FuldStonksDB.debug = false end
  debug:SetChecked(FuldStonksDB.debug ~= false)
end

stonksPanel.refresh = RefreshStonksPanel
stonksPanel:SetScript("OnShow", RefreshStonksPanel)

-- --------------------------------------------------------------------
-- Register all panels in proper hierarchy
-- --------------------------------------------------------------------
local mainCategory, emotesCategory, stonksCategory

if Settings and Settings.RegisterCanvasLayoutCategory then
  -- TWW and beyond: Use new Settings API
  -- Register main category
  mainCategory = Settings.RegisterCanvasLayoutCategory(mainPanel, mainPanel.name)
  Settings.RegisterAddOnCategory(mainCategory)
  
  -- Register subcategories under main
  emotesCategory = Settings.RegisterCanvasLayoutSubcategory(mainCategory, emotesPanel, emotesPanel.name)
  stonksCategory = Settings.RegisterCanvasLayoutSubcategory(mainCategory, stonksPanel, stonksPanel.name)
else
  -- Pre-TWW: Use old InterfaceOptions API
  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(mainPanel)
    InterfaceOptions_AddCategory(emotesPanel)
    InterfaceOptions_AddCategory(stonksPanel)
  end
end

-- Store references
FFE._mainPanel = mainPanel
FFE._emotesPanel = emotesPanel
FFE._stonksPanel = stonksPanel
FFE._mainCategory = mainCategory or nil
FFE._emotesCategory = emotesCategory or nil
FFE._stonksCategory = stonksCategory or nil

-- Function to open options
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
    C_Timer.After(0.1, function()
      RefreshEmotesPanel()
      RefreshStonksPanel()
    end)
  end
end)
