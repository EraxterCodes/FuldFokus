local addonName = ...

FF_DB = FF_DB or { iconSize = 16, selected = "", rules = {}, animate = true }
FFE = FFE or {}
FF.debug = false

local function ok(msg) print("|cffe5a472FF|r " .. tostring(msg)) end
local function dprint(msg) if FF.debug then ok(msg) end end

FF.BASE_DIR = "Interface\\AddOns\\FuldFokusEmotes\\Emotes\\FuldFokus\\"

local PREFIX = "FF"
local _pName, _pRealm = UnitFullName("player")
local playerFullName = (_pRealm and _pRealm ~= "" and (_pName .. "-" .. _pRealm)) or _pName
local playerName = _pName  -- realm-less
local peersFull = {}  -- ["Name-Realm"] = { sel="key", sz=16, at=time }
local peersBase = {}  -- ["Name"]       = { sel="key", sz=16, at=time }  -- last-writer-wins for duplicates
local detailsHooked = false
local ticker
local DETAILS_ATTRIBUTE_DAMAGE = _G.DETAILS_ATTRIBUTE_DAMAGE or 1
local lastSend = 0


--- Easter eggs ---

local function FFE_GetSpecIDByName(name)
  if not name or name == "" then return nil end

  local function unitMatches(u)
    if not UnitExists(u) then return false end
    local n, r = UnitName(u)
    if not n then return false end
    local full = (r and r ~= "") and (n .. "-" .. r) or n
    return (full == name) or (n == name)
  end

  -- Find a unit token for this name
  local unit
  if unitMatches("player") then
    unit = "player"
  else
    if IsInRaid() then
      for i = 1, 40 do if unitMatches("raid"..i) then unit = "raid"..i; break end end
    elseif IsInGroup() then
      for i = 1, 4 do if unitMatches("party"..i) then unit = "party"..i; break end end
    end
  end
  if not unit then return nil end

  local guid = UnitGUID(unit)

  -- Prefer Details' GUID->spec if available
  if guid and _G.Details and type(_G.Details.GetSpecFromGUID) == "function" then
    local specID = _G.Details:GetSpecFromGUID(guid)
    if specID and specID ~= 0 then
      return specID
    end
  end

  -- Player's own spec
  if unit == "player" then
    local spec = GetSpecialization()
    if spec then
      local id = GetSpecializationInfo(spec)
      if id and id ~= 0 then return id end
    end
  end

  -- Fall back to Inspect API for party/raid units (may be 0 if not cached)
  if type(GetInspectSpecialization) == "function" then
    local id = GetInspectSpecialization(unit)
    if id and id ~= 0 then return id end
  end

  return nil
end

local function FFE_IsLoxelName(name)
  local Dokke = "Lôxel"
  if not name or name == "" then return false end
  name = tostring(name)
  -- exact or substring (covers Name-Realm, surnames, etc.)
  return (name == Dokke) or (name:find(Dokke, 1, true) ~= nil)
end

-- ---------- Public helpers ----------

function FF.ResolveKey(key)
  if not key or key == "" then return nil end
  if key:find("\\") or key:find("^%d+$") then return key end
  local candidates = {
    FF.BASE_DIR .. key .. ".tga",
    FF.BASE_DIR .. key .. ".png",
    FF.BASE_DIR .. key .. ".blp",
  }
  local hasAPI = C_Texture and C_Texture.GetFileIDFromPath
  for _, p in ipairs(candidates) do
    if hasAPI then
      if C_Texture.GetFileIDFromPath(p) then return p end
    else
      return p
    end
  end
  return nil
end

