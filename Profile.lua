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

    -- Colunas salvas no formato antigo (ids de Enum) viram chaves -- e a lista sai NORMALIZADA
    -- (agrupada por familia, par total+taxa completo, total antes da taxa).
    --
    -- ⚑ AS DUAS COISAS SAO ADOTADAS SEMPRE; so a MIGRACAO DE FORMATO tem consequencia. Reagrupar
    -- nao invalida a ordenacao escolhida nem e novidade para o jogador: apagar `sortBy` e
    -- anunciar "colunas migradas" a cada login, por causa de uma reordenacao, seria jogar fora a
    -- escolha dele e mentir no chat sobre o motivo.
    local migrated, changed = ns.Data.MigrateColumns(active.columns)
    if migrated then
        active.columns = migrated
        if changed then
            active.sortBy = nil
            ns.Print(L["columns migrated to the new format."])
        end
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
    local herdouDaChaveAntiga = false
    if active.autoScoreboard ~= nil then
        active.autoScoreboardMPlus = active.autoScoreboard
        active.autoScoreboardRaid = active.autoScoreboard
        active.autoScoreboard = nil
        herdouDaChaveAntiga = true
    end

    -- ⚑ O PADRÃO DE RAIDE VIROU DESLIGADO, E PADRÃO NÃO ALCANÇA PERFIL QUE JÁ EXISTE. A chave foi
    -- gravada `true` no primeiro login de quem já usava o addon, e `Fill` só preenche chave
    -- AUSENTE — então, sem esta herança, o pedido *"o placar da raid por padrão pode deixar
    -- desabilitado"* não mudaria nada para quem pediu.
    --
    -- UMA VEZ SÓ, pela mesma razão da herança acima: marcada por chave própria, para não desligar
    -- de novo se o jogador religar a de raide depois. Repetir seria a configuração voltando
    -- sozinha — o defeito que a herança da chave antiga já evitou uma vez.
    --
    -- ⚑ E NÃO PASSA POR CIMA DE QUEM ACABOU DE HERDAR A CHAVE ANTIGA: ali houve escolha
    -- deliberada (o jogador tinha ligado ou desligado o painel), e escolha vale mais que padrão
    -- novo. `raidAutoReviewed` fica FORA de `ns.defaults` de propósito: se estivesse lá, o `Fill`
    -- a marcaria antes desta linha rodar e a herança nunca aconteceria.
    if active.raidAutoReviewed == nil then
        if not herdouDaChaveAntiga then
            active.autoScoreboardRaid = false
        end
        active.raidAutoReviewed = true
    end

    -- `fontOutline` guardava a FLAG do WoW ("OUTLINE"); agora guarda a escolha do jogador
    -- ("thin"), na mesma escala do Chattynator. Sem esta conversão o valor salvo não casa com
    -- nenhuma opção do combo e ele aparece **vazio** — que foi exatamente o que apareceu no
    -- primeiro teste da tela nova.
    local fromFlags = { OUTLINE = "thin", THICKOUTLINE = "thick", [""] = "none" }
    if fromFlags[active.fontOutline] then
        active.fontOutline = fromFlags[active.fontOutline]
    end

    -- UM texto virou TRES (corpo, titulo, cabecalho), cada um com corpo, contorno e sombra
    -- proprios. As chaves antigas eram unicas para a janela inteira; herdar cada uma nos tres
    -- papeis mantem a tela EXATAMENTE como o jogador deixou -- so que agora separavel.
    --
    -- O tamanho e a excecao: herdar o corpo unico nos tres achataria a hierarquia (titulo e
    -- cabecalho menores que a linha, que e o que o medidor nativo faz). Entao o corpo salvo vai
    -- para a linha, e os outros dois mantem a distancia que tinham -- os deltas -2 e -4.
    if not active.text then
        local size = type(active.fontSize) == "number" and active.fontSize or 16
        local outline = active.fontOutline or "thin"

        local shadow = active.fontShadow ~= false

        active.text = {
            body   = { size = size,     outline = outline, shadow = shadow },
            title  = { size = size - 2, outline = outline, shadow = shadow },
            header = { size = size - 4, outline = outline, shadow = shadow },
        }
        active.fontSize, active.fontOutline, active.fontShadow = nil, nil, nil
    end

    -- ⚑ O "MEDIUM" SALVO VIRA "THIN", e esta e a migracao que importa.
    --
    -- A opcao saiu em 08/09 (*"tira o contorno medio das opcoes, claramente tu nao conseguiu
    -- fazer ele funcionar, sempre fica igual ao fino"*). Sem esta passagem, `ns.OutlineFor` nao
    -- acharia "medium" na lista de escolhas e devolveria `""` -- o contorno sumiria sozinho no
    -- proximo login, sem ninguem pedir, e num papel so (o que estivesse em medio).
    --
    -- ⚑ E ELA FICA AQUI, FORA do `if not active.text`. A primeira versao desta migracao entrou
    -- dentro daquele bloco, que so roda quando o perfil ainda esta no formato de fonte UNICA --
    -- e quem escolheu "medium" ja passou daquele formato havia muito, por definicao. Foi o
    -- SavedVariables do proprio usuario que mostrou: `text.header.outline = "medium"`, com
    -- `active.text` existindo. A migracao teria passado ao largo exatamente de quem ela existe
    -- para atender.
    --
    -- Vira "thin", e nao "thick", pela razao que ele mesmo deu: era o fino que ele estava vendo o
    -- tempo todo. A migracao entrega o que ja estava na tela, nao outra coisa.
    if type(active.text) == "table" then
        for _, papel in pairs(active.text) do
            if type(papel) == "table" and papel.outline == "medium" then
                papel.outline = "thin"
            end
        end
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
