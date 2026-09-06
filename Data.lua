-- RocketMeter | Data.lua
-- Camada única sobre C_DamageMeter. Nenhum outro arquivo fala com a API do jogo.
--
-- TRÊS LIÇÕES QUE CUSTARAM CARO:
--
-- 0) **Addon não pode devolver um secret value para a API.** Tentar
--    `GetCombatSessionSourceFromType(tipo, atributo, guidSecret)` responde
--    "Secret values are only allowed during untainted", e o erro derruba o desenho inteiro.
--    Era a base do cruzamento de métricas e estava errado: em combate o GUID é secret, então
--    só dá para cruzar métricas **fora** de combate. Dentro dela, cada métrica é uma lista
--    própria e ordenada, e a única linha que dá para casar é a do próprio jogador
--    (`isLocalPlayer`, que continua legível).
--
-- 1) Uma coluna é **(métrica, campo)**, não só uma métrica. O valor por segundo vem no campo
--    `amountPerSecond` do MESMO objeto que traz o total — é assim que o Details! faz. Os
--    atributos `Enum.DamageMeterType.Dps` e `.Hps` devolvem os mesmos totais do dano/cura, e
--    usá-los como "coluna de DPS" faz a tela repetir o total (era o bug até a 0.8.0).
--
-- 2) Em combate os campos são SECRET VALUES: não dá para comparar, somar ou formatar — só
--    repassar a widget. Fora de combate voltam a ser números legíveis.
--
-- 3) **A métrica `Deaths` não é uma soma, é uma LISTA DE MORTES.** Cada entrada de
--    `combatSources` ali é *um óbito*, não um jogador com contagem: a estrutura
--    `DamageMeterCombatSource` traz `deathRecapID` e `deathTimeSeconds`, e o medidor da
--    Blizzard trata a linha como evento — `GetValueText` devolve o **horário** da morte
--    ("3m 22s") e `GetStatusValue` devolve **1 fixo**, porque não existe "amount"
--    (`DamageMeterEntry.lua:562-604`). Ler `totalAmount` ali dá 0 para quem morreu e nada
--    para quem não morreu, que foi exatamente o que apareceu na primeira corrida real.
--    Por isso a coluna de mortes tem `field = "count"` e é **contada**, não somada.
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
        -- `count`, não `total`: na métrica de mortes cada entrada da lista é UMA MORTE, não um
        -- jogador com contagem. Ver a lição 3 no topo do arquivo.
        { key = "deaths",     attr = E.Deaths,               field = "count",     short = L["Deaths"], label = L["Player deaths"] },
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
--------------------------------------------------------------------------------
-- Tipos de sessão
--------------------------------------------------------------------------------
-- **Nao chutar os numeros.** Existe `Enum.DamageMeterSessionType` (Current / Overall /
-- Expired) e os valores dele nao sao necessariamente 0 e 1. Passar numero chumbado foi o
-- que fez a janela ler uma sessao diferente da que o Details le.
function Data.SessionValue(which)
    local E = Enum.DamageMeterSessionType
    if which == 1 or which == "overall" then
        return E and E.Overall or 1
    end
    return E and E.Current or 0
end

---Os valores reais deste cliente, para o log e para o /rm debug.
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

---Id da sessão mais recente. O nome do campo varia entre versões, então aceita os dois.
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

---A sessão de uma métrica.
---
---Depois de `ResetAllCombatSessions`, a sessão "atual" (tipo 0) pode vir **vazia enquanto a
---luta acontece**, e os dados novos aparecem numa sessão nova, endereçada por id. Sem este
---fallback a janela fica em branco durante o combate e só mostra os números quando ele acaba —
---exatamente o sintoma relatado. O Details! mantém os dois caminhos pelo mesmo motivo.
function Data.GetSession(sessionType, attributeId)
    if not Data.IsAvailable() then return nil end

    local session = C_DamageMeter.GetCombatSessionFromType(Data.SessionValue(sessionType), attributeId)
    if HasSources(session) then return session end

    -- Só faz sentido para o combate atual: o geral é acumulado, não é uma sessão solta.
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

