-- RocketMeter | Demo.lua
-- Uma corrida de Mítico+ inventada, para ver o placar sem precisar rodar uma masmorra.
--
-- POR QUE ISSO EXISTE: o placar só aparece no fim de uma M+ de verdade. Testar aparência
-- assim custa 30 minutos de jogo por rodada de ajuste, e foi por isso que ele ficou meses
-- sem ninguém olhar. Com a simulação, o ciclo vira `/rm score demo` + `/reload`.
--
-- REGRA DURA: nada aqui toca a API nem os dados reais. `ns.Demo.Run()` devolve uma tabela
-- solta; quem desenha decide usá-la. Não há caminho pelo qual um número daqui entre numa
-- sessão do `C_DamageMeter` ou nos SavedVariables de corrida.
--
-- Os números não são aleatórios: saem do print que o usuário mandou do Details Mythic
-- Dungeon Scoreboard (um +14 de 27:34), com os totais reconstruídos por
-- `total = taxa * tempoEmCombate`. Assim as colunas fecham entre si — DPS bate com dano,
-- e o líder de cada coluna é quem o print mostra liderando.
local ADDON, ns = ...
local L = ns.L

local Demo = {}
ns.Demo = Demo

-- 27:07 de corrida com 18:00 em combate (66%). A proporção importa: se o tempo em combate
-- fosse o tempo de parede, os DPS reconstruídos ficariam ~1/3 menores que os do print.
local RUN_SECONDS = 1627
local COMBAT_SECONDS = 1080
local TIME_LIMIT = 1800          -- 30:00, o limite típico de uma chave
local KEY_LEVEL = 14

-- Nomes de personagem de lore, como o próprio Details faz nas barras de teste: deixa óbvio
-- que é simulação e não confunde com gente do grupo.
local MEMBERS = {
    {
        name = "Bölva", class = "DEATHKNIGHT", role = "TANK", specIconID = 135771,
        dps = 103000, hps = 99000, taken = 215e6, avoidable = 1.9e6,
        deaths = 1, interrupts = 6, dispels = 0,
        score = 2847, scoreGain = 16, ilevel = 691, isLocalPlayer = true,
    },
    {
        name = "Drakaris", class = "EVOKER", role = "HEALER", specIconID = 4622448,
        dps = 49000, hps = 150000, taken = 44e6, avoidable = 1.3e6,
        deaths = 2, interrupts = 3, dispels = 15,
        score = 2795, scoreGain = 71, ilevel = 688,
    },
    {
        name = "Kaelvorn", class = "MAGE", role = "DAMAGER", specIconID = 135810,
        dps = 299000, hps = 18000, taken = 60e6, avoidable = 134000,
        deaths = 0, interrupts = 8, dispels = 2,
        score = 2910, scoreGain = 13, ilevel = 693,
    },
    {
        name = "Sargath", class = "WARLOCK", role = "DAMAGER", specIconID = 136150,
        dps = 280000, hps = 12000, taken = 51e6, avoidable = 256000,
        deaths = 1, interrupts = 4, dispels = 0,
        score = 2862, scoreGain = 67, ilevel = 690,
    },
    {
        name = "Lilianvoss", class = "ROGUE", role = "DAMAGER", specIconID = 132320,
        dps = 268000, hps = 21000, taken = 49e6, avoidable = 767000,
        deaths = 0, interrupts = 11, dispels = 5,
        score = 2888, scoreGain = 17, ilevel = 689,
    },
}

