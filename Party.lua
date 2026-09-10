-- RocketMeter | Party.lua
-- O que o medidor NÃO sabe sobre o grupo: nível de item, pedra angular e saque.
--
-- POR QUE ESTE ARQUIVO EXISTE. O placar passou a ser cópia do **Details! Mythic+ Scoreboard**
-- (pedido do usuário: *"copiar tudo mesmo, deixar literalmente tudo igual"*), e três colunas de
-- lá não saem do `C_DamageMeter`:
--
--   * o **nível de item** ao pé do retrato — vem de inspeção;
--   * a **pedra angular** de cada um — vem de comunicação entre addons;
--   * o **saque** da corrida — vem de um evento que só passa uma vez.
--
-- Nenhuma das três é dado de combate, e por isso nenhuma delas cabia em `Data.lua`, que é o
-- envelope do medidor. Elas moram aqui, com uma regra em comum: **quando não dá para saber, o
-- placar mostra vazio** — nunca um número inventado nem um ícone genérico que o jogador leria
-- como afirmação.
local ADDON, ns = ...

local Party = {}
ns.Party = Party

local issecretvalue = issecretvalue
local UnitName = UnitName
local UnitExists = UnitExists

--------------------------------------------------------------------------------
-- Nível de item: inspeção
--------------------------------------------------------------------------------
-- O caminho é o mesmo do Details (`Details_MythicPlus/inspect.lua`): pedir inspeção da unidade,
-- esperar `INSPECT_READY` e ler `C_PaperDollInfo.GetInspectItemLevel`. Do próprio jogador não se
-- pede nada — `GetAverageItemLevel` responde na hora e é exato.
--
-- ⚠️ **A inspeção tem limite do servidor.** Pedir para cinco pessoas de uma vez faz o cliente
-- descartar as últimas em silêncio, então os pedidos saem espaçados, e o resultado fica em cache
-- por um tempo: no fim de uma chave o equipamento não muda mais.
local INSPECT_GAP = 1.25         -- `INSPECT_REQUEST_COOLDOWN` (inspect.lua:20)
local CACHE_TTL = 900            -- 15 min: dentro de uma corrida o equipamento não muda

local ilevelCache = {}           -- [nome] = { level = n, at = tempo }
local inspectQueue = {}
local inspecting = false

-- Declarada aqui e escrita lá embaixo, junto das outras coisas de LibOpenRaid: o nível de item
-- (que vem primeiro no arquivo) e a pedra (que vem depois) usam a MESMA busca, e um `local`
-- referenciado antes da declaração vira busca de global — `nil` na hora da chamada, calado.
local LibLookup

---Nome curto e legível, ou nil. Identidade pode vir opaca em combate.
local function Readable(name)
    if name == nil or issecretvalue(name) or type(name) ~= "string" or name == "" then return nil end
    return ns.SplitName(name) or name
end

local function Remember(name, level)
    if not name or not level or level <= 0 then return end
    ilevelCache[name] = { level = level, at = GetTime and GetTime() or 0 }
end

---O nível de item conhecido de alguém, ou nil.
---
---**nil é resposta**, e é por isso que o placar desenha um traço em vez de um número: dizer "-"
---é dizer "não sei", e é honesto. Um zero ali seria lido como "está pelado".
function Party.ItemLevel(name)
    name = Readable(name)
    if not name then return nil end

    if UnitName and UnitName("player") == name then
        if GetAverageItemLevel then
            local ok, _, equipped = pcall(GetAverageItemLevel)
            if ok and equipped and not issecretvalue(equipped) and equipped > 0 then
                Remember(name, equipped)
                return equipped
            end
        end
    end

    local entry = ilevelCache[name]
    if entry then
        local now = GetTime and GetTime() or 0
        if now - entry.at < CACHE_TTL then return entry.level end
    end

    -- ⚑ SEGUNDA FONTE: a LibOpenRaid. Relato de 10/09/2026: *"não aparece o ilvl dos outros"* — e a
    -- corrida gravada das 02:28 mostrou `ilevel` só na linha do próprio jogador, num grupo
    -- cross-realm de LFG.
    --
    -- A inspeção é frágil por natureza e não avisa quando falha: exige `CanInspect` (distância,
    -- mesma fase), o servidor descarta pedidos em rajada, e ela só é disparada no
    -- `GROUP_ROSTER_UPDATE` — numa chave o grupo não muda, então **é uma tentativa só, no pior
    -- momento possível** (o começo, com todo mundo se posicionando e tela de carregamento).
    --
    -- A lib não tem nenhum desses limites: o dado viaja pelo canal de addon, funciona cross-realm
    -- e a qualquer distância. Ela entra DEPOIS da inspeção, e não antes, porque a inspeção lê o
    -- cliente direto — quando responde, é a fonte mais exata das duas.
    local gear = LibLookup("GetAllUnitsGear", "GetUnitGear", name)
    local nivel = gear and gear.ilevel
    if type(nivel) == "number" and nivel > 0 then
        Remember(name, nivel)
        return nivel
    end
    return nil
