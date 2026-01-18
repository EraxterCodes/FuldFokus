-- FS_Commands.lua - FuldStonks slash commands
-- Part of the FuldFokus addon

local COLOR_GREEN = "|cFF00FF00"
local COLOR_RESET = "|r"
local COLOR_YELLOW = "|cFFFFFF00"
local COLOR_RED = "|cFFFF0000"
local COLOR_ORANGE = "|cFFFF8800"
local COLOR_GRAY = "|cFF808080"

-- Helper function to extract base name (remove realm suffix)
local function GetPlayerBaseName(fullName)
    if not fullName or fullName == "" then
        return fullName
    end
    return fullName:gsub("%-[^%-]*$", "")
end

-- Slash command handler
local function SlashCommandHandler(msg)
    local command = strtrim(msg:lower())
    
    if command == "help" then
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Commands:")
        print("  /FuldStonks or /fs - Toggle main UI")
        print("  /fs help - Show this help message")
        print("  /fs version - Show addon version")
        print("  /fs sync - Request sync from guild/group")
        print("  /fs peers - Show connected peers")
        print("  /fs debug - Toggle debug mode")
        print("  /fs create - Create a new bet")
        print("  /fs pending - Show pending bets (bet creator only)")
        print("  /fs cancel - Cancel your pending bet")
        print("  /fs resolve - Resolve a bet you created")
        print("  /fs showhidden - Show list of hidden bets")
        print("  /fs unhideall - Unhide all hidden bets")
    elseif command == "version" then
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " version " .. (FuldStonks and FuldStonks.version or "unknown"))
    elseif command == "sync" then
        if FuldStonks and FuldStonks.RequestSync then
            FuldStonks:RequestSync()
            print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Requesting sync from guild/group...")
        end
    elseif command == "peers" then
        local count = 0
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Connected peers:")
        if FuldStonks and FuldStonks.peers then
            for name, data in pairs(FuldStonks.peers) do
                local timeSince = math.floor(GetTime() - data.lastSeen)
                local baseName = GetPlayerBaseName(name)
                print("  " .. baseName .. " (seen " .. timeSince .. "s ago)")
                count = count + 1
            end
        end
        if count == 0 then
            print("  No peers connected yet.")
        end
    elseif command == "debug" then
        if FuldStonksDB then
            FuldStonksDB.debug = not FuldStonksDB.debug
            print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Debug mode: " .. (FuldStonksDB.debug and "ON" or "OFF"))
        end
    elseif command == "create" then
        if FuldStonks and FuldStonks.ShowBetCreationDialog then
            FuldStonks:ShowBetCreationDialog()
        end
    elseif command == "cancel" then
        if FuldStonks and FuldStonks.CancelPendingBet then
            FuldStonks:CancelPendingBet()
        end
    elseif command == "resolve" then
        if FuldStonks and FuldStonks.ShowBetResolutionDialog then
            FuldStonks:ShowBetResolutionDialog()
        end
    elseif command == "pending" then
        local count = 0
        print(COLOR_GREEN .. "FuldStonks" .. COLOR_RESET .. " Pending bets awaiting trade:")
        if FuldStonks and FuldStonks.pendingBets and FuldStonksDB and FuldStonksDB.activeBets then
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
        end
        if count == 0 then
            print("  No pending bets.")
        end
    elseif command == "showhidden" then
        if FuldStonks and FuldStonks.ShowHiddenBets then
            FuldStonks:ShowHiddenBets()
        end
    elseif command == "unhideall" then
        if FuldStonks and FuldStonks.UnhideAllBets then
            FuldStonks:UnhideAllBets()
        end
    else
        -- Default: toggle UI
        if FuldStonks and FuldStonks.frame then
            if FuldStonks.frame:IsShown() then
                FuldStonks.frame:Hide()
            else
                FuldStonks.frame:Show()
            end
        elseif _G.ToggleMainFrame then
            _G.ToggleMainFrame()
        end
    end
end

-- Register slash commands
SLASH_FULDSTONKS1 = "/FuldStonks"
SLASH_FULDSTONKS2 = "/fs"
SlashCmdList["FULDSTONKS"] = SlashCommandHandler