---Monta a linha no MESMO formato que `ns.Data.GetRows` devolve, para o placar não precisar
---de dois caminhos de desenho. `values` é indexado pela POSIÇÃO da coluna, não pela chave —
---é assim que `Data.GetRows` faz (`Data.lua:449`), e divergir aqui quebraria o realce.
---@param columns table lista de descritores de coluna do placar
local function BuildRows(columns)
    local rows = {}

    for i = 1, #MEMBERS do
        local member = MEMBERS[i]
        local values = {}

        for c = 1, #columns do
            local column = columns[c]
            values[c] = Demo.Value(member, column.key)
        end

        rows[i] = {
            source = {
                name = member.name,
                classFilename = member.class,
                specIconID = member.specIconID,
                isLocalPlayer = member.isLocalPlayer == true,
                sourceGUID = "Demo-" .. i,
                totalAmount = member.dps * COMBAT_SECONDS,
                amountPerSecond = member.dps,
            },
            demo = member,
            values = values,
        }
    end

    -- O realce de líder é do próprio Data, não uma cópia: se a regra mudar lá (hoje exige
    -- valor > 0, e sai cedo com menos de duas linhas), a simulação acompanha sozinha.
    if ns.Data and ns.Data.MarkColumnLeaders then
        local keys = {}
        for c = 1, #columns do keys[c] = columns[c].key end
        pcall(ns.Data.MarkColumnLeaders, rows, keys)
    end

    return rows
end

---Valor de um membro para uma coluna do placar. Fica separado porque o placar precisa dele
---tanto para montar a linha quanto para o desempate por ordenação.
function Demo.Value(member, key)
    if key == "dps" then return member.dps end
    if key == "hps" then return member.hps end
    if key == "damage" then return member.dps * COMBAT_SECONDS end
    if key == "healing" then return member.hps * COMBAT_SECONDS end
    if key == "taken" then return member.taken end
    if key == "avoidable" then return member.avoidable end
    if key == "deaths" then return member.deaths end
    if key == "interrupts" then return member.interrupts end
    if key == "dispels" then return member.dispels end
    if key == "score" then return member.score end
    return nil
end

---Uma corrida inteira, pronta para `ns.Scoreboard.Show`.
---
---`mapID` fica **nil de propósito**: com id inventado, `C_ChallengeMode.GetMapUIInfo` devolveria
---nada e o painel cairia no fallback de qualquer jeito; com id real, a simulação passaria a
---depender de qual masmorra existe na temporada corrente. O nome entra como texto.
---@param columns table descritores de coluna do placar
function Demo.Run(columns)
    return {
        demo = true,
        title = L["Ruins of the Ember Court"],
        mapID = nil,
        level = KEY_LEVEL,
        durationSeconds = RUN_SECONDS,
        combatSeconds = COMBAT_SECONDS,
        timeLimit = TIME_LIMIT,
        onTime = true,
        upgrades = 1,                 -- +1: dentro do limite, fora dos 80%
        deaths = 4,
        timeLostToDeaths = 60,
        scoreBefore = 2831,
        scoreAfter = 2847,
        -- Afixos por id. Resolvidos por `C_ChallengeMode.GetAffixInfo` na hora de desenhar;
        -- se o cliente não conhecer o id, o painel simplesmente não mostra o ícone.
        affixes = { 10, 152, 148 },
        rows = BuildRows(columns),
        -- Linha do tempo: o mesmo contrato que a corrida real produz.
        --   bosses  = { segundos, nome }
        --   deaths  = { segundos, nome de quem morreu }
        --   combat  = { segundos, true = entrou em combate / false = saiu }
        bosses = {
            { 606, L["First boss"] },
            { 1021, L["Second boss"] },
            { 1523, L["Last boss"] },
        },
        deathMarks = {
            { 342, "Drakaris" },
            { 655, "Bölva" },
            { 1088, "Sargath" },
            { 1402, "Drakaris" },
        },
        combatTimeline = {
            -- A semente do instante zero existe na corrida real (`Run.Start`) e faltava aqui:
            -- sem ela o primeiro trecho do trilho ficava sem cor, e a simulação deixava de
            -- mostrar o painel como ele fica de verdade — que é a única coisa que ela faz.
            { 0, false },
            { 48, true }, { 190, false },
            { 262, true }, { 402, false },
            { 520, true }, { 700, false },
            { 812, true }, { 1040, false },
            { 1120, true }, { 1290, false },
            { 1380, true }, { 1600, false },
        },
    }
end

function Demo.RunSeconds()
    return RUN_SECONDS
end
