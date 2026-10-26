-- RocketMeter | Party.lua
-- What the meter does NOT know about the group: item level, keystone and loot.
--
-- WHY THIS FILE EXISTS. Three scoreboard columns do not come from `C_DamageMeter`:
--
--   * the **item level** at the foot of the portrait -- it comes from inspection;
--   * each one's **keystone** -- it comes from communication between addons;
--   * the run's **loot** -- it comes from an event that only passes once.
--
-- None of the three is combat data, and so none of them fitted in `Data.lua`, which is the
-- meter's envelope. They live here, with one rule in common: **when it cannot be known, the
-- scoreboard shows empty** -- never a made-up number nor a generic icon the player would read
-- as a statement.
local ADDON, ns = ...

local Party = {}
ns.Party = Party

local issecretvalue = issecretvalue
local UnitName = UnitName
local UnitExists = UnitExists

--------------------------------------------------------------------------------
-- Item level: inspection
--------------------------------------------------------------------------------
-- The path is the usual one: ask for the unit's inspection,
-- wait for `INSPECT_READY` and read `C_PaperDollInfo.GetInspectItemLevel`. For the player himself nothing is
-- asked -- `GetAverageItemLevel` answers right away and is exact.
--
-- ⚠️ **Inspection has a server limit.** Asking for five people at once makes the client
-- drop the last ones silently, so the requests go out spaced, and the result stays cached
-- for a while: at the end of a key the gear no longer changes.
local INSPECT_GAP = 1.25         -- seconds between one inspection request and the next
local CACHE_TTL = 900            -- 15 min: within a run the gear does not change

local ilevelCache = {}           -- [nome] = { level = n, at = tempo }
local inspectQueue = {}
local inspecting = false

-- Declared here and written further down, with the other LibOpenRaid things: the item level
-- (which comes first in the file) and the keystone (which comes after) use the SAME lookup, and a `local`
-- referenced before its declaration becomes a global lookup -- `nil` at call time, silently.
local LibLookup

--- A short, readable name, or nil. The identity can come opaque in combat.
local function Readable(name)
    if name == nil or issecretvalue(name) or type(name) ~= "string" or name == "" then return nil end
    return ns.SplitName(name) or name
end

local function Remember(name, level)
    if not name or not level or level <= 0 then return end
    ilevelCache[name] = { level = level, at = GetTime and GetTime() or 0 }
end

--- Someone's known item level, or nil.
---
--- **nil is an answer**, and that is why the scoreboard draws a dash instead of a number: saying "-"
--- is saying "I do not know", and it is honest. A zero there would be read as "he is naked".
function Party.ItemLevel(name)
    name = Readable(name)
    if not name then return nil end

    if UnitName and UnitName("player") == name then
        if GetAverageItemLevel then
            local ok, _, equipped = pcall(GetAverageItemLevel)
            if ok and equipped and not issecretvalue(equipped) and equipped > 0 then
                Remember(name, equipped)
                return equipped
            end
        end
    end

    local entry = ilevelCache[name]
    if entry then
        local now = GetTime and GetTime() or 0
        if now - entry.at < CACHE_TTL then return entry.level end
    end

    -- ⚑ A SECOND SOURCE: LibOpenRaid. The report of 10/09/2026: *"não aparece o ilvl dos outros"* -- and the
    -- run recorded at 02:28 showed `ilevel` only on the player's own row, in a cross-realm
    -- LFG group.
    --
    -- Inspection is fragile by nature and does not say when it fails: it needs `CanInspect` (distance,
    -- the same phase), the server drops requests in bursts, and it is only fired on
    -- `GROUP_ROSTER_UPDATE` -- in a key the group does not change, so **it is one attempt only, at the worst
    -- possible moment** (the start, with everyone getting into position and a loading screen).
    --
    -- The lib has none of those limits: the data travels through the addon channel, works cross-realm
    -- and at any distance. It comes in AFTER the inspection, and not before, because the inspection reads the
    -- client directly -- when it answers, it is the more exact source of the two.
    local gear = LibLookup("GetAllUnitsGear", "GetUnitGear", name)
    local nivel = gear and gear.ilevel
    if type(nivel) == "number" and nivel > 0 then
        Remember(name, nivel)
        return nivel
    end
    return nil
