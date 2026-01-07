local EMOTES = {"fest","DokkeGASM","EmilHuh2","dembWauv","juliehitler","juliefødder","Auger","Roloff","Lawnmower","juliegao","EraxterSmile","Dokkeren","Dokke","madsp","airtox","MMMM","dembFårEndeligPIIstedetForNæbbene","xddWalk","HappiJam","crunch","catPunchU","tasty","EmilHuh","NOW","ALO","eww","Bruhcool","strog","CLANKER","WarlockMening","Eyeroll","Flirt","SayThatAgain","cap","dogsittingverycomfortable","catsittingverycomfortablebutmentallypreparingtogobackintothemines","peepoPogClimbingTreeHard4House","Looking","catsittingverycomfortablegaming","CatDespair","ta","maga","Ragebait","NairyOK","nøddebrunt","manWithProbingCane","Stroxx","darioClassic","ffsejr","wolt","emilFører","OnlyFans","sniffLoot","StroxxTlf","darioSmil","magexdd","mortenSur","eddyPeak","dembSmile","dembRizz","dembDespair","dembd","osmanBruh","levMette","wwwww","Scaredge","LockIn","magiBrain","GigaNæb","kvidder","wikked","MONKA","kaj","iAsk","GAMBAADDICT","fflol","ffActually","catsittingverycomfortable","pause","magiBoksen","EraxterSus","FuldDonk","EmilVinder","flyvebjørn","næb","naeb","fugl","doraGlad","doraW","skodbutik","rema","BobHehe","EmilOk","MortenW","magitlf","FuldFokus","EddySug","EmilMagi","MortenKniv","MortenSug" }
local BASE = "Interface\\AddOns\\FuldFokus\\Emotes\\FuldFokus\\"
local SIZE = ":28:28"

local ANIMATED = {
    Eyeroll = {nFrames=20, frameWidth=32, frameHeight=32, imageWidth=32, imageHeight=640, framerate=8, pingpong=false },
    FuldDonk = { nFrames=2, frameWidth=64, frameHeight=64, imageWidth=64, imageHeight=128, framerate=8, pingpong=false },
    CLANKER = {nFrames = 83, frameWidth = 50, frameHeight = 32, imageWidth = 50, imageHeight = 2656, framerate = 33, pingpong = false},
    NOW = {nFrames = 45, frameWidth = 128, frameHeight = 128, imageWidth = 128, imageHeight = 5760, framerate = 33, pingpong = false},
    xddWalk = {nFrames = 10, frameWidth = 64, frameHeight = 64, imageWidth = 64, imageHeight = 640, framerate = 33, pingpong = false},
    HappiJam = {nFrames = 8, frameWidth = 128, frameHeight = 128, imageWidth = 128, imageHeight = 1024, framerate = 17, pingpong = false},
    crunch = {nFrames = 46, frameWidth = 128, frameHeight = 128, imageWidth = 128, imageHeight = 5888, framerate = 25, pingpong = false},
    catPunchU = {nFrames = 51, frameWidth = 128, frameHeight = 128, imageWidth = 128, imageHeight = 6528, framerate = 25, pingpong = false},
    tasty = {nFrames = 30, frameWidth = 64, frameHeight = 64, imageWidth = 64, imageHeight = 1920, framerate = 25, pingpong = false}, 
    Lawnmower = {nFrames = 49, frameWidth = 64, frameHeight = 64, imageWidth = 64, imageHeight = 3136, framerate = 20, pingpong = false}
}

local WIDE_EMOTES = {
    ["catsittingverycomfortablearoundacampfirewithitsfriends"] = { width = 28, height = 112 },
    ["catsittingverycomfortablearoundacampfirewithitsfriendssingingsongsandtoastingmarshmallows"] = { width = 28, height = 112 },
    ["catsittingverycomfortablearounda75kwdieselgeneratorwithitsfriends"] = { width = 28, height = 112 },
    ["dotdotdot"]= { width = 28, height = 112 },
    ["magexddWide"]= { width = 28, height = 84 },
    ["redoing"]= { width = 28, height = 56 },
    ["checkUpdates"] = { width = 28, height = 56 },
    ["cinema"] = { width = 32, height = 85 },
    ["-aura"] = {width = 32, height = 84},
    ["+aura"] = {width = 32, height = 84},
    ["hattrick"] = {width = 32, height = 84},
    ["Warlocks"] = {width = 32, height = 84},
    ["oddocopypaste"] = { width = 42, height = 124 },
}

local function add_to_autocomplete(ids)
    Emoticons_Settings = Emoticons_Settings or {}
    Emoticons_Settings["ENABLE_AUTOCOMPLETE"] = true
    if AllTwitchEmoteNames then
        local excluded = {}
        if TwitchEmotes_ExcludedSuggestions then
            for _, e in ipairs(TwitchEmotes_ExcludedSuggestions) do excluded[e]=true end
        end
        local present = {}
        for _, name in ipairs(AllTwitchEmoteNames) do present[name]=true end
        for _, id in ipairs(ids) do
            if not excluded[id] and not present[id] then
                table.insert(AllTwitchEmoteNames, id)
            end
        end
        table.sort(AllTwitchEmoteNames)
    else
        Emoticons_SetAutoComplete(true)
    end
end

