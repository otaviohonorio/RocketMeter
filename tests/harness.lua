-- RocketMeter | tests/harness.lua
-- Simulador mínimo da API do WoW para rodar o addon fora do jogo.
--
--   luajit tests/harness.lua        (da pasta do addon)
--
-- Não substitui o teste in-game: não desenha nada e os dados são falsos. Serve para pegar o
-- que quebra no carregamento — nil indexado, função que não existe, evento que estoura.
-- Este arquivo NÃO entra no .toc.

local ADDON = "RocketMeter"

--------------------------------------------------------------------------------
-- Objeto genérico: qualquer método vira no-op que devolve outro objeto genérico.
--------------------------------------------------------------------------------
local function widget(kind)
    local self = { __kind = kind, __scripts = {}, __events = {} }

    function self.SetScript(_, name, fn) self.__scripts[name] = fn end
    function self.GetScript(_, name) return self.__scripts[name] end
    function self.RegisterEvent(_, event) self.__events[event] = true end
    function self.RegisterUnitEvent(_, event) self.__events[event] = true end
    -- FontString sem template nao tem fonte, e o jogo responde "Font not set" no SetText.
    -- O simulador reproduz isso: sem template e sem SetFont previo, SetText estoura.
    function self.CreateFontString(_, _, template)
        local fs = widget("FontString")
        fs.__hasFont = template ~= nil
        function fs.SetFont() fs.__hasFont = true end
        function fs.SetText(_, ...)
            if not fs.__hasFont then
                error("FontString:SetText(): Font not set", 2)
            end
            return ...
        end
        return fs
    end
    function self.CreateTexture() return widget("Texture") end
    function self.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function self.GetName() return kind .. "Stub" end
    function self.IsShown() return true end
    function self.IsMouseEnabled() return true end
    function self.IsForbidden() return false end
    function self.GetStatusBarTexture() return widget("Texture") end
    function self.GetEffectiveScale() return 1 end
    function self.GetCenter() return 400, 300 end
    function self.GetID() return 1 end
    -- Getters numericos: sem isso o codigo que faz conta com GetWidth quebra so no simulador.
    function self.GetWidth() return 400 end
    function self.GetHeight() return 200 end
    function self.GetStringWidth() return 40 end
    function self.GetFrameLevel() return 1 end
    -- A MESMA textura em toda chamada, como no jogo. Devolver uma nova a cada
    -- `GetNormalTexture()` fazia todo teste sobre estado de icone olhar um objeto recem criado
    -- em vez do que o addon acabou de configurar -- o defeito passaria despercebido.
    function self.GetNormalTexture()
        if not self.__normalTexture then
            self.__normalTexture = widget("Texture")
        end
        return self.__normalTexture
    end
    function self.SetNormalTexture(_, path)
        local t = self:GetNormalTexture()
        -- Trocar a textura DESFAZ o atlas, como no jogo: sem isso o atlas anterior ficava
        -- grudado e um teste de "o icone mudou?" respondia sempre que nao.
        t.__texture, t.__atlas = path, nil
        return t
    end
    function self.SetHighlightTexture() end
    -- `SetAtlas` e `SetTexture` REGISTRAM o que receberam: e o unico jeito de um teste
    -- distinguir "trocou o icone" de "nao trocou", ja que o WoW nao devolve isso.
    function self.SetAtlas(_, name) self.__atlas = name; self.__texture = nil end
    function self.SetTexture(_, path) self.__texture = path; self.__atlas = nil end
    function self.GetAtlas() return self.__atlas end
    function self.GetTexture() return self.__texture or "texture" end
    function self.SetDesaturated() end
    function self.SetShown() end

    return setmetatable(self, {
        -- Metodo do WoW e PascalCase; campo que o addon guarda no frame e minusculo.
        -- Sem essa distincao, `row.arrows` devolveria uma funcao e o codigo que testa
        -- "ja existe?" nunca veria nil — falso alarme que nao acontece no jogo.
        __index = function(_, key)
            if type(key) == "string" and key:match("^%u") then
                return function() return widget(key) end
            end
            return nil
        end,
    })
end

local frames = {}

-- FILHOS QUE O TEMPLATE JA TRAZ.
--
-- Sem isto, `check.Text` cai no `__index` generico e volta uma FUNCAO -- que e verdadeira, e
-- portanto passa por `if check.Text then` -- e o `SetText` seguinte estoura so no jogo. E a
-- mesma armadilha do `frame.Inset` no RocketSwap: stub que diverge do template testa a si
-- mesmo. `UICheckButtonTemplate` traz um `Text` posicionado a direita da caixa
-- (`UIPanelTemplates.xml`), e `DefaultPanelTemplate`/`ButtonFrameTemplate` trazem o `Inset`.
local TEMPLATE_PARTS = {
    UICheckButtonTemplate = { "Text" },
    DefaultPanelTemplate = { "Inset" },
    ButtonFrameTemplate = { "Inset" },
    PortraitFrameTemplate = { "Inset" },
}

function CreateFrame(frameType, name, parent, template)
    local f = widget(frameType or "Frame")
    f.__name = name
    f.__template = template

    for _, part in ipairs(TEMPLATE_PARTS[template] or {}) do
        -- Com template: a fonte ja vem definida, como no jogo.
        f[part] = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end

    frames[#frames + 1] = f
    return f
end

--------------------------------------------------------------------------------
-- Globais que o addon usa
--------------------------------------------------------------------------------
UIParent = widget("Frame")
-- Altura de tela plausivel: o placar limita as linhas pelo que cabe, e o stub generico de
-- 200px faria todo teste cair no piso, escondendo o calculo.
UIParent.GetHeight = function() return 1080 end
Minimap = widget("Frame")
GameTooltip = widget("GameTooltip")
UISpecialFrames = {}
RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 0.9 },
                      PRIEST = { r = 1, g = 1, b = 1 },
                      ROGUE = { r = 1, g = 0.96, b = 0.41 } }
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49, 0, 0.25 },
                       PRIEST = { 0.49, 0.73, 0.25, 0.5 },
                       ROGUE = { 0, 0.24, 0.25, 0.5 } }
unpack = unpack or table.unpack

function GameTooltip_Hide() end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCursorPosition() return 400, 300 end
function GetNumGroupMembers() return 5 end
-- Grupo de 5, para o placar descobrir a funcao de cada um sem inspecionar.
local PARTY = {
    player = { name = "Bolva",      role = "TANK" },
    party1 = { name = "Drakaris",   role = "HEALER" },
    party2 = { name = "Kaelvorn",   role = "DAMAGER" },
    party3 = { name = "Sargath",    role = "DAMAGER" },
    party4 = { name = "Lilianvoss", role = "DAMAGER" },
}
function UnitName(unit) return PARTY[unit] and PARTY[unit].name end
function UnitGroupRolesAssigned(unit) return PARTY[unit] and PARTY[unit].role or "NONE" end
function IsInRaid() return false end
function GetLocale() return "ptBR" end
-- Nome cross-realm: o jogo devolve "Nome-Reino" e Ambiguate tira o reino.
function Ambiguate(name, context)
    if context == "short" then return (tostring(name):gsub("%-.*$", "")) end
    return name
end
function date(fmt) return "12:00:00" end
local fakeClock = 1000
function GetTime() return fakeClock end
function time() return 1789000000 end
UNKNOWN = "Desconhecido"
function GetDifficultyInfo(id)
    local map = {
        [14] = { "Normal",  false, false },
        [15] = { "Heroico", true,  false },
        [16] = { "Mitico",  false, true  },
    }
    local d = map[id] or { "Normal", false, false }
    -- name, groupType, isHeroic, isChallengeMode, displayHeroic, displayMythic
    return d[1], "raid", d[2], false, d[2], d[3]
end
function AdvanceClock(seconds) fakeClock = fakeClock + seconds end
function SecondsToClock(s) return string.format("%02d:%02d", s / 60, s % 60) end
function AbbreviateNumbers(v) return tostring(math.floor(v)) end
function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end
function issecretvalue() return false end
function securecallfunction(fn, ...) return fn(...) end
function BreakUpLargeNumbers(v) return tostring(v) end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end end
format = string.format

C_Spell = {
    GetSpellInfo = function(id) return { name = "Magia " .. tostring(id), iconID = 134400 } end,
    RequestLoadSpellData = function() end,
}
function UnitGUID() return "Player-Thalyra" end