---Usado pelo /rm debug: diz por qual caminho os dados vieram.
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

---O `guid` pode ser secret em combate — a API aceita de volta o valor opaco que ela mesma
---produziu, e é isso que torna possível cruzar métricas.
---Dados de um ator dentro de outra métrica.
---
---Só funciona com GUID **legível**: passar um secret de volta para a API é recusado. O `pcall`
---é rede de segurança para o dia em que outra restrição aparecer — um erro aqui não pode
---derrubar o desenho da janela inteira.
function Data.GetSource(sessionType, attributeId, guid, creatureId)
    if not Data.IsAvailable() or guid == nil then return nil end
    if issecretvalue(guid) then return nil end

    local ok, result = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
        Data.SessionValue(sessionType), attributeId, guid, creatureId)
    if ok then return result end
    return nil
end

---O próprio jogador dentro de uma métrica.
---
---`isLocalPlayer` continua legível em combate, então é o único jeito de casar uma linha com
---outra métrica enquanto a luta acontece — e é a linha que mais importa para quem está jogando.
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

---Quantas entradas o próprio jogador tem nesta métrica.
---
---Existe por causa das mortes, onde a lista tem uma entrada por óbito. `isLocalPlayer` é
---`NeverSecret`, então esta contagem funciona **inclusive em combate** — é a única linha que
---continua contável quando o GUID some.
function Data.CountLocalPlayerEntries(session)
    local list = session and session.combatSources
    if not list then return nil end

    local n = 0
    for i = 1, #list do
        local flag = list[i].isLocalPlayer
        if flag ~= nil and not issecretvalue(flag) and flag == true then
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
---@param offset number|nil quantas linhas pular no topo (rolagem)
---@return table[]|nil rows
---@return table|nil session
---@return number total quantos atores existem ao todo, para limitar a rolagem
function Data.GetRows(sessionType, sortKey, columns, maxRows, ascending, offset)
    local sortDef = Data.GetColumn(sortKey)
    if not sortDef then return nil, nil end

    local session = Data.GetSession(sessionType, sortDef.attr)
    local sources = session and session.combatSources
    if not sources then return nil, nil end

    -- Uma consulta por métrica (não por linha): serve para o percentual e para achar a
    -- linha do próprio jogador quando o GUID está secret.
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

    -- Índice guid -> ator, por métrica.
    --
    -- O cruzamento antes usava `GetCombatSessionSourceFromType`, que devolve o **contêiner de
    -- magias** — tem `totalAmount` e `combatSpells`, mas **não tem `amountPerSecond`**. Por isso
    -- as colunas de taxa cruzada (CPS) ficavam em branco enquanto o total aparecia.
    -- A lista da sessão traz o ator completo; um índice por métrica resolve, e ainda troca N
    -- chamadas de API por linha por uma só por coluna.
    ---Identidade de um ator sem usar o GUID.
    ---
    ---`classFilename` e `specIconID` são **`NeverSecret`** na documentação da estrutura
    ---(`DamageMeterCombatSource`), então continuam legíveis onde o GUID não está — dentro de
    ---combate e durante a chave inteira, que é justamente quando o cruzamento falhava e o
    ---healer aparecia sem cura nenhuma.
    ---
    ---Não é identidade de verdade: dois jogadores da mesma especialização colidem. Por isso a
    ---chave só é usada quando é **única nas duas listas** — na de origem e na da métrica. Em
    ---caso de empate o addon devolve nil e a célula fica vazia, que é melhor que trocar os
    ---números de dois jogadores.
    local function IdentityKey(source)
        local class, icon = source.classFilename, source.specIconID
        if class == nil or issecretvalue(class) then return nil end
        if icon == nil or issecretvalue(icon) then return nil end
        return tostring(class) .. "/" .. tostring(icon)
    end

    -- A LISTA DE LINHAS É A UNIÃO DOS ATORES DE TODAS AS MÉTRICAS EXIBIDAS.
    --
    -- Era a lista de UMA métrica — a que ordena a janela — e isso apagava gente. Duas frases do
    -- usuário, no mesmo dia, que são a mesma regra vista de dois ângulos:
    --
    --   "o healer pode dar 0 dano e curar muito, ele tem que aparecer no medidor"
    --   "pode ter alguém que não cura e nem dá dano, só dá interrupt, tem que aparecer"
    --
    -- Quem não pontua na métrica ordenada não estava na lista dela, e portanto não tinha linha —
    -- nem para mostrar zero. O medidor mostrava "quem fez dano", não "quem estava lá".
    --
    -- CADA ATOR ACRESCENTADO LEMBRA DE QUAL MÉTRICA VEIO (`rowAttr`), e isso é obrigatório: o
    -- laço de baixo semeia o cache com `cache[sortDef.attr] = source`, o que para um ator vindo
    -- da cura poria a CURA dele na coluna de dano. O valor da métrica ordenada, para ele, sai da
    -- busca normal — não acha, é conclusivo, e vira zero. Que é o número certo.
    --
    -- DEDUPLICAÇÃO, e o cuidado é o mesmo do resto do arquivo: por GUID quando ele é legível
    -- (todo conteúdo fora de mítica+), e por classe+spec quando não é. Onde a identidade não
    -- serve, o ator NÃO entra — duplicar uma linha é pior que faltar uma, porque os números
    -- passam a ser contados duas vezes na frente do jogador.
    local rowAttr = {}
    do
        local uniao, vistoGuid, vistoIdentidade = {}, {}, {}

        for i = 1, #sources do
            local source = sources[i]
            uniao[i] = source

            local guid = source.sourceGUID
            if guid ~= nil and not issecretvalue(guid) then vistoGuid[guid] = true end
            local key = IdentityKey(source)
            if key then vistoIdentidade[key] = true end
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

    -- Identidades ambíguas na LISTA DE ORIGEM: se duas linhas têm a mesma classe+spec,
    -- nenhuma das duas pode ser casada por identidade.
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

    -- Índice por métrica: ator por GUID, ator por identidade, e CONTAGEM por ambos.
    --
    -- A contagem existe por causa da métrica de mortes, onde cada entrada é um óbito e não um
    -- jogador (ver a lição 3 no topo). Nas outras métricas ela não é usada.
    local indexes = {}
    local function IndexFor(attr)
        local index = indexes[attr]
        if index == nil then
            index = false
            local other = SessionFor(attr)
            local list = other and other.combatSources
            if list then
                index = { byGuid = {}, byIdentity = {}, countByGuid = {}, countByIdentity = {} }
                local identitySeen = {}
                for i = 1, #list do
                    local candidate = list[i]

                    local guid = candidate.sourceGUID
                    if guid ~= nil and not issecretvalue(guid) then
                        index.byGuid[guid] = index.byGuid[guid] or candidate
                        index.countByGuid[guid] = (index.countByGuid[guid] or 0) + 1
                    end

                    local key = IdentityKey(candidate)
                    if key then
                        -- Repetição só é ambiguidade para BUSCAR ator. Para CONTAR, repetir é
                        -- o dado: são duas mortes do mesmo jogador.
                        if identitySeen[key] then
                            index.byIdentity[key] = false
                        elseif index.byIdentity[key] == nil then
                            index.byIdentity[key] = candidate
                        end
                        identitySeen[key] = true
                        index.countByIdentity[key] = (index.countByIdentity[key] or 0) + 1
                    end
                end
            end
            indexes[attr] = index
        end
        return index or nil
    end

    ---Acha o ator desta linha dentro de outra métrica.
    ---@return table|nil ator, boolean conclusivo  (conclusivo = "não achar" significa zero)
    local function MatchIn(attr, guid, guidReadable, identityKey)
        local index = IndexFor(attr)
        if not index then return nil, false end

        if guidReadable then
            return index.byGuid[guid], true
        end

        if identityKey and not rowIdentityAmbiguous[identityKey] then
            local hit = index.byIdentity[identityKey]
            -- `false` = a métrica tem duas linhas com esta classe+spec: ambíguo, não conclusivo.
            if hit ~= false then return hit or nil, true end
        end

        return nil, false
    end

    ---Quantas entradas esta linha tem na métrica. Só faz sentido em `Deaths`.
    ---@return number|nil contagem, boolean conclusivo
    local function CountIn(attr, guid, guidReadable, identityKey)
        local index = IndexFor(attr)
        if not index then return nil, false end

        if guidReadable then
            return index.countByGuid[guid] or 0, true
        end

        -- Para CONTAR, repetição na métrica não é ambiguidade — é o próprio dado. O que
        -- precisa ser único é a identidade da LINHA.
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

    -- MONTA TODOS OS ATORES, não só os que cabem na tela.
    --
    -- O realce de líder é "o melhor de cada coluna", e isso é uma propriedade do GRUPO, não da
    -- página. Antes o laço parava em `count` e `MarkColumnLeaders` recebia só a fatia visível:
    -- rolar a janela trocava quem estava marcado, porque o melhor da fatia mudava junto. Era
    -- um realce que dizia "o melhor entre os que você está vendo", o que não significa nada.
    --
    -- O custo é montar valores para o grupo inteiro em vez de para 5 linhas. É barato: as
    -- consultas de sessão e os índices por GUID já são memorizados acima, então cada ator a
    -- mais são apenas buscas em tabela — não chamadas de API.
    local built = {}
    for position = 1, total do
        local source = sources[ascending and (total - position + 1) or position]
        local values = {}

        -- O CACHE É SEMEADO NA MÉTRICA DE ONDE O ATOR VEIO, e não sempre na ordenada. Para quem
        -- entrou pela união, semear na ordenada poria o número dele (cura, interrupções) na
        -- coluna errada — e o valor da coluna ordenada sairia certo por acidente nunca.
        local fromAttr = rowAttr[source] or sortDef.attr
        local cache = { [fromAttr] = source }

        local guid = source.sourceGUID
        local guidReadable = guid ~= nil and not issecretvalue(guid)
        local isLocal = source.isLocalPlayer
        isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true
        local identityKey = IdentityKey(source)

        -- `conclusive[attr]`: nesta métrica, "não achei o ator" quer dizer **zero** ou quer
        -- dizer **não sei**? A diferença é visível: o Details escreve `0`, e escrever `0` onde
        -- não se sabe é mentir. Só é conclusivo quando a linha pôde ser identificada — por
        -- GUID legível, ou por classe+spec única nas duas listas.
        local conclusive = {}

        for c = 1, #columns do
            local def = Data.GetColumn(columns[c])
            if def then
                if def.field == "count" then
                    -- Mortes: contagem de entradas, não soma de `totalAmount`.
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
                            -- Última cartada em combate: `isLocalPlayer` é `NeverSecret`.
                            hit = Data.GetLocalPlayerSource(SessionFor(def.attr))
                            ok = hit ~= nil
                        end
                        from = hit or false
                        conclusive[def.attr] = ok
                        cache[def.attr] = from
                    end

                    local value = ValueFromSource(from or nil, def, sessionTotals[def.attr] or nil)
                    -- Ausente numa lista que sabemos ler = o jogador não pontuou ali. É zero.
                    if value == nil and from == false and conclusive[def.attr]
                        and def.field ~= "percent" then
                        value = 0
                    end
                    values[c] = value
                end
            end
        end

        -- Fatia do total, para o formato `734K (28.2K, 100%)`. Só fora de combate.
        local percentOfTotal
        local sessionTotal = session.totalAmount
        local own = source.totalAmount
        if own ~= nil and sessionTotal ~= nil
            and not issecretvalue(own) and not issecretvalue(sessionTotal)
            and sessionTotal > 0 then
            percentOfTotal = own / sessionTotal * 100
        end

        built[position] = { source = source, values = values, percentOfTotal = percentOfTotal }
    end

    -- Marca sobre a lista COMPLETA: quem lidera não muda ao rolar nem ao trocar a ordenação.
    Data.MarkColumnLeaders(built, columns)

    -- Só agora recorta a janela visível. `best` já veio decidido de cima.
    local rows = {}
    for i = 1, count do
        rows[i] = built[offset + i]
    end

    return rows, session, total
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
            if value ~= nil and not issecretvalue(value) and type(value) == "number" then  -- luacheck: ignore
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
-- Detalhamento por magia
--------------------------------------------------------------------------------
---Lista de magias de um ator, somando uma ou mais métricas.
---
---Cura e absorção viram uma seção só; interrupções e dissipações também. Quando a mesma magia
---aparece em duas métricas, os valores somam.
---@param attributes number[] métricas a agregar
---@return table[]|nil spells ordenadas da maior para a menor: { spellID, amount, perSecond }
---@return number|nil total
function Data.GetSpellBreakdown(sessionType, attributes, guid, creatureId, limit)
    if not Data.IsAvailable() or guid == nil or issecretvalue(guid) then
        return nil, nil
    end

    local bySpell, total = {}, 0

    for _, attribute in ipairs(attributes) do
        local ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            Data.SessionValue(sessionType), attribute, guid, creatureId)

        local spells = ok and container and container.combatSpells or nil
        if spells then
            for i = 1, #spells do
                local spell = spells[i]
                local id = spell.spellID
                local amount = spell.totalAmount

                -- Sem id legível ou com valor secret não há o que somar nem ordenar.
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
-- Formatação
--------------------------------------------------------------------------------
function Data.IsSessionSecret(session)
    if not session then return false end
    local first = session.combatSources and session.combatSources[1]
    return first ~= nil and issecretvalue(first.name)