end

local function ReadInspect(unit)
    if not C_PaperDollInfo or not C_PaperDollInfo.GetInspectItemLevel then return end
    local name = Readable(UnitName and UnitName(unit))
    if not name then return end

    local ok, level = pcall(C_PaperDollInfo.GetInspectItemLevel, unit)
    if ok and level and not issecretvalue(level) and level > 0 then
        Remember(name, level)
        if ns.Log then ns.Log.Add("ilvl", { quem = name, nivel = level }) end
    end
end

local function NextInspect()
    inspecting = false
    if #inspectQueue == 0 then return end

    local unit = table.remove(inspectQueue, 1)
    if not UnitExists or not UnitExists(unit) then return NextInspect() end
    if not CanInspect or not CanInspect(unit) then return NextInspect() end

    inspecting = true
    -- `ClearInspectPlayer` antes de cada pedido: sem ele o cliente pode devolver o
    -- `INSPECT_READY` da unidade ANTERIOR, e o nível de item vai parar na linha errada — que é o
    -- pior defeito possível aqui, porque não parece defeito nenhum.
    if ClearInspectPlayer then pcall(ClearInspectPlayer) end
    pcall(NotifyInspect, unit)

    C_Timer.After(INSPECT_GAP, NextInspect)
end

---Enfileira a inspeção do grupo inteiro. Barato e sem efeito visível para os outros.
function Party.RefreshItemLevels()
    if InCombatLockdown and InCombatLockdown() then return end
    if not NotifyInspect then return end

    inspectQueue = {}
    local size = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        for i = 1, size do inspectQueue[#inspectQueue + 1] = "raid" .. i end
    else
        for i = 1, math.max(0, size - 1) do inspectQueue[#inspectQueue + 1] = "party" .. i end
    end

    if not inspecting then NextInspect() end
end

--------------------------------------------------------------------------------
-- Pedra angular
--------------------------------------------------------------------------------
-- A do PRÓPRIO jogador o cliente informa direto. A dos outros **não existe em API nenhuma**: ela
-- viaja pelo canal de addon, e quem a distribui é a `LibOpenRaid-1.0` — a biblioteca que o
-- Details, o WeakAuras e vários outros já embutem, e é dela que o `Details_MythicPlus` lê
-- (`dummytails.lua:28`).
--
-- **O RocketMeter não embute a biblioteca**, e a escolha é deliberada: são 3.660 linhas de código
-- de terceiro, com protocolo de rede próprio, para preencher uma coluna. Em vez disso ele
-- PERGUNTA se ela já está carregada — o que é verdade para quem roda o Details, que é justamente
-- quem tem esse placar como referência. Sem ela, a coluna fica vazia, e vazio aqui é honesto:
-- significa "ninguém me contou", não "não tem pedra".
local function OpenRaid()
    if not LibStub or not LibStub.GetLibrary then return nil end
    local ok, lib = pcall(LibStub.GetLibrary, LibStub, "LibOpenRaid-1.0", true)
    if ok then return lib end
    return nil
end

---Acha a entrada de alguém numa tabela da LibOpenRaid, com ou sem reino no nome.
---
---⚑ A CHAVE DA LIB TEM REINO, E A NOSSA NÃO TINHA. Era isto que deixava a coluna Pedra com só a
---linha do próprio jogador preenchida (relato de 10/09/2026: *"também a pontuação e também a
---pedra, só a minha aparece"*) — a minha vem do caminho `C_MythicPlus`, que não passa pela lib.
---
---As duas tabelas dela seguem o mesmo formato, documentado na fonte instalada
---(`Details/Libs/LibOpenRaid/LibOpenRaid.lua:3044`): **`[playerName-realm] = {information}`**. E as
---funções de busca por unidade fazem `GetUnitName(unitId, true) or unitId` — passando "Gsm", que
---não é token de unidade, elas procuram a chave "Gsm" numa tabela indexada por "Gsm-Dragonblight".
---
---**Não levanta erro: devolve `nil`** — e `nil` aqui é indistinguível de "esse jogador não tem
---pedra" ou "não sei o nível de item dele". Foi isso que fez o defeito sobreviver sem ninguém ver.
---
---Varrer casando pela parte antes do "-" resolve os dois casos (com e sem reino) e não depende de
---sabermos o reino de ninguém — informação que o medidor pode não trazer.
---@param todasFn string nome da função que devolve a tabela inteira
---@param umaFn string nome da função de busca direta, usada como reserva
LibLookup = function(todasFn, umaFn, name)
    local lib = OpenRaid()
    if not lib then return nil end

    if lib[todasFn] then
        local ok, todas = pcall(lib[todasFn])
        if ok and type(todas) == "table" then
            for chave, info in pairs(todas) do
                if type(chave) == "string" and type(info) == "table"
                    and (ns.SplitName(chave) or chave) == name then
                    return info
                end
            end
        end
    end

    -- Reserva: a busca direta, que funciona quando o nome já vem sem reino na tabela dela.
    if lib[umaFn] then
        local ok, info = pcall(lib[umaFn], name)
        if ok and type(info) == "table" then return info end
    end
    return nil
end

---@return number|nil nivel, number|nil mapID
function Party.Keystone(name)
    name = Readable(name)
    if not name then return nil end

    if UnitName and UnitName("player") == name and C_MythicPlus then
        local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel()
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID
            and C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        if level and mapID then return level, mapID end
    end

    local info = LibLookup("GetAllKeystonesInfo", "GetKeystoneInfo", name)
    if not info or not info.level or info.level <= 0 then return nil end
    return info.level, info.challengeMapID
end

---Pede aos colegas os dados de pedra pelo canal da LibOpenRaid.
---
---A lib guarda o que os OUTROS mandam, e eles mandam quando alguém pergunta. Sem o pedido, a
---tabela pode estar vazia numa sessão em que ninguém mais perguntou — e a coluna some sem que
---nada esteja quebrado. Chamar não custa: é um `SendAddonMessage` para o grupo.
function Party.RequestKeystones()
    local lib = OpenRaid()
    if not lib then return false end

    -- `RequestAllData` traz o EQUIPAMENTO junto, e e por isso que ele entra aqui: a mesma ida ao
    -- canal de addon que busca a pedra resolve o nivel de item dos outros, que a inspecao so
    -- consegue as vezes. Se ela nao existir, o pedido de pedra sozinho ainda vale.
    if lib.RequestAllData then pcall(lib.RequestAllData) end

    if not lib.RequestKeystoneDataFromParty then return false end
    local ok, enviou = pcall(lib.RequestKeystoneDataFromParty)
    return ok and enviou or false
end

---Assina o aviso da lib: "a pedra de fulano mudou".
---
---⚑ ISTO É O QUE FAZ O PLACAR SE ATUALIZAR SOZINHO conforme o grupo abre o baú, que é o
---comportamento que o usuário descreveu no Details (10/09/2026): *"conforme os jogadores vão
---abrindo o baú ele vai atualizando o placar"*. A pedra nova só existe depois de o baú abrir, e é
---nesse instante que a lib transmite — não há como capturar antes.
---
---Assina uma vez só: a lib guarda a inscrição numa lista e assinar de novo duplicaria a chamada.
local assinado = false

function Party.WatchKeystones()
    if assinado then return true end

    local lib = OpenRaid()
    if not lib or not lib.RegisterCallback then return false end

    -- A lib chama `objeto[nome](...)`, então precisa de uma tabela com o método pelo nome.
    local ouvinte = {
        RocketMeterKeystoneUpdate = function()
            if ns.Scoreboard and ns.Scoreboard.RefreshExternalColumns then
                pcall(ns.Scoreboard.RefreshExternalColumns)
            end
        end,
    }

    local ok = pcall(lib.RegisterCallback, ouvinte, "KeystoneUpdate", "RocketMeterKeystoneUpdate")
    assinado = ok and true or false
    return assinado
end

--------------------------------------------------------------------------------
-- Saque
--------------------------------------------------------------------------------
local loot = {}                  -- [nome] = itemLink

---O item que alguém pegou nesta corrida, ou nil.
function Party.Loot(name)
    name = Readable(name)
    return name and loot[name] or nil
end

function Party.ResetLoot()
    loot = {}
end

---Guarda um item recebido, com os mesmos filtros do Details (`scoreboard.lua:225-238`).
---
---Os filtros existem porque a coluna é sobre **a peça que a corrida rendeu**: sem eles ela
---mostraria a primeira poção que caísse no colo de alguém.
function Party.NoteLoot(itemLink, playerName)
    local name = Readable(playerName)
    if not name or not itemLink or itemLink == "" then return end
    if not C_Item then return end

    local ok, _, _, _, _, _, itemType = pcall(C_Item.GetItemInfoInstant, itemLink)
    if not ok then return end
    if Enum and Enum.ItemClass then
        if itemType ~= Enum.ItemClass.Weapon and itemType ~= Enum.ItemClass.Armor then return end
    end

    -- Item que só vincula ao equipar é presente para outro personagem, não recompensa desta
    -- corrida — o Details descarta pelo mesmo motivo.
    if C_Item.IsItemBindToAccountUntilEquip then
        local okBind, bound = pcall(C_Item.IsItemBindToAccountUntilEquip, itemLink)
        if okBind and bound then return end
    end

    loot[name] = itemLink
    if ns.Log then ns.Log.Add("saque", { quem = name, item = itemLink }) end

    -- ⚑ E AVISA O PLACAR, porque o saque quase sempre chega DEPOIS da captura da corrida. O
    -- diário de 10/09 mediu: captura às 00:33:18, saque do grupo às 00:33:20 e o do próprio
    -- jogador às 00:33:30. Sem este aviso a coluna nasce vazia e fica vazia para sempre.
    if ns.Scoreboard and ns.Scoreboard.OnLoot then
        pcall(ns.Scoreboard.OnLoot, name, itemLink)
    end
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------
local listener = CreateFrame("Frame")
listener:RegisterEvent("INSPECT_READY")
listener:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
listener:RegisterEvent("GROUP_ROSTER_UPDATE")

listener:SetScript("OnEvent", function(_, event, ...)
    if event == "INSPECT_READY" then
        local guid = ...
        -- O evento traz o GUID; a leitura precisa de um token de unidade. Varrer o grupo é
        -- barato e é o único caminho: não há `UnitFromGUID`.
        local size = GetNumGroupMembers and GetNumGroupMembers() or 0
        local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
        for i = 1, size do
            local unit = prefix .. i
            local unitGuid = UnitGUID and UnitGUID(unit)
            if unitGuid ~= nil and not issecretvalue(unitGuid) and unitGuid == guid then
                ReadInspect(unit)
                break
            end
        end

    elseif event == "ENCOUNTER_LOOT_RECEIVED" then
        -- ⚠️ **A DOCUMENTAÇÃO E O DETAILS DISCORDAM SOBRE O 5º ARGUMENTO.**
        --
        -- `LootDocumentation.lua:136-141` chama a carga de `encounterID, itemID, itemLink,
        -- quantity, itemName, fileName`. O `Details_MythicPlus`, que roda em produção neste
        -- mesmo patch, lê `local _, _, itemLink, _, unitName = ...` (`scoreboard.lua:294`) —
        -- ou seja, trata o 5º como **nome do jogador**.
        --
        -- Duas coisas pesam a favor do Details: o 6º campo se chama `fileName`, que é o nome
        -- clássico do arquivo de CLASSE ("WARRIOR"), e nome de item já viaja dentro do
        -- `itemLink` — um 5º campo repetindo-o não faria sentido.
        --
        -- Então o addon segue o Details **e registra o que chegou**: a linha `saque cru` no
        -- diário responde qual dos dois está certo na primeira corrida real, que é mais barato
        -- que qualquer raciocínio a mais aqui.
        local _, _, itemLink, _, quinto, sexto = ...
        if ns.Log then
            ns.Log.Add("saque cru", { link = itemLink, quinto = quinto, sexto = sexto })
        end
        Party.NoteLoot(itemLink, quinto)

    elseif event == "GROUP_ROSTER_UPDATE" then
        Party.RefreshItemLevels()
    end
end)

ns.PartyListener = listener
