-- FF_Commands.lua - slash commands for FuldFokus addon
FF = FF or {}

-- FuldFokus Emotes commands
SLASH_FF1 = "/ff"
SLASH_FF2 = "/ffe"
SlashCmdList["FF"] = function(msg)
  local cmd, rest = (msg or ""):match("^(%S+)%s*(.*)$")
  cmd = (cmd or ""):lower()

  local function help()
    print("|cffe5a472FF|r commands:")
    print("/ff help - show this help")
    print("/ff status - show current selection, size, and resolved path")
    print("/ff test - print a sample icon in chat to verify rendering")
    print("/ff list - where emotes live / how to pick a key")
    print("/ff set <key|none> - set your Details icon (filename without extension)")
    print("/ff sync - rebroadcast your selection to the current group")
    print("/ff clear - reset emote and size to defaults")
    print("/ff size <n> - icon size (8..64)")
    print("/ff options - open the options panel")
    print("")
    print("FuldStonks betting commands:")
    print("/fs - Toggle FuldStonks betting UI")
    print("/fs help - Show FuldStonks help")
    print("/fs create - Create a new bet")
    print("/fs cancel - Cancel your pending bet")
    print("/fs resolve - Resolve a bet you created")
    print("/fs sync - Request sync from guild/group")
  end

  if cmd == "" or cmd == "help" then
    help()
  
  elseif cmd == "options" or cmd == "opt" or cmd == "config" then
  if FF.OpenOptions then
    FF.OpenOptions()
  else
    print("|cffe5a472FF|r Options panel not ready; try /reload.")
  end
  elseif cmd == "clear" then
  if not FF.Clear then
    print("|cffe5a472FF|r Core not loaded yet.")
    return
  end
  FF.Clear()

  elseif cmd == "sync" then
  if not FF.SendState then
    print("|cffe5a472FF|r Core not loaded yet.")
    return
  end
  local chan = FF.SendState(true)
  if chan then
    print("|cffe5a472FF|r Sync sent to " .. chan .. " (" ..
      (FF_DB.selected == "" and "none" or FF_DB.selected) .. "@" .. tostring(FF_DB.iconSize) .. ")")
  else
    print("|cffe5a472FF|r Could not send now; retrying in 1s...")
    C_Timer.After(1.0, function() FF.SendState(true) end)
  end

  elseif cmd == "status" then
    local sel = FF_DB and FF_DB.selected or ""
    local path = (FF.ResolveKey and FF.ResolveKey(sel)) or "(none)"
    print("|cffe5a472FF|r Status:")
    print(" - Selected: " .. (sel == "" and "none" or sel))
    print(" - Resolved: " .. (path or "(none)"))
    print(" - Size: " .. tostring(FF_DB and FF_DB.iconSize or "n/a"))

  elseif cmd == "test" then
    local sel = FF_DB and FF_DB.selected or ""
    if sel == "" then
      print("|cffe5a472FF|r No emote selected. Try: /ffe set FuldFokus")
    else
      local tex = (FF.TextureStringForKey and FF.TextureStringForKey(sel, FF_DB.iconSize)) or ""
      print("|cffe5a472FF|r Test: " .. tex .. " (key='" .. sel .. "', size=" .. tostring(FF_DB.iconSize) .. ")")
    end

  elseif cmd == "list" then
    print("|cffe5a472FF|r Emotes folder:")
    print(" Interface\\AddOns\\FuldFokus\\Emotes\\FuldFokus")
    print("Use the filename (without extension). Example: /ff set FuldFokus")

  elseif cmd == "set" then
    if not FF.SetSelectedEmote then
      print("|cffe5a472FF|r Core not loaded yet.")
      return
    end
    local k = rest
    if not k or k == "" then
      print("|cffe5a472FF|r Usage: /ffe set <key|none>")
      return
    end
    FF.SetSelectedEmote(k)

  elseif cmd == "size" then
    if not FF.SetIconSize then
      print("|cffe5a472FF|r Core not loaded yet.")
      return
    end
    local n = tonumber(rest)
    if not n then
      print("|cffe5a472FF|r Usage: /ffe size <8..64>")
      return
    end
    FF.SetIconSize(n)

  else
    print("|cffe5a472FF|r Unknown command: " .. (cmd or ""))
    help()
  end
end
