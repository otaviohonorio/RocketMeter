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
-- A linha do placar é mais alta que a da janela (25px) de propósito: lá são seis colunas
-- disputando espaço num overlay que fica sobre o jogo; aqui a corrida acabou e a tela é para
-- ler. O corpo da fonte é **próprio** (`ns.Skin.scoreboardFontSize`, hoje 12): este painel foi
-- visto e aprovado nesse tamanho, e a janela de combate subiu para 13 depois — herdar dela
-- desfaria uma aprovação que já existe. Os valores continuam saindo todos de `ns.Skin`.
local ROW_HEIGHT = 34
local ROW_SPACING = 2
local ICON_SIZE = 26
local ROLE_SIZE = 13
local NAME_WIDTH = 176
local SIDE = 14
local HEADER_HEIGHT = 64
local COLHEAD_HEIGHT = 16
local FOOTER_HEIGHT = 66
local MAX_ROWS = 20

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
-- A barra de classe é fundo, não bloco: ver o comentário em `DrawRows`.
local BAR_ALPHA = 0.45

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
}

--------------------------------------------------------------------------------
-- Colunas
--------------------------------------------------------------------------------
-- `key` de coluna de medidor é a mesma chave do catálogo de `Data.lua` — o rótulo curto e o
-- formato do número vêm de lá, sem cópia. `custom = true` marca as que o `C_DamageMeter` não
-- conhece e o placar preenche por conta própria.
local ALL_COLUMNS = {
    { key = "score",      width = 82, custom = true, label = L["Score"] },
    { key = "deaths",     width = 54 },
    { key = "taken",      width = 68 },
    { key = "avoidable",  width = 68 },
    { key = "dps",        width = 66 },
    { key = "hps",        width = 66 },
    { key = "interrupts", width = 54 },
    { key = "dispels",    width = 54 },
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

---Recalcula quais colunas aparecem. Só a de pontuação de M+ é condicional hoje.
local function ComputeColumns()
    if IsKeystone() then return ALL_COLUMNS end

    local out = {}
    for c = 1, #ALL_COLUMNS do
        if not ALL_COLUMNS[c].custom then out[#out + 1] = ALL_COLUMNS[c] end
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

local function ColumnOffsets()
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + columns[c].width
    end
    return offsets, running
end

local function PanelWidth()
    local _, columnsWidth = ColumnOffsets()
    return SIDE * 2 + NAME_WIDTH + columnsWidth
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

        rows[i] = {
            name = name or (UNKNOWN or "?"),
            classFilename = classFilename,
            specIconID = specIconID,
            role = RoleFor(source.name),
            isLocalPlayer = isLocal,
            scoreGain = isLocal and base.scoreGain or nil,
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
local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}

        headerRow.rule = headerRow:CreateTexture(nil, "ARTWORK")
        headerRow.rule:SetPoint("BOTTOMLEFT", 0, 0)
        headerRow.rule:SetPoint("BOTTOMRIGHT", 0, 0)
        headerRow.rule:SetHeight(1)
        headerRow.rule:SetColorTexture(1, 0.82, 0, 0.20)
    end

    headerRow:ClearAllPoints()
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -HEADER_HEIGHT)
    headerRow:SetHeight(COLHEAD_HEIGHT)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(COLHEAD_HEIGHT)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            button.text:SetPoint("RIGHT", -4, 0)
            button.text:SetJustifyH("RIGHT")
            button:SetScript("OnClick", function(self)
                local key = columns[self.columnIndex].key
                if sortBy == key then sortDesc = not sortDesc else sortBy, sortDesc = key, true end
                -- Pela função pública, não por `Draw()` cru: `SafeDraw` é local e declarado
                -- mais abaixo, então aqui ele nem seria visível — e um erro de desenho
                -- disparado de dentro de um OnClick some sem deixar rastro quando
                -- `scriptErrors` está desligado, que é o padrão do jogo.
                Scoreboard.Refresh()
            end)
            button:SetScript("OnEnter", function(self)
                local column = columns[self.columnIndex]
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(column.custom and ColumnLabel(column)
                    or ns.Data.GetAttributeLabel(column.key), 1, 1, 1)
                GameTooltip:AddLine(L["Click to sort by this column."], 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            headerRow.labels[c] = button
        end

        button.columnIndex = c
        button:SetWidth(columns[c].width)
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -offsets[c], 0)

        -- O mesmo corpo do cabeçalho de colunas da janela, lido de `ns.Skin` em vez de
        -- redigitado: é absoluto, não delta, e não deve crescer junto se a linha mudar.
        ns.ApplyScoreboardFont(button.text, ns.Skin.colheadFontSize - ns.Skin.scoreboardFontSize, "")
        -- Só a cor marca a coluna ordenada; seta ao lado repetiria a informação.
        local label = ColumnLabel(columns[c])
        if columns[c].key == sortBy then
            button.text:SetText("|cffffd100" .. label .. "|r")
        else
            button.text:SetText("|cffb8ac8a" .. label .. "|r")
        end
        button:Show()
    end
end

--------------------------------------------------------------------------------
-- Linhas
--------------------------------------------------------------------------------
local function BuildRow(index)
    local row = rows[index]

    if not row then
        -- Frame, não Button: a linha do placar não faz nada ao ser clicada. Como Button ela
        -- capturava o mouse e o painel deixava de ser arrastável em cima das linhas — que é
        -- justamente onde a pessoa agarra. E a textura de HIGHLIGHT que existia aqui nunca
        -- chegou a desenhar: ela estava num Frame filho sem mouse, e HIGHLIGHT só é pintada
        -- pelo próprio botão que recebe o hover.
        row = CreateFrame("Frame", nil, frame)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(false)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT", 0, 0)
        row.bar:SetPoint("BOTTOMRIGHT", 0, 0)
        row.bar:SetStatusBarTexture(ns.BarTexture())
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)
        row.bar:SetFrameLevel(row:GetFrameLevel() + 1)

        -- Frame filho desenha ACIMA de qualquer FontString do pai: sem esta camada o texto
        -- some atrás da barra. Está documentado no `Window.lua` e custou uma rodada lá.
        row.text = CreateFrame("Frame", nil, row)
        row.text:SetAllPoints()
        row.text:SetFrameLevel(row.bar:GetFrameLevel() + 2)

        row.role = row.text:CreateTexture(nil, "OVERLAY")
        row.role:SetSize(ROLE_SIZE, ROLE_SIZE)
        row.role:SetPoint("LEFT", 6, 0)

        -- Duas texturas de ícone porque especialização é id inteiro e classe é recorte de
        -- atlas, e `SetMask` não convive com `SetTexCoord` ("Cannot set tex coords when
        -- texture has mask"). O placar antigo aplicava máscara aqui e o ícone de classe
        -- sumia — é o bug que esta reescrita corrige.
        -- A âncora dos dois ícones é decidida no desenho: ela depende de haver ou não ícone
        -- de função nesta linha (ver `DrawRows`).
        row.icon = row.text:CreateTexture(nil, "OVERLAY")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)

        row.iconClass = row.text:CreateTexture(nil, "OVERLAY")
        row.iconClass:SetSize(ICON_SIZE, ICON_SIZE)
        row.iconClass:Hide()

        row.name = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 7, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.nameHalo = ns.CreateHalo(row.text, row.name)

        -- Nome e reino em dois corpos, exatamente como na janela: quem reparte a largura e
        -- `ns.DrawName`, que vive no Window.lua para as duas telas nao divergirem.
        row.realm = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.realm:SetPoint("LEFT", row.name, "RIGHT", 0, 0)
        row.realm:SetJustifyH("LEFT")
        row.realm:SetWordWrap(false)
        row.realmHalo = ns.CreateHalo(row.text, row.realm)

        row.cells = {}
        row.cellHalos = {}
        rows[index] = row
    end

    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + COLHEAD_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_SPACING))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, offsetY)

    ns.ApplyScoreboardFont(row.name, 0, "")
    ns.SyncHaloFont(row.name, row.nameHalo,
        ns.Skin.scoreboardFontSize - ns.Skin.fontSize)
    ns.ApplyScoreboardFont(row.realm, ns.REALM_FONT_DELTA, "")
    ns.SyncHaloFont(row.realm, row.realmHalo,
        ns.REALM_FONT_DELTA + ns.Skin.scoreboardFontSize - ns.Skin.fontSize)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local cell = row.cells[c]
        if not cell then
            cell = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetJustifyH("RIGHT")
            row.cells[c] = cell
            row.cellHalos[c] = ns.CreateHalo(row.text, cell)
        end
        cell:SetWidth(columns[c].width - 8)
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row, "RIGHT", -offsets[c] - 4, 0)
        for _, echo in ipairs(row.cellHalos[c]) do
            echo:SetWidth(columns[c].width - 8)
        end
        ns.ApplyScoreboardFont(cell, 0, "")
        ns.SyncHaloFont(cell, row.cellHalos[c], ns.Skin.scoreboardFontSize - ns.Skin.fontSize)
        cell:Show()
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
        if not Atlas(mark, "BossBanner-SkullCircle") then
            mark:SetColorTexture(0.85, 0.25, 0.25, 0.9)
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
    timeline:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE, 40)
    timeline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE, 40)
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

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, -13)
    frame.title:SetTextColor(1, 0.82, 0)

    frame.clock = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.clock:SetPoint("TOP", frame.title, "BOTTOM", 0, -4)

    frame.result = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.result:SetPoint("TOP", frame.clock, "BOTTOM", 0, -3)

    -- Afixos à esquerda do cabeçalho, pequenos: são contexto, não manchete.
    frame.affixes = {}
    for i = 1, 4 do
        local icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", SIDE + (i - 1) * 21, -12)
        icon:Hide()
        frame.affixes[i] = icon
    end

    frame.deaths = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.deaths:SetPoint("TOPLEFT", SIDE, -36)
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
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("TOPRIGHT", -10, -38)
    frame.footer:SetJustifyH("RIGHT")

    CreateTimeline()

    rows = {}
    return frame
