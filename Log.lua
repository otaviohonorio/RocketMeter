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

local L = ns.L

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

--------------------------------------------------------------------------------
-- Erros inesperados
--------------------------------------------------------------------------------
-- ⚑ O DIÁRIO SÓ SABIA O QUE A GENTE MANDOU ELE ANOTAR. Erro de Lua ficava fora dele — quem
-- guardava era o !BugGrabber, addon de terceiro, num arquivo de 534 KB com os erros de todo
-- mundo. Em 09/09/2026 isso custou caro nos dois lados: um `for candidate = 0, 3` no diagnóstico
-- do medidor levantava **uma vez por combate**, 1628 vezes acumuladas, e ninguém tinha visto.
--
-- Agora cada addon guarda os erros DELE, no diário dele, junto do que estava acontecendo.
--
-- ⚑ E SÃO DOIS CAMINHOS, NÃO UM, porque o `!BugGrabber` **desliga o `seterrorhandler`**:
-- `real_seterrorhandler(grabError)` e logo abaixo `function seterrorhandler() end`
-- (`!BugGrabber/BugGrabber.lua:573-574`). Instalar um handler com ele presente é uma chamada que
-- não faz nada e não avisa — a captura pareceria ligada e o arquivo sairia vazio para sempre.
--
--   1. com !BugGrabber: assina `BugGrabber.BugGrabbed` no `EventRegistry` e copia o que é nosso.
--      É o caminho melhor: ele já traz pilha e locais prontos;
--   2. sem ele: encadeia no handler que estiver valendo — e **confere que pegou**, comparando
--      `geterrorhandler()` com o nosso. Sem essa conferência o caso 1 passaria despercebido.
--
-- `store.captura` grava qual dos dois valeu. Isso não é enfeite: sem esse campo, "o arquivo não
-- tem erro nenhum" é ambíguo entre *não houve erro* e *não estávamos capturando*.
local MAX_ERROS = 40

local capturaInstalada = false

