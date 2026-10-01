-- RocketMeter | Scoreboard.lua
-- O resumo de fim de Mítico+ e de encontro de raide.
--
-- Aqui a densidade é outra: a corrida acabou, ninguém está lutando, e a tela pode respirar.
-- Linha alta com ícone de especialização e barra na cor da classe, cabeçalho com a estrela do
-- nível da chave, rodapé com a linha do tempo da corrida. Fecha só no X — ESC não fecha.
--
-- DE ONDE VEM A APARÊNCIA. A referência é o painel oficial de fim de M+ da Blizzard, e a arte
-- dele foi levantada lendo o `Details_MythicPlus` instalado em disco (que copia as mesmas
-- texturas: `--use the same textures from the original end of dungeon panel`). Três decisões
-- saíram dessa leitura, contra o que eu teria feito de palpite:
--
--   1. **Sem moldura dourada.** Nine-slice (`DialogBorderTemplate` e parentes) é bonito numa
--      caixa de diálogo estreita; num painel largo joga todo o peso visual para a periferia e
--      briga com a cor de classe das linhas. O painel de referência usa canto escuro e nenhuma
--      borda, e é por isso que lê como Blizzard moderno em vez de Blizzard 2008.
--   2. **`Fillagree` com dois L.** É erro de digitação da própria Blizzard no nome do atlas.
--      `BossBanner-LeftFiligree` falha em silêncio — nada aparece e nada avisa.
--   3. **Não existe atlas de "+1/+2/+3".** Procurado em toda a árvore de addons instalados; o
--      painel oficial resolve com texto, e é o que fazemos.
--
-- SILÊNCIO É O MODO DE FALHA. `SetAtlas` com nome inexistente não levanta erro: a textura
-- simplesmente não desenha. Todo atlas daqui passa por `Atlas()`, que consulta
-- `C_Texture.GetAtlasInfo` ANTES e devolve false para quem quiser um plano B. `/rm atlas`
-- imprime a lista inteira resolvida, para a dúvida morrer com um dado em vez de uma teoria.
local ADDON, ns = ...
local L = ns.L

local Scoreboard = {}
ns.Scoreboard = Scoreboard

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------
-- TODO NÚMERO DESTE BLOCO FOI MEDIDO NO **Details! Mythic+ Scoreboard**, não estimado.
--
-- Pedido do usuário: *"pode copiar e deixa exatamente igual ao do Details! mythic scoreboard?
-- É para copiar tudo mesmo, deixar literalmente tudo igual"*. Então a fonte da verdade deixa de
-- ser o gosto e passa a ser o arquivo dele, instalado em
-- `Interface/AddOns/Details_MythicPlus/`. A referência de cada linha vai no comentário, porque
-- número copiado sem procedência é número que a próxima rodada "arruma" no olho.
--
-- O que **não** foi copiado, e por quê, está no cabeçalho de `ALL_COLUMNS`.
local ROW_HEIGHT = 46            -- `lineHeight`                 (scoreboard.lua:130)
local ROW_SPACING = 1            -- `-((index-1)*(lineHeight+1))` (:821)
local LINE_INSET = 2             -- `lineOffset`                 (:129)
local SIDE = 5                   -- `mainFramePaddingHorizontal` (:119)
local HEADER_HEIGHT = 65         -- `headerY = -65`              (:125)
-- (!) TWO LINES (30/09): the Details header is one line of 20; ours carries the family's name
-- on the first line and the part of each column on the second ("Damage" over "per s" and
-- "total"), so 2 x 16. The user, on "Interr - Missed - CC" in one line: *"só errou na coluna
-- é confuso (...) só se tu montar uma coluna com dois valores um titulo e sub titulo"*.
local COLHEAD_HEIGHT = 32
local COLHEAD_LINE = 16
local COL_PADDING = 2            -- `padding`                    (:733)
-- O RODAPÉ FECHA A CONTA DOS 452 do Details (`mainFrameHeight`, scoreboard.lua:117):
--   65 (cabeçalho) + 20 (colunas) + 5 × 47 (linhas) + 132 = 452.
-- Ele é grande porque o eixo de tempo do Details não vem colado nas linhas: as linhas terminam
-- em −321 e o eixo só começa em −385 (`activityFrameY`, :136). Aqueles 64px de respiro são o
-- que separa a tabela do gráfico — sem eles o eixo lê como mais uma linha da tabela.
local FOOTER_HEIGHT = 132
local MAX_ROWS = 20

-- Retrato, ícone de função e nível de item dentro da coluna de retrato (scoreboard_layout.lua:291-315)
local PORTRAIT_INSET = 2         -- `lineHeight-2`
local ROLE_SIZE = 18             -- `RoleIcon:SetSize(18, 18)`
local ROLE_X, ROLE_Y = -9, -2    -- ancorado em `bottomright` do retrato
local ILVL_FONT = 11
local ILVL_BG_HEIGHT = 14
local ILVL_BG_INSET = 7
local SPEC_ICON = 20             -- `specIcon:SetSize(20, 20)`   (:363)
local KEYSTONE_ICON = 45         -- `keystoneTextureSize`  (scoreboard_layout.lua:13)
local KEYSTONE_FONT = 12
local LOOT_ICON = 32             -- `frame.LootIcon:SetSize(32, 32)` (:695)

-- Fundo alternado das linhas (:131-133). Branco a 5% e a 10% SOBRE o fundo do painel — não é
-- preto sobre preto: a diferença entre as duas linhas é clara mesmo com a arte da masmorra
-- aparecendo por trás, que é o caso real.
local ROW_TINT_ODD = { 1, 1, 1, 0.10 }
local ROW_TINT_EVEN = { 1, 1, 1, 0.05 }

-- Cabeçalho de coluna (DF/header.lua:742-747): célula com fundo próprio, texto branco a 10.
local COLHEAD_TINT = { 0, 0, 0, 0.5 }
local COLHEAD_TINT_SORTED = { 0.3, 0.3, 0.3, 0.5 }

local TITLE_Y = -12              -- `dungeonNameY`   (scoreboard.lua:123)

-- ⚑ OS CORPOS SUBIRAM 2, a pedido (*"aumente só um pouco a fonte"*, 10/09/2026). E subiram TODOS
-- juntos, de propósito: a hierarquia do cabeçalho é a razão entre eles (20/16/11 ≈ 1,8 e 1,45), e
-- crescer um só a achataria. Com +2 vira 22/18/13, e as razões ficam 1,22 e 1,38 — mais próximas
-- entre si, o que é o efeito de aumentar tudo; o que não pode é inverter, e não inverte.
--
-- O tempo é o que mais ganha em presença relativa, e isso é intencional: ele deixou de ser a
-- segunda linha do título e virou o bloco da direita, onde precisa se sustentar sozinho.
local TITLE_SIZE = 22            -- era 20 (`scoreboard.lua:355`)
local CLOCK_SIZE = 18            -- era 16 (:361)
local IDLE_SIZE = 13             -- era 11 (:453)

-- O bloco da direita: o tempo começa na mesma altura do título, e o resultado 2px abaixo dele.
-- Os 2 são o mesmo `GAP_LABEL` que cola rótulo em controle na tela de configuração — aqui o
-- resultado é legenda do tempo, e legenda mora colada no que descreve.
local CLOCK_Y = -14
local RESULT_GAP = -2
local RESULT_SIZE = 13           -- legenda do tempo: mesmo corpo da faixa de contexto

-- ⚑ QUANTO O BLOCO DA DIREITA ENTRA PARA DENTRO. Na 0.85.0 ele nasceu em 29 (a margem do painel
-- mais um respiro) e ficou colado na borda — *"o tempo à direita ficou muito à direita... deixando
-- ele à direita, mas não tão à direita"* (10/09/2026).
--
-- 65 não é um número escolhido no olho: é a largura de uma coluna de contagem (**60**) mais a
-- margem lateral do painel (**5**). Com ele o bloco fica **sobre a última coluna** em vez de
-- pendurado no canto — quer dizer, alinhado a uma borda que já existe na tela, e não a uma
-- distância inventada. Se a largura das colunas mudar, este número tem um lugar de onde vir.
local CLOCK_RIGHT_INSET = 65

-- Estrela do nível da chave: 100x100 centrada em ("center", frame, "top", 0, 27). Os números
-- foram medidos pelo autor do Details contra o painel oficial — copiados, não recalibrados.
local STAR_SIZE = 100
local STAR_OFFSET_Y = 27
local FILIGREE_SIDE_W, FILIGREE_SIDE_H = 72, 43
local FILIGREE_SIDE_X = 50
local FILIGREE_BOTTOM_W, FILIGREE_BOTTOM_H = 66, 28
local FILIGREE_BOTTOM_Y = -19

-- Linha do tempo: trilho de 4px, marcadores de boss acima, mortes abaixo, eixo por último.
local RAIL_HEIGHT = 4
local BOSS_ICON = 18
local DEATH_ICON = 11
local CHEST_ICON = 26            -- nativo 257x226 escalado; aqui só a altura importa
-- A FAIXA DE CLASSE NO RODAPÉ DA LINHA SAIU (era `BAR_STRIP_HEIGHT`/`BAR_ALPHA`). Ela era nossa
-- e não existe no Details, e o pedido foi copiar. A escala de dano que ela desenhava também não
-- existe lá: num placar de fim de corrida a comparação se faz lendo a coluna, não medindo
-- barras — e a identidade da classe continua em três lugares na mesma linha (retrato, ícone de
-- especialização e cor do nome).

-- Todo atlas usado pelo painel, num lugar só, para `/rm atlas` conferir a lista inteira de uma
-- vez em vez de descobrir um nome quebrado por rodada de teste.
ns.SCOREBOARD_ATLASES = {
    "ChallengeMode-SpikeyStar",
    "BossBanner-LeftFillagree",
    "BossBanner-RightFillagree",
    "BossBanner-BottomFillagree",
    "BossBanner-SkullCircle",
    "gficon-chest-evergreen-greatvault-collect",
    "gficon-chest-evergreen-greatvault-complete",
    "worldquest-icon-boss",
    "roleicon-tiny-tank",
    "roleicon-tiny-healer",
    "roleicon-tiny-dps",
    "ui-damagemeters-header-bar",
    "common-icon-redx",
    -- Cadeado destravado do cabecalho da janela (0.55.0). Entra aqui porque `/rm atlas` e o
    -- unico jeito de saber se ele existe: `SetAtlas` com nome invalido falha em silencio.
    "common-icon-move",
    -- O placar copiado do Details! Mythic+ Scoreboard (0.66.0). Todos conferidos na fonte do
    -- 12.1.0 antes de entrar; ficam aqui porque `/rm atlas` e o unico jeito de descobrir que um
    -- deles deixou de existir num patch -- `SetAtlas` com nome morto nao avisa nada.
    "auctionhouse-icon-clock",                    -- tempo fora de combate
    "bags-icon-equipment",                        -- nivel de item medio
    "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",     -- TextureUtil.lua:187-189
    "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
    "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
    "loottoast-itemborder-white",                 -- ColorConstants.lua:63-70
    "loottoast-itemborder-green",
    "loottoast-itemborder-blue",
    "loottoast-itemborder-purple",
    "loottoast-itemborder-orange",
}

--------------------------------------------------------------------------------
-- Colunas
--------------------------------------------------------------------------------
-- AS COLUNAS, NA ORDEM E NA LARGURA DO DETAILS (`scoreboard_layout.lua`, uma linha
-- `ScoreboardColumn:Create` por coluna):
--
--   player-portrait 60 · spec-icon 25 · player-name 110 · keystone 60 · mythic-score 90 ·
--   loot 80 · deaths 80 · avoidable-damage-taken 80 · damage-taken 100 · dps 100 · hps 100 ·
--   interrupts 100 · dispels 80
--
-- ⚠️ **DUAS COLUNAS DELE NÃO ENTRARAM, e não é preguiça:** `player-likes` (34) e
-- `player-like-button` (50). Elas são a rede social do plugin — o "gg" viaja pelo canal de
-- addon do Details entre quem roda o plugin, e ninguém fora dele responde. Um RocketMeter com
-- essa coluna mostraria **0 LIKES** para sempre, em todas as linhas, para todo mundo: uma
-- coluna que só sabe mentir ocupa 84px e ensina o jogador a desconfiar do resto da tela.
--
-- `render` marca a coluna que desenha algo que não é número; sem ele, é célula numérica e o
-- rótulo curto e o formato saem do catálogo de `Data.lua`, sem cópia. `custom` marca as que o
-- `C_DamageMeter` não conhece e o placar preenche por conta própria.
local ALL_COLUMNS = {
    { key = "portrait",   width = 60,  render = "portrait", custom = true, label = "" },
    { key = "spec",       width = 25,  render = "spec",     custom = true, label = "" },
    { key = "name",       width = 110, render = "name",     custom = true, label = "" },
    { key = "keystone",   width = 60,  render = "keystone", custom = true, label = L["Keystone"] },
    { key = "score",      width = 90,  render = "score",    custom = true, label = L["Score"] },
    { key = "loot",       width = 80,  render = "loot",     custom = true, label = L["Loot"] },

    -- ⚑ DAQUI PARA BAIXO O PLACAR DEIXOU DE COPIAR O DETAILS, e é decisão do usuário
    -- (10/09/2026), não descuido: *"tá faltando o total de dano e total de cura, e vamos ordenar
    -- isso, depois da coluna saque, vem o DPS, Dano, CPS, Cura, Interrupts, Disspel, Mortes,
    -- Evitavel, Recebido, pode diminuir só um pouco a largura das colunas"*.
    --
    -- As seis de cima (retrato, spec, nome, pedra, pontuação, saque) continuam com os números
    -- dele: são identidade e Mítico+, e ali a semelhança com o painel que ele conhece vale.
    --
    -- A ORDEM TEM UMA LÓGICA, e ela casa com a da janela de combate: **a taxa vem antes do
    -- total**, porque a taxa é a leitura principal e o total é o contexto dela — a mesma decisão
    -- que inverteu o brilho do par na 0.82.0. Depois vêm as contagens, e por último o dano
    -- recebido, que é o que menos se olha ao fim de uma chave.
    --
    -- AS LARGURAS descem em dois degraus, não num só: métrica de valor (dano, cura, DPS, CPS,
    -- recebido, evitável) fica em **84**, e métrica de CONTAGEM (interrupções, dissipações,
    -- mortes) em **60**. Contagem escreve "7", não "44.4M" — dar a ela a mesma caixa era o que
    -- fazia a tabela parecer vazia à direita. O piso de 60 é o rótulo: "Dissip" e "Mortes"
    -- precisam caber no cabeçalho, senão a coluna perde o nome.
    { key = "dps",        width = 84 },
    { key = "damage",     width = 84 },
    { key = "hps",        width = 84 },
    { key = "healing",    width = 84 },
    { key = "interrupts", width = 60 },
    { key = "dispels",    width = 60 },
    { key = "deaths",     width = 60 },
    { key = "avoidable",  width = 84 },
    { key = "taken",      width = 84 },
}

