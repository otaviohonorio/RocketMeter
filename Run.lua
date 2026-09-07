-- RocketMeter | Run.lua
-- Grava a linha do tempo de uma corrida de Mítico+ enquanto ela acontece.
--
-- POR QUE PRECISA GRAVAR. No fim da corrida o cliente entrega o resultado (tempo, no tempo,
-- mortes, pontuação), mas não entrega o *histórico*: quando cada boss caiu, quando o grupo
-- entrou e saiu de combate, quando alguém morreu. Nada disso é consultável depois. Ou se
-- anota durante, ou o rodapé do placar fica vazio.
--
-- E NÃO DÁ PARA USAR O COMBAT LOG. `COMBAT_LOG_EVENT_UNFILTERED` foi removido no Midnight, e
-- com ele o jeito clássico de saber quem morreu e quando. O que sobrou, e é o que este
-- arquivo usa, são eventos de frame comuns:
--
--   CHALLENGE_MODE_START             -> zera e marca o instante zero
--   PLAYER_REGEN_DISABLED/ENABLED    -> os trechos de dentro e fora de combate
--   ENCOUNTER_END (success)          -> o instante de cada boss
--   CHALLENGE_MODE_DEATH_COUNT_UPDATED -> quando o contador de mortes sobe
--
-- LIMITE CONHECIDO E ACEITO: o evento de morte dá **quando**, não **quem**. A contagem por
-- jogador continua vindo da coluna de mortes do medidor, que é exata; o marcador na linha do
-- tempo fica sem nome. Descobrir o nome exigiria `UNIT_DIED`, cuja validade como evento de
-- frame no 12.1 não está confirmada em lugar nenhum — preferi um marcador anônimo a um
-- `RegisterEvent` que pode estourar.
local ADDON, ns = ...

local Run = {}
ns.Run = Run

local active = false
local startedAt
local partial = false        -- corrida cujo comeco nao foi gravado (entrou depois do inicio)

-- A PARTIR DE QUANDO O REGISTRO VALE, em segundos de corrida. `nil` (ou 0) significa "desde o
-- primeiro instante"; qualquer outro numero e uma corrida RETOMADA, e o trecho antes dele o
-- addon nao viu.
--
-- Isto existe por causa de um defeito relatado com print (07/09 20:22): o painel anunciava
-- **"Fora de combate: 26:13"** numa chave de 26:13 -- ou seja, a corrida inteira. A causa era o
-- `/reload` no meio da chave, que e rotina para quem mexe em addon: `Run.Resume` recupera o
-- tempo total do cronometro do mundo, mas o registro de combate recomeca vazio. Somar "o que nao
-- esta marcado como combate" sobre um registro que so cobre o fim da corrida da o tempo todo.
--
-- O proprio arquivo ja tinha a regra escrita, para os offsets: *"um rodape ausente e honesto, um
-- rodape com os bosses todos deslocados e mentira -- e mentira com aparencia de dado e o pior
-- resultado possivel"*. Faltava valer para o CONTEUDO tambem.
local knownFrom = 0
local combatTimeline = {}
local bosses = {}
local deaths = {}
local lastDeathCount = 0

---Segundos desde o início da corrida. Fora de corrida devolve nil, e quem chama simplesmente
---não grava — é o que faz este módulo ser inerte quando não há M+ em andamento.
local function Elapsed()
    if not active or not startedAt then return nil end
    local now = GetTime()
    local at = now - startedAt
    if at < 0 then at = 0 end
    return at
end

function Run.Start()
    active = true
    partial = false
    knownFrom = 0
    startedAt = GetTime()
    combatTimeline = {}
    bosses = {}
    deaths = {}
    lastDeathCount = 0

    -- Semente: a corrida começa fora de combate. Sem esta entrada o primeiro trecho do
    -- trilho ficaria sem cor até o primeiro `PLAYER_REGEN_DISABLED`.
    combatTimeline[1] = { 0, InCombatLockdown() and true or false }

    -- O QUE O PLACAR COPIADO PRECISA E O MEDIDOR NÃO SABE (0.66.0): o saque é da corrida que
    -- começa agora, e o nível de item de cada um se pede AQUI, no início — a inspeção é
    -- espaçada de propósito e leva alguns segundos, e no fim da chave o grupo já está se
    -- desfazendo.
    if ns.Party then
        ns.Party.ResetLoot()
        ns.Party.RefreshItemLevels()
    end
end

function Run.Stop()
    active = false
end

