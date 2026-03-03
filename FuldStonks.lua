-- FuldStonks: Guild betting addon for World of Warcraft
-- Version: 0.2.6
-- Author: EraxterCodes
-- Part of the FuldFokus addon

-- ============================================
-- FEATURE FLAG: Toggle FuldStonks UI
-- Set to false to disable UI and show "Coming Soon" message
-- Set to true to enable full functionality for testing
-- ============================================
local FULDSTONKS_ENABLED = true

-- Create addon namespace
local ADDON_NAME = "FuldFokus"
local FuldStonks = {}
_G.FuldStonks = FuldStonks  -- Make it globally accessible for commands and options

-- Initialize saved variables
FuldStonksDB = FuldStonksDB or {
    activeBets = {},      -- Active bets in the system
    myBets = {},          -- Bets I've placed
    betHistory = {},      -- Historical bets
    ignoredBets = {},     -- Bets hidden from view
    showHiddenBets = false, -- Show hidden bets in active list UI
    devModeEnabled = false, -- Enable local UI test data generation
    stateVersion = 0,     -- Lamport clock for state versioning
    syncNonce = 0         -- Nonce to track sync sessions
}

-- Constants
local COLOR_GREEN = "|cFF00FF00"
local COLOR_RESET = "|r"
local COLOR_YELLOW = "|cFFFFFF00"
local COLOR_RED = "|cFFFF0000"
local COLOR_ORANGE = "|cFFFF8800"
local COLOR_GRAY = "|cFF808080"

-- State sync constants
local STATE_SYNC_INTERVAL = 5  -- Seconds between state broadcasts
local STATE_CLEANUP_TIMEOUT = 30  -- Seconds before cleaning up stale state updates
local SYNC_TYPE_HEADER = "HEADER"
local SYNC_TYPE_BET = "BET"
local SYNC_TYPE_PARTICIPANT = "PARTICIPANT"
local SYNC_TYPE_HISTORY = "HISTORY"

-- Addon state
FuldStonks.version = "0.3.0"
FuldStonks.frame = nil
FuldStonks.peers = {}           -- Track connected peers: [fullName] = { lastSeen = time, stateVersion = 0, nonce = 0 }
FuldStonks.lastBroadcast = 0    -- Rate limiting for broadcasts
FuldStonks.syncRequested = false
FuldStonks.syncTicker = nil     -- Store state sync ticker for cleanup (replaces heartbeat)
FuldStonks.lastBroadcastState = nil  -- Track last broadcast state to avoid spam
FuldStonks.rosterUpdateTimer = nil  -- Debounce timer for roster updates
FuldStonks.betIdCounter = 0      -- Counter for generating unique bet IDs
FuldStonks.pendingBets = {}      -- Track pending bets awaiting gold trade: {betId, option, amount}
FuldStonks.pendingStateUpdates = {}  -- Queue for state updates to be applied

-- Event frame for initialization
local eventFrame = CreateFrame("Frame")

-- Get player's full name (Name-Realm)
local playerName, playerRealm = UnitFullName("player")
local playerFullName = (playerRealm and playerRealm ~= "" and (playerName .. "-" .. playerRealm)) or playerName

-- Helper function for debug output
local function DebugPrint(msg, category)
    if FuldStonksDB.debug == true then
        local timestamp = date("%H:%M:%S")
        category = category or "DEBUG"
        print(COLOR_GREEN .. "FuldStonks [" .. category .. "]" .. COLOR_RESET .. " " .. timestamp .. " " .. tostring(msg))
    end
end

-- Log only if something changed
local function LogIfChanged(msg, changed, section)
    if changed and FuldStonksDB.debug == true then
        DebugPrint(msg, section or "CHANGE")
    end
end

-- Static popup for confirming bet cancellation
StaticPopupDialogs["FULDSTONKS_CONFIRM_CANCEL"] = {
    text = "Cancel this bet and return all gold to participants?",
    button1 = "Yes",
    button2 = "No",
    OnAccept = function(self, betId)
        FuldStonks:CancelBet(betId)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Helper function to extract base name (remove realm suffix)
-- Handles hyphenated names correctly: "Mary-Jane-Stormrage" -> "Mary-Jane"
local function GetPlayerBaseName(fullName)
    if not fullName or fullName == "" then
        return fullName
    end
    return fullName:gsub("%-[^%-]*$", "")
end

-- Generate unique bet ID
local function GenerateBetId()
    FuldStonks.betIdCounter = FuldStonks.betIdCounter + 1
    local timestamp = math.floor(GetTime())
    return playerName .. "-" .. timestamp .. "-" .. FuldStonks.betIdCounter
end

-- Serialize bet data for transmission
local function SerializeBet(bet)
    -- Format: betId|title|betType|option1,option2,...|createdBy|timestamp
    local options = table.concat(bet.options, ",")
    return bet.id .. "|" .. bet.title .. "|" .. bet.betType .. "|" .. options .. "|" .. bet.createdBy .. "|" .. bet.timestamp
end

-- Deserialize bet data from message
local function DeserializeBet(betString)
    local parts = {strsplit("|", betString)}
    if #parts < 6 then return nil end
    
    local bet = {
        id = parts[1],
        title = parts[2],
        betType = parts[3],
        options = {strsplit(",", parts[4])},
        createdBy = parts[5],
        timestamp = tonumber(parts[6]) or 0,
        participants = {},  -- {playerName = {option = "Yes", amount = 100}}
        totalPot = 0,
        status = "active",   -- active, locked, resolved
        pendingTrades = {}   -- Only used by bet holder
    }
    return bet
end

-- Addon initialization
local function Initialize()
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " addon loaded! Type /FuldStonks or /fs to open the UI.")
end

-- Create the main UI frame
local function CreateMainFrame()
    if FuldStonks.frame then
        return FuldStonks.frame
    end
    
    -- Create main frame
    local frame = CreateFrame("Frame", "FuldStonksMainFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(600, 480)  -- Increased height slightly for better spacing
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    
    -- Set title
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.title:SetPoint("TOP", frame.TitleBg, "TOP", 0, -3)
    frame.title:SetText("FuldStonks - Guild Betting")
    
    -- Tab system
    frame.currentTab = "active"  -- "active" or "stats"
    
    -- Active Bets tab button
    frame.activeTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.activeTab:SetSize(140, 28)
    frame.activeTab:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -30)
    frame.activeTab:SetText("Active Bets")
    frame.activeTab:SetScript("OnClick", function()
        frame.currentTab = "active"
        frame:UpdateBetList()
        frame.activeTab:Disable()
        frame.statsTab:Enable()
    end)
    
    -- Stats tab button
    frame.statsTab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.statsTab:SetSize(140, 28)
    frame.statsTab:SetPoint("TOPLEFT", frame.activeTab, "TOPRIGHT", 5, 0)
    frame.statsTab:SetText("Stats")
    frame.statsTab:SetScript("OnClick", function()
        frame.currentTab = "stats"
        frame:UpdateBetList()
        frame.statsTab:Disable()
        frame.activeTab:Enable()
    end)
    
    -- Start with active tab selected
    frame.activeTab:Disable()
    
    -- Tab content title
    frame.tabTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.tabTitle:SetPoint("TOPLEFT", frame.activeTab, "BOTTOMLEFT", 5, -12)
    frame.tabTitle:SetText("Active Bets:")

    -- Show hidden toggle (active tab only)
    frame.showHiddenCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.showHiddenCheck:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -64)
    frame.showHiddenCheck:SetChecked(FuldStonksDB.showHiddenBets == true)
    frame.showHiddenCheck:SetScript("OnClick", function(btn)
        FuldStonksDB.showHiddenBets = btn:GetChecked() and true or false
        frame:UpdateBetList()
    end)

    frame.showHiddenLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.showHiddenLabel:SetPoint("RIGHT", frame.showHiddenCheck, "LEFT", -2, 0)
    frame.showHiddenLabel:SetText("Show hidden")
    frame.showHiddenLabel:SetTextColor(0.85, 0.85, 0.85)
    
    -- Stats headers (shown in stats tab)
    frame.statsHeadersFrame = CreateFrame("Frame", nil, frame)
    frame.statsHeadersFrame:SetPoint("TOPLEFT", frame.tabTitle, "BOTTOMLEFT", -5, -8)
    frame.statsHeadersFrame:SetSize(520, 25)
    frame.statsHeadersFrame:Hide()
    
    frame.winnersHeader = frame.statsHeadersFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.winnersHeader:SetPoint("TOPLEFT", frame.statsHeadersFrame, "TOPLEFT", 0, 0)
    frame.winnersHeader:SetText(COLOR_GREEN .. "Winners" .. COLOR_RESET)
    
    frame.losersHeader = frame.statsHeadersFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.losersHeader:SetPoint("TOPLEFT", frame.statsHeadersFrame, "TOPLEFT", 270, 0)
    frame.losersHeader:SetText(COLOR_RED .. "Losers" .. COLOR_RESET)
    
    -- Scrollable bet list (adjusted to leave room for bottom button)
    frame.betList = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.betList:SetPoint("TOPLEFT", frame.tabTitle, "BOTTOMLEFT", -5, -8)
    frame.betList:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -30, 55)  -- More space at bottom
    
    frame.betListContent = CreateFrame("Frame", nil, frame.betList)
    frame.betListContent:SetSize(540, 1)
    frame.betList:SetScrollChild(frame.betListContent)
    
    -- Create "Create Bet" button at bottom (larger and centered)
    frame.createBetButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.createBetButton:SetSize(200, 35)
    frame.createBetButton:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    frame.createBetButton:SetText("+ Create New Bet")
    frame.createBetButton:SetNormalFontObject("GameFontNormalLarge")
    frame.createBetButton:SetScript("OnClick", function()
        FuldStonks:ShowBetCreationDialog()
    end)


    
    -- Function to update bet list display
    frame.UpdateBetList = function(self)
        -- Clear existing children
        for _, child in pairs({self.betListContent:GetChildren()}) do
            child:Hide()
            child:SetParent(nil)
        end

        -- Hide reusable "no bets" message
        if self.noBetsText then
            self.noBetsText:Hide()
        end
        
        -- Update tab title and visibility
        if self.currentTab == "active" then
            self.tabTitle:SetText("Active Bets:")
            self.showHiddenCheck:Show()
            self.showHiddenLabel:Show()
            self.statsHeadersFrame:Hide()
        else -- stats
            self.tabTitle:SetText("Statistics:")
            self.showHiddenCheck:Hide()
            self.showHiddenLabel:Hide()
            self.statsHeadersFrame:Show()
        end
        
        local yOffset = 0
        local betCount = 0
        local activeTotalCount, activeHiddenCount, showHidden = 0, 0, false
        
        -- ACTIVE BETS TAB
        if self.currentTab == "active" then
            showHidden = (FuldStonksDB.showHiddenBets == true)
            local betsToShow = {}
            
            -- Collect visible active bets
            for betId, bet in pairs(FuldStonksDB.activeBets) do
                if bet.status == "active" then
                    activeTotalCount = activeTotalCount + 1
                    local isHidden = FuldStonksDB.ignoredBets[betId] == true
                    if isHidden then
                        activeHiddenCount = activeHiddenCount + 1
                    end

                    if showHidden or not isHidden then
                        table.insert(betsToShow, {id = betId, bet = bet, isHidden = isHidden})
                    end
                end
            end
            
            -- Render each active bet
            for _, betData in ipairs(betsToShow) do
                local betId = betData.id
                local bet = betData.bet
                local isHidden = betData.isHidden == true
                
                local betFrame = CreateFrame("Frame", nil, self.betListContent, "BackdropTemplate")
                betFrame:SetSize(520, 110)
                betFrame:SetPoint("TOPLEFT", self.betListContent, "TOPLEFT", 0, -yOffset)
                betFrame:SetBackdrop({
                    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
                    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 }
                })
                betFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
                betFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
                
                -- Bet title
                local title = betFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                title:SetPoint("TOPLEFT", betFrame, "TOPLEFT", 10, -8)
                title:SetText(bet.title)
                title:SetJustifyH("LEFT")
                title:SetWidth(445)
                
                -- Hide/Unhide button
                local hideButton = CreateFrame("Button", nil, betFrame, "UIPanelButtonTemplate")
                hideButton:SetSize(62, 20)
                hideButton:SetPoint("TOPRIGHT", betFrame, "TOPRIGHT", -8, -8)
                hideButton:SetText(isHidden and "Unhide" or "Hide")
                hideButton:SetScript("OnClick", function()
                    if isHidden then
                        FuldStonks:UnhideBet(betId)
                    else
                        FuldStonks:HideBet(betId)
                    end
                    self:UpdateBetList()
                end)
                
                -- Creator info
                local creatorName = GetPlayerBaseName(bet.createdBy)
                local info = betFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                info:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
                info:SetWidth(500)
                info:SetWordWrap(false)
                info:SetText("By: " .. creatorName .. " • Type: " .. bet.betType .. " • Pot: " .. bet.totalPot .. "g")
                info:SetTextColor(0.7, 0.7, 0.7)
                
                -- Check for pending bet
                local hasPending = FuldStonks.pendingBets[playerFullName] and FuldStonks.pendingBets[playerFullName].betId == betId
                
                if hasPending then
                    -- Show pending status
                    local pendingBet = FuldStonks.pendingBets[playerFullName]
                    local pendingText = betFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    pendingText:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -3)
                    pendingText:SetWidth(500)
                    pendingText:SetWordWrap(false)
                    pendingText:SetText(COLOR_ORANGE .. "⏳ PENDING: " .. pendingBet.option .. " (" .. pendingBet.amount .. "g)" .. COLOR_RESET)
                    pendingText:SetTextColor(1, 0.5, 0)
                    
                    -- Cancel button
                    local cancelButton = CreateFrame("Button", nil, betFrame, "UIPanelButtonTemplate")
                    cancelButton:SetSize(80, 22)
                    cancelButton:SetPoint("TOPLEFT", pendingText, "BOTTOMLEFT", 0, -5)
                    cancelButton:SetText("Cancel")
                    cancelButton:SetScript("OnClick", function()
                        FuldStonks:CancelPendingBet()
                        self:UpdateBetList()
                    end)
                    
                    -- Inspect button
                    local inspectButton = CreateFrame("Button", nil, betFrame, "UIPanelButtonTemplate")
                    inspectButton:SetSize(80, 22)
                    inspectButton:SetPoint("TOPLEFT", pendingText, "BOTTOMLEFT", 85, -5)
                    inspectButton:SetText("Inspect")
                    inspectButton:SetScript("OnClick", function()
                        FuldStonks:ShowBetInspectDialog(betId)
                    end)
                else
                    -- Place bet buttons for each option
                    local buttonOffset = 0
                    for _, option in ipairs(bet.options) do
                        local optionButton = CreateFrame("Button", nil, betFrame, "UIPanelButtonTemplate")
                        optionButton:SetSize(75, 22)
                        optionButton:SetPoint("TOPLEFT", info, "BOTTOMLEFT", buttonOffset, -5)
                        optionButton:SetText(option)
                        optionButton:SetScript("OnClick", function()
                            FuldStonks:ShowPlaceBetDialog(betId, option)
                        end)
                        buttonOffset = buttonOffset + 80
                    end
                    
                    -- Inspect button
                    local inspectButton = CreateFrame("Button", nil, betFrame, "UIPanelButtonTemplate")
                    inspectButton:SetSize(80, 22)
                    inspectButton:SetPoint("TOPLEFT", info, "BOTTOMLEFT", buttonOffset, -5)
                    inspectButton:SetText("Inspect")
                    inspectButton:SetScript("OnClick", function()
                        FuldStonks:ShowBetInspectDialog(betId)
                    end)
                end
                
                yOffset = yOffset + 118
                betCount = betCount + 1
            end
        
        -- STATS TAB
        else
            -- Offset for headers
            yOffset = 30
            
            -- Calculate cumulative statistics
            local playerStats = {}
            
            for betId, bet in pairs(FuldStonksDB.betHistory) do
                if bet.status == "resolved" and bet.winningOption then
                    for playerName, participation in pairs(bet.participants or {}) do
                        if not playerStats[playerName] then
                            playerStats[playerName] = {wins = 0, losses = 0, totalWon = 0, totalLost = 0}
                        end
                        
                        if participation.option == bet.winningOption then
                            playerStats[playerName].wins = playerStats[playerName].wins + 1
                            playerStats[playerName].totalWon = playerStats[playerName].totalWon + (participation.amount or 0)
                        else
                            playerStats[playerName].losses = playerStats[playerName].losses + 1
                            playerStats[playerName].totalLost = playerStats[playerName].totalLost + (participation.amount or 0)
                        end
                    end
                end
            end
            
            -- Separate and sort users
            local winners = {}
            local losers = {}
            
            for playerName, stats in pairs(playerStats) do
                local net = stats.totalWon - stats.totalLost
                if net > 0 then
                    table.insert(winners, {name = playerName, stats = stats, net = net})
                elseif net < 0 then
                    table.insert(losers, {name = playerName, stats = stats, net = math.abs(net)})
                else
                    table.insert(winners, {name = playerName, stats = stats, net = 0})
                end
            end
            
            table.sort(winners, function(a, b) return a.net > b.net end)
            table.sort(losers, function(a, b) return a.net > b.net end)
            
            -- Display side-by-side columns
            local maxRows = math.max(#winners, #losers)
            
            for i = 1, maxRows do
                -- Winner column (left)
                if winners[i] then
                    local winner = winners[i]
                    local winFrame = CreateFrame("Frame", nil, self.betListContent, "BackdropTemplate")
                    winFrame:SetSize(230, 45)
                    winFrame:SetPoint("TOPLEFT", self.betListContent, "TOPLEFT", 5, -yOffset)
                    winFrame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 8, insets = { left = 3, right = 3, top = 3, bottom = 3 }})
                    winFrame:SetBackdropColor(0.05, 0.15, 0.05, 0.7)
                    winFrame:SetBackdropBorderColor(0.2, 0.6, 0.2, 0.8)
                    
                    local name = winFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    name:SetPoint("TOPLEFT", winFrame, "TOPLEFT", 8, -5)
                    name:SetText(GetPlayerBaseName(winner.name))
                    name:SetTextColor(0.9, 0.9, 0.9)
                    
                    local gold = winFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    gold:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
                    gold:SetText(COLOR_GREEN .. "+" .. winner.net .. "g" .. COLOR_RESET)
                    gold:SetTextColor(0.5, 1, 0.5)
                    
                    local record = winFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    record:SetPoint("TOPLEFT", gold, "BOTTOMLEFT", 0, -2)
                    record:SetText(winner.stats.wins .. "W - " .. winner.stats.losses .. "L")
                    record:SetTextColor(0.7, 0.7, 0.7)
                    
                    betCount = betCount + 1
                end
                
                -- Loser column (right)
                if losers[i] then
                    local loser = losers[i]
                    local loseFrame = CreateFrame("Frame", nil, self.betListContent, "BackdropTemplate")
                    loseFrame:SetSize(230, 45)
                    loseFrame:SetPoint("TOPLEFT", self.betListContent, "TOPLEFT", 265, -yOffset)
                    loseFrame:SetBackdrop({bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 8, insets = { left = 3, right = 3, top = 3, bottom = 3 }})
                    loseFrame:SetBackdropColor(0.15, 0.05, 0.05, 0.7)
                    loseFrame:SetBackdropBorderColor(0.6, 0.2, 0.2, 0.8)
                    
                    local name = loseFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    name:SetPoint("TOPLEFT", loseFrame, "TOPLEFT", 8, -5)
                    name:SetText(GetPlayerBaseName(loser.name))
                    name:SetTextColor(0.9, 0.9, 0.9)
                    
                    local gold = loseFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    gold:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
                    gold:SetText(COLOR_RED .. "-" .. loser.net .. "g" .. COLOR_RESET)
                    gold:SetTextColor(1, 0.5, 0.5)
                    
                    local record = loseFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                    record:SetPoint("TOPLEFT", gold, "BOTTOMLEFT", 0, -2)
                    record:SetText(loser.stats.wins .. "W - " .. loser.stats.losses .. "L")
                    record:SetTextColor(0.7, 0.7, 0.7)
                    
                    betCount = betCount + 1
                end
                
                yOffset = yOffset + 50
            end
        end
        
        -- Show "no bets" message if empty
        if betCount == 0 then
            if not self.noBetsText then
                self.noBetsText = self.betListContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                self.noBetsText:SetPoint("TOP", self.betListContent, "TOP", 0, -20)
                self.noBetsText:SetJustifyH("CENTER")
            end

            if self.currentTab == "active" then
                if activeTotalCount > 0 and activeHiddenCount == activeTotalCount and not showHidden then
                    self.noBetsText:SetText("All active bets are hidden.\nEnable " .. COLOR_YELLOW .. "Show hidden" .. COLOR_RESET .. " or use " .. COLOR_YELLOW .. "/fs unhideall" .. COLOR_RESET .. ".")
                else
                    self.noBetsText:SetText("No active bets.\nUse " .. COLOR_YELLOW .. "/fs create" .. COLOR_RESET .. " to create one!")
                end
            else
                self.noBetsText:SetText("No statistics yet.\nWin some bets to see your stats!")
            end
            self.noBetsText:Show()
        end
        
        self.betListContent:SetHeight(math.max(yOffset + 20, 300))
    end
    
    -- Create connected peers display
    frame.peersText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.peersText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
    frame.peersText:SetJustifyH("LEFT")
    frame.peersText:SetTextColor(0.6, 0.6, 0.6)
    
    -- Update function for peers display
    frame.UpdatePeers = function(self)
        local peerCount = 0
        for _ in pairs(FuldStonks.peers) do
            peerCount = peerCount + 1
        end
        self.peersText:SetText("Connected: " .. peerCount .. " peers • v" .. FuldStonks.version)
    end
    
    -- Create close button handler
    frame.CloseButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    
    -- Update displays every 2 seconds when visible
    frame:SetScript("OnShow", function(self)
        self:UpdatePeers()
        self:UpdateBetList()
        self.updateTicker = C_Timer.NewTicker(2, function()
            if self:IsShown() then
                self:UpdatePeers()
                self:UpdateBetList()
            end
        end)
    end)
    
    frame:SetScript("OnHide", function(self)
        if self.updateTicker then
            self.updateTicker:Cancel()
            self.updateTicker = nil
        end
    end)
    
    -- Initial update
    frame:UpdatePeers()
    frame:UpdateBetList()
    
    FuldStonks.frame = frame
    return frame