local DEFAULT_SORT = "dps"

-- As colunas VISÍVEIS nesta corrida. O catálogo acima é fixo; esta lista é recalculada a cada
-- desenho porque um placar de raide não tem pontuação de Mítico+ — mostrar a coluna vazia (ou
-- pior, com a pontuação de M+ de cada um ao lado do dano num boss de raide) é ruído com cara
-- de dado. Todo o resto do arquivo lê daqui, nunca do catálogo.
local columns = ALL_COLUMNS

local frame, headerRow, rows, timeline
local sortBy, sortDesc = DEFAULT_SORT, true
local context                -- a corrida que está na tela

---A corrida em tela é uma chave de Mítico+? O placar de raide não tem nível, nem afixos, nem
---baú, nem eixo de tempo — e mostrar essas peças vazias em volta de um boss morto é pior que
---não mostrar nada. `level` é o que separa os dois casos.
local function IsKeystone()
    return context ~= nil and context.level ~= nil
end

---Recalcula quais colunas aparecem.
---
---Fora de uma chave saem as três que só existem em Mítico+ — pedra, pontuação e saque. As
---outras `custom` (retrato, especialização, nome) valem em qualquer placar e ficam: um placar
---de raide sem a coluna de nome seria uma tabela de números sem dono.
local KEYSTONE_ONLY = { keystone = true, score = true, loot = true }