end

local function ReadInspect(unit)
    if not C_PaperDollInfo or not C_PaperDollInfo.GetInspectItemLevel then return end
    local name = Readable(UnitName and UnitName(unit))
    if not name then return end

    local ok, level = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
    if ok and level and not issecretvalue(level) and level > 0 then
        Remember(name, level)
        if ns.Log then ns.Log.Add("ilvl", { quem = name, nivel = level }) end
    end
end

local function NextInspect()
    inspecting = false
    if #inspectQueue == 0 then return end

    -- (14/10) The player's own Inspect window is open: `ClearInspectPlayer` would empty it. Wait
    -- and try again after the gap.
    if InspectFrame and InspectFrame.IsShown and InspectFrame:IsShown() then
        inspecting = true
        C_Timer.After(INSPECT_GAP, NextInspect)
        return
    end
    local unit = table.remove(inspectQueue, 1)
    if not UnitExists or not UnitExists(unit) then return NextInspect() end
    if not CanInspect or not CanInspect(unit) then return NextInspect() end
    -- Known less than 15 minutes ago: nothing to ask (a raid's roster changes all the time).
    local known = Readable(UnitName and UnitName(unit))
    local entry = known and ilevelCache[known]
    if entry and (GetTime and GetTime() or 0) - entry.at < CACHE_TTL then return NextInspect() end

    inspecting = true
    -- `ClearInspectPlayer` before each request: without it the client may return the
    -- PREVIOUS unit's `INSPECT_READY`, and the item level ends up on the wrong row -- the
    -- worst possible defect here, because it does not look like a defect at all.
    if ClearInspectPlayer then pcall(ClearInspectPlayer) end
    pcall(NotifyInspect, unit)

    C_Timer.After(INSPECT_GAP, NextInspect)
end

--- Queues the whole group's inspection. Cheap and with no visible effect for the others.
function Party.RefreshItemLevels()
    if InCombatLockdown and InCombatLockdown() then return end
    if not NotifyInspect then return end

    inspectQueue = {}
    local size = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        for i = 1, size do inspectQueue[#inspectQueue + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, size - 1) do inspectQueue[#inspectQueue + 1] = "party" .. i end
    end

    if not inspecting then NextInspect() end
end

--------------------------------------------------------------------------------
-- Pedra angular
--------------------------------------------------------------------------------
-- The player's OWN one the client gives directly. The others' **exists in no API**: it
-- travels through the addon channel, and what distributes it is `LibOpenRaid-1.0` -- the library
-- several addons already bundle.
--
-- **RocketMeter does not bundle the library**, and the choice is deliberate: it is 3,660 lines of
-- third-party code, with a network protocol of its own, to fill one column. Instead it
-- ASKS whether it is already loaded -- which is true for whoever runs some addon that bundles it.
-- Without it, the column stays empty, and empty here is honest:
-- it means "nobody told me", not "he has no keystone".
local function OpenRaid()
    if not LibStub or not LibStub.GetLibrary then return nil end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibOpenRaid-1.0", true)
    if ok then return lib end
    return nil
end

--- Finds someone's entry in a LibOpenRaid table, with or without the realm in the name.
---
--- ⚑ THE LIB'S KEY HAS THE REALM, AND OURS DID NOT. That is what left the Keystone column with only the
--- player's own row filled (the report of 10/09/2026: *"também a pontuação e também a
--- pedra, só a minha aparece"*) -- mine comes from the `C_MythicPlus` path, which does not go through the lib.
---
--- Its two tables follow the same format, documented in the library's source:
--- **`[playerName-realm] = {information}`**. And the
--- lookup functions by unit do `GetUnitName(unitId, true) or unitId` -- passing "Gsm", which
--- is not a unit token, they look for the key "Gsm" in a table indexed by "Gsm-Dragonblight".
---
--- **It raises no error: it returns `nil`** -- and `nil` here cannot be told from "that player has no
--- keystone" or "I do not know his item level". That is what let the defect survive with nobody seeing.
---
--- Sweeping and matching by the part before the "-" settles both cases (with and without the realm) and does not depend on
--- our knowing anyone's realm -- information the meter may not bring.
--- @param todasFn string the name of the function that returns the whole table
--- @param umaFn string the name of the direct lookup function, used as a fallback
LibLookup = function(todasFn, umaFn, name)
    local lib = OpenRaid()
    if not lib then return nil end

    if lib[todasFn] then
        local ok, todas = pcall(lib[todasFn])
        if ok and type(todas) == "table" then
            for chave, info in pairs(todas) do
                if type(chave) == "string" and type(info) == "table"
                    and (ns.SplitName(chave) or chave) == name then
                    return info
                end
            end
        end
    end

    -- The fallback: the direct lookup, which works when the name already comes without the realm in its table.
    if lib[umaFn] then
        local ok, info = pcall(lib[umaFn], name)
        if ok and type(info) == "table" then return info end
    end
    return nil
end

--------------------------------------------------------------------------------
-- (!) THE LIBKEYSTONE PROTOCOL (26/09)
--
-- The user: *"os itens ainda não aparecem e nem as keystone de outros players"*. The saved +12 of
-- 26/09 had a keystone for ONE row -- the player's own. Cause, measured: every other keystone came
-- from LibOpenRaid, and nothing loaded it any more. So the column had no source at all.
--
-- LibKeystone (embedded by several addons) has a
-- one-line protocol, spoken here directly so nothing third-party has to be loaded:
--   prefix "LibKS", channel PARTY; "level,challengeMapID,rating" announces a key; "R" asks for them.
-- Everyone running it announces the NEW key on their own when they open the chest
-- (LibKeystone.lua, ITEM_PUSH / ITEM_CHANGED after CHALLENGE_MODE_COMPLETED), and answers "R".
-- When LibKeystone is loaded in THIS client it already answers for us, so we stay quiet then.
--------------------------------------------------------------------------------
local LKS_PREFIX = "LibKS"
local LKS_THROTTLE = 3
local lksKeys = {}               -- [short name] = { level, mapID, rating, at }
local lksRequestedAt = -math.huge

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, LKS_PREFIX)
end

local function LibKeystoneLoaded()
    if not (LibStub and LibStub.GetLibrary) then return false end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibKeystone", true)
    return ok and lib ~= nil
end

local function OwnKeystone()
    local level = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0
    local mapID = C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID
        and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
    local rating = 0
    if C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local ok, s = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, "player")
        if ok and type(s) == "table" and type(s.currentSeasonScore) == "number" then rating = s.currentSeasonScore end
    end
    return level or 0, mapID or 0, rating