end

-- Show "Coming Soon" dialog when feature is disabled
local function ShowComingSoonDialog()
    -- Create the dialog if it doesn't exist
    if not FuldStonks.comingSoonDialog then
        local dialog = CreateFrame("Frame", "FuldStonksComingSoonDialog", UIParent, "BasicFrameTemplateWithInset")
        dialog:SetSize(400, 200)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        
        -- Title
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.title:SetPoint("TOP", 0, -8)
        dialog.title:SetText("FuldStonks - Coming Soon!")
        
        -- Main message
        dialog.message = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.message:SetPoint("TOP", 0, -50)
        dialog.message:SetWidth(350)
        dialog.message:SetJustifyH("CENTER")
        dialog.message:SetText("The FuldStonks guild betting system is\ncurrently under development.")
        
        -- Teaser message
        dialog.teaser = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.teaser:SetPoint("TOP", 0, -90)
        dialog.teaser:SetWidth(350)
        dialog.teaser:SetJustifyH("CENTER")
        dialog.teaser:SetText("Skud ud til Oskar for at hjælpe med testing - Jeg giver end red bull til LAN!")
        dialog.teaser:SetTextColor(0.7, 0.7, 0.7)
        
        -- Stay tuned message
        dialog.footer = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dialog.footer:SetPoint("BOTTOM", 0, 30)
        dialog.footer:SetText("Stay tuned for the official release!")
        dialog.footer:SetTextColor(1, 0.82, 0)
        
        -- Close button
        local closeBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        closeBtn:SetSize(100, 25)
        closeBtn:SetPoint("BOTTOM", 0, 10)
        closeBtn:SetText("Close")
        closeBtn:SetScript("OnClick", function()
            dialog:Hide()
        end)
        
        FuldStonks.comingSoonDialog = dialog
    end
    
    FuldStonks.comingSoonDialog:Show()
end

-- Toggle main frame visibility
function FuldStonks.ToggleMainFrame()
    -- Check if feature is enabled
    if not FULDSTONKS_ENABLED then
        ShowComingSoonDialog()
        return
    end
    
    local frame = CreateMainFrame()
    
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- Show bet creation dialog
function FuldStonks:ShowBetCreationDialog()
    -- Create dialog if it doesn't exist
    if not self.betCreationDialog then
        local dialog = CreateFrame("Frame", "FuldStonksBetCreationDialog", UIParent, "BasicFrameTemplateWithInset")
        dialog:SetSize(400, 300)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        dialog:Hide()
        
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.title:SetPoint("TOP", dialog.TitleBg, "TOP", 0, -3)
        dialog.title:SetText("Create New Bet")
        
        -- Bet title input
        dialog.titleLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.titleLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -35)
        dialog.titleLabel:SetText("Bet Question:")
        
        dialog.titleInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
        dialog.titleInput:SetSize(360, 20)
        dialog.titleInput:SetPoint("TOPLEFT", dialog.titleLabel, "BOTTOMLEFT", 10, -5)
        dialog.titleInput:SetAutoFocus(false)
        dialog.titleInput:SetMaxLetters(100)
        
        -- Bet type selector
        dialog.typeLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.typeLabel:SetPoint("TOPLEFT", dialog.titleInput, "BOTTOMLEFT", -10, -15)
        dialog.typeLabel:SetText("Bet Type:")
        
        -- Yes/No radio button
        dialog.yesNoRadio = CreateFrame("CheckButton", nil, dialog, "UIRadioButtonTemplate")
        dialog.yesNoRadio:SetPoint("TOPLEFT", dialog.typeLabel, "BOTTOMLEFT", 0, -5)
        dialog.yesNoRadio.text:SetText("Yes/No")
        dialog.yesNoRadio:SetChecked(true)
        
        -- Multiple choice radio (for future expansion)
        dialog.multiRadio = CreateFrame("CheckButton", nil, dialog, "UIRadioButtonTemplate")
        dialog.multiRadio:SetPoint("TOPLEFT", dialog.yesNoRadio, "BOTTOMLEFT", 0, -5)
        dialog.multiRadio.text:SetText("Multiple Choice (Coming Soon)")
        dialog.multiRadio:Disable()
        
        -- Radio button behavior
        dialog.yesNoRadio:SetScript("OnClick", function(self)
            self:SetChecked(true)
            dialog.multiRadio:SetChecked(false)
        end)
        
        -- Create button
        dialog.createButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.createButton:SetSize(100, 25)
        dialog.createButton:SetPoint("BOTTOM", dialog, "BOTTOM", -55, 15)
        dialog.createButton:SetText("Create")
        dialog.createButton:SetScript("OnClick", function()
            local title = dialog.titleInput:GetText()
            if title and title ~= "" then
                local betType = "YesNo"  -- Default for now
                local options = {"Yes", "No"}
                
                FuldStonks:CreateBet({
                    title = title,
                    betType = betType,
                    options = options
                })
                
                dialog.titleInput:SetText("")
                dialog:Hide()
            else
                print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Please enter a bet question!")
            end
        end)
        
        -- Cancel button
        dialog.cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.cancelButton:SetSize(100, 25)
        dialog.cancelButton:SetPoint("BOTTOM", dialog, "BOTTOM", 55, 15)
        dialog.cancelButton:SetText("Cancel")
        dialog.cancelButton:SetScript("OnClick", function()
            dialog.titleInput:SetText("")
            dialog:Hide()
        end)
        
        dialog.CloseButton:SetScript("OnClick", function()
            dialog.titleInput:SetText("")
            dialog:Hide()
        end)
        
        self.betCreationDialog = dialog
    end
    
    self.betCreationDialog:Show()
end

-- Show place bet dialog
function FuldStonks:ShowPlaceBetDialog(betId, option)
    -- Create dialog if it doesn't exist
    if not self.placeBetDialog then
        local dialog = CreateFrame("Frame", "FuldStonksPlaceBetDialog", UIParent, "BasicFrameTemplateWithInset")
        dialog:SetSize(350, 200)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        dialog:Hide()
        
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.title:SetPoint("TOP", dialog.TitleBg, "TOP", 0, -3)
        dialog.title:SetText("Place Bet")
        
        dialog.betInfo = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.betInfo:SetPoint("TOP", dialog, "TOP", 0, -40)
        dialog.betInfo:SetWidth(310)
        dialog.betInfo:SetJustifyH("CENTER")
        
        dialog.amountLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.amountLabel:SetPoint("TOP", dialog.betInfo, "BOTTOM", 0, -20)
        dialog.amountLabel:SetText("Amount (gold):")
        
        dialog.amountInput = CreateFrame("EditBox", nil, dialog, "InputBoxTemplate")
        dialog.amountInput:SetSize(100, 20)
        dialog.amountInput:SetPoint("TOP", dialog.amountLabel, "BOTTOM", 0, -5)
        dialog.amountInput:SetAutoFocus(false)
        dialog.amountInput:SetNumeric(true)
        dialog.amountInput:SetMaxLetters(10)
        
        dialog.placeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.placeButton:SetSize(100, 25)
        dialog.placeButton:SetPoint("BOTTOM", dialog, "BOTTOM", -55, 15)
        dialog.placeButton:SetText("Place Bet")
        
        dialog.cancelButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.cancelButton:SetSize(100, 25)
        dialog.cancelButton:SetPoint("BOTTOM", dialog, "BOTTOM", 55, 15)
        dialog.cancelButton:SetText("Cancel")
        dialog.cancelButton:SetScript("OnClick", function()
            dialog:Hide()
        end)
        
        dialog.CloseButton:SetScript("OnClick", function()
            dialog:Hide()
        end)
        
        self.placeBetDialog = dialog
    end
    
    -- Set current bet info
    local bet = FuldStonksDB.activeBets[betId]
    if bet then
        self.placeBetDialog.betInfo:SetText("Betting " .. COLOR_YELLOW .. option .. COLOR_RESET .. " on:\n" .. bet.title)
        self.placeBetDialog.currentBetId = betId
        self.placeBetDialog.currentOption = option
        
        self.placeBetDialog.placeButton:SetScript("OnClick", function()
            local amount = tonumber(self.placeBetDialog.amountInput:GetText())
            if amount and amount > 0 then
                FuldStonks:PlaceBet(betId, option, amount)
                self.placeBetDialog.amountInput:SetText("")
                self.placeBetDialog:Hide()
            else
                print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Please enter a valid amount!")
            end
        end)
        
        self.placeBetDialog:Show()
    end
end