function FF.TextureStringForKey(key, size)
  local path = FF.ResolveKey(key)
  if not path then return "" end
  size = size or (FF_DB and FF_DB.iconSize) or 16

  local metaMap = _G.TwitchEmotes_animation_metadata
  local meta = metaMap and metaMap[path] or nil

  -- If user disabled animation, render FIRST FRAME (idx = 0) for animated sheets.
  if (FF_DB and FF_DB.animate == false) and meta then
    -- 1) Prefer TwitchEmotes helper if present
    if type(_G.TwitchEmotes_BuildEmoteFrameString) == "function" then
      local s = _G.TwitchEmotes_BuildEmoteFrameString(path, meta, 0, size, size) -- frame 0
      if s and s:sub(1,2) == "|T" then
        -- force width/height in case helper injects its own
        s = s:gsub("^|T([^:]+):%d+:%d+(:?.*)|t$", function(tex, rest)
          return ("|T%s:%d:%d%s|t"):format(tex, size, size, rest or "")
        end)
      end
      if s and s ~= "" then return s end
    end

    -- 2) Manual crop of frame 0
    local frames = tonumber(meta.nFrames) or tonumber(meta.frames) or 0
    local cols   = tonumber(meta.columns) or tonumber(meta.cols) or 1
    local rows   = tonumber(meta.rows) or 0
    local texW   = tonumber(meta.imageWidth) or tonumber(meta.texW)
    local texH   = tonumber(meta.imageHeight) or tonumber(meta.texH)

    if frames and frames > 1 and texW and texH then
      if (not rows or rows == 0) and cols and cols > 1 then
        rows = math.ceil(frames / cols)
      elseif (not cols or cols == 0) and rows and rows > 1 then
        cols = math.ceil(frames / rows)
      end
      cols = cols or 1
      rows = rows or frames

      local idx    = 0 -- first frame
      local frameW = math.floor(texW / cols + 0.5)
      local frameH = math.floor(texH / rows + 0.5)
      local col    = idx % cols
      local row    = math.floor(idx / cols)

      local left   = col * frameW
      local right  = left + frameW
      local top    = row * frameH
      local bottom = top + frameH

      return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t")
        :format(path, size, size, texW, texH, left, right, top, bottom)
    end
    -- If no meta or couldn't crop, fall through to static.
  end

  -- Animation enabled: try helpers first
  if meta then
    if type(_G.TwitchEmotes_GetCurrentFrameNum) == "function"
       and type(_G.TwitchEmotes_BuildEmoteFrameString) == "function" then
      local frame = _G.TwitchEmotes_GetCurrentFrameNum(meta)
      local s = _G.TwitchEmotes_BuildEmoteFrameString(path, meta, frame, size, size)
      if s and s:sub(1,2) == "|T" then
        s = s:gsub("^|T([^:]+):%d+:%d+(:?.*)|t$", function(tex, rest)
          return ("|T%s:%d:%d%s|t"):format(tex, size, size, rest or "")
        end)
      end
      if s and s ~= "" then return s end
    end

    -- Manual animated frame (time-based)
    local frames = tonumber(meta.nFrames) or tonumber(meta.frames) or 0
    local cols   = tonumber(meta.columns) or tonumber(meta.cols) or 1
    local rows   = tonumber(meta.rows) or 0
    local fps    = tonumber(meta.framerate) or tonumber(meta.fps) or 0
    local texW   = tonumber(meta.imageWidth) or tonumber(meta.texW)
    local texH   = tonumber(meta.imageHeight) or tonumber(meta.texH)

    if frames and frames > 1 and fps and fps > 0 and texW and texH then
      if (not rows or rows == 0) and cols and cols > 1 then
        rows = math.ceil(frames / cols)
      elseif (not cols or cols == 0) and rows and rows > 1 then
        cols = math.ceil(frames / rows)
      end
      cols = cols or 1
      rows = rows or frames

      local t = (GetTime and GetTime() or 0)
      local idx = math.floor((t * fps) % frames)

      local frameW = math.floor(texW / cols + 0.5)
      local frameH = math.floor(texH / rows + 0.5)
      local col    = idx % cols
      local row    = math.floor(idx / cols)

      local left   = col * frameW
      local right  = left + frameW
      local top    = row * frameH
      local bottom = top + frameH

      return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t")
        :format(path, size, size, texW, texH, left, right, top, bottom)
    end
  end

  -- Static fallback (non-animated emotes or no meta)
  return ("|T%s:%d:%d|t"):format(path, size, size)
