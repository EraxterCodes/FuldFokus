-- FFE_Commands.lua - slash commands
FFE = FFE or {}

SLASH_FFE1 = "/ffe"
SlashCmdList["FFE"] = function(msg)
  local cmd, rest = (msg or ""):match("^(%S+)%s*(.*)$")
  cmd = (cmd or ""):lower()

  local function help()
    print("|cffe5a472FFE|r commands:")
    print("/ffe help - show this help")
    print("/ffe list - where emotes live / how to pick a key")
    print("/ffe options - open the options panel")
  end

  if cmd == "" or cmd == "help" then
    help()
  
  elseif cmd == "options" or cmd == "opt" or cmd == "config" then
    if FFE.OpenOptions then
      FFE.OpenOptions()
    else
      print("|cffe5a472FFE|r Options panel not ready; try /reload.")
    end

  elseif cmd == "list" then
    print("|cffe5a472FFE|r Emotes folder:")
    print(" Interface\\AddOns\\FuldFokus\\Emotes\\FuldFokus")
    print("Emotes are integrated into TwitchEmotes and accessible via the emote menu.")

  else
    print("|cffe5a472FFE|r Unknown command: " .. (cmd or ""))
    help()
  end
end