end

---@return string|nil texto pronto, ou nil se o valor for secret (aí use SetText direto)
---Formato compacto: `2.9M`, `112K`, `847`.
---
---`AbbreviateNumbers` depende do idioma do cliente e devolve textos longos em pt-BR
---("365.594"), que estouravam a largura da coluna e viravam reticências. A referência mostra
---`2.9M` e `112K` — três a quatro caracteres, sempre.
---**Teto rígido de 5 caracteres.** A célula tem 50px e um texto maior não é cortado: vira
---reticências, que é o que o usuário viu numa corrida de 28 minutos. Duas faixas existem só
---por causa disso:
---
---  * **bilhão** — sem ela, 1,2 bilhão de dano dava `"1234.6M"`, sete caracteres. Uma raide
---    longa chega lá.
---  * **centena** — `%.1f` de 339 dá `"339.1M"`, seis. Acima de 100 a casa decimal não
---    informa nada (0,03% do valor) e custa a coluna inteira.
function Data.FormatAmount(value)
    if value == nil or issecretvalue(value) then
        return nil
    end

    -- Os limiares são o valor JÁ ARREDONDADO, não o redondo. 99.999.999 com `%.1f` vira
    -- "100.0M" — seis caracteres — porque o arredondamento empurra a mantissa para três
    -- dígitos antes de o limiar redondo (100.000.000) ser alcançado. Cortar em 99,95M põe
    -- esse caso na faixa de cima, onde ele vira "100M".
    local absolute = value < 0 and -value or value
    if absolute >= 999500000 then
        return format("%.1fB", value / 1000000000)      -- 1.2B
    elseif absolute >= 99950000 then
        return format("%.0fM", value / 1000000)         -- 339M
    elseif absolute >= 1000000 then
        return format("%.1fM", value / 1000000)         -- 33.9M
    elseif absolute >= 9995 then
        return format("%.0fK", value / 1000)            -- 786K
    elseif absolute >= 1000 then
        return format("%.1fK", value / 1000)            -- 9.6K
    end
    return format("%d", value + 0.5)                    -- 847
