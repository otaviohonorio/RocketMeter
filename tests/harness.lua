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
function GetTime() return 1000 end
function SecondsToClock(s) return string.format("%02d:%02d", s / 60, s % 60) end
function AbbreviateNumbers(v) return tostring(math.floor(v)) end
function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end
function issecretvalue() return false end
tinsert, tremove, wipe = table.insert, table.remove, function(t) for k in pairs(t) do t[k] = nil end end
format = string.format

C_AddOns = { GetAddOnMetadata = function() return "0.6.0" end }
C_Timer = { After = function(_, fn) fn() end }
C_ChallengeMode = {
    GetChallengeCompletionInfo = function() return { mapChallengeModeID = 2, level = 12, time = 1500000, onTime = true } end,
    GetMapUIInfo = function() return "Masmorra de Teste" end,
}

Enum = {
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
        -- Valores distintos por metrica: se o cruzamento estiver errado, o teste abaixo pega.
        local byAttribute = {
            [Enum.DamageMeterType.HealingDone] = { totalAmount = 600000, amountPerSecond = 5000 },
            [Enum.DamageMeterType.Interrupts] = { totalAmount = 3, amountPerSecond = 0 },
            [Enum.DamageMeterType.Deaths] = { totalAmount = 1, amountPerSecond = 0 },
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
try("Window.ToggleColumn", ns.Window.ToggleColumn, "absorb")
try("Window.MoveColumn", ns.Window.MoveColumn, 2, -1)
try("Window.ApplyPreset(raid)", ns.Window.ApplyPreset, "raid")
try("Picker.Toggle", ns.Picker.Toggle)
try("Picker.Refresh", ns.Picker.Refresh)
try("Minimap.ApplyVisibility", ns.Minimap.ApplyVisibility)
try("Profile.SetPerCharacter(true)", ns.Profile.SetPerCharacter, true)
try("Profile.SetPerCharacter(false)", ns.Profile.SetPerCharacter, false)
try("Profile.Reset", ns.Profile.Reset)
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
check("cura total (metrica cruzada)", first[3], 600000)
check("hps (metrica cruzada)", first[4], 5000)
check("interrupcoes (metrica cruzada)", first[5], 3)
check("percentual do dano", math.floor(first[6] + 0.5), math.floor(1200000 / 2920000 * 100 + 0.5))

-- ordem invertida: a ultima linha vira a primeira, sem comparar nada
local asc = ns.Data.GetRows(0, "damage", cols, 5, true)
check("ordem crescente comeca pelo menor", asc[1].source.totalAmount, 740000)

-- migracao das colunas salvas no formato antigo (ids de Enum)
local migrated = ns.Data.MigrateColumns({ Enum.DamageMeterType.DamageDone, Enum.DamageMeterType.Hps })
check("migracao converte id em chave", migrated[1], "damage")
check("migracao converte Hps em hps", migrated[2], "hps")

print("== comandos ==")
for _, cmd in ipairs({ "", "show", "hide", "help", "col", "columns", "preset raid", "preset",
                       "overall", "profile", "profile char", "profile account",
                       "move 2 right", "score", "config", "reset" }) do
    local ok, err = pcall(SlashCmdList.ROCKETMETER, cmd)
    print(ok and ("  ok    /rm " .. cmd) or ("  ERRO  /rm " .. cmd .. ": " .. tostring(err)))
    if not ok then os.exit(1) end
end

print("\nTudo carregou e rodou sem erro de Lua.")
