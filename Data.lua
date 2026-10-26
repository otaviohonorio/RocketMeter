-- RocketMeter | Data.lua
-- The single layer over C_DamageMeter. No other file talks to the game's API.
--
-- THREE LESSONS THAT COST DEARLY:
--
-- 0) **An addon cannot hand a secret value back to the API.** Trying
--    `GetCombatSessionSourceFromType(type, attribute, secretGuid)` answers
--    "Secret values are only allowed during untainted", and the error brings the whole drawing down.
--    It was the base of crossing metrics and it was wrong: in combat the GUID is secret, so
--    metrics can only be crossed **out** of combat. Inside it, each metric is a list of its
--    own, sorted, and the only row that can be matched is the player's own
--    (`isLocalPlayer`, which stays readable).
--
-- 1) A column is **(metric, field)**, not only a metric. The per-second value comes in the
--    `amountPerSecond` field of the SAME object that brings the total -- that is how meters do it. The
--    attributes `Enum.DamageMeterType.Dps` and `.Hps` return the same totals as damage/healing, and
--    using them as a "DPS column" makes the screen repeat the total (it was the bug until 0.8.0).
--
-- 2) In combat the fields are SECRET VALUES: they cannot be compared, added or formatted -- only
--    passed on to a widget. Out of combat they become readable numbers again.
--
-- 3) **The `Deaths` metric is not a sum, it is a LIST OF DEATHS.** Each entry of
--    `combatSources` there is *one death*, not a player with a count: the structure
--    `DamageMeterCombatSource` brings `deathRecapID` and `deathTimeSeconds`, and Blizzard's
--    meter treats the row as an event -- `GetValueText` returns the death's **time**
--    ("3m 22s") and `GetStatusValue` returns **a fixed 1**, because there is no "amount"
--    (`DamageMeterEntry.lua:562-604`). Reading `totalAmount` there gives 0 for whoever died and nothing
--    for whoever did not, which is exactly what showed in the first real run.
--    That is why the deaths column has `field = "count"` and is **counted**, not added.
local ADDON, ns = ...
local L = ns.L

local Data = {}
ns.Data = Data

--------------------------------------------------------------------------------
-- The catalogue of columns
--------------------------------------------------------------------------------
local columnList, columnByKey, columnItems, itemByColumn

