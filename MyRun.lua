-- RocketMeter | MyRun.lua
-- "Minha corrida": what THIS player did in a key or a raid, fight by fight, and what cost.
--
-- (!) WHY A SCREEN OF ONE PLAYER (01/10). The game gives an addon far more of the local player
-- than of anyone else: every cast with its time (read in a real key: 6,665 of the player, all
-- readable; 3,035 of the four others, all secret), the recap of a death blow by blow, and the
-- meter's own numbers. The user, once told that the others' data is hidden: *"vamos mudar essa
-- janela (...) uma tela individual do jogador, o que ele fez na mítica (parcial e total) e coisas
-- que pode melhorar (...) cada um joga com sua role, mostra os dados de sua role"*.
--
-- WHAT IS RECORDED, and from where:
--   * the fights: PLAYER_REGEN_DISABLED/ENABLED; a boss is ENCOUNTER_START/END around a fight;
--     at the end of each fight, the id of the newest session the meter lists, to ask the
--     meter about THAT fight later (`GetCombatSessionFromID`; the meter forgets old ones);
--   * the player's own casts (UNIT_SPELLCAST_SUCCEEDED for "player"), with the second of the
--     run; the gaps between casts in combat longer than GAP_SECONDS ("standing there");
--   * potions and the healthstone: a cast whose spell is the spell of an item in the bags
--     (C_Item.GetItemSpell), the item being a Consumable of the Potion subclass, or the
--     healthstone (item 5512);
--   * the player's own deaths, from the meter's Deaths metric read at the end of the fight,
--     with the recap: what killed and the hardest blow (Blizzard_DeathRecap.lua: first event =
--     the killer, largest amount = the hardest);
--   * the game's own list of important spells of the spec, from the Cooldown Manager
--     (C_CooldownViewer, categories Essential and Utility) with the base cooldown of each, for
--     "used / fitted"; only spells with a cooldown of COOLDOWN_MIN or more count as a cooldown.
--   * at the end of the run and of EACH FIGHT, the meter's numbers of the local player, kept in
--     the fight itself (`f.m`, one second after the combat, when they can be read). The filter
--     by boss and the chart by fight read from there, not from the meter's memory of old fights
--     (01/10: what Warcraft Logs shows per pull, as far as the game lets an addon go).
--
-- WHAT IS NOT: anything of the other players beyond what the meter gives (their casts are
-- secret), and a damage curve over time (the meter has no event stream).
--
-- The run is kept in memory while it happens and SAVED at its end (RocketMeterRunsDB.myRuns,
-- the last HISTORY_SIZE, per character), compacted: casts become counts per spell per fight.
local ADDON, ns = ...
local L = ns.L

local MyRun = {}
ns.MyRun = MyRun

local GAP_SECONDS = 5           -- a gap between casts in combat longer than this is "standing there"
local PREPULL_SECONDS = 3       -- a cast or potion this close before a fight belongs to it (pre-cast, pre-pot)
local COOLDOWN_MIN = 45         -- a spell with a shorter base cooldown is rotation, not a cooldown
local HISTORY_SIZE = 8
local HEALTHSTONE_ITEM = 5512
local MAX_TAKEN_SPELLS = 25
local MAX_FIGHT_SPELLS = 12     -- the damage taken by spell kept with each fight (20/10: 6 -> 12, Warcraft Logs' tab)
local METRIC_KEYS = { "damage", "healing", "absorbs", "taken", "avoidable", "interrupts", "dispels" }
local MAX_RECAP_EVENTS = 10     -- what the game's recap holds (read in a real key)

-- (!) EVERY KIND OF CONTENT IS RECORDED (07/10). The screen only had something to say in a key
-- or a raid: `Start` was called by CHALLENGE_MODE_START and by the first boss of a raid, and
-- nowhere else. The user: *"quando não estamos em DG a informação é bem pobre, seria legal
-- tentar chegar perto do que aparece nas DGs (...) delve, mundo aberto"*. Out of those two the
-- screen said "start a key or a raid", or showed the last key as if it were now.
--
-- So a run now starts BY ITSELF at the first fight wherever the player is, and is named by
-- where that is (`MyRun.Context`):
--   delve      `C_PartyInfo.IsDelveInProgress`, with its tier (`C_DelvesUI.GetActiveDelveTier`)
--   dungeon    a party instance that is not a key (normal, heroic, mythic, follower, timewalking)
--   scenario   any other scenario
--   pvp        a battleground or an arena
--   world      everywhere else, one session per ZONE
-- It ends when the player leaves that place (another zone, another instance), and an open-world
-- session also after WORLD_IDLE without a fight: the next fight is another session. A key or a
-- raid still starts as before and is never interrupted by this.
--
-- The numbers of such a run are the SUM OF ITS FIGHTS (`f.m`, kept at the end of each), not the
-- meter's "overall": the meter's overall runs from its last reset, which out of a key is
-- whenever the player last cleared it, and would not be this session.
local AUTO = { delve = true, dungeon = true, scenario = true, pvp = true, world = true }
local WORLD_IDLE = 600          -- an open-world session ends after this long without a fight
local MAX_WORLD_SAVED = 3       -- open-world sessions kept in the history, so they do not push the keys out

local run                       -- the run in progress (or the last one, until a new one starts)
local itemSpells = {}           -- [spellID] = { itemID, kind } from the bags
local bagsDirty = true

local function Readable(v) return v ~= nil and not issecretvalue(v) end
local function Num(v) return Readable(v) and type(v) == "number" and v or nil end

--------------------------------------------------------------------------------
-- The player: role, spec, class
--------------------------------------------------------------------------------
---"TANK", "HEALER" or "DAMAGER": the role assigned in the group, else the role of the spec.
function MyRun.Role()
    local role
    if UnitGroupRolesAssigned then
        local ok, r = pcall(UnitGroupRolesAssigned, "player")
        if ok and (r == "TANK" or r == "HEALER" or r == "DAMAGER") then role = r end
    end
    if not role then
        local index = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
        if index and GetSpecializationRole then
            local ok, r = pcall(GetSpecializationRole, index)
            if ok and (r == "TANK" or r == "HEALER" or r == "DAMAGER") then role = r end
        end
    end
    return role or "DAMAGER"
end

local function SpecName()
    local index = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization and C_SpecializationInfo.GetSpecialization()
    if not index then return nil, nil end
    local get = C_SpecializationInfo.GetSpecializationInfo
    if not get then return nil, nil end
    local ok, id, name, _, icon = pcall(get, index)
    if ok and type(name) == "string" then return name, icon end
    return nil, nil
end

--------------------------------------------------------------------------------
-- Items in the bags: which spell is a potion, which is the healthstone
--------------------------------------------------------------------------------
local function ScanBags()
    bagsDirty = false
    itemSpells = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemID
            and C_Item and C_Item.GetItemSpell and C_Item.GetItemInfoInstant) then return end
    for bag = 0, 4 do
        local okN, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (okN and type(slots) == "number" and slots or 0) do
            local okI, itemID = pcall(C_Container.GetContainerItemID, bag, slot)
            if okI and type(itemID) == "number" then
                local okS, _, spellID = pcall(C_Item.GetItemSpell, itemID)
                if okS and type(spellID) == "number" then
                    local kind
                    if itemID == HEALTHSTONE_ITEM then
                        kind = "healthstone"
                    else
                        local okC, _, _, _, _, _, classID, subclassID = pcall(C_Item.GetItemInfoInstant, itemID)
                        -- Consumable (0) / Potion (1): the game's own item classes.
                        if okC and classID == 0 and subclassID == 1 then kind = "potion" end
                    end
                    if kind then itemSpells[spellID] = { itemID = itemID, kind = kind } end
                end
            end
        end
    end
end

---A potion the player carries, for the icon of "potion not used": the item id, or nil.
function MyRun.KnownPotion()
    if bagsDirty then pcall(ScanBags) end
    local best
    for _, item in pairs(itemSpells) do
        if item.kind == "potion" and (not best or item.itemID < best) then best = item.itemID end
    end
    return best
end

---For the harness: pretend the bags hold these.
function MyRun.__setItemSpells(t) itemSpells = t or {}; bagsDirty = false end