end


local function getEmoteForPlayer(name)
  if not name or name == "" then return "" end

  -- Easter egg: if enabled, force-render Dokkeren for Lôxel, without touching DB
  if FF_DB and FF_DB.easter ~= false then
    -- 1) Name-based: Lôxel -> Dokkeren
    if FFE_IsLoxelName(name) then
      return "Dokkeren"
    end

    -- 2) Spec-based: any Augmentation Evoker -> Auger
    local specID = FFE_GetSpecIDByName(name)
    if specID == 1473 then
      return "Auger"
    end
  end

  -- explicit per-player overrides (you can store with or without realm)
  if FF_DB.rules and FF_DB.rules[name] then
    local k = FF_DB.rules[name]
    if FF.ResolveKey(k) then return k end
  end
  
  -- Also check base name for rules if the lookup name includes realm
  if name:find("%-") then
    local baseName = name:gsub("%-.*", "")
    if FF_DB.rules and FF_DB.rules[baseName] then
      local k = FF_DB.rules[baseName]
      if FF.ResolveKey(k) then return k end
    end
  else
    -- Also check if there's a rule stored with realm for this base name
    if FF_DB.rules then
      for ruleName, k in pairs(FF_DB.rules) do
        if ruleName:gsub("%-.*", "") == name then
          if FF.ResolveKey(k) then return k end
        end
      end
    end
  end

  -- me
  if name == playerName or name == playerFullName then
    return FF_DB.selected or ""
  end

  -- someone else in group who has told us their selection
  -- Try full name first (for cross-realm players)
  local st = peersFull[name]
  if st and st.sel and st.sel ~= "" then
    return st.sel
  end
  
  -- If no match, try base name (for same-realm players)
  -- Extract base name if this is a full name, or use as-is if already base
  local baseName = name:gsub("%-.*", "")
  local baseSt = peersBase[baseName]
  if baseSt and baseSt.sel and baseSt.sel ~= "" then
    return baseSt.sel
  end

  return ""
end

local function anyAnimatedInUse()
  if FF_DB and FF_DB.animate == false then
    return false, 0
  end
  local function fpsForKey(k)
    if not k or k == "" then return 0 end
    local path = FF.ResolveKey(k)
    if not path then return 0 end
    local meta = _G.TwitchEmotes_animation_metadata and _G.TwitchEmotes_animation_metadata[path]
    local frames = meta and (tonumber(meta.nFrames) or tonumber(meta.frames)) or 0
    local fps = meta and (tonumber(meta.framerate) or tonumber(meta.fps)) or 0
    if frames and frames > 1 and fps and fps > 0 then return fps end
    return 0
  end
  local fastest = 0
  fastest = math.max(fastest, fpsForKey(FF_DB.selected))
  if FF_DB.rules then for _, k in pairs(FF_DB.rules) do fastest = math.max(fastest, fpsForKey(k)) end end
  for _, st in pairs(peersFull) do fastest = math.max(fastest, fpsForKey(st.sel)) end
  return fastest > 0, fastest
end

function FF.RefreshDetails()
  local Details = _G._detalhes or _G.Details
  if Details and Details.RefreshMainWindow then
    Details:RefreshMainWindow(-1, true)
  end
end

-- actively reapply nicknames (so icons show even if Details caches display names)
function FF.RefreshAllDisplayNames()
  local Details = _G._detalhes or _G.Details
  if not Details or not Details.GetCurrentCombat then return end
  local currentCombat = Details:GetCurrentCombat()
  if not currentCombat or not currentCombat.GetContainer then return end
  local actorContainer = currentCombat:GetContainer(DETAILS_ATTRIBUTE_DAMAGE)
  if not actorContainer or not actorContainer.ListActors then return end

  for _, actorObject in actorContainer:ListActors() do
    if actorObject and actorObject.Name and actorObject.SetDisplayName then
      local nick = Details:GetNickname(actorObject:Name(), false, true)
      if nick and nick ~= "" then actorObject:SetDisplayName(nick) end
    end
  end
