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
    rows = 8,
    scale = 1.0,
    font = nil,               -- caminho da fonte; nil = Friz Quadrata do jogo
    fontSize = 12,
    rowHeight = 20,
    columnWidth = 58,
    width = nil,              -- largura escolhida na alça; nil = mínimo das colunas
    rowIcon = "spec",         -- "spec" (padrão) ou "class"
    highlightBest = true,     -- realça quem lidera cada coluna
    autoHeight = true,        -- encolhe para o número de jogadores; a alça desliga isso
    locked = false,
    shown = true,             -- a janela volta como o usuário deixou
    combatOnly = false,       -- só aparece em combate
    hideDelay = 5,            -- segundos para sumir depois da luta, no modo acima
    minimap = { hide = false, angle = 200 },
    autoScoreboard = true,
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
-- Scoreboard de fim de conteúdo
--------------------------------------------------------------------------------
function handlers:CHALLENGE_MODE_COMPLETED()
    if not ns.db.autoScoreboard then return end
    -- Pequena espera: a sessão ainda está sendo fechada quando o evento dispara.
    C_Timer.After(1.5, function()
        ns.Scoreboard.OnChallengeCompleted()
    end)
end

function handlers:ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)
    if not ns.db.autoScoreboard then return end
    if success ~= 1 and success ~= true then return end
    if not IsInRaid() then return end   -- em M+ quem manda é o CHALLENGE_MODE_COMPLETED

    local difficultyName = difficultyID and select(1, GetDifficultyInfo(difficultyID)) or nil
    C_Timer.After(1, function()
        ns.Scoreboard.OnEncounterEnd(encounterName, difficultyName)
    end)
end

-- Ao sair do combate os valores deixam de ser secret: vale um refresh completo.
function handlers:PLAYER_REGEN_ENABLED()
    FlushQueue()
    ns.Window.Refresh(true)
    ns.Window.OnCombatEnd()
end

function handlers:PLAYER_REGEN_DISABLED()
    ns.Window.OnCombatStart()
    ns.Window.Refresh(true)
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