end

---Our own key on the LibKS channel -- only when no LibKeystone here would do it.
local function AnnounceOwn(channel)
    if LibKeystoneLoaded() then return false end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage and IsInGroup and IsInGroup()) then return false end
    local level, mapID, rating = OwnKeystone()
    local ok = pcall(C_ChatInfo.SendAddonMessage, LKS_PREFIX,
        string.format("%d,%d,%d", level, mapID, math.floor(rating)), channel or "PARTY")
    return ok
end

---A LibKS message arrived.
function Party.OnLibKS(msg, channel, sender)
    if type(msg) ~= "string" then return end
    if msg == "R" then
        if channel == "PARTY" then AnnounceOwn("PARTY") end
        return
    end
    local l, m, r = msg:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
    local nome = Readable(sender)
    if not (l and nome) then return end
    lksKeys[nome] = { level = tonumber(l), mapID = tonumber(m), rating = tonumber(r),
                      at = GetTime and GetTime() or 0 }
    if ns.Log then ns.Log.Add("pedra", { quem = nome, nivel = tonumber(l), mapa = tonumber(m), via = "LibKS" }) end
    if ns.Scoreboard and ns.Scoreboard.RefreshExternalColumns then
        pcall(ns.Scoreboard.RefreshExternalColumns)
    end