local function BuildColumns()
    local E = Enum.DamageMeterType
    if not E then return {}, {} end

    -- `part` IS THE SECOND LINE OF THE SCOREBOARD'S HEADER (30/09): the family's name goes on top
    -- ("Damage") and the part under each column ("total", "per s", "share"). The user, on the
    -- one-line "Interr - Missed - CC": *"só errou na coluna é confuso, pode ser qualquer coisa,
    -- só se tu montar uma coluna com dois valores um titulo e sub titulo"*. A family with one
    -- column has no part: the name alone says it.
    local list = {
        { key = "damage",     attr = E.DamageDone,           field = "total",     short = L["Dmg"],    label = L["Total damage"],               part = L["total"] },
        { key = "dps",        attr = E.DamageDone,           field = "perSecond", short = L["DPS"],    label = L["Damage per second"],          part = L["per s"] },
        { key = "damagepct",  attr = E.DamageDone,           field = "percent",   short = L["Dmg%"],   label = L["Share of the group damage"],  part = L["share"] },
        { key = "healing",    attr = E.HealingDone,          field = "total",     short = L["Heal"],   label = L["Total healing"],              part = L["total"] },
        { key = "hps",        attr = E.HealingDone,          field = "perSecond", short = L["HPS"],    label = L["Healing per second"],         part = L["per s"] },
        { key = "healingpct", attr = E.HealingDone,          field = "percent",   short = L["Heal%"],  label = L["Share of the group healing"], part = L["share"] },
        { key = "absorb",     attr = E.Absorbs,              field = "total",     short = L["Absorb"], label = L["Absorbs"] },
        { key = "taken",      attr = E.DamageTaken,          field = "total",     short = L["Taken"],  label = L["Damage taken"],               part = L["total"] },
        { key = "takenps",    attr = E.DamageTaken,          field = "perSecond", short = L["TPS"],    label = L["Damage taken per second"],    part = L["per s"] },
        { key = "avoidable",  attr = E.AvoidableDamageTaken, field = "total",     short = L["Avoid"],  label = L["Avoidable damage"] },
        { key = "interrupts", attr = E.Interrupts,           field = "total",     short = L["Interr"], label = L["Interrupts"] },
        -- (!) NO COLUMN OF CASTS (30/09, night). "Interrupts that missed" and "CC used" were two
        -- columns counted from casts (Casts.lua). Read in the diary of a real key: the casts of
        -- the four others arrived 100% secret (1,335 / 650 / 204 / 846 casts, none readable),
        -- so the columns filled for the local player alone. The user: *"tem que mostrar de
        -- todos, se não, não faz sentido ter essas colunas"*. The counting stays, for the
        -- player's own breakdown.
        { key = "dispels",    attr = E.Dispels,              field = "total",     short = L["Dispel"], label = L["Dispels"] },
        -- `count`, not `total`: in the deaths metric each entry of the list is ONE DEATH, not a
        -- player with a count. See lesson 3 at the top of the file.
        { key = "deaths",     attr = E.Deaths,               field = "count",     short = L["Deaths"], label = L["Player deaths"] },
        { key = "enemies",    attr = E.EnemyDamageTaken,     field = "total",     short = L["Enemies"],label = L["Damage on enemies"] },
    }

    -- THE FAMILY'S NAME, for the section header. "Dano", not "Dano total": the header names
    -- the METRIC, and its total already shows beside it. All these keys already existed in the
    -- language file -- none was made up for this.
    local FAMILY = {
        [E.DamageDone]           = L["Damage"],
        [E.HealingDone]          = L["Healing"],
        [E.Absorbs]              = L["Absorbs"],
        [E.DamageTaken]          = L["Damage taken"],
        [E.AvoidableDamageTaken] = L["Avoidable damage"],
        [E.Interrupts]           = L["Interrupts"],
        [E.Dispels]              = L["Dispels"],
        [E.Deaths]               = L["Deaths"],
        [E.EnemyDamageTaken]     = L["Damage on enemies"],
    }
    -- A METRIC THAT COUNTS, and not one that adds. The difference matters for whoever draws: "339M" and "8"
    -- need very different widths, and `field` does NOT tell the two apart -- interrupts and
    -- dispels are also `total`, only of a count.
    --
    -- The distinction lives here, with the metric's definition, and not in the window: it is a property of the
    -- DATA ("this metric yields small numbers"), not of the screen.
    local CONTAGEM = {
        [E.Interrupts] = true,
        [E.Dispels] = true,
        [E.Deaths] = true,
    }

    for i = 1, #list do
        list[i].family = list[i].family or FAMILY[list[i].attr] or list[i].short
        list[i].group = list[i].group or list[i].attr
        list[i].counts = CONTAGEM[list[i].attr] or nil
    end

    local byKey = {}
    for i, def in ipairs(list) do
        def.order = i
        byKey[def.key] = def
    end

    -- THE ITEMS: what the player turns on and off, which is not the same thing as a column.
    --
    -- The user's request: *"onde escolhe as colunas na configuracao o dano e dps e cura e cps tem
    -- que ser um so item"*. Total and rate are the same measure in two units -- offering both
    -- as independent choices asked the player for a decision he has no reason to take.
    --
    -- The rule is by SHAPE, not by a list of names: every family that has a total AND a rate becomes
    -- an item. That catches the two pairs he named (damage/DPS, healing/HPS) and also damage
    -- taken/DTPS, which has exactly the same shape -- treating the third differently would be
    -- arbitrary. A percentage does NOT come in: "how much of the group's total" is another question, and he did not
    -- ask for it to come along.
    local totalDe, taxaDe = {}, {}
    for _, def in ipairs(list) do
        if def.field == "total" then totalDe[def.attr] = def end
        if def.field == "perSecond" then taxaDe[def.attr] = def end
    end

    local items, itemDe = {}, {}
    for _, def in ipairs(list) do
        local par = def.field == "total" and taxaDe[def.attr]
        if par then
            -- The label is made of the two halves already translated ("Dano total / DPS"): three
            -- new translation keys to say what two existing ones already say would be a
            -- third thing to keep up to date in two languages.
            local item = { key = def.key, keys = { def.key, par.key },
                label = def.label .. " / " .. par.short, attr = def.attr }
            items[#items + 1] = item
            itemDe[def.key], itemDe[par.key] = item, item
        elseif def.field ~= "perSecond" or not totalDe[def.attr] then
            -- Taxa sem total marcado no catalogo continua sendo item proprio; e o `elseif` que
            -- impede a taxa de aparecer DUAS vezes na lista.
            local item = { key = def.key, keys = { def.key }, label = def.label, attr = def.attr }
            items[#items + 1] = item
            itemDe[def.key] = item
        end
    end

    return list, byKey, items, itemDe
end

local function EnsureColumns()
    if not columnList then
        columnList, columnByKey, columnItems, itemByColumn = BuildColumns()
    end
    return columnList, columnByKey
end

function Data.GetColumns()
    local list = EnsureColumns()
    return list
end

function Data.GetColumn(key)
    local _, byKey = EnsureColumns()
    return byKey[key]
end

function Data.GetShortLabel(key)
    local def = Data.GetColumn(key)
    return def and def.short or "?"
end

function Data.GetAttributeLabel(key)
    local def = Data.GetColumn(key)
    return def and def.label or "?"
end

--- A column's family name ("Dano"), for the section header.
function Data.GetFamilyLabel(key)
    local def = Data.GetColumn(key)
    return def and def.family or "?"
end

---Metrics where the most is the worst: damage taken, avoidable damage, deaths.
---(14/10) Nobody "leads" them: the highlight of the leader (the scoreboard's cream) went to whoever
---died most, the same as to the top damage.
function Data.IsNegativeColumn(key)
    local def = Data.GetColumn(key)
    if not def then return false end
    local E = Enum.DamageMeterType
    return def.attr == E.DamageTaken
        or def.attr == E.AvoidableDamageTaken
        or def.attr == E.Deaths
end

function Data.IsPercentColumn(key)
    local def = Data.GetColumn(key)
    return def ~= nil and def.field == "percent"
end

---Converte colunas salvas no formato antigo (ids de Enum) para as chaves atuais.
function Data.MigrateColumns(saved)
    if type(saved) ~= "table" then return nil end

    local E = Enum.DamageMeterType
    if not E then return nil end

    local fromEnum = {
        [E.DamageDone] = "damage",
        [E.Dps] = "dps",
        [E.HealingDone] = "healing",
        [E.Hps] = "hps",
        [E.Absorbs] = "absorb",
        [E.DamageTaken] = "taken",
        [E.AvoidableDamageTaken] = "avoidable",
        [E.Interrupts] = "interrupts",
        [E.Dispels] = "dispels",
        [E.Deaths] = "deaths",
        [E.EnemyDamageTaken] = "enemies",
    }

    local out, changed, dropped = {}, false, false
    for _, entry in ipairs(saved) do
        if type(entry) == "number" then
            changed = true
            local key = fromEnum[entry]
            if key then out[#out + 1] = key end
        elseif Data.GetColumn(entry) then
            out[#out + 1] = entry
        else
            -- (14/10) A column that no longer exists is not "the old format": it is dropped, and
            -- said apart (third value), without throwing away the chosen sort.
            dropped = true
        end
    end

    if #out == 0 then return nil, changed, dropped end

    -- AND THE LOCKED ORDER HOLDS FOR THE SAVED LIST. A list from before this version may have healing
    -- between damage and DPS, or the total without the rate -- and both break the bar that crosses the
    -- pair.
    --
    -- ⚑ BUT THAT IS NOT A "FORMAT MIGRATION", and the difference matters. The second return makes the
    -- profile ERASE the chosen sort (`active.sortBy = nil`) and write in the chat that the
    -- columns were migrated -- right when there was a numeric Enum id saved, false when the
    -- list was only regrouped. Lumping the two made the addon, at every login, throw away the column
    -- the player chose to sort by and announce a migration that did not happen.
    --
    -- So the second value goes back to meaning ONLY "there was an old format". The normalised
    -- list is always returned, and the profile adopts it without ceremony.
    local normal = Data.NormalizeColumns(out)
    return normal, changed, dropped
end

--------------------------------------------------------------------------------
-- Conjuntos prontos
--------------------------------------------------------------------------------
--- The ITEMS the player turns on and off in `/rm columns`, in the catalogue's order.
---
--- An item can count for TWO columns (the total+rate pair). Whoever wants the raw list of columns
--- still has `Data.GetColumns`.
function Data.GetColumnItems()
    EnsureColumns()
    return columnItems
end

--- The item a column belongs to -- so any key finds its pair.
function Data.GetItemFor(key)
    EnsureColumns()
    return itemByColumn[key]
end

--- THE LOCKED ORDER of the list of columns, and the complete pair.
---
--- The user's request: *"vamos bloquear para que a coluna de Dano sempre venha primeiro que a DPS
--- e assim com a cura sempre na frente do CPS"*.
---
--- He asked for it because the two came to share ONE bar: the bar crosses from the total's column
--- to the rate's, and a list that puts healing between the two makes the damage bar cross
--- under a healing number. It is not a preference of arrangement -- it is what keeps the drawing
--- possible.
---
--- Three things happen here, in this order:
---
--- 1. **it groups by family**, keeping the order in which each family first showed
---   (whoever put healing ahead of damage keeps healing ahead);
--- 2. **it completes the pair**: a family with the total ticked and not the rate gets the rate, because an item
---   the player sees as one has to be whole on screen;
--- 3. **it sorts within the family**: total, then rate, then percentage.
---
--- @return table the normalised list, boolean changed
function Data.NormalizeColumns(columns)
    EnsureColumns()
    local PESO = { total = 1, count = 1, perSecond = 2, percent = 3 }

    local familias, porAttr = {}, {}
    for _, key in ipairs(columns) do
        local def = Data.GetColumn(key)
        if def and not porAttr[def.attr] then
            porAttr[def.attr] = { attr = def.attr, keys = {} }
            familias[#familias + 1] = porAttr[def.attr]
        end
        -- Chave repetida na lista salva entra uma vez so.
        if def and not porAttr[def.attr][key] then
            porAttr[def.attr][key] = true
            local f = porAttr[def.attr]
            f.keys[#f.keys + 1] = key
        end
    end

    for _, familia in ipairs(familias) do
        -- IT COMPLETES THE PAIR. A list saved before this version may have only the total.
        for _, key in ipairs({ unpack(familia.keys) }) do
            local item = itemByColumn[key]
            if item then
                for _, irma in ipairs(item.keys) do
                    if not familia[irma] then
                        familia[irma] = true
                        familia.keys[#familia.keys + 1] = irma
                    end
                end
            end
        end

        -- AND SORTS WITHIN IT. `table.sort` is not stable, so the tie-break uses the position in the
        -- catalogue -- two columns of the same weight (there are none today) would never swap places by themselves.
        table.sort(familia.keys, function(a, b)
            local da, db = Data.GetColumn(a), Data.GetColumn(b)
            local pa, pb = PESO[da.field] or 9, PESO[db.field] or 9
            if pa ~= pb then return pa < pb end
            return da.order < db.order
        end)
    end

    local out = {}
    for _, familia in ipairs(familias) do
        for _, key in ipairs(familia.keys) do out[#out + 1] = key end
    end

    local mudou = #out ~= #columns
    if not mudou then
        for i = 1, #out do
            if out[i] ~= columns[i] then mudou = true break end
        end
    end
    return out, mudou
end

function Data.GetPresets()
    return {
        mplus = {
            label = L["Mythic+"],
            columns = { "damage", "dps", "healing", "hps", "interrupts", "avoidable", "deaths" },
        },
        raid = {
            label = L["Raid"],
            columns = { "damage", "dps", "damagepct", "healing", "hps", "taken", "deaths" },
        },
        damage = {
            label = L["Damage only"],
            columns = { "damage", "dps", "damagepct" },
        },
    }
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Session types
--------------------------------------------------------------------------------
-- **Do not guess the numbers.** There is `Enum.DamageMeterSessionType` (Current / Overall /
-- Expired) and its values are not necessarily 0 and 1. Passing a hard-coded number is
-- what made the window read a different session than it should.
function Data.SessionValue(which)
    local E = Enum.DamageMeterSessionType
    if which == 1 or which == "overall" then
        return E and E.Overall or 1
    end
    return E and E.Current or 0
end

--- This client's real values, for the log and for /rm debug.
function Data.DescribeSessionEnum()
    local E = Enum.DamageMeterSessionType
    if not E then return "Enum.DamageMeterSessionType does not exist" end
    return format("Current=%s Overall=%s Expired=%s",
        tostring(E.Current), tostring(E.Overall), tostring(E.Expired))
end

function Data.IsAvailable()
    return C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable and C_DamageMeter.IsDamageMeterAvailable()
end

local function HasSources(session)
    return session ~= nil and session.combatSources ~= nil and session.combatSources[1] ~= nil
end

--- The id of the most recent session. The field's name varies between versions, so it accepts both.
local function NewestSessionID()
    if not C_DamageMeter.GetAvailableCombatSessions then return nil end
    local list = C_DamageMeter.GetAvailableCombatSessions()
    if not list or #list == 0 then return nil end
    local newest = list[#list]
    if type(newest) == "table" then
        return newest.sessionID or newest.sessionId or newest.id
    end
    return newest
end

--- A metric's session.
---
--- After `ResetAllCombatSessions`, the "current" session (type 0) can come **empty while the
--- fight is going on**, and the new data shows in a new session, addressed by id. Without this
--- fallback the window stays blank during combat and only shows the numbers when it ends --
--- exactly the reported symptom. That is why both paths stay.
function Data.GetSession(sessionType, attributeId)
    if not Data.IsAvailable() then return nil end

    local session = C_DamageMeter.GetCombatSessionFromType(Data.SessionValue(sessionType), attributeId)
    if HasSources(session) then return session end

    -- It only makes sense for the current combat: the overall is accumulated, not a loose session.
    if sessionType == 0 and C_DamageMeter.GetCombatSessionFromID then
        local id = NewestSessionID()
        if id then
            local byId = C_DamageMeter.GetCombatSessionFromID(id, attributeId)
            if HasSources(byId) then
                return byId
            end
        end
    end

    return session
end

--- Used by /rm debug: says which path the data came through.
function Data.DescribeSources(sessionType, attributeId)
    if not Data.IsAvailable() then return "API unavailable" end

    local byType = C_DamageMeter.GetCombatSessionFromType(Data.SessionValue(sessionType), attributeId)
    local typeCount = byType and byType.combatSources and #byType.combatSources or 0

    local id = NewestSessionID()
    local idCount = 0
    if id and C_DamageMeter.GetCombatSessionFromID then
        local byId = C_DamageMeter.GetCombatSessionFromID(id, attributeId)
        idCount = byId and byId.combatSources and #byId.combatSources or 0
    end

    return format("by type: %d source(s) | by id (%s): %d source(s)",
        typeCount, tostring(id), idCount)
end

--- The player himself inside a metric.
---
--- `isLocalPlayer` stays readable in combat, so it is the only way to match a row with
--- another metric while the fight is going on -- and it is the row that matters most to whoever is playing.
function Data.GetLocalPlayerSource(session)
    local list = session and session.combatSources
    if not list then return nil end

    for i = 1, #list do
        local candidate = list[i]
        local flag = candidate.isLocalPlayer
        if flag ~= nil and not issecretvalue(flag) and flag == true then
            return candidate
        end
    end
    return nil
end

--- Is this entry of the deaths metric a real death?
---
--- **It is `deathRecapID` that decides, and not the presence in the list.** Blizzard's own meter treats
--- the entry as a death only when `deathRecapID ~= 0`, and asks that same question in FOUR places
--- before drawing -- in the name, in the value, and in the bar's two limits
--- (`DamageMeterEntry.lua:563,572,580,594`). An entry with a zero recap it draws as a plain
--- row; we counted it as a death.
---
--- The report that exposed it: a hunter showed **19 deaths** in a mythic+ without having died --
--- he used "Feign Death" many times. **It is not confirmed** that the feigning produces
--- the extra entries; what is confirmed is that there are entries in the list the game does NOT count
--- as a death, and that we counted. `/rm fontes` shows each entry's `recap`.
---
--- `deathRecapID` is **`NeverSecret`** (`DamageMeterDocumentation.lua:207`), so comparing is
--- safe even in combat and during the whole key -- which is exactly when this shows.
-- (14/10) Was declared INSIDE Data.GetRows, so Data.GetDeathList only existed after the meter
-- window drew once: with the window hidden, "My run" lost the deaths without a word.
local function IsRealDeath(source)
    local recap = source.deathRecapID
    if recap == nil or issecretvalue(recap) then return false end
    return recap ~= 0
end

--- The session's deaths, one per entry, with WHO died and WHEN.
---
--- ⚑ THIS EXISTS BECAUSE `Run.lua` ONLY KNOWS THE "WHEN". It is written there, as an accepted limit:
--- `CHALLENGE_MODE_DEATH_COUNT_UPDATED` gives the instant and the counter, never the name. The request of
--- 10/09/2026: *"a outra marcação é a morte, poderia ter o ícone da classe que morreu"* -- and the
--- answer was at the other end, in the meter's deaths metric, where **each entry is a
--- death** and brings `classFilename` along.
---
--- `deathTimeSeconds` goes along, but it is for **checking**, not for placing: there is no
--- confirming from here what its clock's origin is (session? combat? key?), and guessing it
--- would put a skull at the wrong minute. What places is still `Run`.
--- @return table list `{ { name, class, when }, ... }`, already filtered by `deathRecapID ~= 0`
function Data.GetDeathList(sessionType)
    local out = {}
    if not Enum or not Enum.DamageMeterType then return out end

    local session = Data.GetSession(sessionType, Enum.DamageMeterType.Deaths)
    local sources = session and session.combatSources
    if not sources then return out end

    for i = 1, #sources do
        local src = sources[i]
        if IsRealDeath(src) then
            local nome = src.name
            if issecretvalue(nome) then nome = nil end
            local classe = src.classFilename
            if issecretvalue(classe) then classe = nil end
            local quando = src.deathTimeSeconds
            if quando ~= nil and issecretvalue(quando) then quando = nil end
            -- (01/10) `local_` and `recap` are for "Minha corrida": the player's own deaths, and
            -- the recap id to read the blow-by-blow. `isLocalPlayer` is never secret.
            local recap = src.deathRecapID
            if recap ~= nil and issecretvalue(recap) then recap = nil end
            -- (01/10) `guid`, for the screen of ONE player (PlayerWindow.lua): two players of
            -- the same name on two realms are told apart by it.
            local guid = src.sourceGUID
            if guid ~= nil and issecretvalue(guid) then guid = nil end
            out[#out + 1] = { nome = nome, classe = classe, quando = quando, guid = guid,
                local_ = src.isLocalPlayer == true, recap = recap }
        end
    end
    return out
end

--- How many entries the player himself has in this metric.
---
--- It exists because of the deaths, where the list has one entry per death. `isLocalPlayer` is
--- `NeverSecret`, so this count works **even in combat** -- it is the only row that
--- stays countable when the GUID goes away.
function Data.CountLocalPlayerEntries(session)
    local list = session and session.combatSources
    if not list then return nil end

    local n = 0
    for i = 1, #list do
        local flag = list[i].isLocalPlayer
        -- (14/10) Only real deaths: an entry with recap 0 is not one (the "19 deaths" hunter).
        if flag ~= nil and not issecretvalue(flag) and flag == true and IsRealDeath(list[i]) then
            n = n + 1
        end
    end
    return n
end

function Data.GetDuration(sessionType)
    if not Data.IsAvailable() then return 0 end
    return C_DamageMeter.GetSessionDurationSeconds(Data.SessionValue(sessionType)) or 0
end

function Data.ResetAll()
    if Data.IsAvailable() then
        C_DamageMeter.ResetAllCombatSessions()
    end
end

--- Resetting erases the current combat AND the overall -- it cannot be undone, so it asks first.
--- `skipConfirm` exists for the chat command of whoever knows what he is doing.
function Data.RequestReset(skipConfirm)
    if skipConfirm then
        Data.ResetAll()
        if ns.Window then ns.Window.Refresh(true) end
        ns.Print(L["sessions cleared."])
        return
    end

    StaticPopupDialogs["ROCKETMETER_RESET"] = StaticPopupDialogs["ROCKETMETER_RESET"] or {
        text = L["Clear the current fight and the overall? This cannot be undone."],
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            Data.ResetAll()
            if ns.Window then ns.Window.Refresh(true) end
            ns.Print(L["sessions cleared."])
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    StaticPopup_Show("ROCKETMETER_RESET")
end

--------------------------------------------------------------------------------
-- Building the rows
--------------------------------------------------------------------------------
local function ValueFromSource(source, def, sessionTotal)
    if not source then return nil end

    if def.field == "total" then
        return source.totalAmount
    elseif def.field == "perSecond" then
        return source.amountPerSecond
    elseif def.field == "percent" then
        local value, total = source.totalAmount, sessionTotal
        -- A percentage needs arithmetic: it only exists when both values are readable.
        if value == nil or total == nil then return nil end
        if issecretvalue(value) or issecretvalue(total) or total <= 0 then return nil end
        return value / total * 100
    end
    return nil
end

--- Builds the rows: one per actor, with one value per column.
---
--- The order comes from the API (the query of the sorting metric) because sorting in Lua would need comparing
--- values -- forbidden in combat. `ascending` walks the list backwards, which compares nothing.
--- @param columns string[] column keys
--- @return table[]|nil rows { source = <combat_source>, values = { [column] = number } }
--- @return table|nil session
--- @param offset number|nil how many rows to skip at the top (scrolling)
--- @return table[]|nil rows
--- @return table|nil session
--- @return number total how many actors there are in all, to limit the scrolling
function Data.GetRows(sessionType, sortKey, columns, maxRows, ascending, offset)
    local sortDef = Data.GetColumn(sortKey)
    if not sortDef then return nil, nil end

    local session = Data.GetSession(sessionType, sortDef.attr)
    local sources = session and session.combatSources
    if not sources then return nil, nil end

    -- One query per metric (not per row): it serves the percentage and finding the
    -- player's own row when the GUID is secret.
    local sessions = { [sortDef.attr] = session }
    local function SessionFor(attr)
        local cached = sessions[attr]
        if cached == nil then
            cached = Data.GetSession(sessionType, attr) or false
            sessions[attr] = cached
        end
        return cached or nil
    end

    local sessionTotals = {}
    for c = 1, #columns do
        local def = Data.GetColumn(columns[c])
        if def and def.field == "percent" and sessionTotals[def.attr] == nil then
            local other = SessionFor(def.attr)
            sessionTotals[def.attr] = other and other.totalAmount or false
        end
    end

    -- An index guid -> actor, per metric.
    --
    -- The crossing used to use `GetCombatSessionSourceFromType`, which returns the **spells
    -- container** -- it has `totalAmount` and `combatSpells`, but **no `amountPerSecond`**. That is why
    -- the crossed rate columns (HPS) stayed blank while the total showed.
    -- The session's list brings the whole actor; an index per metric solves it, and also swaps N
    -- API calls per row for one per column.
    --- An actor's identity without using the GUID.
    ---
    --- `classFilename` and `specIconID` are **`NeverSecret`** in the structure's documentation
    --- (`DamageMeterCombatSource`), so they stay readable where the GUID is not -- inside
    --- combat and during the whole key, which is exactly when the crossing failed and the
    --- healer showed with no healing at all.
    ---
    --- It is not a real identity: two players of the same specialization collide. That is why the
    --- key is only used when it is **unique in both lists** -- the source one and the metric's. In
    --- a tie the addon returns nil and the cell stays empty, which is better than swapping the
    --- numbers of two players.
    local function IdentityKey(source)
        local class, icon = source.classFilename, source.specIconID
        if class == nil or issecretvalue(class) then return nil end
        if icon == nil or issecretvalue(icon) then return nil end
        return tostring(class) .. "/" .. tostring(icon)
    end

    -- THE LIST OF ROWS IS THE UNION OF THE ACTORS OF ALL THE METRICS SHOWN.
    --
    -- It was the list of ONE metric -- the one that sorts the window -- and that erased people. Two phrases of the
    -- user, on the same day, which are the same rule seen from two angles:
    --
    --   "o healer pode dar 0 dano e curar muito, ele tem que aparecer no medidor"
    --   "pode ter alguém que não cura e nem dá dano, só dá interrupt, tem que aparecer"
    --
    -- Whoever does not score in the sorted metric was not in its list, and so had no row --
    -- not even to show zero. The meter showed "who did damage", not "who was there".
    --
    -- EACH ACTOR ADDED REMEMBERS WHICH METRIC IT CAME FROM (`rowAttr`), and that is required: the
    -- loop below seeds the cache with `cache[sortDef.attr] = source`, which for an actor coming
    -- from healing would put his HEALING in the damage column. The sorted metric's value, for him, comes from the
    -- normal lookup -- it does not find him, it is conclusive, and it becomes zero. Which is the right number.
    --
    -- DEDUPLICATION, and the care is the same as in the rest of the file: by GUID when it is readable
    -- (all content outside mythic+), and by class+spec when it is not. Where the identity does not
    -- serve, the actor does NOT come in -- duplicating a row is worse than missing one, because the numbers
    -- come to be counted twice in front of the player.
    local rowAttr = {}
    do
        local uniao, vistoGuid, vistoIdentidade = {}, {}, {}

        -- (14/10) Sorted by DEATHS, the base list has one entry per death, not per player: whoever
        -- died 3 times had 3 lines. Then each player once (the count is the column's value), and
        -- an entry that is no death (recap 0) is no line.
        local porObito = sortDef.field == "count"
        for i = 1, #sources do
            local source = sources[i]
            local guid = source.sourceGUID
            local guidLegivel = guid ~= nil and not issecretvalue(guid)
            local key = IdentityKey(source)
            local repetido = porObito and ((guidLegivel and vistoGuid[guid]) or (not guidLegivel and key and vistoIdentidade[key]))
            if not (porObito and (repetido or not IsRealDeath(source))) then
                uniao[#uniao + 1] = source
                -- Seen only when it became a line: a player whose only entry is no death (recap 0)
                -- still comes in from the other metrics, with no deaths.
                if guidLegivel then vistoGuid[guid] = true end
                if key then vistoIdentidade[key] = true end
            end
        end

        for c = 1, #columns do
            local def = Data.GetColumn(columns[c])
            if def and def.attr ~= sortDef.attr then
                local outra = SessionFor(def.attr)
                local lista = outra and outra.combatSources
                for i = 1, (lista and #lista or 0) do
                    local source = lista[i]
                    local guid = source.sourceGUID
                    local legivel = guid ~= nil and not issecretvalue(guid)

                    local novo = false
                    if legivel then
                        if not vistoGuid[guid] then
                            vistoGuid[guid] = true
                            novo = true
                        end
                    else
                        local key = IdentityKey(source)
                        if key and not vistoIdentidade[key] then
                            vistoIdentidade[key] = true
                            novo = true
                        end
                    end

                    if novo then
                        uniao[#uniao + 1] = source
                        rowAttr[source] = def.attr
                    end
                end
            end
        end

        sources = uniao
    end

    -- Ambiguous identities in the SOURCE LIST: if two rows have the same class+spec,
    -- neither of them can be matched by identity.
    local rowIdentityAmbiguous = {}
    do
        local seen = {}
        for i = 1, #sources do
            local key = IdentityKey(sources[i])
            if key then
                if seen[key] then rowIdentityAmbiguous[key] = true end
                seen[key] = true
            end
        end
    end

    -- An index per metric: actor by GUID, actor by identity, and the COUNT by both.
    --
    -- The count exists because of the deaths metric, where each entry is a death and not a
    -- player (see lesson 3 at the top). In the other metrics it is not used.
    local indexes = {}
    local function IndexFor(attr)
        local index = indexes[attr]
        if index == nil then
            index = false
            local other = SessionFor(attr)
            local list = other and other.combatSources
            if list then
                -- ONLY THE DEATHS METRIC filters by `deathRecapID`, and the limitation is
                -- DEFENSIVE, not load-bearing: today the count maps are only read by the
                -- deaths column, so filtering in all of them would come to the same. The test confirms
                -- it -- sabotaging this line fails nothing.
                --
                -- It stays this way anyway because in the other metrics `deathRecapID` is 0 for
                -- everyone: the day a second count metric exists, filtering without
                -- scope would zero its column silently.
                local somenteMortes = Enum and Enum.DamageMeterType
                    and attr == Enum.DamageMeterType.Deaths

                index = { byGuid = {}, byIdentity = {}, countByGuid = {}, countByIdentity = {} }
                local identitySeen = {}
                for i = 1, #list do
                    local candidate = list[i]
                    local conta = not somenteMortes or IsRealDeath(candidate)

                    local guid = candidate.sourceGUID
                    if guid ~= nil and not issecretvalue(guid) then
                        index.byGuid[guid] = index.byGuid[guid] or candidate
                        if conta then
                            index.countByGuid[guid] = (index.countByGuid[guid] or 0) + 1
                        end
                    end

                    local key = IdentityKey(candidate)
                    if key then
                        -- A repeat is only an ambiguity for LOOKING UP an actor. For COUNTING, repeating is
                        -- the data: they are two deaths of the same player.
                        if identitySeen[key] then
                            index.byIdentity[key] = false
                        elseif index.byIdentity[key] == nil then
                            index.byIdentity[key] = candidate
                        end
                        identitySeen[key] = true
                        if conta then
                            index.countByIdentity[key] = (index.countByIdentity[key] or 0) + 1
                        end
                    end
                end
            end
            indexes[attr] = index
        end
        return index or nil
    end

    --- Finds this row's actor inside another metric.
    --- @return table|nil actor, boolean conclusive  (conclusive = "not found" means zero)
    local function MatchIn(attr, guid, guidReadable, identityKey)
        local index = IndexFor(attr)
        if not index then return nil, false end

        if guidReadable then
            return index.byGuid[guid], true
        end

        if identityKey and not rowIdentityAmbiguous[identityKey] then
            local hit = index.byIdentity[identityKey]
            -- `false` = the metric has two rows with this class+spec: ambiguous, not conclusive.
            if hit ~= false then return hit or nil, true end
        end

        return nil, false
    end

    --- How many entries this row has in the metric. It only makes sense in `Deaths`.
    --- @return number|nil count, boolean conclusive
    local function CountIn(attr, guid, guidReadable, identityKey)
        local index = IndexFor(attr)
        if not index then return nil, false end

        if guidReadable then
            return index.countByGuid[guid] or 0, true
        end

        -- For COUNTING, a repeat in the metric is not an ambiguity -- it is the data itself. What
        -- has to be unique is the ROW's identity.
        if identityKey and not rowIdentityAmbiguous[identityKey] then
            return index.countByIdentity[identityKey] or 0, true
        end

        return nil, false
    end

    local total = #sources

    offset = offset or 0
    if offset < 0 then offset = 0 end
    if offset > total - 1 then offset = total - 1 end
    if offset < 0 then offset = 0 end

    local count = total - offset
    if count > maxRows then count = maxRows end

    -- BUILDS ALL THE ACTORS, not only those that fit on screen.
    --
    -- The leader highlight is "the best of each column", and that is a property of the GROUP, not of the
    -- page. Before, the loop stopped at `count` and `MarkColumnLeaders` got only the visible slice:
    -- scrolling the window changed who was marked, because the slice's best changed along. It was
    -- a highlight that said "the best among those you are seeing", which means nothing.
    --
    -- The cost is building values for the whole group instead of for 5 rows. It is cheap: the
    -- session queries and the GUID indexes are already memoised above, so each extra actor
    -- is only table lookups -- not API calls.
    local built = {}
    for position = 1, total do
        local source = sources[ascending and (total - position + 1) or position]
        local values = {}

        -- THE CACHE IS SEEDED IN THE METRIC THE ACTOR CAME FROM, and not always in the sorted one. For whoever
        -- came in through the union, seeding in the sorted one would put his number (healing, interrupts) in the
        -- wrong column -- and the sorted column's value would come out right by accident never.
        local fromAttr = rowAttr[source] or sortDef.attr
        local cache = { [fromAttr] = source }

        local guid = source.sourceGUID
        local guidReadable = guid ~= nil and not issecretvalue(guid)
        local isLocal = source.isLocalPlayer
        isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true
        local identityKey = IdentityKey(source)

        -- `conclusive[attr]`: in this metric, does "I did not find the actor" mean **zero** or does it
        -- mean **I do not know**? The difference is visible: writing `0` where one does not know is lying. It is only conclusive when the row could be identified -- by a
        -- readable GUID, or by a class+spec unique in both lists.
        local conclusive = {}

        for c = 1, #columns do
            local def = Data.GetColumn(columns[c])
            if def then
                if def.field == "count" then
                    -- Deaths: a count of entries, not a sum of `totalAmount`.
                    local n, ok = CountIn(def.attr, guid, guidReadable, identityKey)
                    if not ok and isLocal then
                        n = Data.CountLocalPlayerEntries(SessionFor(def.attr))
                        ok = n ~= nil
                    end
                    values[c] = ok and n or nil
                else
                    local from = cache[def.attr]
                    if from == nil then
                        local hit, ok = MatchIn(def.attr, guid, guidReadable, identityKey)
                        if not ok and isLocal then
                            -- The last card in combat: `isLocalPlayer` is `NeverSecret`.
                            hit = Data.GetLocalPlayerSource(SessionFor(def.attr))
                            ok = hit ~= nil
                        end
                        from = hit or false
                        conclusive[def.attr] = ok
                        cache[def.attr] = from
                    end

                    local value = ValueFromSource(from or nil, def, sessionTotals[def.attr] or nil)
                    -- Absent from a list we can read = the player did not score there. It is zero.
                    if value == nil and from == false and conclusive[def.attr]
                        and def.field ~= "percent" then
                        value = 0
                    end
                    values[c] = value
                end
            end
        end

        built[position] = { source = source, values = values }
    end


    -- (14/10) THE ORDER IS THE CLICKED COLUMN'S whenever its numbers can be read. The API's list
    -- comes in the order of its TOTAL: "DPS" gilded on the header with the rows by damage done
    -- (the log: two players with total and per-second in opposite orders), and Deaths in the
    -- order the deaths happened. In combat the values are secret: then the API's order stays.
    local sortCol
    for c = 1, #columns do if columns[c] == sortKey then sortCol = c end end
    if sortCol then
        local legivel = true
        for i = 1, total do
            local v = built[i].values[sortCol]
            if v ~= nil and (issecretvalue(v) or type(v) ~= "number") then legivel = false; break end
        end
        if legivel then
            local pos = {}
            for i = 1, total do pos[built[i]] = i end
            table.sort(built, function(x, y)
                local a, b = x.values[sortCol] or -1, y.values[sortCol] or -1
                if a ~= b then
                    if ascending then return a < b end
                    return a > b
                end
                return pos[x] < pos[y]
            end)
        end
    end

    -- Marks over the WHOLE list: who leads does not change when scrolling nor when changing the sort.
    Data.MarkColumnLeaders(built, columns)

    -- Only now it cuts the visible window. `best` already came decided from above.
    local rows = {}
    for i = 1, count do
        rows[i] = built[offset + i]
    end

    -- (14/10) THE LARGEST READABLE VALUE OF EACH COLUMN, over the whole list (not the page): the
    -- ruler of a bar that fills with what the API has no `maxAmount` for — deaths (a count; the
    -- game's maxAmount is 0 there), a share, a per-second the list is sorted by.
    rows.readMax = {}
    for c = 1, #columns do
        local max, ok = nil, true
        for i = 1, total do
            local v = built[i].values[c]
            if v ~= nil then
                if issecretvalue(v) or type(v) ~= "number" then ok = false; break end
                if max == nil or v > max then max = v end
            end
        end
        if ok and max then rows.readMax[c] = max end
    end

    return rows, session, total
end

--------------------------------------------------------------------------------
-- The columns of casts
--------------------------------------------------------------------------------
---The value of a cast column for one row. `nil` is "cannot say", and the cell stays empty.
---
---What the breakdown panel shows of the player's OWN casts: the interrupt spells cast (by
---spell, with how many of all of them missed) and the crowd control used (by spell).
---
---(!) THE METER'S INTERRUPT LIST IS WHAT WAS INTERRUPTED, NOT WHAT INTERRUPTED (30/09, read in
---the diary of a real key): under each player it names the enemy's spells ("Raio", "Brisa
---Curativa"), one entry per cut. So the credited list cannot be matched spell by spell with
---the casts, and cannot TEACH which spells are interrupts. What it gives is the TOTAL credited,
---and "missed" is casts minus that total, for the whole family.
---Only the local player has casts: the others' arrive secret (100% in a real key), and for
---them both lists are empty, so the panel shows no section.
---@return table[] interrupts { spellID, amount = casts }
---@return table[] control { spellID, amount = casts }
---@return number|nil missed casts of interrupt spells minus the interrupts credited; nil when not known
function Data.GetCastBreakdown(sessionType, source, guid, creatureId)
    local interrupts, control = {}, {}
    if not ns.Casts or not source then return interrupts, control, nil end

    local isLocal = source.isLocalPlayer
    isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true
    local name = source.name
    local nameReadable = name ~= nil and not issecretvalue(name)
    if not isLocal and not nameReadable then return interrupts, control, nil end

    local which = ns.Casts.Which(sessionType)
    local casts = ns.Casts.For(which, nameReadable and name or nil, isLocal)
    if not casts then return interrupts, control, nil end

    for id, n in pairs(casts.interrupt) do
        interrupts[#interrupts + 1] = { spellID = id, amount = n }
    end
    for id, n in pairs(casts.control) do
        control[#control + 1] = { spellID = id, amount = n }
    end
    local function byAmount(a, b)
        if a.amount == b.amount then return a.spellID < b.spellID end
        return a.amount > b.amount
    end
    table.sort(interrupts, byAmount)
    table.sort(control, byAmount)

    -- The interrupts the game credited to this row, as a total: what the casts are measured
    -- against. Readable out of combat; in combat there is no subtraction to make.
    local missed
    local E = Enum.DamageMeterType
    if #interrupts > 0 and guid ~= nil and not issecretvalue(guid) then
        local ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            Data.SessionValue(sessionType), E.Interrupts, guid, creatureId)
        local spells = ok and type(container) == "table" and container.combatSpells or nil
        if spells then
            local credited = 0
            for i = 1, #spells do
                local n = spells[i].totalAmount
                if n == nil or issecretvalue(n) or type(n) ~= "number" then credited = nil; break end
                credited = credited + n
            end
            if credited then
                missed = casts.interruptTotal - credited
                if missed < 0 then missed = 0 end
            end
        end
    end
    return interrupts, control, missed
end

--- Marks who leads **each** column, not only the sorted one: the healer who heals most is highlighted
--- even being third in damage.
---
--- That needs comparing values, which is **forbidden with secret values**. In combat, therefore,
--- the highlight simply does not show; leaving combat it comes back. Better than getting the leader wrong.
--- The METRICS in which the window shows a ranking, each one with its own list.
---
--- WHY THIS EXISTS. The request: *"qual seria a melhor forma de em uma janela ver uma ordenacao
--- onde eu consiga ver quem esta sendo o melhor em Dano/DPS, Cura/CPS e Interrupts"*. They are **three
--- rankings at once** over the same five people, and a table sorted by one
--- column only answers the first -- in the other two the leader gets lost in the middle.
---
--- ⚑ AND MIDNIGHT'S RESTRICTION DECIDES THE DESIGN. In combat the values are secret: comparing
--- raises an error, so **the addon cannot find out who is the biggest**. The leader highlight per
--- column that existed only worked out of combat, and nobody had noticed because out of
--- combat is where we look when we are tuning.
---
--- What works is asking. `C_DamageMeter.GetCombatSessionFromType` **returns the list already
--- sorted** by the metric asked for -- checked in Blizzard's own meter, which sorts
--- nothing in Lua: it walks `combatSources` in order and uses `index = i` as the position
--- (`DamageMeterSessionWindow.lua:621-641`). One query per metric = one ready ranking,
--- for free, valid in and out of combat.
---
--- So: **the position in the list is the only reliable ranking**, and one section per metric is the way to
--- have three of them. The leader is always the first row of each section.
---
--- THE SECTIONS COME FROM THE COLUMNS THE PLAYER ALREADY CHOSE, grouped by metric (`attr`): ticking
--- "Damage total" and "Damage per second" does not give two sections, it gives one Damage section that shows both
--- numbers. So the settings screen still holds, and comes to mean something better.
---
--- @param sessionType number
--- @param columns string[] the ticked columns, in order
--- @param rowsPerSection number how many rows per section
--- @return table[] sections `{ key, attr, label, columns, rows, session }`
function Data.GetSections(sessionType, columns, rowsPerSection)
    local out, seen = {}, {}

    for c = 1, #columns do
        local def = Data.GetColumn(columns[c])
        if def and not seen[def.attr] then
            seen[def.attr] = { key = def.key, attr = def.attr, columns = {} }
            out[#out + 1] = seen[def.attr]
        end
        if def then
            local grupo = seen[def.attr]
            grupo.columns[#grupo.columns + 1] = def.key

            -- THE COLUMN THAT SORTS THE SECTION is the TOTAL's, not the first ticked. Whoever ticks only
            -- "Damage per second" still wants the section sorted by damage -- and the rate is derived from the
            -- total, so the two orders are the same; but whoever ticks both expects to see the total
            -- first, because it is the number the native meter highlights.
            if def.field == "total" or def.field == "count" then
                grupo.key = grupo.key or def.key
                if def.field == "total" then grupo.key = def.key end
            end
        end
    end

    local secoes = {}
    for i = 1, #out do
        local grupo = out[i]
        local rows, session = Data.GetRows(sessionType, grupo.key, grupo.columns,
            rowsPerSection, false)

        -- A SECTION WITH NOBODY DOES NOT SHOW. Nobody interrupted yet -> the interrupts section
        -- does not exist, instead of existing empty. It is the workspace skill's rule: *empty space
        -- reserved for people who are not there is what most makes a window look broken*.
        if rows and #rows > 0 then
            secoes[#secoes + 1] = {
                key = grupo.key,
                attr = grupo.attr,
                label = Data.GetFamilyLabel(grupo.key),
                columns = grupo.columns,
                rows = rows,
                session = session,
            }
        end
    end

    return secoes
end

--- The VISIBLE columns: the ones chosen by the player, grouped by metric.
---
--- The user's idea: instead of two columns (Damage and DPS, Healing and HPS), merge them into one, with the
--- header "Dano - DPS" and the value "65.1M - 48K".
---
--- He is right, and the gain is twofold. The obvious one: two columns become one, so width is left and the
--- bar gets bigger -- which was the complaint before. The less obvious, and more important: **the total and the
--- rate are the same thing measured two ways**. Separating them into columns forced the eye to cross
--- the row to join "how much" with "how fast"; together, the reading is one.
---
--- Each group returns `keys` in the order the player ticked them, and `key` (the first) is what
--- sorts the group -- clicking the "Dano - DPS" header sorts by damage.
---
--- @return table[] groups `{ key, attr, keys }`
function Data.GroupColumns(columns)
    local grupos, porAttr = {}, {}

    for c = 1, #columns do
        local def = Data.GetColumn(columns[c])
        if def then
            -- By `group`, which is the metric unless the column asks for a group of its own
            -- (the crowd control lives in the interrupts metric and is not an interrupt).
            local grupo = porAttr[def.group]
            if not grupo then
                grupo = { key = def.key, attr = def.attr, keys = {} }
                porAttr[def.group] = grupo
                grupos[#grupos + 1] = grupo
            end
            grupo.keys[#grupo.keys + 1] = def.key

            -- The group's own column is the TOTAL, even when the rate was ticked first: it is
            -- the one with a ruler in combat (`maxAmount`). (14/10) Not "the same list" as the
            -- rate: the log showed two players with total and per-second in opposite orders.
            if def.field == "total" then grupo.key = def.key end
        end
    end

    return grupos
end

--- EACH COLUMN'S RULER: the biggest value of the metric it belongs to.
---
--- WHY THIS EXISTS, and it is what makes the columns design work in combat. The request was to see
--- **who is best at Damage, Healing and Interrupts at the same time**, and in combat the addon cannot
--- find out who is the biggest: the values are secret and comparing raises an error.
---
--- The way out is not needing to find out. If each column is drawn as a BAR scaled by the biggest
--- value OF THAT metric, then the column's leader is its only full bar -- the geometry
--- answers what Lua cannot compute. Three columns, three leaders, at a glance.
---
--- The ruler comes from `session.maxAmount`, which the game gives ready per metric. Neither it nor the value
--- are read here: both go straight to the widget.
---
--- ⚠️ A RATE COLUMN USES THE TOTAL'S RULER, and that is on purpose -- it is what the native meter does.
--- `DamageMeterSessionWindow.lua:638` assigns the session's `maxAmount` to each actor and draws the bar
--- with it **even when it shows the per-second value**. The bar is "how much of this metric was yours"; the
--- number is what you asked to see. There is no rate `maxAmount` in the API to do otherwise.
---
--- @return table by column position: that column's ruler
function Data.GetColumnScales(sessionType, columns)
    local scales, porAttr = {}, {}

    for c = 1, #columns do
        local def = Data.GetColumn(columns[c])
        if def then
            if porAttr[def.attr] == nil then
                local session = Data.GetSession(sessionType, def.attr)
                porAttr[def.attr] = session and session.maxAmount or false
            end
            scales[c] = porAttr[def.attr] or nil
        end
    end

    return scales
end

function Data.MarkColumnLeaders(rows, columns)
    if #rows < 2 then return end

    for c = 1, #columns do
        local bestIndex, bestValue
        local negative = Data.IsNegativeColumn(columns[c])

        for i = 1, negative and 0 or #rows do
            local value = rows[i].values[c]
            if value ~= nil and not issecretvalue(value) and type(value) == "number" then  -- luacheck: ignore
                if bestValue == nil or value > bestValue then
                    bestIndex, bestValue = i, value
                end
            end
        end

        -- Zero is no leadership: nobody "leads" the deaths when nobody died.
        if bestIndex and bestValue and bestValue > 0 then
            local row = rows[bestIndex]
            row.best = row.best or {}
            row.best[c] = true
        end
    end
end

--------------------------------------------------------------------------------
-- Detalhamento por magia
--------------------------------------------------------------------------------
--- An actor's list of spells, adding one or more metrics.
---
--- Healing and absorbs become one section; interrupts and dispels too. When the same spell
--- shows in two metrics, the values add.
--- @param attributes number[] the metrics to aggregate
--- @return table[]|nil spells sorted from biggest to smallest: { spellID, amount, perSecond }
--- @return number|nil total
function Data.GetSpellBreakdown(sessionType, attributes, guid, creatureId, limit)
    if not Data.IsAvailable() or guid == nil or issecretvalue(guid) then
        return nil, nil
    end

    local bySpell, total = {}, 0

    for _, attribute in ipairs(attributes) do
        -- (20/10) `sessionType` may be `{ id = <sessionID> }`: one PAST session of the meter, by its id ("My run"
        -- keeps each fight's spells; GetCombatSessionSourceFromID answered in all 43 readings of RocketLab's probe)
        local ok, container
        if type(sessionType) == "table" then
            if not C_DamageMeter.GetCombatSessionSourceFromID then return nil, nil end
            ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionType.id, attribute, guid, creatureId)
        else
            ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
                Data.SessionValue(sessionType), attribute, guid, creatureId)
        end

        local spells = ok and container and container.combatSpells or nil
        if spells then
            for i = 1, #spells do
                local spell = spells[i]
                local id = spell.spellID
                local amount = spell.totalAmount

                -- With no readable id or with a secret value there is nothing to add nor sort.
                if id ~= nil and not issecretvalue(id)
                    and amount ~= nil and not issecretvalue(amount) then
                    local entry = bySpell[id]
                    if not entry then
                        entry = { spellID = id, amount = 0, perSecond = 0 }
                        bySpell[id] = entry
                    end
                    entry.amount = entry.amount + amount

                    local rate = spell.amountPerSecond
                    if rate ~= nil and not issecretvalue(rate) then
                        entry.perSecond = entry.perSecond + rate
                    end

                    total = total + amount
                end
            end
        end
    end

    local list = {}
    for _, entry in pairs(bySpell) do
        list[#list + 1] = entry
    end
    if #list == 0 then return nil, nil end

    table.sort(list, function(a, b) return a.amount > b.amount end)

    if limit and #list > limit then
        for i = #list, limit + 1, -1 do
            list[i] = nil
        end
    end

    return list, total
end

--------------------------------------------------------------------------------
-- (!) THE GAME'S "HEALING DONE" CARRIES THE SHIELDS (08/10, read in the diary of a real
-- session). The user, on a guardian druid: *"Pelagem Embaraçada curou, mas ela apenas absorve
-- dano"* and, after healing and absorbs were split into two sections, *"ainda me parece tudo
-- errado (...) gerar uns logs para ter certeza"*. The log was there (`healabs`, 15:52:01):
--
--     Ursoc's Fury (372505)   healing 1,347,697   absorbs 1,347,697
--     Matted Fur   (385787)   healing   412,041   absorbs   412,041
--     Brambles     (203953)   healing    47,043   absorbs    47,043
--
-- Three shields, each listed by the game under healing done AND under absorbs, with the same
-- number to the unit. The client says as much in its own names: the storage behind healing is
-- `HealingAndAbsorbs` (DamageMeterConstantsDocumentation.lua). So "healing done", in the game's
-- meter as in every meter before it, is healing PLUS damage absorbed; splitting the two lists
-- left every shield in both.
--
-- What really healed is therefore healing done MINUS absorbs, spell by spell: a spell that only
-- shields comes to nothing and leaves the list; a spell that does both keeps what is left.
-- Only out of combat: in combat both numbers are secret and cannot be subtracted.
---@return table[]|nil spells `{ spellID, amount, perSecond }`, largest first: healing without the shields
---@return number|nil total
function Data.GetPureHealing(sessionType, guid, creatureId, limit)
    local E = Enum.DamageMeterType
    local healing, healingTotal = Data.GetSpellBreakdown(sessionType, { E.HealingDone }, guid, creatureId)
    if not healing then return nil, nil end
    local absorbs, absorbsTotal = Data.GetSpellBreakdown(sessionType, { E.Absorbs }, guid, creatureId)
    local shield = {}
    for _, sp in ipairs(absorbs or {}) do shield[sp.spellID] = sp.amount end
    local list, total, both = {}, 0, 0
    for _, sp in ipairs(healing) do
        local off = shield[sp.spellID] or 0
        if off > 0 then both = both + 1 end
        local rest = sp.amount - off
        -- Under one point is rounding between the two lists, not healing.
        if rest >= 1 then
            list[#list + 1] = { spellID = sp.spellID, amount = rest,
                perSecond = sp.amount > 0 and (sp.perSecond or 0) * rest / sp.amount or 0 }
            total = total + rest
        end
    end
    -- For the diary (development only): the two totals of the game and what is left, so that
    -- the rule above can be checked against any class after a session.
    if ns.Log and ns.Log.Add then
        local now = GetTime and GetTime() or 0
        if now - (Data.lastHealingLog or -60) >= 60 then
            Data.lastHealingLog = now
            ns.Log.Add("healing", { gameHealing = healingTotal, gameAbsorbs = absorbsTotal or 0, pure = total,
                spells = #healing, inBoth = both, left = #list })
        end
    end
    if #list == 0 then return nil, nil end
    table.sort(list, function(a, b) return a.amount > b.amount end)
    if limit then for i = #list, limit + 1, -1 do list[i] = nil end end
    return list, total
end

---The same for a TOTAL (08/10): one player's healing metric with the absorbs metric taken out.
---The user, told that the game's healing done carries the shields, asked to keep the meter's
---window as it is and to show the two apart in the popups and the breakdown, if possible. So the
---meter's own window keeps the game's number (healing with shields), and
---the detail screens show the two apart: this is what they call.
---@param healing table|nil `{ total, perSecond, rank, of, groupTotal }` of healing done
---@param absorbs table|nil the same of absorbs
---@return table|nil healing without the shields; `absorbed` is what was taken out. The place in
---the group is kept only when nobody in the group absorbed anything (it was worked out on the
---game's number, and would be the place by healing PLUS shields).
function Data.PureHealingMetric(healing, absorbs)
    if type(healing) ~= "table" then return healing end
    local off = type(absorbs) == "table" and absorbs.total or 0
    local groupOff = type(absorbs) == "table" and absorbs.groupTotal or 0
    if (off or 0) <= 0 and (groupOff or 0) <= 0 then return healing end
    off = off or 0
    local offRate = type(absorbs) == "table" and absorbs.perSecond or 0
    return {
        total = math.max(0, (healing.total or 0) - off),
        perSecond = math.max(0, (healing.perSecond or 0) - (offRate or 0)),
        of = healing.of, rank = nil,
        groupTotal = healing.groupTotal and math.max(0, healing.groupTotal - (groupOff or 0)) or nil,
        absorbed = off,
    }
end

--------------------------------------------------------------------------------
-- Formatting
--------------------------------------------------------------------------------

--- @return string|nil the ready text, or nil if the value is secret (then use SetText directly)
--- The compact format: `2.9M`, `112K`, `847`.
---
--- `AbbreviateNumbers` depends on the client's language and returns long texts in pt-BR
--- ("365.594"), which overflowed the column's width and turned into an ellipsis. The format that fits is
--- `2.9M` and `112K` -- three to four characters, always.
--- **A hard ceiling of 5 characters.** The cell is 50px and a bigger text is not cut: it becomes
--- an ellipsis, which is what the user saw in a 28-minute run. Two bands exist only
--- because of that:
---
---  * **billion** -- without it, 1.2 billion damage gave `"1234.6M"`, seven characters. A long
---    raid gets there.
---  * **hundred** -- `%.1f` of 339 gives `"339.1M"`, six. Above 100 the decimal place tells
---    nothing (0.03% of the value) and costs the whole column.
function Data.FormatAmount(value)
    if value == nil or issecretvalue(value) then
        return nil
    end

    -- The thresholds are the value ALREADY ROUNDED, not the round one. 99,999,999 with `%.1f` becomes
    -- "100.0M" -- six characters -- because the rounding pushes the mantissa to three
    -- digits before the round threshold (100,000,000) is reached. Cutting at 99.95M puts
    -- that case in the band above, where it becomes "100M".
    local absolute = value < 0 and -value or value
    if absolute >= 999500000 then
        return format("%.1fB", value / 1000000000)      -- 1.2B
    elseif absolute >= 99950000 then
        return format("%.0fM", value / 1000000)         -- 339M
    elseif absolute >= 999500 then                      -- (14/10) 999.600 was "1000K"
        return format("%.1fM", value / 1000000)         -- 33.9M
    elseif absolute >= 9950 then                        -- (14/10) 9.994 was "10.0K"
        return format("%.0fK", value / 1000)            -- 786K
    elseif absolute >= 1000 then
        return format("%.1fK", value / 1000)            -- 9.6K
    end
    return format("%d", value + 0.5)                    -- 847
end

--- How many characters a cell takes before turning into an ellipsis.
---
--- It holds for the ready text, whether it comes from `FormatAmount` (which respects this by construction) or
--- from the client, on the secret values' path -- where it cannot be abbreviated by hand and the only
--- defence is **refusing** a format that comes back too long.
Data.MAX_CELL_CHARS = 6

--------------------------------------------------------------------------------
-- Formatting secret values
--------------------------------------------------------------------------------
-- Abbreviating (603K) needs dividing, and arithmetic with a secret value is forbidden in addon code.
-- The wiki says `string.format` is allowed, and `securecallfunction` runs a Blizzard function
-- outside our tainted context -- which **may** free the arithmetic in there.
--
-- None of this is a guess: the strategies are tested in the game itself, the first time a
-- secret value shows up, and the one that works is recorded in the log. If none works, the
-- number shows raw, as today.
local STRATEGIES = {
    {
        name = "securecallfunction(AbbreviateNumbers)",
        run = function(value)
            if not securecallfunction or not AbbreviateNumbers then return nil end
            return securecallfunction(AbbreviateNumbers, value)
        end,
    },
    {
        name = "securecallfunction(BreakUpLargeNumbers)",
        run = function(value)
            if not securecallfunction or not BreakUpLargeNumbers then return nil end
            return securecallfunction(BreakUpLargeNumbers, value)
        end,
    },
    {
        name = "format('%s')",
        run = function(value)
            return format("%s", value)
        end,
    },
}

local chosenStrategy      -- index of the strategy that worked; false = none

--- Does this strategy's output fit in the cell?
---
--- `AbbreviateNumbers` **only abbreviates above a threshold**; below it it returns the number in
--- full with a thousands separator, and in pt-BR that is `"365.594"` -- seven characters in a
--- cell that takes six. The warning was already written in `FormatAmount`'s comment, but the
--- probe did not obey it: `AbbreviateNumbers` is the **first** in the list, so it only had to
--- work to be chosen, and from then on every big cell turned into an ellipsis.
---
--- A result still secret passes: it cannot be measured, and the widget is what will draw.
local function FitsCell(text)
    if text == nil then return false end
    if issecretvalue(text) then return true end
    if type(text) ~= "string" then return true end
    return #text <= Data.MAX_CELL_CHARS
end

local function ProbeStrategies(value)
    for index, strategy in ipairs(STRATEGIES) do
        local ok, result = pcall(strategy.run, value)
        if ok and result ~= nil and FitsCell(result) then
            chosenStrategy = index
            if ns.Log then
                ns.Log.Add("formatador", {
                    escolhido = strategy.name,
                    resultadoSecret = issecretvalue(result) and true or false,
                })
            end
            return result
        end
    end

    chosenStrategy = false
    if ns.Log then
        ns.Log.Add("formatador", { escolhido = "nenhuma; valor cru" })
    end
    return nil
end

--- The text of a value that may be secret. Returns nil when there is no way to format -- then the
--- caller passes the raw value to the FontString, which the engine renders.
--- The chosen strategy counts as a **preference**, not a final verdict.
---
--- The reason: whether it fits depends on the VALUE, not only on the client. `AbbreviateNumbers` returns
--- `"2.9M"` for 2.9 million and `"365.594"` for 365 thousand -- below the abbreviation threshold it
--- writes the number in full. A single probe, made with the first value that showed up,
--- decides wrong for half the others: that is how the damage column turned into an ellipsis
--- while the HPS one, with smaller numbers, stayed right.
---
--- That is why the fit is checked **at each value**, and the other strategies stay as a fallback.
function Data.FormatSecretAmount(value)
    if chosenStrategy == nil then
        return ProbeStrategies(value)
    end
    if chosenStrategy == false then
        return nil
    end

    local ok, result = pcall(STRATEGIES[chosenStrategy].run, value)
    if not ok then
        -- The restriction may change along the way: it redoes the probe once.
        chosenStrategy = nil
        return nil
    end
    if FitsCell(result) then return result end

    -- The preferred one does not serve for THIS number. It tries the others, without changing the preference --
    -- it is still the one that serves for most.
    for index, strategy in ipairs(STRATEGIES) do
        if index ~= chosenStrategy then
            local fine, alternative = pcall(strategy.run, value)
            if fine and FitsCell(alternative) then return alternative end
        end
    end
    return nil
end

function Data.GetFormatterName()
    if chosenStrategy == nil then return "not probed yet" end
    if chosenStrategy == false then return "none (raw value)" end
    return STRATEGIES[chosenStrategy].name
end

function Data.FormatPercent(value)
    if value == nil or issecretvalue(value) then
        return nil
    end
    return format("%.0f%%", value)
end