--------------------------------------------------------------------------------
-- The game's cooldown list
--------------------------------------------------------------------------------
---The important spells of the spec, from the game's Cooldown Manager, with the base cooldown.
---@return table[] { spellID, name, cooldown (seconds), charges, category = "essential"|"utility" }
function MyRun.ReadCooldowns()
    local out = {}
    if not (C_CooldownViewer and C_CooldownViewer.GetCooldownViewerCategorySet
            and C_CooldownViewer.GetCooldownViewerCooldownInfo) then return out end
    local seen = {}
    local function Add(spellID, base, category)
        seen[spellID] = true
        local okB, ms = pcall(GetSpellBaseCooldown or error, spellID)
        local cd = okB and type(ms) == "number" and ms / 1000 or 0
        local charges
        if C_Spell and C_Spell.GetSpellCharges then
            local okC, c = pcall(C_Spell.GetSpellCharges, spellID)
            if okC and type(c) == "table" and type(c.maxCharges) == "number" then charges = c.maxCharges end
        end
        local name = C_Spell and C_Spell.GetSpellName and select(2, pcall(C_Spell.GetSpellName, spellID))
        out[#out + 1] = { spellID = spellID, name = type(name) == "string" and name or ("#" .. spellID),
            cooldown = cd, charges = charges or 1, category = category, base = base,
            defensive = MyRun.IsDefensive(spellID, base) or nil }
    end
    for _, cat in ipairs({ { "essential", 0 }, { "utility", 1 } }) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat[2], false)
        for i = 1, (ok and type(ids) == "table" and #ids or 0) do
            local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, ids[i])
            local spellID = okI and type(info) == "table" and (info.overrideSpellID or info.spellID) or nil
            if type(spellID) == "number" and not seen[spellID] and (info.isKnown == nil or info.isKnown == true) then
                Add(spellID, info.spellID, cat[1])
            end
        end
    end
    -- (21/10) THE DEFENSIVES THE COOLDOWN MANAGER DOES NOT LIST, so a death can say which were ready
    -- (Data/DefensiveSpells.lua, from the game's tables). Only the ones this character knows.
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        for id in pairs(type(ns.DefensiveSpells) == "table" and ns.DefensiveSpells or {}) do
            if not seen[id] then
                local ok, known = pcall(C_SpellBook.IsSpellKnown, id)
                if ok and known == true then Add(id, id, "defensive") end
            end
        end
    end
    return out
end

--------------------------------------------------------------------------------
-- The run
--------------------------------------------------------------------------------
local function Now() return GetTime and GetTime() or 0 end

local function Elapsed()
    if not run then return nil end
    local t = Now() - run.startedAt
    return t < 0 and 0 or t
end

local function NewestSessionID()
    if not (C_DamageMeter and C_DamageMeter.GetAvailableCombatSessions) then return nil end
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(list) ~= "table" then return nil end
    local best
    for i = 1, #list do
        local id = Num(list[i].sessionID)
        if id and (not best or id > best) then best = id end
    end
    return best
end

---Where the player is, as the kind of run it would be.
---@return string kind "key", "raid", "delve", "dungeon", "scenario", "pvp" or "world"
---@return string|nil name the instance, or the zone
---@return number|nil tier the delve's tier
---@return string|nil detail the difficulty's name (a dungeon)
function MyRun.Context()
    local name, instanceType, difficultyName
    if GetInstanceInfo then
        local ok, n, t, _, dn = pcall(GetInstanceInfo)
        if ok then
            name = type(n) == "string" and n ~= "" and n or nil
            instanceType = type(t) == "string" and t or nil
            difficultyName = type(dn) == "string" and dn ~= "" and dn or nil
        end
    end
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and active == true then return "key", name end
    end
    if C_PartyInfo and C_PartyInfo.IsDelveInProgress then
        local ok, delve = pcall(C_PartyInfo.IsDelveInProgress)
        if ok and delve == true then
            local tier
            if C_DelvesUI and C_DelvesUI.GetActiveDelveTier then
                local okT, info = pcall(C_DelvesUI.GetActiveDelveTier)
                if okT then tier = type(info) == "table" and Num(info.tier) or Num(info) end
            end
            return "delve", name, (tier and tier > 0) and tier or nil
        end
    end
    if instanceType == "raid" then return "raid", name end
    if instanceType == "party" then return "dungeon", name, nil, difficultyName end
    if instanceType == "scenario" then return "scenario", name end
    if instanceType == "pvp" or instanceType == "arena" then return "pvp", name end
    local zone
    if GetRealZoneText then
        local ok, z = pcall(GetRealZoneText)
        if ok and type(z) == "string" and z ~= "" then zone = z end
    end
    return "world", zone
end

---Is this kind of run one that starts and ends by itself?
function MyRun.IsAuto(kind) return AUTO[kind] == true end

---Where a run was, as the screen writes it: the key with its level, the delve with its tier,
---the dungeon with its difficulty, the open world with its zone.
function MyRun.Where(r)
    if type(r) ~= "table" then return "" end
    local name = r.name or ""
    if r.kind == "world" then
        return name ~= "" and format("%s · %s", L["Open world"], name) or L["Open world"]
    elseif r.kind == "delve" then
        return (name ~= "" and name or L["Delve"]) .. (r.tier and (" · " .. format(L["Tier %d"], r.tier)) or "")
    elseif r.kind == "dungeon" then
        return name .. (r.detail and (" · " .. r.detail) or "")
    end
    return name .. (r.level and (" +" .. r.level) or "")
end

---Called when a fight starts: opens a run for where the player is, when none is open, and
---closes the one that was open somewhere else (or an open-world one left idle).
function MyRun.AutoStart()
    local kind, name, tier, detail = MyRun.Context()
    if not AUTO[kind] then return false end
    if run and not run.finished then
        -- A key or a raid in progress owns the recording.
        if not AUTO[run.kind] then return false end
        local last = run.fights[#run.fights]
        local idle = run.kind == "world" and not run.open and last and last.e
            and (Elapsed() - last.e) > WORLD_IDLE
        if run.kind == kind and run.name == name and not idle then return false end
        MyRun.Stop(nil)
    end
    MyRun.Start(kind, name, nil)
    run.tier, run.detail = tier, detail
    return true
end

---Called when the player changes place out of combat: a run that belongs to another place ends.
function MyRun.AutoStop()
    if not run or run.finished or not AUTO[run.kind] or run.open then return false end
    if InCombatLockdown and InCombatLockdown() then return false end
    local kind, name = MyRun.Context()
    if kind == run.kind and name == run.name then return false end
    MyRun.Stop(nil)
    return true
end

---Starts a run. `kind` is "key", "raid" or one of the kinds that start by themselves
---(`MyRun.Context`); `name` the dungeon, raid or zone; `level` the key level.
function MyRun.Start(kind, name, level)
    -- A session that was being recorded by itself ends here, with what it had.
    if run and not run.finished and AUTO[run.kind] then pcall(MyRun.Stop, nil) end
    local class
    if UnitClassBase then
        local ok, c = pcall(UnitClassBase, "player")
        if ok and type(c) == "string" then class = c end
    end
    if not class and UnitClass then
        local ok, _, c = pcall(UnitClass, "player")
        if ok and type(c) == "string" then class = c end
    end
    local spec, specIcon = SpecName()
    run = {
        kind = kind or "key", name = name, level = level,
        startedAt = Now(), date = date and date("%Y-%m-%d %H:%M") or "",
        -- (20/10) the second on the clock, for tools/meter_timeline.py to find the run in the game's combat log
        at = time and time() or nil,
        role = MyRun.Role(), class = class, spec = spec, specIcon = specIcon,
        player = UnitName and UnitName("player") or "",
        fights = {}, casts = {}, items = {}, gaps = {}, deaths = {}, kinds = true,
        cooldowns = MyRun.ReadCooldowns(),
        lastCast = nil, open = nil, encounter = nil, finished = false,
    }
    -- (14/10) The meter's overall only clears when the player clears it: the deaths already in it
    -- are of the runs before (a 6 s scenario saved with the 3 deaths of the delve before it).
    run.oldRecaps = {}
    if ns.Data and ns.Data.GetDeathList then
        local ok, list = pcall(ns.Data.GetDeathList, 1)
        for _, d in ipairs(ok and list or {}) do
            if d.local_ and d.recap then run.oldRecaps[d.recap] = true end
        end
    end
    if bagsDirty then pcall(ScanBags) end
    -- (20/10) the character sheet and the gear at the start, as Warcraft Logs' summary shows them
    local okS, stats = pcall(MyRun.ReadStats)
    run.stats = okS and stats or nil
    local okG, gear = pcall(MyRun.ReadGear)
    run.gear = okG and gear or nil
    if InCombatLockdown() then MyRun.OnCombatStart() end
end

-- The gear slots, in the order of the character sheet's two columns and the weapons (shirt and tabard left out).
local GEAR_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
MyRun.GEAR_SLOTS = GEAR_SLOTS

---The character sheet: the primary stat (the highest of strength, agility and intellect), stamina, and the
---rating of each secondary with its percent. Read the way RocketLab reads it (Snapshot.lua, checked in game).
function MyRun.ReadStats()
    local function N(v) return Readable(v) and type(v) == "number" and v or nil end
    local s = {}
    local best, which = -1, nil
    for _, index in ipairs({ 1, 2, 4 }) do
        local v = N(select(2, UnitStat("player", index)))
        if v and v > best then best, which = v, index end
    end
    s.primary, s.primaryStat = which and best or nil, which
    s.stamina = N(select(2, UnitStat("player", 3)))
    s.crit, s.critPct = N(GetCombatRating(CR_CRIT_SPELL)), N(GetCritChance())
    s.haste, s.hastePct = N(GetCombatRating(CR_HASTE_SPELL)), N(GetHaste())
    s.mastery, s.masteryPct = N(GetCombatRating(CR_MASTERY)), N(GetMasteryEffect())
    local versBonus = N(GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE))
    local versExtra = N(GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE))
    s.versatility, s.versatilityPct = N(GetCombatRating(CR_VERSATILITY_DAMAGE_DONE)), versBonus and (versBonus + (versExtra or 0)) or nil
    s.avoidance = N(GetCombatRating(CR_AVOIDANCE))
    s.leech = N(GetCombatRating(CR_LIFESTEAL))
    s.speed = N(GetCombatRating(CR_SPEED))
    if GetAverageItemLevel then s.ilvl = N(select(2, GetAverageItemLevel())) end
    return s
end

