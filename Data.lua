-- RocketMeter | Data.lua
-- Camada única sobre C_DamageMeter. Nenhum outro arquivo fala com a API do jogo.
--
-- DUAS LIÇÕES QUE CUSTARAM CARO:
--
-- 1) Uma coluna é **(métrica, campo)**, não só uma métrica. O valor por segundo vem no campo
--    `amountPerSecond` do MESMO objeto que traz o total — é assim que o Details! faz. Os
--    atributos `Enum.DamageMeterType.Dps` e `.Hps` devolvem os mesmos totais do dano/cura, e
--    usá-los como "coluna de DPS" faz a tela repetir o total (era o bug até a 0.8.0).
--
-- 2) Em combate os campos são SECRET VALUES: não dá para comparar, somar ou formatar — só
--    repassar a widget. Fora de combate voltam a ser números legíveis.
local ADDON, ns = ...
local L = ns.L

local Data = {}
ns.Data = Data

--------------------------------------------------------------------------------
-- Catálogo de colunas
--------------------------------------------------------------------------------
local columnList, columnByKey

local function BuildColumns()
    local E = Enum.DamageMeterType
    if not E then return {}, {} end

    local list = {
        { key = "damage",     attr = E.DamageDone,           field = "total",     short = L["Dmg"],    label = L["Total damage"] },
        { key = "dps",        attr = E.DamageDone,           field = "perSecond", short = L["DPS"],    label = L["Damage per second"] },
        { key = "damagepct",  attr = E.DamageDone,           field = "percent",   short = L["Dmg%"],   label = L["Share of the group damage"] },
        { key = "healing",    attr = E.HealingDone,          field = "total",     short = L["Heal"],   label = L["Total healing"] },
        { key = "hps",        attr = E.HealingDone,          field = "perSecond", short = L["HPS"],    label = L["Healing per second"] },
        { key = "healingpct", attr = E.HealingDone,          field = "percent",   short = L["Heal%"],  label = L["Share of the group healing"] },
        { key = "absorb",     attr = E.Absorbs,              field = "total",     short = L["Absorb"], label = L["Absorbs"] },
        { key = "taken",      attr = E.DamageTaken,          field = "total",     short = L["Taken"],  label = L["Damage taken"] },
        { key = "takenps",    attr = E.DamageTaken,          field = "perSecond", short = L["TPS"],    label = L["Damage taken per second"] },
        { key = "avoidable",  attr = E.AvoidableDamageTaken, field = "total",     short = L["Avoid"],  label = L["Avoidable damage"] },
        { key = "interrupts", attr = E.Interrupts,           field = "total",     short = L["Interr"], label = L["Interrupts"] },
        { key = "dispels",    attr = E.Dispels,              field = "total",     short = L["Dispel"], label = L["Dispels"] },
        { key = "deaths",     attr = E.Deaths,               field = "total",     short = L["Deaths"], label = L["Player deaths"] },
        { key = "enemies",    attr = E.EnemyDamageTaken,     field = "total",     short = L["Enemies"],label = L["Damage on enemies"] },
    }

    local byKey = {}
    for i, def in ipairs(list) do
        def.order = i
        byKey[def.key] = def
    end
    return list, byKey
end

local function EnsureColumns()
    if not columnList then
        columnList, columnByKey = BuildColumns()
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

function Data.IsRateColumn(key)
    local def = Data.GetColumn(key)
    return def ~= nil and def.field == "perSecond"
end