local function ComputeColumns()
    if IsKeystone() then return ALL_COLUMNS end

    local out = {}
    for c = 1, #ALL_COLUMNS do
        if not KEYSTONE_ONLY[ALL_COLUMNS[c].key] then out[#out + 1] = ALL_COLUMNS[c] end
    end
    return out
end

---Altura do rodapé. Sem linha do tempo ele não precisa dos 66px — sobrariam como um vão
---vazio embaixo das linhas, que é o tipo de espaço reservado para nada que faz uma janela
---parecer quebrada.
local function FooterHeight()
    return IsKeystone() and FOOTER_HEIGHT or 20
end

local function ColumnLabel(column)
    if column.label then return column.label end
    return ns.Data.GetShortLabel(column.key)
end

---The header's groups: consecutive columns of the same family (`group` in the catalogue). A
---custom column is a group by itself.
---@return table[] { first, last, label }
local function HeaderGroups()
    local groups = {}
    for c = 1, #columns do
        local column = columns[c]
        local def = not column.custom and ns.Data.GetColumn(column.key) or nil
        local key = def and def.group or nil
        local last = groups[#groups]
        if key ~= nil and last and last.key == key and last.last == c - 1 then
            last.last = c
        else
            groups[#groups + 1] = { first = c, last = c, key = key,
                label = def and def.family or ColumnLabel(column) }
        end
    end
    return groups
end

---A borda ESQUERDA de cada coluna, e a largura total.
---
---Da esquerda para a direita, e este é o giro de 180° que a cópia obrigou: o placar antigo
---empilhava as colunas a partir da BORDA DIREITA, com um bloco fixo de nome à esquerda. O
---Details não faz isso — cada coluna começa onde a anterior terminou, mais `padding`
---(`DF/header.lua:363` e `:531`), e o conteúdo da célula se alinha à esquerda dela
---(`AlignWithHeader(headerFrame, "left")`, `scoreboard.lua:836`). Nome e retrato deixam de ser
---exceção e viram duas colunas como as outras.
local function ColumnOffsets()
    local offsets, x = {}, 0
    for c = 1, #columns do
        offsets[c] = x
        x = x + columns[c].width + COL_PADDING
    end
    return offsets, x
end

local function PanelWidth()
    local _, columnsWidth = ColumnOffsets()
    return SIDE * 2 + columnsWidth
end

local function PanelHeight(rowCount)
    return HEADER_HEIGHT + COLHEAD_HEIGHT
        + rowCount * (ROW_HEIGHT + ROW_SPACING)
        + FooterHeight()
end

---Quantas linhas cabem na tela. Uma raide de 20 pessoas daria 866px de painel mais a estrela
---por cima: em tela de 1080 com escala de UI padrão o rodapé sai por baixo e o usuário não
---tem como arrastar de volta o que está fora. O piso de 3 existe para o caso de a altura do
---UIParent vir estranha — melhor um painel pequeno que um painel de uma linha.
local function MaxRowsOnScreen()
    local screen = UIParent and UIParent:GetHeight()
    if not screen or screen <= 0 then return MAX_ROWS end

    local free = screen - 160 - HEADER_HEIGHT - COLHEAD_HEIGHT - FooterHeight()
    local fits = math.floor(free / (ROW_HEIGHT + ROW_SPACING))
    if fits < 3 then fits = 3 end
    if fits > MAX_ROWS then fits = MAX_ROWS end
    return fits
end

--------------------------------------------------------------------------------
-- Arte, com o silêncio contornado
--------------------------------------------------------------------------------
---Aplica um atlas só se ele existir neste cliente.
---
---`SetAtlas` com nome errado não levanta erro nem devolve nada — a textura fica vazia e o bug
---aparece semanas depois como "aquele canto está esquisito". Consultar `GetAtlasInfo` antes é
---o padrão que os addons instalados usam, e é o que permite ter plano B.
---@return boolean aplicado
local function Atlas(texture, name)
    if not texture or not name then return false end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    if not info then return false end
    texture:SetAtlas(name)
    return true
end

ns.SetAtlasSafe = Atlas

local ROLE_ATLAS = {
    TANK = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

---Função (tanque / curandeiro / dano) de um jogador, pelo nome.
---
---O medidor não informa função, e sem isto o ícone só aparecia na SIMULAÇÃO — na corrida real
---cada linha ficava com 19px vazios à esquerda, o que faz o painel parecer desalinhado sem
---que dê para dizer por quê. Varrer as unidades do grupo é barato (no máximo 40 chamadas) e
---não depende de inspeção nem de comunicação entre addons.
---
---`UnitName` continua legível em combate (identidade não é secret por padrão), mas o cliente
---pode escondê-la caso a caso — daí a checagem antes de comparar.
local function RoleFor(name)
    if name == nil or issecretvalue(name) or type(name) ~= "string" then return nil end
    if not UnitGroupRolesAssigned or not UnitName then return nil end

    local wanted = ns.SplitName(name)
    local size = GetNumGroupMembers() or 0

    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, size do units[i] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, math.max(0, size - 1) do units[i + 1] = "party" .. i end
    end

    for i = 1, #units do
        local unitName = UnitName(units[i])
        if unitName ~= nil and not issecretvalue(unitName) and unitName == wanted then
            local role = UnitGroupRolesAssigned(units[i])
            if role and role ~= "NONE" then return role end
            return nil
        end
    end
    return nil
end

---Fundo do painel: a arte da própria masmorra, dessaturada e apagada.
---
---O 5º retorno de `GetMapUIInfo` é o `backgroundTexture` da masmorra — funciona para qualquer
---masmorra, presente ou futura, sem tabela amarrada a temporada (o Details_MythicPlus mantém
---uma pasta de `.jpg` por masmorra e ela já não cobre a temporada atual). Sem mapID — que é o
---caso da simulação — simplesmente não há fundo, e o painel fica no escuro liso.
local function ApplyBackdropArt(texture, mapID)
    texture:SetTexture(nil)
    if not mapID or not C_ChallengeMode or not C_ChallengeMode.GetMapUIInfo then return false end

    local ok, _, _, _, _, background = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if not ok or not background then return false end

    texture:SetTexture(background)
    texture:SetDesaturation(0.5)
    texture:SetAlpha(0.16)
    return true
end

--------------------------------------------------------------------------------
-- Dados
--------------------------------------------------------------------------------
---Pontuação de M+ de um jogador pelo nome.
---
---`GetPlayerMythicPlusRatingSummary` aceita nome ou unit token; o placar só tem o nome que o
---medidor devolveu. Em combate a identidade pode ser secret, e aí não há o que consultar —
---por isso o `pcall` e a checagem: o placar aparece depois da corrida, mas o usuário pode
---reabrir no meio de outra luta.
local function ScoreFor(name)
    if name == nil or issecretvalue(name) then return nil end
    if not C_PlayerInfo or not C_PlayerInfo.GetPlayerMythicPlusRatingSummary then return nil end

    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, name)
    if not ok or type(summary) ~= "table" then return nil end
    return summary.currentSeasonScore
end

---Normaliza as linhas para que `values[c]` corresponda sempre a `columns[c]`.
---
---`Data.GetRows` só conhece colunas de medidor, então ele recebe a sublista e devolve valores
---indexados por ela. Remapear aqui é o que permite ao desenho ter um caminho só, valendo
---igual para corrida real e para simulação — dois caminhos de desenho divergem na terceira
---mudança, e o projeto já pagou por isso uma vez.
--------------------------------------------------------------------------------
-- Retrato da corrida: da sessão viva para dado gravável
--------------------------------------------------------------------------------
---Todas as chaves de coluna que um retrato guarda.
---
---Guarda o catálogo INTEIRO, não só o que está visível: quem abrir a corrida daqui a uma
---semana pode ter mudado as colunas, e um retrato que só gravou o que estava na tela naquele
---dia obriga a resposta "esse dado eu não tenho". Gravar tudo custa oito números por jogador.
local function SnapshotKeys()
    local keys = {}
    for c = 1, #ALL_COLUMNS do
        if not ALL_COLUMNS[c].custom then keys[#keys + 1] = ALL_COLUMNS[c].key end
    end
    return keys
end

---Um número que possa ir para o disco, ou nil.
---
---Secret value **não pode ser serializado** — é regra explícita do Midnight, e tentar gravá-lo
---nos SavedVariables é erro. Aqui ele simplesmente não entra: a célula fica vazia no retrato,
---que é honesto, em vez de gravar lixo ou derrubar a captura.
local function Storable(value)
    if value == nil or issecretvalue(value) then return nil end
    if type(value) ~= "number" then return nil end
    return value
end

---Copia a sessão viva para uma tabela solta, pronta para desenhar e para gravar.
---@param base table o contexto da corrida (título, tempo, afixos, linha do tempo...)
---@return table retrato
function Scoreboard.Snapshot(base)
    local keys = SnapshotKeys()
    local data = ns.Data.GetRows(base.sessionType or 1, DEFAULT_SORT, keys, MAX_ROWS, false)

    local rows = {}
    for i = 1, (data and #data or 0) do
        local source = data[i].source
        local name = source.name
        if issecretvalue(name) then name = nil end

        local values = {}
        for k = 1, #keys do
            values[keys[k]] = Storable(data[i].values[k])
        end
        if base.kind == "mplus" then
            values.score = Storable(ScoreFor(source.name))
        end

        local classFilename = source.classFilename
        if issecretvalue(classFilename) then classFilename = nil end
        local specIconID = source.specIconID
        if issecretvalue(specIconID) then specIconID = nil end
        local isLocal = source.isLocalPlayer
        isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true

        -- O QUE O MEDIDOR NÃO SABE viaja no retrato junto com o resto: nível de item, pedra e
        -- saque. Tem que ser AQUI, no instante da captura — uma corrida reaberta na semana que
        -- vem não tem mais grupo para inspecionar nem evento de saque para ouvir.
        local ilevel, keystoneLevel, keystoneMapID, gotLoot
        if ns.Party then
            ilevel = ns.Party.ItemLevel(source.name)
            keystoneLevel, keystoneMapID = ns.Party.Keystone(source.name)
            gotLoot = ns.Party.Loot(source.name)
        end

        rows[i] = {
            name = name or (UNKNOWN or "?"),
            classFilename = classFilename,
            specIconID = specIconID,
            role = RoleFor(source.name),
            isLocalPlayer = isLocal,
            scoreGain = isLocal and base.scoreGain or nil,
            ilevel = ilevel,
            keystoneLevel = keystoneLevel,
            keystoneMapID = keystoneMapID,
            loot = gotLoot,
            values = values,
        }
    end

    base.rows = rows
    base.recordedAt = time and time() or nil
    return base
end

--------------------------------------------------------------------------------
-- Corridas guardadas
--------------------------------------------------------------------------------
---Onde as corridas moram.
---
---SavedVariable PRÓPRIO, por personagem, fora de `ns.db`: `Profile.Reset()` apaga tudo que
---está na configuração, e "restaurar o padrão" não pode significar "perder as corridas". Além
---disso a corrida é do personagem que a fez, não da conta.
local function Store()
    if RocketMeterRunsDB == nil then RocketMeterRunsDB = {} end
    return RocketMeterRunsDB
end

function Scoreboard.SaveRun(kind, snapshot)
    if not kind or not snapshot then return end
    Store()[kind] = snapshot
end

function Scoreboard.GetRun(kind)
    local run = Store()[kind]
    if type(run) ~= "table" or type(run.rows) ~= "table" or #run.rows == 0 then return nil end
    return run
end

---Põe a CLASSE em cada marcador de morte da linha do tempo — quando dá para provar qual é.
---
---Pedido de 10/09/2026: *"a outra marcação é a morte, poderia ter o ícone da classe que morreu"*.
---
---⚑ SÃO DUAS FONTES E NENHUMA DELAS SOZINHA RESPONDE. O `Run` sabe **quando** cada morte
---aconteceu, no relógio da chave, mas o evento dele não diz **quem**. A métrica de mortes do
---medidor sabe **quem** (uma entrada por óbito, com a classe), mas o relógio dela é
---`deathTimeSeconds`, e daqui não dá para confirmar de onde ele conta.
---
---Então não se mistura relógio: o `Run` continua posicionando, e a lista do medidor só empresta a
---classe **na ordem**. E isso só é honesto sob uma condição que dá para verificar em tempo de
---execução: **as duas listas terem o mesmo tamanho**. Se tiverem, cada morte do medidor casa com
---o marcador de mesma posição. Se não tiverem, alguma das duas viu algo que a outra não viu, a
---correspondência por ordem passa a ser chute, e o marcador fica a caveira de sempre.
---
---É a diferença entre um ícone que pode estar errado e um ícone que só aparece quando está certo.
local function AttachDeathClasses(base)
    local marks = base.deathMarks
    if type(marks) ~= "table" or #marks == 0 then return end
    if not ns.Data or not ns.Data.GetDeathList then return end

    local obitos = ns.Data.GetDeathList(base.sessionType or 1)

    if #obitos ~= #marks then
        if ns.Log then
            ns.Log.Add("mortes", {
                marcadores = #marks, medidor = #obitos,
                decisao = "contagens diferentes; marcador fica sem classe",
            })
        end
        return
    end

    for i = 1, #marks do
        marks[i][2] = obitos[i].classe
        marks[i][3] = obitos[i].nome
    end

    if ns.Log then
        ns.Log.Add("mortes", { marcadores = #marks, decisao = "classe casada por ordem" })
    end
end

---O saque chegou DEPOIS da captura. Costura ele na corrida que já está retratada.
---
---⚑ ESTE É O DEFEITO DO PRINT DE 10/09, e o diário do usuário o datou sem sobrar dúvida:
---
---    00:33:16  snapshot  fim do combate
---    00:33:18  saque cru  Kankerlekker  (descartado: não é arma nem armadura)
---    00:33:20  saque      Gsm
---    00:33:30  saque      Dauð
---
---`Scoreboard.OnChallengeCompleted` roda **1,5 s** depois do `CHALLENGE_MODE_COMPLETED` — ou seja,
---por volta de 00:33:18. O saque do Gsm chegou 2 s depois e o do próprio jogador **12 s** depois.
---A coluna era capturada vazia e nunca mais olhava para trás; por isso ela estava vazia para
---**todo mundo**, inclusive para quem abriu o painel e sabia que tinha ganhado item.
---
---Esperar mais antes de capturar não resolve: não há prazo garantido para o último item cair, e
---qualquer número escolhido aqui seria chute. Costurar depois resolve para qualquer atraso.
---
---Mexe nos DOIS lugares onde a corrida existe, e é por isso que a função é uma só: o retrato em
---memória (o que está na tela) e o gravado em disco (o que `/rm score` reabre amanhã).
---
---⚑ E O DESENHO NÃO SE ATUALIZA SOZINHO — quem repinta é `Scoreboard.Refresh`, chamado no fim.
---`Scoreboard.Refresh`, e não o `SafeDraw` local: ele só é declarado 1200 linhas abaixo daqui, e um
---`local` referenciado antes da declaração vira busca de global — `nil` na hora da chamada.
-- ⚑ REDESENHO NAO PODE ACONTECER DENTRO DE UM REDESENHO, e isto nasceu de um defeito real: o
-- `ReencostarAteCompletar` chama `RefreshExternalColumns`, que chama `Scoreboard.Refresh`. Com o
-- timer do simulador rodando o callback **dentro** de quem o agendou (o do jogo não faz isso), a
-- corrente virava 24 desenhos empilhados, um por cima do outro, reescrevendo os caches
-- compartilhados no meio do próprio uso. O sintoma eram erros de TIPO em lugares sem relação
-- nenhuma com timer, um a cada ~30 execuções.
--
-- O stub do harness foi corrigido, mas a guarda fica: no jogo o `Refresh` também pode ser chamado
-- de um `OnClick`, de um evento e do timer, e nada garante que dois não se cruzem.
local desenhando = false

local function Costura(mexe)
    local naTela = false
    if type(context) == "table" and type(context.rows) == "table" then
        naTela = mexe(context) and true or false
    end

    -- Em disco, só a corrida do mesmo tipo da que está na tela: um saque de chave não pode
    -- aparecer no placar do último chefe de raide.
    local kind = context and context.kind
    local guardada = kind and Store()[kind]
    if type(guardada) == "table" and type(guardada.rows) == "table" and guardada ~= context then
        mexe(guardada)
    end

    if naTela and frame and frame:IsShown() then
        Scoreboard.Refresh()
    end
    return naTela
end

function Scoreboard.OnLoot(name, itemLink)
    if not name or not itemLink then return end

    -- (!) NOME SEM REINO DOS DOIS LADOS (26/09). `Party.NoteLoot` manda o nome curto ("Bizco"),
    -- e a linha de quem e de OUTRO reino guarda "Bizco-Quel'dorei" (corrida salva de 26/09). A
    -- comparacao exata deixava o item de todo jogador de outro reino fora do placar -- ele so
    -- entrava se chegasse nos 2 minutos da janela de `RefreshExternalColumns`, que tira o reino.
    local curto = ns.SplitName(name) or name
    Costura(function(run)
        local mudou = false
        for _, row in ipairs(run.rows) do
            if (ns.SplitName(row.name) or row.name) == curto and row.loot == nil then
                row.loot = itemLink
                mudou = true
            end
        end
        return mudou
    end)
end

---A pedra e a pontuação chegam **depois**, como o saque — e continuam chegando por minutos.
---
---⚑ ISTO É OBSERVAÇÃO DO USUÁRIO SOBRE O DETAILS, 10/09/2026, e ela reenquadrou a correção:
---*"geralmente o Details também não aparece na hora, mas conforme os jogadores vão abrindo o baú
---ele vai atualizando o placar, e então fica tudo certinho, as pedras o saque, a pontuação"*.
---
---Ou seja: **não é para acertar o instante da captura, é para o placar continuar vivo depois
---dela.** Faz sentido pelo próprio jogo — a pedra nova só existe quando cada um abre o baú, e é
---ela que a LibOpenRaid transmite; a pontuação da temporada é recalculada no servidor. Capturar
---mais tarde só trocaria um instante errado por outro.
---
---Então esta função reencosta as três colunas que dependem de fora, e ela é chamada tanto pelo
---aviso da lib quanto por uma janela de tentativas depois do fim da corrida.
---@return boolean mudou alguma coisa
function Scoreboard.RefreshExternalColumns()
    if not ns.Party then return false end

    return Costura(function(run)
        local mudou = false
        for _, row in ipairs(run.rows) do
            if row.name then
                if row.keystoneLevel == nil then
                    local nivel, mapa = ns.Party.Keystone(row.name)
                    if nivel then
                        row.keystoneLevel, row.keystoneMapID = nivel, mapa
                        mudou = true
                    end
                end
                if row.loot == nil then
                    local item = ns.Party.Loot(row.name)
                    if item then
                        row.loot = item
                        mudou = true
                    end
                end
                -- O NÍVEL DE ITEM ENTRA NA MESMA LISTA, pelo mesmo motivo: a inspeção do começo
                -- da chave falha calada (distância, fase, rajada de pedidos), e a resposta da
                -- LibOpenRaid pode chegar depois. Relato de 10/09: *"não aparece o ilvl dos
                -- outros"*.
                if row.ilevel == nil then
                    local nivel = ns.Party.ItemLevel(row.name)
                    if nivel then
                        row.ilevel = nivel
                        mudou = true
                    end
                end
                -- A PONTUAÇÃO É A ÚNICA QUE SE SOBRESCREVE, e de propósito: ela não "chega", ela
                -- **muda** — o servidor recalcula a da temporada depois da corrida. Manter a
                -- primeira leitura seria mostrar de propósito o número velho.
                local nova = ScoreFor(row.name)
                if nova and row.values and row.values.score ~= nova then
                    row.values.score = nova
                    mudou = true
                end
            end
        end
        return mudou
    end)
end

---Há quanto tempo a corrida foi feita, em texto curto ("há 2 dias").
local function RunAge(snapshot)
    if not snapshot or not snapshot.recordedAt or not time then return nil end

    local seconds = time() - snapshot.recordedAt
    if seconds < 0 then return nil end
    if seconds < 3600 then
        return format(L["%d min ago"], math.max(1, math.floor(seconds / 60)))
    end
    if seconds < 86400 then
        return format(L["%d h ago"], math.floor(seconds / 3600))
    end
    return format(L["%d d ago"], math.floor(seconds / 86400))
end

---Converte o retrato (valores por CHAVE) para o formato que o desenho usa (por POSIÇÃO).
---
---O placar não lê mais a sessão viva. Ele lê sempre um retrato: da corrida que acabou, de uma
---corrida guardada em disco, ou da simulação. Três motivos:
---
---  1. A sessão do `C_DamageMeter` é zerada pela próxima luta. "Ver o último placar" só é
---     possível se os números tiverem sido copiados para fora dela no momento certo.
---  2. Um retrato é dado morto: não tem secret value, não tem referência para tabela da API,
---     e por isso pode ser gravado nos SavedVariables.
---  3. Um caminho de desenho só. Corrida real, corrida guardada e simulação desenham pelo
---     mesmo código — o que faz a simulação valer como teste do painel de verdade.
local function CollectRows(rowCount)
    local stored = context and context.rows
    if not stored then return {} end

    local out = {}
    local limit = #stored
    if rowCount and rowCount < limit then limit = rowCount end

    for i = 1, limit do
        local entry = stored[i]
        local values = {}
        for c = 1, #columns do
            values[c] = entry.values and entry.values[columns[c].key]
        end
        out[i] = {
            source = entry,          -- nome, classe, ícone: o retrato tem os mesmos campos
            row = entry,
            values = values,
            best = {},
        }
    end

    -- O realce sai do próprio `Data`, não de uma cópia da regra: se lá mudar o que conta como
    -- liderança (hoje exige valor > 0 e pelo menos duas linhas), o placar acompanha sozinho.
    if ns.Data.MarkColumnLeaders then
        local keys = {}
        for c = 1, #columns do keys[c] = columns[c].key end
        pcall(ns.Data.MarkColumnLeaders, out, keys)
    end

    return out
end

---Reordena as linhas já montadas. Só roda quando o valor é legível — em combate os campos são
---secret e comparar levanta erro.
local function SortRows(list, columnIndex)
    local readable = true
    for i = 1, #list do
        local v = list[i].values[columnIndex]
        if v ~= nil and (issecretvalue(v) or type(v) ~= "number") then
            readable = false
            break
        end
    end
    if not readable then return end

    table.sort(list, function(a, b)
        local x = a.values[columnIndex] or -1
        local y = b.values[columnIndex] or -1
        if x == y then return false end
        if sortDesc then return x > y end
        return x < y
    end)
end

--------------------------------------------------------------------------------
-- Cabeçalho de colunas
--------------------------------------------------------------------------------
---O cabeçalho de colunas, no formato do Details: cada coluna é uma CÉLULA com fundo próprio,
---20px de altura, texto branco pequeno encostado à esquerda.
---
---A régua dourada que havia aqui saiu. Ela era invenção nossa; o Details separa cabeçalho de
---linhas pelo próprio fundo das células (`header_backdrop_color = {0, 0, 0, 0.5}`,
---`DF/header.lua:743`), que é mais escuro que o das linhas — e por isso a divisão aparece sem
---precisar de um risco.
---
---O clique para ordenar FICA. Ele não é do Details, mas também não muda nada do que se vê:
---a coluna ordenada troca o tom do fundo pelo `header_backdrop_color_selected` que o próprio
---framework dele já define (`:744`), então até o realce é número dele.
local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
    end

    headerRow:ClearAllPoints()
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -HEADER_HEIGHT)
    headerRow:SetHeight(COLHEAD_HEIGHT)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow, "BackdropTemplate")
            button:SetHeight(COLHEAD_HEIGHT)
            button:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                tileSize = 64, tile = true,
            })
            -- The PART of the column, on the second line; the family goes on the first, over
            -- the whole group (`headerRow.families`, below).
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("BOTTOMLEFT", COL_PADDING, 0)
            button.text:SetHeight(COLHEAD_LINE)
            button.text:SetJustifyH("LEFT")
            button.text:SetWordWrap(false)
            button:SetScript("OnClick", function(self)
                local column = columns[self.columnIndex]
                if column.render and column.render ~= "score" then return end
                local key = column.key
                if sortBy == key then sortDesc = not sortDesc else sortBy, sortDesc = key, true end
                -- Pela função pública, não por `Draw()` cru: `SafeDraw` é local e declarado
                -- mais abaixo, então aqui ele nem seria visível — e um erro de desenho
                -- disparado de dentro de um OnClick some sem deixar rastro quando
                -- `scriptErrors` está desligado, que é o padrão do jogo.
                Scoreboard.Refresh()
            end)
            button:SetScript("OnEnter", function(self)
                local column = columns[self.columnIndex]
                local label = ColumnLabel(column)
                if label == "" then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(column.custom and label
                    or ns.Data.GetAttributeLabel(column.key), 1, 1, 1)
                if not column.render or column.render == "score" then
                    GameTooltip:AddLine(L["Click to sort by this column."], 0.7, 0.7, 0.7)
                end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            headerRow.labels[c] = button
        end

        button.columnIndex = c
        button:SetWidth(columns[c].width)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", headerRow, "TOPLEFT", offsets[c], 0)

        local sorted = columns[c].key == sortBy
        button:SetBackdropColor(unpack(sorted and COLHEAD_TINT_SORTED or COLHEAD_TINT))

        -- Corpo 10, que é o `text_size` do framework dele (`DF/header.lua:730`), lido pela
        -- escada do addon para o seletor de fonte continuar valendo.
        ns.ApplyScoreboardFont(button.text, 10 - ns.Skin.scoreboardFontSize, "")
        local def = not columns[c].custom and ns.Data.GetColumn(columns[c].key) or nil
        button.text:SetText(def and def.part or "")
        button.text:SetTextColor(0.62, 0.62, 0.66, 1)
        button:Show()
    end

    for c = #columns + 1, #headerRow.labels do
        headerRow.labels[c]:Hide()
    end

    -- THE FIRST LINE: one label per group, over the group's columns. A group of one column has
    -- no part, so its name takes the two lines: centred on them, and a long name ("Controle
    -- coletivo") wraps into the second line instead of running over the next column.
    headerRow.families = headerRow.families or {}
    local groups = HeaderGroups()
    for g = 1, #groups do
        local group = groups[g]
        local label = headerRow.families[g]
        if not label then
            label = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetJustifyH("LEFT")
            headerRow.families[g] = label
        end
        local width = offsets[group.last] - offsets[group.first] + columns[group.last].width
        label:ClearAllPoints()
        label:SetWidth(width - COL_PADDING)
        ns.ApplyScoreboardFont(label, 10 - ns.Skin.scoreboardFontSize, "")
        label:SetText(group.label)
        label:SetTextColor(1, 1, 1, 1)
        if group.last > group.first then
            -- (!) CENTRED OVER THE PAIR (30/09). Left-aligned, the family sat over its first
            -- column and read as that column's own title, and the second column looked like a
            -- stranger under a grey word; the user: *"tem coluna que é dupla mas no cabeçalho
            -- do título estão separadas"*. Centred on the span of the group, the name belongs
            -- to both columns, as in the meter window's header.
            label:SetJustifyH("CENTER")
            label:SetWordWrap(false)
            label:SetHeight(COLHEAD_LINE)
            label:SetPoint("TOPLEFT", headerRow, "TOPLEFT", offsets[group.first] + COL_PADDING, 0)
        else
            -- A family of one column sits over its numbers, which are left-aligned.
            label:SetJustifyH("LEFT")
            label:SetWordWrap(true)
            label:SetHeight(COLHEAD_HEIGHT)
            label:SetJustifyV("MIDDLE")
            label:SetPoint("TOPLEFT", headerRow, "TOPLEFT", offsets[group.first] + COL_PADDING, 0)
        end
        label:SetShown(group.label ~= "")
    end
    for g = #groups + 1, #headerRow.families do
        headerRow.families[g]:Hide()
    end
end

---For the harness: the header's groups as drawn.
function Scoreboard.__headerGroups()
    return HeaderGroups(), headerRow and headerRow.families or {}
end

--------------------------------------------------------------------------------
-- Linhas
--------------------------------------------------------------------------------
---As peças de uma célula, por tipo de coluna. Cada construtor devolve o objeto que o desenho
---vai preencher, e todos vivem dentro de um frame de célula com a largura da coluna — assim
---quem muda a largura de uma coluna não precisa saber o que tem dentro dela.
local CellBuilders = {}

---Retrato redondo + ícone de função + nível de item (`scoreboard_layout.lua:291-315`).
function CellBuilders.portrait(cell)
    local size = ROW_HEIGHT - PORTRAIT_INSET * 2

    cell.portrait = cell:CreateTexture(nil, "ARTWORK")
    cell.portrait:SetSize(size, size)
    cell.portrait:SetPoint("LEFT", COL_PADDING, 0)

    cell.role = cell:CreateTexture(nil, "OVERLAY", nil, 6)
    cell.role:SetSize(ROLE_SIZE, ROLE_SIZE)
    cell.role:SetPoint("BOTTOMLEFT", cell.portrait, "BOTTOMRIGHT", ROLE_X, ROLE_Y)

    -- A placa escura atrás do nível de item. `LoC-ShadowBG` é a mesma textura do Details
    -- (`:311`) e é do próprio jogo — não é arte do addon dele.
    cell.ilvlBg = cell:CreateTexture(nil, "OVERLAY", nil, 5)
    cell.ilvlBg:SetTexture("Interface\\Cooldown\\LoC-ShadowBG")
    cell.ilvlBg:SetPoint("BOTTOMLEFT", cell.portrait, "BOTTOMLEFT", -ILVL_BG_INSET, -1)
    cell.ilvlBg:SetPoint("BOTTOMRIGHT", cell.portrait, "BOTTOMRIGHT", ILVL_BG_INSET, -1)
    cell.ilvlBg:SetHeight(ILVL_BG_HEIGHT)

    cell.ilvl = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.ilvl:SetPoint("BOTTOM", cell.portrait, "BOTTOM", 0, 0)
end

function CellBuilders.spec(cell)
    cell.icon = cell:CreateTexture(nil, "OVERLAY")
    cell.icon:SetSize(SPEC_ICON, SPEC_ICON)
    cell.icon:SetPoint("LEFT", COL_PADDING, 0)

    -- Segunda textura porque especialização é id de ícone e classe é recorte de atlas, e
    -- `SetMask` não convive com `SetTexCoord`. O placar antigo aplicava máscara aqui e o ícone
    -- de classe sumia — é o defeito que aquela reescrita corrigiu, e ele não pode voltar.
    cell.iconClass = cell:CreateTexture(nil, "OVERLAY")
    cell.iconClass:SetSize(SPEC_ICON, SPEC_ICON)
    cell.iconClass:SetPoint("LEFT", COL_PADDING, 0)
    cell.iconClass:Hide()
end

function CellBuilders.name(cell)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.text:SetPoint("LEFT", COL_PADDING, 0)
    cell.text:SetPoint("RIGHT", -COL_PADDING, 0)
    cell.text:SetJustifyH("LEFT")
    cell.text:SetWordWrap(false)
end

---Ícone da masmorra da pedra + nível (`scoreboard_layout.lua:515-560`).
function CellBuilders.keystone(cell)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(KEYSTONE_ICON, KEYSTONE_ICON)
    cell.icon:SetPoint("LEFT", COL_PADDING, 0)
    -- O recorte tira a moldura da arte da masmorra e deixa só a cena.
    cell.icon:SetTexCoord(36 / 512, 375 / 512, 50 / 512, 290 / 512)
    cell.icon:SetAlpha(0.932)
    if cell.icon.SetMask then
        pcall(cell.icon.SetMask, cell.icon, "Interface\\FrameGeneral\\UIFrameIconMask")
    end

    cell.levelBg = cell:CreateTexture(nil, "ARTWORK", nil, 6)
    cell.levelBg:SetTexture("Interface\\Cooldown\\LoC-ShadowBG")
    cell.levelBg:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMLEFT", -5, -1)
    cell.levelBg:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 5, -1)
    cell.levelBg:SetHeight(ILVL_BG_HEIGHT)

    cell.level = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.level:SetPoint("BOTTOM", cell.icon, "BOTTOM", 0, -1)
end

---Quadrado de saque: ícone 32 com borda na cor da qualidade e o nível do item por cima
---(`scoreboard_layout.lua:674-699`).
function CellBuilders.loot(cell)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(LOOT_ICON, LOOT_ICON)
    cell.icon:SetPoint("LEFT", COL_PADDING, 0)

    cell.border = cell:CreateTexture(nil, "OVERLAY")
    cell.border:SetSize(LOOT_ICON, LOOT_ICON)
    cell.border:SetPoint("CENTER", cell.icon, "CENTER", 0, 0)
    -- A borda nasce escondida: quem escolhe o atlas e a QUALIDADE do item, no desenho.
    cell.border:Hide()

    cell.ilvlBg = cell:CreateTexture(nil, "OVERLAY", nil, 5)
    cell.ilvlBg:SetTexture("Interface\\Cooldown\\LoC-ShadowBG")
    cell.ilvlBg:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMLEFT", -3, -1)
    cell.ilvlBg:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 3, -1)
    cell.ilvlBg:SetHeight(ILVL_BG_HEIGHT)

    cell.ilvl = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.ilvl:SetPoint("BOTTOM", cell.icon, "BOTTOM", 0, 0)
end

---Célula de número — e de pontuação, que é número com o ganho colado.
function CellBuilders.value(cell)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.text:SetPoint("LEFT", COL_PADDING, 0)
    cell.text:SetPoint("RIGHT", -COL_PADDING, 0)
    -- À ESQUERDA, e é a mudança que mais se vê. O placar antigo alinhava número à direita, que
    -- é o certo para comparar grandezas empilhadas; o Details alinha tudo à esquerda, colado ao
    -- rótulo da coluna (`AlignWithHeader(headerFrame, "left")`). Copiar é copiar isso também.
    cell.text:SetJustifyH("LEFT")
    cell.text:SetWordWrap(false)
end

-- A CÉLULA DE PONTUAÇÃO É UMA CÉLULA DE NÚMERO, e faltava dizer isso ao construtor.
--
-- Era o defeito do print de 07/09 20:22: a coluna declara `render = "score"`, existe um
-- `CellPainters.score` para escrever `2863 (+0)`, e **não existia `CellBuilders.score`**. O
-- `BuildRow` faz `CellBuilders[kind](cell)`, então na primeira linha ele chamava nil e o desenho
-- inteiro abortava — com o cabeçalho e os rótulos de coluna já na tela, porque eles são
-- desenhados antes. O painel abria bonito e **vazio**, que é o sintoma mais enganoso possível:
-- não parece erro de Lua, parece "não tem dado".
--
-- O comentário logo acima já dizia "e de pontuação, que é número com o ganho colado". A intenção
-- estava escrita; só o roteamento não estava.
CellBuilders.score = CellBuilders.value

local function BuildRow(index)
    local row = rows[index]

    if not row then
        -- Frame, não Button: a linha do placar não faz nada ao ser clicada. Como Button ela
        -- capturava o mouse e o painel deixava de ser arrastável em cima das linhas — que é
        -- justamente onde a pessoa agarra.
        row = CreateFrame("Frame", nil, frame)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(false)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.cells = {}
        rows[index] = row
    end

    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + COLHEAD_HEIGHT
        + (index - 1) * (ROW_HEIGHT + ROW_SPACING) + 1)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + LINE_INSET, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE - LINE_INSET, offsetY)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local cell = row.cells[c]
        local kind = columns[c].render or "value"

        -- A célula guarda o TIPO com que foi construída. As colunas mudam entre uma corrida de
        -- chave e um placar de raide, e uma célula reaproveitada com o construtor errado
        -- desenharia um retrato onde deveria haver um número — sem erro nenhum, só errado.
        if cell and cell.kind ~= kind then
            cell:Hide()
            cell = nil
            row.cells[c] = nil
        end

        if not cell then
            cell = CreateFrame("Frame", nil, row)
            cell.kind = kind
            cell:SetHeight(ROW_HEIGHT)
            CellBuilders[kind](cell)
            row.cells[c] = cell
        end

        cell:SetWidth(columns[c].width)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", offsets[c], 0)

        if cell.text then ns.ApplyScoreboardFont(cell.text, 0, "") end
        if cell.ilvl then ns.ApplyScoreboardFont(cell.ilvl, ILVL_FONT - ns.Skin.scoreboardFontSize, "") end
        if cell.level then ns.ApplyScoreboardFont(cell.level, KEYSTONE_FONT - ns.Skin.scoreboardFontSize, "") end
        cell:Show()
    end

    for c = #columns + 1, #row.cells do
        if row.cells[c] then row.cells[c]:Hide() end
    end

    return row