---The items worn: `{ slot, link, ilvl }` in the order of GEAR_SLOTS. The link carries the enchant and the gems; the
---screen asks the game's tooltip for them.
function MyRun.ReadGear()
    local out = {}
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink("player", slot)
        if Readable(link) and type(link) == "string" then
            local ilvl = C_Item and C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(link)
            out[#out + 1] = { slot = slot, link = link, ilvl = Readable(ilvl) and ilvl or nil }
        end
    end
    return out
end

---Is a run being recorded?
function MyRun.IsActive() return run ~= nil and not run.finished end

---The run in memory: the one happening, or the last one finished.
function MyRun.Current() return run end

function MyRun.OnCombatStart()
    if not run or run.finished or run.open then return end
    run.open = { s = Elapsed(), boss = run.encounter and run.encounter.name or nil, enc = run.encounter and run.encounter.id or nil }
    run.lastCast = nil
end

function MyRun.OnCombatEnd()
    if not run or run.finished or not run.open then return end
    local f = run.open
    f.e = Elapsed()
    f.sid = NewestSessionID()
    run.fights[#run.fights + 1] = f
    run.open = nil
    -- A death of the player in this fight, with its recap: read now, while it is fresh.
    pcall(MyRun.ReadDeaths)
    -- The player's numbers of THIS fight, one second later: at the event itself the meter's
    -- values can still be secret. A new fight inside that second leaves this one without them.
    local doRun = run
    local function Snapshot()
        -- (20/10) development only: every session the meter lists, by id (Log.NoteSessions), also when a new
        -- fight has begun and this one goes without its reading
        if ns.Log and ns.Log.NoteSessions then pcall(ns.Log.NoteSessions) end
        if run ~= doRun or doRun.open or doRun.fights[#doRun.fights] ~= f then return end
        if InCombatLockdown and InCombatLockdown() then return end
        local ok, m = pcall(MyRun.LiveMetrics, "current")
        -- (15/10) THE LAST BOSS OF A KEY. Its fight was saved with every number at 0 in the three keys
        -- of 14/10 (Charonus, Rei Dazar, Nalorakk; read in RocketMeterRunsDB): one second after it the
        -- meter's "current" was ANOTHER session -- the key's end opens one -- with the player not in it
        -- (of = 0, or 260 of healing from 3 others). The fight's own session, by the id kept at its end
        -- (f.sid), still has it: read from there when "current" does not have the player. A fight read
        -- so has no damage taken by spell (the meter gives that by session type only).
        local mine = ok and type(m) == "table" and m.damage and m.damage.rank ~= nil
        if not mine and f.sid then
            local okId, byId = pcall(MyRun.LiveMetrics, #doRun.fights)
            if okId and type(byId) == "table" and byId.damage and byId.damage.rank ~= nil then
                ok, m = true, byId
                if ns.Log and ns.Log.Add then ns.Log.Add("luta-por-id", { luta = #doRun.fights, sid = f.sid, dano = byId.damage.total }) end
            end
        end
        if ok and type(m) == "table" then
            while m.takenSpells and #m.takenSpells > MAX_FIGHT_SPELLS do table.remove(m.takenSpells) end
            f.m = m
        end
        -- (14/10) "My run" open shows the fight that just ended (nothing redrew it before): once
        -- per fight, when its numbers are in, and not every frame — a redraw remakes the menus.
        if ns.MyRunWindow and ns.MyRunWindow.Refresh then pcall(ns.MyRunWindow.Refresh) end
    end
    if C_Timer and C_Timer.After then C_Timer.After(1, Snapshot) else Snapshot() end
end

function MyRun.OnEncounterStart(encounterID, encounterName)
    if not run or run.finished then return end
    run.encounter = { id = encounterID, name = encounterName }
    if run.open then run.open.boss, run.open.enc = encounterName, encounterID end
end

function MyRun.OnEncounterEnd(encounterID, encounterName, success)
    if not run or run.finished then return end
    if run.open then
        run.open.boss, run.open.enc = run.open.boss or encounterName, run.open.enc or encounterID
        run.open.success = (success == 1 or success == true)
    end
    run.encounter = nil
end

---A cast of the player: counted with its second of the run; the gap before it, if long.
---(14/10) WHAT A CAST IS. The user: *"do que se trata cada magia/lançamento (...) "Abrindo" (...)
---skills que não conhecia que surgiu da delve"*. Read in every saved run (14 characters): the
---player's casts mix three things — the buttons pressed; effects the game TRIGGERS and reports as
---casts (Infliction of Sorrow: 2,722 on a blood DK, more than any button); and the world (an aura
---of the zone, a campfire, a delve's power, a mount, "[DNT]" spells). The game says which is
---which: a button is in the player's spellbook (`C_SpellBook`, other specs included, the base
---spell of an override), an item's spell is the item's. The rest is "not pressed".
---@return string "book" | "general" (the spellbook's General tab: racials) | "item" | "other"
local castKinds = {}
function MyRun.CastKind(spellID)
    local kind = castKinds[spellID]
    if kind then return kind end
    kind = "book"   -- a client without the API: everything counts, as before
    if itemSpells[spellID] then
        kind = "item"
    elseif C_SpellBook and C_SpellBook.FindSpellBookSlotForSpell then
        kind = "other"
        local ids = { spellID }
        if C_SpellBook.FindBaseSpellByID then
            local ok, base = pcall(C_SpellBook.FindBaseSpellByID, spellID)
            if ok and type(base) == "number" and base ~= spellID then ids[2] = base end
        end
        for _, id in ipairs(ids) do
            local ok, slot, bank = pcall(C_SpellBook.FindSpellBookSlotForSpell, id, true, true, false, true)
            if ok and slot then
                kind = "book"
                local okInfo, info = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
                local general = Enum and Enum.SpellBookSkillLineIndex and Enum.SpellBookSkillLineIndex.General or 1
                if okInfo and type(info) == "table" and info.skillLineIndex == general then kind = "general" end
                break
            end
        end
        if kind == "other" and GetInventoryItemID and C_Item and C_Item.GetItemSpell then
            for _, slotID in ipairs({ 13, 14 }) do
                local itemID = GetInventoryItemID("player", slotID)
                local ok, _, itemSpell = pcall(C_Item.GetItemSpell, itemID or 0)
                if itemID and ok and itemSpell == spellID then kind = "item" end
            end
        end
    end
    castKinds[spellID] = kind
    -- The diary (development only): each spell once, to check the sorting against a real session.
    if ns.Log and ns.Log.Add then ns.Log.Add("castkind", { spellID = spellID, kind = kind }) end
    return kind
end
function MyRun.__castKinds() castKinds = {} end

function MyRun.OnCast(unit, spellID)
    if not run or run.finished then return end
    if unit ~= "player" or not Readable(spellID) or type(spellID) ~= "number" then return end
    -- Opening a chest, a door or a mechanic object is a cast for the game, not an ability (14/10).
    if ns.OpenSpells and ns.OpenSpells[spellID] then return end
    local t = Elapsed()
    -- Not pressed (a triggered effect, the world): kept apart, with a 0, and no gap is closed by it.
    local pressed = MyRun.CastKind(spellID) ~= "other"
    run.casts[#run.casts + 1] = pressed and { t, spellID } or { t, spellID, 0 }
    if pressed and run.open then
        if run.lastCast and t - run.lastCast > GAP_SECONDS then
            run.gaps[#run.gaps + 1] = { t, t - run.lastCast }
        end
        run.lastCast = t
    end
    if bagsDirty then pcall(ScanBags) end
    local item = itemSpells[spellID]
    if item then run.items[#run.items + 1] = { t, item.kind, item.itemID } end
end

function MyRun.OnBagsChanged() bagsDirty = true end

---The player's own deaths the meter lists now, with the recap of each one not read yet.
function MyRun.ReadDeaths()
    if not run or not (ns.Data and ns.Data.GetDeathList) then return end
    local list = ns.Data.GetDeathList(1)   -- overall: every death of the run so far
    local seen = {}
    for recap in pairs(run.oldRecaps or {}) do seen[recap] = true end
    for _, d in ipairs(run.deaths) do seen[d.recap] = true end
    for _, d in ipairs(list) do
        if d.local_ and d.recap and not seen[d.recap] then
            -- `t` is when the death was READ: the end of the fight it happened in. The meter's
            -- `deathTimeSeconds` counts from a clock nobody here can confirm, so it is not used.
            local death = { t = Elapsed(), recap = d.recap, name = d.nome, class = d.classe }
            -- The recap: the first event killed; the largest amount is the hardest blow.
            if C_DeathRecap and C_DeathRecap.GetRecapEvents then
                local ok, events = pcall(C_DeathRecap.GetRecapEvents, d.recap)
                if ok and type(events) == "table" and #events > 0 then
                    local first = events[1]
                    death.killer = Readable(first.spellName) and first.spellName or nil
                    death.killerSource = Readable(first.sourceName) and first.sourceName or nil
                    death.killerSpell = Num(first.spellId)
                    death.avoidable = first.avoidable == true
                    death.amount = Num(first.amount)
                    local hardest, hi = nil, 0
                    for i = 1, #events do
                        local a = Num(events[i].amount)
                        if a and a > hi then hi, hardest = a, events[i] end
                    end
                    if hardest and hardest ~= first then
                        death.hardest = Readable(hardest.spellName) and hardest.spellName or nil
                        death.hardestSource = Readable(hardest.sourceName) and hardest.sourceName or nil
                        death.hardestSpell = Num(hardest.spellId)
                        death.hardestAmount = hi
                    end
                    -- (!) THE BLOW BY BLOW IS KEPT (01/10). The user: *"um quadro onde eu pudesse ver
                    -- todas as minhas mortes, para quem, qual skill deu mais dano em mim e qual skill
                    -- matou"*. The recap holds up to 10 events (read in a real key); each is kept with
                    -- the seconds before the death (the first event is the death itself).
                    local deathStamp = Num(first.timestamp)
                    death.events = {}
                    for i = 1, math.min(#events, MAX_RECAP_EVENTS) do
                        local ev = events[i]
                        local stamp = Num(ev.timestamp)
                        death.events[#death.events + 1] = {
                            before = deathStamp and stamp and (deathStamp - stamp) or nil,
                            spell = Readable(ev.spellName) and ev.spellName or nil,
                            spellId = Num(ev.spellId),
                            source = Readable(ev.sourceName) and ev.sourceName or nil,
                            amount = Num(ev.amount), overkill = Num(ev.overkill), absorbed = Num(ev.absorbed),
                            hp = Num(ev.currentHP),
                            avoidable = ev.avoidable == true, deadly = ev.deadly == true,
                        }
                    end
                    if C_DeathRecap.GetRecapMaxHealth then
                        local okM, maxHealth = pcall(C_DeathRecap.GetRecapMaxHealth, d.recap)
                        death.maxHealth = okM and Num(maxHealth) or nil
                    end
                end
            end
            run.deaths[#run.deaths + 1] = death
            seen[d.recap] = true
        end
    end
end

---Ends the run. `result` is what the game said of it (timed, time, ...), or nil.
function MyRun.Stop(result)
    if not run or run.finished then return end
    if run.open then MyRun.OnCombatEnd() end
    run.finished = true
    run.elapsed = Elapsed()
    run.result = result
    pcall(MyRun.ReadDeaths)
    if AUTO[run.kind] then
        run.metrics = MyRun.Metrics("all", run)
    else
        run.metrics = MyRun.LiveMetrics("all")
    end
    pcall(MyRun.Save)
end

--------------------------------------------------------------------------------
-- Scopes: the whole run, the current fight, one boss, the trash
--------------------------------------------------------------------------------
---The fights a scope covers. `scope`: "all", "current", "trash", or a fight index.
---@return table[] fights, number combatSeconds
local function FightsOf(scope, r)
    r = r or run
    if not r then return {}, 0 end
    local list = {}
    if scope == "current" then
        if r.open then list[1] = r.open elseif #r.fights > 0 then list[1] = r.fights[#r.fights] end
    elseif type(scope) == "number" then
        if r.fights[scope] then list[1] = r.fights[scope] end
    else
        for _, f in ipairs(r.fights) do
            if scope ~= "trash" or not f.boss then list[#list + 1] = f end
        end
        if r.open and (scope ~= "trash" or not r.open.boss) then list[#list + 1] = r.open end
    end
    local seconds = 0
    for _, f in ipairs(list) do seconds = seconds + ((f.e or (r == run and Elapsed()) or f.s) - f.s) end
    return list, seconds
end

---`grace`: seconds before a fight that still belong to it (the pre-cast, the pre-potion).
local function Within(t, fights, grace)
    grace = grace or 0
    for _, f in ipairs(fights) do
        if t >= f.s - grace and t <= (f.e or math.huge) then return true end
    end
    return false
end

---The scopes the combos offer: whole run, current fight, each boss, the trash.
---@return table[] { key, label }
function MyRun.Scopes(r)
    r = r or run
    local out = { { key = "all", label = L["Whole run"] } }
    -- "Current fight" is the meter's live session: only the run in progress has one.
    if r == run then out[#out + 1] = { key = "current", label = L["This fight"] } end
    if r then
        local trash = false
        for i, f in ipairs(r.fights) do
            if f.boss then out[#out + 1] = { key = i, label = f.boss } else trash = true end
        end
        if trash and r.kind == "key" then out[#out + 1] = { key = "trash", label = L["Trash"] } end
    end
    return out
end

--------------------------------------------------------------------------------
-- The player's own numbers of a scope (casts, gaps, items, deaths, cooldowns)
--------------------------------------------------------------------------------
---@return table { casts, perMinute, combatSeconds, gaps = {count,total,longest,longestAt}, potions, healthstones, deaths = {...}, cooldowns = {...}, bossCount }
---(!) WHAT A COOLDOWN IS FOR DECIDES HOW IT IS JUDGED (01/10). Every cooldown of the game's list
---was measured the same way: how many times it fitted in the fight against how many it was
---pressed. That is right for a damage or a healing cooldown, and wrong for what is pressed only
---when something asks for it. The user: *"sobre skills de reviver em combate, poderia ter usado
---7 vezes, mas talvez não precisasse ou não tem 7 mortes (...) tem que ser mais analítico"*.
---
---So a cooldown is SITUATIONAL when it is a combat resurrection or a Bloodlust
---(`Data/SituationalSpells.lua`), an interrupt (`Data/InterruptSpells.lua`) or a crowd control
---(the game's own word, `C_Spell.IsSpellCrowdControl`). Those are listed with how many times
---they were used and nothing else: no "fitted", no red, never a problem, and out of the sums.
---@return string|nil "rez", "haste", "interrupt", "control"
---(21/10) Is this cooldown one of the player's own defensives (Data/DefensiveSpells.lua)?
function MyRun.IsDefensive(spellID, base)
    local t = type(ns.DefensiveSpells) == "table" and ns.DefensiveSpells
    if not t then return false end
    return (spellID and t[spellID] ~= nil) or (base and t[base] ~= nil) or false
end

function MyRun.Situational(spellID, base)
    for _, id in ipairs({ spellID, base }) do
        if type(id) == "number" then
            local s = type(ns.SituationalSpells) == "table" and ns.SituationalSpells[id]
            if s then return s end
            if type(ns.InterruptSpells) == "table" and ns.InterruptSpells[id] then return "interrupt" end
            if C_Spell and C_Spell.IsSpellCrowdControl then
                local ok, answer = pcall(C_Spell.IsSpellCrowdControl, id)
                if ok and answer == true then return "control" end
            end
        end
    end
    return nil
end

---Is "used N of M fitted" a judgement for this cooldown and this role? ONE answer for the three
---places that judge (the "what cost" list, the red in the cooldown list, the history's share).
---(14/10) What the logs of real Mythic+ tanks showed: Barkskin active 13-23% of the key, used
---when health drops, never "on cooldown"; healers press their big cooldowns for a moment of
---damage. And the game's Utility category is mobility and tricks (Wild Charge, Camouflage,
---Stampeding Roar), never a "defensive". So only a damage dealer's essential cooldowns are
---judged by how many times they fitted; the rest is listed with how many times it was used.
function MyRun.Judged(cd, role)
    if cd.situational then return false end
    -- (21/10) a defensive is pressed when the damage comes, never "as often as it fits", even when the
    -- game lists it as Essential (a damage dealer's Icebound Fortitude was judged as if it were burst)
    if cd.defensive or MyRun.IsDefensive(cd.spellID, cd.base) then return false end
    if cd.category == "utility" then return false end
    return (role or "DAMAGER") == "DAMAGER"
end

function MyRun.Own(scope, r)
    r = r or run
    local fights, seconds = FightsOf(scope, r)
    local out = { combatSeconds = seconds, casts = 0, bySpell = {}, notPressed = {}, gaps = { count = 0, total = 0, longest = 0 },
                  potions = 0, healthstones = 0, deaths = {}, cooldowns = {}, bossCount = 0, potionBosses = 0 }
    if not r then return out end
    local inScope = scope == "all" and function() return true end or function(t) return Within(t, fights) end
    -- (14/10) Casts and items count only inside the fights of the scope, "all" included: between
    -- packs the player mounts, opens chests, swaps talents, and those were counted as casts and
    -- divided by the combat time only (the saved runs had 1,106 casts of one aura outside fights).
    local inFight = function(t) return Within(t, fights, PREPULL_SECONDS) end
    local open = ns.OpenSpells or {}
    -- (14/10) Only what was PRESSED counts (MyRun.CastKind); the rest goes to `notPressed`. A run
    -- recorded before that (no `kinds`) is sorted now, by the spellbook of today.
    local function Add(id, n, notPressed)
        if notPressed == nil then notPressed = not r.kinds and MyRun.CastKind(id) == "other" end
        if notPressed then
            out.notPressed[id] = (out.notPressed[id] or 0) + n
        else
            out.casts = out.casts + n
            out.bySpell[id] = (out.bySpell[id] or 0) + n
        end
    end
    if r.casts then
        for _, c in ipairs(r.casts) do
            if inFight(c[1]) and not open[c[2]] then Add(c[2], 1, r.kinds and c[3] == 0 or nil) end
        end
    else
        -- A saved run: the casts are counts per spell for each fight (the run's own count also
        -- has what was cast between fights, and is not read).
        for _, f in ipairs(fights) do
            for id, n in pairs(f.bySpell or {}) do
                if not open[id] then Add(id, n, r.kinds and false or nil) end
            end
            for id, n in pairs(f.other or {}) do
                if not open[id] then Add(id, n, true) end
            end
        end
    end
    out.perMinute = seconds > 0 and out.casts / (seconds / 60) or nil
    for _, g in ipairs(r.gaps or {}) do
        if inScope(g[1]) then
            out.gaps.count = out.gaps.count + 1
            out.gaps.total = out.gaps.total + g[2]
            if g[2] > out.gaps.longest then out.gaps.longest, out.gaps.longestAt = g[2], g[1] end
        end
    end
    for _, it in ipairs(r.items or {}) do
        if inFight(it[1]) then
            if it[2] == "potion" then
                out.potions = out.potions + 1
                out.potionItem = out.potionItem or it[3]
            else
                out.healthstones = out.healthstones + 1
            end
        end
    end
    -- (14/10) Per BOSS, not per pull (three wipes on one boss were three "bosses"), and the
    -- potion of the pre-pull counts like everywhere else.
    local bosses = {}
    for _, f in ipairs(fights) do
        if f.boss then
            local key = f.enc or f.boss
            if bosses[key] == nil then bosses[key] = false; out.bossCount = out.bossCount + 1 end
            for _, it in ipairs(r.items or {}) do
                if it[2] == "potion" and it[1] >= f.s - PREPULL_SECONDS and it[1] <= (f.e or math.huge) then
                    if not bosses[key] then bosses[key] = true; out.potionBosses = out.potionBosses + 1 end
                    break
                end
            end
        end
    end
    for _, d in ipairs(r.deaths or {}) do
        if inScope(d.t) then out.deaths[#out.deaths + 1] = d end
    end
    -- Cooldowns: used = casts of the spell in the scope; fitted = how many times it was ready in
    -- the fights of the scope, used as soon as ready, charges counted. Never fewer than used.
    -- (14/10) The cooldown RUNS BETWEEN THE FIGHTS too: ten packs of 30 s with a 2 min cooldown
    -- gave "fitted 3" from the summed combat time, when it was ready in all ten.
    local role = r.role
    for _, cd in ipairs(r.cooldowns or {}) do
        if cd.cooldown >= COOLDOWN_MIN then
            local used = (out.bySpell[cd.spellID] or 0) + (cd.base and cd.base ~= cd.spellID and out.bySpell[cd.base] or 0)
            local fitted, readyAt = (cd.charges or 1) - 1, -math.huge
            for _, f in ipairs(fights) do
                local e = f.e or ((r == run and Elapsed()) or f.s)
                local t = math.max(f.s, readyAt)
                while t <= e do fitted = fitted + 1; t = t + cd.cooldown end
                readyAt = t
            end
            if seconds <= 0 then fitted = 0 end
            if fitted < used then fitted = used end
            -- Pressed only when something asks for it: there is no "fitted" to be behind of.
            local situational = MyRun.Situational(cd.spellID, cd.base)
            if situational then fitted = used end
            local entry = { spellID = cd.spellID, base = cd.base, name = cd.name, cooldown = cd.cooldown,
                used = used, fitted = fitted, category = cd.category, situational = situational,
                defensive = cd.defensive or MyRun.IsDefensive(cd.spellID, cd.base) or nil,
                idle = fitted > used and (fitted - used) * cd.cooldown or 0 }
            entry.judged = MyRun.Judged(entry, role)
            out.cooldowns[#out.cooldowns + 1] = entry
        end
    end
    table.sort(out.cooldowns, function(a, b)
        -- the ones that are judged first; the situational ones after them
        if (a.situational ~= nil) ~= (b.situational ~= nil) then return a.situational == nil end
        local ra, rb = a.fitted > 0 and a.used / a.fitted or 1, b.fitted > 0 and b.used / b.fitted or 1
        if ra == rb then return a.cooldown > b.cooldown end
        return ra < rb
    end)
    return out
end

--------------------------------------------------------------------------------
-- The meter's numbers of the local player, for a scope
--------------------------------------------------------------------------------
local function SessionGetter(scope)
    if scope == "all" then
        return function(attr) return ns.Data.GetSession(1, attr) end
    elseif scope == "current" then
        return function(attr) return ns.Data.GetSession(0, attr) end
    elseif type(scope) == "number" then
        local f = run and run.fights[scope]
        local sid = f and f.sid
        if not (sid and C_DamageMeter and C_DamageMeter.GetCombatSessionFromID) then return nil end
        return function(attr)
            local ok, s = pcall(C_DamageMeter.GetCombatSessionFromID, sid, attr)
            return ok and type(s) == "table" and s or nil
        end
    end
    return nil   -- "trash": the meter has no such session; only the player's own numbers
end

---One metric of the local player: total, per second, rank in the group and the group size.
local function Metric(get, attr)
    local session = get(attr)
    local list = session and session.combatSources
    if type(list) ~= "table" then return nil end
    local mine
    for i = 1, #list do
        local flag = list[i].isLocalPlayer
        if Readable(flag) and flag == true then mine = list[i]; break end
    end
    if not mine then return { total = 0, perSecond = 0, rank = nil, of = #list } end
    local total, per = Num(mine.totalAmount), Num(mine.amountPerSecond)
    if not total then return nil end   -- in combat: secret, nothing to say
    local rank = 0
    for i = 1, #list do
        local other = Num(list[i].totalAmount)
        if other and other > total then rank = rank + 1 end
    end
    return { total = total, perSecond = per, rank = rank + 1, of = #list,
             groupTotal = Num(session.totalAmount) }
end

---The meter's numbers of the local player for a scope, or nil when the meter cannot answer
---(in combat, or a fight the meter no longer keeps).
---(!) HEALING WITHOUT THE SHIELDS, in every number of this screen (08/10; Data.PureHealingMetric).
---Done once per table of numbers and marked (`pure`): the numbers of a fight are kept and summed,
---and a run saved before this still has the game's number -- it is put right when it is read.
local function Purify(m)
    if type(m) == "table" and not m.pure then
        if m.healing and m.absorbs and ns.Data.PureHealingMetric then
            m.healing = ns.Data.PureHealingMetric(m.healing, m.absorbs)
        end
        m.pure = true
    end
    return m
end

-- (!) ONE SESSION OF THE METER, SEVERAL OF OUR FIGHTS (20/10). The meter does not open a session at every drop out of
-- combat: fights a few seconds apart are ONE session, and its reading at the end of each is the total SINCE THE
-- SESSION BEGAN. Read in the 720 readings saved on this machine: a gap of up to 3.0 s joins, 3.1 s or more does not
-- (Temja, 00:05: fight 2 read 3,427,929 = fights 1 and 2 of the combat log, 3,428,199). Summed as they were, the
-- delve of 01:00 said 247.0M for 224.7M. Where a reading starts: its total over its rate is the session's length
-- (whole seconds, from 0 to 1 s over the fight's own); checked against the combat log, 54 of 55 readings named the
-- same fights the log did. So a reading that the next one of the same session covers is the earlier part of it, and
-- each reading's OWN numbers are it minus the reading before it in its session.
local MERGE_SLACK = 1.5         -- s: the session's start against the end of the fight before (a real gap is 3.1 s or more)

---How long the meter's session of a reading lasted: total over rate, of the first metric that has both.
local function SessionSeconds(m)
    for _, key in ipairs({ "damage", "taken", "healing", "absorbs" }) do
        local x = m[key]
        if x and (x.total or 0) > 0 and (x.perSecond or 0) > 0 then return x.total / x.perSecond end
    end
    return nil
end

---The reading `a` minus the reading `b` before it in the same session, over `seconds`.
local function Minus(a, b, seconds)
    local out = { takenSpells = {}, pure = true }
    for _, key in ipairs(METRIC_KEYS) do
        local x, y = a[key], b[key]
        if x then
            local total = math.max(0, (x.total or 0) - (y and y.total or 0))
            out[key] = { total = total, of = x.of, rank = nil,
                         perSecond = seconds and seconds > 0 and total / seconds or nil,
                         groupTotal = x.groupTotal and y and y.groupTotal and math.max(0, x.groupTotal - y.groupTotal) or nil,
                         absorbed = x.absorbed and math.max(0, x.absorbed - (y and y.absorbed or 0)) or nil }
        end
    end
    local before = {}
    for _, sp in ipairs(b.takenSpells or {}) do before[sp.spellID or 0] = sp.amount end
    for _, sp in ipairs(a.takenSpells or {}) do
        local amount = sp.amount - (before[sp.spellID or 0] or 0)
        if amount > 0 then
            out.takenSpells[#out.takenSpells + 1] = { spellID = sp.spellID, amount = amount, creature = sp.creature,
                                                      avoidable = sp.avoidable, deadly = sp.deadly }
        end
    end
    -- (20/10) the lists by spell the same way (MyRun.ReadSpells)
    if a.spells then
        out.spells = {}
        for key, list in pairs(a.spells) do
            local prior = {}
            for _, sp in ipairs(b.spells and b.spells[key] or {}) do prior[sp.spellID or 0] = sp.amount end
            local rows = {}
            for _, sp in ipairs(list) do
                local amount = sp.amount - (prior[sp.spellID or 0] or 0)
                if amount > 0 then rows[#rows + 1] = { spellID = sp.spellID, amount = amount } end
            end
            table.sort(rows, function(x, y) return x.amount > y.amount end)
            out.spells[key] = rows
        end
    end
    return out
end

---Each reading's own numbers: [i] = { m = what fight i's reading adds, from = the first fight it covers }, for the
---fights that have a reading. A fight inside a later reading's session has none of its own.
local function OwnReadings(r)
    local fights, out, prev = r and r.fights or {}, {}, nil
    for i, f in ipairs(fights) do
        if f.m then
            Purify(f.m)
            local seconds, from = SessionSeconds(f.m), i
            if seconds and f.e then
                local start = f.e - seconds
                while from > 1 and fights[from - 1].e and fights[from - 1].e > start - MERGE_SLACK do from = from - 1 end
            end
            if prev and prev >= from then
                local before = SessionSeconds(fights[prev].m)
                local own = seconds and before and seconds - before or nil
                if not (own and own > 0) then
                    own = 0
                    for k = prev + 1, i do own = own + ((fights[k].e or fights[k].s) - fights[k].s) end
                end
                out[i] = { m = Minus(f.m, fights[prev].m, own), from = prev + 1 }
            else
                out[i] = { m = f.m, from = from }
            end
            prev = i
        end
    end
    return out
end

---The numbers of several fights as one: totals summed, the rate over their combat time. No rank
---(the others' numbers of each fight are not kept). Each reading counts once, by its own numbers
---(OwnReadings), with the combat time of every fight it covers.
local function SumFights(r, wanted)
    local out, seconds, any = { takenSpells = {}, pure = true }, 0, false
    local bySpell = {}
    local fights, own = r and r.fights or {}, OwnReadings(r)
    for i, f in ipairs(fights) do
        local o = own[i]
        if o and wanted(f) then
            any = true
            for k = o.from, i do seconds = seconds + ((fights[k].e or fights[k].s) - fights[k].s) end
            for _, key in ipairs(METRIC_KEYS) do
                local x = o.m[key]
                if x then
                    out[key] = out[key] or { total = 0 }
                    out[key].total = out[key].total + (x.total or 0)
                end
            end
            for _, sp in ipairs(o.m.takenSpells or {}) do
                local acc = bySpell[sp.spellID or 0]
                if not acc then
                    acc = { spellID = sp.spellID, amount = 0, creature = sp.creature }
                    bySpell[sp.spellID or 0] = acc
                    out.takenSpells[#out.takenSpells + 1] = acc
                end
                acc.amount = acc.amount + sp.amount
                acc.avoidable = acc.avoidable or sp.avoidable
                acc.deadly = acc.deadly or sp.deadly
            end
            -- (20/10) the lists by spell (MyRun.ReadSpells), summed the same way
            for key, list in pairs(o.m.spells or {}) do
                out.spells = out.spells or {}
                local into = out.spells[key] or { index = {} }
                out.spells[key] = into
                for _, sp in ipairs(list) do
                    local acc = into.index[sp.spellID or 0]
                    if not acc then
                        acc = { spellID = sp.spellID, amount = 0 }
                        into.index[sp.spellID or 0] = acc
                        into[#into + 1] = acc
                    end
                    acc.amount = acc.amount + sp.amount
                end
            end
        end
    end
    if not any then return nil end
    for _, key in ipairs(METRIC_KEYS) do
        if out[key] then out[key].perSecond = seconds > 0 and out[key].total / seconds or 0 end
    end
    table.sort(out.takenSpells, function(a, b) return a.amount > b.amount end)
    for _, list in pairs(out.spells or {}) do
        list.index = nil
        table.sort(list, function(a, b) return a.amount > b.amount end)
    end
    out.combatSeconds = seconds
    return out
end

---The meter's numbers of the local player for a scope, or nil when there is nothing to say.
---A fight answers from what was kept at its end (`f.m`); the trash is the sum of the fights
---without a boss; the whole run and the current fight are the meter's, read now (nil in
---combat); a saved run has the numbers taken at its end.
function MyRun.Metrics(scope, r)
    r = r or run
    local saved = r ~= nil and r ~= run
    if type(scope) == "number" then
        local own = r and OwnReadings(r)[scope]
        if own then return own.m end
        if saved then return nil end
    elseif scope == "trash" then
        return SumFights(r, function(f) return not f.boss end)
    elseif saved then
        if scope ~= "all" then return nil end
        -- (20/10) a run that started by itself was saved with the sum of its readings, the earlier part of a
        -- session counted again (OwnReadings): summed again from its fights, it comes out right
        if AUTO[r.kind] then return SumFights(r, function() return true end) or Purify(r.metrics) end
        return Purify(r.metrics)
    elseif scope == "all" and r and AUTO[r.kind] then
        -- A session that started by itself: the sum of its own fights (see AUTO).
        return SumFights(r, function() return true end)
    end
    return MyRun.LiveMetrics(scope)
end

---The meter, asked now.
function MyRun.LiveMetrics(scope)
    if not (ns.Data and ns.Data.IsAvailable and ns.Data.IsAvailable()) then return nil end
    if InCombatLockdown and InCombatLockdown() then return nil end
    local get = SessionGetter(scope)
    if not get then return nil end
    local E = Enum.DamageMeterType
    local out = {
        damage = Metric(get, E.DamageDone), healing = Metric(get, E.HealingDone), absorbs = Metric(get, E.Absorbs),
        taken = Metric(get, E.DamageTaken), avoidable = Metric(get, E.AvoidableDamageTaken),
        interrupts = Metric(get, E.Interrupts), dispels = Metric(get, E.Dispels),
    }
    if not out.damage then return nil end
    Purify(out)
    -- Damage taken by spell, with the game's marks: the top ones.
    local session = get(E.DamageTaken)
    local mine
    for _, s in ipairs(session and session.combatSources or {}) do
        if Readable(s.isLocalPlayer) and s.isLocalPlayer == true then mine = s; break end
    end
    out.takenSpells = {}
    -- (20/10) A past fight answers by its id too: GetCombatSessionSourceFromID gave the player's spells in all 43
    -- readings of RocketLab's probe (until then this said the meter answered by session TYPE only).
    local st = scope == "current" and 0 or scope == "all" and 1 or nil
    if type(scope) == "number" then
        local f = run and run.fights[scope]
        st = f and f.sid and { id = f.sid } or nil
    end
    if mine and Readable(mine.sourceGUID) and st ~= nil then
        local ok, container
        if type(st) == "table" then
            if C_DamageMeter.GetCombatSessionSourceFromID then
                ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromID, st.id, E.DamageTaken, mine.sourceGUID, mine.sourceCreatureID)
            end
        elseif C_DamageMeter.GetCombatSessionSourceFromType then
            ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromType, ns.Data.SessionValue(st), E.DamageTaken, mine.sourceGUID, mine.sourceCreatureID)
        end
        local spells = ok and type(container) == "table" and container.combatSpells or nil
        for i = 1, (spells and #spells or 0) do
            local sp = spells[i]
            local amount = Num(sp.totalAmount)
            if amount then
                local d = sp.combatSpellDetails
                out.takenSpells[#out.takenSpells + 1] = {
                    spellID = Num(sp.spellID), amount = amount,
                    avoidable = sp.isAvoidable == true, deadly = sp.isDeadly == true,
                    creature = Readable(sp.creatureName) and sp.creatureName ~= "" and sp.creatureName
                        or (type(d) == "table" and Readable(d.unitName) and d.unitName) or nil,
                }
            end
        end
        table.sort(out.takenSpells, function(a, b) return a.amount > b.amount end)
        while #out.takenSpells > MAX_TAKEN_SPELLS do table.remove(out.takenSpells) end
    end
    -- (20/10) WHAT EACH SPELL GAVE, kept with the numbers (the tabs of "My run", after Warcraft Logs'): the user,
    -- *"replicar a informação que tem no warcraftlogs dentro das informações detalhadas do meter"*. Until now the
    -- meter was asked live, so a boss of the run and a run of the history had casts and no amounts.
    out.spells = MyRun.ReadSpells(st, mine)
    return out
end

-- How many spells each list keeps: enough for the tabs, small enough for the saved file (a delve has 100 fights).
local SPELL_LIMITS = { damage = 25, healing = 16, absorbs = 8, interrupts = 8, dispels = 8 }
MyRun.SPELL_LIMITS = SPELL_LIMITS

---The player's spells of a session (0 current, 1 overall, `{ id = sessionID }` one by its id): per kind, a list of
---`{ spellID, amount }`, largest first. Healing without the shields (Data.GetPureHealing). nil when unreadable.
function MyRun.ReadSpells(st, mine)
    if st == nil or not (ns.Data and ns.Data.GetSpellBreakdown) then return nil end
    local guid = mine and Readable(mine.sourceGUID) and mine.sourceGUID or (UnitGUID and UnitGUID("player"))
    if guid == nil or issecretvalue(guid) then return nil end
    local creature = mine and Readable(mine.sourceCreatureID) and mine.sourceCreatureID or nil
    local E = Enum.DamageMeterType
    local function Keep(list)
        local out = {}
        -- the meter's own rate of the spell is kept: a scope of one session shows it as the game does
        for _, sp in ipairs(list or {}) do out[#out + 1] = { spellID = sp.spellID, amount = sp.amount, perSecond = sp.perSecond } end
        return out
    end
    local okH, healing = pcall(ns.Data.GetPureHealing, st, guid, creature, SPELL_LIMITS.healing)
    return {
        damage = Keep((ns.Data.GetSpellBreakdown(st, { E.DamageDone }, guid, creature, SPELL_LIMITS.damage))),
        healing = Keep(okH and healing or nil),
        absorbs = Keep((ns.Data.GetSpellBreakdown(st, { E.Absorbs }, guid, creature, SPELL_LIMITS.absorbs))),
        interrupts = Keep((ns.Data.GetSpellBreakdown(st, { E.Interrupts }, guid, creature, SPELL_LIMITS.interrupts))),
        dispels = Keep((ns.Data.GetSpellBreakdown(st, { E.Dispels }, guid, creature, SPELL_LIMITS.dispels))),
    }
end

--------------------------------------------------------------------------------
-- What cost: the ranked list, by role
--------------------------------------------------------------------------------
local function Clock(seconds)
    seconds = math.floor((seconds or 0) + 0.5)
    return format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end
MyRun.Clock = Clock

local function BossAt(t, r)
    r = r or run
    if not r then return nil end
    for _, f in ipairs(r.fights) do
        if f.boss and t >= f.s and t <= (f.e or math.huge) then return f.boss end
    end
    return nil
end

MyRun.BossAt = BossAt

local function NextBossAfter(t)
    if not run then return nil end
    for _, f in ipairs(run.fights) do
        if f.boss and f.s >= t then return f.boss end
    end
    return nil
end

---The ranked list of what cost, for the role. Each item: { kind, severity (1 worst..3), spellID,
---atlas, title, detail, number }. Empty when nothing was found; `checked` says what was looked at.
function MyRun.Problems(scope, role, r)
    r = r or run
    role = role or (r and r.role) or "DAMAGER"
    local own = MyRun.Own(scope, r)
    local m = MyRun.Metrics(scope, r)
    local out, checked = {}, {}

    -- 1. Deaths: every one, worst first.
    checked[#checked + 1] = L["deaths"]
    for index, d in ipairs(own.deaths) do
        local what = d.killer and (d.killer .. (d.killerSource and (" · " .. d.killerSource) or "")) or L["cause unknown"]
        local detail = {}
        if d.avoidable then detail[#detail + 1] = L["avoidable"] end
        if d.amount then detail[#detail + 1] = format(L["%s blow"], ns.Data.FormatAmount(d.amount)) end
        if d.hardest then detail[#detail + 1] = format(L["hardest: %s"], d.hardest .. (d.hardestSource and (" · " .. d.hardestSource) or "")) end
        out[#out + 1] = { kind = "death", severity = 1, atlas = "deathrecap-icon-tombstone", spellID = d.killerSpell,
            title = format(L["Died at %s — %s"], Clock(d.t), what), detail = table.concat(detail, " · "),
            number = BossAt(d.t, r) or L["trash"], t = d.t, recap = d.recap, index = index }
    end

    -- 2. Avoidable damage: the share of what was taken, and the spell that gave most of it.
    -- (14/10) "Looked at" only when there were numbers to look at.
    if m and m.avoidable then checked[#checked + 1] = L["avoidable damage"] end
    if m and m.avoidable and m.taken and m.taken.total > 0 and m.avoidable.total > 0 then
        local share = m.avoidable.total / m.taken.total * 100
        local worst
        for _, sp in ipairs(m.takenSpells or {}) do if sp.avoidable then worst = sp; break end end
        local sev = share >= 15 and 1 or (share >= 5 and 2 or 3)
        if share >= 5 or (worst and worst.amount >= m.taken.total * 0.1) then
            local title = format(L["%s of avoidable damage"], ns.Data.FormatAmount(m.avoidable.total))
            if worst then
                title = title .. format(" — %d%% %s", math.floor(worst.amount / m.avoidable.total * 100 + 0.5),
                    (C_Spell and C_Spell.GetSpellName and select(2, pcall(C_Spell.GetSpellName, worst.spellID))) or "")
                if worst.creature then title = title .. " · " .. worst.creature end
            end
            out[#out + 1] = { kind = "avoidable", severity = sev, atlas = "damagemeters-avoidabledamage-icon", spellID = worst and worst.spellID,
                -- (The place in the group only when there is one: a session summed from its
                -- fights, and anything played alone, has none.)
                -- (14/10) No place in the group: "1st of the group" in avoidable damage read as
                -- first place, when it was the most avoidable damage taken.
                title = title, detail = format(L["%d%% of all you took"], math.floor(share + 0.5)),
                number = format("%d%%", math.floor(share + 0.5)) }
        end
    end

    -- 3. Interrupts cast that cut nothing (casts of interrupt spells minus the meter's credit).
    if m and m.interrupts then checked[#checked + 1] = L["interrupts"] end
    if m and m.interrupts and ns.Casts and ns.InterruptSpells then
        local cast, spellID = 0, nil
        for id, n in pairs(own.bySpell) do
            if ns.InterruptSpells[id] then cast = cast + n; spellID = spellID or id end
        end
        local missed = cast - m.interrupts.total
        if missed >= 3 and missed / cast >= 0.25 then
            out[#out + 1] = { kind = "interrupts", severity = 2, spellID = spellID,
                title = format(L["%d of %d interrupts cut nothing"], missed, cast),
                detail = L["kicked a target that was not casting, or someone cut first"],
                number = format(L["%d%% missed"], math.floor(missed / cast * 100 + 0.5)) }
        end
    end

    -- 4. Damage cooldowns left idle (MyRun.Judged: a damage dealer's essential cooldowns only).
    if role == "DAMAGER" then checked[#checked + 1] = L["cooldowns"] end
    for _, cd in ipairs(own.cooldowns) do
        local ratio = cd.fitted > 0 and cd.used / cd.fitted or 1
        if MyRun.Judged(cd, role) and cd.fitted >= 2 and ratio < 0.7 then
            local detail = format(L["cooldown of %s · idle %s in total"], Clock(cd.cooldown), Clock(cd.idle))
            out[#out + 1] = { kind = "cooldown", severity = ratio < 0.5 and 2 or 3, spellID = cd.spellID,
                title = format(L["%s: used %d times; %d fitted"], cd.name, cd.used, cd.fitted),
                detail = detail,
                number = format("%d%%", math.floor(ratio * 100 + 0.5)) }
        end
    end

    -- 5. Standing there: gaps between casts in combat. (14/10) Not for a healer: standing still
    -- with the group at full health is not a mistake.
    if role ~= "HEALER" then checked[#checked + 1] = L["gaps without casting"] end
    if role ~= "HEALER" and own.gaps.count >= 3 and own.gaps.total >= 30 then
        out[#out + 1] = { kind = "gaps", severity = own.gaps.total >= 90 and 2 or 3, atlas = "worldquest-icon-clock",
            title = format(L["%d gaps without casting of more than %d s in combat"], own.gaps.count, GAP_SECONDS),
            detail = format(L["%s idle in total · the longest: %d s at %s"], Clock(own.gaps.total), math.floor(own.gaps.longest + 0.5), Clock(own.gaps.longestAt or 0)),
            number = own.perMinute and format(L["%d/min"], math.floor(own.perMinute + 0.5)) or "" }
    end

    -- 6. Potions and the healthstone.
    checked[#checked + 1] = L["potions"]
    if own.bossCount > 0 and own.potionBosses < own.bossCount then
        -- The icon is the potion's own: the one used in the scope, else one in the bags.
        out[#out + 1] = { kind = "potion", severity = 3, item = true,
            itemID = own.potionItem or (r == run and MyRun.KnownPotion() or nil),
            title = format(L["Potion in %d of %d bosses"], own.potionBosses, own.bossCount),
            detail = own.healthstones == 0 and L["the healthstone was not used"] or format(L["healthstone used %d times"], own.healthstones),
            number = format("%d/%d", own.potionBosses, own.bossCount) }
    end

    -- Healer: the group's deaths are the healer's problem too.
    if role == "HEALER" and r == run and ns.Data and ns.Data.GetDeathList and scope == "all" then
        checked[#checked + 1] = L["deaths of the group"]
        local list = ns.Data.GetDeathList(1)
        local others = 0
        for _, d in ipairs(list) do if not d.local_ then others = others + 1 end end
        if others > 0 then
            out[#out + 1] = { kind = "groupdeaths", severity = others >= 3 and 2 or 3, atlas = "deathrecap-icon-tombstone",
                title = format(L["%d deaths in the group"], others), detail = L["the scoreboard says who and when"], number = tostring(others) }
        end
    end

    -- Worst first; among equals a death first, then by the time it happened.
    for i, p in ipairs(out) do p.order = i end
    table.sort(out, function(a, b)
        if a.severity ~= b.severity then return a.severity < b.severity end
        local da, db = a.kind == "death" and 0 or 1, b.kind == "death" and 0 or 1
        if da ~= db then return da < db end
        if (a.t or 0) ~= (b.t or 0) then return (a.t or 0) < (b.t or 0) end
        return a.order < b.order
    end)
    return out, checked
end

--------------------------------------------------------------------------------
-- What the screen draws beyond the totals (01/10, from the tabs of Warcraft Logs that the game
-- lets an addon rebuild for the local player)
--------------------------------------------------------------------------------
---When each cooldown was used: { [spellID] = { t1, t2, ... } }, for the cooldowns of the list.
---A saved run keeps this table; the run in memory has every cast.
function MyRun.CooldownUses(r)
    r = r or run
    if not r then return {} end
    if not r.casts then return r.cdCasts or {} end
    local wanted, out = {}, {}
    for _, cd in ipairs(r.cooldowns or {}) do
        if cd.cooldown >= COOLDOWN_MIN then
            wanted[cd.spellID] = cd.spellID
            if cd.base then wanted[cd.base] = cd.spellID end
        end
    end
    local fights = FightsOf("all", r)
    for _, c in ipairs(r.casts) do
        local id = wanted[c[2]]
        -- (14/10) Only inside the fights, like every other count (the timeline drew the uses
        -- made travelling between packs).
        if id and Within(c[1], fights, PREPULL_SECONDS) then
            out[id] = out[id] or {}
            out[id][#out[id] + 1] = c[1]
        end
    end
    return out
end

---(21/10) When each DEFENSIVE was used, the whole run and not only inside the fights: one pressed between two
---packs is still on its cooldown when the next fight kills. { [spellID] = { t1, t2, ... } }; a saved run keeps it.
function MyRun.DefensiveUses(r)
    r = r or run
    if not r then return {} end
    -- a run saved before 21/10 kept no defensive's use: nil, and nothing is said of its deaths
    if not r.casts then return r.defCasts end
    local wanted, out = {}, {}
    for _, cd in ipairs(r.cooldowns or {}) do
        if cd.defensive or MyRun.IsDefensive(cd.spellID, cd.base) then
            wanted[cd.spellID] = cd.spellID
            if cd.base then wanted[cd.base] = cd.spellID end
        end
    end
    for _, c in ipairs(r.casts) do
        local id = wanted[c[2]]
        if id then
            out[id] = out[id] or {}
            out[id][#out[id] + 1] = c[1]
        end
    end
    return out
end

---(21/10) THE DEFENSIVES READY AT A DEATH, and not pressed. The user: *"é para incremental o que tem igual o
---warcraftlogs, vamos melhorar o que ele tem"*. Warcraft Logs shows the blows of a death; it does not say what the
---player still had. Health in combat is secret in Midnight (0 of 347 readings, 20/10), so "it fitted to press it"
---over a fight cannot be told -- at the death it can: each use's time (`DefensiveUses`) against the cooldown and
---its charges, one charge back every cooldown. The base cooldown is the game's (`GetSpellBaseCooldown`): a talent
---that shortens it makes this say "not ready" when it was -- never the other way round.
---@return table|nil { { spellID, name, cooldown }, ... } in the order of the run's list; nil when the run cannot say
function MyRun.ReadyAtDeath(d, r)
    r = r or run
    local out = {}
    if not (r and d and d.t) then return out end
    local uses = MyRun.DefensiveUses(r)
    if not uses then return nil end
    for _, cd in ipairs(r.cooldowns or {}) do
        if (cd.defensive or MyRun.IsDefensive(cd.spellID, cd.base)) and (cd.cooldown or 0) > 0 then
            local max = cd.charges or 1
            local have, back = max, nil          -- charges now; when the next one comes back
            local function Until(t)
                while have < max and back and back <= t do
                    have = have + 1
                    back = have < max and (back + cd.cooldown) or nil
                end
            end
            local times = {}
            for _, u in ipairs(uses[cd.spellID] or {}) do if u <= d.t then times[#times + 1] = u end end
            table.sort(times)
            for _, u in ipairs(times) do
                Until(u)
                have = math.max(0, have - 1)
                if not back then back = u + cd.cooldown end
            end
            Until(d.t)
            if have >= 1 then out[#out + 1] = { spellID = cd.spellID, name = cd.name, cooldown = cd.cooldown } end
        end
    end
    return out
end

---The casts of a scope as a list: each spell with its count, its share and its casts per minute.
---@param own table what `MyRun.Own` gave
function MyRun.CastList(own)
    local list = {}
    for id, n in pairs(own.bySpell or {}) do
        list[#list + 1] = { spellID = id, count = n, share = own.casts > 0 and n / own.casts * 100 or 0,
            perMinute = own.combatSeconds > 0 and n / (own.combatSeconds / 60) or nil }
    end
    table.sort(list, function(a, b)
        if a.count == b.count then return a.spellID < b.spellID end
        return a.count > b.count
    end)
    return list
end

---A death in three numbers: how many blows the game kept, over how many seconds, how much
---damage in all; and the names of the last three blows, the killer first.
function MyRun.DeathSummary(death)
    local events = death and death.events or {}
    local total, last = 0, {}
    for i, ev in ipairs(events) do
        total = total + (ev.amount or 0)
        if i <= 3 and ev.spell then last[#last + 1] = ev.spell end
    end
    return { blows = #events, seconds = events[#events] and events[#events].before or nil,
             total = total, last = last, oneShot = #events == 1 }
end

---One number per fight, for the chart: the rate that is the role's (damage, healing, taken).
---@return table[] { s, e, boss, rate } and the largest rate
function MyRun.FightRates(r, role, key)
    r = r or run
    key = key or (role == "HEALER" and "healing" or (role == "TANK" and "taken" or "damage"))
    local out, top = {}, 0
    local fights, own = r and r.fights or {}, OwnReadings(r)
    for i, f in ipairs(fights) do
        -- a reading that covers the fights before it (one session of the meter) draws over all of them
        local o = own[i]
        local x = o and o.m[key]
        local s = o and fights[o.from].s or f.s
        -- a reading without its rate (a sum of readings) is its total over the time it covers
        local rate = x and (x.perSecond or (x.total and f.e and f.e > s and x.total / (f.e - s))) or nil
        if rate and rate > top then top = rate end
        out[#out + 1] = { s = s, e = f.e, boss = f.boss, rate = rate }
    end
    return out, top, key
end

--------------------------------------------------------------------------------
-- History: the last runs, saved per character
--------------------------------------------------------------------------------
local function Store()
    if RocketMeterRunsDB == nil then RocketMeterRunsDB = {} end
    RocketMeterRunsDB.myRuns = RocketMeterRunsDB.myRuns or {}
    return RocketMeterRunsDB.myRuns
end

---Compacts the run for the saved file: casts become counts per spell per fight.
local function Compact(r)
    local c = { kind = r.kind, name = r.name, level = r.level, tier = r.tier, detail = r.detail,
                date = r.date, at = r.at, role = r.role, class = r.class,
                spec = r.spec, specIcon = r.specIcon, player = r.player, elapsed = r.elapsed, result = r.result,
                fights = {}, gaps = r.gaps, items = r.items, deaths = r.deaths, cooldowns = r.cooldowns,
                metrics = r.metrics, bySpell = {}, castCount = #r.casts, finished = true, kinds = r.kinds,
                stats = r.stats, gear = r.gear, castLog = MyRun.PackCasts(r.casts) }
    for i, f in ipairs(r.fights) do
        c.fights[i] = { s = f.s, e = f.e, boss = f.boss, enc = f.enc, success = f.success, bySpell = {}, m = f.m }
    end
    c.cdCasts = MyRun.CooldownUses(r)
    c.defCasts = MyRun.DefensiveUses(r)
    for _, cast in ipairs(r.casts) do
        -- Not pressed (MyRun.CastKind) apart, in `other`, fight by fight.
        local key = cast[3] == 0 and "other" or "bySpell"
        if key == "bySpell" then c.bySpell[cast[2]] = (c.bySpell[cast[2]] or 0) + 1 end
        for _, f in ipairs(c.fights) do
            if cast[1] >= f.s - PREPULL_SECONDS and cast[1] <= (f.e or math.huge) then
                f[key] = f[key] or {}
                f[key][cast[2]] = (f[key][cast[2]] or 0) + 1
                break
            end
        end
    end
    return c
end

-- (20/10) WHAT IS KEPT OF THE CASTS. A saved run had the casts as counts per spell per fight, enough for every count
-- and not for a chart in time (Warcraft Logs' "Casts"). Kept as text, "tenths:spell", which is small: a key of 30
-- minutes has 2,000 to 7,000 casts.
local function PackPairs(list, fmt)
    local parts = {}
    for _, p in ipairs(list or {}) do parts[#parts + 1] = format(fmt, p[1], p[2]) end
    return table.concat(parts, ",")
end
local function UnpackPairs(text, scale)
    local out = {}
    if type(text) ~= "string" then return out end
    for a, b in text:gmatch("(%-?[%d%.]+):(%d+)") do out[#out + 1] = { tonumber(a) / (scale or 1), tonumber(b) } end
    return out
end

---The casts of a run as text (pressed only: what was not pressed has a 0 in the third place).
function MyRun.PackCasts(casts)
    local list = {}
    for _, c in ipairs(casts or {}) do
        if c[3] ~= 0 then list[#list + 1] = { math.floor(c[1] * 10 + 0.5), c[2] } end
    end
    return PackPairs(list, "%d:%d")
end

---The pressed casts of a run with their second: { { t, spellID }, ... }, live or saved.
function MyRun.CastTimes(r)
    r = r or run
    if not r then return {} end
    if r.casts then
        local out = {}
        for _, c in ipairs(r.casts) do if c[3] ~= 0 then out[#out + 1] = c end end
        return out
    end
    return UnpackPairs(r.castLog, 10)
end

function MyRun.Save()
    if not run or not run.finished then return end
    -- A session that started by itself and had no fight is nothing to keep.
    if AUTO[run.kind] and #run.fights == 0 then return end
    local list = Store()
    table.insert(list, 1, Compact(run))
    -- The open world gives a session per zone: only the newest few stay, so that walking around
    -- does not push the keys and the delves out of the history.
    local world = 0
    for i = 1, #list do
        if list[i] and list[i].kind == "world" then
            world = world + 1
            if world > MAX_WORLD_SAVED then list[i] = false end
        end
    end
    for i = #list, 1, -1 do if list[i] == false then table.remove(list, i) end end
    while #list > HISTORY_SIZE do table.remove(list) end
end

---The saved runs, newest first.
function MyRun.History() return Store() end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------
local function KeyName()
    local mapID = C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID and select(2, pcall(C_ChallengeMode.GetActiveChallengeMapID))
    local name
    if mapID and C_ChallengeMode.GetMapUIInfo then
        local ok, n = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok and type(n) == "string" then name = n end
    end
    local level
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local ok, lv = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok and type(lv) == "number" then level = lv end
    end
    return name, level
end

--------------------------------------------------------------------------------
-- The game's combat log
--------------------------------------------------------------------------------
-- (!) ON BY ITSELF INSIDE AN INSTANCE (20/10). The user: *"liga o combatlog sozinho, ambos addons"*, and then, for
-- the published addon, *"Ligada"* by default: whoever uploads to Warcraft Logs has the file without remembering
-- /combatlog (the addon only turns the game's log on: it cannot read the file nor send it -- the site's own app
-- does). On in a dungeon (key or not), a raid or a scenario (a delve is one), with the game's own call
-- (LoggingCombat(true); /combatlog is the same call); off when leaving --
-- only the log this addon turned on: the player's own /combatlog, or another addon's, is left alone. Not in the open world
-- nor in PvP. The option off (`combatLog`) turns off what it had turned on, and touches nothing else.
local LOG_INSTANCES = { party = true, raid = true, scenario = true }
local combatLogOwned = false

function MyRun.CombatLogByPlace()
    if type(LoggingCombat) ~= "function" or not GetInstanceInfo then return end
    local okI, _, instanceType = pcall(GetInstanceInfo)
    local wanted = ns.db and ns.db.combatLog and okI and LOG_INSTANCES[instanceType]
    if wanted then
        if combatLogOwned then return end
        local ok, on = pcall(LoggingCombat)
        if not ok or on then return end
        if pcall(LoggingCombat, true) then
            combatLogOwned = true
            ns.Print(COMBATLOGENABLED)
            ns.Log.Add("combatlog", { on = true, where = instanceType })
        end
    elseif combatLogOwned then
        combatLogOwned = false
        pcall(LoggingCombat, false)
        ns.Print(COMBATLOGDISABLED)
        ns.Log.Add("combatlog", { on = false, where = tostring(instanceType) })
    end
end

function MyRun.Init()
    local frame = CreateFrame("Frame", ADDON .. "MyRunFrame")
    frame:RegisterEvent("CHALLENGE_MODE_START")
    frame:RegisterEvent("CHALLENGE_MODE_RESET")
    frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    frame:RegisterEvent("ENCOUNTER_START")
    frame:RegisterEvent("ENCOUNTER_END")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("BAG_UPDATE_DELAYED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    frame:RegisterEvent("PLAYER_LOGOUT")
    frame:SetScript("OnEvent", function(_, event, a, b, c, d, e)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            pcall(MyRun.OnCast, a, c)
        elseif event == "PLAYER_REGEN_DISABLED" then
            pcall(MyRun.AutoStart)
            pcall(MyRun.OnCombatStart)
        elseif event == "PLAYER_REGEN_ENABLED" then
            pcall(MyRun.OnCombatEnd)
        elseif event == "ENCOUNTER_START" then
            pcall(MyRun.OnEncounterStart, a, b)
            -- A raid: the run is the raid instance, and starts at its first boss.
            if not MyRun.IsActive() and IsInRaid and IsInRaid() then
                local name = GetInstanceInfo and select(1, GetInstanceInfo()) or nil
                pcall(MyRun.Start, "raid", name, nil)
                pcall(MyRun.OnEncounterStart, a, b)
                if InCombatLockdown() then pcall(MyRun.OnCombatStart) end
            end
        elseif event == "ENCOUNTER_END" then
            pcall(MyRun.OnEncounterEnd, a, b, e)
        elseif event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_RESET" then
            local name, level = KeyName()
            pcall(MyRun.Start, "key", name, level)
            pcall(MyRun.CombatLogByPlace)
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            C_Timer.After(2, function() pcall(MyRun.Stop, nil) end)
        elseif event == "BAG_UPDATE_DELAYED" then
            MyRun.OnBagsChanged()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Leaving the instance ends a raid run that is still open; and (14/10) a key too: an
            -- abandoned key has no CHALLENGE_MODE_COMPLETED, and its run swallowed every fight
            -- after it, out in the world.
            if run and not run.finished and (run.kind == "raid" or run.kind == "key") and GetInstanceInfo then
                local _, instanceType = GetInstanceInfo()
                local still = (run.kind == "raid" and instanceType == "raid") or (run.kind == "key" and instanceType == "party")
                if not still then pcall(MyRun.Stop, nil) end
            end
            -- (14/10) A /reload in the middle of a key: the run is in memory only, and no
            -- CHALLENGE_MODE_START comes again; it starts again here, from now on.
            if not MyRun.IsActive() and C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
                local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
                if ok and active == true then
                    local name, level = KeyName()
                    pcall(MyRun.Start, "key", name, level)
                end
            end
            pcall(MyRun.AutoStop)
            pcall(MyRun.CombatLogByPlace)
        elseif event == "PLAYER_LOGOUT" then
            -- (20/10) A session that started by itself (the world, a delve, a dungeon) ended only on a change of zone or
            -- after WORLD_IDLE: a /reload or leaving the game threw it away. The user's dummies of 20/10 (18:0x, in the
            -- city) never reached the history: the /reload of 18:15 came first. PLAYER_LOGOUT comes on a /reload too,
            -- and the saved variables are written after it.
            if run and not run.finished and AUTO[run.kind] then pcall(MyRun.Stop, nil) end
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            pcall(MyRun.AutoStop)
            pcall(MyRun.CombatLogByPlace)
        end
    end)
end

-- For the harness.
function MyRun.__reset() run = nil; itemSpells = {}; bagsDirty = true end
function MyRun.__run() return run end
function MyRun.__compact(r) return Compact(r) end
function MyRun.__constants() return { GAP_SECONDS = GAP_SECONDS, COOLDOWN_MIN = COOLDOWN_MIN, HISTORY_SIZE = HISTORY_SIZE,
    WORLD_IDLE = WORLD_IDLE, MAX_WORLD_SAVED = MAX_WORLD_SAVED } end