-- Show bet resolution dialog
function FuldStonks:ShowBetResolutionDialog(betId)
    betId = betId or self.selectedBetForResolution
    
    if not betId then
        -- If no betId provided, show selection dialog
        self:ShowBetSelectionDialog()
        return
    end
    
    local bet = FuldStonksDB.activeBets[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Bet not found!")
        return
    end
    
    -- Only bet creator can resolve
    if bet.createdBy ~= playerFullName then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Only the bet creator can resolve this bet!")
        return
    end
    
    -- Create dialog if it doesn't exist
    if not self.resolutionDialog then
        local dialog = CreateFrame("Frame", "FuldStonksResolutionDialog", UIParent, "BasicFrameTemplateWithInset")
        dialog:SetSize(450, 400)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        dialog:Hide()
        
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.title:SetPoint("TOP", dialog.TitleBg, "TOP", 0, -3)
        dialog.title:SetText("Resolve Bet")
        
        dialog.betTitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.betTitle:SetPoint("TOP", dialog, "TOP", 0, -35)
        dialog.betTitle:SetWidth(420)
        dialog.betTitle:SetJustifyH("CENTER")
        
        dialog.infoLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.infoLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 20, -70)
        dialog.infoLabel:SetText("Select winning option:")
        
        -- Scrollable payout info
        dialog.scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        dialog.scrollFrame:SetPoint("TOPLEFT", dialog.infoLabel, "BOTTOMLEFT", 0, -10)
        dialog.scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 80)
        
        dialog.scrollContent = CreateFrame("Frame", nil, dialog.scrollFrame)
        dialog.scrollContent:SetSize(390, 1)
        dialog.scrollFrame:SetScrollChild(dialog.scrollContent)
        
        dialog.payoutText = dialog.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dialog.payoutText:SetPoint("TOPLEFT", dialog.scrollContent, "TOPLEFT", 0, 0)
        dialog.payoutText:SetWidth(390)
        dialog.payoutText:SetJustifyH("LEFT")
        
        dialog.CloseButton:SetScript("OnClick", function()
            dialog:Hide()
        end)
        
        self.resolutionDialog = dialog
    end
    
    -- Set bet info
    self.resolutionDialog.betTitle:SetText(COLOR_YELLOW .. bet.title .. COLOR_RESET)
    self.resolutionDialog.currentBetId = betId
    
    -- Calculate and show payout information
    local payoutInfo = "Total Pot: " .. COLOR_GREEN .. bet.totalPot .. "g" .. COLOR_RESET .. "\n\n"
    
    -- Group participants by option
    local optionGroups = {}
    for playerName, participation in pairs(bet.participants) do
        if not optionGroups[participation.option] then
            optionGroups[participation.option] = {}
        end
        table.insert(optionGroups[participation.option], {name = playerName, amount = participation.amount})
    end
    
    -- Show breakdown for each option
    for _, option in ipairs(bet.options) do
        local group = optionGroups[option] or {}
        local totalBets = 0
        for _, p in ipairs(group) do
            totalBets = totalBets + p.amount
        end
        
        payoutInfo = payoutInfo .. COLOR_YELLOW .. option .. ":" .. COLOR_RESET .. " " .. #group .. " bets, " .. totalBets .. "g total\n"
        
        if #group > 0 then
            for _, p in ipairs(group) do
                local baseName = GetPlayerBaseName(p.name)
                local payout = math.floor((p.amount / totalBets) * bet.totalPot)
                local profit = payout - p.amount
                payoutInfo = payoutInfo .. "  " .. baseName .. ": " .. p.amount .. "g bet → " .. payout .. "g payout ("
                if profit > 0 then
                    payoutInfo = payoutInfo .. COLOR_GREEN .. "+" .. profit .. "g" .. COLOR_RESET
                elseif profit < 0 then
                    payoutInfo = payoutInfo .. COLOR_RED .. profit .. "g" .. COLOR_RESET
                else
                    payoutInfo = payoutInfo .. "0g"
                end
                payoutInfo = payoutInfo .. ")\n"
            end
        else
            payoutInfo = payoutInfo .. "  No bets\n"
        end
        payoutInfo = payoutInfo .. "\n"
    end
    
    self.resolutionDialog.payoutText:SetText(payoutInfo)
    
    -- Update scroll content height
    local textHeight = self.resolutionDialog.payoutText:GetStringHeight()
    self.resolutionDialog.scrollContent:SetHeight(math.max(textHeight + 20, 200))
    
    -- Clear old option buttons
    if self.resolutionDialog.optionButtons then
        for _, btn in ipairs(self.resolutionDialog.optionButtons) do
            btn:Hide()
            btn:SetParent(nil)
        end
    end
    self.resolutionDialog.optionButtons = {}
    
    -- Create option buttons
    local buttonOffset = 0
    for _, option in ipairs(bet.options) do
        local optionButton = CreateFrame("Button", nil, self.resolutionDialog, "UIPanelButtonTemplate")
        optionButton:SetSize(100, 25)
        optionButton:SetPoint("BOTTOMLEFT", self.resolutionDialog, "BOTTOMLEFT", 20 + buttonOffset, 15)
        optionButton:SetText(option .. " Wins")
        optionButton:SetScript("OnClick", function()
            FuldStonks:ResolveBet(betId, option)
            self.resolutionDialog:Hide()
        end)
        table.insert(self.resolutionDialog.optionButtons, optionButton)
        buttonOffset = buttonOffset + 110
    end
    
    -- Cancel button
    local cancelButton = CreateFrame("Button", nil, self.resolutionDialog, "UIPanelButtonTemplate")
    cancelButton:SetSize(100, 25)
    cancelButton:SetPoint("BOTTOMRIGHT", self.resolutionDialog, "BOTTOMRIGHT", -20, 15)
    cancelButton:SetText("Cancel")
    cancelButton:SetScript("OnClick", function()
        self.resolutionDialog:Hide()
    end)
    table.insert(self.resolutionDialog.optionButtons, cancelButton)
    
    self.resolutionDialog:Show()
end

-- Show bet selection dialog for resolution
function FuldStonks:ShowBetSelectionDialog()
    -- Find bets created by this player
    local myBets = {}
    for betId, bet in pairs(FuldStonksDB.activeBets) do
        if bet.createdBy == playerFullName and bet.status == "active" then
            table.insert(myBets, {id = betId, title = bet.title})
        end
    end
    
    if #myBets == 0 then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " You have no active bets to resolve.")
        return
    end
    
    if #myBets == 1 then
        -- Only one bet, show resolution dialog directly
        self:ShowBetResolutionDialog(myBets[1].id)
        return
    end
    
    -- Multiple bets, let user choose
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Select a bet to resolve:")
    for i, bet in ipairs(myBets) do
        print("  " .. i .. ". " .. bet.title)
    end
    print("Use: /fs resolve (from UI click Resolve button on the specific bet)")
end

-- Show payout dialog
function FuldStonks:ShowPayoutDialog(betId, winningOption)
    local bet = FuldStonksDB.betHistory[betId] or FuldStonksDB.activeBets[betId]
    if not bet then
        return
    end
    
    -- Create dialog if it doesn't exist
    if not self.payoutDialog then
        local dialog = CreateFrame("Frame", "FuldStonksPayoutDialog", UIParent, "BasicFrameTemplateWithInset")
        dialog:SetSize(500, 450)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        dialog:Hide()
        
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.title:SetPoint("TOP", dialog.TitleBg, "TOP", 0, -3)
        dialog.title:SetText("Payout Summary")
        
        dialog.betTitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.betTitle:SetPoint("TOP", dialog, "TOP", 0, -35)
        dialog.betTitle:SetWidth(460)
        dialog.betTitle:SetJustifyH("CENTER")
        
        dialog.resultText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.resultText:SetPoint("TOP", dialog.betTitle, "BOTTOM", 0, -10)
        dialog.resultText:SetWidth(460)
        dialog.resultText:SetJustifyH("CENTER")
        
        -- Scrollable payout list
        dialog.scrollFrame = CreateFrame("ScrollFrame", nil, dialog, "UIPanelScrollFrameTemplate")
        dialog.scrollFrame:SetPoint("TOPLEFT", dialog.resultText, "BOTTOMLEFT", 0, -15)
        dialog.scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 50)
        
        dialog.scrollContent = CreateFrame("Frame", nil, dialog.scrollFrame)
        dialog.scrollContent:SetSize(440, 1)
        dialog.scrollFrame:SetScrollChild(dialog.scrollContent)
        
        dialog.payoutText = dialog.scrollContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.payoutText:SetPoint("TOPLEFT", dialog.scrollContent, "TOPLEFT", 0, 0)
        dialog.payoutText:SetWidth(440)
        dialog.payoutText:SetJustifyH("LEFT")
        
        -- Close button
        dialog.closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.closeButton:SetSize(100, 25)
        dialog.closeButton:SetPoint("BOTTOM", dialog, "BOTTOM", 0, 15)
        dialog.closeButton:SetText("Close")
        dialog.closeButton:SetScript("OnClick", function()
            dialog:Hide()
        end)
        
        dialog.CloseButton:SetScript("OnClick", function()
            dialog:Hide()
        end)
        
        self.payoutDialog = dialog
    end
    
    -- Set bet info
    self.payoutDialog.betTitle:SetText(COLOR_YELLOW .. bet.title .. COLOR_RESET)
    
    local payoutInfo = ""
    
    if bet.status == "cancelled" then
        -- Cancelled bet - return all money
        self.payoutDialog.resultText:SetText(COLOR_YELLOW .. "BET CANCELLED - Return All Gold" .. COLOR_RESET)
        
        payoutInfo = COLOR_ORANGE .. "Return the following amounts to each participant:\n\n" .. COLOR_RESET
        
        if next(bet.participants) then
            local sortedParticipants = {}
            for playerName, participation in pairs(bet.participants) do
                table.insert(sortedParticipants, {name = playerName, amount = participation.amount, option = participation.option})
            end
            table.sort(sortedParticipants, function(a, b) return a.amount > b.amount end)
            
            for _, p in ipairs(sortedParticipants) do
                local baseName = GetPlayerBaseName(p.name)
                payoutInfo = payoutInfo .. COLOR_GREEN .. baseName .. COLOR_RESET .. "\n"
                payoutInfo = payoutInfo .. "  Return: " .. COLOR_YELLOW .. p.amount .. "g" .. COLOR_RESET .. " (originally bet on " .. p.option .. ")\n\n"
            end
        else
            payoutInfo = COLOR_GRAY .. "No participants to refund." .. COLOR_RESET
        end
        
    elseif bet.status == "resolved" and winningOption then
        -- Resolved bet - calculate payouts
        self.payoutDialog.resultText:SetText(COLOR_GREEN .. winningOption .. " WINS!" .. COLOR_RESET)
        
        -- Calculate winners
        local totalWinningBets = 0
        local winners = {}
        local losers = {}
        
        for playerName, participation in pairs(bet.participants) do
            if participation.option == winningOption then
                totalWinningBets = totalWinningBets + participation.amount
                table.insert(winners, {name = playerName, amount = participation.amount})
            else
                table.insert(losers, {name = playerName, amount = participation.amount, option = participation.option})
            end
        end
        
        if totalWinningBets == 0 then
            -- No winners - return all bets
            payoutInfo = COLOR_ORANGE .. "No winners! Return all gold:\n\n" .. COLOR_RESET
            
            for _, p in ipairs(losers) do
                local baseName = GetPlayerBaseName(p.name)
                payoutInfo = payoutInfo .. COLOR_GREEN .. baseName .. COLOR_RESET .. "\n"
                payoutInfo = payoutInfo .. "  Return: " .. COLOR_YELLOW .. p.amount .. "g" .. COLOR_RESET .. "\n\n"
            end
        else
            -- Winners get payouts
            table.sort(winners, function(a, b) return a.amount > b.amount end)
            
            payoutInfo = COLOR_GREEN .. "WINNERS - Pay Out:\n\n" .. COLOR_RESET
            
            for _, winner in ipairs(winners) do
                local share = math.floor((winner.amount / totalWinningBets) * bet.totalPot)
                local profit = share - winner.amount
                local baseName = GetPlayerBaseName(winner.name)
                
                payoutInfo = payoutInfo .. COLOR_GREEN .. baseName .. COLOR_RESET .. "\n"
                payoutInfo = payoutInfo .. "  Bet: " .. winner.amount .. "g\n"
                payoutInfo = payoutInfo .. "  Payout: " .. COLOR_YELLOW .. share .. "g" .. COLOR_RESET
                
                if profit > 0 then
                    payoutInfo = payoutInfo .. " (" .. COLOR_GREEN .. "+" .. profit .. "g profit" .. COLOR_RESET .. ")"
                elseif profit < 0 then
                    payoutInfo = payoutInfo .. " (" .. COLOR_RED .. profit .. "g loss" .. COLOR_RESET .. ")"
                end
                
                payoutInfo = payoutInfo .. "\n\n"
            end
            
            -- Show losers (no payout)
            if #losers > 0 then
                table.sort(losers, function(a, b) return a.amount > b.amount end)
                payoutInfo = payoutInfo .. "\n" .. COLOR_RED .. "LOSERS - No Payout:\n\n" .. COLOR_RESET
                
                for _, loser in ipairs(losers) do
                    local baseName = GetPlayerBaseName(loser.name)
                    payoutInfo = payoutInfo .. COLOR_GRAY .. baseName .. COLOR_RESET .. " (lost " .. loser.amount .. "g on " .. loser.option .. ")\n"
                end
            end
        end
    end
    
    self.payoutDialog.payoutText:SetText(payoutInfo)
    
    -- Update scroll content height
    local textHeight = self.payoutDialog.payoutText:GetStringHeight()
    self.payoutDialog.scrollContent:SetHeight(math.max(textHeight + 20, 300))
    
    self.payoutDialog:Show()
end

