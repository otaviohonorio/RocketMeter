-- RocketMeter | Profile.lua
-- Onde a configuração é guardada: na conta (padrão) ou só neste personagem.
--
-- `ns.db` é um proxy estável: quem lê ou escreve nele nunca precisa saber qual dos dois
-- armazenamentos está ativo. Isso importa porque a Settings API guarda a referência da
-- tabela no momento do registro — se `ns.db` fosse trocado por outra tabela, o painel de
-- opções continuaria escrevendo na antiga.
local ADDON, ns = ...
local L = ns.L

local Profile = {}
ns.Profile = Profile

local active

local function Fill(store)
    for k, v in pairs(ns.defaults) do
        if store[k] == nil then
            store[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
end

---Padrões que só podem ser montados com o cliente carregado (dependem de Enum).
---Chamado no login e sempre que a configuração é trocada ou zerada.
function Profile.EnsureRuntimeDefaults()
    if not active then return end

    -- Colunas salvas no formato antigo (ids de Enum) viram chaves.
    local migrated, changed = ns.Data.MigrateColumns(active.columns)
    if migrated and changed then
        active.columns = migrated
        active.sortBy = nil
        ns.Print(L["columns migrated to the new format."])
    end

    if not active.columns or #active.columns == 0 then
        local preset = ns.Data.GetPresets().mplus
        active.columns = preset and CopyTable(preset.columns) or { "damage" }
    end

    if not active.sortBy or not ns.Data.GetColumn(active.sortBy) then
        active.sortBy = active.columns[1]
    end

    -- `autoScoreboard` (uma chave) virou duas: Mítico+ e raide. Quem tinha desligado o painel
    -- teria ele de volta ligado, porque as chaves novas nascem `true` — então a escolha antiga
    -- é herdada uma vez e a chave velha some, para a herança não se repetir.
    if active.autoScoreboard ~= nil then
        active.autoScoreboardMPlus = active.autoScoreboard
        active.autoScoreboardRaid = active.autoScoreboard
        active.autoScoreboard = nil
    end

    -- `fontOutline` guardava a FLAG do WoW ("OUTLINE"); agora guarda a escolha do jogador
    -- ("thin"), na mesma escala do Chattynator. Sem esta conversão o valor salvo não casa com
    -- nenhuma opção do combo e ele aparece **vazio** — que foi exatamente o que apareceu no
    -- primeiro teste da tela nova.
    local fromFlags = { OUTLINE = "thin", THICKOUTLINE = "thick", [""] = "none" }
    if fromFlags[active.fontOutline] then
        active.fontOutline = fromFlags[active.fontOutline]
    end
end

function Profile.Init()
    RocketMeterDB = RocketMeterDB or {}
    RocketMeterCharDB = RocketMeterCharDB or {}

    active = RocketMeterCharDB.usePerCharacter and RocketMeterCharDB or RocketMeterDB
    Fill(active)
end

function Profile.IsPerCharacter()
    return RocketMeterCharDB and RocketMeterCharDB.usePerCharacter == true
end

---Liga ou desliga a configuração própria deste personagem.
---Ao ligar pela primeira vez, herda o que está valendo agora — ninguém quer recomeçar do zero.
function Profile.SetPerCharacter(enabled)
    if enabled == Profile.IsPerCharacter() then return end

    if enabled then
        for k, v in pairs(active) do
            if k ~= "usePerCharacter" and RocketMeterCharDB[k] == nil then
                RocketMeterCharDB[k] = type(v) == "table" and CopyTable(v) or v
            end
        end
        RocketMeterCharDB.usePerCharacter = true
        active = RocketMeterCharDB
    else
        RocketMeterCharDB.usePerCharacter = false
        active = RocketMeterDB
    end

    Fill(active)
    Profile.EnsureRuntimeDefaults()
    ns.Print(enabled and L["settings for this character only."] or L["settings shared by the account."])

    if ns.Window then
        ns.Window.ApplyScale()
        ns.Window.Rebuild()
    end
end

---Volta esta configuração para o padrão de fábrica.
function Profile.Reset()
    for k in pairs(active) do
        if k ~= "usePerCharacter" then
            active[k] = nil
        end
    end
    Fill(active)
    Profile.EnsureRuntimeDefaults()
    if ns.Window then
        ns.Window.ApplyScale()
        ns.Window.Rebuild()
    end
end

-- O proxy. `pairs(ns.db)` não funciona de propósito: use ns.Profile.Raw() para isso.
ns.db = setmetatable({}, {
    __index = function(_, key)
        return active and active[key]
    end,
    __newindex = function(_, key, value)
        if active then active[key] = value end
    end,
})

function Profile.Raw()
    return active
end
