-- RocketMeter | Core.lua
local ADDON, ns = ...
local L = ns.L

ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0.0"

ns.defaults = {
    -- columns/sortBy usam Enum.DamageMeterType, resolvido no PLAYER_LOGIN (o Enum não
    -- existe ainda quando os arquivos carregam). Padrão: o conjunto de Mítico+.
    columns = nil,
    sortBy = nil,
    sessionType = 0,      -- 0 = sessão atual; 1 = geral

    -- A VISÃO SEGUE O COMBATE: em combate, a luta atual; fora dele, o geral. **Ligado por
    -- padrão**, a pedido — e o padrão é o certo porque as duas visões respondem a perguntas
    -- diferentes em momentos diferentes. Durante a luta a única pergunta é "como estou AGORA";
    -- terminada ela, a pergunta vira "como foi a corrida até aqui", e trocar isso na mão a cada
    -- pull é trabalho que a máquina faz melhor.
    --
    -- Trocar na mão continua funcionando (`/rm overall` e o clique no cabeçalho); o que a opção
    -- garante é para onde a visão volta na PRÓXIMA transição de combate.
    autoSession = true,
    sortDesc = true,      -- maior primeiro
    rows = 5,                 -- linhas visíveis; a alça muda isso
    scale = 1.0,
    font = nil,               -- caminho da fonte; nil = a padrao (ns.FONT_CHOICES[1])
    -- TRES textos independentes: corpo das linhas, titulo e cabecalho de coluna. Cada um com
    -- tamanho, contorno e sombra proprios -- mexer num nao pode mexer nos outros, que foi a
    -- reprovacao do corpo unico. Limites e motivo de cada um em `Window.lua`
    -- (FONT_SIZE_MIN/MAX); os padroes ficam em `ROLE_DEFAULTS`, que e a fonte unica deles.
    --
    -- `nil` aqui de proposito: `Profile.EnsureRuntimeDefaults` monta a tabela, herdando as
    -- chaves antigas de quem ja tinha configuracao salva.
    text = nil,
    rowHeight = 20,          -- altura da barra na referência
    columnWidth = 58,

    -- AS DUAS DISTÂNCIAS DA LINHA, configuráveis a pedido (09/09/2026), com print e retângulos
    -- apontando as duas: *"são das distância entre colunas e entre valores nas colunas
    -- mescladas"*. Os padrões são os números que ele deu.
    --
    --   `groupGap`   o branco ENTRE famílias de métrica (Dano+DPS | Cura+CPS | Interr | Mortes)
    --   `totalWidth` a largura da coluna de TOTAL, que é quem governa a distância entre os dois
    --                valores de uma coluna dupla — cada um é ancorado numa ponta da barra, então
    --                aproximar os dois é encurtar a barra, e não mexer num espaçamento
    --
    -- ⚑ As unidades são pixel do jogo, e o print de 09/09 saiu 1:1: o vão medido nele (10 px)
    -- era exatamente o `GROUP_GAP` do código. Medir na tela e digitar aqui funciona.
    groupGap = 8,
    totalWidth = 84,
    width = nil,              -- largura escolhida na alça; nil = mínimo das colunas
    rowIcon = "spec",         -- "spec" (padrão) ou "class"
    barTexture = "flat",      -- chapada, como a referência
    rowBorder = true,         -- borda de 1px separando as linhas
    windowAlpha = 0.9,        -- opacidade do fundo da janela
    barAlpha = 1.0,           -- opacidade do preenchimento da barra
    roundIcons = true,        -- ícone circular, como no medidor nativo
    valueFormat = "columns",  -- colunas, como o usuário quer; "details" = 734K (28.2K, 100%)
    showColumnHeader = true,  -- faixa com os nomes das colunas
    barBrightness = 0.7,      -- escurece a cor da classe para o texto branco contrastar
    highlightBest = true,     -- realça quem lidera cada coluna
    autoHeight = true,        -- encolhe para o número de jogadores; a alça desliga isso
    locked = false,
    shown = true,             -- a janela volta como o usuário deixou
    combatOnly = false,       -- só aparece em combate
    hideDelay = 5,            -- segundos para sumir depois da luta, no modo acima
    minimap = { hide = false, angle = 200 },

    -- Reino do jogador ("-Tichondrius") ao lado do nome. **Desligado por padrão**: ele come a
    -- largura da coluna e o nome é que vira reticências. Quem joga cross-realm liga em
    -- `/rm columns`.
    showRealm = false,

    -- O painel de fim de corrida abre sozinho? Duas chaves, não uma: quem faz Mítico+ toda
    -- noite pode querer o resumo lá e não a cada chefe de raide, e vice-versa. A chave antiga
    -- `autoScoreboard` continua sendo lida uma vez, para não desligar o painel de quem já
    -- tinha escolhido (ver `Profile.MigrateScoreboard`).
    --
    -- ⚑ RAIDE NASCE DESLIGADA (pedido de 11/09: *"o placar da raid por padrão pode deixar
    -- desabilitado"*). A assimetria tem razão de uso: uma corrida de Mítico+ termina UMA vez, e o
    -- resumo é o fecho dela; uma noite de raide tem um chefe atrás do outro, e o painel abrindo a
    -- cada um vira estorvo no meio da progressão.
    autoScoreboardMPlus = true,
    autoScoreboardRaid = false,

    pos = nil,
}

-- O DIARIO E FERRAMENTA DE DESENVOLVIMENTO, E NAO VAI NO PACOTE. Regra do usuario (23/09):
-- *"quando forem publicados não devem gerar os logs, por que vai ficar consumindo espaço e disco
-- do usuário, apenas aqui para desenvolvimento"*. `Log.lua` e o `RocketMeterLogDB` ficam em
-- `#@debug@` no .toc, que o empacotador remove de TODO build (alpha inclusive), e o `.pkgmeta`
-- tira o arquivo do zip. O medidor era o que mais escrevia: um retrato a cada combate.
--
-- Este substituto e o que o jogador recebe: toda chamada responde nada, entao as chamadas ao
-- diario espalhadas pelo addon nao precisam de guarda. Em desenvolvimento o `Log.lua`, carregado
-- depois deste arquivo, troca pelo real.
ns.Log = setmetatable({ enabled = false }, {
    __index = function() return function() end end,
})

function ns.Print(...)
    print("|cffff6a00Rocket|r Meter:", ...)
end

--------------------------------------------------------------------------------
-- Fila de combate
--------------------------------------------------------------------------------
local queue = {}

function ns.RunWhenSafe(fn)
    if InCombatLockdown() then
        queue[#queue + 1] = fn
    else
        fn()
    end
end

local function FlushQueue()
    for i = 1, #queue do
        queue[i]()
    end
    wipe(queue)
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------
local handlers = {}

function handlers:ADDON_LOADED(addon)
    if addon ~= ADDON then return end

    -- O perfil decide se a configuração vem da conta ou deste personagem.
    ns.Profile.Init()
    ns.Log.Init()
end

function handlers:PLAYER_LOGIN()
    -- Colunas padrão dependem de Enum, que só existe com o cliente carregado.
    ns.Profile.EnsureRuntimeDefaults()

    if not ns.Data.IsAvailable() then
        ns.Print(L["the native meter (C_DamageMeter) is not available on this client."])
        return
    end

    ns.Window.Create()
    ns.Minimap.Create()
    ns.SetupOptions()

    -- A visão salva pode ser a do combate anterior ao `/reload`. Aplicar a regra no login é o
    -- que impede a janela de abrir em "Combate atual" parada fora de combate — estado que a
    -- opção existe justamente para não deixar acontecer.
    ns.Window.ApplyAutoSession()

    ns.Window.ApplyVisibility()
end

-- Dados da sessão em andamento mudaram (dispara muito durante o combate).
function handlers:DAMAGE_METER_CURRENT_SESSION_UPDATED()
    ns.Window.Refresh()
end

-- Uma sessão registrada mudou (fim de combate, novo segmento).
function handlers:DAMAGE_METER_COMBAT_SESSION_UPDATED()
    ns.Window.Refresh(true)
end

function handlers:DAMAGE_METER_RESET()
    ns.Window.Refresh(true)
end

--------------------------------------------------------------------------------
-- Gravação da corrida e placar de fim de conteúdo
--------------------------------------------------------------------------------
-- `Run.lua` é arquivo NOVO, e arquivo novo no `.toc` só entra depois de sair para a tela de
-- personagens — `/reload` não basta. Entre atualizar o addon e reiniciar o cliente, `ns.Run`
-- é nil, e `ns.Run.OnCombatStart()` cru derrubaria o `PLAYER_REGEN_DISABLED` a CADA LUTA,
-- levando junto o refresh da janela. O addon inteiro pareceria quebrado por causa de um
-- arquivo que ainda não carregou. `Window.lua` já usa essa guarda pelo mesmo motivo.
local function RunCall(method, ...)
    local run = ns.Run
    if not run or not run[method] then return end
    local ok, err = pcall(run[method], ...)
    if not ok then ns.Print("Run." .. method .. ": " .. tostring(err)) end
end

function handlers:CHALLENGE_MODE_START()
    -- A gravação da linha do tempo não depende de `autoScoreboard`: quem desliga o painel
    -- automático ainda pode abrir depois com `/rm score`, e aí o rodapé precisa ter dados.
    RunCall("Start")

    -- E pede a pedra dos colegas no começo da chave, não no fim: a resposta viaja pelo canal de
    -- addon e leva um instante. Perguntar na captura seria perguntar tarde demais — o mesmo erro
    -- de tempo que deixava a coluna de saque vazia.
    --
    -- ⚑ E ASSINA O AVISO DE MUDANÇA, que é o que faz o placar acertar sozinho depois: a pedra
    -- NOVA de cada um só existe quando ele abre o baú, e é aí que a lib transmite.
    if ns.Party then
        if ns.Party.RequestKeystones then pcall(ns.Party.RequestKeystones) end
        if ns.Party.WatchKeystones then pcall(ns.Party.WatchKeystones) end
    end
end

function handlers:CHALLENGE_MODE_RESET()
    RunCall("Start")    -- refazer a chave recomeça a corrida do zero
end

function handlers:CHALLENGE_MODE_DEATH_COUNT_UPDATED()
    RunCall("OnDeathCountUpdated")
end

-- Entrar no mundo cobre os dois lados que faltavam:
--   * `/reload` no meio da chave — o `CHALLENGE_MODE_START` já passou e a gravação nunca
--     ligaria; `Resume` religa e recupera o instante zero pelo cronômetro do mundo (ou marca
--     a corrida como parcial e cala o rodapé, em vez de mostrar marcador fora de lugar);
--   * sair da masmorra sem completar — nada desarmava a gravação, e ela seguiria anotando
--     as lutas do mundo aberto como se fossem da corrida.
function handlers:PLAYER_ENTERING_WORLD()
    local active
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        active = ok and mapID and mapID ~= 0
    end

    if active then
        RunCall("Resume")
    else
        RunCall("Stop")
    end
end

function handlers:CHALLENGE_MODE_COMPLETED()
    -- WHEN the scoreboard opens, measured (26/09): *"o scoreboard final dele demora um pouco para
    -- aparecer"*, and nothing saved could say where the time went -- the 1.5 s below, or the wait
    -- for the end of combat (`RunWhenSafe`). Scoreboard.lua logs the other two instants.
    ns.scoreboardClock = GetTime and GetTime() or 0
    ns.Log.Add("placar", { fase = "fim da chave", emCombate = InCombatLockdown() and true or false })
    RunCall("Stop")
    -- Idem: grava sempre, mostra conforme a preferência.
    -- Pequena espera: a sessão ainda está sendo fechada quando o evento dispara.
    C_Timer.After(1.5, function()
        ns.Scoreboard.OnChallengeCompleted()
    end)
end

function handlers:ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)
    -- Dentro de uma corrida, todo boss vira marcador na linha do tempo — inclusive quando o
    -- placar automático está desligado.
    RunCall("OnEncounterEnd", encounterName, success)

    if success ~= 1 and success ~= true then return end
    if not IsInRaid() then return end   -- em M+ quem manda é o CHALLENGE_MODE_COMPLETED

    -- A captura acontece mesmo com o painel automático desligado: "ver o último placar de
    -- raide" só funciona se a corrida tiver sido gravada quando aconteceu. Quem decide se a
    -- janela aparece é o `autoScoreboard`, lá dentro.
    C_Timer.After(1, function()
        ns.Scoreboard.OnEncounterEnd(encounterName, difficultyID)
    end)
end

-- Ao sair do combate os valores deixam de ser secret: vale um refresh completo.
function handlers:PLAYER_REGEN_ENABLED()
    FlushQueue()
    ns.Window.Refresh(true)
    ns.Window.OnCombatEnd()
    ns.Log.OnCombatEnd()
    RunCall("OnCombatEnd")
end

function handlers:PLAYER_REGEN_DISABLED()
    ns.Window.OnCombatStart()
    ns.Window.Refresh(true)
    ns.Log.OnCombatStart()
    RunCall("OnCombatStart")
end

local frame = CreateFrame("Frame", ADDON .. "EventFrame")
for event in pairs(handlers) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, ...)
    handlers[event](self, ...)
end)

ns.frame = frame

function RocketMeter_OnCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        ns.OpenOptions()
    else
        ns.Window.Toggle()
    end
end