end

---Escreve a célula de pontuação: `2847 (+16)`, com o ganho em verde.
---O ganho só existe para quem o cliente sabe informar — na corrida real, só o próprio jogador
---(vem de `oldOverallDungeonScore`/`newOverallDungeonScore`). Sem ganho, mostra só o número.
local function ScoreText(entry, index)
    local value = entry.values[index]
    if value == nil then return "—" end
    -- Secret vai INTEIRO para o FontString: o motor sabe renderizar, o Lua nao pode ler. Um
    -- `math.floor` aqui derrubaria o desenho da linha inteira.
    if issecretvalue(value) then return value end
    if type(value) ~= "number" then return tostring(value) end

    local text = tostring(math.floor(value + 0.5))
    -- O ganho é por jogador no retrato: só o próprio jogador tem esse número (vem de
    -- `oldOverallDungeonScore`/`newOverallDungeonScore`, que o cliente só informa de si).
    local gain = entry.row and entry.row.scoreGain
    if gain and gain > 0 then
        text = text .. " |cff40d878(+" .. gain .. ")|r"
    end
    return text
end

--------------------------------------------------------------------------------
-- Linha do tempo
--------------------------------------------------------------------------------
---Desenha o rodapé: trilho da corrida, marcadores de boss e de morte, eixo de tempo e o baú.
---
---O verde/vermelho do trilho NÃO é ritmo da chave — é dentro/fora de combate, que é o que o
---painel de referência mostra e o que eu teria errado sem ler o código dele. Verde é lutando,
---vermelho é andando. Quem diz "deu no tempo" é o baú no fim, verde ou vermelho.
local function DrawTimeline()
    if not timeline then return end

    -- Baú de Cofre Grandioso, eixo de tempo e marcador de chave fechada são vocabulário de
    -- Mítico+. Num placar de encontro de raide eles apareciam do mesmo jeito — um baú verde
    -- dizendo "no tempo" embaixo de um boss que não tem cronômetro. O rodapé inteiro sai.
    local total = context and context.durationSeconds
    if not IsKeystone() or not total or issecretvalue(total) or total <= 0 then
        timeline:Hide()
        return
    end
    timeline:Show()

    local limit = context.timeLimit

    -- O eixo vai até o limite da chave quando ele é maior que a corrida: assim dá para ver
    -- quanto tempo sobrou, que é a informação que o jogador procura primeiro.
    local span = total
    if limit and limit > span then span = limit end

    local width = timeline:GetWidth()
    if not width or width <= 0 then width = PanelWidth() - SIDE * 2 end
    local function X(seconds)
        local at = seconds / span
        if at < 0 then at = 0 elseif at > 1 then at = 1 end
        return at * width
    end

    -- Segmentos de combate.
    timeline.segments = timeline.segments or {}
    for _, seg in ipairs(timeline.segments) do seg:Hide() end

    -- O TRECHO QUE O ADDON NAO VIU FICA NEUTRO, nem verde nem vermelho. Numa corrida retomada
    -- o trilho pintava de vermelho -- "andando" -- os minutos anteriores ao `/reload`, que e a
    -- mesma mentira do numero de fora-de-combate, so que desenhada.
    local desde = context.knownFrom or 0
    if desde > 0 then
        timeline.unknown = timeline.unknown or timeline:CreateTexture(nil, "ARTWORK")
        timeline.unknown:SetHeight(RAIL_HEIGHT)
        timeline.unknown:ClearAllPoints()
        timeline.unknown:SetPoint("LEFT", timeline.rail, "LEFT", 0, 0)
        timeline.unknown:SetWidth(math.max(1, X(desde)))
        timeline.unknown:SetColorTexture(0.45, 0.45, 0.48, 0.55)
        timeline.unknown:Show()
    elseif timeline.unknown then
        timeline.unknown:Hide()
    end

    local marks = (context.combatTimeline or {})
    local used = 0
    for i = 1, #marks do
        local startAt = marks[i][1]
        local inCombat = marks[i][2]
        local stopAt = marks[i + 1] and marks[i + 1][1] or total
        if stopAt > startAt then
            used = used + 1
            local seg = timeline.segments[used]
            if not seg then
                seg = timeline:CreateTexture(nil, "ARTWORK")
                seg:SetHeight(RAIL_HEIGHT)
                timeline.segments[used] = seg
            end
            seg:ClearAllPoints()
            seg:SetPoint("LEFT", timeline.rail, "LEFT", X(startAt), 0)
            seg:SetWidth(math.max(1, X(stopAt) - X(startAt)))
            if inCombat then
                seg:SetColorTexture(0.10, 0.70, 0.10, 0.85)
            else
                seg:SetColorTexture(0.70, 0.10, 0.10, 0.70)
            end
            seg:Show()
        end
    end

    -- Marcadores de boss, acima do trilho.
    timeline.bosses = timeline.bosses or {}
    for _, marker in ipairs(timeline.bosses) do marker:Hide() end

    for i, boss in ipairs(context.bosses or {}) do
        local marker = timeline.bosses[i]
        if not marker then
            marker = CreateFrame("Frame", nil, timeline)
            marker:SetSize(BOSS_ICON, BOSS_ICON)
            marker.icon = marker:CreateTexture(nil, "ARTWORK")
            marker.icon:SetAllPoints()
            marker.label = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            marker.label:SetPoint("LEFT", marker, "RIGHT", 1, 0)
            marker.tick = marker:CreateTexture(nil, "ARTWORK")
            marker.tick:SetSize(1, 4)
            marker.tick:SetPoint("TOP", marker, "BOTTOM", 0, 1)
            marker.tick:SetColorTexture(1, 1, 1, 0.5)
            timeline.bosses[i] = marker
        end

        if not Atlas(marker.icon, "worldquest-icon-boss") then
            marker.icon:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
        end
        ns.ApplyFont(marker.label, -3, "")
        marker.label:SetText(SecondsToClock(boss[1]))
        marker.label:SetTextColor(0.86, 0.87, 0.90)

        -- Perto do fim do eixo o rótulo à direita sai do painel, e ainda esbarra no baú.
        -- Vira para a esquerda do ícone; é o único lado que sobra.
        local at = X(boss[1])
        marker.label:ClearAllPoints()
        if at > width - 56 then
            marker.label:SetPoint("RIGHT", marker, "LEFT", -1, 0)
            marker.label:SetJustifyH("RIGHT")
        else
            marker.label:SetPoint("LEFT", marker, "RIGHT", 1, 0)
            marker.label:SetJustifyH("LEFT")
        end

        marker:ClearAllPoints()
        marker:SetPoint("BOTTOM", timeline.rail, "TOPLEFT", at, 3)
        marker:Show()
    end

    -- Mortes, abaixo do trilho: são má notícia e não devem competir com os bosses.
    timeline.deaths = timeline.deaths or {}
    for _, mark in ipairs(timeline.deaths) do mark:Hide() end

    for i, death in ipairs(context.deathMarks or {}) do
        local mark = timeline.deaths[i]
        if not mark then
            mark = timeline:CreateTexture(nil, "OVERLAY")
            mark:SetSize(DEATH_ICON, DEATH_ICON)
            timeline.deaths[i] = mark
        end
        -- ⚑ O ÍCONE DA CLASSE QUANDO SE SABE QUAL FOI, a caveira quando não se sabe. A classe só
        -- chega aqui se `AttachDeathClasses` tiver conseguido provar a correspondência (as duas
        -- listas com o mesmo tamanho) — então `death[2]` presente já significa "isto está certo".
        --
        -- A arte é a folha de classes do próprio jogo, recortada por `CLASS_ICON_TCOORDS`, que é
        -- como o retrato da linha já faz neste arquivo. Sem inventar atlas: o recorte vem da mesma
        -- tabela que a Blizzard usa na ficha do personagem.
        local classe = death[2]
        local coords = classe and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classe]
        if coords then
            mark:SetTexture("Interface\\WorldStateFrame\\ICONS-CLASSES")
            mark:SetTexCoord(unpack(coords))
        else
            -- `SetTexCoord` fica pegajoso: uma textura que já foi ícone de classe guarda o
            -- recorte, e o atlas seguinte sairia cortado no mesmo quadrado. Desfaz antes.
            mark:SetTexCoord(0, 1, 0, 1)
            if not Atlas(mark, "BossBanner-SkullCircle") then
                mark:SetColorTexture(0.85, 0.25, 0.25, 0.9)
            end
        end
        mark:ClearAllPoints()
        mark:SetPoint("TOP", timeline.rail, "BOTTOMLEFT", X(death[1]), -3)
        mark:Show()
    end

    -- Baú do fim da corrida: verde se deu no tempo, vermelho se estourou.
    local chest = timeline.chest
    local onTime = context.onTime
    if not Atlas(chest, onTime and "gficon-chest-evergreen-greatvault-collect"
        or "gficon-chest-evergreen-greatvault-complete") then
        chest:SetTexture("Interface\\Icons\\INV_Box_01")
    end
    chest:ClearAllPoints()
    chest:SetPoint("CENTER", timeline.rail, "LEFT", X(total), 0)

    -- Eixo: uma marca a cada 5 minutos, mais o fim.
    timeline.ticks = timeline.ticks or {}
    for _, tick in ipairs(timeline.ticks) do tick:Hide() end

    local step = 300
    if span > 2400 then step = 600 end
    local count = 0
    local at = 0
    while at <= span do
        count = count + 1
        local tick = timeline.ticks[count]
        if not tick then
            tick = CreateFrame("Frame", nil, timeline)
            tick:SetSize(1, 4)
            tick.line = tick:CreateTexture(nil, "ARTWORK")
            tick.line:SetAllPoints()
            tick.line:SetColorTexture(1, 1, 1, 0.25)
            tick.label = tick:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            tick.label:SetPoint("TOP", tick, "BOTTOM", 0, -1)
            timeline.ticks[count] = tick
        end
        ns.ApplyFont(tick.label, -4, "")
        tick.label:SetText(SecondsToClock(at))
        tick:ClearAllPoints()
        tick:SetPoint("TOP", timeline.rail, "BOTTOMLEFT", X(at), -20)
        tick:Show()
        at = at + step
    end
