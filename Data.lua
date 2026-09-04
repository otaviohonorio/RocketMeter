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

---Detalhe de um ator (lista de magias) — usado no drill-down.
function Data.GetSource(sessionType, attributeId, guid)
    if not Data.IsAvailable() then return nil end
    return C_DamageMeter.GetCombatSessionSourceFromType(sessionType, attributeId, guid)
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