end

---Quantos caracteres uma célula aguenta antes de virar reticências.
---
---Vale para o texto pronto, venha ele de `FormatAmount` (que respeita isto por construção) ou
---do cliente, no caminho dos valores secret — onde não dá para abreviar na mão e a única
---defesa é **recusar** um formato que volte longo demais.
Data.MAX_CELL_CHARS = 6

--------------------------------------------------------------------------------
-- Formatação de valores secret
--------------------------------------------------------------------------------
-- Abreviar (603K) exige dividir, e aritmética com secret value é proibida em código de addon.
-- A wiki diz que `string.format` é permitido, e `securecallfunction` executa uma função da
-- Blizzard fora do nosso contexto tainted — o que **pode** liberar a conta lá dentro.
--
-- Nada disso é chute: as estratégias são testadas no próprio jogo, na primeira vez que um
-- valor secret aparece, e a que funcionar fica registrada no log. Se nenhuma funcionar, o
-- número aparece cru, como hoje.
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

local chosenStrategy      -- índice da estratégia que funcionou; false = nenhuma

---A saída desta estratégia cabe na célula?
---
---`AbbreviateNumbers` **só abrevia acima de um limiar**; abaixo dele devolve o número por
---extenso com separador de milhar, e em pt-BR isso é `"365.594"` — sete caracteres numa
---célula que aguenta seis. O aviso já estava escrito no comentário de `FormatAmount`, mas a
---sondagem não o obedecia: `AbbreviateNumbers` é a **primeira** da lista, então bastava
---funcionar para ser escolhida, e a partir daí toda célula grande virava reticências.
---
---Um resultado ainda secret passa: não dá para medir, e o widget é quem vai desenhar.
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

