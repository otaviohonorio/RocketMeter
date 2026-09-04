-- RocketMeter | Data.lua
-- Camada única sobre C_DamageMeter. Nenhum outro arquivo fala com a API do jogo.
--
-- Regra do Midnight: durante o combate os campos da sessão (inclusive `name`) são
-- SECRET VALUES. Não dá para comparar, somar ou formatar — só repassar a widget.
-- Fora de combate os mesmos campos voltam a ser números/strings legíveis.
local ADDON, ns = ...

local Data = {}
ns.Data = Data

-- Atributos que o medidor nativo expõe, na ordem em que aparecem na UI.
function Data.GetAttributes()
    local E = Enum.DamageMeterType
    if not E then return {} end
    return {
        { id = E.Dps,                  label = _G.DAMAGE_METER_TYPE_DPS                   or "DPS" },
        { id = E.DamageDone,           label = _G.DAMAGE_METER_TYPE_DAMAGE_DONE           or "Dano causado" },
        { id = E.Hps,                  label = _G.DAMAGE_METER_TYPE_HPS                   or "HPS" },
        { id = E.HealingDone,          label = _G.DAMAGE_METER_TYPE_HEALING_DONE          or "Cura" },
        { id = E.Absorbs,              label = _G.DAMAGE_METER_TYPE_ABSORBS               or "Absorções" },
        { id = E.DamageTaken,          label = _G.DAMAGE_METER_TYPE_DAMAGE_TAKEN          or "Dano recebido" },
        { id = E.AvoidableDamageTaken, label = _G.DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN or "Dano evitável" },
        { id = E.Interrupts,           label = _G.DAMAGE_METER_TYPE_INTERRUPTS            or "Interrupções" },
        { id = E.Dispels,              label = _G.DAMAGE_METER_TYPE_DISPELS               or "Dissipações" },
        { id = E.Deaths,               label = _G.DAMAGE_METER_TYPE_DEATHS                or "Mortes" },
        { id = E.EnemyDamageTaken,     label = _G.DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN    or "Dano nos inimigos" },
    }
end

---Colunas "duplas" mostram total e valor por segundo na mesma célula — é o caso de dano e
---cura, em que os dois números importam. `amountPerSecond` vem no mesmo objeto que o total.
function Data.IsDualColumn(attributeId)
    local E = Enum.DamageMeterType
    if not E then return false end
    return attributeId == E.DamageDone
        or attributeId == E.HealingDone
        or attributeId == E.DamageTaken
end

-- Rótulos curtos, para caber no cabeçalho das colunas.
function Data.GetShortLabel(attributeId)
    local E = Enum.DamageMeterType
    if not E then return "?" end
    local short = {
        [E.Dps] = "DPS",
        [E.DamageDone] = "Dano",
        [E.Hps] = "HPS",
        [E.HealingDone] = "Cura",
        [E.Absorbs] = "Absor",
        [E.DamageTaken] = "Recebi",
        [E.AvoidableDamageTaken] = "Evitáv",
        [E.Interrupts] = "Interr",
        [E.Dispels] = "Dissip",
        [E.Deaths] = "Mortes",
        [E.EnemyDamageTaken] = "Inimig",
    }
    return short[attributeId] or "?"
end

-- Conjuntos prontos, pensados no que se olha de verdade em cada conteúdo.
function Data.GetPresets()
    local E = Enum.DamageMeterType
    if not E then return {} end
    return {
        -- Dano e cura entram como colunas duplas: total em cima, por segundo embaixo.
        mplus = {
            label = "Mítico+",
            columns = { E.DamageDone, E.HealingDone, E.Interrupts, E.AvoidableDamageTaken, E.Deaths },
        },
        raid = {
            label = "Raide",
            columns = { E.DamageDone, E.HealingDone, E.Absorbs, E.AvoidableDamageTaken, E.Deaths },
        },
        dano = {
            label = "Só dano",
            columns = { E.DamageDone },
        },
    }
end

function Data.GetAttributeLabel(attributeId)
    for _, attr in ipairs(Data.GetAttributes()) do
        if attr.id == attributeId then
            return attr.label
        end
    end
    return "?"
end

function Data.IsAvailable()
    return C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable and C_DamageMeter.IsDamageMeterAvailable()
end

---Sessão atual para um tipo de sessão e um atributo.
---@return table|nil session campos: combatSources, totalAmount, maxAmount, durationSeconds
function Data.GetSession(sessionType, attributeId)
    if not Data.IsAvailable() then return nil end
    return C_DamageMeter.GetCombatSessionFromType(sessionType, attributeId)
end

---Detalhe de um ator dentro de um atributo: totalAmount daquele ator naquela métrica,
---mais a lista de magias. O `guid` pode ser secret em combate — a API aceita de volta o
---valor opaco que ela mesma produziu, e é isso que torna possível cruzar métricas.
function Data.GetSource(sessionType, attributeId, guid, creatureId)
    if not Data.IsAvailable() or guid == nil then return nil end
    return C_DamageMeter.GetCombatSessionSourceFromType(sessionType, attributeId, guid, creatureId)
end

---Monta as linhas da janela: uma por ator, com um valor por coluna.
---
---A ordem vem da API (consulta do atributo de ordenação) porque ordenar no Lua exigiria
---comparar valores — proibido em combate. As demais colunas são buscadas ator a ator,
---passando o GUID de volta para a API.
---@param sessionType number 0 = combate atual, 1 = geral
---@param sortAttr number atributo que define a ordem das linhas
---@param columns number[] atributos a exibir, na ordem das colunas
---@param maxRows number
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
                values[c] = { total = source.totalAmount, perSecond = source.amountPerSecond }
            else
                local other = Data.GetSource(sessionType, columns[c], source.sourceGUID, source.sourceCreatureID)
                if other then
                    values[c] = { total = other.totalAmount, perSecond = other.amountPerSecond }
                end
            end
        end

        rows[i] = { source = source, values = values }
    end

    return rows, session
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

---True quando a sessão está com dados protegidos (combate em andamento).
---Serve para decidir entre "mostrar número formatado" e "só repassar ao widget".
function Data.IsSessionSecret(session)
    if not session then return false end
    local first = session.combatSources and session.combatSources[1]
    return first ~= nil and issecretvalue(first.name)
end

---Formata um valor que pode ser secret.
---@return string|nil texto pronto, ou nil se o valor for secret (aí use SetText direto)
function Data.FormatAmount(value)
    if value == nil or issecretvalue(value) then
        return nil
    end
    return AbbreviateNumbers(value)
end

---Percentual só existe quando os dois valores são legíveis.
function Data.FormatPercent(value, total)
    if value == nil or total == nil then return nil end
    if issecretvalue(value) or issecretvalue(total) then return nil end
    if total <= 0 then return nil end
    return format("%.1f%%", value / total * 100)
end