end

---Ask the group for their keys on the LibKS channel (throttled like the library: 3 s).
local function RequestLibKS()
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage and IsInGroup and IsInGroup()) then return false end
    local agora = GetTime and GetTime() or 0
    if agora - lksRequestedAt < LKS_THROTTLE then return true end
    lksRequestedAt = agora
    local ok = pcall(C_ChatInfo.SendAddonMessage, LKS_PREFIX, "R", "PARTY")
    return ok
end

---@return number|nil nivel, number|nil mapID
function Party.Keystone(name)
    name = Readable(name)
    if not name then return nil end

    if UnitName and UnitName("player") == name and C_MythicPlus then
        local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID
            and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        if level and mapID then return level, mapID end
    end

    -- LibKS first: it is what the most common group addons send, and it needs nothing loaded here.
    local k = lksKeys[name]
    if k and k.level and k.level > 0 then return k.level, k.mapID end

    local info = LibLookup("GetAllKeystonesInfo", "GetKeystoneInfo", name)
    if not info or not info.level or info.level <= 0 then return nil end
    return info.level, info.challengeMapID
end

--- Asks the others for the keystone data through the LibOpenRaid channel.
---
--- The lib keeps what the OTHERS send, and they send when someone asks. Without the request, the
--- table may be empty in a session in which nobody else asked -- and the column vanishes with
--- nothing broken. Calling costs nothing: it is a `SendAddonMessage` to the group.
function Party.RequestKeystones()
    local pediuLKS = RequestLibKS()
    local lib = OpenRaid()
    if not lib then return pediuLKS end

    -- `RequestAllData` brings the GEAR along, and that is why it comes in here: the same trip to the
    -- addon channel that fetches the keystone settles the others' item level, which the inspection only
    -- gets sometimes. If it does not exist, the keystone request alone still holds.
    if lib.RequestAllData then pcall(lib.RequestAllData) end

    if not lib.RequestKeystoneDataFromParty then return pediuLKS end
    local ok, enviou = pcall(lib.RequestKeystoneDataFromParty)
    return (ok and enviou) or pediuLKS
end

--- Subscribes to the lib's notice: "so-and-so's keystone changed".
---
--- ⚑ THIS IS WHAT MAKES THE SCOREBOARD UPDATE BY ITSELF as the group opens the chest, which is the
--- behaviour the user described (10/09/2026): *"conforme os jogadores vão
--- abrindo o baú ele vai atualizando o placar"*. The new keystone only exists after the chest opens, and it is
--- at that instant that the lib broadcasts -- there is no capturing it before.
---
--- It subscribes once only: the lib keeps the subscription in a list and subscribing again would duplicate the call.
local assinado = false

function Party.WatchKeystones()
    if assinado then return true end

    local lib = OpenRaid()
    if not lib or not lib.RegisterCallback then return false end

    -- The lib calls `object[name](...)`, so it needs a table with the method by name.
    local ouvinte = {
        RocketMeterKeystoneUpdate = function()
            if ns.Scoreboard and ns.Scoreboard.RefreshExternalColumns then
                pcall(ns.Scoreboard.RefreshExternalColumns)
            end
        end,
    }

    local ok = pcall(lib.RegisterCallback, ouvinte, "KeystoneUpdate", "RocketMeterKeystoneUpdate")
    assinado = ok and true or false
    return assinado
end

--------------------------------------------------------------------------------
-- Saque
--------------------------------------------------------------------------------
local loot = {}                  -- [nome] = itemLink

--- The item someone got in this run, or nil.
function Party.Loot(name)
    name = Readable(name)
    return name and loot[name] or nil
end

function Party.ResetLoot()
    loot = {}
end