-- Show bet inspect dialog
function FuldStonks:ShowBetInspectDialog(betId)
    -- Check both active bets and history
    local bet = FuldStonksDB.activeBets[betId] or FuldStonksDB.betHistory[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Bet not found!")
        return
    end
    
    -- Create dialog if it doesn't exist
    if not self.inspectDialog then
        local dialog = CreateFrame("Frame", "FuldStonksInspectDialog", UIParent, "BasicFrameTemplateWithInset")
        dialog:SetSize(700, 560)
        dialog:SetPoint("CENTER")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetFrameStrata("DIALOG")
        dialog:Hide()
        
        dialog.title = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.title:SetPoint("TOP", dialog.TitleBg, "TOP", 0, -3)
        dialog.title:SetText("Inspect Bet")
        
        dialog.betTitle = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.betTitle:SetPoint("TOP", dialog, "TOP", 0, -35)
        dialog.betTitle:SetWidth(660)
        dialog.betTitle:SetJustifyH("CENTER")
        
        -- Info section
        dialog.infoText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.infoText:SetPoint("TOP", dialog.betTitle, "BOTTOM", 0, -10)
        dialog.infoText:SetWidth(660)
        dialog.infoText:SetJustifyH("CENTER")

        -- Money flow graph (confirmed + pending)
        dialog.graphFrame = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
        dialog.graphFrame:SetPoint("TOPLEFT", dialog.infoText, "BOTTOMLEFT", 10, -10)
        dialog.graphFrame:SetPoint("TOPRIGHT", dialog.infoText, "BOTTOMRIGHT", -10, -10)
        dialog.graphFrame:SetHeight(120)

        dialog.graphTitle = dialog.graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.graphTitle:SetPoint("TOP", dialog.graphFrame, "TOP", 0, -8)
        dialog.graphTitle:SetText("MONEY FLOW")

        dialog.graphSummary = dialog.graphFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dialog.graphSummary:SetPoint("BOTTOM", dialog.graphFrame, "BOTTOM", 0, 8)
        dialog.graphSummary:SetTextColor(0.75, 0.75, 0.75)

        dialog.graphRows = {}
        dialog.GetGraphRow = function(self, index)
            if self.graphRows[index] then
                return self.graphRows[index]
            end

            local row = CreateFrame("Frame", nil, self.graphFrame)
            row:SetSize(620, 18)
            row:SetPoint("TOPLEFT", self.graphFrame, "TOPLEFT", 10, -28 - ((index - 1) * 20))

            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.label:SetWidth(90)
            row.label:SetJustifyH("LEFT")

            row.barContainer = CreateFrame("Frame", nil, row)
            row.barContainer:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
            row.barContainer:SetSize(320, 12)

            row.barBg = row.barContainer:CreateTexture(nil, "BACKGROUND")
            row.barBg:SetAllPoints(row.barContainer)
            row.barBg:SetColorTexture(0.18, 0.18, 0.18, 0.9)

            row.barFill = row.barContainer:CreateTexture(nil, "ARTWORK")
            row.barFill:SetPoint("LEFT", row.barContainer, "LEFT", 0, 0)
            row.barFill:SetHeight(12)
            row.barFill:SetColorTexture(0.4, 0.4, 0.4, 0.95)

            row.value = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.value:SetPoint("LEFT", row.barContainer, "RIGHT", 8, 0)
            row.value:SetWidth(190)
            row.value:SetJustifyH("LEFT")

            self.graphRows[index] = row
            return row
        end
        
        -- Two columns (Yes and No) with larger readable area
        dialog.yesFrame = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
        dialog.yesFrame:SetPoint("TOPLEFT", dialog.graphFrame, "BOTTOMLEFT", 0, -10)
        dialog.yesFrame:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 20, 50)
        dialog.yesFrame:SetWidth(320)
        
        dialog.yesTitle = dialog.yesFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.yesTitle:SetPoint("TOP", dialog.yesFrame, "TOP", 0, -8)
        dialog.yesTitle:SetText(COLOR_GREEN .. "YES" .. COLOR_RESET)
        
        dialog.yesScroll = CreateFrame("ScrollFrame", nil, dialog.yesFrame, "UIPanelScrollFrameTemplate")
        dialog.yesScroll:SetPoint("TOPLEFT", dialog.yesFrame, "TOPLEFT", 8, -30)
        dialog.yesScroll:SetPoint("BOTTOMRIGHT", dialog.yesFrame, "BOTTOMRIGHT", -28, 32)
        
        dialog.yesContent = CreateFrame("Frame", nil, dialog.yesScroll)
        dialog.yesContent:SetSize(230, 1)
        dialog.yesScroll:SetScrollChild(dialog.yesContent)
        
        dialog.yesText = dialog.yesContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.yesText:SetPoint("TOPLEFT", dialog.yesContent, "TOPLEFT", 0, 0)
        dialog.yesText:SetWidth(230)
        dialog.yesText:SetJustifyH("LEFT")
        
        dialog.noFrame = CreateFrame("Frame", nil, dialog, "InsetFrameTemplate")
        dialog.noFrame:SetPoint("TOPRIGHT", dialog.graphFrame, "BOTTOMRIGHT", 0, -10)
        dialog.noFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -20, 50)
        dialog.noFrame:SetWidth(320)
        
        dialog.noTitle = dialog.noFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        dialog.noTitle:SetPoint("TOP", dialog.noFrame, "TOP", 0, -8)
        dialog.noTitle:SetText(COLOR_RED .. "NO" .. COLOR_RESET)
        
        dialog.noScroll = CreateFrame("ScrollFrame", nil, dialog.noFrame, "UIPanelScrollFrameTemplate")
        dialog.noScroll:SetPoint("TOPLEFT", dialog.noFrame, "TOPLEFT", 8, -30)
        dialog.noScroll:SetPoint("BOTTOMRIGHT", dialog.noFrame, "BOTTOMRIGHT", -28, 32)
        
        dialog.noContent = CreateFrame("Frame", nil, dialog.noScroll)
        dialog.noContent:SetSize(230, 1)
        dialog.noScroll:SetScrollChild(dialog.noContent)
        
        dialog.noText = dialog.noContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.noText:SetPoint("TOPLEFT", dialog.noContent, "TOPLEFT", 0, 0)
        dialog.noText:SetWidth(230)
        dialog.noText:SetJustifyH("LEFT")
        
        -- Resolution buttons (shown only if bet creator)
        dialog.yesWinsButton = CreateFrame("Button", nil, dialog.yesFrame, "UIPanelButtonTemplate")
        dialog.yesWinsButton:SetSize(80, 22)
        dialog.yesWinsButton:SetPoint("BOTTOM", dialog.yesFrame, "BOTTOM", 0, 8)
        dialog.yesWinsButton:SetText("YES Wins")
        dialog.yesWinsButton:SetScript("OnClick", function()
            if dialog.currentBetId then
                FuldStonks:ResolveBet(dialog.currentBetId, "Yes")
                dialog:Hide()
            end
        end)
        
        dialog.noWinsButton = CreateFrame("Button", nil, dialog.noFrame, "UIPanelButtonTemplate")
        dialog.noWinsButton:SetSize(80, 22)
        dialog.noWinsButton:SetPoint("BOTTOM", dialog.noFrame, "BOTTOM", 0, 8)
        dialog.noWinsButton:SetText("NO Wins")
        dialog.noWinsButton:SetScript("OnClick", function()
            if dialog.currentBetId then
                FuldStonks:ResolveBet(dialog.currentBetId, "No")
                dialog:Hide()
            end
        end)
        
        -- Cancel bet button (shown only if bet creator)
        dialog.cancelBetButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.cancelBetButton:SetSize(100, 25)
        dialog.cancelBetButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -122, 12)
        dialog.cancelBetButton:SetText("Cancel Bet")
        dialog.cancelBetButton:SetScript("OnClick", function()
            if dialog.currentBetId then
                StaticPopup_Show("FULDSTONKS_CONFIRM_CANCEL", nil, nil, dialog.currentBetId)
            end
        end)

        -- Attached side window for owner moderation tools (left side)
        local ownerDialog = CreateFrame("Frame", "FuldStonksInspectOwnerDialog", UIParent, "BasicFrameTemplateWithInset")
        ownerDialog:SetSize(340, 220)
        ownerDialog:SetPoint("TOPRIGHT", dialog, "TOPLEFT", -8, 0)
        ownerDialog:SetFrameStrata("DIALOG")
        ownerDialog:Hide()

        ownerDialog.title = ownerDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        ownerDialog.title:SetPoint("TOP", ownerDialog.TitleBg, "TOP", 0, -3)
        ownerDialog.title:SetText("Owner Tools")

        dialog.modLabel = ownerDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dialog.modLabel:SetPoint("TOPLEFT", ownerDialog, "TOPLEFT", 16, -40)
        dialog.modLabel:SetText("Player name:")
        dialog.modLabel:SetTextColor(0.85, 0.85, 0.85)

        dialog.modTargetInput = CreateFrame("EditBox", nil, ownerDialog, "InputBoxTemplate")
        dialog.modTargetInput:SetSize(190, 20)
        dialog.modTargetInput:SetPoint("TOPLEFT", dialog.modLabel, "BOTTOMLEFT", 0, -8)
        dialog.modTargetInput:SetAutoFocus(false)
        dialog.modTargetInput:SetMaxLetters(32)

        dialog.removeBetButton = CreateFrame("Button", nil, ownerDialog, "UIPanelButtonTemplate")
        dialog.removeBetButton:SetSize(140, 24)
        dialog.removeBetButton:SetPoint("TOPLEFT", dialog.modTargetInput, "BOTTOMLEFT", 0, -14)
        dialog.removeBetButton:SetText("Remove Confirmed Bet")
        dialog.removeBetButton:SetScript("OnClick", function()
            if dialog.currentBetId then
                FuldStonks:CancelUserBet(dialog.currentBetId, dialog.modTargetInput:GetText(), false)
                dialog.modTargetInput:SetText("")
            end
        end)

        dialog.removePendingButton = CreateFrame("Button", nil, ownerDialog, "UIPanelButtonTemplate")
        dialog.removePendingButton:SetSize(140, 24)
        dialog.removePendingButton:SetPoint("TOPLEFT", dialog.removeBetButton, "BOTTOMLEFT", 0, -8)
        dialog.removePendingButton:SetText("Remove Pending Bet")
        dialog.removePendingButton:SetScript("OnClick", function()
            if dialog.currentBetId then
                FuldStonks:CancelUserBet(dialog.currentBetId, dialog.modTargetInput:GetText(), true)
                dialog.modTargetInput:SetText("")
            end
        end)

        ownerDialog.helpText = ownerDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ownerDialog.helpText:SetPoint("BOTTOMLEFT", ownerDialog, "BOTTOMLEFT", 16, 16)
        ownerDialog.helpText:SetWidth(300)
        ownerDialog.helpText:SetJustifyH("LEFT")
        ownerDialog.helpText:SetTextColor(0.75, 0.75, 0.75)
        ownerDialog.helpText:SetText("Use name or name-realm.")

        ownerDialog.CloseButton:SetScript("OnClick", function()
            ownerDialog:Hide()
        end)
        
        -- Close button
        dialog.closeButton = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.closeButton:SetSize(100, 25)
        dialog.closeButton:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -12, 12)
        dialog.closeButton:SetText("Close")
        dialog.closeButton:SetScript("OnClick", function()
            dialog:Hide()
        end)
        
        dialog.CloseButton:SetScript("OnClick", function()
            dialog:Hide()
        end)

        -- Attached side window for pending bets
        local pendingDialog = CreateFrame("Frame", "FuldStonksInspectPendingDialog", UIParent, "BasicFrameTemplateWithInset")
        pendingDialog:SetSize(340, 560)
        pendingDialog:SetPoint("TOPLEFT", dialog, "TOPRIGHT", 8, 0)
        pendingDialog:SetFrameStrata("DIALOG")
        pendingDialog:Hide()

        pendingDialog.title = pendingDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        pendingDialog.title:SetPoint("TOP", pendingDialog.TitleBg, "TOP", 0, -3)
        pendingDialog.title:SetText("Pending Bets")

        pendingDialog.summary = pendingDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        pendingDialog.summary:SetPoint("TOP", pendingDialog, "TOP", 0, -35)
        pendingDialog.summary:SetWidth(300)
        pendingDialog.summary:SetJustifyH("CENTER")
        pendingDialog.summary:SetTextColor(0.8, 0.8, 0.8)

        pendingDialog.scroll = CreateFrame("ScrollFrame", nil, pendingDialog, "UIPanelScrollFrameTemplate")
        pendingDialog.scroll:SetPoint("TOPLEFT", pendingDialog, "TOPLEFT", 12, -60)
        pendingDialog.scroll:SetPoint("BOTTOMRIGHT", pendingDialog, "BOTTOMRIGHT", -30, 40)

        pendingDialog.content = CreateFrame("Frame", nil, pendingDialog.scroll)
        pendingDialog.content:SetSize(280, 1)
        pendingDialog.scroll:SetScrollChild(pendingDialog.content)

        pendingDialog.text = pendingDialog.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        pendingDialog.text:SetPoint("TOPLEFT", pendingDialog.content, "TOPLEFT", 0, 0)
        pendingDialog.text:SetWidth(280)
        pendingDialog.text:SetJustifyH("LEFT")

        pendingDialog.closeButton = CreateFrame("Button", nil, pendingDialog, "UIPanelButtonTemplate")
        pendingDialog.closeButton:SetSize(100, 24)
        pendingDialog.closeButton:SetPoint("BOTTOM", pendingDialog, "BOTTOM", 0, 12)
        pendingDialog.closeButton:SetText("Close")
        pendingDialog.closeButton:SetScript("OnClick", function()
            pendingDialog:Hide()
        end)

        pendingDialog.CloseButton:SetScript("OnClick", function()
            pendingDialog:Hide()
        end)

        dialog:SetScript("OnHide", function()
            if FuldStonks.inspectPendingDialog then
                FuldStonks.inspectPendingDialog:Hide()
            end
            if FuldStonks.inspectOwnerDialog then
                FuldStonks.inspectOwnerDialog:Hide()
            end
        end)

        self.inspectOwnerDialog = ownerDialog
        self.inspectPendingDialog = pendingDialog
        
        self.inspectDialog = dialog
    end
    
    -- Set bet info
    self.inspectDialog.betTitle:SetText(COLOR_YELLOW .. bet.title .. COLOR_RESET)
    self.inspectDialog.currentBetId = betId
    
    local infoText = "Total Pot: " .. COLOR_GREEN .. bet.totalPot .. "g" .. COLOR_RESET .. " (confirmed only) • Created by: " .. GetPlayerBaseName(bet.createdBy)
    self.inspectDialog.infoText:SetText(infoText)
    
    -- Show/hide resolution buttons based on whether player is bet creator
    local isCreator = (bet.createdBy == playerFullName)
    self.inspectDialog.yesWinsButton:SetShown(isCreator)
    self.inspectDialog.noWinsButton:SetShown(isCreator)
    self.inspectDialog.cancelBetButton:SetShown(isCreator)
    self.inspectDialog.modLabel:SetShown(isCreator)
    self.inspectDialog.modTargetInput:SetShown(isCreator)
    self.inspectDialog.removeBetButton:SetShown(isCreator)
    self.inspectDialog.removePendingButton:SetShown(isCreator)
    if self.inspectOwnerDialog then
        self.inspectOwnerDialog:SetShown(isCreator)
    end
    
    -- Group participants by option
    local optionGroups = {}
    for playerName, participation in pairs(bet.participants) do
        if not optionGroups[participation.option] then
            optionGroups[participation.option] = {}
        end
        table.insert(optionGroups[participation.option], {name = playerName, amount = participation.amount})
    end
    
    -- Sort participants within each group by amount (highest first)
    for option, group in pairs(optionGroups) do
        table.sort(group, function(a, b) return a.amount > b.amount end)
    end

    -- Build graph data (money + bet counts + pending)
    local optionTotals = {}
    local optionCounts = {}
    for _, option in ipairs(bet.options or {}) do
        optionTotals[option] = 0
        optionCounts[option] = 0
    end

    for _, participation in pairs(bet.participants or {}) do
        local opt = participation.option or "Other"
        optionTotals[opt] = (optionTotals[opt] or 0) + (participation.amount or 0)
        optionCounts[opt] = (optionCounts[opt] or 0) + 1
    end

    local pendingTotal = 0
    local pendingCount = 0
    for _, pendingBet in pairs(self.pendingBets) do
        if pendingBet.betId == betId then
            pendingTotal = pendingTotal + (pendingBet.amount or 0)
            pendingCount = pendingCount + 1
        end
    end

    local graphRowsData = {}
    for _, option in ipairs(bet.options or {}) do
        local color = {0.8, 0.8, 0.3}
        if option == "Yes" then
            color = {0.2, 0.85, 0.2}
        elseif option == "No" then
            color = {0.9, 0.2, 0.2}
        end

        table.insert(graphRowsData, {
            label = option,
            amount = optionTotals[option] or 0,
            count = optionCounts[option] or 0,
            color = color
        })
    end

    table.insert(graphRowsData, {
        label = "Pending",
        amount = pendingTotal,
        count = pendingCount,
        color = {1.0, 0.55, 0.15}
    })

    local totalFlow = (bet.totalPot or 0) + pendingTotal
    local flowBase = math.max(totalFlow, 1)

    for i, rowData in ipairs(graphRowsData) do
        local row = self.inspectDialog:GetGraphRow(i)
        local amount = rowData.amount or 0
        local count = rowData.count or 0
        local pct = 0
        if totalFlow > 0 then
            pct = math.floor((amount / totalFlow) * 100 + 0.5)
        end

        row.label:SetText(rowData.label)
        row.value:SetText(amount .. "g • " .. count .. " bets (" .. pct .. "%)")

        local fillWidth = 0
        if amount > 0 then
            fillWidth = math.floor((amount / flowBase) * row.barContainer:GetWidth())
            if fillWidth < 2 then
                fillWidth = 2
            end
        end
        row.barFill:SetWidth(fillWidth)
        row.barFill:SetColorTexture(rowData.color[1], rowData.color[2], rowData.color[3], 0.95)
        row:Show()
    end

    for i = #graphRowsData + 1, #self.inspectDialog.graphRows do
        self.inspectDialog.graphRows[i]:Hide()
    end

    self.inspectDialog.graphSummary:SetText(
        "Confirmed: " .. (bet.totalPot or 0) .. "g • Pending: " .. pendingTotal .. "g • Total Flow: " .. totalFlow .. "g"
    )
    
    -- Build Yes section
    local yesGroup = optionGroups["Yes"] or {}
    local yesTotalBets = 0
    for _, p in ipairs(yesGroup) do
        yesTotalBets = yesTotalBets + p.amount
    end
    
    local yesInfo = #yesGroup .. " bets • " .. COLOR_GREEN .. yesTotalBets .. "g" .. COLOR_RESET
    if yesTotalBets > 0 and bet.totalPot > 0 then
        local percentage = math.floor((yesTotalBets / bet.totalPot) * 100)
        yesInfo = yesInfo .. " (" .. percentage .. "%)"
    end
    yesInfo = yesInfo .. "\n\n"
    
    if #yesGroup > 0 then
        for _, p in ipairs(yesGroup) do
            local baseName = GetPlayerBaseName(p.name)
            if bet.totalPot > 0 then
                local percentage = math.floor((p.amount / bet.totalPot) * 100)
                yesInfo = yesInfo .. baseName .. "\n" .. COLOR_GREEN .. p.amount .. "g" .. COLOR_RESET .. " (" .. percentage .. "%)\n\n"
            else
                yesInfo = yesInfo .. baseName .. "\n" .. COLOR_GREEN .. p.amount .. "g" .. COLOR_RESET .. "\n\n"
            end
        end
    else
        yesInfo = yesInfo .. COLOR_GRAY .. "No bets placed" .. COLOR_RESET .. "\n"
    end
    
    self.inspectDialog.yesText:SetText(yesInfo)
    local yesHeight = self.inspectDialog.yesText:GetStringHeight()
    self.inspectDialog.yesContent:SetHeight(math.max(yesHeight + 20, 100))
    
    -- Build No section
    local noGroup = optionGroups["No"] or {}
    local noTotalBets = 0
    for _, p in ipairs(noGroup) do
        noTotalBets = noTotalBets + p.amount
    end
    
    local noInfo = #noGroup .. " bets • " .. COLOR_RED .. noTotalBets .. "g" .. COLOR_RESET
    if noTotalBets > 0 and bet.totalPot > 0 then
        local percentage = math.floor((noTotalBets / bet.totalPot) * 100)
        noInfo = noInfo .. " (" .. percentage .. "%)"
    end
    noInfo = noInfo .. "\n\n"
    
    if #noGroup > 0 then
        for _, p in ipairs(noGroup) do
            local baseName = GetPlayerBaseName(p.name)
            if bet.totalPot > 0 then
                local percentage = math.floor((p.amount / bet.totalPot) * 100)
                noInfo = noInfo .. baseName .. "\n" .. COLOR_RED .. p.amount .. "g" .. COLOR_RESET .. " (" .. percentage .. "%)\n\n"
            else
                noInfo = noInfo .. baseName .. "\n" .. COLOR_RED .. p.amount .. "g" .. COLOR_RESET .. "\n\n"
            end
        end
    else
        noInfo = noInfo .. COLOR_GRAY .. "No bets placed" .. COLOR_RESET .. "\n"
    end
    
    self.inspectDialog.noText:SetText(noInfo)
    local noHeight = self.inspectDialog.noText:GetStringHeight()
    self.inspectDialog.noContent:SetHeight(math.max(noHeight + 20, 100))
    
    -- Build pending bets section (in attached side window)
    local pendingInfo = ""
    local hasPendingBets = false
    
    for playerName, pendingBet in pairs(self.pendingBets) do
        if pendingBet.betId == betId then
            hasPendingBets = true
            local baseName = GetPlayerBaseName(playerName)
            local optionColor = pendingBet.option == "Yes" and COLOR_GREEN or COLOR_RED
            pendingInfo = pendingInfo .. COLOR_ORANGE .. "⏳" .. COLOR_RESET .. " " .. baseName .. " • " .. optionColor .. pendingBet.option .. COLOR_RESET .. " • " .. pendingBet.amount .. "g • " .. COLOR_ORANGE .. "Awaiting trade" .. COLOR_RESET .. "\n\n"
        end
    end
    
    if not hasPendingBets then
        if bet.totalPot == 0 then
            pendingInfo = COLOR_GRAY .. "No bets or pending bets yet" .. COLOR_RESET
        else
            pendingInfo = COLOR_GRAY .. "No pending bets" .. COLOR_RESET
        end
    end

    if self.inspectPendingDialog then
        self.inspectPendingDialog.summary:SetText(
            COLOR_ORANGE .. pendingCount .. COLOR_RESET .. " pending entries • " .. COLOR_ORANGE .. pendingTotal .. "g" .. COLOR_RESET
        )
        self.inspectPendingDialog.text:SetText(pendingInfo)
        local pendingHeight = self.inspectPendingDialog.text:GetStringHeight()
        self.inspectPendingDialog.content:SetHeight(math.max(pendingHeight + 20, 420))
        self.inspectPendingDialog:Show()
    end

    self.inspectDialog:Show()
