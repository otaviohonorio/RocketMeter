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
    -- COMO A BARRA DA LINHA SE TRATA. Ver `ns.BAR_STYLES` em `Window.lua`: e questao de
    -- RENDERIZACAO, e renderizacao so o jogo responde -- por isso sao variantes trocaveis por
    -- `/rm barra` em vez de um valor decidido no escuro.
    barStyle = "nativo",
    rowHeight = 20,          -- altura da barra na referência
    columnWidth = 58,
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
    autoScoreboardMPlus = true,
    autoScoreboardRaid = true,

    pos = nil,
}

function ns.Print(...)
    print("|cffff6a00Rocket|rMeter:", ...)
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
