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
--   * at the end of the run and of each fight, the meter's numbers of the local player.
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
local COOLDOWN_MIN = 45         -- a spell with a shorter base cooldown is rotation, not a cooldown
local HISTORY_SIZE = 8
local HEALTHSTONE_ITEM = 5512
local MAX_TAKEN_SPELLS = 12
local MAX_RECAP_EVENTS = 10     -- what the game's recap holds (read in a real key)

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
    for _, cat in ipairs({ { "essential", 0 }, { "utility", 1 } }) do
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat[2], false)
        for i = 1, (ok and type(ids) == "table" and #ids or 0) do
            local okI, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, ids[i])
            local spellID = okI and type(info) == "table" and (info.overrideSpellID or info.spellID) or nil
            if type(spellID) == "number" and not seen[spellID] and (info.isKnown == nil or info.isKnown == true) then
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
                    cooldown = cd, charges = charges or 1, category = cat[1], base = info.spellID }
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

---Starts a run. `kind` is "key" or "raid"; `name` the dungeon or raid; `level` the key level.
function MyRun.Start(kind, name, level)
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
        role = MyRun.Role(), class = class, spec = spec, specIcon = specIcon,
        player = UnitName and UnitName("player") or "",
        fights = {}, casts = {}, items = {}, gaps = {}, deaths = {},
        cooldowns = MyRun.ReadCooldowns(),
        lastCast = nil, open = nil, encounter = nil, finished = false,
    }
    if bagsDirty then pcall(ScanBags) end
    if InCombatLockdown() then MyRun.OnCombatStart() end
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
function MyRun.OnCast(unit, spellID)
    if not run or run.finished then return end
    if unit ~= "player" or not Readable(spellID) or type(spellID) ~= "number" then return end
    local t = Elapsed()
    run.casts[#run.casts + 1] = { t, spellID }
    if run.open then
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
    run.metrics = MyRun.Metrics("all")
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

local function Within(t, fights)
    for _, f in ipairs(fights) do
        if t >= f.s and t <= (f.e or math.huge) then return true end
    end
    return false
end

---The scopes the combos offer: whole run, current fight, each boss, the trash.
---@return table[] { key, label }
function MyRun.Scopes(r)
    r = r or run
    local out = { { key = "all", label = L["Whole run"] } }
    -- "Current fight" is the meter's live session: only the run in progress has one.
    if r == run then out[#out + 1] = { key = "current", label = L["Current fight"] } end
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
function MyRun.Own(scope, r)
    r = r or run
    local fights, seconds = FightsOf(scope, r)
    local out = { combatSeconds = seconds, casts = 0, bySpell = {}, gaps = { count = 0, total = 0, longest = 0 },
                  potions = 0, healthstones = 0, deaths = {}, cooldowns = {}, bossCount = 0, potionBosses = 0 }
    if not r then return out end
    local inScope = scope == "all" and function() return true end or function(t) return Within(t, fights) end
    if r.casts then
        for _, c in ipairs(r.casts) do
            if inScope(c[1]) then
                out.casts = out.casts + 1
                out.bySpell[c[2]] = (out.bySpell[c[2]] or 0) + 1
            end
        end
    else
        -- A saved run: the casts are counts per spell, for the run and for each fight.
        local tables = scope == "all" and { r.bySpell or {} } or {}
        if scope ~= "all" then for _, f in ipairs(fights) do tables[#tables + 1] = f.bySpell or {} end end
        for _, t in ipairs(tables) do
            for id, n in pairs(t) do
                out.casts = out.casts + n
                out.bySpell[id] = (out.bySpell[id] or 0) + n
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
        if inScope(it[1]) then
            if it[2] == "potion" then out.potions = out.potions + 1 else out.healthstones = out.healthstones + 1 end
        end
    end
    for _, f in ipairs(fights) do
        if f.boss then
            out.bossCount = out.bossCount + 1
            for _, it in ipairs(r.items or {}) do
                if it[2] == "potion" and it[1] >= f.s and it[1] <= (f.e or math.huge) then out.potionBosses = out.potionBosses + 1; break end
            end
        end
    end
    for _, d in ipairs(r.deaths or {}) do
        if inScope(d.t) then out.deaths[#out.deaths + 1] = d end
    end
    -- Cooldowns: used = casts of the spell in the scope; fitted = how many the combat time of
    -- the scope allows, charges counted. Never fewer than used.
    for _, cd in ipairs(r.cooldowns or {}) do
        if cd.cooldown >= COOLDOWN_MIN then
            local used = (out.bySpell[cd.spellID] or 0) + (cd.base and cd.base ~= cd.spellID and out.bySpell[cd.base] or 0)
            local fitted = math.floor(seconds / cd.cooldown) + (cd.charges or 1)
            if seconds <= 0 then fitted = 0 end
            if fitted < used then fitted = used end
            out.cooldowns[#out.cooldowns + 1] = { spellID = cd.spellID, name = cd.name, cooldown = cd.cooldown,
                used = used, fitted = fitted, category = cd.category,
                idle = fitted > used and (fitted - used) * cd.cooldown or 0 }
        end
    end
    table.sort(out.cooldowns, function(a, b)
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
function MyRun.Metrics(scope, r)
    r = r or run
    -- A saved run has only the numbers taken at its end, for the whole run.
    if r and r ~= run then return scope == "all" and r.metrics or nil end
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
    -- Damage taken by spell, with the game's marks: the top ones.
    local session = get(E.DamageTaken)
    local mine
    for _, s in ipairs(session and session.combatSources or {}) do
        if Readable(s.isLocalPlayer) and s.isLocalPlayer == true then mine = s; break end
    end
    out.takenSpells = {}
    -- A past fight has no list by spell: the meter answers the spells of a source only for a
    -- session TYPE (current, overall), not by id. The screen says so for a boss.
    if mine and Readable(mine.sourceGUID) and C_DamageMeter.GetCombatSessionSourceFromType and type(scope) ~= "number" then
        local sessionValue = scope == "current" and ns.Data.SessionValue(0) or ns.Data.SessionValue(1)
        local ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromType, sessionValue, E.DamageTaken, mine.sourceGUID, mine.sourceCreatureID)
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
    return out
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
    checked[#checked + 1] = L["avoidable damage"]
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
                title = title, detail = format(L["%d%% of all you took · %s of the group"], math.floor(share + 0.5),
                    m.avoidable.rank and format(L["%dº"], m.avoidable.rank) or "?"),
                number = format("%d%%", math.floor(share + 0.5)) }
        end
    end

    -- 3. Interrupts cast that cut nothing (casts of interrupt spells minus the meter's credit).
    checked[#checked + 1] = L["interrupts"]
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

    -- 4. Cooldowns left idle (DPS and healer: essentials; tank: the defensives first).
    checked[#checked + 1] = L["cooldowns"]
    for _, cd in ipairs(own.cooldowns) do
        local ratio = cd.fitted > 0 and cd.used / cd.fitted or 1
        local defensive = cd.category == "utility"
        -- The tank is judged by the defensives; the others by the offensive cooldowns, and by a
        -- defensive only when it was never pressed at all.
        local matters = defensive and (role == "TANK" or cd.used == 0) or (not defensive and role ~= "TANK")
        if matters and cd.fitted >= 2 and ratio < 0.7 then
            out[#out + 1] = { kind = defensive and "defensive" or "cooldown", severity = ratio < 0.5 and 2 or 3, spellID = cd.spellID,
                title = format(L["%s: used %d times; %d fitted"], cd.name, cd.used, cd.fitted),
                detail = format(L["cooldown of %s · idle %s in total"], Clock(cd.cooldown), Clock(cd.idle)),
                number = format("%d%%", math.floor(ratio * 100 + 0.5)) }
        end
    end

    -- 5. Standing there: gaps between casts in combat.
    checked[#checked + 1] = L["gaps without casting"]
    if own.gaps.count >= 3 and own.gaps.total >= 30 then
        out[#out + 1] = { kind = "gaps", severity = own.gaps.total >= 90 and 2 or 3, atlas = "worldquest-icon-clock",
            title = format(L["%d gaps without casting of more than %d s in combat"], own.gaps.count, GAP_SECONDS),
            detail = format(L["%s idle in total · the longest: %d s at %s"], Clock(own.gaps.total), math.floor(own.gaps.longest + 0.5), Clock(own.gaps.longestAt or 0)),
            number = own.perMinute and format(L["%d/min"], math.floor(own.perMinute + 0.5)) or "" }
    end

    -- 6. Potions and the healthstone.
    checked[#checked + 1] = L["potions"]
    if own.bossCount > 0 and own.potionBosses < own.bossCount then
        out[#out + 1] = { kind = "potion", severity = 3, item = true,
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
-- History: the last runs, saved per character
--------------------------------------------------------------------------------
local function Store()
    if RocketMeterRunsDB == nil then RocketMeterRunsDB = {} end
    RocketMeterRunsDB.myRuns = RocketMeterRunsDB.myRuns or {}
    return RocketMeterRunsDB.myRuns
end

---Compacts the run for the saved file: casts become counts per spell per fight.
local function Compact(r)
    local c = { kind = r.kind, name = r.name, level = r.level, date = r.date, role = r.role, class = r.class,
                spec = r.spec, specIcon = r.specIcon, player = r.player, elapsed = r.elapsed, result = r.result,
                fights = {}, gaps = r.gaps, items = r.items, deaths = r.deaths, cooldowns = r.cooldowns,
                metrics = r.metrics, bySpell = {}, castCount = #r.casts, finished = true }
    for i, f in ipairs(r.fights) do
        c.fights[i] = { s = f.s, e = f.e, boss = f.boss, enc = f.enc, success = f.success, bySpell = {} }
    end
    for _, cast in ipairs(r.casts) do
        c.bySpell[cast[2]] = (c.bySpell[cast[2]] or 0) + 1
        for _, f in ipairs(c.fights) do
            if cast[1] >= f.s and cast[1] <= (f.e or math.huge) then f.bySpell[cast[2]] = (f.bySpell[cast[2]] or 0) + 1; break end
        end
    end
    return c
end

function MyRun.Save()
    if not run or not run.finished then return end
    local list = Store()
    table.insert(list, 1, Compact(run))
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
    frame:SetScript("OnEvent", function(_, event, a, b, c, d, e)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            pcall(MyRun.OnCast, a, c)
        elseif event == "PLAYER_REGEN_DISABLED" then
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
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            C_Timer.After(2, function() pcall(MyRun.Stop, nil) end)
        elseif event == "BAG_UPDATE_DELAYED" then
            MyRun.OnBagsChanged()
        elseif event == "PLAYER_ENTERING_WORLD" then
            -- Leaving the instance ends a raid run that is still open.
            if run and not run.finished and run.kind == "raid" and GetInstanceInfo then
                local _, instanceType = GetInstanceInfo()
                if instanceType ~= "raid" then pcall(MyRun.Stop, nil) end
            end
        end
    end)
end

-- For the harness.
function MyRun.__reset() run = nil; itemSpells = {}; bagsDirty = true end
function MyRun.__run() return run end
function MyRun.__constants() return { GAP_SECONDS = GAP_SECONDS, COOLDOWN_MIN = COOLDOWN_MIN, HISTORY_SIZE = HISTORY_SIZE } end
