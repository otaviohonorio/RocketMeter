-- RocketMeter | Data.lua
-- Camada única sobre C_DamageMeter. Nenhum outro arquivo fala com a API do jogo.
--
-- Regra do Midnight: durante o combate os campos da sessão (inclusive `name`) são
-- SECRET VALUES. Não dá para comparar, somar ou formatar — só repassar a widget.
-- Fora de combate os mesmos campos voltam a ser números/strings legíveis.
local ADDON, ns = ...
local L = ns.L

local Data = {}
ns.Data = Data

-- Cada métrica é uma coluna independente: total e por segundo são colunas separadas,
-- para você ligar só o que quiser ver.
function Data.GetAttributes()
    local E = Enum.DamageMeterType
    if not E then return {} end
    return {
        { id = E.DamageDone,           short = L["Dmg"],     label = L["Total damage"] },
        { id = E.Dps,                  short = L["DPS"],     label = L["Damage per second"] },
        { id = E.HealingDone,          short = L["Heal"],    label = L["Total healing"] },
        { id = E.Hps,                  short = L["HPS"],     label = L["Healing per second"] },
        { id = E.Absorbs,              short = L["Absorb"],  label = L["Absorbs"] },
        { id = E.DamageTaken,          short = L["Taken"],   label = L["Damage taken"] },
        { id = E.AvoidableDamageTaken, short = L["Avoid"],   label = L["Avoidable damage"] },
        { id = E.Interrupts,           short = L["Interr"],  label = L["Interrupts"] },
        { id = E.Dispels,              short = L["Dispel"],  label = L["Dispels"] },
        { id = E.Deaths,               short = L["Deaths"],  label = L["Player deaths"] },
        { id = E.EnemyDamageTaken,     short = L["Enemies"], label = L["Damage on enemies"] },
    }
end

local function FindAttribute(attributeId)
    for _, attr in ipairs(Data.GetAttributes()) do
        if attr.id == attributeId then return attr end
    end
    return nil
end

function Data.GetAttributeLabel(attributeId)
    local attr = FindAttribute(attributeId)
    return attr and attr.label or "?"
end

function Data.GetShortLabel(attributeId)
    local attr = FindAttribute(attributeId)
    return attr and attr.short or "?"
end

---Métricas que já são "por segundo": mostradas com o sufixo /s quando legíveis.
function Data.IsRateColumn(attributeId)
    local E = Enum.DamageMeterType
    if not E then return false end
    return attributeId == E.Dps or attributeId == E.Hps
end

-- Conjuntos prontos, pensados no que se olha de verdade em cada conteúdo.
function Data.GetPresets()
    local E = Enum.DamageMeterType
    if not E then return {} end
    return {
        mplus = {
            label = L["Mythic+"],
            columns = { E.DamageDone, E.Dps, E.HealingDone, E.Hps, E.Interrupts,
                        E.AvoidableDamageTaken, E.Deaths },
        },
        raid = {
            label = L["Raid"],
            columns = { E.DamageDone, E.Dps, E.HealingDone, E.Hps, E.Absorbs,
                        E.AvoidableDamageTaken, E.Deaths },
        },
        dano = {
            label = L["Damage only"],
            columns = { E.DamageDone, E.Dps },
        },
    }
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------
function Data.IsAvailable()
    return C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable and C_DamageMeter.IsDamageMeterAvailable()
end

---@return table|nil session campos: combatSources, totalAmount, maxAmount, durationSeconds
function Data.GetSession(sessionType, attributeId)
    if not Data.IsAvailable() then return nil end
    return C_DamageMeter.GetCombatSessionFromType(sessionType, attributeId)
end

---Detalhe de um ator dentro de um atributo: o total daquele ator naquela métrica.
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

---Monta as linhas da janela: uma por ator, com um valor por coluna.
---
---A ordem vem da API (consulta do atributo de ordenação) porque ordenar no Lua exigiria
---comparar valores — proibido em combate. As demais colunas são buscadas ator a ator,
---passando o GUID de volta para a API.
---@return table[]|nil rows cada uma: { source = <combat_source>, values = { [coluna] = valor } }
---@return table|nil session
function Data.GetRows(sessionType, sortAttr, columns, maxRows)
    local session = Data.GetSession(sessionType, sortAttr)
    local sources = session and session.combatSources
    if not sources then return nil, nil end

    local rows = {}
    local count = #sources
    if count > maxRows then count = maxRows end

    for i = 1, count do
        local source = sources[i]
        local values = {}

        for c = 1, #columns do
            if columns[c] == sortAttr then
                values[c] = source.totalAmount
            else
                local other = Data.GetSource(sessionType, columns[c], source.sourceGUID, source.sourceCreatureID)
                values[c] = other and other.totalAmount or nil
            end
        end

        rows[i] = { source = source, values = values }
    end

    return rows, session
end

--------------------------------------------------------------------------------
-- Formatação
--------------------------------------------------------------------------------
---True quando a sessão está com dados protegidos (combate em andamento).
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

function Data.FormatPercent(value, total)
    if value == nil or total == nil then return nil end
    if issecretvalue(value) or issecretvalue(total) then return nil end
    if total <= 0 then return nil end
    return format("%.1f%%", value / total * 100)
end