---Texto de um valor que pode ser secret. Devolve nil quando não há como formatar — aí o
---chamador repassa o valor cru ao FontString, que o motor renderiza.
---A estratégia escolhida vale como **preferência**, não como veredito final.
---
---Motivo: se cabe ou não depende do VALOR, não só do cliente. `AbbreviateNumbers` devolve
---`"2.9M"` para 2,9 milhões e `"365.594"` para 365 mil — abaixo do limiar de abreviação ela
---escreve o número por extenso. Uma sondagem única, feita com o primeiro valor que aparecer,
---decide errado para metade dos outros: foi assim que a coluna de dano virou reticências
---enquanto a de CPS, com números menores, continuava certa.
---
---Por isso o encaixe é conferido **a cada valor**, e as outras estratégias ficam como reserva.
function Data.FormatSecretAmount(value)
    if chosenStrategy == nil then
        return ProbeStrategies(value)
    end
    if chosenStrategy == false then
        return nil
    end

    local ok, result = pcall(STRATEGIES[chosenStrategy].run, value)
    if not ok then
        -- A restrição pode mudar no meio do caminho: refaz a sondagem uma vez.
        chosenStrategy = nil
        return nil
    end
    if FitsCell(result) then return result end

    -- A preferida não serve para ESTE número. Tenta as outras, sem trocar a preferência —
    -- ela continua sendo a que serve para a maioria.
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