end

-- Slash command handler
local function SlashCommandHandler(msg)
    msg = msg or ""
    local command = strtrim(msg:lower())
    
    if command == "" then
        -- Default: toggle UI
        print("DEBUG: Empty command, calling ToggleMainFrame")
        local success, err = pcall(function() FuldStonks.ToggleMainFrame() end)
        if not success then
            print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: " .. tostring(err))
        end
    elseif command == "help" then
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Commands:")
        print("  /FuldStonks or /fs - Toggle main UI")
        print("  /FuldStonks help - Show this help message")
        print("  /FuldStonks version - Show addon version")
        print("  /FuldStonks sync - Request sync from guild/group")
        print("  /FuldStonks peers - Show connected peers")
        print("  /FuldStonks debug - Toggle debug mode")
        print("  /FuldStonks create - Create a new bet")
        print("  /FuldStonks pending - Show pending bets (bet creator only)")
        print("  /FuldStonks cancel - Cancel your pending bet")
        print("  /FuldStonks resolve - Resolve a bet you created")
        print("  /FuldStonks showhidden - Show list of hidden bets")
        print("  /FuldStonks unhideall - Unhide all hidden bets")
    elseif command == "version" then
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " version " .. FuldStonks.version)
    elseif command == "sync" then
        FuldStonks:RequestSync()
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Requesting sync from guild/group...")
    elseif command == "peers" then
        local count = 0
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Connected peers:")
        for name, data in pairs(FuldStonks.peers) do
            local timeSince = math.floor(GetTime() - data.lastSeen)
            local baseName = GetPlayerBaseName(name)
            print("  " .. baseName .. " (seen " .. timeSince .. "s ago)")
            count = count + 1
        end
        if count == 0 then
            print("  No peers connected yet.")
        end
    elseif command == "debug" then
        FuldStonksDB.debug = not FuldStonksDB.debug
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Debug mode: " .. (FuldStonksDB.debug and "ON" or "OFF"))
    elseif command == "create" then
        -- Show bet creation dialog
        FuldStonks:ShowBetCreationDialog()
    elseif command == "cancel" then
        -- Cancel pending bet
        FuldStonks:CancelPendingBet()
    elseif command == "resolve" then
        -- Show bet resolution dialog
        FuldStonks:ShowBetResolutionDialog()
    elseif command == "pending" then
        -- Show pending bets (bet creator only)
        local count = 0
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Pending bets awaiting trade:")
        for playerName, pendingBet in pairs(FuldStonks.pendingBets) do
            local bet = FuldStonksDB.activeBets[pendingBet.betId]
            if bet then
                local baseName = GetPlayerBaseName(playerName)
                local timeAgo = math.floor(GetTime() - pendingBet.timestamp)
                print("  " .. baseName .. ": " .. pendingBet.amount .. "g on " .. COLOR_YELLOW .. pendingBet.option .. COLOR_RESET .. " (" .. timeAgo .. "s ago)")
                print("    Bet: " .. bet.title)
                count = count + 1
            end
        end
        if count == 0 then
            print("  No pending bets.")
        end
    elseif command == "showhidden" then
        FuldStonks:ShowHiddenBets()
    elseif command == "unhideall" then
        FuldStonks:UnhideAllBets()
    elseif command:sub(1, 7) == "delete " then
        -- Master delete command: /fs delete <betId> <password>
        local args = {strsplit(" ", command)}
        if args[2] and args[3] then
            FuldStonks:MasterDelete(args[2], args[3])
        else
            print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Usage: /fs delete <betId> <password>")
        end
    else
        -- Default: toggle UI (shouldn't normally reach here if command is empty)
        local success, err = pcall(function() FuldStonks.ToggleMainFrame() end)
        if not success then
            print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: " .. tostring(err))
        end
    end
end

-- Register slash commands
SLASH_FULDSTONKS1 = "/FuldStonks"
SLASH_FULDSTONKS2 = "/fs"
SlashCmdList["FULDSTONKS"] = SlashCommandHandler

-- ============================================
-- ADDON MESSAGE COMMUNICATION
-- ============================================

-- Addon message prefix for communication between players
local MESSAGE_PREFIX = "FuldStonks"

-- Message types (State-based sync model)
local MSG_STATE_SYNC = "STATESYNC"  -- Full state broadcast (sent every 5s)
local MSG_SYNC_REQUEST = "SYNCREQ"  -- Request full state sync on demand
local MSG_BET_PENDING = "BETPND"    -- Pending bet notification (sent to bet creator immediately)
local MSG_BET_PENDING_CANCEL = "BETPNDCNL"  -- Pending bet cancellation (sent to bet creator immediately)
local MSG_BET_PENDING_REJECT = "BETPNDRJ"  -- Pending bet rejected by bet creator
local MSG_BET_CONFIRMED = "BETCNF"  -- Confirmed bet update for immediate UI refresh

-- Determine the best channel to send messages
local function GetBroadcastChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    else
        return "GUILD"
    end
end

-- Serialize data for transmission (use ASCII control character as delimiter)
local DELIMITER = "\001"  -- ASCII SOH (Start of Heading) - safe delimiter

local function SerializeMessage(msgType, ...)
    -- Format: msgType|version|arg1|arg2|...
    local parts = {msgType, FuldStonks.version}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        table.insert(parts, tostring(v))
    end
    return table.concat(parts, DELIMITER)
end

-- Deserialize received message
local function DeserializeMessage(message)
    local parts = {strsplit(DELIMITER, message)}
    local msgType = parts[1]
    local senderVersion = parts[2]
    -- Use unpack starting from index 3 to skip msgType and version
    return msgType, senderVersion, unpack(parts, 3)
end

-- ============================================
-- STATE SYNCHRONIZATION SYSTEM
-- ============================================

-- Increment Lamport clock for state versioning
local function IncrementStateVersion()
    FuldStonksDB.stateVersion = FuldStonksDB.stateVersion + 1
    return FuldStonksDB.stateVersion
end

-- Update Lamport clock when receiving a message
local function UpdateStateVersion(receivedVersion)
    local currentVersion = FuldStonksDB.stateVersion
    FuldStonksDB.stateVersion = math.max(currentVersion, receivedVersion) + 1
    LogIfChanged("v" .. FuldStonksDB.stateVersion, true, "STATE")
end

-- Serialize a single bet for transmission
local function SerializeBetForSync(bet)
    -- Format: id^title^betType^options^createdBy^timestamp^status^totalPot^stateVersion
    local options = table.concat(bet.options, ",")
    local parts = {
        bet.id,
        bet.title,
        bet.betType,
        options,
        bet.createdBy,
        tostring(bet.timestamp),
        bet.status or "active",
        tostring(bet.totalPot or 0),
        tostring(bet.stateVersion or 0)
    }
    return table.concat(parts, "^")
end

-- Deserialize a bet from sync message
local function DeserializeBetFromSync(betString)
    local parts = {strsplit("^", betString)}
    if #parts < 9 then 
        DebugPrint("Invalid bet string, not enough parts: " .. #parts)
        return nil 
    end
    
    local bet = {
        id = parts[1],
        title = parts[2],
        betType = parts[3],
        options = {strsplit(",", parts[4])},
        createdBy = parts[5],
        timestamp = tonumber(parts[6]) or 0,
        status = parts[7],
        totalPot = tonumber(parts[8]) or 0,
        stateVersion = tonumber(parts[9]) or 0,
        participants = {},
        pendingTrades = {}
    }
    return bet
end

-- Serialize a participant entry
local function SerializeParticipant(playerName, participation)
    -- Format: playerName~option~amount~confirmed~timestamp
    return playerName .. "~" .. participation.option .. "~" .. tostring(participation.amount) .. "~" .. 
           tostring(participation.confirmed or true) .. "~" .. tostring(participation.timestamp or GetTime())
end

-- Deserialize a participant entry
local function DeserializeParticipant(participantString)
    local parts = {strsplit("~", participantString)}
    if #parts < 5 then return nil end
    
    return parts[1], {
        option = parts[2],
        amount = tonumber(parts[3]) or 0,
        confirmed = (parts[4] == "true"),
        timestamp = tonumber(parts[5]) or 0
    }
end

-- Refresh inspect dialogs if currently open
local function RefreshOpenInspectDialog()
    if not FuldStonks.inspectDialog then
        return
    end
    
    if not FuldStonks.inspectDialog:IsShown() then
        return
    end

    local currentBetId = FuldStonks.inspectDialog.currentBetId
    if not currentBetId then
        return
    end

    if FuldStonksDB.activeBets[currentBetId] or FuldStonksDB.betHistory[currentBetId] then
        FuldStonks:ShowBetInspectDialog(currentBetId)
    else
        FuldStonks.inspectDialog:Hide()
    end
end

-- Create a snapshot of current addon state
function FuldStonks:CreateStateSnapshot()
    local snapshot = {
        version = FuldStonksDB.stateVersion or 0,
        nonce = (FuldStonksDB.syncNonce or 0) + 1,
        timestamp = GetTime(),
        bets = {},
        participants = {},  -- Separate participant data
        history = {}  -- Include resolved bets for statistics sync
    }
    
    FuldStonksDB.syncNonce = snapshot.nonce
    
    -- Collect all active bets
    for betId, bet in pairs(FuldStonksDB.activeBets) do
        if bet.status == "active" then
            table.insert(snapshot.bets, {
                id = betId,
                data = SerializeBetForSync(bet)
            })
            
            -- Collect participants for this bet
            for playerName, participation in pairs(bet.participants or {}) do
                table.insert(snapshot.participants, {
                    betId = betId,
                    data = SerializeParticipant(playerName, participation)
                })
            end
        end
    end
    
    -- Include recent resolved bets for statistics (last 50 for bandwidth)
    local historyCount = 0
    for betId, bet in pairs(FuldStonksDB.betHistory) do
        if historyCount < 50 then
            table.insert(snapshot.history, {
                id = betId,
                status = bet.status,
                winningOption = bet.winningOption,
                participants = bet.participants or {}
            })
            historyCount = historyCount + 1
        end
    end
    
    return snapshot
end

-- Broadcast full state sync
function FuldStonks:BroadcastStateSync()
    local snapshot = self:CreateStateSnapshot()
    
    -- Build a state signature to check for changes
    local stateSignature = snapshot.version .. "|" .. #snapshot.bets .. "|" .. #snapshot.participants
    
    -- Skip if nothing changed since last broadcast
    if self.lastBroadcastState == stateSignature then
        return
    end
    self.lastBroadcastState = stateSignature

    -- Build a sendable payload first so header counts match what is actually sent.
    -- Otherwise receivers can wait forever for chunks that were skipped.
    local sendableBets = {}
    local sendableBetIds = {}
    for _, betData in ipairs(snapshot.bets) do
        local preview = SerializeMessage(MSG_STATE_SYNC, SYNC_TYPE_BET, snapshot.nonce, 1, betData.id, betData.data)
        if #preview <= 255 then
            table.insert(sendableBets, betData)
            sendableBetIds[betData.id] = true
        end
    end

    local sendableParticipants = {}
    for _, participantData in ipairs(snapshot.participants) do
        if sendableBetIds[participantData.betId] then
            local preview = SerializeMessage(MSG_STATE_SYNC, SYNC_TYPE_PARTICIPANT, snapshot.nonce, 1, participantData.betId, participantData.data)
            if #preview <= 255 then
                table.insert(sendableParticipants, participantData)
            end
        end
    end

    -- Send header with the exact chunk counts we will send.
    local header = SerializeMessage(MSG_STATE_SYNC, SYNC_TYPE_HEADER, snapshot.version, snapshot.nonce, #sendableBets, #sendableParticipants, #snapshot.history)
    local channel = GetBroadcastChannel()
    if #header <= 255 then
        C_ChatInfo.SendAddonMessage(MESSAGE_PREFIX, header, channel)
        -- Only log if there's actual data to broadcast
        if #sendableBets > 0 or #sendableParticipants > 0 or #snapshot.history > 0 then
            DebugPrint("↑ Broadcast: v" .. snapshot.version .. " (" .. #sendableBets .. " bets, " .. #sendableParticipants .. " participants, " .. #snapshot.history .. " history)", "SYNC")
        end
    end

    -- Send each bet
    for i, betData in ipairs(sendableBets) do
        local betMsg = SerializeMessage(MSG_STATE_SYNC, SYNC_TYPE_BET, snapshot.nonce, i, betData.id, betData.data)
        C_ChatInfo.SendAddonMessage(MESSAGE_PREFIX, betMsg, channel)
    end

    -- Send participant data
    for i, participantData in ipairs(sendableParticipants) do
        local partMsg = SerializeMessage(MSG_STATE_SYNC, SYNC_TYPE_PARTICIPANT, snapshot.nonce, i, participantData.betId, participantData.data)
        C_ChatInfo.SendAddonMessage(MESSAGE_PREFIX, partMsg, channel)
    end
    
    -- Send history data (for statistics sync)
    for i, historyBet in ipairs(snapshot.history) do
        local historyData = historyBet.id .. "|" .. historyBet.status .. "|" .. (historyBet.winningOption or "")
        local histMsg = SerializeMessage(MSG_STATE_SYNC, SYNC_TYPE_HISTORY, snapshot.nonce, i, historyData)
        C_ChatInfo.SendAddonMessage(MESSAGE_PREFIX, histMsg, channel)
    end
    
    self.lastBroadcast = GetTime()
end

-- Merge received state with local state
function FuldStonks:MergeState(receivedBets, receivedParticipants, senderVersion, sender, receivedHistory)
    local changesMade = false
    local conflicts = 0
    
    -- Track changes for consolidated logging
    local changes = {
        newBets = {},
        updatedBets = {},
        closedBets = {},
        potUpdates = {}
    }
    
    -- Update our Lamport clock
    UpdateStateVersion(senderVersion)
    
    -- Merge received history (resolved/cancelled bets) for statistics
    if receivedHistory and #receivedHistory > 0 then
        for _, historyData in ipairs(receivedHistory) do
            -- Parse history data: betId|status|winningOption
            local betId, status, winningOption = strsplit("|", historyData)
            
            if betId then
                -- Only add if we don't have it or if this is newer information
                if not FuldStonksDB.betHistory[betId] then
                    -- Create a stub entry with received information
                    FuldStonksDB.betHistory[betId] = {
                        id = betId,
                        status = status or "",
                        winningOption = winningOption and (winningOption ~= "" and winningOption or nil) or nil,
                        participants = {},  -- Will be populated from other sources
                        stateVersion = senderVersion
                    }
                    changesMade = true
                elseif senderVersion > (FuldStonksDB.betHistory[betId].stateVersion or 0) then
                    -- Update if we have newer information
                    FuldStonksDB.betHistory[betId].status = status or ""
                    FuldStonksDB.betHistory[betId].winningOption = winningOption and (winningOption ~= "" and winningOption or nil) or nil
                    FuldStonksDB.betHistory[betId].stateVersion = senderVersion
                    changesMade = true
                end
            end
        end
    end
    
    -- Process each received bet
    for betId, receivedBet in pairs(receivedBets) do
        local localBet = FuldStonksDB.activeBets[betId]
        local historyBet = FuldStonksDB.betHistory[betId]
        
        -- Check if we have this bet in history (cancelled/resolved)
        if historyBet and (historyBet.stateVersion or 0) >= (receivedBet.stateVersion or 0) then
            -- We have a newer or equal version in history, ignore the received bet
            -- Don't add it back to active bets
            
        elseif not localBet then
            -- New bet we don't have (and not in history or history is older)
            -- Accept it with empty participants (will be filled by participant merge)
            receivedBet.participants = {}
            receivedBet.totalPot = 0
            FuldStonksDB.activeBets[betId] = receivedBet
            changesMade = true
            
            local creatorName = GetPlayerBaseName(receivedBet.createdBy)
            print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " " .. creatorName .. " created bet: " .. receivedBet.title)
            table.insert(changes.newBets, receivedBet.title)
            
        elseif receivedBet.stateVersion > (localBet.stateVersion or 0) then
            -- Received bet is newer - update it
            -- Preserve local participants and totalPot for merging
            local localParticipants = localBet.participants
            local oldTotalPot = localBet.totalPot
            
            FuldStonksDB.activeBets[betId] = receivedBet
            
            -- Keep local participants and totalPot - will be merged properly in participant processing
            receivedBet.participants = localParticipants or {}
            receivedBet.totalPot = oldTotalPot or 0
            
            changesMade = true
            table.insert(changes.updatedBets, betId)
            
        elseif receivedBet.stateVersion == (localBet.stateVersion or 0) then
            -- Same version - use tie-breaker (creator name lexicographically)
            if receivedBet.createdBy < localBet.createdBy then
                local localParticipants = localBet.participants
                local oldTotalPot = localBet.totalPot
                
                FuldStonksDB.activeBets[betId] = receivedBet
                
                receivedBet.participants = localParticipants or {}
                receivedBet.totalPot = oldTotalPot or 0
                
                conflicts = conflicts + 1
                changesMade = true
            end
        end
        -- else: local bet is newer, keep it
    end
    
    -- Check for bets that should be removed from activeBets
    -- If a bet's creator broadcasts without including the bet, it means they cancelled/resolved it
    for betId, localBet in pairs(FuldStonksDB.activeBets) do
        if localBet.createdBy == sender and not receivedBets[betId] then
            -- The creator of this bet sent a sync without including it
            -- This means they've cancelled or resolved it
            
            -- Move to history as "externally cancelled" if not already there
            if not FuldStonksDB.betHistory[betId] then
                localBet.status = "cancelled"
                localBet.cancelledAt = GetTime()
                localBet.stateVersion = senderVersion
                FuldStonksDB.betHistory[betId] = localBet
                changesMade = true
                print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Bet '" .. localBet.title .. "' was closed by creator")
                table.insert(changes.closedBets, localBet.title)
            end
            
            FuldStonksDB.activeBets[betId] = nil
        end
    end
    
    -- Process participants - rebuild totalPot from scratch for each bet to avoid double-counting
    local potsToRecalculate = {}
    
    for betId, participants in pairs(receivedParticipants) do
        local bet = FuldStonksDB.activeBets[betId]
        if bet then
            for playerName, participation in pairs(participants) do
                local localParticipation = bet.participants[playerName]
                
                if not localParticipation then
                    -- New participant
                    bet.participants[playerName] = participation
                    potsToRecalculate[betId] = true
                    changesMade = true
                    
                elseif (participation.timestamp or 0) > (localParticipation.timestamp or 0) then
                    -- Received participant data is newer
                    bet.participants[playerName] = participation
                    potsToRecalculate[betId] = true
                    changesMade = true
                end
            end
        end
    end
    
    -- Recalculate totalPot for bets that had participant changes
    for betId, _ in pairs(potsToRecalculate) do
        local bet = FuldStonksDB.activeBets[betId]
        if bet then
            local newTotal = 0
            for playerName, participation in pairs(bet.participants) do
                newTotal = newTotal + participation.amount
            end
            
            if newTotal ~= bet.totalPot then
                bet.totalPot = newTotal
                
                if not FuldStonksDB.ignoredBets[betId] then
                    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Pot updated for '" .. bet.title .. "': " .. newTotal .. "g")
                    table.insert(changes.potUpdates, bet.title)
                end
            end
        end
    end

    -- If our own pending bet is now confirmed via sync, clear local pending state.
    local myPending = self.pendingBets[playerFullName]
    if myPending then
        local pendingBet = FuldStonksDB.activeBets[myPending.betId]
        if pendingBet and pendingBet.participants and pendingBet.participants[playerFullName] then
            self.pendingBets[playerFullName] = nil
            changesMade = true
        end
    end
    
    -- Log consolidated summary only if changes were made
    if changesMade then
        local summary = "← Sync from " .. GetPlayerBaseName(sender) .. ": "
        local parts = {}
        
        if #changes.newBets > 0 then
            table.insert(parts, #changes.newBets .. " new")
        end
        if #changes.updatedBets > 0 then
            table.insert(parts, #changes.updatedBets .. " updated")
        end
        if conflicts > 0 then
            table.insert(parts, conflicts .. " conflict(s)")
        end
        if #changes.closedBets > 0 then
            table.insert(parts, #changes.closedBets .. " closed")
        end
        if #changes.potUpdates > 0 then
            table.insert(parts, #changes.potUpdates .. " pot update(s)")
        end
        
        summary = summary .. table.concat(parts, ", ")
        DebugPrint(summary, "SYNC")
    end
    
    -- Update UI if changes were made
    if changesMade and self.frame and self.frame:IsShown() then
        self.frame:UpdateBetList()
    end
    if changesMade then
        RefreshOpenInspectDialog()
    end
    
    return changesMade
end

-- Send addon message (simplified for state-based sync)
function FuldStonks:BroadcastMessage(msgType, ...)
    local channel = GetBroadcastChannel()
    local message = SerializeMessage(msgType, ...)
    
    -- Check message length (WoW limit is 255 chars)
    if #message > 255 then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: Message too long (" .. #message .. " chars)")
        return false
    end
    
    C_ChatInfo.SendAddonMessage(MESSAGE_PREFIX, message, channel)
    DebugPrint("→ " .. msgType, "MSG")
    return true
end

-- Initialize addon communication
local function InitializeAddonComms()
    -- Register addon message prefix
    C_ChatInfo.RegisterAddonMessagePrefix(MESSAGE_PREFIX)
end

-- Request full sync from other players (on-demand)
function FuldStonks:RequestSync()
    self:BroadcastMessage(MSG_SYNC_REQUEST)
    self.syncRequested = true
    DebugPrint("Syncing...", "SYNC")
end

-- Handle received addon messages
local function OnAddonMessageReceived(prefix, message, channel, sender)
    if prefix ~= MESSAGE_PREFIX then
        return
    end
    
    -- Ignore messages from self
    if sender == playerFullName then
        return
    end
    
    local msgType, senderVersion, arg1, arg2, arg3, arg4, arg5, arg6 = DeserializeMessage(message)
    
    -- Version check: Only accept messages from same addon version (silently ignore mismatches)
    if senderVersion ~= FuldStonks.version then
        return
    end
    
    local now = GetTime()
    
    -- Only log message type if it's not a state sync chunk (those are too verbose)
    if msgType ~= MSG_STATE_SYNC or arg1 == SYNC_TYPE_HEADER then
        DebugPrint("Received " .. msgType .. " from " .. GetPlayerBaseName(sender), "MSG")
    end
    
    -- Update peer tracking
    if not FuldStonks.peers[sender] then
        FuldStonks.peers[sender] = {
            lastSeen = now,
            stateVersion = 0,
            nonce = 0,
            addonVersion = senderVersion
        }
        local baseName = GetPlayerBaseName(sender)
        --print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " " .. baseName .. " connected!")
    end
    FuldStonks.peers[sender].lastSeen = now
    
    -- Handle different message types
    if msgType == MSG_STATE_SYNC then
        local syncType = arg1  -- SYNC_TYPE_HEADER, SYNC_TYPE_BET, or SYNC_TYPE_PARTICIPANT
        
        if syncType == SYNC_TYPE_HEADER then
            -- State sync header: version, nonce, betCount, participantCount, historyCount
            local version = tonumber(arg2) or 0
            local nonce = tonumber(arg3) or 0
            local betCount = tonumber(arg4) or 0
            local participantCount = tonumber(arg5) or 0
            local historyCount = tonumber(arg6) or 0
            
            FuldStonks.peers[sender].stateVersion = version
            FuldStonks.peers[sender].nonce = nonce
            
            -- Initialize pending state update for this nonce
            if not FuldStonks.pendingStateUpdates[sender] then
                FuldStonks.pendingStateUpdates[sender] = {}
            end
            
            FuldStonks.pendingStateUpdates[sender][nonce] = {
                version = version,
                expectedBets = betCount,
                expectedParticipants = participantCount,
                expectedHistory = historyCount,
                receivedBets = {},
                receivedParticipants = {},
                receivedHistory = {},
                timestamp = now
            }
            
            DebugPrint("← Sync from " .. GetPlayerBaseName(sender) .. ": v" .. version .. " nonce:" .. nonce .. " (" .. betCount .. " bets, " .. participantCount .. " participants, " .. historyCount .. " history)", "SYNC")

            -- Handle empty snapshots immediately (no BET/PARTICIPANT/HISTORY chunks will follow).
            if betCount == 0 and participantCount == 0 and historyCount == 0 then
                FuldStonks:CheckAndApplyStateUpdate(sender, nonce)
            end
            
        elseif syncType == SYNC_TYPE_BET then
            -- Bet data: nonce, index, betId, serializedBet
            local nonce = tonumber(arg2) or 0
            local index = tonumber(arg3) or 0
            local betId = arg4
            local betData = arg5
            
            if FuldStonks.pendingStateUpdates[sender] and FuldStonks.pendingStateUpdates[sender][nonce] then
                local bet = DeserializeBetFromSync(betData)
                if bet then
                    FuldStonks.pendingStateUpdates[sender][nonce].receivedBets[betId] = bet
                    
                    -- Check if we've received all expected data
                    FuldStonks:CheckAndApplyStateUpdate(sender, nonce)
                end
            end
            
        elseif syncType == SYNC_TYPE_PARTICIPANT then
            -- Participant data: nonce, index, betId, serializedParticipant
            local nonce = tonumber(arg2) or 0
            local index = tonumber(arg3) or 0
            local betId = arg4
            local participantData = arg5
            
            if FuldStonks.pendingStateUpdates[sender] and FuldStonks.pendingStateUpdates[sender][nonce] then
                local playerName, participation = DeserializeParticipant(participantData)
                if playerName and participation then
                    if not FuldStonks.pendingStateUpdates[sender][nonce].receivedParticipants[betId] then
                        FuldStonks.pendingStateUpdates[sender][nonce].receivedParticipants[betId] = {}
                    end
                    FuldStonks.pendingStateUpdates[sender][nonce].receivedParticipants[betId][playerName] = participation
                    
                    -- Check if we've received all expected data
                    FuldStonks:CheckAndApplyStateUpdate(sender, nonce)
                end
            end
            
        elseif syncType == SYNC_TYPE_HISTORY then
            -- History data: nonce, index, historyData (betId|status|winningOption)
            local nonce = tonumber(arg2) or 0
            local index = tonumber(arg3) or 0
            local historyData = arg4
            
            if FuldStonks.pendingStateUpdates[sender] and FuldStonks.pendingStateUpdates[sender][nonce] then
                if historyData then
                    table.insert(FuldStonks.pendingStateUpdates[sender][nonce].receivedHistory, historyData)
                    
                    -- Check if we've received all expected data
                    FuldStonks:CheckAndApplyStateUpdate(sender, nonce)
                end
            end
        end
        
    elseif msgType == MSG_SYNC_REQUEST then
        DebugPrint(GetPlayerBaseName(sender) .. " requested sync", "SYNC")
        -- Send our current state immediately
        FuldStonks:BroadcastStateSync()
        
    elseif msgType == MSG_BET_PENDING then
        -- Handle pending bet notification (received by bet creator)
        -- This still sends immediately for better UX
        local betId = arg1
        local option = arg2
        local amount = tonumber(arg3) or 0
        
        local bet = FuldStonksDB.activeBets[betId]
        if bet and bet.createdBy == playerFullName then
            local existingConfirmed = bet.participants[sender]
            if existingConfirmed and existingConfirmed.option ~= option then
                DebugPrint("Rejected pending bet from " .. GetPlayerBaseName(sender) .. " (conflicts with existing vote)", "BET")
                FuldStonks:BroadcastMessage(MSG_BET_PENDING_REJECT, betId, sender)
                return
            end

            -- Store pending bet info from this player
            FuldStonks.pendingBets[sender] = {
                betId = betId,
                option = option,
                amount = amount,
                timestamp = GetTime()
            }
            
            local baseName = GetPlayerBaseName(sender)
            print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " " .. baseName .. " wants to bet " .. amount .. "g on " .. COLOR_YELLOW .. option .. COLOR_RESET)
            print("  Bet: " .. bet.title)
            print("  " .. COLOR_YELLOW .. "Accept their trade to confirm the bet" .. COLOR_RESET)
            
            DebugPrint("Pending bet: " .. baseName .. " → " .. amount .. "g on " .. option, "BET")
            
            -- Update UI immediately to show pending bet
            if FuldStonks.frame and FuldStonks.frame:IsShown() then
                FuldStonks.frame:UpdateBetList()
            end
            RefreshOpenInspectDialog()
        end
        
    elseif msgType == MSG_BET_PENDING_CANCEL then
        -- Handle pending bet cancellation (received by bet creator)
        local betId = arg1
        
        -- Remove the pending bet for this sender if it matches
        if FuldStonks.pendingBets[sender] and FuldStonks.pendingBets[sender].betId == betId then
            local baseName = GetPlayerBaseName(sender)
            print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " " .. baseName .. " cancelled their pending bet")
            FuldStonks.pendingBets[sender] = nil
            DebugPrint("Cancelled: " .. baseName, "BET")
            
            -- Update UI immediately
            if FuldStonks.frame and FuldStonks.frame:IsShown() then
                FuldStonks.frame:UpdateBetList()
            end
            RefreshOpenInspectDialog()
        end

    elseif msgType == MSG_BET_PENDING_REJECT then
        -- Bet creator rejected this pending bet (or removed it manually)
        local betId = arg1
        local targetName = arg2
        local myPending = FuldStonks.pendingBets[playerFullName]
        local isTargeted = false
        if targetName then
            local targetBase = GetPlayerBaseName(targetName)
            local myBase = GetPlayerBaseName(playerFullName)
            isTargeted = (targetName == playerFullName) or (targetBase == myBase)
        end
        if myPending and myPending.betId == betId and isTargeted then
            FuldStonks.pendingBets[playerFullName] = nil
            print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Your pending bet was removed by the bet creator.")
            
            -- Update UI immediately
            if FuldStonks.frame and FuldStonks.frame:IsShown() then
                FuldStonks.frame:UpdateBetList()
            end
            RefreshOpenInspectDialog()
        end

    elseif msgType == MSG_BET_CONFIRMED then
        -- Fast-path confirmed bet update so clients see participants/pot immediately.
        local betId = arg1
        local confirmedPlayer = arg2
        local option = arg3
        local amount = tonumber(arg4) or 0
        local totalPot = tonumber(arg5)

        local bet = FuldStonksDB.activeBets[betId]
        if bet and bet.createdBy == sender and confirmedPlayer and option and amount > 0 then
            -- Update participant data
            bet.participants[confirmedPlayer] = {
                option = option,
                amount = amount,
                confirmed = true,
                timestamp = GetTime()
            }

            -- Update total pot
            if totalPot then
                bet.totalPot = totalPot
            else
                local recalculated = 0
                for _, p in pairs(bet.participants) do
                    recalculated = recalculated + (p.amount or 0)
                end
                bet.totalPot = recalculated
            end

            -- Clear pending bet for the confirmed player (if we have any pending bets on this bet)
            local myPending = FuldStonks.pendingBets[playerFullName]
            if myPending and myPending.betId == betId then
                local confirmedBase = GetPlayerBaseName(confirmedPlayer)
                local myBase = GetPlayerBaseName(playerFullName)
                if confirmedPlayer == playerFullName or confirmedBase == myBase then
                    FuldStonks.pendingBets[playerFullName] = nil
                    DebugPrint("Cleared pending bet for " .. playerFullName .. " due to confirmation")
                end
            end

            -- Update UI for all participants
            if FuldStonks.frame and FuldStonks.frame:IsShown() then
                FuldStonks.frame:UpdateBetList()
            end
            RefreshOpenInspectDialog()
            
            DebugPrint("Processed bet confirmation: " .. confirmedPlayer .. " for " .. betId)
        end
        
    else
        DebugPrint("Unknown message type: " .. tostring(msgType))
    end
end

-- Check if we've received complete state update and apply it
function FuldStonks:CheckAndApplyStateUpdate(sender, nonce)
    local update = self.pendingStateUpdates[sender] and self.pendingStateUpdates[sender][nonce]
    if not update then return end
    
    local receivedBetCount = 0
    for _ in pairs(update.receivedBets) do
        receivedBetCount = receivedBetCount + 1
    end
    
    local receivedParticipantCount = 0
    for _, participants in pairs(update.receivedParticipants) do
        for _ in pairs(participants) do
            receivedParticipantCount = receivedParticipantCount + 1
        end
    end
    
    local receivedHistoryCount = #(update.receivedHistory or {})
    
    -- Check if we have all the data
    if receivedBetCount >= update.expectedBets and receivedParticipantCount >= update.expectedParticipants and receivedHistoryCount >= (update.expectedHistory or 0) then
        -- Apply the state update (merge also handles history)
        self:MergeState(update.receivedBets, update.receivedParticipants, update.version, sender, update.receivedHistory)
        
        -- Clean up
        self.pendingStateUpdates[sender][nonce] = nil
        
        -- Clean up old pending updates (older than STATE_CLEANUP_TIMEOUT seconds)
        local now = GetTime()
        for peerName, nonces in pairs(self.pendingStateUpdates) do
            for n, upd in pairs(nonces) do
                if now - upd.timestamp > STATE_CLEANUP_TIMEOUT then
                    self.pendingStateUpdates[peerName][n] = nil
                end
            end
        end
    end
end

-- ============================================
-- TRADE HANDLING FOR BET HOLDER
-- ============================================

-- Track trade information
FuldStonks.currentTrade = {
    player = nil,
    amount = 0,
    betInfo = nil,
    traderName = nil,
    goldBefore = 0
}

-- Handle trade window opening
local function OnTradeShow()
    local tradeName = UnitName("NPC")
    if not tradeName then return end
    
    -- Get full name with realm
    local _, tradeRealm = UnitFullName("NPC")
    local tradeFullName = (tradeRealm and tradeRealm ~= "" and (tradeName .. "-" .. tradeRealm)) or tradeName
    
    FuldStonks.currentTrade.player = tradeFullName
    FuldStonks.currentTrade.amount = 0
    FuldStonks.currentTrade.betInfo = nil
    FuldStonks.currentTrade.goldBefore = math.floor(GetMoney() / 10000)  -- Store current gold
    
    DebugPrint("Trade opened with " .. GetPlayerBaseName(tradeFullName), "TRADE")
    
    -- SCENARIO 1: Check if YOU have a pending bet and are trading TO the bet creator
    local myPendingBet = FuldStonks.pendingBets[playerFullName]
    if myPendingBet then
        local bet = FuldStonksDB.activeBets[myPendingBet.betId]
        if bet then
            local betCreatorBaseName = GetPlayerBaseName(bet.createdBy)
            local tradeBaseName = GetPlayerBaseName(tradeFullName)
            
            -- Check if the person we're trading with is the bet creator
            if bet.createdBy == tradeFullName or betCreatorBaseName == tradeBaseName then
                FuldStonks.currentTrade.betInfo = myPendingBet
                FuldStonks.currentTrade.traderName = playerFullName  -- I am the trader
                print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Trading gold for your bet:")
                print("  Bet: " .. bet.title)
                print("  Amount: " .. myPendingBet.amount .. "g")
                print("  Option: " .. myPendingBet.option)
                DebugPrint("→ Sending gold for bet: " .. bet.title, "TRADE")
                return
            end
        end
    end
    
    -- SCENARIO 2: Check if someone is trading TO YOU for a bet you created
    local foundMatch = false
    for playerName, pendingBet in pairs(FuldStonks.pendingBets) do
        local playerBaseName = GetPlayerBaseName(playerName)
        local tradeBaseName = GetPlayerBaseName(tradeFullName)
        
        -- Match by full name OR base name (for same-realm players)
        if playerName == tradeFullName or playerBaseName == tradeBaseName then
            local bet = FuldStonksDB.activeBets[pendingBet.betId]
            if bet and bet.createdBy == playerFullName then
                FuldStonks.currentTrade.betInfo = pendingBet
                FuldStonks.currentTrade.traderName = playerName  -- Store the actual key used in pendingBets
                print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Receiving gold for bet:")
                print("  Bet: " .. bet.title)
                print("  Expected: " .. pendingBet.amount .. "g")
                DebugPrint("← Receiving " .. pendingBet.amount .. "g for: " .. bet.title, "TRADE")
                foundMatch = true
                break
            end
        end
    end
end

-- Handle gold being added to trade
local function OnTradeMoneyChanged()
    local targetGold = GetTargetTradeMoney()
    
    -- Track the amount being received (convert copper to gold)
    FuldStonks.currentTrade.amount = math.floor(targetGold / 10000)
    
    if FuldStonks.currentTrade.betInfo then
        local bet = FuldStonksDB.activeBets[FuldStonks.currentTrade.betInfo.betId]
        if bet and bet.createdBy == playerFullName then
            local expected = FuldStonks.currentTrade.betInfo.amount
            if FuldStonks.currentTrade.amount == expected then
                local traderName = GetPlayerBaseName(FuldStonks.currentTrade.player)
                print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " " .. traderName .. " is trading the correct amount: " .. expected .. "g")
                DebugPrint("Gold matches expected amount", "TRADE")
            elseif FuldStonks.currentTrade.amount > 0 then
                print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Warning: Expected " .. expected .. "g but receiving " .. FuldStonks.currentTrade.amount .. "g")
            end
        end
    end
end

-- Handle trade accept button updates
local function OnTradeAcceptUpdate(player, target)
    if FuldStonksDB.debug == true and player == 1 and target == 1 then
        DebugPrint("Both players accepted", "TRADE")
    end
end

-- Handle trade window closing (check if money increased)
local function OnTradeClosed()
    if FuldStonks.currentTrade.betInfo and FuldStonks.currentTrade.amount > 0 then
        -- Store trade info locally before clearing (C_Timer callback needs it)
        local tradeInfo = {
            betInfo = FuldStonks.currentTrade.betInfo,
            goldBefore = FuldStonks.currentTrade.goldBefore,
            traderName = FuldStonks.currentTrade.traderName or FuldStonks.currentTrade.player
        }
        
        -- Delay gold check slightly because TRADE_CLOSED fires before gold is added
        C_Timer.After(0.5, function()
            -- Check if our money increased by the expected amount
            local currentGold = math.floor(GetMoney() / 10000)
            local goldIncrease = currentGold - tradeInfo.goldBefore
            
            local pendingBet = tradeInfo.betInfo
            if not pendingBet then
                return
            end
            
            local traderName = tradeInfo.traderName
            local bet = FuldStonksDB.activeBets[pendingBet.betId]
            
            if not bet then
                return
            end
            
            -- CASE 1: We are the bet creator and received gold from a participant
            if bet.createdBy == playerFullName then
                if goldIncrease == pendingBet.amount then
                    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Trade completed successfully! Confirming bet...")
                    DebugPrint("Gold: " .. tradeInfo.goldBefore .. "g → " .. currentGold .. "g (+=" .. goldIncrease .. "g)", "TRADE")
                    
                    -- Confirm the bet
                    FuldStonks:ConfirmBetTrade(traderName, pendingBet.betId, pendingBet.option, pendingBet.amount)
                    
                    -- Remove from pending
                    FuldStonks.pendingBets[traderName] = nil
                    
                elseif goldIncrease > 0 then
                    print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Trade amount mismatch! Expected " .. pendingBet.amount .. "g but received " .. goldIncrease .. "g")
                    DebugPrint("Mismatch: expected " .. pendingBet.amount .. "g, got " .. goldIncrease .. "g", "TRADE")
                end
            -- CASE 2: We are a participant who just traded gold to the creator
            else
                -- We initiated the trade and sent the gold
                -- Clear our pending bet immediately for better UX
                if FuldStonks.pendingBets[playerFullName] and FuldStonks.pendingBets[playerFullName].betId == pendingBet.betId then
                    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Trade completed! Waiting for creator to confirm...")
                    DebugPrint("Sent " .. pendingBet.amount .. "g, awaiting confirmation", "TRADE")
                    
                    -- Update UI to show that confirmation is pending
                    if FuldStonks.frame and FuldStonks.frame:IsShown() then
                        FuldStonks.frame:UpdateBetList()
                    end
                    RefreshOpenInspectDialog()
                end
            end
        end)
    end
    
    -- Clear trade info
    FuldStonks.currentTrade = {
        player = nil,
        amount = 0,
        betInfo = nil,
        traderName = nil,
        goldBefore = 0
    }
end

-- Event handler
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            Initialize()
            InitializeAddonComms()
            FuldStonks:LoadData()
            
            -- Initialize debug mode if not set
            if FuldStonksDB.debug == nil then
                FuldStonksDB.debug = false
            end
            
            -- Initialize state versioning
            if not FuldStonksDB.stateVersion then
                FuldStonksDB.stateVersion = 0
            end
            if not FuldStonksDB.syncNonce then
                FuldStonksDB.syncNonce = 0
            end
            
            -- Start state sync timer (every STATE_SYNC_INTERVAL seconds)
            if FuldStonks.syncTicker then
                FuldStonks.syncTicker:Cancel()
            end
            FuldStonks.syncTicker = C_Timer.NewTicker(STATE_SYNC_INTERVAL, function()
                FuldStonks:BroadcastStateSync()
            end)
            
            -- Send initial state sync after a short delay
            C_Timer.After(2.0, function()
                FuldStonks:BroadcastStateSync()
            end)
        end
    elseif event == "CHAT_MSG_ADDON" then
        OnAddonMessageReceived(...)
    elseif event == "GROUP_ROSTER_UPDATE" then
        -- Debounce roster updates to prevent spam
        if FuldStonks.rosterUpdateTimer then
            FuldStonks.rosterUpdateTimer:Cancel()
        end
        FuldStonks.rosterUpdateTimer = C_Timer.NewTimer(1.5, function()
            FuldStonks:BroadcastStateSync()  -- Sync state on roster change
            FuldStonks.rosterUpdateTimer = nil
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Entering world/instance, request sync and broadcast our state
        C_Timer.After(2.0, function()
            FuldStonks:BroadcastStateSync()
            FuldStonks:RequestSync()
        end)
    elseif event == "PLAYER_LOGOUT" then
        -- Clean up timers on logout
        if FuldStonks.syncTicker then
            FuldStonks.syncTicker:Cancel()
            FuldStonks.syncTicker = nil
        end
        if FuldStonks.rosterUpdateTimer then
            FuldStonks.rosterUpdateTimer:Cancel()
            FuldStonks.rosterUpdateTimer = nil
        end
    elseif event == "TRADE_SHOW" then
        OnTradeShow()
    elseif event == "TRADE_MONEY_CHANGED" then
        OnTradeMoneyChanged()
    elseif event == "TRADE_ACCEPT_UPDATE" then
        OnTradeAcceptUpdate(...)
    elseif event == "TRADE_CLOSED" then
        OnTradeClosed()
    end
end)

-- Register events
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("TRADE_SHOW")
eventFrame:RegisterEvent("TRADE_MONEY_CHANGED")
eventFrame:RegisterEvent("TRADE_ACCEPT_UPDATE")
eventFrame:RegisterEvent("TRADE_CLOSED")

-- ============================================
-- FUTURE EXPANSION HOOKS
-- ============================================

-- Hook for bet management
function FuldStonks:CreateBet(betData)
    -- Generate unique bet ID
    local betId = GenerateBetId()
    
    -- Increment state version
    local stateVersion = IncrementStateVersion()
    
    -- Create bet object
    local bet = {
        id = betId,
        title = betData.title,
        betType = betData.betType or "YesNo",
        options = betData.options or {"Yes", "No"},
        createdBy = playerFullName,
        timestamp = GetTime(),
        participants = {},
        totalPot = 0,
        status = "active",
        stateVersion = stateVersion,
        pendingTrades = {}  -- Track pending gold trades
    }
    
    -- Add to active bets
    FuldStonksDB.activeBets[betId] = bet
    
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Bet created: " .. bet.title)
    DebugPrint("Created bet: " .. betId .. " (v" .. stateVersion .. ")")
    
    -- Immediately broadcast state so spectators see the new bet right away
    -- Don't wait for the next 5s sync cycle for better UX
    self:BroadcastStateSync()
    
    -- Force UI update immediately
    if self.frame and self.frame.UpdateBetList then
        self.frame:UpdateBetList()
    end
    
    return betId
end

function FuldStonks:PlaceBet(betId, option, amount)
    local bet = FuldStonksDB.activeBets[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: Bet not found!")
        return
    end
    
    if bet.status ~= "active" then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: Bet is not active!")
        return
    end
    
    -- Validate option
    local validOption = false
    for _, opt in ipairs(bet.options) do
        if opt == option then
            validOption = true
            break
        end
    end
    
    if not validOption then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: Invalid option!")
        return
    end
    
    -- Check if player is the bet creator
    local isCreator = (bet.createdBy == playerFullName)

    -- Prevent opposite-side voting for same player on same bet
    local existingConfirmed = bet.participants[playerFullName]
    if existingConfirmed and existingConfirmed.option ~= option then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " You already have a confirmed bet on " .. COLOR_YELLOW .. existingConfirmed.option .. COLOR_RESET .. ".")
        print("  Ask the bet creator to remove your current bet before switching sides.")
        return
    end
    
    if isCreator then
        -- Bet creator can participate without trading (can't trade with themselves)
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Placing bet as creator (no trade required)...")
        
        -- Directly confirm the bet
        self:ConfirmBetTrade(playerFullName, betId, option, amount)
        
        -- Clear any pending bet
        self.pendingBets[playerFullName] = nil
        
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Bet placed successfully!")
        print("  Bet: " .. bet.title)
        print("  Choice: " .. COLOR_YELLOW .. option .. COLOR_RESET)
        print("  Amount: " .. amount .. "g")
        
        return
    end
    
    -- Store pending bet (waiting for gold trade)
    self.pendingBets[playerFullName] = {
        betId = betId,
        option = option,
        amount = amount,
        timestamp = GetTime()
    }
    
    -- Broadcast pending bet notification to bet creator
    -- Use current channel (GUILD/PARTY/RAID/INSTANCE) instead of WHISPER for addon messages
    local betTitle = bet.title
    local betCreator = bet.createdBy
    
    -- Send addon message to bet creator with pending bet info via broadcast channel
    local pendingMsg = betId .. DELIMITER .. option .. DELIMITER .. tostring(amount)
    DebugPrint("Sending pending bet notification: " .. pendingMsg)
    self:BroadcastMessage(MSG_BET_PENDING, betId, option, tostring(amount))
    
    -- Also send regular whisper for visibility
    local whisperMsg = string.format("FuldStonks: Trading you %dg for '%s' (betting %s)", amount, betTitle, option)
    SendChatMessage(whisperMsg, "WHISPER", nil, betCreator)
    
    print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Please trade " .. amount .. "g to " .. GetPlayerBaseName(betCreator) .. " to confirm your bet.")
    print("  Bet: " .. betTitle)
    print("  Choice: " .. COLOR_YELLOW .. option .. COLOR_RESET)
    print("  " .. COLOR_ORANGE .. "Type /fs cancel to cancel this pending bet" .. COLOR_RESET)
    
    DebugPrint("Pending bet: " .. betId .. " | " .. option .. " | " .. amount .. "g - awaiting trade")
end

-- Cancel a pending bet
function FuldStonks:CancelPendingBet()
    local pendingBet = self.pendingBets[playerFullName]
    if not pendingBet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " You have no pending bets to cancel.")
        return
    end
    
    local bet = FuldStonksDB.activeBets[pendingBet.betId]
    if bet then
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Cancelled pending bet: " .. bet.title)
        print("  Choice: " .. COLOR_YELLOW .. pendingBet.option .. COLOR_RESET .. " (" .. pendingBet.amount .. "g)")
        
        -- Notify the bet creator that we cancelled
        self:BroadcastMessage(MSG_BET_PENDING_CANCEL, pendingBet.betId)
        DebugPrint("Sent pending bet cancellation for: " .. pendingBet.betId)
    end
    
    self.pendingBets[playerFullName] = nil
    DebugPrint("Cancelled pending bet")
end

-- Confirm bet after gold trade (called by bet holder)
function FuldStonks:ConfirmBetTrade(playerName, betId, option, amount)
    local bet = FuldStonksDB.activeBets[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: Bet not found for confirmation!")
        return
    end

    -- Prevent opposite-side confirmed votes for same player
    local existingParticipation = bet.participants[playerName]
    if existingParticipation and existingParticipation.option ~= option then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Rejected confirmation for " .. GetPlayerBaseName(playerName) .. ": already confirmed on " .. existingParticipation.option .. ".")
        return
    end

    -- Increment state version for this change
    IncrementStateVersion()
    
    -- Record bet placement (handle bet changes by subtracting old amount)
    local oldAmount = 0
    if bet.participants[playerName] then
        oldAmount = bet.participants[playerName].amount or 0
    end
    
    bet.participants[playerName] = {
        option = option,
        amount = amount,
        confirmed = true,
        timestamp = GetTime()  -- Add timestamp for conflict resolution
    }
    
    bet.totalPot = bet.totalPot - oldAmount + amount
    bet.stateVersion = FuldStonksDB.stateVersion  -- Update bet's state version

    -- Clear pending entry for this player once confirmed
    if self.pendingBets[playerName] and self.pendingBets[playerName].betId == betId then
        self.pendingBets[playerName] = nil
    end
    
    -- Whisper confirmation to the player
    local betTitle = bet.title
    local confirmMsg = string.format("FuldStonks: Confirmed %dg for '%s' (%s). Pot now: %dg", amount, betTitle, option, bet.totalPot)
    SendChatMessage(confirmMsg, "WHISPER", nil, playerName)
    
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Confirmed " .. GetPlayerBaseName(playerName) .. "'s bet: " .. amount .. "g on " .. COLOR_YELLOW .. option .. COLOR_RESET)
    DebugPrint("Confirmed bet: " .. betId .. " | " .. playerName .. " | " .. option .. " | " .. amount .. "g (v" .. FuldStonksDB.stateVersion .. ")")
    
    -- Update local UI immediately BEFORE broadcasting (ensures the confirming player sees it right away)
    if self.frame and self.frame:IsShown() then
        self.frame:UpdateBetList()
    end
    RefreshOpenInspectDialog()
    
    -- Send immediate lightweight participant update for fast UI/inspect refresh on peers.
    self:BroadcastMessage(MSG_BET_CONFIRMED, betId, playerName, option, tostring(amount), tostring(bet.totalPot))

    -- Broadcast immediately so all open UIs update pot/participant state right away.
    self:BroadcastStateSync()
end

function FuldStonks:HideBet(betId)
    FuldStonksDB.ignoredBets[betId] = true
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Bet hidden from view. Use Show hidden in the UI or /fs showhidden.")
end

function FuldStonks:UnhideBet(betId)
    if FuldStonksDB.ignoredBets[betId] then
        FuldStonksDB.ignoredBets[betId] = nil
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Bet unhidden.")
    end
end

function FuldStonks:CancelUserBet(betId, targetName, pendingOnly)
    local bet = FuldStonksDB.activeBets[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Bet not found.")
        return
    end

    if bet.createdBy ~= playerFullName then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Only the bet creator can remove user bets.")
        return
    end

    local query = strtrim((targetName or ""):lower())
    if query == "" then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Enter a player name (with or without realm).")
        return
    end

    local function NameMatches(fullName)
        local fullLower = (fullName or ""):lower()
        local baseLower = (GetPlayerBaseName(fullName) or ""):lower()
        return fullLower == query or baseLower == query
    end

    local matchedParticipantName = nil
    for pName, _ in pairs(bet.participants or {}) do
        if NameMatches(pName) then
            matchedParticipantName = pName
            break
        end
    end

    local matchedPendingName = nil
    for pName, pending in pairs(self.pendingBets) do
        if pending.betId == betId and NameMatches(pName) then
            matchedPendingName = pName
            break
        end
    end

    local didChangeConfirmed = false
    local didRemovePending = false

    if not pendingOnly and matchedParticipantName then
        local removed = bet.participants[matchedParticipantName]
        bet.participants[matchedParticipantName] = nil
        bet.totalPot = math.max(0, (bet.totalPot or 0) - (removed.amount or 0))
        IncrementStateVersion()
        bet.stateVersion = FuldStonksDB.stateVersion
        didChangeConfirmed = true
    end

    if matchedPendingName then
        self.pendingBets[matchedPendingName] = nil
        didRemovePending = true
        self:BroadcastMessage(MSG_BET_PENDING_REJECT, betId, matchedPendingName)
    end

    if not didChangeConfirmed and not didRemovePending then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " No matching user found on this bet.")
        return
    end

    local displayName = GetPlayerBaseName(matchedParticipantName or matchedPendingName)
    if didChangeConfirmed and didRemovePending then
        print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Removed " .. displayName .. "'s confirmed and pending entries.")
    elseif didChangeConfirmed then
        print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Removed " .. displayName .. "'s confirmed bet.")
    else
        print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Removed " .. displayName .. "'s pending bet.")
    end

    if didChangeConfirmed then
        self:BroadcastStateSync()
    end

    if self.frame and self.frame:IsShown() then
        self.frame:UpdateBetList()
    end
    if self.inspectDialog and self.inspectDialog:IsShown() and self.inspectDialog.currentBetId == betId then
        self:ShowBetInspectDialog(betId)
    end
end

-- Master override to force delete any bet (protected by silly password)
function FuldStonks:MasterDelete(betId, password)
    if password ~= "fuldmaster2025" then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Incorrect master password.")
        return
    end

    local bet = FuldStonksDB.activeBets[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Bet not found.")
        return
    end

    local betTitle = bet.title
    FuldStonksDB.activeBets[betId] = nil
    
    -- Broadcast the deletion to all peers
    IncrementStateVersion()
    FuldStonks:BroadcastStateSync()
    
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Master deleted bet: " .. betTitle)
    DebugPrint("Master deleted: " .. betId, "MASTER")
    
    if self.frame and self.frame:IsShown() then
        self.frame:UpdateBetList()
    end
end

function FuldStonks:ShowHiddenBets()
    local count = 0
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Hidden bets:")
    for betId, _ in pairs(FuldStonksDB.ignoredBets) do
        local bet = FuldStonksDB.activeBets[betId]
        if bet then
            print("  " .. bet.title)
            count = count + 1
        else
            -- Clean up reference to non-existent bet
            FuldStonksDB.ignoredBets[betId] = nil
        end
    end
    if count == 0 then
        print("  No hidden bets.")
    else
        print("Use /fs unhideall to unhide all bets.")
    end
end

function FuldStonks:UnhideAllBets()
    local count = 0
    for _ in pairs(FuldStonksDB.ignoredBets) do
        count = count + 1
    end
    FuldStonksDB.ignoredBets = {}
    print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Unhidden " .. count .. " bet(s).")
    if self.frame and self.frame:IsShown() then
        self.frame:UpdateBetList()
    end
end

function FuldStonks:CancelBet(betId)
    local bet = FuldStonksDB.activeBets[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: Bet not found!")
        return
    end
    
    -- Only bet creator can cancel
    if bet.createdBy ~= playerFullName then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Only the bet creator can cancel this bet!")
        return
    end
    
    -- Increment state version
    IncrementStateVersion()
    
    print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " Bet cancelled! Returning all bets...")
    print("  Bet: " .. bet.title)
    
    -- Return bets to participants
    if next(bet.participants) then
        print("  Returned:")
        for playerName, participation in pairs(bet.participants) do
            print("    " .. GetPlayerBaseName(playerName) .. ": " .. participation.amount .. "g")
        end
    else
        print("  No bets to return.")
    end
    
    -- Mark as cancelled and move to history
    bet.status = "cancelled"
    bet.cancelledAt = GetTime()
    bet.stateVersion = FuldStonksDB.stateVersion
    
    FuldStonksDB.betHistory[betId] = bet
    FuldStonksDB.activeBets[betId] = nil
    
    -- Clear any pending bets for this bet
    for playerName, pendingBet in pairs(self.pendingBets) do
        if pendingBet.betId == betId then
            self.pendingBets[playerName] = nil
        end
    end
    
    -- Immediately broadcast state so bet disappears for everyone
    self:BroadcastStateSync()
    
    -- Update UI if open
    if self.frame and self.frame:IsShown() then
        self.frame:UpdateBetList()
    end
    
    -- Close inspect dialog if open
    if self.inspectDialog and self.inspectDialog:IsShown() then
        self.inspectDialog:Hide()
    end
    
    -- Show payout dialog
    self:ShowPayoutDialog(betId, nil)
end

function FuldStonks:ResolveBet(betId, winningOption)
    local bet = FuldStonksDB.activeBets[betId]
    if not bet then
        print(COLOR_RED .. "FuldStonks" .. COLOR_RESET .. " Error: Bet not found!")
        return
    end
    
    -- Increment state version
    IncrementStateVersion()
    
    -- Calculate winners and payouts
    local totalWinningBets = 0
    local winners = {}
    
    for playerName, participation in pairs(bet.participants) do
        if participation.option == winningOption then
            totalWinningBets = totalWinningBets + participation.amount
            table.insert(winners, {name = playerName, amount = participation.amount})
        end
    end
    
    if totalWinningBets == 0 then
        print(COLOR_YELLOW .. "FuldStonks" .. COLOR_RESET .. " No winners! Pot returned.")
        -- Return bets to participants
        for playerName, participation in pairs(bet.participants) do
            print("  " .. GetPlayerBaseName(playerName) .. ": " .. participation.amount .. "g returned")
        end
    else
        -- Distribute winnings proportionally
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Bet resolved! Winners:")
        for _, winner in ipairs(winners) do
            local share = (winner.amount / totalWinningBets) * bet.totalPot
            local profit = share - winner.amount
            print("  " .. GetPlayerBaseName(winner.name) .. ": " .. math.floor(share) .. "g (+" .. math.floor(profit) .. "g)")
        end
    end
    
    -- Mark as resolved and move to history
    bet.status = "resolved"
    bet.winningOption = winningOption
    bet.resolvedAt = GetTime()
    bet.stateVersion = FuldStonksDB.stateVersion
    
    FuldStonksDB.betHistory[betId] = bet
    FuldStonksDB.activeBets[betId] = nil
    
    -- Clear any pending bets for this bet
    for playerName, pendingBet in pairs(self.pendingBets) do
        if pendingBet.betId == betId then
            self.pendingBets[playerName] = nil
        end
    end
    
    -- Immediately broadcast state so bet disappears for everyone
    self:BroadcastStateSync()
    
    -- Whisper all participants about their result
    if totalWinningBets == 0 then
        -- No winners - everyone gets refunded
        for playerName, participation in pairs(bet.participants) do
            if playerName ~= playerFullName then
                local whisperMsg = string.format("FuldStonks: Bet '%s' resolved - No winners! Your %dg has been returned.", bet.title, participation.amount)
                SendChatMessage(whisperMsg, "WHISPER", nil, playerName)
            end
        end
    else
        -- Whisper winners
        for _, winner in ipairs(winners) do
            if winner.name ~= playerFullName then
                local share = math.floor((winner.amount / totalWinningBets) * bet.totalPot)
                local profit = share - winner.amount
                local whisperMsg = string.format("FuldStonks: You WON! Bet: '%s'. Your payout is %dg (+%dg profit)", bet.title, share, profit)
                SendChatMessage(whisperMsg, "WHISPER", nil, winner.name)
            end
        end
        
        -- Whisper losers
        for playerName, participation in pairs(bet.participants) do
            if participation.option ~= winningOption and playerName ~= playerFullName then
                local whisperMsg = string.format("FuldStonks: You lost. Bet: '%s' - %s won. You lost %dg.", bet.title, winningOption, participation.amount)
                SendChatMessage(whisperMsg, "WHISPER", nil, playerName)
            end
        end
    end
    
    -- Update UI if open
    if self.frame and self.frame:IsShown() then
        self.frame:UpdateBetList()
    end
    
    -- Show payout dialog
    self:ShowPayoutDialog(betId, winningOption)
end

-- Hook for data persistence
function FuldStonks:SaveData()
    -- SavedVariables automatically persists FuldStonksDB
    DebugPrint("Data saved to SavedVariables")
end

function FuldStonks:LoadData()
    -- Ensure structures exist
    FuldStonksDB.activeBets = FuldStonksDB.activeBets or {}
    FuldStonksDB.myBets = FuldStonksDB.myBets or {}
    FuldStonksDB.betHistory = FuldStonksDB.betHistory or {}
    FuldStonksDB.ignoredBets = FuldStonksDB.ignoredBets or {}
    FuldStonksDB.showHiddenBets = FuldStonksDB.showHiddenBets or false
    FuldStonksDB.devModeEnabled = FuldStonksDB.devModeEnabled or false
    DebugPrint("Data loaded from SavedVariables")
end