end

--------------------------------------------------------------------------------
-- Números do cabeçalho
--------------------------------------------------------------------------------
---Quanto tempo da corrida foi passado FORA de combate.
---
---Sai do mesmo eixo que desenha o trilho verde e vermelho, então os dois nunca podem discordar:
---o número no cabeçalho é a soma do que está pintado de vermelho embaixo.
local function OutOfCombatSeconds()
    local total = context and context.durationSeconds
    if not total or issecretvalue(total) or total <= 0 then return nil end

    local marks = context.combatTimeline
    if type(marks) ~= "table" or #marks == 0 then return nil end

    -- REGISTRO INCOMPLETO NAO VIRA NUMERO. `knownFrom > 0` e uma corrida retomada depois de um
    -- `/reload`: o addon sabe quanto a chave durou (o cronometro do mundo diz), mas so viu o
    -- combate a partir dali. Somar o resto como "fora de combate" foi o que produziu
    -- **"Fora de combate: 26:13"** numa chave de 26:13.
    --
    -- Some da tela em vez de mostrar um numero qualificado: a faixa de cima tem quatro coisas
    -- disputando espaco, e "8:12 (parcial)" pede uma explicacao que nao cabe ali. Ausencia se
    -- entende sozinha; numero errado, nao.
    local desde = context.knownFrom or 0
    if desde > 0 then return nil end

    local idle = 0
    for i = 1, #marks do
        local startAt, inCombat = marks[i][1], marks[i][2]
        local stopAt = marks[i + 1] and marks[i + 1][1] or total
        if not inCombat and stopAt > startAt then idle = idle + (stopAt - startAt) end
    end
    return idle
end

---Nível de item médio do grupo, pelos que o retrato conseguiu saber.
---
---Média só do que se sabe, e nil quando não se sabe de ninguém. Contar quem não foi
---inspecionado como zero puxaria a média para baixo e daria um número errado com cara de certo.
local function AverageItemLevel()
    local rows = context and context.rows
    if type(rows) ~= "table" then return nil end

    local sum, count = 0, 0
    for i = 1, #rows do
        local level = rows[i].ilevel
        if level and level > 0 then
            sum = sum + level
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return sum / count
end

--------------------------------------------------------------------------------
-- Construção do painel
--------------------------------------------------------------------------------
local function CreateHeaderArt()
    -- Estrela do nível: fica FORA do frame, mordendo a borda de cima. É ela que dá o ar de
    -- painel oficial; sem ela o cabeçalho é só uma faixa escura com texto dourado.
    frame.star = frame:CreateTexture(nil, "OVERLAY")
    frame.star:SetSize(STAR_SIZE, STAR_SIZE)
    frame.star:SetPoint("CENTER", frame, "TOP", 0, STAR_OFFSET_Y)
    if not Atlas(frame.star, "ChallengeMode-SpikeyStar") then
        frame.star:Hide()
    end

    frame.level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.level:SetPoint("CENTER", frame.star, "CENTER", 0, 0)
    frame.level:SetTextColor(1, 0.94, 0.72)

    local function Filigree(atlas, w, h, point, relPoint, x, y)
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetSize(w, h)
        tex:SetPoint(point, frame, relPoint, x, y)
        if not Atlas(tex, atlas) then tex:Hide() end
        return tex
    end

    -- Grafia `Fillagree` com dois L: é assim no cliente. `Filigree` some sem avisar.
    frame.filigreeLeft = Filigree("BossBanner-LeftFillagree",
        FILIGREE_SIDE_W, FILIGREE_SIDE_H, "BOTTOM", "TOP", -FILIGREE_SIDE_X, -2)
    frame.filigreeRight = Filigree("BossBanner-RightFillagree",
        FILIGREE_SIDE_W, FILIGREE_SIDE_H, "BOTTOM", "TOP", FILIGREE_SIDE_X, -2)
    frame.filigreeBottom = Filigree("BossBanner-BottomFillagree",
        FILIGREE_BOTTOM_W, FILIGREE_BOTTOM_H, "BOTTOM", "BOTTOM", 0, FILIGREE_BOTTOM_Y)
end

