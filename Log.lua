-- RocketMeter | Log.lua
-- Diário de diagnóstico gravado em SavedVariables.
--
-- Addon não escreve arquivo arbitrário, mas SavedVariables vira um `.lua` legível em
--   WTF\Account\<conta>\SavedVariables\RocketMeter.lua
-- que pode ser lido de fora do jogo. É o jeito de mandar o que aconteceu para análise.
--
-- REGRA DE OURO: nunca guardar um secret value aqui. Gravar valor opaco em SavedVariables
-- é caminho certo para erro. O log guarda **fatos sobre** os dados (quantos atores vieram,
-- se o campo estava secret, o valor já formatado quando legível), nunca o dado cru.
local ADDON, ns = ...

local Log = {}
ns.Log = Log

local MAX_ENTRIES = 300

local function Store()
    RocketMeterLogDB = RocketMeterLogDB or { entries = {} }
    RocketMeterLogDB.entries = RocketMeterLogDB.entries or {}
    return RocketMeterLogDB
end

---Descreve um valor sem nunca guardá-lo cru.
local function Describe(value)
    if value == nil then return "nil" end
    if issecretvalue(value) then return "SECRET" end
    if type(value) == "number" then return tostring(value) end
    if type(value) == "string" then return value end
    return type(value)
end

function Log.Add(event, data)
    local store = Store()
    local entries = store.entries

    entries[#entries + 1] = {
        time = date("%H:%M:%S"),
        event = event,
        combat = InCombatLockdown() and true or false,
        data = data,
    }

    -- Anel: mantém só as últimas entradas, para o arquivo não crescer sem limite.
    while #entries > MAX_ENTRIES do
        tremove(entries, 1)
    end
end

---Fotografa o que a API está devolvendo neste instante.
function Log.Snapshot(reason)
    local data = {
        reason = reason,
        sessionType = ns.db and ns.db.sessionType,
        sortBy = ns.db and ns.db.sortBy,
        available = ns.Data.IsAvailable() and true or false,
    }

    local def = ns.db and ns.Data.GetColumn(ns.db.sortBy)
    if not def then
        data.problem = "coluna de ordenacao invalida"
        Log.Add("snapshot", data)
        return
    end

    -- Os dois caminhos, separados: é a pergunta que precisa de resposta.
    local byType = C_DamageMeter.GetCombatSessionFromType(ns.db.sessionType, def.attr)
    data.byTypeCount = byType and byType.combatSources and #byType.combatSources or 0
    data.byTypeDuration = Describe(byType and byType.durationSeconds)
    data.byTypeMax = Describe(byType and byType.maxAmount)

    if C_DamageMeter.GetAvailableCombatSessions then
        local list = C_DamageMeter.GetAvailableCombatSessions()
        data.sessionCount = list and #list or 0
        local newest = list and list[#list]
        local id = type(newest) == "table" and (newest.sessionID or newest.sessionId or newest.id) or newest
        data.newestId = Describe(id)
        if id and C_DamageMeter.GetCombatSessionFromID then
            local byId = C_DamageMeter.GetCombatSessionFromID(id, def.attr)
            data.byIdCount = byId and byId.combatSources and #byId.combatSources or 0
        end
    end

    -- O primeiro ator, campo a campo: diz o que é legível e o que é secret em combate.
    local session = ns.Data.GetSession(ns.db.sessionType, def.attr)
    local first = session and session.combatSources and session.combatSources[1]
    if first then
        data.first = {
            name = Describe(first.name),
            guid = Describe(first.sourceGUID),
            total = Describe(first.totalAmount),
            perSecond = Describe(first.amountPerSecond),
            class = Describe(first.classFilename),
            specIcon = Describe(first.specIconID),
            isLocalPlayer = Describe(first.isLocalPlayer),
        }
    end

    data.formatter = ns.Data.GetFormatterName and ns.Data.GetFormatterName() or "?"

    local lastError = ns.Window and ns.Window.GetLastError and ns.Window.GetLastError()
    if lastError then
        data.drawError = tostring(lastError)
    end

    Log.Add("snapshot", data)
end

function Log.Clear()
    RocketMeterLogDB = { entries = {} }
end

function Log.Count()
    return #Store().entries
end

---Fotografa em pontos-chave do combate, sem depender de o usuário lembrar de rodar comando.
function Log.OnCombatStart()
    Log.Snapshot("inicio do combate")
    -- Três segundos depois: aí já houve dano, e é onde a janela aparecia vazia.
    C_Timer.After(3, function() Log.Snapshot("3s de combate") end)
end

function Log.OnCombatEnd()
    Log.Snapshot("fim do combate")
end

function Log.Init()
    local store = Store()
    store.version = ns.version
    store.locale = GetLocale()
    store.started = date("%Y-%m-%d %H:%M:%S")
end