---Formato do medidor nativo: `734K (28.2K, 100%)` — total, e entre parênteses o valor por
---segundo e a fatia do grupo. É o que a imagem de referência mostra.
---
---Concatenação com secret é permitida (`string.format`), mas o percentual exige divisão e por
---isso só existe fora de combate; nesse caso o parêntese sai com o que houver.
function Data.FormatDetailsStyle(total, perSecond, percent)
    local totalText = Data.FormatAmount(total)
    if totalText == nil then
        totalText = Data.FormatSecretAmount(total)
    end

    local parts = {}
    local rateText = Data.FormatAmount(perSecond)
    if rateText == nil then
        rateText = Data.FormatSecretAmount(perSecond)
    end
    if rateText ~= nil then
        parts[#parts + 1] = rateText
    end

    local percentText = Data.FormatPercent(percent)
    if percentText ~= nil then
        parts[#parts + 1] = percentText
    end

    if totalText == nil then
        return nil          -- nem o total deu para formatar: o chamador usa o valor cru
    end

    if #parts == 0 then
        return totalText
    end
    return totalText .. "  |cffb0b0b0(" .. table.concat(parts, ", ") .. ")|r"
end

function Data.FormatPercent(value)
    if value == nil or issecretvalue(value) then
        return nil
    end
    return format("%.0f%%", value)
end