local function CreateTimeline()
    timeline = CreateFrame("Frame", nil, frame)
    -- 63 do fundo: o eixo do Details fica em −385 num painel de 452 e tem 4px de altura
    -- (`activityFrameY` e `activityFrame:SetHeight(4)`, scoreboard.lua:136 e :851).
    timeline:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE + LINE_INSET * 2, 63)
    timeline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE - LINE_INSET * 2 - 1, 63)
    timeline:SetHeight(RAIL_HEIGHT)

    -- Os dois gradientes são o que faz o eixo parecer arte em vez de um risco: escuro
    -- descendo por cima e subindo por baixo, com o trilho no meio.
    timeline.glowTop = timeline:CreateTexture(nil, "BACKGROUND")
    timeline.glowTop:SetPoint("BOTTOMLEFT", timeline, "TOPLEFT", 0, 0)
    timeline.glowTop:SetPoint("BOTTOMRIGHT", timeline, "TOPRIGHT", 0, 0)
    timeline.glowTop:SetHeight(28)
    timeline.glowTop:SetColorTexture(1, 1, 1, 1)
    if timeline.glowTop.SetGradient and CreateColor then
        timeline.glowTop:SetGradient("VERTICAL",
            CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
    else
        timeline.glowTop:SetColorTexture(0, 0, 0, 0.3)
    end

    timeline.rail = timeline:CreateTexture(nil, "BORDER")
    timeline.rail:SetAllPoints()
    timeline.rail:SetColorTexture(0, 0, 0, 0.83)

    timeline.chest = timeline:CreateTexture(nil, "OVERLAY")
    timeline.chest:SetSize(CHEST_ICON, CHEST_ICON)
end

local function CreatePanel()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Scoreboard", UIParent, "BackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("HIGH")
    -- IN FRONT WHEN OPENED OR CLICKED (27/09). Every Rocket window shares the HIGH strata, and
    -- inside a strata the order is the frame LEVEL: without this, the rows of a window opened
    -- earlier (deeper children, higher levels) drew over the background of the one opened on
    -- top -- the user's print had RocketMount's list showing through RocketSwap. `toplevel`
    -- raises on click; `Raise` on show. Same pair as Chattynator (`CustomiseDialog/Main.lua:841,846`).
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self) self:Raise() end)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    -- Painel de leitura, não overlay: aqui o fundo é obrigatório, senão o texto disputa com o
    -- cenário. `panelAlpha` é o valor que a skin reserva para isso.
    frame:SetBackdropColor(0.035, 0.035, 0.05, ns.Skin.scoreboardAlpha)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()

    frame.art = frame:CreateTexture(nil, "BACKGROUND")
    frame.art:SetPoint("TOPLEFT", 1, -1)
    frame.art:SetPoint("BOTTOMRIGHT", -1, 1)

    frame.headerArt = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.headerArt:SetPoint("TOPLEFT", 1, -1)
    frame.headerArt:SetPoint("TOPRIGHT", -1, -1)
    frame.headerArt:SetHeight(HEADER_HEIGHT - 6)
    ns.ApplyHeaderArt(frame.headerArt)
    frame.headerArt:SetAlpha(0.9)

    CreateHeaderArt()

    -- ⚑ A PILHA CENTRAL VIROU DUAS COLUNAS, e a medição no print de 10/09 é o motivo.
    --
    -- O Details empilha três coisas no centro — título (-12, corpo 20), tempo (-8, corpo 16) e,
    -- abaixo, o resultado. Copiamos as medidas dele, mas **não a fonte**: a nossa sai de
    -- `ns.Skin.scoreboardFontSize` com a família que o jogador escolheu, e ela renderiza mais
    -- alta. A pilha não cabia nos 65 do cabeçalho, e o print mostra exatamente isso:
    --
    --     faixa de cabeçalho de coluna ... y 80 a 106
    --     "no tempo +1" .................. y 93 a 99   ← dentro dela
    --
    -- Espremer os vãos consertaria um pixel e deixaria a mesma armadilha para o próximo que
    -- mexesse no corpo da fonte. **Tirar do eixo resolve por construção**: o centro fica só com o
    -- título, e o tempo — que é o número principal de uma corrida — vai para a DIREITA, com o
    -- resultado embaixo dele. Foi o que o usuário pediu (*"o tempo da dungeon não está em um lugar
    -- bom, pode ficar melhor alinhado na direita"*), e é também a saída certa: a esquerda já é uma
    -- faixa de contexto (fora de combate, ilvl, mortes), então a direita era o vazio da tela.
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, TITLE_Y)
    frame.title:SetTextColor(1, 0.82, 0)

    -- O TEMPO, à direita, alinhado pela borda. Abaixo do botão de fechar para não disputar com
    -- ele, e com a mesma margem lateral do resto do painel.
    frame.clock = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.clock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CLOCK_RIGHT_INSET, CLOCK_Y)
    frame.clock:SetJustifyH("RIGHT")

    -- E o resultado logo abaixo dele, na mesma borda: os dois formam UM bloco, e o olho lê
    -- "30:47 / no tempo +1" como uma coisa só, que é o que eles são.
    frame.result = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.result:SetPoint("TOPRIGHT", frame.clock, "BOTTOMRIGHT", 0, RESULT_GAP)
    frame.result:SetJustifyH("RIGHT")

    -- CANTO SUPERIOR ESQUERDO: o relógio de tempo FORA de combate e o nível de item médio do
    -- grupo (`scoreboard.lua:443-470`). São as duas linhas de contexto da corrida que o Details
    -- põe ali, e as duas respondem perguntas que o resto do painel não responde: quanto tempo se
    -- gastou andando, e com que equipamento o grupo entrou.
    frame.idleIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.idleIcon:SetSize(24, 24)
    frame.idleIcon:SetPoint("TOPLEFT", SIDE, -5)
    -- `auctionhouse-icon-clock` nao e um relogio escolhido no olho: e o que a Blizzard usa em
    -- tres lugares (`Blizzard_AuctionHouseUtil.lua:8`, `CovenantMissionTemplates.xml:588`,
    -- `Blizzard_ProfessionsTemplates.lua:114`), conferido na fonte do 12.1.0.
    if not Atlas(frame.idleIcon, "auctionhouse-icon-clock") then
        frame.idleIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    end
    frame.idleIcon:SetVertexColor(0.75, 0.75, 0.78)

    frame.idle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.idle:SetPoint("LEFT", frame.idleIcon, "RIGHT", 6, -3)
    frame.idle:SetJustifyH("LEFT")
    frame.idle:SetTextColor(0.75, 0.75, 0.78)

    frame.ilvlIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.ilvlIcon:SetSize(20, 20)
    frame.ilvlIcon:SetPoint("LEFT", frame.idleIcon, "RIGHT", 260, 0)
    -- `bags-icon-equipment` (`ContainerFrame.lua:219`). O Details usa um PNG proprio aqui; a
    -- arte equivalente que o jogo tem e o icone de equipamento das bolsas.
    if not Atlas(frame.ilvlIcon, "bags-icon-equipment") then
        frame.ilvlIcon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
    end
    frame.ilvlIcon:SetVertexColor(0.9, 0.9, 0.9)
    frame.ilvlIcon:SetAlpha(0.834)

    frame.ilvl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.ilvl:SetPoint("LEFT", frame.ilvlIcon, "RIGHT", 6, 0)
    frame.ilvl:SetJustifyH("LEFT")

    -- Afixos: logo abaixo do relógio, pequenos. O Details não os mostra — mas ele também não
    -- mostra o resultado da chave em texto, e nós mostramos: são as duas coisas que o painel
    -- ganhou antes desta cópia e que tirar seria PERDER informação, não copiar.
    frame.affixes = {}
    for i = 1, 4 do
        local icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", SIDE + (i - 1) * 21, -34)
        icon:Hide()
        frame.affixes[i] = icon
    end

    -- A CONTAGEM DE MORTES SOBREVIVEU À CÓPIA, e vale dizer por quê: o número de mortes virou
    -- coluna (como no Details), mas o **tempo perdido com elas** — o `(-00:10)` — não existe no
    -- painel dele, e é o dado que responde "as mortes custaram a chave?". Copiar não é apagar o
    -- que a nossa tela já respondia melhor.
    --
    -- Ela vai para a direita do nível de item, que é o espaço livre da faixa de cima.
    frame.deaths = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.deaths:SetPoint("LEFT", frame.ilvl, "RIGHT", 24, 0)
    frame.deaths:SetJustifyH("LEFT")

    -- Glifo chapado, não botão com moldura: a família de ícones do addon é plana.
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -8, -8)
    local closeTex = close:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    if not Atlas(closeTex, "common-icon-redx") then
        closeTex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    end
    close:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    close:SetScript("OnClick", function() frame:Hide() end)

    -- A dica (e o aviso de simulação) vai no CABEÇALHO, não no rodapé: embaixo ela disputaria
    -- espaço com o eixo de tempo, e o eixo é informação, a dica é só dica.
    -- ⚑ O RODAPÉ FOI PARA O RODAPÉ, e isso é conserto de uma colisão que eu criei na 0.85.0.
    --
    -- Ele estava em `TOPRIGHT, -10, -38` — dentro do CABEÇALHO, apesar do nome — e era o único
    -- ocupante da direita ali. Quando o tempo da corrida mudou para esse canto, os dois passaram a
    -- disputar o mesmo espaço: o relato foi *"tem texto embaixo"*, e a conta bate — o resultado
    -- ("no tempo +1") fecha por volta de −39 e ele começava em −38.
    --
    -- O lugar certo é embaixo, e por dois motivos além de não colidir: é o que o nome dele diz, e
    -- o que ele escreve — *"há 20 min"* ou a dica de arrastar — é a informação de menor prioridade
    -- da tela. O eixo do tempo fica a 63 do fundo, então há faixa livre abaixo dele.
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE - 6, 6)
    frame.footer:SetJustifyH("RIGHT")

    CreateTimeline()

    rows = {}
    return frame
end