end

function FF.UpdateTicker()
  if ticker then ticker:Cancel(); ticker = nil end

  -- If the whole feature is disabled OR animations are disabled, don't create a ticker
  if FF_DB.enabled == false or FF_DB.animate == false then
    return
  end

  local has, fps = anyAnimatedInUse()
  if has then
    local interval = 1 / math.min(fps, 30)
    ticker = C_Timer.NewTicker(interval, function()
      FF.RefreshAllDisplayNames()
      FF.RefreshDetails()
    end)
  end
end

function FF.SendState(force)
  local now = GetTime and GetTime() or 0
  if not force and (now - (lastSend or 0) < 1.5) then
    return
  end
  lastSend = now

  local chan = (IsInGroup(2) and "INSTANCE_CHAT") or (IsInRaid() and "RAID") or (IsInGroup() and "PARTY") or "GUILD"
  if C_ChatInfo and C_ChatInfo.IsAddonMessagePrefixRegistered and C_ChatInfo.IsAddonMessagePrefixRegistered("FF") then
    C_ChatInfo.SendAddonMessage("FF", (FF_DB.selected or "").."|"..tostring(FF_DB.iconSize or 16), chan)
    if FF.debug then print("|cffe5a472FF|r Sent state to " .. chan .. " (" .. (FF_DB.selected or "none") .. ", " .. tostring(FF_DB.iconSize) .. ")") end
  end
end

function FF.Clear()
  local oldSel  = FF_DB.selected or ""
  local oldSize = FF_DB.iconSize or 16

  FF_DB.selected = ""
  FF_DB.iconSize = 16

  ok(("Cleared. Emote='none', size=%d (was '%s' @ %d)"):format(
    FF_DB.iconSize, (oldSel ~= "" and oldSel or "none"), oldSize))

  C_Timer.After(0,   function() FF.RefreshAllDisplayNames(); FF.RefreshDetails() end)
  C_Timer.After(0.2, function() FF.SendState(true); FF.UpdateTicker() end)
  C_Timer.After(0.6, function() FF.RefreshAllDisplayNames(); FF.RefreshDetails() end)
end

function FF.SetSelectedEmote(k)
  if k == "none" or k == "" or not k then
    FF_DB.selected = ""
    ok("Cleared emote selection.")
  else
    FF_DB.selected = k
    local tex = (FF.TextureStringForKey and FF.TextureStringForKey(k, FF_DB.iconSize)) or ""
    if tex ~= "" then
      ok(("Emote set: %s  (key='%s', size=%d)"):format(tex, k, FF_DB.iconSize))
    else
      ok(("Emote set: '%s' (texture not resolved yet—may appear after reload)"):format(k))
    end
  end

  C_Timer.After(0,   function() FF.RefreshAllDisplayNames(); FF.RefreshDetails() end)
  C_Timer.After(0.2, function() FF.SendState(true); FF.UpdateTicker() end)
  C_Timer.After(0.6, function() FF.RefreshAllDisplayNames(); FF.RefreshDetails() end)
end

function FF.SetIconSize(n)
  n = tonumber(n)
  if not n then ok("Size must be a number between 8 and 64."); return end
  local old = FF_DB.iconSize
  FF_DB.iconSize = math.max(8, math.min(64, math.floor(n)))
  FF.RefreshAllDisplayNames()
  FF.RefreshDetails()
end

-- ---------- Details integration ----------