--- Keeps an item received, if it passes the filters.
---
--- The filters exist because the column is about **the piece the run yielded**: without them it
--- would show the first potion that fell into someone's lap.
function Party.NoteLoot(itemLink, playerName)
    local name = Readable(playerName)
    if not name or not itemLink or itemLink == "" then return end
    if not C_Item then return end

    local ok, _, _, _, _, _, itemType = pcall(C_Item.GetItemInfoInstant, itemLink)
    if not ok then return end
    if Enum and Enum.ItemClass then
        if itemType ~= Enum.ItemClass.Weapon and itemType ~= Enum.ItemClass.Armor then return end
    end

    -- An item that only binds on equip is a present for another character, not a reward of this
    -- run.
    if C_Item.IsItemBindToAccountUntilEquip then
        local okBind, bound = pcall(C_Item.IsItemBindToAccountUntilEquip, itemLink)
        if okBind and bound then return end
    end

    loot[name] = itemLink
    if ns.Log then ns.Log.Add("saque", { quem = name, item = itemLink }) end

    -- ⚑ AND IT TELLS THE SCOREBOARD, because the loot almost always arrives AFTER the run's capture. The
    -- log of 10/09 measured it: capture at 00:33:18, the group's loot at 00:33:20 and the player's
    -- own at 00:33:30. Without this notice the column is born empty and stays empty forever.
    if ns.Scoreboard and ns.Scoreboard.OnLoot then
        pcall(ns.Scoreboard.OnLoot, name, itemLink)
    end
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------
local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")
listener:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
listener:RegisterEvent("GROUP_ROSTER_UPDATE")
listener:RegisterEvent("CHAT_MSG_ADDON")
listener:RegisterEvent("CHALLENGE_MODE_COMPLETED")

listener:SetScript("OnEvent", function(_, event, ...)
    if event == "INSPECT_READY" then
        local guid = ...
        -- The event brings the GUID; the reading needs a unit token. Sweeping the group is
        -- cheap and it is the only way: there is no `UnitFromGUID`.
        local size = GetNumGroupMembers and GetNumGroupMembers() or 0
        local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
        for i = 1, size do
            local unit = prefix .. i
            local unitGuid = UnitGUID and UnitGUID(unit)
            if unitGuid ~= nil and not issecretvalue(unitGuid) and unitGuid == guid then
                ReadInspect(unit)
                break
            end
        end

    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        -- ⚠️ **THE DOCUMENTATION AND THE USE IN PRODUCTION DISAGREE ABOUT THE 5TH ARGUMENT.**
        --
        -- `LootDocumentation.lua:136-141` calls the payload `encounterID, itemID, itemLink,
        -- quantity, itemName, fileName`. A scoreboard running in production on this same patch reads
        -- `local _, _, itemLink, _, unitName = ...` -- that is, it treats the 5th as **the
        -- player's name**.
        --
        -- Two things weigh in favour of that use: the 6th field is called `fileName`, which is the
        -- classic name of the CLASS file ("WARRIOR"), and an item's name already travels inside the
        -- `itemLink` -- a 5th field repeating it would make no sense.
        --
        -- So the addon follows that use **and records what arrived**: the `saque cru` line in the
        -- log. (14/10) ANSWERED: the log recorded `quinto = "Gothmorg"`, `sexto =
        -- "DEMONHUNTER"`, and the game itself reads `playerName, className` (BossBannerToast.lua:194).
        local _, _, itemLink, _, quinto, sexto = ...
        if ns.Log then
            ns.Log.Add("saque cru", { link = itemLink, quinto = quinto, sexto = sexto })
        end
        Party.NoteLoot(itemLink, quinto)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = ...
        if prefix == LKS_PREFIX then Party.OnLibKS(msg, channel, sender) end

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- Our NEW key, once the chest gives it, the way LibKeystone does it -- only when it is not
        -- loaded here (then it does it itself). The key changes a moment after the chest.
        if not LibKeystoneLoaded() and C_Timer and C_Timer.After then
            for _, s in ipairs({ 5, 20, 60 }) do C_Timer.After(s, function() AnnounceOwn("PARTY") end) end
        end

    elseif event == "GROUP_ROSTER_UPDATE" then
        Party.RefreshItemLevels()
    end
end)

ns.PartyListener = listener