---Retoma a gravacao quando o addon carrega DENTRO de uma corrida ja em andamento — o caso do
---`/reload` no meio da chave, que e rotina quando se esta mexendo em addon.
---
---Sem isto o `CHALLENGE_MODE_START` ja passou, `Run` nunca liga, e no fim da corrida o rodape
---do placar aparece vazio sem nada explicar.
---
---O instante zero e recuperado do cronometro do mundo. Se ele nao vier, a corrida fica marcada
---como PARCIAL e os getters devolvem nil: um rodape ausente e honesto, um rodape com os bosses
---todos deslocados e mentira — e mentira com aparencia de dado e o pior resultado possivel.
function Run.Resume()
    if active then return end
    if not C_ChallengeMode or not C_ChallengeMode.GetActiveChallengeMapID then return end

    local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    if not ok or not mapID or mapID == 0 then return end

    Run.Start()

    local elapsed = Run.ElapsedFromWorldTimer()
    if elapsed then
        startedAt = GetTime() - elapsed
        -- O REGISTRO SO VALE DAQUI PARA A FRENTE. A semente entra no instante da retomada, nao
        -- no zero: marcar o zero como "fora de combate" seria afirmar sobre os 20 minutos que o
        -- addon nao acompanhou.
        knownFrom = elapsed
        combatTimeline[1] = { elapsed, InCombatLockdown() and true or false }
    else
        partial = true
    end
end

---Segundos ja decorridos da chave, lidos do cronometro do mundo.
---
---Usa `Enum.WorldElapsedTimerTypes.ChallengeMode`, nao a global legada
---`LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE`: essa constante aparece uma unica vez em todos
---os addons instalados e nenhum a define, entao provavelmente e nil neste cliente — e
---`timerType ~= nil` seria sempre verdadeiro, fazendo a busca nunca achar o cronometro.
function Run.ElapsedFromWorldTimer()
    if not GetWorldElapsedTimers or not GetWorldElapsedTime then return nil end
    local wanted = Enum and Enum.WorldElapsedTimerTypes and Enum.WorldElapsedTimerTypes.ChallengeMode
    if wanted == nil then return nil end

    local ok, timers = pcall(GetWorldElapsedTimers)
    if not ok or type(timers) ~= "table" then return nil end

    for i = 1, #timers do
        local got, _, elapsed, kind = pcall(GetWorldElapsedTime, timers[i])
        if got and kind == wanted and type(elapsed) == "number" and elapsed > 0 then
            return elapsed
        end
    end
    return nil
end

function Run.IsPartial()
    return partial
end

---A partir de que segundo da corrida o registro pode ser lido como verdade.
---
---0 numa corrida acompanhada do inicio; o instante da retomada quando houve `/reload` no meio.
---Quem desenha usa isto para nao afirmar sobre o trecho que ninguem viu.
function Run.GetKnownFrom()
    if partial then return nil end
    return knownFrom
end

function Run.IsActive()
    return active
end

function Run.OnCombatStart()
    local at = Elapsed()
    if not at then return end
    combatTimeline[#combatTimeline + 1] = { at, true }
end

function Run.OnCombatEnd()
    local at = Elapsed()
    if not at then return end
    combatTimeline[#combatTimeline + 1] = { at, false }
end

---Um boss caiu. `success` do `ENCOUNTER_END` vem como 1 ou true dependendo do cliente.
function Run.OnEncounterEnd(encounterName, success)
    if success ~= 1 and success ~= true then return end
    local at = Elapsed()
    if not at then return end
    bosses[#bosses + 1] = { at, encounterName }
end

---O contador de mortes da masmorra subiu. Pode subir mais de um de uma vez (grupo inteiro
---morrendo junto), e aí grava um marcador por morte no mesmo instante.
function Run.OnDeathCountUpdated()
    local at = Elapsed()
    if not at then return end

    local count = 0
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local ok, value = pcall(C_ChallengeMode.GetDeathCount)
        if ok and type(value) == "number" then count = value end
    end

    -- Sem contador legível, registra uma morte e segue: melhor um marcador a menos do que
    -- um laço que não termina.
    if count <= lastDeathCount then
        deaths[#deaths + 1] = { at }
        lastDeathCount = lastDeathCount + 1
        return
    end

    for _ = lastDeathCount + 1, count do
        deaths[#deaths + 1] = { at }
    end
    lastDeathCount = count
end

-- Os tres getters devolvem nil quando a corrida e PARCIAL. O carimbo de tempo de tudo que foi
-- gravado depende do instante zero, e numa corrida parcial esse instante e desconhecido: os
-- marcadores sairiam todos deslocados, e o usuario nao teria como saber disso olhando.
function Run.GetCombatTimeline()
    if partial or #combatTimeline == 0 then return nil end
    return combatTimeline
end

function Run.GetBosses()
    if partial or #bosses == 0 then return nil end
    return bosses
end

function Run.GetDeaths()
    if partial or #deaths == 0 then return nil end
    return deaths
end
