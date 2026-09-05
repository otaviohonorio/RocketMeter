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
    function self.CreateFontString() return widget("FontString") end
    function self.CreateTexture() return widget("Texture") end
    function self.GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
    function self.GetName() return kind .. "Stub" end
    function self.IsShown() return true end
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
    function self.GetNormalTexture() return widget("Texture") end
    function self.GetTexture() return "texture" end

    return setmetatable(self, {
        __index = function(_, key)
            return function() return widget(key) end
        end,
    })
end

local frames = {}

function CreateFrame(frameType, name, parent, template)
    local f = widget(frameType or "Frame")
    f.__name = name
    f.__template = template
    frames[#frames + 1] = f
    return f
end

--------------------------------------------------------------------------------
-- Globais que o addon usa
--------------------------------------------------------------------------------
UIParent = widget("Frame")
Minimap = widget("Frame")
GameTooltip = widget("GameTooltip")
UISpecialFrames = {}
RAID_CLASS_COLORS = { MAGE = { r = 0.4, g = 0.8, b = 0.9 } }
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.49, 0, 0.25 } }
unpack = unpack or table.unpack

function GameTooltip_Hide() end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function GetCursorPosition() return 400, 300 end
function GetNumGroupMembers() return 5 end
function IsInRaid() return false end
function GetDifficultyInfo() return "Mítico" end
function GetLocale() return "ptBR" end
function date(fmt) return "12:00:00" end
function GetTime() return 1000 end
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

C_AddOns = { GetAddOnMetadata = function() return "0.6.0" end }
C_Timer = { After = function(_, fn) fn() end }
C_ChallengeMode = {
    GetChallengeCompletionInfo = function() return { mapChallengeModeID = 2, level = 12, time = 1500000, onTime = true } end,
    GetMapUIInfo = function() return "Masmorra de Teste" end,
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
local function fakeSource(name, total)
    return {
        name = name, sourceGUID = "Player-" .. name, sourceCreatureID = 0,
        totalAmount = total, amountPerSecond = total / 120,
        classFilename = "MAGE", specIconID = 1, deathRecapID = 0,
        deathTimeSeconds = 0, classification = "player", isLocalPlayer = name == "Thalyra",
    }
end

C_DamageMeter = {
    IsDamageMeterAvailable = function() return true end,
    GetSessionDurationSeconds = function() return 134 end,
    ResetAllCombatSessions = function() end,
    GetAvailableCombatSessions = function() return { { sessionID = 1 } } end,
    GetCombatSessionFromType = function()
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
            combatSpells = {}, maxAmount = entry.totalAmount,
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
fire("PLAYER_REGEN_DISABLED")
fire("PLAYER_REGEN_ENABLED")
fire("CHALLENGE_MODE_COMPLETED")

print("== funcionalidades ==")
local function try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    print(ok and ("  ok    " .. label) or ("  ERRO  " .. label .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

try("Window.ApplyVisibility", ns.Window.ApplyVisibility)
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
try("Picker.Toggle", ns.Picker.Toggle)
try("Picker.Refresh", ns.Picker.Refresh)
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
check("hps (metrica cruzada)", first[4], 1000)
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

print("== comandos ==")
for _, cmd in ipairs({ "", "show", "hide", "help", "col", "columns", "preset raid", "preset",
                       "overall", "profile", "profile char", "profile account",
                       "move 2 right", "score", "config", "reset" }) do
    local ok, err = pcall(SlashCmdList.ROCKETMETER, cmd)
    print(ok and ("  ok    /rm " .. cmd) or ("  ERRO  /rm " .. cmd .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

print("\nTudo carregou e rodou sem erro de Lua.")