--------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------
local function DrawHeader()
    -- Os corpos do Details, aplicados pela escada do addon para o seletor de fonte continuar
    -- valendo: título 20, tempo 16, relógio de ocioso 11.
    ns.ApplyScoreboardFont(frame.title, TITLE_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.clock, CLOCK_SIZE - ns.Skin.scoreboardFontSize, "")
    -- O RESULTADO FICAVA DE FORA desta lista, e por isso era o único texto do cabeçalho que não
    -- seguia a fonte escolhida pelo jogador — ficava no `GameFontNormalSmall` do template. Passou
    -- despercebido porque "não seguir a fonte" não parece defeito, parece escolha.
    ns.ApplyScoreboardFont(frame.result, RESULT_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.idle, IDLE_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.ilvl, IDLE_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.deaths, IDLE_SIZE - ns.Skin.scoreboardFontSize, "")

    frame.title:SetText(context.title or L["Dungeon"])

    -- A estrela é o selo de "que conteúdo é este". Em Mítico+ carrega o nível da pedra; em
    -- raide, a inicial da dificuldade (N / H / M), que é a informação equivalente — sem ela o
    -- placar de raide não diz se aquele boss caiu no normal ou no mítico.
    local badge = context.level and tostring(context.level) or context.badge
    if badge and badge ~= "" then
        frame.level:SetText(badge)
        -- Dois caracteres ("LFR", "+2") não cabem no mesmo corpo de um número de dois dígitos.
        frame.level:SetFont(ns.Skin.font, #badge > 2 and 20 or 28, "OUTLINE")
        frame.level:Show()
        if frame.star:GetTexture() then frame.star:Show() end
    else
        frame.level:SetText("")
        frame.star:Hide()
    end

    local duration = context.durationSeconds
    if duration and not issecretvalue(duration) then
        frame.clock:SetText(SecondsToClock(duration))
        frame.clock:SetTextColor(1, 0.94, 0.72)
    else
        frame.clock:SetText("--:--")
    end

    -- Resultado: sem atlas de "+1/+2/+3" no cliente, o painel oficial usa texto — e nós também.
    if context.onTime == nil then
        frame.result:SetText(context.result or "")
    elseif context.onTime then
        local upgrades = context.upgrades or 1
        frame.result:SetText("|cff40d878" .. L["on time"]
            .. (upgrades > 0 and ("  +" .. upgrades) or "") .. "|r")
    else
        frame.result:SetText("|cffe06060" .. L["over time"] .. "|r")
    end

    -- TEMPO FORA DE COMBATE: soma dos trechos vermelhos do eixo. É o número que o Details
    -- mostra como *"Not in combat"*, e ele responde a pergunta que a duração sozinha não
    -- responde — quanto da corrida foi andando.
    local idle = OutOfCombatSeconds()
    frame.idle:SetShown(idle ~= nil)
    if idle then
        frame.idle:SetText(format(L["Not in combat: %s"], SecondsToClock(idle)))
    end

    -- NÍVEL DE ITEM MÉDIO do grupo, do próprio retrato. Sem nenhum conhecido, some: um "0" ali
    -- seria lido como um grupo pelado em vez de "não deu para inspecionar".
    local average = AverageItemLevel()
    frame.ilvlIcon:SetShown(average ~= nil)
    frame.ilvl:SetShown(average ~= nil)
    frame.ilvl:SetText(average and tostring(math.floor(average + 0.5)) or "")

    local deaths = context.deaths
    if deaths and not issecretvalue(deaths) then
        local text = format(L["%d deaths"], deaths)
        local lost = context.timeLostToDeaths
        if lost and lost > 0 then
            text = text .. "  (-" .. SecondsToClock(lost) .. ")"
        end
        frame.deaths:SetText(text)
    else
        frame.deaths:SetText("")
    end

    for i = 1, #frame.affixes do
        local icon = frame.affixes[i]
        local id = context.affixes and context.affixes[i]
        local shown = false
        if id and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
            local ok, _, _, fileID = pcall(C_ChallengeMode.GetAffixInfo, id)
            if ok and fileID then
                icon:SetTexture(fileID)
                icon:Show()
                shown = true
            end
        end
        if not shown then icon:Hide() end
    end

    ApplyBackdropArt(frame.art, context.mapID)
end

--------------------------------------------------------------------------------
-- Desenho de uma célula, por tipo
--------------------------------------------------------------------------------
-- `GetMicroIconForRole` (`Blizzard_SharedXMLBase/TextureUtil.lua:193`) é a global que o próprio
-- Details usa aqui, e ela **levanta erro** para função desconhecida — daí a tabela ao lado dela
-- em vez de uma chamada direta com o que vier do retrato.
local ROLE_MICRO_ATLAS = {
    TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
    HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
    DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
}

local CellPainters = {}

---Retrato: o rosto real de quem ainda está no grupo; o círculo da classe para o resto.
---
---É a mesma degradação do Details (`scoreboard_layout.lua:320-336`), e ela importa porque o
---placar guardado é aberto dias depois — quando `SetPortraitTexture` não tem mais unidade para
---consultar e a única identidade que sobrou é a classe.
function CellPainters.portrait(cell, entry)
    local row = entry.row or {}
    local class = row.classFilename

    local drew = false
    local name = row.name
    if name and not issecretvalue(name) and UnitExists and UnitExists(name) and SetPortraitTexture then
        drew = pcall(SetPortraitTexture, cell.portrait, name)
        if drew then cell.portrait:SetTexCoord(0, 1, 0, 1) end
    end

    if not drew or not cell.portrait:GetTexture() then
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            cell.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            cell.portrait:SetTexCoord(unpack(coords))
        else
            cell.portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
            cell.portrait:SetTexCoord(0, 1, 0, 1)
        end
    end

    local role = row.role
    if role and ROLE_MICRO_ATLAS[role] and Atlas(cell.role, ROLE_MICRO_ATLAS[role]) then
        cell.role:Show()
    else
        cell.role:Hide()
    end

    -- Nível de item na cor da classe, como no Details (`:344`). Sem o número, um traço: a
    -- placa escura fica, porque o buraco na coluna é pior que o traço.
    local ilevel = row.ilevel
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    cell.ilvl:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    cell.ilvl:SetText(ilevel and ilevel > 0 and tostring(math.floor(ilevel + 0.5)) or "-")
end

function CellPainters.spec(cell, entry)
    ns.ApplyRowIcon(cell.icon, cell.iconClass, entry.source)
end

function CellPainters.name(cell, entry)
    local row = entry.row or {}
    -- COR DE CLASSE NO NOME, que é o oposto da regra da janela de combate — lá a classe colore
    -- a BARRA e o texto fica branco, porque texto na cor da classe SOME dentro de uma barra da
    -- mesma cor. Aqui não há barra: o Details pinta o nome (`scoreboard_layout.lua:384`) e o
    -- fundo é neutro, então a colisão que motivou aquela regra não existe.
    local color = row.classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[row.classFilename]
    cell.text:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    cell.text:SetText(ns.SplitName(row.name) or row.name or "?")
end

function CellPainters.keystone(cell, entry)
    local row = entry.row or {}
    local level = row.keystoneLevel
    local mapID = row.keystoneMapID

    local drew = false
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local ok, _, _, _, texture = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok and texture then
            cell.icon:SetTexture(texture)
            drew = true
        end
    end

    -- SEM PEDRA, A CÉLULA FICA VAZIA — e não com um ícone genérico apagado, que é o que o
    -- Details faz. O motivo é que aqui a ausência tem duas causas diferentes e indistinguíveis
    -- na tela: o jogador pode não ter pedra, ou o RocketMeter pode não ter como saber
    -- (ver `KeystoneFor`). Desenhar um ícone nos dois casos afirmaria a primeira.
    cell.icon:SetShown(drew)
    cell.levelBg:SetShown(drew and level ~= nil and level > 0)
    if drew and level and level > 0 then
        cell.level:SetText("+" .. level)
        cell.level:Show()
    else
        cell.level:Hide()
    end
end

function CellPainters.score(cell, entry, index)
    cell.text:SetText(ScoreText(entry, index))
    cell.text:SetTextColor(1, 1, 1)
end

function CellPainters.loot(cell, entry)
    local link = entry.row and entry.row.loot
    if not link or link == "" or not Item or not Item.CreateFromItemLink then
        cell.icon:Hide(); cell.border:Hide(); cell.ilvlBg:Hide(); cell.ilvl:Hide()
        return
    end

    -- `ContinueOnItemLoad` PORQUE O ITEM PODE NÃO ESTAR EM CACHE. Ler ícone e qualidade na hora
    -- devolve nil para item que o cliente ainda não baixou, e o resultado é um quadrado vazio
    -- que só se conserta reabrindo o painel — que é como este defeito apareceria.
    local ok, item = pcall(Item.CreateFromItemLink, Item, link)
    if not ok or not item then
        cell.icon:Hide(); cell.border:Hide(); cell.ilvlBg:Hide(); cell.ilvl:Hide()
        return
    end

    item:ContinueOnItemLoad(function()
        local quality = item:GetItemQuality()
        cell.icon:SetTexture(item:GetItemIcon())
        cell.icon:Show()
        cell.ilvl:SetText(item:GetCurrentItemLevel() or "")
        cell.ilvl:Show()
        cell.ilvlBg:Show()

        local atlas = LOOT_BORDER_BY_QUALITY and LOOT_BORDER_BY_QUALITY[quality]
        if atlas and Atlas(cell.border, atlas) then
            cell.border:Show()
        else
            cell.border:Hide()
        end
    end)
end

function CellPainters.value(cell, entry, index)
    ns.SetCellText(cell.text, entry.values[index], columns[index].key)

    local best = entry.best and entry.best[index]
    -- `standout_color` do Details (`start.lua:60`): {230, 204, 128}/255. É creme, não dourado —
    -- e a skill do workspace explica por que isso importa: creme não colide com cor de classe
    -- nenhuma, então ele destaca sem ser lido como "este é ladino".
    if best and ns.db.highlightBest ~= false then
        cell.text:SetTextColor(230 / 255, 204 / 255, 128 / 255)
    else
        cell.text:SetTextColor(1, 1, 1)
    end
end

local function DrawRows(list, rowCount)
    for i = 1, rowCount do
        local row = BuildRow(i)
        local entry = list[i]

        if not entry then
            row:Hide()
        else
            -- Fundo alternado, e só ele. A faixa de classe no rodapé da linha saiu: ela era
            -- nossa, o Details não a tem, e o pedido foi copiar. A identidade da classe
            -- continua em três lugares na mesma linha — retrato, ícone e cor do nome.
            row.bg:SetColorTexture(unpack(i % 2 == 1 and ROW_TINT_ODD or ROW_TINT_EVEN))

            for c = 1, #columns do
                local cell = row.cells[c]
                local painter = CellPainters[cell.kind]
                if painter then painter(cell, entry, c) end
            end

            row:Show()
        end
    end

    for i = rowCount + 1, #rows do
        rows[i]:Hide()
    end
end

---As medidas do placar, para o teste poder conferir a cópia contra a fonte.
---
---O que se trava com isto NÃO é "ficou bonito" — é que os números continuam sendo os do
---Details. Uma refatoração que mexa em qualquer um deles passa a reprovar, e é para isso que
---esta porta existe: o pedido foi copiar, e cópia sem conferência vira lembrança.
function Scoreboard.__frame()
    return frame
end

function Scoreboard.DebugLayout()
    local widths = {}
    for c = 1, #ALL_COLUMNS do
        widths[ALL_COLUMNS[c].key] = ALL_COLUMNS[c].width
    end
    return {
        rowHeight = ROW_HEIGHT,
        rowSpacing = ROW_SPACING,
        lineInset = LINE_INSET,
        side = SIDE,
        headerHeight = HEADER_HEIGHT,
        colheadHeight = COLHEAD_HEIGHT,
        colheadLine = COLHEAD_LINE,
        colPadding = COL_PADDING,
        footerHeight = FOOTER_HEIGHT,
        titleY = TITLE_Y,
        titleSize = TITLE_SIZE,
        clockSize = CLOCK_SIZE,
        -- O corpo da faixa de contexto (fora de combate, ilvl, mortes). Entra porque o que o
        -- harness trava agora e a HIERARQUIA entre os tres, e nao os numeros de cada um.
        idleSize = IDLE_SIZE,
        -- E o que o harness precisa para conferir que a pilha CABE na faixa de cabecalho, que e
        -- o defeito que o print de 10/09 mostrou: "no tempo +1" desenhado dentro da faixa das
        -- colunas. Sem estes tres, so daria para afirmar sobre corpos de fonte soltos.
        clockY = CLOCK_Y,
        resultGap = RESULT_GAP,
        resultSize = RESULT_SIZE,
        widths = widths,
        order = (function()
            local out = {}
            for c = 1, #ALL_COLUMNS do out[c] = ALL_COLUMNS[c].key end
            return out
        end)(),
        panelWidth = (function()
            local total = 0
            for c = 1, #ALL_COLUMNS do total = total + ALL_COLUMNS[c].width + COL_PADDING end
            return SIDE * 2 + total
        end)(),
        panelHeight = HEADER_HEIGHT + COLHEAD_HEIGHT + 5 * (ROW_HEIGHT + ROW_SPACING) + FOOTER_HEIGHT,

        -- Os TRES conjuntos que precisam fechar entre si: cada `render` declarado numa coluna
        -- tem que ter um construtor e um pintor. Foi a falta desse fechamento que deixou a
        -- coluna de pontuacao sem construtor e o painel sem corpo (print de 07/09 20:22).
        renders = (function()
            local vistos, out = {}, {}
            for c = 1, #ALL_COLUMNS do
                local kind = ALL_COLUMNS[c].render or "value"
                if not vistos[kind] then
                    vistos[kind] = true
                    out[#out + 1] = kind
                end
            end
            return out
        end)(),
        builders = (function()
            local out = {}
            for kind in pairs(CellBuilders) do out[kind] = true end
            return out
        end)(),
        painters = (function()
            local out = {}
            for kind in pairs(CellPainters) do out[kind] = true end
            return out
        end)(),
    }
end

---O que a faixa de cima esta MOSTRANDO. Existe porque a diferenca entre "o numero esta certo" e
---"o numero nao devia estar ai" so se ve perguntando ao widget.
---A corrida que está na tela, para o harness afirmar sobre ela.
---
---`context` é local do arquivo e o teste do saque precisa ver a linha ANTES e DEPOIS de o item
---chegar — sem esta porta, ele teria que reabrir o painel e inferir pelo desenho, que é medir
---outra coisa.
function Scoreboard.DebugContext()
    return context
end

---A ancoragem real dos textos do cabeçalho, lida dos widgets.
---
---⚑ NÃO SÃO AS CONSTANTES DE NOVO. O defeito de 10/09 foi de ARRANJO — três textos empilhados no
---mesmo eixo, o último caindo dentro da faixa das colunas —, e um teste que só soma constantes
---continuaria passando se alguém reempilhasse tudo. Aqui se lê onde o widget ficou de fato.
function Scoreboard.DebugHeaderAnchors()
    if not frame then return nil end
    local function ancora(fs)
        if not fs or not fs.GetPoint then return nil end
        local ponto, relativo, relPonto = fs:GetPoint(1)
        return { point = ponto, relativeTo = relativo, relativePoint = relPonto }
    end
    return {
        title = ancora(frame.title),
        clock = ancora(frame.clock),
        result = ancora(frame.result),
        -- O rodapé entra aqui porque ele DISPUTAVA este espaço: enquanto estava ancorado no topo
        -- à direita, o bloco do tempo caía em cima dele. Só um teste que veja os dois pega isso.
        footer = ancora(frame.footer),
        titleWidget = frame.title,
        clockWidget = frame.clock,
        clockInset = CLOCK_RIGHT_INSET,
    }
end

function Scoreboard.DebugHeader()
    if not frame then return {} end
    return {
        idleShown = frame.idle and frame.idle:IsShown() and true or false,
        idleText = frame.idle and frame.idle:GetText() or nil,
        ilvlShown = frame.ilvl and frame.ilvl:IsShown() and true or false,
    }
end

---As celulas desenhadas de uma linha, para o teste poder afirmar que ela existe de verdade.
function Scoreboard.DebugRow(index)
    local row = rows and rows[index]
    return row and row.cells or nil
end

function Scoreboard.Draw()
    if not frame or not context then return end

    -- Antes de tudo: quais colunas esta corrida tem. Todo o resto do desenho lê de `columns`.
    columns = ComputeColumns()

    local rowCount = context.rowCount or 5
    local ceiling = MaxRowsOnScreen()
    if rowCount > ceiling then rowCount = ceiling end

    local list = CollectRows(rowCount) or {}

    -- Ordenação local: para coluna própria sempre, e para a simulação em qualquer coluna
    -- (não há API para pedir ordem a dados inventados).
    local sortIndex
    for c = 1, #columns do
        if columns[c].key == sortBy then sortIndex = c end
    end
    if sortIndex and (context.demo or columns[sortIndex].custom) then
        SortRows(list, sortIndex)
    end

    if #list > 0 and #list < rowCount then rowCount = #list end
    if rowCount < 1 then rowCount = 1 end

    frame:SetSize(PanelWidth(), PanelHeight(rowCount))

    DrawHeader()
    BuildColumnHeader()
    DrawRows(list, rowCount)

    if context.demo then
        frame.footer:SetText(L["Simulation — invented data."])
        frame.footer:SetTextColor(1, 0.72, 0.2)
    else
        -- "há 2 dias" importa quando o painel mostra corrida guardada: sem isso não dá para
        -- saber se aquilo é de agora ou da semana passada.
        local age = RunAge(context)
        frame.footer:SetText(age or L["Click a column header to sort. Drag to move."])
        frame.footer:SetTextColor(0.5, 0.5, 0.5)
    end

    DrawTimeline()
end

---Envelope de segurança: um erro no laço de desenho não pode derrubar o painel inteiro sem
---deixar pista. Mesma defesa que a janela usa.
---
---É **função pública** porque o clique no cabeçalho de coluna precisa dela: chamar `Draw()` cru
---de dentro de um `OnClick` faz o erro sumir em silêncio quando `scriptErrors` está desligado
---(o padrão do jogo), e aí o usuário vê a coluna trocar de cor e as linhas não mudarem.
function Scoreboard.Refresh()
    -- ⚑ NAO REENTRA. Ver a nota de `desenhando`: um desenho disparado de dentro de outro reescreve
    -- os caches no meio do uso, e o erro sai em outro lugar, com outra cara.
    if desenhando then return end
    desenhando = true

    local ok, err = pcall(Scoreboard.Draw)

    desenhando = false

    if not ok then
        Scoreboard.lastError = err
        ns.Print(L["error while drawing:"] .. " " .. tostring(err))
    end
end

local SafeDraw = Scoreboard.Refresh

function Scoreboard.Show(newContext)
    -- Opened by hand (or by the chest): nothing is waiting any more. Through the table: the wait
    -- is declared further down the file, and a local named here would be a nil global.
    if Scoreboard.CancelChestWait then Scoreboard.CancelChestWait() end
    context = newContext or context
    if not context then
        ns.Print(L["no run recorded in this session yet."])
        return
    end

    CreatePanel()
    SafeDraw()
    frame:Show()
end

function Scoreboard.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end

    -- Depois de um `/reload` não há corrida em memória, mas pode haver em disco. Sem isto o
    -- `/rm score` respondia "nenhuma corrida registrada" com a corrida gravada ali do lado.
    if not context and Scoreboard.ShowMostRecent() then return end

    Scoreboard.Show()
end

function Scoreboard.GetLastError()
    return Scoreboard.lastError
end

--------------------------------------------------------------------------------
-- Simulação
--------------------------------------------------------------------------------
---Abre o placar com uma corrida inventada.
---
---Não toca em nada real: `ns.Demo.Run` devolve uma tabela solta, e ela **não** é gravada em
---disco. Existe para ver o painel sem rodar uma masmorra — testar aparência de um placar de
---fim de M+ custava meia hora de jogo por ajuste.
function Scoreboard.ShowDemo()
    if not ns.Demo then
        ns.Print(L["restart the client: the demo module was not loaded yet."])
        return
    end
    Scoreboard.Show(ns.Demo.Run())
end

---Abre a última corrida guardada de um tipo ("mplus" ou "raid").
function Scoreboard.ShowLast(kind)
    local run = Scoreboard.GetRun(kind)
    if not run then
        ns.Print(kind == "raid" and L["no raid encounter recorded yet."]
            or L["no Mythic+ run recorded yet."])
        return
    end
    Scoreboard.Show(run)
end

---Abre a mais recente entre as duas guardadas.
function Scoreboard.ShowMostRecent()
    local mplus, raid = Scoreboard.GetRun("mplus"), Scoreboard.GetRun("raid")
    if mplus and raid then
        local a, b = mplus.recordedAt or 0, raid.recordedAt or 0
        Scoreboard.Show(a >= b and mplus or raid)
        return true
    end
    if mplus or raid then
        Scoreboard.Show(mplus or raid)
        return true
    end
    return false
end

function Scoreboard.HasRun(kind)
    return Scoreboard.GetRun(kind) ~= nil
end

---Captura a corrida que acabou, guarda em disco e mostra.
---
---A captura vai por `ns.RunWhenSafe`: em combate os números da sessão são secret e o retrato
---sairia vazio. A fila do `Core.lua` já drena no `PLAYER_REGEN_ENABLED`, então o placar de um
---boss de raide morto com adds ainda vivos aparece quando a luta realmente acaba — que é
---também quando ele é útil.
---A guarda das classes de morte, para o harness exercitar os dois ramos.
---
---Gancho declarado, no estilo do `Picker.__probe`: ela roda dentro da captura, e sem esta porta o
---teste do ramo "as contagens discordam" teria que forjar uma corrida inteira para chegar nela.
Scoreboard.__attachDeathClasses = AttachDeathClasses

---A janela em que o placar continua reencostando as colunas que vêm de fora.
---
---⚑ ELA EXISTE PORQUE NÃO HÁ EVENTO PARA "O GRUPO TERMINOU DE ABRIR O BAÚ". A pedra nova de cada
---um chega quando ele abre; a pontuação, quando o servidor recalcula. O aviso da LibOpenRaid cobre
---a pedra de quem roda addon compatível — esta janela cobre o resto, e cobre também o caso de a
---lib não estar presente.
---
---Dois minutos, de 5 em 5 segundos, e **para assim que não falta mais nada**: enquanto houver
---linha sem pedra ou sem saque continua tentando; completou, encerra. Assim o custo é do caso
---incompleto, e não de toda corrida.
local JANELA_EXTERNA_SEGUNDOS = 120
local JANELA_EXTERNA_PASSO = 5

local function ReencostarAteCompletar(restante)
    if not context or type(context.rows) ~= "table" then return end

    pcall(Scoreboard.RefreshExternalColumns)

    local falta = false
    for _, row in ipairs(context.rows) do
        if row.keystoneLevel == nil or row.loot == nil or row.ilevel == nil then
            falta = true
            break
        end
    end

    if not falta then
        if ns.Log then ns.Log.Add("placar", { externas = "completou" }) end
        return
    end

    restante = restante - JANELA_EXTERNA_PASSO
    if restante <= 0 then
        if ns.Log then
            ns.Log.Add("placar", { externas = "prazo esgotado; alguma linha ficou sem pedra ou saque" })
        end
        return
    end

    C_Timer.After(JANELA_EXTERNA_PASSO, function() ReencostarAteCompletar(restante) end)
end

local function Desde()
    local t0 = ns.scoreboardClock
    if not t0 or not GetTime then return nil end
    return math.floor((GetTime() - t0) * 10 + 0.5) / 10
end

--------------------------------------------------------------------------------
-- (!) THE KEYSTONE SCOREBOARD OPENS WHEN THE CHEST IS LOOTED, LIKE DETAILS (26/09)
--
-- The user: *"ele tem um delay para mostrar o scoreboard e mostra certinhos os itens e as keystones
-- dos outros jogadores, isso que precisa melhorar"*. Ours opened 1.5 s after the key ended, before
-- anyone had opened the chest -- so there was no loot and no NEW key yet for anybody.
-- Details_MythicPlus captures at the end but SHOWS on `LOOT_CLOSED` (its default,
-- `start.lua:22`; `scoreboard.lua:273-292`): by the time the player closes the chest the loot has
-- been handed out and every key has changed and been announced. Same here: the run becomes the
-- current one at once (so loot and keys stitch into it), and the panel appears on the first
-- LOOT_CLOSED; leaving the instance first cancels, as in Details (`/rm score` still opens it).
--------------------------------------------------------------------------------
local pendente               -- the run waiting for the chest
local esperaBau = CreateFrame("Frame")

local function IniciarReencosto()
    if ns.Party and ns.Party.RequestKeystones then pcall(ns.Party.RequestKeystones) end
    ReencostarAteCompletar(JANELA_EXTERNA_SEGUNDOS)
end

esperaBau:SetScript("OnEvent", function(self, event, isLogin, isReload)
    if event == "LOOT_CLOSED" then
        self:UnregisterAllEvents()
        local run = pendente
        pendente = nil
        if run and context == run then
            pcall(Scoreboard.RefreshExternalColumns)
            Scoreboard.Show(run)
            if ns.Log then ns.Log.Add("placar", { fase = "aberto ao fechar o bau", segundos = Desde() }) end
            IniciarReencosto()
        end
    elseif event == "PLAYER_ENTERING_WORLD" and not isLogin and not isReload then
        self:UnregisterAllEvents()
        if pendente and ns.Log then ns.Log.Add("placar", { fase = "saiu sem abrir o bau" }) end
        pendente = nil
    end
end)

---True while a finished key waits for its chest (for the harness and `/rm score`).
function Scoreboard.IsWaitingForChest() return pendente ~= nil end

function Scoreboard.CancelChestWait()
    pendente = nil
    esperaBau:UnregisterAllEvents()
end

local function CaptureAndShow(base, kind, auto)
    base.kind = kind
    if ns.Log then
        ns.Log.Add("placar", { fase = "pedido", segundos = Desde(), emCombate = InCombatLockdown() and true or false })
    end
    ns.RunWhenSafe(function()
        if ns.Log then ns.Log.Add("placar", { fase = "captura", segundos = Desde() }) end
        -- A classe de cada morte entra ANTES do retrato, para viajar junto com ele para o disco:
        -- uma corrida reaberta na semana que vem não tem mais sessão de medidor para consultar.
        pcall(AttachDeathClasses, base)

        local ok, snapshot = pcall(Scoreboard.Snapshot, base)
        if not ok or not snapshot then
            ns.Print(L["error while drawing:"] .. " " .. tostring(snapshot))
            return
        end

        Scoreboard.SaveRun(kind, snapshot)

        -- `auto == false` é a abertura pedida à mão (botão, `/rm score`): essa sempre mostra.
        -- A automática obedece à caixa do tipo de conteúdo — são duas, porque quem quer o
        -- resumo de toda chave não necessariamente quer o de todo chefe de raide.
        local wanted = kind == "mplus" and ns.db.autoScoreboardMPlus or ns.db.autoScoreboardRaid
        -- A KEY, opened by itself: wait for the chest (see above). The run is the current one
        -- already, so what arrives before the panel stitches into it.
        if kind == "mplus" and auto ~= false and wanted then
            context = snapshot
            pendente = snapshot
            esperaBau:RegisterEvent("LOOT_CLOSED")
            esperaBau:RegisterEvent("PLAYER_ENTERING_WORLD")
            if ns.Log then ns.Log.Add("placar", { fase = "esperando o bau", segundos = Desde() }) end
            IniciarReencosto()
            return
        end

        if auto == false or wanted then
            pendente = nil
            Scoreboard.Show(snapshot)
            if ns.Log then ns.Log.Add("placar", { fase = "aberto", segundos = Desde() }) end
        end

        -- E a partir daqui o placar continua vivo: pedra, saque e pontuação chegam nos minutos
        -- seguintes, conforme cada um abre o baú. Só em Mítico+ — num chefe de raide essas três
        -- colunas nem existem.
        if kind == "mplus" then
            IniciarReencosto()
        end
    end)
end

--------------------------------------------------------------------------------
-- Gatilhos
--------------------------------------------------------------------------------
local function GroupRowCount()
    local size = GetNumGroupMembers()
    if not size or size < 1 then size = 1 end
    return math.min(size, MAX_ROWS)
end

function Scoreboard.OnChallengeCompleted()
    -- No 12.1.0 esta função devolve UMA TABELA (confirmado em quatro addons instalados, um
    -- deles checando `type(info) == "table"` em tempo de execução). O ramo posicional fica
    -- porque o cliente já trocou a forma antes e o custo de manter é uma linha.
    local a, level, timeMs, onTime, upgrades, _, scoreBefore, scoreAfter =
        C_ChallengeMode.GetChallengeCompletionInfo()

    local mapID = a
    if type(a) == "table" then
        mapID, level, timeMs, onTime = a.mapChallengeModeID, a.level, a.time, a.onTime
        upgrades = a.keystoneUpgradeLevels
        scoreBefore, scoreAfter = a.oldOverallDungeonScore, a.newOverallDungeonScore
    end

    -- Guarda de sanidade: depois de um /reload dentro da masmorra o cliente devolve a tabela
    -- com mapChallengeModeID = 0, e o painel abriria com uma corrida vazia. Foi assim que o
    -- Details_MythicPlus apanhou — o `if` está no código dele com o motivo escrito.
    if mapID == nil or mapID == 0 then return end

    local mapName, timeLimit
    if mapID and C_ChallengeMode.GetMapUIInfo then
        local ok, name, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok then mapName, timeLimit = name, limit end
    end

    local deaths, timeLost
    if C_ChallengeMode.GetDeathCount then
        local ok, count, lost = pcall(C_ChallengeMode.GetDeathCount)
        if ok then deaths, timeLost = count, lost end
    end

    -- Afixos: o 2º retorno de `GetActiveKeystoneInfo` é a lista de ids. Mas a chave é
    -- consumida ao completar, então essa chamada pode voltar vazia justamente aqui — daí o
    -- fallback para os afixos da semana, que vêm como lista de tabelas com campo `.id`.
    -- Nunca hardcodar id de afixo: a família do Midnight não existia antes.
    local affixes
    if C_ChallengeMode.GetActiveKeystoneInfo then
        local ok, _, ids = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok and type(ids) == "table" and #ids > 0 then affixes = ids end
    end
    if not affixes and C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
        -- `GetCurrentAffixes` devolve nil enquanto o cliente não pediu os dados ao servidor.
        -- O pedido é assíncrono: não adianta esperar aqui, mas ele deixa a lista pronta para
        -- a próxima corrida. `RequestMapInfo` é o gatilho que os outros addons usam.
        if C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end

        local ok, week = pcall(C_MythicPlus.GetCurrentAffixes)
        if ok and type(week) == "table" then
            affixes = {}
            for i = 1, #week do affixes[i] = week[i].id end
        end
    end

    local seconds
    if timeMs and not issecretvalue(timeMs) then seconds = timeMs / 1000 end

    CaptureAndShow({
        title = mapName or L["Dungeon"],
        mapID = mapID,
        level = level,
        durationSeconds = seconds,
        timeLimit = timeLimit,
        onTime = onTime,
        upgrades = upgrades,
        deaths = deaths,
        timeLostToDeaths = timeLost,
        scoreBefore = scoreBefore,
        scoreAfter = scoreAfter,
        scoreGain = (scoreBefore and scoreAfter and scoreAfter > scoreBefore)
            and (scoreAfter - scoreBefore) or nil,
        affixes = affixes,
        combatTimeline = ns.Run and ns.Run.GetCombatTimeline(),
        knownFrom = ns.Run and ns.Run.GetKnownFrom() or 0,
        bosses = ns.Run and ns.Run.GetBosses(),
        deathMarks = ns.Run and ns.Run.GetDeaths(),
        sessionType = 1,   -- geral: a corrida inteira
        rowCount = GroupRowCount(),
    }, "mplus")
end

---Selo da estrela para uma dificuldade de raide: a inicial, como o jogo faz nos seus próprios
---indicadores (N / H / M).
---
---Sai de `displayHeroic` / `displayMythic`, que são os campos que o cliente entrega justamente
---para isso — em vez de uma tabela de ids de dificuldade, que muda de expansão em expansão. A
---inicial do nome localizado é a reserva, e funciona em pt-BR (Normal, Heroico, Mítico).
local function DifficultyBadge(difficultyID)
    if not difficultyID or not GetDifficultyInfo then return nil, nil end

    local ok, name, _, _, _, displayHeroic, displayMythic = pcall(GetDifficultyInfo, difficultyID)
    if not ok then return nil, nil end

    if displayMythic then return "M", name end
    if displayHeroic then return "H", name end
    if type(name) == "string" and name ~= "" then
        return name:sub(1, 1):upper(), name
    end
    return nil, name
end

-- (!) THE SESSION BOARD (30/09). The user: *"podemos por um icone na janela do medidor que abra
-- o parcial da tela de scoreboard, sem a informação de chave e itens"*. The same board, with
-- what the meter's window shows now (the session the window is on), and without what only a
-- finished key has: keystone, score, loot, level, affixes, result, timeline. A snapshot, like
-- the others: opening again takes a new one.
function Scoreboard.ShowSession(sessionType)
    sessionType = sessionType or (ns.db and ns.db.sessionType) or 1
    local duration = ns.Data.GetDuration(sessionType)
    local seconds = (duration and not issecretvalue(duration)) and duration or nil

    -- The place: the key's dungeon when in one (with its art), else the instance or zone.
    local title, mapID
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and id and id ~= 0 and C_ChallengeMode.GetMapUIInfo then
            local okName, name = pcall(C_ChallengeMode.GetMapUIInfo, id)
            if okName and name then title, mapID = name, id end
        end
    end
    if not title and GetInstanceInfo then
        local ok, name = pcall(GetInstanceInfo)
        if ok and type(name) == "string" and name ~= "" then title = name end
    end

    CaptureAndShow({
        title = title or L["Session"],
        subtitle = sessionType == 0 and L["Current fight"] or L["Overall"],
        durationSeconds = seconds,
        result = sessionType == 0 and L["Current fight"] or L["Overall"],
        sessionType = sessionType,
        mapID = mapID,
        rowCount = GroupRowCount(),
    }, "session", false)
end

function Scoreboard.OnEncounterEnd(encounterName, difficultyID)
    local duration = ns.Data.GetDuration(0)
    local seconds = (duration and not issecretvalue(duration)) and duration or nil
    local badge, difficultyName = DifficultyBadge(difficultyID)

    CaptureAndShow({
        title = encounterName or L["Encounter"],
        -- Sem nível de chave, a estrela carrega a dificuldade: é o mesmo papel, e sem ela o
        -- placar de raide não diria se o boss caiu no normal ou no mítico.
        badge = badge,
        subtitle = difficultyName,
        durationSeconds = seconds,
        result = "|cff40d878" .. L["defeated"] .. "|r",
        sessionType = 0,
        rowCount = GroupRowCount(),
    }, "raid")
end