-- Le o .toc de verdade em vez de devolver um numero fixo: com constante aqui, um teste
-- sobre versao passaria a confirmar o stub em vez do addon.
C_AddOns = {
    GetAddOnMetadata = function(_, field)
        for line in io.lines(ADDON .. ".toc") do
            local value = line:match("^## " .. field .. ":%s*(.-)%s*$")
            if value then return (value:gsub("%c", "")) end
        end
    end,
}
C_Texture = {
    GetAtlasInfo = function()
        return { file = "atlas.blp", leftTexCoord = 0, rightTexCoord = 1,
                 topTexCoord = 0, bottomTexCoord = 1, width = 64, height = 64 }
    end,
}
C_Timer = { After = function(_, fn) fn() end }
C_ChallengeMode = {
    -- Formato do 12.1.0: UMA TABELA. Os campos abaixo sao os que o placar le.
    GetChallengeCompletionInfo = function()
        return {
            mapChallengeModeID = 2, level = 12, time = 1500000, onTime = true,
            keystoneUpgradeLevels = 1, practiceRun = false,
            oldOverallDungeonScore = 2800, newOverallDungeonScore = 2871,
            isEligibleForScore = true,
        }
    end,
    -- name, id, timeLimit, texture, backgroundTexture
    GetMapUIInfo = function() return "Masmorra de Teste", 2, 1800, 1, 2 end,
    GetDeathCount = function() return 3, 45 end,
    GetActiveKeystoneInfo = function() return 12, { 10, 152 } end,
    GetAffixInfo = function(id) return "Afixo " .. tostring(id), "descricao", 100 end,
}
C_PlayerInfo = {
    GetPlayerMythicPlusRatingSummary = function(name)
        if name == nil then return nil end
        return { currentSeasonScore = 2500 + #tostring(name), runs = {} }
    end,
}
C_MythicPlus = {
    GetCurrentAffixes = function() return { { id = 10 }, { id = 152 }, { id = 148 } } end,
    RequestMapInfo = function() end,
}

Enum = {
    DamageMeterSessionType = { Current = 0, Overall = 1, Expired = 2 },
    DamageMeterType = {
        DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4,
        Interrupts = 5, Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8,
        Deaths = 9, EnemyDamageTaken = 10,
    },
}

-- Dados falsos, no formato lido do Details!
-- Classe e spec DISTINTAS por ator. Nao e enfeite: `classFilename` e `specIconID` sao
-- `NeverSecret` e por isso viraram a chave de casamento entre metricas quando o GUID esta
-- secret. Com os tres atores como "MAGE/1" o casamento por identidade ficava sempre ambiguo
-- e o caminho novo nunca era exercitado.
local FAKE_IDENTITY = {
    Thalyra = { class = "MAGE",   spec = 101 },
    Brumm   = { class = "PRIEST", spec = 102 },
    Sarien  = { class = "ROGUE",  spec = 103 },
}

local function fakeSource(name, total, extra)
    local id = FAKE_IDENTITY[name] or { class = "MAGE", spec = 199 }
    local src = {
        name = name, sourceGUID = "Player-" .. name, sourceCreatureID = 0,
        totalAmount = total, amountPerSecond = total / 120,
        classFilename = id.class, specIconID = id.spec, deathRecapID = 0,
        deathTimeSeconds = 0, classification = "player", isLocalPlayer = name == "Thalyra",
    }
    for k, v in pairs(extra or {}) do src[k] = v end
    return src
end

C_DamageMeter = {
    IsDamageMeterAvailable = function() return true end,
    GetSessionDurationSeconds = function() return 134 end,
    ResetAllCombatSessions = function() end,
    GetAvailableCombatSessions = function() return { { sessionID = 1 } } end,
    GetCombatSessionFromType = function(sessionType, attribute)
        -- Cada metrica tem seus proprios valores: e o que torna os testes de cruzamento
        -- significativos. Antes tudo devolvia a sessao de dano e o teste passava por acidente.
        -- MORTES TEM FORMA PROPRIA: cada entrada da lista e UM OBITO, nao um jogador com
        -- contagem em `totalAmount`. Quem nao morreu simplesmente NAO APARECE. Confirmado na
        -- documentacao da API (`DamageMeterCombatSource` traz `deathRecapID` e
        -- `deathTimeSeconds`), no consumidor da Blizzard (`DamageMeterEntry.lua:562-604`,
        -- onde `GetValueText` devolve o HORARIO e `GetStatusValue` devolve 1 fixo) e no
        -- retrato da primeira corrida real, onde os dois que morreram vieram com 0.
        --
        -- Brumm morreu 2x, Sarien 1x, Thalyra nenhuma.
        if attribute == Enum.DamageMeterType.Deaths then
            return {
                combatSources = {
                    fakeSource("Brumm",  0, { deathRecapID = 11, deathTimeSeconds = 42 }),
                    fakeSource("Sarien", 0, { deathRecapID = 12, deathTimeSeconds = 88 }),
                    fakeSource("Brumm",  0, { deathRecapID = 13, deathTimeSeconds = 130 }),
                },
                combatSourcesCount = 3, totalAmount = 0, maxAmount = 0, durationSeconds = 134,
            }
        end

        local perAttribute = {
            [Enum.DamageMeterType.HealingDone] = { 120000, 900000, 50000 },
            [Enum.DamageMeterType.Interrupts] = { 1, 0, 5 },
            [Enum.DamageMeterType.Dispels] = { 0, 0, 3 },
            [Enum.DamageMeterType.Absorbs] = { 0, 0, 0 },
        }
        local values = perAttribute[attribute]
        if values then
            -- ATOR COM ZERO NAO APARECE. E assim na API -- foi o que o retrato da corrida real
            -- mostrou: o Delzoka nao tinha a chave `avoidable` porque o dele era 0, e o
            -- Details escrevia 0 na mesma celula. Com o stub criando os tres sempre, a
            -- diferenca entre "zero" e "nao sei" nao existia aqui dentro.
            local names = { "Thalyra", "Brumm", "Sarien" }
            local sources, total, maximum = {}, 0, 0
            for i = 1, 3 do
                if values[i] > 0 then
                    sources[#sources + 1] = fakeSource(names[i], values[i])
                    total = total + values[i]
                    if values[i] > maximum then maximum = values[i] end
                end
            end
            return {
                combatSources = sources, totalAmount = total,
                maxAmount = maximum, durationSeconds = 134,
            }
        end
        return {
            combatSources = { fakeSource("Thalyra", 1200000), fakeSource("Brumm", 980000),
                              fakeSource("Sarien", 740000) },
            totalAmount = 2920000, maxAmount = 1200000, durationSeconds = 134,
        }
    end,
    GetCombatSessionSourceFromType = function(sessionType, attribute, guid)
        -- Valores distintos por metrica E por ator: assim o teste de lider por coluna
        -- verifica que o healer (Brumm) lidera a cura mesmo estando em segundo no dano.
        local perActor = {
            ["Player-Thalyra"] = { heal = 120000, interrupts = 1, deaths = 0 },
            ["Player-Brumm"] = { heal = 900000, interrupts = 0, deaths = 2 },
            ["Player-Sarien"] = { heal = 50000, interrupts = 5, deaths = 1 },
        }
        local actor = perActor[guid] or { heal = 0, interrupts = 0, deaths = 0 }
        local byAttribute = {
            [Enum.DamageMeterType.HealingDone] = { totalAmount = actor.heal, amountPerSecond = actor.heal / 120 },
            [Enum.DamageMeterType.Interrupts] = { totalAmount = actor.interrupts, amountPerSecond = 0 },
            [Enum.DamageMeterType.Deaths] = { totalAmount = actor.deaths, amountPerSecond = 0 },
        }
        local entry = byAttribute[attribute] or { totalAmount = 42000, amountPerSecond = 350 }
        return {
            combatSpells = {
                { spellID = 1001, totalAmount = 500000, amountPerSecond = 4000 },
                { spellID = 1002, totalAmount = 300000, amountPerSecond = 2500 },
                { spellID = 1003, totalAmount = 120000, amountPerSecond = 1000 },
            },
            maxAmount = entry.totalAmount,
            totalAmount = entry.totalAmount, amountPerSecond = entry.amountPerSecond,
        }
    end,
    GetCombatSessionFromID = function() return nil end,
}

-- Settings API
local settingsStore = {}
Settings = {
    RegisterVerticalLayoutCategory = function(name)
        return { name = name, GetID = function() return 1 end }, { AddInitializer = function() end }
    end,
    RegisterAddOnCategory = function() end,
    RegisterAddOnSetting = function(_, variable, key, tbl, kind, label, default)
        settingsStore[variable] = { key = key, tbl = tbl, default = default }
        -- exercita o proxy: lê e escreve como o painel faria
        local _ = tbl[key]
        return { variable = variable, GetValue = function() return tbl[key] end }
    end,
    SetOnValueChangedCallback = function() end,
    CreateCheckbox = function() end,
    CreateSlider = function() end,
    CreateDropdown = function() end,
    CreateSliderOptions = function() return {} end,
    CreateControlTextContainer = function()
        return { Add = function() end, GetData = function() return {} end }
    end,
    OpenToCategory = function() end,
}
function CreateSettingsListSectionHeaderInitializer() return {} end

StaticPopupDialogs = {}
YES, NO = "Sim", "Nao"
local popupShown
function StaticPopup_Show(which)
    popupShown = which
    -- executa o OnAccept para exercitar o caminho de verdade
    local dialog = StaticPopupDialogs[which]
    if dialog and dialog.OnAccept then dialog.OnAccept() end
end

SlashCmdList = {}

--------------------------------------------------------------------------------
-- Carrega o addon na ordem do .toc
--------------------------------------------------------------------------------
local ns = {}
local files = {}
for line in io.lines(ADDON .. ".toc") do
    line = line:gsub("\r", "")
    if line:match("%.lua$") and not line:match("^#") then
        files[#files + 1] = line:gsub("\\", "/")
    end
end

print("== carregando " .. #files .. " arquivos ==")
for _, file in ipairs(files) do
    local chunk, err = loadfile(file)
    if not chunk then
        print("  FALHA AO COMPILAR " .. file .. ": " .. err)
        os.exit(1)
    end
    local ok, runErr = pcall(chunk, ADDON, ns)
    print(ok and ("  ok    " .. file) or ("  ERRO  " .. file .. ": " .. tostring(runErr)))
    if not ok then os.exit(1) end
end

--------------------------------------------------------------------------------
-- Dispara os eventos do ciclo de vida
--------------------------------------------------------------------------------
local function fire(event, ...)
    for _, f in ipairs(frames) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, err = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then
                print("  ERRO em " .. event .. ": " .. tostring(err))
                os.exit(1)
            end
        end
    end
    print("  ok    " .. event)
end

print("== ciclo de vida ==")
fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
fire("DAMAGE_METER_CURRENT_SESSION_UPDATED")
fire("DAMAGE_METER_COMBAT_SESSION_UPDATED")
fire("CHALLENGE_MODE_START")
fire("PLAYER_REGEN_DISABLED")
fire("ENCOUNTER_END", 1234, "Chefe de Teste", 16, 20, 1)
fire("CHALLENGE_MODE_DEATH_COUNT_UPDATED")
fire("PLAYER_REGEN_ENABLED")
fire("CHALLENGE_MODE_COMPLETED")

print("== funcionalidades ==")
local function try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    print(ok and ("  ok    " .. label) or ("  ERRO  " .. label .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

try("Window.ApplyVisibility", ns.Window.ApplyVisibility)
try("Window.ApplyLock (travado)", function()
    ns.db.locked = true
    ns.Window.ApplyLock()
end)
try("Window.ApplyLock (destravado)", function()
    ns.db.locked = false
    ns.Window.ApplyLock()
end)
try("Window.Show", ns.Window.Show)
try("Window.Hide", ns.Window.Hide)
try("Window.OnCombatStart", ns.Window.OnCombatStart)
try("Window.OnCombatEnd", ns.Window.OnCombatEnd)
try("Window.Draw", ns.Window.Draw)
try("Window.Rebuild", ns.Window.Rebuild)
try("ApplyRowIcon (spec)", function()
    ns.db.rowIcon = "spec"
    ns.Window.Rebuild()
end)
try("ApplyRowIcon (class)", function()
    ns.db.rowIcon = "class"
    ns.Window.Rebuild()
    ns.db.rowIcon = "spec"
end)
try("Window.ToggleColumn", ns.Window.ToggleColumn, "absorb")
try("Window.MoveColumn", ns.Window.MoveColumn, 2, -1)
try("Window.ApplyPreset(raid)", ns.Window.ApplyPreset, "raid")
try("Minimap.ApplyVisibility", ns.Minimap.ApplyVisibility)
try("Profile.SetPerCharacter(true)", ns.Profile.SetPerCharacter, true)
try("Profile.SetPerCharacter(false)", ns.Profile.SetPerCharacter, false)
try("Profile.Reset", ns.Profile.Reset)
try("Data.RequestReset (com confirmacao)", ns.Data.RequestReset)
try("Data.RequestReset (direto)", ns.Data.RequestReset, true)
try("Log.Snapshot", ns.Log.Snapshot, "teste")
try("Log.OnCombatStart", ns.Log.OnCombatStart)
try("Log.OnCombatEnd", ns.Log.OnCombatEnd)
try("Log.Clear", ns.Log.Clear)
try("Scoreboard.Show", ns.Scoreboard.Show)
try("Breakdown.Show", function()
    local session = C_DamageMeter.GetCombatSessionFromType(0, Enum.DamageMeterType.DamageDone)
    ns.Breakdown.Show(session.combatSources[1], 0)
end)
try("Breakdown.Refresh", ns.Breakdown.Refresh)
try("Breakdown.Hide", ns.Breakdown.Hide)
try("Data.GetRows", ns.Data.GetRows, 0, "damage", { "damage", "dps", "hps" }, 5, false)


print("== valores ==")
-- Regressao da 0.8.0: a coluna de DPS mostrava o total, porque usava o atributo Enum.Dps
-- em vez do campo amountPerSecond. Aqui isso quebra o teste.
local function check(label, got, want)
    local ok = got == want
    print(ok and ("  ok    " .. label .. " = " .. tostring(got))
        or ("  ERRO  " .. label .. ": esperado " .. tostring(want) .. ", veio " .. tostring(got)))
    if not ok then os.exit(1) end
end

local cols = { "damage", "dps", "healing", "hps", "interrupts", "damagepct" }
local rows = ns.Data.GetRows(0, "damage", cols, 5, false)
if not rows or not rows[1] then
    print("  ERRO  GetRows nao devolveu linhas")
    os.exit(1)
end

local first = rows[1].values
check("dano total", first[1], 1200000)
check("dps (amountPerSecond, nao o total)", first[2], 1200000 / 120)
check("cura total (metrica cruzada)", first[3], 120000)
-- Regressao: CPS ficava em branco porque o conteiner de magias nao tem amountPerSecond.
check("cps (metrica cruzada, nao pode ser nil)", first[4], 120000 / 120)
check("interrupcoes (metrica cruzada)", first[5], 1)

-- Lider por coluna: Thalyra lidera o dano (linha 1), mas quem cura mais e o Brumm (linha 2)
-- e quem mais interrompe e o Sarien (linha 3). Cada coluna tem seu proprio realce.
check("lider do dano e a linha 1", rows[1].best and rows[1].best[1] or false, true)
check("lider da cura e a linha 2", rows[2].best and rows[2].best[3] or false, true)
check("linha 1 nao lidera a cura", rows[1].best and rows[1].best[3] or false, false)
check("lider das interrupcoes e a linha 3", rows[3].best and rows[3].best[5] or false, true)
check("percentual do dano", math.floor(first[6] + 0.5), math.floor(1200000 / 2920000 * 100 + 0.5))

-- ordem invertida: a ultima linha vira a primeira, sem comparar nada
local asc = ns.Data.GetRows(0, "damage", cols, 5, true)
check("ordem crescente comeca pelo menor", asc[1].source.totalAmount, 740000)

-- migracao das colunas salvas no formato antigo (ids de Enum)
local migrated = ns.Data.MigrateColumns({ Enum.DamageMeterType.DamageDone, Enum.DamageMeterType.Hps })
check("migracao converte id em chave", migrated[1], "damage")
check("migracao converte Hps em hps", migrated[2], "hps")

print("== mortes sao CONTADAS, nao somadas ==")
-- Primeira corrida real (05/09/2026) trouxe o defeito inteiro num retrato: os tres que NAO
-- morreram vieram sem a chave `deaths`, e os DOIS que morreram vieram com `deaths = 0`.
-- A causa nao era o placar: e que a metrica de mortes lista UM OBITO POR ENTRADA, e
-- `totalAmount` ali nao significa nada. Quem le `totalAmount` acerta zero e erra o resto.
do
    local cols = { "damage", "deaths" }
    local r = ns.Data.GetRows(0, "damage", cols, 5, false)

    -- ordem por dano: Thalyra (1.2M), Brumm (980K), Sarien (740K)
    check("quem nao morreu tem 0, nao vazio", r[1].values[2], 0)
    check("duas mortes do mesmo jogador contam 2", r[2].values[2], 2)
    check("uma morte conta 1", r[3].values[2], 1)
end

print("== ausente numa metrica e ZERO, nao desconhecido ==")
-- O Details escreve `0`. Nos escreviamos "." porque `SourceFor` devolvia nil e o valor virava
-- nil. Quem nao aparece na lista de uma metrica nao pontuou nela -- desde que a lista tenha
-- sido lida, que e o caso fora de combate.
do
    local semDispel = ns.Data.GetRows(0, "damage", { "damage", "dispels" }, 5, false)
    check("sem dissipacoes = 0", semDispel[1].values[2], 0)
end

print("== cruzamento por classe+spec quando o GUID esta secret ==")
-- Durante a chave inteira o GUID e secret (restricao de ChallengeMode) e
-- `GetCombatSessionSourceFromType` recusa receber o valor opaco de volta
-- (`SecretArguments = "AllowedWhenUntainted"` e addon e codigo tainted). Resultado no jogo:
-- so o proprio jogador tinha Cura/CPS e o HEALER aparecia zerado -- reclamacao do usuario.
--
-- `classFilename` e `specIconID` sao `NeverSecret`: dao para casar o ator entre metricas.
do
    local marker = setmetatable({}, { __tostring = function() return "SECRET" end })
    local realIsSecret = issecretvalue
    issecretvalue = function(v) return v == marker end

    local plain = C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType = function(sessionType, attribute)
        local session = plain(sessionType, attribute)
        for i, src in ipairs(session.combatSources) do
            src.sourceGUID = marker
            src.isLocalPlayer = i == 1
        end
        return session
    end

    local r = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 5, false)
    -- Brumm e o healer e esta em SEGUNDO no dano: sem o casamento por identidade a celula
    -- dele fica vazia, que foi o "healer sem informacoes de healer" do print.
    check("healer tem cura mesmo com GUID secret", r[2].values[2], 900000)
    check("terceiro tambem, nao so o jogador local", r[3].values[2], 50000)

    -- E a contagem de mortes tem que sobreviver ao mesmo cenario.
    local d = ns.Data.GetRows(0, "damage", { "damage", "deaths" }, 5, false)
    check("mortes contadas com GUID secret", d[2].values[2], 2)

    C_DamageMeter.GetCombatSessionFromType = plain
    issecretvalue = realIsSecret
end

print("== identidade ambigua nao inventa numero ==")
-- Dois jogadores da mesma classe E spec colidem na chave. Nesse caso o addon tem que devolver
-- vazio, nao o numero do outro: trocar os valores de dois jogadores e pior que nao mostrar.
do
    local marker = setmetatable({}, { __tostring = function() return "SECRET" end })
    local realIsSecret = issecretvalue
    issecretvalue = function(v) return v == marker end

    local plain = C_DamageMeter.GetCombatSessionFromType
    C_DamageMeter.GetCombatSessionFromType = function(sessionType, attribute)
        local session = plain(sessionType, attribute)
        for i, src in ipairs(session.combatSources) do
            src.sourceGUID = marker
            src.isLocalPlayer = false          -- ninguem e o jogador local: so resta a identidade
            src.classFilename = "MAGE"         -- todos iguais de proposito
            src.specIconID = 101
        end
        return session
    end

    local r = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 5, false)
    check("empate de classe+spec deixa vazio", r[2].values[2], nil)

    C_DamageMeter.GetCombatSessionFromType = plain
    issecretvalue = realIsSecret
end

print("== combate: guid secret ==")
-- SIMULA_SECRET: reproduz o bug real relatado no log do usuario. Em combate o GUID e secret,
-- e devolver esse valor para a API responde "Secret values are only allowed during untainted".
-- Antes da correcao, o erro derrubava o desenho e a janela ficava vazia a luta inteira.
local secretMarker = setmetatable({}, { __tostring = function() return "SECRET" end })
local realIsSecret = issecretvalue
issecretvalue = function(v) return v == secretMarker end

local plainFromType = C_DamageMeter.GetCombatSessionFromType
C_DamageMeter.GetCombatSessionFromType = function(sessionType, attribute)
    local session = plainFromType(sessionType, attribute)
    for i, src in ipairs(session.combatSources) do
        src.sourceGUID = secretMarker           -- em combate o GUID e opaco
        src.isLocalPlayer = i == 1              -- so a propria linha da para casar
    end
    return session
end
C_DamageMeter.GetCombatSessionSourceFromType = function(_, _, guid)
    if guid == secretMarker then
        error("Secret values are only allowed during untainted execution")
    end
    return { totalAmount = 1, amountPerSecond = 1 }
end

local combatRows = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 5, false)
if not combatRows or not combatRows[1] then
    print("  ERRO  nenhuma linha em combate — a janela ficaria vazia")
    os.exit(1)
end
print("  ok    " .. #combatRows .. " linha(s) mesmo com guid secret")
if combatRows[1].values[1] == nil then
    print("  ERRO  a coluna ordenada precisa de valor mesmo em combate")
    os.exit(1)
end
print("  ok    coluna ordenada preenchida em combate")

issecretvalue = realIsSecret
C_DamageMeter.GetCombatSessionFromType = plainFromType
C_DamageMeter.GetCombatSessionSourceFromType = function(sessionType, attribute, guid)
    local byAttribute = {
        [Enum.DamageMeterType.HealingDone] = { totalAmount = 600000, amountPerSecond = 5000 },
    }
    return byAttribute[attribute] or { totalAmount = 42000, amountPerSecond = 350 }
end

print("== sessao vazia por tipo (cenario do reset) ==")
-- SIMULA_RESET: depois de zerar, a sessao "atual" volta vazia enquanto a luta acontece.
-- Os dados so aparecem pela sessao por id — sem o fallback, a janela fica em branco.
local originalFromType = C_DamageMeter.GetCombatSessionFromType
C_DamageMeter.GetCombatSessionFromType = function()
    return { combatSources = {}, totalAmount = 0, maxAmount = 0, durationSeconds = 0 }
end
C_DamageMeter.GetCombatSessionFromID = function(id, attribute)
    return originalFromType(0, attribute)
end

local fallbackRows = ns.Data.GetRows(0, "damage", { "damage", "dps" }, 5, false)
if fallbackRows and fallbackRows[1] then
    print("  ok    fallback por id devolveu " .. #fallbackRows .. " linha(s)")
else
    print("  ERRO  fallback por id nao devolveu linhas — janela ficaria vazia em combate")
    os.exit(1)
end

C_DamageMeter.GetCombatSessionFromType = originalFromType
C_DamageMeter.GetCombatSessionFromID = function() return nil end

print("== formato dos numeros ==")
-- Regressao: AbbreviateNumbers do cliente devolvia texto longo e a coluna virava reticencias.
check("milhoes", ns.Data.FormatAmount(2900000), "2.9M")
check("centenas de milhar", ns.Data.FormatAmount(786000), "786K")
check("milhares com decimal", ns.Data.FormatAmount(9600), "9.6K")
check("valor pequeno inteiro", ns.Data.FormatAmount(847), "847")

-- TETO DE LARGURA. A celula tem 50px; texto maior nao e cortado, vira reticencias -- foi a
-- reclamacao "esses pontos me incomoda" depois de uma corrida de 28 minutos. As duas faixas
-- abaixo nao existiam: 339 milhoes davam "339.1M" (6) e 1,2 bilhao dava "1234.6M" (7).
check("centenas de milhao sem decimal", ns.Data.FormatAmount(339123456), "339M")
check("bilhoes tem faixa propria", ns.Data.FormatAmount(1234567890), "1.2B")
check("negativo grande tambem", ns.Data.FormatAmount(-339123456), "-339M")

do
    -- Inclui os pontos de ARREDONDAMENTO, nao so os limiares redondos: e ali que a mantissa
    -- ganha um digito e o texto estoura (99.999.999 dava "100.0M").
    local piores = { 0, 1, 999, 1000, 9994, 9995, 9999, 10000, 999999, 1000000,
                     99949999, 99950000, 99999999, 100000000, 999499999, 999500000,
                     999999999, 1000000000, 9999999999 }
    local maior, culpado = 0, nil
    for _, v in ipairs(piores) do
        local t = ns.Data.FormatAmount(v)
        if #t > maior then maior, culpado = #t, t end
    end
    check("nenhum valor passa do teto (" .. tostring(culpado) .. ")",
        maior <= ns.Data.MAX_CELL_CHARS, true)
end

print("== linhas ==")
ns.Window.SetRows(5)
check("altura padrao mostra 5 jogadores", ns.Window.GetRows(), 5)
ns.Window.SetRows(12)
check("stepper muda a quantidade", ns.Window.GetRows(), 12)
ns.Window.SetRows(0)
check("minimo respeitado", ns.Window.GetRows(), 1)
ns.Window.SetRows(99)
check("maximo respeitado", ns.Window.GetRows(), 20)
ns.Window.SetRows(5)

print("== rolagem ==")
-- Com 3 atores e janela de 2 linhas, rolar uma posicao mostra o 2o e o 3o.
local scrolled, _, totalActors = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 1)
check("total de atores", totalActors, 3)
check("rolagem pula o primeiro", scrolled[1].source.name, "Brumm")
check("janela mostra 2 linhas", #scrolled, 2)

local clamped = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 99)
check("rolagem excessiva nao estoura", clamped ~= nil and #clamped > 0, true)

print("== lider e o melhor de TODOS, nao da pagina ==")
-- Reclamacao do usuario (05/09): "eu rolo e ele vai trocando". O realce era calculado sobre a
-- fatia visivel, entao dizia "o melhor entre os que voce esta vendo" — que nao significa nada.
-- O harness tem 3 atores; com janela de 2, a segunda pagina nao contem o lider de dano e
-- portanto nao pode ter NINGUEM marcado.
local pagina1 = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 0)
local pagina2 = ns.Data.GetRows(0, "damage", { "damage" }, 2, false, 1)

check("o primeiro colocado e o lider", pagina1[1].best ~= nil and pagina1[1].best[1] == true, true)
check("o segundo da primeira pagina nao e lider",
    pagina1[2].best ~= nil and pagina1[2].best[1] == true, false)
check("rolar nao promove ninguem",
    pagina2[1].best ~= nil and pagina2[1].best[1] == true, false)
check("nem na ultima linha",
    pagina2[2] ~= nil and pagina2[2].best ~= nil and pagina2[2].best[1] == true, false)

-- Trocar a coluna de ordenacao tambem nao pode mexer em quem lidera cada coluna.
local porDano = ns.Data.GetRows(0, "damage", { "damage", "healing" }, 3, false, 0)
local porCura = ns.Data.GetRows(0, "healing", { "damage", "healing" }, 3, false, 0)
local function lider(lista, coluna)
    for i = 1, #lista do
        if lista[i].best and lista[i].best[coluna] then return lista[i].source.name end
    end
end
check("o lider de dano nao muda com a ordenacao",
    lider(porDano, 1), lider(porCura, 1))

print("== degrade da faixa ==")
-- Regressao da 0.50.0: a faixa era pintada chapada com a cor cheia da classe
-- (`SetStatusBarColor(ns.ClassColor(...))`), e por isso saia visivelmente mais clara que a do
-- medidor nativo, que vai de ~52% a ~84% da cor ao longo do comprimento. Se alguem voltar a
-- chapar, estes checks caem.
local pintado = { gradiente = nil, chapado = nil }
local faixa = {
    GetStatusBarTexture = function()
        return {
            SetGradient = function(_, orientacao, minCor, maxCor)
                pintado.gradiente = { orientacao = orientacao, min = minCor, max = maxCor }
            end,
        }
    end,
    SetStatusBarColor = function(_, r, g, b)
        pintado.chapado = { r, g, b }
    end,
}

ns.ApplyBarColor(faixa, "MAGE")
check("degrade aplicado", pintado.gradiente ~= nil, true)
check("degrade na horizontal", pintado.gradiente.orientacao, "HORIZONTAL")
-- Mage e 0.4/0.8/0.9 no simulador; as pontas sao 52% e 84% disso.
check("ponta esquerda escurecida", string.format("%.3f", pintado.gradiente.min.r), "0.208")
check("ponta direita mais clara", string.format("%.3f", pintado.gradiente.max.r), "0.336")
check("cor de vertice neutra antes do degrade", pintado.chapado[1], 1)
check("faixa nunca recebe a cor cheia", pintado.gradiente.max.b < 0.9, true)

print("== placar: retrato ==")
-- O placar NAO le mais a sessao viva: le sempre um retrato solto. Tres produtores (corrida
-- que acabou, corrida guardada em disco, simulacao) e um caminho de desenho so. O contrato do
-- retrato e `values` indexado pela CHAVE da coluna — nao pela posicao, que nao sobrevive a uma
-- mudanca na lista de colunas entre o dia da gravacao e o dia da leitura.
local run = ns.Demo.Run()

check("corrida marcada como simulacao", run.demo, true)
check("simulacao e do tipo mplus", run.kind, "mplus")
check("cinco jogadores", #run.rows, 5)
check("valores indexados por chave", run.rows[1].values.dps, 103000)
check("nao ha valores por posicao", run.rows[1].values[1], nil)
check("a linha carrega a classe", run.rows[1].classFilename, "DEATHKNIGHT")
check("a linha carrega a funcao", run.rows[1].role, "TANK")

-- Os totais sao reconstruidos por taxa * tempo em combate: se alguem mexer num sem mexer no
-- outro, as colunas param de fechar entre si e o placar mostra numeros que se contradizem.
check("dano reconstruido do dps",
    run.rows[1].values.damage, run.rows[1].values.dps * run.combatSeconds)
check("tempo em combate menor que a corrida", run.combatSeconds < run.durationSeconds, true)

print("== placar: corridas guardadas ==")
-- "Ver o ultimo placar" so funciona se a corrida tiver sido copiada para fora da sessao no
-- momento certo: a sessao do C_DamageMeter e zerada pela proxima luta.
-- O CHALLENGE_MODE_COMPLETED do ciclo de vida (bem la em cima) ja deve ter capturado e
-- gravado: e esse o caminho que faz o botao "Ultimo Mitico+" ter o que mostrar.
check("o fim da corrida gravou sozinho", ns.Scoreboard.HasRun("mplus"), true)
-- O ENCOUNTER_END tambem disparou, mas IsInRaid() e falso no simulador: em masmorra quem
-- manda e o CHALLENGE_MODE_COMPLETED, e o caminho de raide tem que sair cedo.
check("encounter fora de raide nao grava placar de raide", ns.Scoreboard.HasRun("raid"), false)

local guardada = ns.Scoreboard.Snapshot({ kind = "mplus", title = "Teste", level = 12,
    durationSeconds = 1500, sessionType = 1 })
check("o retrato tem linhas", #guardada.rows > 0, true)
check("o retrato carimba a hora", type(guardada.recordedAt), "number")
check("o retrato guarda por chave", type(guardada.rows[1].values.dps), "number")
check("o retrato guarda TODAS as metricas, nao so as visiveis",
    guardada.rows[1].values.taken ~= nil and guardada.rows[1].values.dispels ~= nil, true)

ns.Scoreboard.SaveRun("mplus", guardada)
check("agora ha corrida de mplus", ns.Scoreboard.HasRun("mplus"), true)
check("raide continua vazia", ns.Scoreboard.HasRun("raid"), false)
check("gravou no SavedVariable proprio, fora da configuracao",
    RocketMeterRunsDB ~= nil and RocketMeterRunsDB.mplus == guardada, true)

-- Profile.Reset apaga a CONFIGURACAO. Nao pode levar as corridas junto.
ns.Profile.Reset()
check("restaurar o padrao nao apaga as corridas", ns.Scoreboard.HasRun("mplus"), true)

-- Nada no retrato pode ser secret: SavedVariables nao serializa valor opaco.
local function temSecret(t, profundidade)
    if profundidade > 6 then return false end
    for k, v in pairs(t) do
        if issecretvalue(k) or issecretvalue(v) then return true end
        if type(v) == "table" and temSecret(v, profundidade + 1) then return true end
    end
    return false
end
check("retrato nao carrega secret value", temSecret(guardada, 0), false)

print("== corpos de fonte ==")
-- A descida foi 16 -> 14 -> 13 -> 12, cada degrau pedido depois de teste in-game. O que este
-- bloco tranca nao e o numero em si, e sim que a LINHA tem corpo unico e que as telas com
-- corpo proprio (titulo, cabecalho de coluna, painel de detalhamento) NAO seguem a linha —
-- eles sao valores absolutos, e ja se perderam rodadas por alguem tratar um deles como delta.
local function spyFontString()
    local fs = {}
    function fs.SetFont(_, path, size, flags) fs.path, fs.size, fs.flags = path, size, flags end
    function fs.SetShadowOffset() end
    function fs.SetShadowColor() end
    function fs.SetAlpha() end
    function fs.GetWidth() return 40 end
    function fs.SetWidth() end
    function fs.SetText() end
    function fs.SetTextColor(_, r, g, b) fs.color = { r, g, b } end
    function fs.SetJustifyH() end
    function fs.GetJustifyH() return "LEFT" end
    return fs
end

local fs = spyFontString()
ns.ApplyFont(fs, 0)
-- A REFERENCIA E A JANELA DE CHAT DO USUARIO, e os numeros sao os que ELE configurou -- lidos
-- de `SavedVariables/Chattynator.lua`, nao inferidos de print:
--     message_font = "default"  -> Chattynator: fonts.default = "ChatFontNormal" -> ARIALN
--     message_font_size = 17
--     message_font_outline = "thin" -> "OUTLINE"
--     show_font_shadow = true
-- UM numero cravado, e so um: `ns.Skin.fontSize` e a fonte unica da verdade, e todo o resto e
-- conferido POR RELACAO a ela. Assim mudar o corpo e uma linha aqui, e nao seis.
check("corpo da linha e o que foi decidido", ns.Skin.fontSize, 16)
check("ApplyFont usa o corpo do Skin", fs.size, ns.Skin.fontSize)
check("linha usa a fonte do chat (Arial Narrow)", fs.path, ns.Skin.font)
check("a fonte e mesmo Arial Narrow", ns.Skin.font:find("ARIALN", 1, true) ~= nil, true)

-- UM CONTORNO SO PARA TUDO. A mistura anterior (celula sem contorno, nome com halo desenhado)
-- foi o que o usuario leu como "umas colunas parece ta com mais borda a fonte, outras nao".
check("linha com contorno", fs.flags, "OUTLINE")
do
    local celula = spyFontString()
    celula.classFilename = nil
    local linha = { cells = { celula }, classFilename = "MAGE" }
    ns.StyleCell(linha, 1, false, 0)
    check("celula usa o MESMO contorno da linha", celula.flags, fs.flags)
end

-- O placar NAO segue a janela: ele foi visto e aprovado em 12, e a janela subiu para 13
-- depois, a pedido. Herdar desfaria uma aprovacao que ja existe.
-- HIERARQUIA DA JANELA. Titulo, relogio e cabecalho de coluna eram tres numeros ABSOLUTOS,
-- herdados de quando a linha era 13. Cada vez que o corpo da linha mudava -- e mudou seis
-- vezes -- a relacao se desfazia sozinha: chegou ao ponto de o titulo EMPATAR com a linha,
-- quando no medidor nativo ele e menor, e e o menor que da a hierarquia.
--
-- Agora sao deltas. Estes checks travam a relacao, que e o que precisa sobreviver a proxima
-- mudanca de corpo -- nao os numeros.
check("titulo e menor que a linha", ns.Skin.titleFontSize < ns.Skin.fontSize, true)
check("relogio e menor que o titulo", ns.Skin.clockFontSize < ns.Skin.titleFontSize, true)
check("cabecalho e o menor de todos", ns.Skin.colheadFontSize < ns.Skin.clockFontSize, true)
-- E nenhum pode despencar: hierarquia nao e sumir.
check("cabecalho nao fica ilegivel", ns.Skin.colheadFontSize >= ns.Skin.fontSize - 5, true)

-- O CONTORNO E O MESMO EM TODA A JANELA. Era isto que faltava quando o usuario disse "umas
-- colunas parece ta com mais borda a fonte, outras nao": as celulas iam sem contorno, o nome
-- ia com halo desenhado, e titulo/relogio/cabecalho iam sem nada.
do
    local titulo, relogio, cabecalho = spyFontString(), spyFontString(), spyFontString()
    ns.ApplyFont(titulo,   ns.Skin.titleFontSize   - ns.Skin.fontSize, ns.Skin.fontOutline)
    ns.ApplyFont(relogio,  ns.Skin.clockFontSize   - ns.Skin.fontSize, ns.Skin.fontOutline)
    ns.ApplyFont(cabecalho, ns.Skin.colheadFontSize - ns.Skin.fontSize, ns.Skin.fontOutline)

    check("titulo com o contorno da janela", titulo.flags, fs.flags)
    check("relogio com o contorno da janela", relogio.flags, fs.flags)
    check("cabecalho com o contorno da janela", cabecalho.flags, fs.flags)
    check("e os tres na mesma familia", titulo.path, ns.Skin.font)
end

-- E o desenho de verdade tem que usar isso: sem este check, os tres poderiam continuar
-- passando "" no codigo e os checks acima passariam mesmo assim.
do
    local vistos = {}
    local arquivo = io.open("Window.lua")
    local texto = arquivo:read("*a")
    arquivo:close()
    -- Os tres pelo nome exato: `REALM_FONT_DELTA` tambem casa com "FONT_DELTA" e nao e destes.
    for _, nome in ipairs({ "TITLE_FONT_DELTA", "CLOCK_FONT_DELTA", "COLHEAD_FONT_DELTA" }) do
        for chamada in texto:gmatch("ns%.ApplyFont%(([^\n]-)%)") do
            if chamada:find(nome, 1, true) then
                vistos[#vistos + 1] = chamada
            end
        end
    end
    check("titulo, relogio e cabecalho sao desenhados por delta", #vistos, 3)
    local semContorno = 0
    for _, chamada in ipairs(vistos) do
        if chamada:find('""', 1, true) then semContorno = semContorno + 1 end
    end
    check("nenhum deles desenha sem contorno", semContorno, 0)
end

ns.ApplyScoreboardFont(fs, 0)
check("corpo do placar e proprio", fs.size, 12)
check("ns.Skin expoe o corpo do placar", ns.Skin.scoreboardFontSize, 12)

ns.ApplyPanelFont(fs, 0)
check("painel de detalhamento tem corpo proprio", fs.size, 13)

ns.ApplyFont(fs, -30)
check("piso de 6pt respeitado", fs.size, 6)

print("== ponta da faixa de titulo ==")
-- O atlas ui-damagemeters-header-bar tem 17px transparentes e depois uma rampa de alfa ate
-- ~x=70 (de 560): e o afunilamento que faz a faixa parecer uma fita, e e o que o rastreador
-- de missoes do jogo mostra. O recorte antigo comecava em 0.045 (x=25), no MEIO da rampa, e o
-- resultado era uma parede vertical de alfa 40. Se alguem voltar a recortar, isto cai.
check("faixa comeca no inicio do atlas", ns.Skin.headerCrop[1], 0)
check("faixa termina no fim do atlas", ns.Skin.headerCrop[2], 1)
check("sem recorte vertical (as bordas douradas moram nele)",
    ns.Skin.headerCrop[3] .. "," .. ns.Skin.headerCrop[4], "0,1")

print("== nome cross-realm ==")
-- Print de 05/09: as tres linhas mostravam "Magicpanda-Tic...", "Huntwave-Stor...",
-- "Szarazard-Ticho..." — nome e reino brigando pela mesma largura, reticencias comendo os dois.
-- A correcao NAO e apagar o reino (primeira tentativa, reprovada pelo usuario): e hierarquia,
-- com o reino um ponto abaixo do nome.
local nome, reino = ns.SplitName("Magicpanda-Tichondrius")
check("separa o nome", nome, "Magicpanda")
check("separa o reino, sem o hifen", reino, "Tichondrius")

nome, reino = ns.SplitName("Bolva")
check("nome sem reino volta inteiro", nome, "Bolva")
check("sem reino devolve nil", reino, nil)

-- Reino com espaco existe ("Nemesis", "Azralon", mas tambem "Ragnaros" vs "Nome-Reino Composto")
nome, reino = ns.SplitName("Thrall-Ragnaros Prime")
check("reino com espaco nao quebra", reino, "Ragnaros Prime")

check("nil nao estoura", (ns.SplitName(nil)), nil)
check("nao-string passa cru", (ns.SplitName(42)), 42)
check("delta do reino e -1", ns.REALM_FONT_DELTA, -1)

-- O reino e um ponto abaixo do nome — se o corpo da linha mudar, a diferenca acompanha.
local fsNome, fsReino = spyFontString(), spyFontString()
ns.ApplyFont(fsNome, 0)
ns.ApplyFont(fsReino, ns.REALM_FONT_DELTA)
-- O que precisa ficar travado e a RELACAO, nao o numero: o corpo da linha ja mudou quatro vezes
-- (16 -> 14 -> 13 -> 12 -> 13 -> 17) e um teste com valor cravado so obriga a reescrever o
-- teste junto. O reino e sempre um ponto abaixo do nome.
check("reino e exatamente um ponto abaixo do nome", fsNome.size - fsReino.size, 1)
check("nome usa o corpo da linha", fsNome.size, ns.Skin.fontSize)

print("== halo nao herda cor ==")
-- As copias do halo sao pretas por SetTextColor, mas um |cff...| dentro da string SOBRESCREVE
-- isso: o "(+16)" verde da coluna de pontuacao reaparecia nas duas copias, deslocado 1px, e o
-- que devia ser contorno virava fantasma verde. As copias levam o texto sem escape de cor.
local original, copias = spyFontString(), { spyFontString(), spyFontString() }
for _, echo in ipairs(copias) do
    function echo.SetText(_, t) echo.text = t end
end
function original.SetText(_, t) original.text = t end

ns.SetHaloText(original, copias, "2847 |cff40d878(+16)|r")
check("o original mantem a cor", original.text, "2847 |cff40d878(+16)|r")
check("a copia perde o escape de cor", copias[1].text, "2847 (+16)")
check("as duas copias iguais", copias[2].text, copias[1].text)

ns.SetHaloText(original, copias, "sem cor nenhuma")
check("texto sem escape passa igual", copias[1].text, "sem cor nenhuma")
ns.SetHaloText(original, nil, "halo ausente nao estoura")
check("halo nil e aceito", original.text, "halo ausente nao estoura")

print("== placar: nomes de atlas ==")
-- SetAtlas com nome errado falha em SILENCIO. Dois nomes aqui sao armadilha conhecida:
-- a Blizzard escreve "Fillagree" com dois L, e "Filigree" (a grafia correta do ingles) some
-- sem avisar. Este teste existe para ninguem "corrigir" a grafia.
local sawFillagree = 0
for _, name in ipairs(ns.SCOREBOARD_ATLASES) do
    if name:match("Filigree") then
        print("  ERRO  grafia errada no atlas: " .. name .. " (a Blizzard usa Fillagree)")
        os.exit(1)
    end
    if name:match("Fillagree") then sawFillagree = sawFillagree + 1 end
end
check("as tres filigranas do BossBanner na lista", sawFillagree, 3)
check("estrela do nivel na lista",
    (function()
        for _, n in ipairs(ns.SCOREBOARD_ATLASES) do
            if n == "ChallengeMode-SpikeyStar" then return true end
        end
        return false
    end)(), true)

print("== linha do tempo da corrida ==")
-- Sem combat log no Midnight, a linha do tempo so existe se for gravada durante a corrida.
ns.Run.Start()
check("comeca com a semente de fora de combate", #ns.Run.GetCombatTimeline(), 1)

AdvanceClock(30) ; ns.Run.OnCombatStart()
AdvanceClock(60) ; ns.Run.OnCombatEnd()
check("dois toggles gravados", #ns.Run.GetCombatTimeline(), 3)
check("entrada de combate aos 30s", ns.Run.GetCombatTimeline()[2][1], 30)
check("saida de combate aos 90s", ns.Run.GetCombatTimeline()[3][1], 90)

AdvanceClock(10) ; ns.Run.OnEncounterEnd("Chefe de Teste", 1)
check("boss gravado", #ns.Run.GetBosses(), 1)
check("boss no instante certo", ns.Run.GetBosses()[1][1], 100)
ns.Run.OnEncounterEnd("Wipe", 0)
check("wipe nao vira marcador de boss", #ns.Run.GetBosses(), 1)

-- O stub de GetDeathCount devolve 3: tres mortes acumuladas viram tres marcadores.
AdvanceClock(5) ; ns.Run.OnDeathCountUpdated()
check("mortes gravadas pela diferenca do contador", #ns.Run.GetDeaths(), 3)
ns.Run.OnDeathCountUpdated()
check("contador que nao subiu grava uma so", #ns.Run.GetDeaths(), 4)

-- Fora de corrida o modulo e inerte: sem isso ele gravaria em toda luta do jogo.
local before = #ns.Run.GetCombatTimeline()
ns.Run.Stop()
ns.Run.OnCombatStart()
ns.Run.OnEncounterEnd("Chefe fora da corrida", 1)
check("fora de corrida nao grava", #ns.Run.GetCombatTimeline(), before)
check("boss fora da corrida nao entra", #ns.Run.GetBosses(), 1)

print("== localizacao: rotulos que vem do jogo ==")
-- `FROM_GAME` troca nossos rotulos pelas palavras que o CLIENTE ja traduziu, o que vale para os
-- ~12 idiomas de uma vez. O modo de falha e silencioso e grave: global que nao existe e `nil`,
-- e `nil` no lugar de um rotulo faz o texto SUMIR da tela.
--
-- Roda em namespace proprio, carregando so o enUS.lua. Motivo: num cliente pt-BR o ptBR.lua
-- sobrescreve TODAS as 25 chaves, entao pelo `L` de verdade este caminho e invisivel — e teste
-- que nao consegue ver o que testa nao testa nada.
do
    local saved, touched = {}, {}
    local function setglobal(name, value)
        if not touched[name] then
            saved[name], touched[name] = _G[name], true
        end
        _G[name] = value
    end

    -- Os quatro casos que as guardas precisam separar:
    setglobal("DAMAGE_METER_TYPE_DEATHS", "Todesfaelle")   -- 1. global limpa
    setglobal("DAMAGE_METER_TYPE_DISPELS", nil)            -- 2. nao existe neste cliente
    setglobal("DAMAGE_METER_CATEGORY_DAMAGE", "%d. %s")    -- 3. e modelo de frase, nao rotulo
    setglobal("DAMAGE_METER_CATEGORY_HEALING", "")         -- 4. existe mas esta vazia
    -- Esta e limpa DE PROPOSITO: e a isca do teste de "conferir nao escreve" la embaixo.
    -- Sem uma global valida ali, a sabotagem nao teria o que sobrescrever e o teste
    -- passaria em cima do bug.
    setglobal("DAMAGE_METER_TYPE_ABSORBS", "Absorption-DE")

    local probe = {}
    assert(loadfile("Locales/enUS.lua"))(ADDON, probe)
    local PL = probe.L

    check("global limpa vira o rotulo", PL["Player deaths"], "Todesfaelle")
    check("global ausente cai no ingles, nao em nil", PL["Dispels"], "Dispels")
    check("global com marcador de formato e recusada", PL["Damage"], "Damage")
    check("global vazia e recusada", PL["Healing"], "Healing")

    -- O relatorio do `/rm i18n` precisa dizer exatamente qual global nao serviu e por que: e
    -- ele que transforma "o rotulo esta estranho" em dado, sem rodada de teste in-game.
    local why = {}
    for _, row in ipairs(probe.CheckGameStrings()) do
        why[row.tag] = row.why or false
    end
    check("ausente entra no relatorio", why["DAMAGE_METER_TYPE_DISPELS"], "ausente")
    check("com formato entra no relatorio", why["DAMAGE_METER_CATEGORY_DAMAGE"], "modelo de frase")
    check("vazia entra no relatorio", why["DAMAGE_METER_CATEGORY_HEALING"], "vazia")
    check("limpa NAO entra no relatorio", why["DAMAGE_METER_TYPE_DEATHS"], false)

    -- O relatorio nao pode ESCREVER. `/rm i18n` roda muito depois da carga, e reaplicar ali
    -- apagaria o que o arquivo de idioma sobrescreveu: num cliente pt-BR "Absorcoes" viraria
    -- "Absorve" ate o proximo /reload. Aqui: o ptBR ja rodou sobre o L de verdade, entao
    -- chamar o relatorio nao pode mexer nele.
    local antes = ns.L["Absorbs"]
    ns.CheckGameStrings()
    check("conferir NAO reaplica por cima da traducao", ns.L["Absorbs"], antes)

    -- Chave de FROM_GAME que o codigo nao usa e peso morto que ninguem descobre sozinho.
    local usedKeys = {}
    for _, file in ipairs(files) do
        local fh = io.open(file)
        for key in fh:read("*a"):gmatch('L%[%s*"([^"]*)"%s*%]') do
            usedKeys[key] = true
        end
        fh:close()
    end
    local orphan = false
    for key in pairs(probe.FROM_GAME) do
        if not usedKeys[key] then
            orphan = key
        end
    end
    check("nenhuma chave de FROM_GAME esta morta", orphan, false)

    -- REGRESSAO 0.53.0: `DAMAGE_METER_TYPE_DPS` e `_HPS` chegaram a entrar em FROM_GAME porque
    -- em enUS e ptBR sao a sigla "DPS"/"CPS" e pareciam perfeitas para o cabecalho de coluna.
    -- Nos outros nove idiomas nao sao sigla: deDE da "Schadensklassen" (15 caracteres, e quer
    -- dizer *classes de dano* -- o tradutor leu DPS como FUNCAO), ruRU da "Бойцы"
    -- (*combatentes*), esMX da "Sanacion por segundo" (20). O cabecalho tem 58px.
    check("DPS nao volta para FROM_GAME", probe.FROM_GAME["DPS"] or false, false)
    check("HPS nao volta para FROM_GAME", probe.FROM_GAME["HPS"] or false, false)

    for name in pairs(touched) do
        _G[name] = saved[name]
    end
end

print("== cadeado: a forma muda, nao so a cor ==")
-- Ate a 0.54.0 os dois estados usavam a MESMA textura e so trocavam o tom. Num glifo de 14px
-- isso nao se le -- o usuario disse que nao conseguia perceber. E a licao ja estava registrada
-- na saga do realce de lider: cor sozinha ficou fraca.
do
    local btn = ns.Window.__frame and ns.Window.__frame.lockButton
    check("o botao de cadeado existe", btn ~= nil, true)

    if btn then
        ns.db.locked = false
        ns.Window.ApplyLock()
        local destravado = btn:GetNormalTexture().__atlas

        ns.db.locked = true
        ns.Window.ApplyLock()
        local travado = btn:GetNormalTexture().__atlas

        check("os dois estados nao usam a mesma arte", destravado ~= travado, true)
        check("destravado usa o glifo de mover", destravado, "common-icon-move")
        check("travado nao usa o glifo de mover", travado ~= "common-icon-move", true)
    end
end

print("== cadeado: atlas ausente nao deixa o botao vazio ==")
-- `SetAtlas` com nome invalido falha em SILENCIO. Se o cliente nao tiver o atlas, o botao tem
-- que continuar mostrando o cadeado de sempre -- nunca sumir.
do
    local btn = ns.Window.__frame and ns.Window.__frame.lockButton
    local real = C_Texture.GetAtlasInfo
    C_Texture.GetAtlasInfo = function() return nil end

    ns.db.locked = false
    ns.Window.ApplyLock()
    check("sem o atlas, sobra a textura do cadeado",
        btn:GetNormalTexture().__texture, "Interface\\PetBattles\\PetBattle-LockIcon")

    C_Texture.GetAtlasInfo = real
    ns.db.locked = false
    ns.Window.ApplyLock()
end

print("== redimensionar nao pode cortar a linha de um jogador ==")
-- Pedido do usuario: "criar um minimo aceitavel para caber as informacoes de acordo com as
-- colunas e as linhas, para nao cortar a linha de um jogador".
do
    local altura = ns.Window.__WindowHeight
    local cabem = ns.Window.__RowsThatFit
    check("os dois auxiliares estao expostos", altura ~= nil and cabem ~= nil, true)

    if altura and cabem then
        -- Meia linha a mais NAO pode virar uma linha a mais.
        for n = 1, 12 do
            local exata = altura(n)
            if cabem(exata) ~= n then
                check("altura exata de " .. n .. " linha(s) devolve " .. n, cabem(exata), n)
            end
            -- sobra de meia linha: continua sendo n, nunca n+1
            local sobrando = exata + math.floor(ns.Window.__RowStep() / 2)
            if cabem(sobrando) ~= n then
                check("meia linha sobrando nao promove (" .. n .. ")", cabem(sobrando), n)
            end
        end
        check("varredura de 1 a 12 linhas sem corte", true, true)

        -- Faltando um pixel para a ultima linha: tem que devolver n-1, nao n.
        check("faltando 1px, a ultima linha nao entra", cabem(altura(6) - 1), 5)

        -- Piso: nunca abaixo de uma linha, por menor que seja a altura.
        check("altura absurda nao vai a zero linhas", cabem(10), 1)
    end
end

print("== realce do lider: clarear NAO pode dessaturar ==")
-- Relato: "a cor que da o realce dos melhores precisa ta mais escuro, a do DK parece ate rosa".
-- Estava certo, e a causa era a formula: misturar com branco (`r + (1-r)*k`) clareia mas
-- DESSATURA, e vermelho escuro dessaturado e literalmente rosa.
--
-- Medido nas cores de classe do 12.x:
--   Cavaleiro da Morte  RGB(196,31,59)  satur 0.84
--   com a mistura       RGB(216,105,124) satur 0.51   <- o rosa
--   multiplicando       RGB(255,39,76)   satur 0.84   <- vermelho vivo, e MAIS ESCURO
do
    local salvo = RAID_CLASS_COLORS
    RAID_CLASS_COLORS = {
        DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },   -- escuro: passa pela correcao
        ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },   -- claro: tem que sair intacto
    }

    local function satur(r, g, b)
        local hi = math.max(r, g, b)
        local lo = math.min(r, g, b)
        if hi <= 0 then return 0 end
        return (hi - lo) / hi
    end

    local r, g, b = ns.LeaderColor("DEATHKNIGHT")
    local sOriginal = satur(0.77, 0.12, 0.23)
    local sRealce = satur(r, g, b)

    -- O teste central: a saturacao nao pode cair. Com a formula antiga ela caia de 0.84 p/ 0.51.
    check("realce nao dessatura (o que fazia virar rosa)", sRealce >= sOriginal - 0.02, true)

    -- E o verde/azul nao podem subir muito: e neles que o rosa aparece.
    check("canal verde nao explode", g < 0.30, true)
    check("canal azul nao explode", b < 0.40, true)

    -- "precisa ta mais escuro": a formula antiga levava a luma para 0.55.
    local luma = 0.299 * r + 0.587 * g + 0.114 * b
    check("mais escuro que o piso antigo de 0.55", luma < 0.55, true)
    check("ainda assim legivel (nao ficou no original 0.33)", luma > 0.36, true)

    -- Classe que ja passa do piso sai INTACTA: clarear quem nao precisa e ruido.
    local rr, gg, bb = ns.LeaderColor("ROGUE")
    check("classe clara sai intacta (r)", rr, 1.00)
    check("classe clara sai intacta (g)", gg, 0.96)
    check("classe clara sai intacta (b)", bb, 0.41)

    -- Nenhum canal pode passar de 1: o jogo satura e a cor viraria outra.
    check("canais dentro de 0..1", r <= 1 and g <= 1 and b <= 1, true)

    RAID_CLASS_COLORS = salvo
end

print("== comandos ==")
for _, cmd in ipairs({ "", "show", "hide", "help", "col", "columns", "preset raid", "preset",
                       "overall", "profile", "profile char", "profile account",
                       "move 2 right", "score", "score demo", "score mplus", "score raid",
                       "atlas", "atlas ChallengeMode-SpikeyStar", "i18n", "config", "reset" }) do
    local ok, err = pcall(SlashCmdList.ROCKETMETER, cmd)
    print(ok and ("  ok    /rm " .. cmd) or ("  ERRO  /rm " .. cmd .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

print("\nTudo carregou e rodou sem erro de Lua.")