---Métricas em que liderar é ruim: quem mais tomou dano, quem mais morreu.
---O realce existe do mesmo jeito, mas em vermelho — a informação é útil mesmo sendo má notícia.
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

    local out, changed = {}, false
    for _, entry in ipairs(saved) do
        if type(entry) == "number" then
            changed = true
            local key = fromEnum[entry]
            if key then out[#out + 1] = key end
        elseif Data.GetColumn(entry) then
            out[#out + 1] = entry
        else
            changed = true
        end
    end

    if #out == 0 then return nil end
    return out, changed
end

--------------------------------------------------------------------------------
-- Conjuntos prontos
--------------------------------------------------------------------------------
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
function Data.IsAvailable()
    return C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable and C_DamageMeter.IsDamageMeterAvailable()
end

function Data.GetSession(sessionType, attributeId)
    if not Data.IsAvailable() then return nil end
    return C_DamageMeter.GetCombatSessionFromType(sessionType, attributeId)
end

---O `guid` pode ser secret em combate — a API aceita de volta o valor opaco que ela mesma
---produziu, e é isso que torna possível cruzar métricas.
function Data.GetSource(sessionType, attributeId, guid, creatureId)
    if not Data.IsAvailable() or guid == nil then return nil end
    return C_DamageMeter.GetCombatSessionSourceFromType(sessionType, attributeId, guid, creatureId)
end

function Data.GetDuration(sessionType)
    if not Data.IsAvailable() then return 0 end
    return C_DamageMeter.GetSessionDurationSeconds(sessionType) or 0
end

function Data.ResetAll()
    if Data.IsAvailable() then
        C_DamageMeter.ResetAllCombatSessions()
    end
end

---Zerar apaga o combate atual E o geral — nao da para desfazer, entao pergunta antes.
---`skipConfirm` existe para o comando de chat de quem sabe o que esta fazendo.
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
-- Montagem das linhas
--------------------------------------------------------------------------------
local function ValueFromSource(source, def, sessionTotal)
    if not source then return nil end

    if def.field == "total" then
        return source.totalAmount
    elseif def.field == "perSecond" then
        return source.amountPerSecond
    elseif def.field == "percent" then
        local value, total = source.totalAmount, sessionTotal
        -- Percentual exige aritmética: só existe quando os dois valores são legíveis.
        if value == nil or total == nil then return nil end
        if issecretvalue(value) or issecretvalue(total) or total <= 0 then return nil end
        return value / total * 100
    end
    return nil
end

---Monta as linhas: uma por ator, com um valor por coluna.
---
---A ordem vem da API (consulta da métrica de ordenação) porque ordenar no Lua exigiria comparar
---valores — proibido em combate. `ascending` percorre a lista ao contrário, o que não compara nada.
---@param columns string[] chaves de coluna
---@return table[]|nil rows { source = <combat_source>, values = { [coluna] = número } }
---@return table|nil session
function Data.GetRows(sessionType, sortKey, columns, maxRows, ascending)
    local sortDef = Data.GetColumn(sortKey)
    if not sortDef then return nil, nil end

    local session = Data.GetSession(sessionType, sortDef.attr)
    local sources = session and session.combatSources
    if not sources then return nil, nil end

    -- Totais por métrica: uma consulta por coluna (não por linha), para os percentuais.
    local sessionTotals, needTotals = {}, false
    for c = 1, #columns do
        local def = Data.GetColumn(columns[c])
        if def and def.field == "percent" and sessionTotals[def.attr] == nil then
            needTotals = true
            local other = def.attr == sortDef.attr and session or Data.GetSession(sessionType, def.attr)
            sessionTotals[def.attr] = other and other.totalAmount or false
        end
    end
    if not needTotals then sessionTotals = nil end

    local rows = {}
    local count = #sources
    if count > maxRows then count = maxRows end
    local total = #sources

    for i = 1, count do
        local source = sources[ascending and (total - i + 1) or i]
        local values = {}
        local cache = { [sortDef.attr] = source }

        for c = 1, #columns do
            local def = Data.GetColumn(columns[c])
            if def then
                local from = cache[def.attr]
                if from == nil then
                    from = Data.GetSource(sessionType, def.attr, source.sourceGUID, source.sourceCreatureID)
                        or false
                    cache[def.attr] = from
                end
                values[c] = ValueFromSource(from or nil, def,
                    sessionTotals and sessionTotals[def.attr] or nil)
            end
        end

        rows[i] = { source = source, values = values }
    end

    Data.MarkColumnLeaders(rows, columns)

    return rows, session
end

---Marca quem lidera **cada** coluna, não só a ordenada: o healer que cura mais fica realçado
---mesmo estando em terceiro no dano.
---
---Isso exige comparar valores, o que é **proibido com secret values**. Em combate, portanto,
---o realce simplesmente não aparece; ao sair do combate ele volta. Preferível a errar o líder.
function Data.MarkColumnLeaders(rows, columns)
    if #rows < 2 then return end

    for c = 1, #columns do
        local bestIndex, bestValue

        for i = 1, #rows do
            local value = rows[i].values[c]
            if value ~= nil and not issecretvalue(value) and type(value) == "number" then
                if bestValue == nil or value > bestValue then
                    bestIndex, bestValue = i, value
                end
            end
        end

        -- Zero não é liderança: ninguém "lidera" as mortes quando ninguém morreu.
        if bestIndex and bestValue and bestValue > 0 then
            local row = rows[bestIndex]
            row.best = row.best or {}
            row.best[c] = true
        end
    end
end

--------------------------------------------------------------------------------
-- Formatação
--------------------------------------------------------------------------------
function Data.IsSessionSecret(session)
    if not session then return false end
    local first = session.combatSources and session.combatSources[1]
    return first ~= nil and issecretvalue(first.name)
end

---@return string|nil texto pronto, ou nil se o valor for secret (aí use SetText direto)
function Data.FormatAmount(value)
    if value == nil or issecretvalue(value) then
        return nil
    end
    return AbbreviateNumbers(value)
end

function Data.FormatPercent(value)
    if value == nil or issecretvalue(value) then
        return nil
    end
    return format("%.0f%%", value)
end
