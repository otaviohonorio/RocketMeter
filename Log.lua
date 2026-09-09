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

    -- VARREDURA: qual tipo de sessão tem o grupo? Percorre todos os valores possíveis e
    -- anota quantos atores e quem é o primeiro. É o que responde por que a Valira sumiu.
    --
    -- ⚑ ELA PERCORRE O ENUM, E NÃO `0, 3`. O laço fixo era um erro de Lua por combate: este
    -- cliente tem TRÊS valores (`Current=1 Overall=0 Expired=2`), o `3` não existe, e
    -- `GetCombatSessionFromType` levanta em argumento inválido em vez de devolver `nil`. Como o
    -- diagnóstico roda em todo `PLAYER_REGEN_DISABLED`, dava uma linha vermelha por pull — 1628
    -- delas no BugGrabber até 09/09, sempre a mesma. Instrumento que quebra o addon que ele
    -- deveria explicar é pior que instrumento nenhum.
    --
    -- E a chave passa a ser o NOME do valor, não "tipo0": o número sozinho não diz nada, e a
    -- ordem deles muda de cliente para cliente (aqui `Current` é 1, não 0).
    data.sessionEnum = ns.Data.DescribeSessionEnum()
    data.sweep = {}

    local candidatos = {}
    for nome, valor in pairs(Enum.DamageMeterSessionType or {}) do
        if type(valor) == "number" then
            candidatos[#candidatos + 1] = { nome = nome, valor = valor }
        end
    end
    table.sort(candidatos, function(a, b) return a.valor < b.valor end)

    for _, candidato in ipairs(candidatos) do
        local candidate = candidato.valor
        -- `pcall` porque a API LEVANTA em valor que ela não aceita, e um cliente futuro pode
        -- acrescentar um valor de enum que ela ainda não atenda.
        local okProbe, probe = pcall(C_DamageMeter.GetCombatSessionFromType, candidate, def.attr)
        if not okProbe then probe = nil end
        local list = probe and probe.combatSources
        local entry = {
            atores = list and #list or 0,
            duracao = Describe(probe and probe.durationSeconds),
            total = Describe(probe and probe.totalAmount),
        }
        if list then
            local nomes = {}
            for i = 1, math.min(#list, 5) do
                nomes[i] = Describe(list[i].name) .. "=" .. Describe(list[i].totalAmount)
            end
            entry.quem = table.concat(nomes, " | ")
        end
        entry.erro = (not okProbe) and "a API recusou este valor" or nil
        data.sweep[candidato.nome .. "(" .. candidate .. ")"] = entry
    end

    -- Os dois caminhos, separados: é a pergunta que precisa de resposta.
    local byType = C_DamageMeter.GetCombatSessionFromType(ns.Data.SessionValue(ns.db.sessionType), def.attr)
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

    -- Estado da janela: ordenação e quantidade de linhas explicam muita coisa.
    data.sortDesc = ns.db and ns.db.sortDesc
    data.rows = ns.db and ns.db.rows
    data.columns = ns.db and table.concat(ns.db.columns, ",")

    -- TODOS os atores que a API devolveu, na ordem em que vieram. É o que responde
    -- "por que fulano não aparece" e "de onde saiu esse número".
    local session = ns.Data.GetSession(ns.db.sessionType, def.attr)
    local sources = session and session.combatSources
    if sources then
        data.sessionTotal = Describe(session.totalAmount)
        data.actors = {}
        for i = 1, math.min(#sources, 8) do
            local src = sources[i]
            data.actors[i] = {
                name = Describe(src.name),
                total = Describe(src.totalAmount),
                perSecond = Describe(src.amountPerSecond),
                class = Describe(src.classFilename),
                isLocalPlayer = Describe(src.isLocalPlayer),
                classification = Describe(src.classification),
            }
        end
    end

    -- E o que as linhas montadas realmente contêm, depois de toda a nossa lógica.
    local rows = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
        ns.db.rows or 5, not ns.db.sortDesc)
    data.builtRows = rows and #rows or 0
    if rows and rows[1] then
        data.firstBuilt = {
            name = Describe(rows[1].source.name),
            value1 = Describe(rows[1].values[1]),
            value2 = Describe(rows[1].values[2]),
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