---Só os quadros DESTE addon, e no máximo seis.
---
---A pilha inteira do jogo tem trinta linhas de `FrameXML` que não dizem nada sobre o nosso
---defeito; o que interessa é onde ELE está. Se nenhuma linha for nossa, devolve `nil` — e é assim
---que o filtro decide que o erro é de outro addon.
local function NossosQuadros(stack)
    if type(stack) ~= "string" then return nil end

    local linhas, achou = {}, false
    for linha in stack:gmatch("[^\r\n]+") do
        if linha:find("AddOns\\" .. ADDON, 1, true) or linha:find("AddOns/" .. ADDON, 1, true) then
            achou = true
            if #linhas < 6 then
                linhas[#linhas + 1] = (linha:gsub("^%s+", ""))
            end
        end
    end

    if not achou then return nil end
    return table.concat(linhas, " <- ")
end

---Grava um erro nosso. Repetição vira contagem, não linha nova.
---
---⚑ A CONTAGEM É O PONTO. O caso que motivou isto repetiu 1628 vezes; sem agrupar, o anel de 300
---linhas seria varrido pelo mesmo erro e apagaria justamente o contexto que explica ele.
local function RegistrarErro(mensagem, stack)
    if type(mensagem) ~= "string" then return end

    local nossos = NossosQuadros(stack)
    -- A mensagem também identifica: `Window.lua:882: ...` já diz de quem é, mesmo sem pilha.
    local pelaMensagem = mensagem:find("AddOns\\" .. ADDON, 1, true)
        or mensagem:find("AddOns/" .. ADDON, 1, true)
    if not nossos and not pelaMensagem then return end

    local store = Store()
    store.erros = store.erros or {}

    for _, e in ipairs(store.erros) do
        if e.mensagem == mensagem then
            e.vezes = (e.vezes or 1) + 1
            e.ultima = date("%Y-%m-%d %H:%M:%S")
            return
        end
    end

    store.erros[#store.erros + 1] = {
        mensagem = mensagem,
        pilha = nossos,
        vezes = 1,
        primeira = date("%Y-%m-%d %H:%M:%S"),
        ultima = date("%Y-%m-%d %H:%M:%S"),
        versao = ns.version,
        combate = InCombatLockdown() and true or false,
        -- ONDE A CORRENTE ESTAVA. Um erro sozinho diz o quê; com a última linha do diário ao lado,
        -- diz também o quando — e foi o "quando" que respondeu as duas investigações de 09/09.
        depoisDe = (function()
            local ultimo = Store().entries[#Store().entries]
            return ultimo and (ultimo.time .. " " .. tostring(ultimo.event)) or nil
        end)(),
    }

    while #store.erros > MAX_ERROS do tremove(store.erros, 1) end
end

---Liga a captura. Idempotente: chamar de novo não instala dois handlers.
---@return string qual caminho valeu ("buggrabber", "handler" ou "nenhuma")
function Log.CaptureErrors()
    if capturaInstalada then return Store().captura or "nenhuma" end
    capturaInstalada = true

    local store = Store()

    -- CAMINHO 1: o !BugGrabber já capturou tudo; a gente só copia o que é nosso.
    if BugGrabber and BugGrabber.GetErrorByID and EventRegistry then
        EventRegistry:RegisterCallback("BugGrabber.BugGrabbed", function(_, tableID)
            -- `pcall` porque isto roda DENTRO do tratamento de um erro: estourar aqui é como se
            -- perde o erro original, e o jogador vê um defeito nosso no lugar do defeito real.
            pcall(function()
                local erro = BugGrabber:GetErrorByID(tableID)
                if erro then RegistrarErro(erro.message, erro.stack) end
            end)
        end, Log)
        store.captura = "buggrabber"
        return store.captura
    end

    -- CAMINHO 2: encadeia no handler que estiver valendo.
    if type(seterrorhandler) == "function" then
        local anterior = type(geterrorhandler) == "function" and geterrorhandler() or nil
        local meu
        meu = function(mensagem, ...)
            pcall(RegistrarErro, mensagem, debugstack and debugstack(2) or nil)
            if anterior then return anterior(mensagem, ...) end
        end

        seterrorhandler(meu)

        -- ⚑ CONFERE QUE PEGOU. Ver a nota do topo: com o !BugGrabber presente esta chamada é um
        -- `function() end`, e sem esta linha a captura se declararia ligada estando desligada.
        if type(geterrorhandler) == "function" and geterrorhandler() == meu then
            store.captura = "handler"
            return store.captura
        end
    end

    store.captura = "nenhuma"
    return store.captura
end

---Esquece que a captura foi instalada, para o harness poder exercitar os TRÊS mundos
---(com !BugGrabber, sem ele, e com o `seterrorhandler` neutralizado sem ele).
---
---Gancho de teste declarado, no estilo do `Picker.__probe` — e ele existe por necessidade: a
---escolha do caminho acontece UMA vez, no carregamento, e sem poder desfazê-la o harness só
---conseguiria testar o mundo em que ele mesmo carregou.
function Log.__resetCapture()
    capturaInstalada = false
    Store().captura = nil
end

---Quantos erros distintos estão guardados, e quantas ocorrências no total.
function Log.ErrorCount()
    local distintos, total = 0, 0
    for _, e in ipairs(Store().erros or {}) do
        distintos = distintos + 1
        total = total + (e.vezes or 1)
    end
    return distintos, total
end

---O resumo dos erros no chat. Responde "aconteceu alguma coisa?" sem `/reload` e sem sair do
---jogo — que é o que o arquivo exige, porque SavedVariables só é escrito no logout.
---
---⚑ E ELE DIZ SE ESTÁ CAPTURANDO. "Nenhum erro" e "não estou olhando" são estados diferentes e
---parecem iguais no silêncio; sem esta linha, o segundo passaria por bom notícia.
function ns.PrintErrorSummary()
    local distintos, total = Log.ErrorCount()
    local modo = Store().captura or "nenhuma"

    if modo == "nenhuma" then
        ns.Print(L["errors are NOT being captured on this client."])
        return
    end

    if distintos == 0 then
        ns.Print(format(L["no error captured (capture: %s)."], modo))
        return
    end

    ns.Print(format(L["%d error(s) captured, %d occurrence(s):"], distintos, total))
    for _, e in ipairs(Store().erros or {}) do
        print(format("  |cffff5555x%d|r %s", e.vezes or 1, e.mensagem))
        if e.pilha then print("      " .. e.pilha) end
    end
end

function Log.ClearErrors()
    Store().erros = {}
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

    -- A captura entra AQUI, e não no `PLAYER_LOGIN`: erro que acontece durante a
    -- carga do addon é justamente o que ninguém vê passar.
    Log.CaptureErrors()
end