end

--------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------
local function DrawHeader()
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

local function DrawRows(list, rowCount)
    local sortIndex = 1
    for c = 1, #columns do
        if columns[c].key == sortBy then sortIndex = c end
    end

    -- A régua da barra é o maior valor DA COLUNA ORDENADA, não o `maxAmount` da sessão: a
    -- sessão só conhece a métrica que ordenou a consulta, e aqui o usuário pode estar
    -- ordenando por mortes ou por interrupções, onde aquele máximo não significa nada.
    --
    -- ...MAS não da coluna ordenada quando ela é a de pontuação: todo mundo tem ~2800 de
    -- pontuação, e uma régua de 0 a 2910 deixaria as cinco barras visualmente iguais. Nesse
    -- caso a barra volta a medir a métrica padrão, que é o que dá forma à linha.
    local barIndex = sortIndex
    if columns[barIndex] and columns[barIndex].custom then
        for c = 1, #columns do
            if columns[c].key == DEFAULT_SORT then barIndex = c end
        end
    end

    -- `issecretvalue` ANTES de `type`: para um valor opaco `type()` devolve o tipo REAL
    -- ("number"), então testar só o tipo deixa o secret passar — e aí `v > scale` levanta
    -- "attempt to compare a secret value" e o desenho inteiro aborta. Em combate (o placar
    -- pode ser reaberto no meio de outra luta) isso é o caminho normal, não a exceção.
    local scale
    for i = 1, #list do
        local v = list[i].values[barIndex]
        if v ~= nil and not issecretvalue(v) and type(v) == "number" then   -- luacheck: ignore
            if scale == nil or v > scale then scale = v end
        end
    end
    -- `not scale` também é teste booleano: comparar com nil explicitamente evita tocar secret.
    if scale == nil or scale <= 0 then scale = 1 end

    for i = 1, rowCount do
        local row = BuildRow(i)
        local entry = list[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source
            row.classFilename = source.classFilename    -- `ns.StyleCell` lê daqui

            local value = entry.values[barIndex]
            row.bar:SetStatusBarTexture(ns.BarTexture())
            row.bar:SetMinMaxValues(0, scale)
            row.bar:SetValue(type(value) == "number" and value or 0)
            row.bar:SetStatusBarColor(ns.BarColor(source.classFilename))
            -- Tinta, não bloco. A barra preenche a linha inteira, e a 0.85 ela virava um
            -- retângulo sólido na cor da classe — o que quebra a regra que a janela já
            -- aprendeu: o realce do líder é a cor da classe CLAREADA, e cor da classe sobre
            -- cor da classe some. Em 0.45 a linha ainda se identifica de relance e o texto
            -- (com halo) continua legível por cima.
            row.bar:SetAlpha(BAR_ALPHA)

            row.bg:SetColorTexture(0, 0, 0, i % 2 == 0 and 0.16 or 0.28)

            -- A função foi resolvida na captura e viajou junto no retrato: uma corrida
            -- guardada não pode depender de o grupo ainda existir para saber quem tankava.
            local role = entry.row and entry.row.role
            if role and ROLE_ATLAS[role] and Atlas(row.role, ROLE_ATLAS[role]) then
                row.role:Show()
                -- `ClearAllPoints` antes: `SetPoint` ACRESCENTA âncora, não substitui, e sem
                -- isso a textura ficaria presa às duas posições ao alternar entre os ramos.
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row.role, "RIGHT", 5, 0)
                row.iconClass:ClearAllPoints()
                row.iconClass:SetPoint("LEFT", row.role, "RIGHT", 5, 0)
                row.nameArea = NAME_WIDTH - ROLE_SIZE - ICON_SIZE - 30
            else
                -- Sem função conhecida o ícone some E o espaço dele é devolvido: 19px de vão
                -- fixo à esquerda de toda linha é o tipo de buraco que faz o painel parecer
                -- desalinhado sem que se saiba dizer o motivo.
                row.role:Hide()
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.iconClass:ClearAllPoints()
                row.iconClass:SetPoint("LEFT", row, "LEFT", 6, 0)
                row.nameArea = NAME_WIDTH - ICON_SIZE - 17
            end

            ns.ApplyRowIcon(row.icon, row.iconClass, source)
            ns.DrawName(row, source.name)
            row.name:SetTextColor(unpack(ns.Skin.text))

            for c = 1, #columns do
                if columns[c].custom then
                    ns.SetHaloText(row.cells[c], row.cellHalos[c], ScoreText(entry, c))
                else
                    ns.SetCellText(row.cells[c], entry.values[c], columns[c].key, row.cellHalos[c])
                end
                ns.StyleCell(row, c, entry.best and entry.best[c],
                    ns.Skin.scoreboardFontSize - ns.Skin.fontSize)
            end

            row:Show()
        end
    end

    for i = rowCount + 1, #rows do
        rows[i]:Hide()
    end
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
    local ok, err = pcall(Scoreboard.Draw)
    if not ok then
        Scoreboard.lastError = err
        ns.Print(L["error while drawing:"] .. " " .. tostring(err))
    end
end

local SafeDraw = Scoreboard.Refresh

function Scoreboard.Show(newContext)
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
local function CaptureAndShow(base, kind, auto)
    base.kind = kind
    ns.RunWhenSafe(function()
        local ok, snapshot = pcall(Scoreboard.Snapshot, base)
        if not ok or not snapshot then
            ns.Print(L["error while drawing:"] .. " " .. tostring(snapshot))
            return
        end

        Scoreboard.SaveRun(kind, snapshot)
        if auto == false or ns.db.autoScoreboard then
            Scoreboard.Show(snapshot)
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
