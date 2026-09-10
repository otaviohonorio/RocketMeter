-- RocketMeter | Locales/enUS.lua
-- Base da localização. Este arquivo carrega SEMPRE, em qualquer idioma de cliente.
--
-- Duas camadas, nesta ordem:
--
--   1. A CHAVE É O TEXTO EM INGLÊS. Sem tradução, a própria chave aparece na tela — então o
--      inglês é o fallback automático de todo idioma que ainda não tem arquivo aqui, sem
--      nenhuma linha de código para isso.
--
--   2. `FROM_GAME` puxa do próprio cliente os rótulos que a Blizzard já traduziu. Isso vale
--      para os ~12 idiomas de uma vez, e — o que importa mais — usa **a palavra que o jogador
--      já lê na interface do jogo**, não a nossa versão dela.
--
-- Depois deste arquivo carrega o do idioma (ptBR.lua), que sobrescreve o que quiser. A
-- precedência final é: nossa escolha explícita > palavra do jogo > chave em inglês.
local ADDON, ns = ...

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

ns.L = L

--------------------------------------------------------------------------------
-- Rótulos que o jogo já traduziu
--------------------------------------------------------------------------------
-- O medidor nativo da Blizzard tem uma global para CADA atributo que este addon mostra, e é a
-- mesma fonte de dados (`C_DamageMeter`). A tabela abaixo espelha
-- `Blizzard_DamageMeter/DamageMeterSessionWindow.lua:34-46`:
--
--     local DAMAGE_METER_TYPE_NAMES = {
--         [Enum.DamageMeterType.DamageDone] = DAMAGE_METER_TYPE_DAMAGE_DONE,
--         [Enum.DamageMeterType.Dps]        = DAMAGE_METER_TYPE_DPS,
--         ...
--
-- SÓ ENTRAM AQUI RÓTULOS LONGOS (tooltip, título, botão). Os cabeçalhos de coluna continuam
-- nossos: eles têm ~50px, e "Dano evitável recebido" não cabe onde cabe "Evitáv". A Blizzard
-- não tem forma curta desses nomes — o medidor dela mostra uma métrica por janela, nós
-- mostramos seis colunas. Onde a global JÁ é curta (DPS, HPS, Deaths), ela entra.
local FROM_GAME = {
    -- Nomes de métrica, do medidor nativo
    ["Total damage"]        = "DAMAGE_METER_TYPE_DAMAGE_DONE",
    ["Total healing"]       = "DAMAGE_METER_TYPE_HEALING_DONE",
    ["Absorbs"]             = "DAMAGE_METER_TYPE_ABSORBS",
    ["Damage taken"]        = "DAMAGE_METER_TYPE_DAMAGE_TAKEN",
    ["Avoidable damage"]    = "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN",
    ["Interrupts"]          = "DAMAGE_METER_TYPE_INTERRUPTS",
    ["Dispels"]             = "DAMAGE_METER_TYPE_DISPELS",
    ["Player deaths"]       = "DAMAGE_METER_TYPE_DEATHS",
    ["Damage on enemies"]   = "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN",
    ["Damage per second"]   = "DAMAGE_PER_SECOND",

    -- Cabeçalho curto. Só entra global que seja curta nos ONZE idiomas — ver a nota sobre
    -- DPS/HPS logo abaixo, que é o motivo de só sobrar esta.
    ["Deaths"]              = "DAMAGE_METER_TYPE_DEATHS",   -- máx. 7 (esES)

    -- Seções do detalhamento por magia
    ["Damage"]              = "DAMAGE_METER_CATEGORY_DAMAGE",
    ["Healing"]             = "DAMAGE_METER_CATEGORY_HEALING",

    -- Sessão, conteúdo e controles
    ["Overall"]             = "DAMAGE_METER_OVERALL_SESSION",
    ["Clear the data"]      = "DAMAGE_METER_RESET_ALL_SESSIONS",
    ["Lock position"]       = "DAMAGE_METER_LOCK_WINDOW",
    ["Configure"]           = "SETTINGS",
    ["in combat"]           = "HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY_IN_COMBAT",
    ["Mythic+"]             = "PLAYER_DIFFICULTY_MYTHIC_PLUS",
    ["Raid"]                = "RAID",
    ["Dungeon"]             = "LFG_TYPE_DUNGEON",
    ["defeated"]            = "BOSS_DEAD",
    ["version"]             = "GAME_VERSION_LABEL",
}

-- O que NÃO entrou, e por quê — para ninguém "consertar" isso depois sem saber:
--
--   "Current fight"  DAMAGE_METER_CURRENT_SESSION é "Segmento atual". "Combate atual" é mais
--                    claro e foi aprovado in-game em várias rodadas de ajuste visual.
--   "Control"        DAMAGE_METER_CATEGORY_ACTIONS é "Ações", e o grupo da Blizzard inclui
--                    mortes; o nosso é interromper + dissipar. Palavra diferente, conjunto
--                    diferente — trocar mudaria o que o painel significa.
--   "Score"          PROVING_GROUNDS_SCORE traz dois-pontos embutido — "Score:" em inglês e
--                    "Pontuação:" em português. Rótulo com pontuação dentro quebra o layout.
--   "Absorb"         ABSORB é "Absorver", 8 caracteres, no cabeçalho de ~58px. Não cabe.
--   "Enemies"        SPELL_TARGET_TYPE13_DESC é "inimigos", minúsculo e de outro domínio.
--   "Heal"           só existe em WOW_LABS_HEAL_TOOLTIP, de um modo de jogo que pode sumir.
--
--   "DPS" e "HPS"    ESTE É O CASO QUE MAIS ENSINA, e eu já tinha errado aqui. Em enUS e ptBR
--                    `DAMAGE_METER_TYPE_DPS` é a sigla "DPS", então a global parece perfeita
--                    para o cabeçalho. Nos outros nove idiomas ela NÃO é sigla:
--
--                        deDE  "Schadensklassen"       15 caracteres — e quer dizer
--                                                      *classes de dano*: o tradutor leu DPS
--                                                      como FUNÇÃO, não como métrica
--                        ruRU  "Бойцы"                 *combatentes* — mesmo erro
--                        koKR  "초당 피해량"             frase, não sigla
--
--                    `DAMAGE_METER_TYPE_HPS` idem: esMX "Sanación por segundo" (20),
--                    ruRU "Ед. здоровья в сек." (19). O cabeçalho tem 58px.
--
--                    A lição não é sobre estas duas globais: é que **conferir enUS e ptBR não
--                    testa uma promessa sobre onze idiomas**. Toda entrada desta tabela foi
--                    medida nos onze, e as larguras anotadas ao lado são o máximo encontrado.
--
--   "version"        `VERSION` existe e o texto está certo, mas tem `Flags=2` no DB2 — sem o
--                    bit que TODAS as outras globais confirmadas aqui carregam — e zero
--                    leituras na fonte 12.1.0 e nos 116 addons instalados. Dois sinais
--                    independentes de que ela não vira global de Lua. Trocada por
--                    `GAME_VERSION_LABEL` (Flags=1), mesmo texto nos onze idiomas.

ns.FROM_GAME = FROM_GAME

---Esta global serve como rótulo?
---
---Três guardas, cada uma contra uma falha diferente:
---
---  * **não é string** → a global não existe neste cliente. Esta é a guarda que **não pode**
---    ser simplificada: sem ela, `text:find` recebe `nil` e **levanta erro na carga do
---    arquivo**. Como é aqui que `ns.L` nasce, o addon inteiro morre junto — não é um rótulo
---    em branco, é a tela toda. Travado por teste (sabotagem verificada: *"attempt to index
---    local 'text' (a nil value)"*).
---  * **string vazia** → existe mas não tem texto; viraria um rótulo em branco.
---  * **tem `%s`/`%d`** → é modelo de frase, não rótulo (`DAMAGE_METER_SOURCE_NAME` = `"%d. %s"`),
---    e apareceria cru na tela.
---
---Nos três casos a chave fica em paz e o inglês continua valendo. Vale notar que
---`rawset(L, key, nil)` seria inofensivo por si — apagar a chave a devolve ao `__index`; o
---perigo real é a indexação do `nil`, não o buraco na tabela.
---@return string|nil texto, string|nil motivo da recusa
local function Usable(tag)
    local text = _G[tag]
    if type(text) ~= "string" then return nil, "ausente" end
    if text == "" then return nil, "vazia" end
    if text:find("%%") then return nil, "modelo de frase" end
    return text
end

---Escreve os rótulos do jogo em `L`. Roda **uma vez**, na carga deste arquivo, antes do
---arquivo de idioma — que sobrescreve o que quiser depois.
function ns.ApplyGameStrings()
    for key, tag in pairs(FROM_GAME) do
        local text = Usable(tag)
        if text then
            rawset(L, key, text)
        end
    end
end

---Relatório para o `/rm i18n`. **Só lê.**
---
---Não pode aplicar nada: este comando roda muito depois da carga, e reaplicar aqui apagaria
---as traduções que o arquivo de idioma escreveu por cima — num cliente pt-BR, "Absorções"
---viraria "Absorve" até o próximo `/reload`, sem ninguém entender por quê.
---@return table lista de { key, tag, text, why }, ordenada pela global
function ns.CheckGameStrings()
    local report = {}
    for key, tag in pairs(FROM_GAME) do
        local text, why = Usable(tag)
        report[#report + 1] = { key = key, tag = tag, text = text, why = why }
    end
    -- ⚑ O DESEMPATE PELA CHAVE NÃO É ENFEITE. `DAMAGE_METER_TYPE_DEATHS` está em `FROM_GAME`
    -- DUAS vezes — uma para "Player deaths" e outra para "Deaths" —, e um comparador que devolve
    -- `false` para os dois deixa a ordem deles indefinida: `table.sort` não é estável.
    --
    -- Isso parecia inofensivo (as duas linhas dizem a mesma coisa), e não era: a saída do `/rm
    -- i18n` mudava de ordem entre execuções, o harness a imprime, e o `sabotar.py` casa a saída
    -- por TEXTO para decidir qual check reprovou primeiro. **Uma suíte de sabotagem que muda de
    -- resultado sem o código mudar não distingue "o teste não pega" de "deu azar agora"** — e foi
    -- exatamente esse sintoma que apareceu em 10/09/2026, com sabotagens diferentes falhando a
    -- cada rodada.
    table.sort(report, function(a, b)
        if a.tag ~= b.tag then return a.tag < b.tag end
        return a.key < b.key
    end)
    return report
end

ns.ApplyGameStrings()