local function installDetailsHook()
  if detailsHooked then return end
  local detalhes = _G._detalhes or _G.Details
  if not detalhes then return end

  detalhes.ignore_nicktag = true
  local original = detalhes.GetNickname
  detailsHooked = true
  ok("Details hook installed.")

  -- Always prefix (some Details builds pass default=nil/true inconsistently)
  detalhes.GetNickname = function(self, name, default, silent)
  -- Helper: pass through to original and ensure realm removal on fallback
  local function passThrough()
    local result = original and original(self, name, default, silent)
    if type(result) == "string" and result ~= "" then
      return result
    end
    local shown = name or ""
    if detalhes.remove_realm_from_name and shown ~= "" then
      shown = shown:gsub("%-.*", "")
    end
    return shown
  end

  -- If disabled, behave like stock Details (no prefix), but still respect realm removal
  if FF_DB.enabled == false then
    return passThrough()
  end

  -- Enabled: build prefix and prepend to whatever Details would show
  local key = getEmoteForPlayer(name)
  local prefix = (key and key ~= "") and (FF.TextureStringForKey(key, FF_DB.iconSize) .. " ") or ""
  return prefix .. passThrough()
end
end

-- ---------- Events ----------

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("CHAT_MSG_ADDON")
f:RegisterEvent("GROUP_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

f:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == addonName then
      FF_DB.iconSize = FF_DB.iconSize or 16
      FF_DB.selected = FF_DB.selected or ""
      FF_DB.rules    = FF_DB.rules or {}
      if FF_DB.enabled == nil then FF_DB.enabled = true end
      if FF_DB.animate == nil then FF_DB.animate = true end
      if FF_DB.easter == nil then FF_DB.easter = true end
      dprint("Addon loaded. Current: selected='" .. (FF_DB.selected or "none") .. "', size=" .. tostring(FF_DB.iconSize))
    end

  elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
  -- slight delay so the client knows which chat channel we're in
  C_Timer.After(0.5, function() FF.SendState(true) end)
  FF.RefreshAllDisplayNames()
  FF.RefreshDetails()
  FF.UpdateTicker()

  elseif event == "PLAYER_LOGIN" then
    installDetailsHook()

    -- Hook Details.RefreshMainWindow to reapply display names right before drawing
    local Details = _G._detalhes or _G.Details
    if Details and not FF._refreshHooked and type(Details.RefreshMainWindow) == "function" then
      FF._refreshHooked = true
      local original = Details.RefreshMainWindow
      Details.RefreshMainWindow = function(self, instanceOrForce, bForceRefresh)
        FF.RefreshAllDisplayNames()
        return original(self, instanceOrForce, bForceRefresh)
      end
      dprint("RefreshMainWindow hook installed.")
    end

    FF.UpdateTicker()
    ok("Ready. Selected='" .. (FF_DB.selected == "" and "none" or FF_DB.selected) .. "', size=" .. tostring(FF_DB.iconSize) .. ". Try |cffffff00/ffe test|r.")
    C_Timer.After(1.0, FF.SendState)

  elseif event == "CHAT_MSG_ADDON" then
  local prefix, msg, _, sender = ...
  if prefix == PREFIX then
    -- Ignore own broadcasts (compare using full name)
    if sender == playerFullName then return end

    local sel, sz = strsplit("|", msg or "")
    local st = { sel = sel or "", sz = tonumber(sz) or 16, at = GetTime() }

    -- Store by full and base name
    peersFull[sender] = st
    local base = sender:gsub("%-.*", "")
    peersBase[base] = st

    if FF.debug then
      print("|cffe5a472FF|r Received state from " .. (sender or "?") .. ": " .. (sel or "none") .. "@" .. (sz or 16))
    end

    FF.RefreshAllDisplayNames()
    FF.RefreshDetails()
    FF.UpdateTicker()
  end

  else
    -- Helpful nudges during combat/roster changes
    FF.RefreshAllDisplayNames()
    FF.RefreshDetails()
    FF.UpdateTicker()
  end
end)