local function integrate()
    TwitchEmotes_defaultpack = TwitchEmotes_defaultpack or {}
    TwitchEmotes_emoticons   = TwitchEmotes_emoticons   or {}
    TwitchEmotes_dropdown_options = TwitchEmotes_dropdown_options or {}
    TwitchEmotes_animation_metadata = TwitchEmotes_animation_metadata or {}
    Emoticons_Settings = Emoticons_Settings or {}

    for _, id in ipairs(EMOTES) do
        local path = BASE .. id .. ".tga" .. SIZE
        TwitchEmotes_defaultpack[id] = path
        TwitchEmotes_emoticons[id] = id
        TwitchEmotes_emoticons[":"..id..":"] = id
    end

    local wideIds = {}
    for id, meta in pairs(WIDE_EMOTES) do
        local w = (meta and meta.width) or 56   -- sensible wide default
        local h = (meta and meta.height) or 28  -- default to normal height
        TwitchEmotes_defaultpack[id] = BASE .. id .. ".tga:" .. w .. ":" .. h
        TwitchEmotes_emoticons[id] = id
        TwitchEmotes_emoticons[":"..id..":"] = id
        table.insert(wideIds, id)
    end

    for id, meta in pairs(ANIMATED) do
        local fullpath = BASE .. id .. ".tga"
        TwitchEmotes_animation_metadata[fullpath] = {
            nFrames = meta.nFrames,
            frameWidth = meta.frameWidth,
            frameHeight = meta.frameHeight,
            imageWidth = meta.imageWidth,
            imageHeight = meta.imageHeight,
            framerate = meta.framerate,
            pingpong = meta.pingpong,
        }
    end

    local function ensureCategory(catName)
        for i, cat in ipairs(TwitchEmotes_dropdown_options) do
            if type(cat) == "table" and cat[1] == catName then
                for j = #cat, 2, -1 do cat[j] = nil end
                return i, cat
            end
        end
        table.insert(TwitchEmotes_dropdown_options, { catName })
        return #TwitchEmotes_dropdown_options, TwitchEmotes_dropdown_options[#TwitchEmotes_dropdown_options]
    end

    local ALL_IDS = {}
    for _, id in ipairs(EMOTES) do table.insert(ALL_IDS, id) end
    for _, id in ipairs(wideIds) do table.insert(ALL_IDS, id) end

    local perCat = 15
    local numCats = math.ceil(#ALL_IDS / perCat)
    local createdCatIndexes = {}

    for c = 1, numCats do
        local catName = (c == 1) and "FuldFokus" or ("FuldFokus" .. c)
        local idx, cat = ensureCategory(catName)
        table.insert(createdCatIndexes, idx)

        local startIdx = (c - 1) * perCat + 1
        local endIdx   = math.min(c * perCat, #ALL_IDS)
        for i = startIdx, endIdx do
            table.insert(cat, ALL_IDS[i])
        end
    end

    Emoticons_Settings["FAVEMOTES"] = Emoticons_Settings["FAVEMOTES"] or {}
    for _, catIndex in ipairs(createdCatIndexes) do
        Emoticons_Settings["FAVEMOTES"][catIndex] = true
    end

    add_to_autocomplete(ALL_IDS)
end


local function escpattern(x)
    return (x:gsub("%%","%%%%")
             :gsub("%^","%%^")
             :gsub("%$","%%$")
             :gsub("%(","%%(")
             :gsub("%)","%%)")
             :gsub("%.","%%.")
             :gsub("%[","%%[")
             :gsub("%]","%%]")
             :gsub("%*","%%*")
             :gsub("%+","%%+")
             :gsub("%-","%%-")
             :gsub("%?","%%?"))
end

local function FF_Animator_UpdateEmoteInFontString(fontstring, widthOverride, heightOverride, fixedFrame)
    local txt = fontstring:GetText()
    if not txt then return end
    for emoteTextureString in txt:gmatch("(|TInterface\\AddOns\\FuldFokusEmotes\\Emotes.-|t)") do
        local imagepath = emoteTextureString:match("|T(Interface\\AddOns\\FuldFokusEmotes\\Emotes.-%.tga).-|t")
        local animdata = TwitchEmotes_animation_metadata[imagepath]
        if animdata then
            local framenum = fixedFrame ~= nil and fixedFrame or TwitchEmotes_GetCurrentFrameNum(animdata)
            local replacement
            if widthOverride or heightOverride then
                replacement = TwitchEmotes_BuildEmoteFrameStringWithDimensions(imagepath, animdata, framenum, widthOverride or animdata.frameWidth, heightOverride or animdata.frameHeight)
            else
                replacement = TwitchEmotes_BuildEmoteFrameString(imagepath, animdata, framenum)
            end
            local nTxt = txt:gsub(escpattern(emoteTextureString), replacement)
            if fontstring.messageInfo ~= nil then fontstring.messageInfo.message = nTxt end
            fontstring:SetText(nTxt)
            txt = nTxt
        end
    end
end

local FF_TimeSince = 0
local FF_Frame = CreateFrame("Frame")
FF_Frame:SetScript("OnUpdate", function(_, elapsed)
    FF_TimeSince = FF_TimeSince + elapsed
    if FF_TimeSince >= 0.033 then
        for _, frameName in pairs(CHAT_FRAMES) do
            for _, visibleLine in ipairs(_G[frameName].visibleLines) do
                if _G[frameName]:IsShown() and visibleLine.messageInfo ~= TwitchEmotes_HoverMessageInfo then
                    FF_Animator_UpdateEmoteInFontString(visibleLine, 28, 28, nil)
                end
            end
        end
        if EditBoxAutoCompleteBox and EditBoxAutoCompleteBox:IsShown() and EditBoxAutoCompleteBox.existingButtonCount then
            for i = 1, EditBoxAutoCompleteBox.existingButtonCount do
                local cBtn = EditBoxAutoComplete_GetAutoCompleteButton(i)
                if cBtn:IsVisible() then
                    FF_Animator_UpdateEmoteInFontString(cBtn, 16, 16, nil)
                else
                    break
                end
            end
        end
        FF_TimeSince = 0
    end
end)

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", integrate)
