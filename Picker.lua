-- RocketMeter | Picker.lua
-- A única tela de configuração do addon: uma janela larga, em seções, distribuídas em três
-- colunas — as colunas do medidor, a janela e o placar, e os três textos.
--
-- POR QUE NÃO ABAS. Elas foram tentadas (0.58.0) e o problema não era hierarquia, era espaço: as
-- opções são poucas, e esconder metade delas atrás de uma aba deixava duas das três telas com um
-- vazio enorme. Com colunas tudo aparece de uma vez e a janela fica cheia.
--
-- A REGRA DE POSIÇÃO É UMA SÓ, e existe porque a violação dela foi o defeito relatado: o
-- checkbox nascia a 40% da largura da JANELA — no meio — e o rótulo dele saía pela borda
-- direita. Agora todo controle vive dentro de uma COLUNA, e é a coluna que diz onde ele começa e
-- onde termina; nada é posicionado em relação à janela inteira. `Picker.__probe()` devolve o
-- retângulo de cada controle para o harness conferir que nenhum vaza.
--
-- OS COMPONENTES SÃO OS DA BLIZZARD, com os nomes conferidos na fonte do 12.1.0 — não vêm de
-- "o Chattynator usa, então existe", que é a falácia que já custou uma rodada aqui:
--
--   `MinimalSliderWithSteppersTemplate`  Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml
--   `WowStyle1DropdownTemplate`          Blizzard_Menu/Mainline/MenuTemplates.xml
--   `MenuUtil.CreateRadioMenu`           Blizzard_Menu/MenuUtil.lua:381
--
-- (`Mainline`, não `Classic`: o template existe nas duas pastas e é o de `Mainline` que o
-- retail carrega. A citação errada estava aqui desde a 0.58.0.)
--
-- O QUE SE CONFIGURA E O QUE NÃO. A regra de 0.20.0 — aparência não se configura, o padrão é que
-- precisa estar certo — continua valendo para cor, textura, borda e opacidade. A tipografia é a
-- exceção deliberada: o corpo foi ajustado a pedido seis vezes, porque o valor certo depende de
-- resolução, escala de interface e de quanto o jogador enxerga. Os LIMITES é que não se
-- negociam, e o motivo de cada um está em `Window.lua`.
local ADDON, ns = ...
local L = ns.L

local Picker = {}
ns.Picker = Picker

--------------------------------------------------------------------------------
-- Grade
--------------------------------------------------------------------------------
local MARGIN = 18               -- da borda da janela até o conteúdo
local GUTTER = 20               -- entre as colunas
local COL_W = 262               -- largura útil de cada coluna
local COLUMNS = 3
local WIDTH = MARGIN * 2 + COL_W * COLUMNS + GUTTER * (COLUMNS - 1)

local TOP = 36                  -- abaixo da barra de título
-- Só a margem de baixo: o botão "Limpar dados" saiu daqui a pedido — os dados se limpam na
-- própria janela do medidor, e um botão em largura cheia no rodapé de uma tela de configuração
-- dava a ele um peso que ele não tem.
-- 14 of margin under the columns, plus the support line (Donate.lua, `DONATE_ROW`, 27/09).
local FOOTER = 14 + (ns.DONATE_ROW or 0)

-- RITMO VERTICAL. Todo número aqui foi lido na fonte do 12.1.0, e nenhum foi arredondado.
--
-- NÃO HÁ GRADE DE 4 NESTA TELA, e isso é decisão, não descuido. A tentativa anterior impôs uma
-- unidade de 4 e teve que torcer os valores para caber nela — mas **nenhum** número da Blizzard
-- é múltiplo de 4: 9, 25, 45, 5, 15, 37, 26. Arredondar 9 para 8 não compra alinhamento nenhum
-- e perde a coincidência exata com o nativo, que é justamente o objetivo.
--
-- A ALTURA DE LINHA É ÚNICA, e o widget é que se ajusta a ela. Os NOVE templates de opção da
-- Blizzard (`Blizzard_SettingControls.xml:108-164` — caixa, deslizador, combo, botão, cor e as
-- combinações) têm todos **280×26**, e é o painel que impõe a largura ao controle
-- (`Blizzard_SettingControls.lua:656,741`), nunca o contrário.
local H_CONTROL = 26
local H_LABEL = 12              -- caixa de `GameFontHighlightSmall` (fonte 10, `Fonts.xml:41`)

-- O DEFEITO RELATADO ERA UMA RAZÃO, NÃO UM NÚMERO. O espaço DENTRO de um campo (rótulo → seu
-- controle) era 4 e o espaço ENTRE campos era 6 — 1,5×. Com 1,5× o olho não decide se o rótulo
-- pertence ao controle abaixo dele ou é continuação da linha de cima, e o resultado é literalmente
-- "tudo muito junto e grudado, é feio, confuso". Lei de proximidade da Gestalt, e ela tem número.
--
-- O NÚMERO VEM DO ÚNICO FORMULÁRIO EMPILHADO DA BLIZZARD, o de criar comunidade
-- (`Blizzard_Communities/CommunitiesSettings.xml`): o campo nasce a `y="-2"` do rótulo dele
-- (`:79`), e o rótulo seguinte a `y="-34"` do rótulo anterior (`:25`) sobre um campo de 22
-- (`:77`) — ou seja, **2 por dentro e 10 por fora, razão 5×**.
--
-- (Uma rodada anterior "corrigiu" isto para 4 e 12 = 3×, para caber na grade de 4. Era o inverso:
-- afastou do valor medido em nome de uma grade que a Blizzard não usa.)
local GAP_LABEL = 2
local GAP_FIELD = 10

-- A tinta de um campo e a vaga dele: a vaga e a tinta MAIS o respiro que vem depois. Os dois
-- nomes existem porque o harness mede vão entre tintas, e vaga menos vaga daria zero sempre.
local INK_FIELD = H_LABEL + GAP_LABEL + H_CONTROL              -- 40
local INK_SECTION = H_LABEL + 4                                -- título e régua

local H_FIELD = INK_FIELD + GAP_FIELD                          -- 50
local H_CHECK = H_CONTROL + GAP_FIELD                          -- 36: o rótulo mora na linha
local H_BUTTON = H_CONTROL + GAP_FIELD                         -- 36
local H_COLUMN_ROW = H_CONTROL                                 -- lista densa, sem folga extra

-- ENTRE GRUPOS, o branco que a Blizzard abre acima de um título de seção: **25** = os 9 de
-- respiro de linha (`Blizzard_SettingsList.lua:46`) mais os 16 de recuo do título dentro do
-- bloco de cabeçalho de 45 (`Blizzard_SettingControls.xml:14,19`). São 2,5× o espaço entre
-- campos — acima do piso de 2× abaixo do qual a borda de grupo deixa de ser percebida.
--
-- E o corolário que importa mais que a razão: **grupo não se separa só com ar**. A Blizzard gasta
-- um bloco com título; por isso `BuildSection` desenha título e régua, e não um vão maior.
local GAP_SECTION = 25
local H_SECTION = H_LABEL + 4 + GAP_FIELD                      -- título, régua e respiro

-- 28, e não um número escolhido por mim: é o tamanho que a própria Blizzard dá ao
-- `UICheckButtonTemplate` quando o envelopa no `ResizeCheckButtonTemplate`
-- (`SharedUIPanelTemplates.xml:1322`). O template nasce 32×32; 28 é a medida que ela usa em
-- formulário.
local CHECK_SIZE = 28

-- A LISTA DE COLUNAS é lista densa, não formulário: caixa menor e sem folga entre linhas, como a
-- coluna de categorias do painel (`Blizzard_CategoryList.xml:51`, linha de 20).
local ROW_CHECK = 22
local ARROW = 18                -- seta de reordenar
local ARROW_GAP = 6             -- 18 + 6 = 24 centro a centro (WCAG 2.2 SC 2.5.8)
local ORDER_W = 14              -- o número da posição, à esquerda das setas

-- O `Text` do `UICheckButtonTemplate` é ancorado `LEFT` no `RIGHT` da caixa com **x = −2**
-- (`CheckButtonTemplates.xml:56`) — ele começa 2px ANTES do fim da caixa. Esse −2 é calibrado
-- para a arte de **32×32** do template original, que tem margem transparente; encolhendo a caixa
-- para 28 a margem some junto e o texto passa a encostar mesmo.
--
-- A própria Blizzard resolve isso onde faz a mesma troca: no `ResizeCheckButtonTemplate` ela usa
-- 28×28 e **reancora** o rótulo em `+2` (`SharedUIPanelTemplates.xml:1322,1337`). Os dois números
-- andam em par, e a versão anterior daqui copiou só o 28 — corrigia a largura e deixava a âncora
-- errada, que é a que decide onde o texto começa.
local CHECK_TEXT_OFFSET = 2

local frame, rows

-- O RETÂNGULO INTEIRO de cada controle, para o harness. Guardar só `x` e `width` foi o furo que
-- deixou três reprovações passarem: todas as três eram colisão VERTICAL (abas sobrepostas, campo
-- encavalado no seguinte), e sem `y`/`height` não havia o que conferir. Vai também a coluna, para
-- que a conferência de vizinhança compare quem de fato é vizinho.
--
-- A ALTURA REGISTRADA É A DA TINTA, não a da vaga. Registrar a vaga (que já embute o respiro)
-- faria o vão entre vizinhos dar zero sempre, e o teste passaria por construção sem medir nada —
-- que é o mesmo defeito, de novo, num nível acima.
local probes = {}

local function Probe(name, widget, x, width, y, height, column, isSection)
    probes[#probes + 1] = {
        name = name, widget = widget,
        x = x, width = width,
        y = y, height = height, column = column,
        isSection = isSection or false,
    }
end

---Este grupo desenhado contem esta coluna?
local function GroupHasKey(grupo, key)
    for _, id in ipairs(grupo.keys) do
        if id == key then return true end
    end
    return false
end

---O item esta ligado? Basta UMA das colunas dele estar na lista.
---
---"Basta uma" e de proposito: uma lista salva de antes desta versao pode ter so o total. A caixa
---mostra ligado, e desligar leva as duas -- que e o que "um so item" quer dizer. A lista se
---completa sozinha na proxima normalizacao.
local function IsEnabled(item)
    for _, id in ipairs(ns.db.columns) do
        for _, key in ipairs(item.keys) do
            if id == key then return true end
        end
    end
    return false
end

---A posicao do item entre os GRUPOS DESENHADOS -- que e o indice que `Window.MoveColumn` espera.
---
---⚑ ESTE ERA O DEFEITO. A tela devolvia a posicao em `ns.db.columns` e `MoveColumn` indexava a
---lista de grupos: com {dano, DPS, cura, CPS, interr} (5 colunas, 3 grupos), a seta da linha
---"DPS" movia o grupo da CURA e a de "CPS" nao fazia nada, por estourar a lista. Nada de errado
---aparecia na tela -- a seta simplesmente mexia na coluna errada.
local function IndexOf(item)
    local grupos = ns.Data.GroupColumns(ns.db.columns)
    for i, grupo in ipairs(grupos) do
        -- CASA PELAS CHAVES DO ITEM, nao pelo `attr` dele.
        --
        -- Hoje os dois dao o mesmo resultado, e vale dizer por que em vez de deixar parecendo
        -- correcao de defeito: os grupos desenhados sao POR FAMILIA, entao a "Fatia do dano" cai
        -- no mesmo grupo do par "Dano total / DPS" de qualquer maneira. O que muda e a
        -- dependencia -- casar por chave pergunta "este grupo contem alguma coluna DESTE item?",
        -- que continua certo se um dia um grupo deixar de ser uma familia inteira. Casar por
        -- `attr` so funciona enquanto grupo e familia forem sinonimos.
        for _, key in ipairs(item.keys) do
            if GroupHasKey(grupo, key) then return i, #grupos end
        end
    end
    return nil, #grupos
end

---As opções de contorno, montadas a partir de `ns.OUTLINE_CHOICES`.
---
---A lista era escrita à mão aqui, e por isso não seguiu quando `Window.lua` ganhou um nível:
---duas fontes de verdade para a mesma lista divergem na primeira mudança. Agora a ordem e o
---conjunto vêm de lá; aqui fica só o rótulo, que é a única parte que precisa de tradução.
---
---Os rótulos ficam DENTRO da função e com a chave escrita por extenso, e isso é requisito, não
---estilo: `tests/locales.lua` procura exatamente essa forma para saber quais chaves estão em uso.
---Montar a chave por variável (`L[MAPA[v]]`) apaga as quatro do radar e o teste as dá por mortas.
local function OutlineEntries()
    local label = {
        none   = L["None"],
        thin   = L["Thin"],
        thick  = L["Thick"],
    }

    local entries = {}
    for _, choice in ipairs(ns.OUTLINE_CHOICES) do
        entries[#entries + 1] = { label = label[choice.value] or choice.value, value = choice.value }
    end
    return entries
end

--------------------------------------------------------------------------------
-- Componentes
--------------------------------------------------------------------------------
---Título de seção, em dourado, com a régua fina que o placar já usa.
local function BuildSection(col, y, title)
    Probe("secao: " .. title, nil, 0, COL_W, y, INK_SECTION, col.index, true)
    local text = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    text:SetText(title)
    text:SetTextColor(1, 0.82, 0)

    local rule = col:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y - H_LABEL - 4)
    rule:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, -y - H_LABEL - 4)
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    return y + H_SECTION
end

---Rótulo EM CIMA do controle, não ao lado.
---
---Numa coluna estreita, rótulo à esquerda deixaria ~100px para o texto e o resto para o
---controle, e "Abrir ao fim de uma corrida de Mítico+" não cabe em 100. Em cima, o rótulo tem a
---coluna inteira e o controle também.
local function BuildLabelText(col, y)
    local text = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    text:SetWidth(COL_W)
    text:SetJustifyH("LEFT")
    return text
end

local function BuildLabel(col, y, label)
    BuildLabelText(col, y):SetText(label)
    return y + H_LABEL + GAP_LABEL
end

---Deslizador com o valor **no rótulo**, não ao lado do controle.
---
---O template desenha o valor num `RightText` ancorado a `Slider.RIGHT` com **x=25**
---(`MinimalSlider.xml:73-77`), e o `Slider` já fica 19px para dentro do frame — ou seja, o
---texto começa **6px FORA** da largura que a gente dá, e ainda cresce pela largura dele. Foi
---por isso que "13px" e "5" apareceram fora da janela.
---
---Os rótulos do template nascem `hidden="true"` e só aparecem se um formatador for passado no
---`Init`. Então não passamos nenhum: o valor entra no rótulo de cima, que já existe e já está
---dentro da coluna. Vazamento zero **por construção**, e o número fica ao lado do nome dele.
local function BuildSlider(col, y, label, low, high, suffix, get, set)
    local text = BuildLabelText(col, y)
    local at = y + H_LABEL + GAP_LABEL

    local slider = CreateFrame("Slider", nil, col, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -at)
    slider:SetWidth(COL_W)
    slider:SetHeight(H_CONTROL)
    Probe(label, slider, 0, COL_W, y, INK_FIELD, col.index)

    local function write()
        text:SetText(format("%s   |cffffd100%s|r", label, (suffix or "%d"):format(get())))
    end

    -- `Init(valor, min, max, passos, formatadores)`. Os passos são o número de INTERVALOS, e por
    -- isso é `high - low`: com um a mais o deslizador para em posições fracionárias e o número
    -- pisca entre dois inteiros.
    if slider.Init then
        -- Sem tabela de formatadores: os rótulos do template ficam escondidos e nada sai da
        -- coluna. O valor é escrito por `write()`, no rótulo de cima.
        slider:Init(get(), low, high, high - low)
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, value)
                set(value)
                write()
            end)
    end

    write()
    slider.Refresh = function()
        if slider.SetValue then slider:SetValue(get()) end
        write()
    end
    return y + H_FIELD, slider
end

---Combo de escolha única.
---
---`MenuUtil.CreateRadioMenu(dropdown, isSelected, setSelected, ...)` recebe os itens como pares
---`{ rótulo, valor }`. A marca de seleção sai de `isSelected`, então não há estado duplicado
---aqui — ela é sempre a resposta de quem guarda a configuração. Se o valor salvo não casar com
---nenhum item, o botão desenha **em branco**; aconteceu na 0.58.0, e o conserto é migrar a
---chave, não remendar aqui.
local function BuildDropdown(col, y, label, entries, get, set)
    local at = BuildLabel(col, y, label)

    local dropdown = CreateFrame("DropdownButton", nil, col, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -at)
    dropdown:SetWidth(COL_W)
    dropdown:SetHeight(H_CONTROL)
    Probe(label, dropdown, 0, COL_W, y, INK_FIELD, col.index)

    if MenuUtil and MenuUtil.CreateRadioMenu then
        local list = {}
        for _, entry in ipairs(entries) do
            list[#list + 1] = { entry.label, entry.value }
        end
        MenuUtil.CreateRadioMenu(dropdown,
            function(value) return get() == value end,
            function(value) set(value) end,
            unpack(list))
    end

    dropdown.Refresh = function()
        if dropdown.GenerateMenu then dropdown:GenerateMenu() end
    end
    return y + H_FIELD, dropdown
end

---Caixa de opção: a caixa na MARGEM DA COLUNA e o rótulo à direita dela.
---
---Era aqui o defeito relatado. A caixa nascia a 40% da largura da janela e o rótulo saía pela
---borda. Agora a caixa começa em 0 da coluna, e o rótulo recebe largura EXPLÍCITA: o que sobra
---da coluna depois da caixa. Sem essa largura, a FontString cresce até onde o texto pedir e
---atravessa a borda em vez de quebrar.
local function BuildCheck(col, y, label, tip, get, set)
    local check = CreateFrame("CheckButton", nil, col, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    check:SetSize(CHECK_SIZE, CHECK_SIZE)

    -- Testa o TIPO, não só a verdade: um stub que devolve função aqui passa no `if` e só
    -- estoura no `SetText`. Já aconteceu neste projeto, com `frame.Inset`.
    if type(check.Text) == "table" and check.Text.SetText then
        check.Text:SetText(label)
        check.Text:SetFontObject("GameFontHighlightSmall")
        -- REANCORAR, e não só medir. `SetWidth` conserta a conta; quem decide onde o texto
        -- começa é a âncora, e a herdada do template é −2 (ver `CHECK_TEXT_OFFSET`).
        check.Text:ClearAllPoints()
        check.Text:SetPoint("LEFT", check, "RIGHT", CHECK_TEXT_OFFSET, 0)
        check.Text:SetWidth(COL_W - CHECK_SIZE - CHECK_TEXT_OFFSET)
        check.Text:SetJustifyH("LEFT")
    end
    Probe(label, check, 0, COL_W, y, H_CONTROL, col.index)

    check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)

    check.Refresh = function() check:SetChecked(get()) end
    check.Refresh()
    return y + H_CHECK, check
end

local function BuildButton(col, y, label, tip, onClick)
    local b = CreateFrame("Button", nil, col, "UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    b:SetSize(COL_W, H_CONTROL)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    Probe(label, b, 0, COL_W, y, H_CONTROL, col.index)
    return y + H_BUTTON, b
end

--------------------------------------------------------------------------------
-- Linha da lista de colunas
--------------------------------------------------------------------------------
local function BuildRow(index, item, col, y)
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, col)
        row:SetSize(COL_W, H_COLUMN_ROW)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(ROW_CHECK, ROW_CHECK)
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetScript("OnClick", function(self)
            ns.Window.ToggleColumn(self.columnKey)
            Picker.Refresh()
        end)

        -- AS SETAS SÃO ALVO DE CLIQUE, e alvo pequeno tem norma: WCAG 2.2 SC 2.5.8 (AA) pede
        -- 24×24, **ou** 24 de distância CENTRO A CENTRO até o alvo vizinho — a exceção é medida
        -- entre centros, não entre bordas. Com 18×18 e vão de 2 dá 20, e reprova; com vão de 6 dá
        -- 18 + 6 = 24 e passa, sem precisar inchar o botão numa lista já densa.
        row.down = CreateFrame("Button", nil, row)
        row.down:SetSize(ARROW, ARROW)
        row.down:SetPoint("RIGHT", -2, 0)
        row.down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        row.down:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        row.down:SetScript("OnClick", function(self)
            local at = IndexOf(self.item)
            if at then
                ns.Window.MoveColumn(at, 1)
                Picker.Refresh()
            end
        end)

        row.up = CreateFrame("Button", nil, row)
        row.up:SetSize(ARROW, ARROW)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -ARROW_GAP, 0)
        row.up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        row.up:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        row.up:SetScript("OnClick", function(self)
            local at = IndexOf(self.item)
            if at then
                ns.Window.MoveColumn(at, -1)
                Picker.Refresh()
            end
        end)

        row.order = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.order:SetPoint("RIGHT", row.up, "LEFT", -ARROW_GAP, 0)

        -- Largura EXPLÍCITA para o rótulo, pelo mesmo motivo do checkbox: sem ela um nome longo
        -- empurra as setas para fora da coluna.
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.label:SetWidth(COL_W - ROW_CHECK - 4 - (2 + ARROW + ARROW_GAP + ARROW + ARROW_GAP + ORDER_W))
        row.label:SetJustifyH("LEFT")

        row:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
        rows[index] = row
    end

    -- A LINHA FALA DE UM ITEM. `columnKey` continua sendo uma chave -- `ToggleColumn` liga o
    -- item inteiro a partir de qualquer uma delas -- e `item` e o que as setas usam para achar o
    -- grupo correspondente na janela.
    row.check.columnKey = item.key
    row.up.item, row.down.item = item, item

    local enabled = IsEnabled(item)
    row.check:SetChecked(enabled)
    row.label:SetText(item.label)

    if enabled then
        local position, quantos = IndexOf(item)
        row.label:SetTextColor(1, 1, 1)
        -- "1." e não "1º": o ordinal masculino só existe em algumas línguas latinas, e em
        -- inglês, alemão ou coreano vira lixo. O ponto é o que o próprio medidor nativo usa
        -- para numerar linha (`DAMAGE_METER_SOURCE_NAME = "%d. %s"`).
        row.order:SetText(position .. ".")
        row.order:Show()
        row.up:Show()
        row.down:Show()
        row.up:SetEnabled(position > 1)
        row.down:SetEnabled(position < quantos)
    else
        row.label:SetTextColor(0.5, 0.5, 0.5)
        row.order:Hide()
        row.up:Hide()
        row.down:Hide()
    end

    row:Show()
end

--------------------------------------------------------------------------------
function Picker.Create()
    if frame then return frame end

    local columns = ns.Data.GetColumnItems()
    rows, probes = {}, {}

    -- ALTURA: soma de cada coluna, e a janela fica com a maior. Contar aqui, com as MESMAS
    -- constantes que posicionam os controles, é o que impede a janela de sobrar ou faltar
    -- espaço quando uma linha é acrescentada.
    local h1 = H_SECTION + #columns * H_COLUMN_ROW
    -- Aparencia: fonte, linhas, os DOIS deslizadores de distancia, o rotulo do vao e o reino.
    -- Aparencia: fonte, linhas, os dois deslizadores de distancia e o reino.
    local h2 = H_SECTION + H_FIELD * 4 + H_CHECK                       -- Aparencia
        + GAP_SECTION + H_SECTION + H_CHECK                            -- Sessao
        + GAP_SECTION + H_SECTION + H_CHECK * 2 + 4 + H_BUTTON * 2     -- Placar
    -- Tres secoes de texto identicas: titulo + deslizador + combo + caixa.
    local h3 = (H_SECTION + H_FIELD * 2 + H_CHECK) * 3 + GAP_SECTION * 2
    local content = math.max(h1, math.max(h2, h3))

    frame = CreateFrame("Frame", ADDON .. "Picker", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WIDTH, TOP + content + FOOTER)
    frame:SetFrameStrata("DIALOG")
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
    frame:Hide()
    if frame.SetTitle then frame:SetTitle(L["Configure"]) end

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- "Support the project" (27/09): a line of its own at the very bottom (Donate.lua).
    frame.donate = ns.DonateFooter(frame)

    ---Uma coluna é um Frame de largura fixa. Todo controle é posicionado em relação a ELA, e
    ---nunca à janela — foi posicionar em relação à janela que fez o rótulo sair pela borda.
    local function Column(index)
        local col = CreateFrame("Frame", nil, frame)
        col:SetWidth(COL_W)
        col:SetPoint("TOPLEFT", frame, "TOPLEFT",
            MARGIN + (index - 1) * (COL_W + GUTTER), -TOP)
        col:SetPoint("BOTTOM", frame, "BOTTOM", 0, FOOTER)
        col.index = index       -- o harness usa para comparar só quem é vizinho de verdade
        return col
    end

    local colColumns, colWindow, colText = Column(1), Column(2), Column(3)
    frame.leftColumn = colColumns

    -- Coluna 1: quais colunas a janela mostra, e em que ordem.
    frame.columnsTop = BuildSection(colColumns, 0, L["Columns"])

    ----------------------------------------------------------------------------
    -- Coluna 2: a janela e o placar
    ----------------------------------------------------------------------------
    local y = BuildSection(colWindow, 0, L["Appearance"])

    -- A FAMILIA e uma so para o addon inteiro, de proposito. Fonte diferente por elemento nao
    -- da hierarquia, da colcha de retalhos -- e o que separa titulo de linha aqui e corpo,
    -- contorno e sombra, que sao os tres que o usuario pediu.
    local fontEntries = {}
    for _, choice in ipairs(ns.FONT_CHOICES) do
        fontEntries[#fontEntries + 1] = { label = choice.label, value = choice.path }
    end
    y, frame.fontDrop = BuildDropdown(colWindow, y, L["Font"], fontEntries,
        function() return ns.FontPath() end,
        function(v) ns.Window.SetFont(v) end)

    y, frame.rowsSlider = BuildSlider(colWindow, y, L["Rows"],
        ns.Skin.rowsMin, ns.Skin.rowsMax, "%d",
        function() return ns.Window.GetRows() or 5 end,
        function(v) ns.Window.SetRows(v) end)

    -- AS DUAS DISTÂNCIAS DA LINHA, na seção da aparência da janela porque é disso que se trata:
    -- densidade. Pedido de 09/09/2026, com print e retângulos apontando as duas.
    --
    -- A LEGENDA "N px entre os dois valores" SAIU a pedido (10/09/2026). Ela existia para amarrar
    -- um controle abstrato (a largura da coluna) ao número que o jogador enxerga na janela — mas o
    -- efeito já está à vista: a janela redesenha a cada arrasto, com os dois valores se aproximando
    -- na tela atrás da configuração. Legenda que descreve o que já se vê é peso, não ajuda.
    y, frame.gapSlider = BuildSlider(colWindow, y, L["Space between columns"],
        ns.Skin.groupGapMin, ns.Skin.groupGapMax, "%dpx",
        function() return ns.Window.GetGroupGap() end,
        function(v) ns.Window.SetGroupGap(v) end)

    y, frame.pairSlider = BuildSlider(colWindow, y, L["Width of the total column"],
        ns.Skin.totalWidthMin, ns.Skin.totalWidthMax, "%dpx",
        function() return ns.Window.GetTotalWidth() end,
        function(v) ns.Window.SetTotalWidth(v) end)

    y, frame.realmCheck = BuildCheck(colWindow, y, L["Show the realm next to the name"],
        L["Off by default: the realm eats the column and the name is what ends up cut."],
        function() return ns.db.showRealm end,
        function(v)
            ns.db.showRealm = v
            ns.Window.Refresh()
        end)

    -- SEÇÃO PRÓPRIA, e não uma quarta linha em "Aparência". A regra da tela é que seção é
    -- ASSUNTO, não quantidade: fonte, linhas e reino dizem como a janela SE PARECE; qual sessão
    -- ela mostra é outro assunto, e enfiá-lo sob "Aparência" faria o título mentir. Uma seção com
    -- um controle só é o que a Blizzard faz quando o assunto é um só.
    y = BuildSection(colWindow, y + GAP_SECTION, L["Session"])

    y, frame.autoSession = BuildCheck(colWindow, y, L["Follow the combat"],
        L["In combat, the current fight; when it ends, back to the overall."],
        function() return ns.db.autoSession end,
        function(v)
            ns.db.autoSession = v
            -- Ligar a caixa fora de combate tem que MOSTRAR o efeito na hora. Marcar e não ver
            -- nada acontecer até a próxima luta é o que faz o jogador achar que a opção não pega.
            if ns.Window.ApplyAutoSession() then
                ns.Window.Refresh(true)
            end
        end)

    y = BuildSection(colWindow, y + GAP_SECTION, L["Scoreboard"])

    y, frame.autoMPlus = BuildCheck(colWindow, y, L["Open at the end of a Mythic+ run"],
        L["When the keystone ends, the summary of the run opens by itself."],
        function() return ns.db.autoScoreboardMPlus end,
        function(v) ns.db.autoScoreboardMPlus = v end)

    y, frame.autoRaid = BuildCheck(colWindow, y, L["Open when a raid boss dies"],
        L["When an encounter is defeated, the summary of the fight opens by itself."],
        function() return ns.db.autoScoreboardRaid end,
        function(v) ns.db.autoScoreboardRaid = v end)

    -- Os dois ultimos placares. Apagados quando nao ha corrida guardada: botao que responde com
    -- erro no chat ensina menos que botao apagado.
    y, frame.lastMPlus = BuildButton(colWindow, y + 4, L["Last Mythic+"],
        L["Opens the scoreboard of the last Mythic+ run finished on this character."],
        function() ns.Scoreboard.ShowLast("mplus") end)
    frame.lastMPlus.hasRun = "mplus"

    y, frame.lastRaid = BuildButton(colWindow, y, L["Last raid"],
        L["Opens the scoreboard of the last raid boss defeated on this character."],
        function() ns.Scoreboard.ShowLast("raid") end)
    frame.lastRaid.hasRun = "raid"

    ----------------------------------------------------------------------------
    -- Coluna 3: os TRES textos, cada um com corpo, contorno e sombra proprios
    ----------------------------------------------------------------------------
    -- Uma secao por papel, com os mesmos tres controles na mesma ordem. Repetir a forma e o que
    -- torna a coluna legivel: o jogador aprende uma vez e le as outras duas de relance.
    frame.roleWidgets = {}

    local ROLE_LABELS = {
        body   = L["Row text"],
        title  = L["Title"],
        header = L["Column header"],
    }

    local ry = 0
    for i, role in ipairs(ns.ROLES) do
        ry = BuildSection(colText, ry + (i > 1 and GAP_SECTION or 0), ROLE_LABELS[role])

        local widgets = {}
        ry, widgets.size = BuildSlider(colText, ry, L["Text size"],
            ns.Skin.fontSizeMin, ns.Skin.fontSizeMax, "%dpx",
            function() return ns.Window.GetRoleSize(role) end,
            function(v) ns.Window.SetRoleSize(role, v) end)

        ry, widgets.outline = BuildDropdown(colText, ry, L["Font outline"], OutlineEntries(),
            function() return ns.Window.GetRoleOutline(role) end,
            function(v) ns.Window.SetRoleOutline(role, v) end)

        ry, widgets.shadow = BuildCheck(colText, ry, L["Font shadow"],
            L["A 1px black shadow below the text. Carries the letters over any background."],
            function() return ns.Window.GetRoleShadow(role) end,
            function(v) ns.Window.SetRoleShadow(role, v) end)

        frame.roleWidgets[role] = widgets
    end

    return frame
end

--------------------------------------------------------------------------------
-- Ganchos para o harness. O que se verifica é GEOMETRIA — foi ela que falhou duas vezes
-- seguidas no teste in-game, e é o que dá para conferir sem desenhar nada.
--------------------------------------------------------------------------------
Picker.__layout = {
    width = WIDTH,
    margin = MARGIN,
    gutter = GUTTER,
    columnWidth = COL_W,
    columns = COLUMNS,
    top = TOP,
    footer = FOOTER,
    checkSize = CHECK_SIZE,
    checkTextOffset = CHECK_TEXT_OFFSET,
    arrow = ARROW,
    arrowGap = ARROW_GAP,
    control = H_CONTROL,
    label = H_LABEL,
    gapLabel = GAP_LABEL,
    gapField = GAP_FIELD,
    gapSection = GAP_SECTION,
    field = H_FIELD,
    check = H_CHECK,
    section = H_SECTION,
}

---A lista de contorno como o combo a monta, para o harness conferir contra `ns.OUTLINE_CHOICES`.
function Picker.__outlineEntries()
    return OutlineEntries()
end

---Cada controle e onde ele fica DENTRO da coluna. É com isso que o harness confere que nada
---vaza pela borda.
---O que a LISTA DE COLUNAS oferece, na ordem da tela.
---
---Ela deixou de listar o catalogo e passou a listar ITENS -- dano+DPS numa linha so. A porta
---devolve o que a tela desenha, nao o que `Data` calcula: e a diferenca entre afirmar que a lista
---de itens existe e afirmar que a tela usa ela.
function Picker.__items()
    local out = {}
    for i, row in ipairs(rows) do
        if row:IsShown() then
            out[i] = { key = row.check.columnKey, label = row.label:GetText() }
        end
    end
    return out
end

---O indice que a SETA de uma linha passa para `Window.MoveColumn`.
---
---⚑ ISTO EXISTE POR CAUSA DE UM DEFEITO REAL: a tela devolvia a posicao em `ns.db.columns` e
---`MoveColumn` indexava a lista de GRUPOS. Com {dano, DPS, cura, CPS, interr} a seta da linha
---"dano/DPS" chegava certa por coincidencia e a da cura movia outra familia. Nada aparecia
---errado -- a seta so mexia na coisa errada.
function Picker.__arrowTarget(key)
    for _, row in ipairs(rows) do
        if row.check.columnKey == key and row.up.item then
            return IndexOf(row.up.item)
        end
    end
    return nil
end

function Picker.__probe()
    return probes
end

function Picker.__frame()
    return frame
end

function Picker.__frameHeight()
    return frame and frame:GetHeight() or 0
end

--------------------------------------------------------------------------------
function Picker.RefreshRows()
    if not frame then return end
    if frame.rowsSlider and frame.rowsSlider.Refresh then frame.rowsSlider.Refresh() end
end

function Picker.Refresh()
    if not frame or not frame:IsShown() then return end

    for _, widget in ipairs({ frame.rowsSlider, frame.fontDrop, frame.realmCheck,
                             frame.gapSlider, frame.pairSlider,
                             frame.autoSession, frame.autoMPlus, frame.autoRaid }) do
        if widget and widget.Refresh then widget.Refresh() end
    end

    for _, widgets in pairs(frame.roleWidgets or {}) do
        for _, widget in pairs(widgets) do
            if widget.Refresh then widget.Refresh() end
        end
    end

    for _, b in ipairs({ frame.lastMPlus, frame.lastRaid }) do
        if b then b:SetEnabled(ns.Scoreboard.HasRun(b.hasRun)) end
    end

    -- ITENS, nao colunas: dano+DPS e cura+CPS ocupam UMA linha cada.
    local items = ns.Data.GetColumnItems()
    for i = 1, #items do
        BuildRow(i, items[i], frame.leftColumn,
            frame.columnsTop + (i - 1) * H_COLUMN_ROW)
    end

    -- Linha que sobrou de uma lista maior nao pode ficar na tela: `rows` e cache por indice, e o
    -- catalogo encolheu de 14 entradas para 11 itens.
    for i = #items + 1, #rows do rows[i]:Hide() end
end

function Picker.Toggle(anchorTo)
    Picker.Create()
    if frame:IsShown() then
        frame:Hide()
        return
    end

    frame:ClearAllPoints()
    if anchorTo then
        frame:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 6, 0)
    else
        frame:SetPoint("CENTER")
    end

    frame:Show()
    Picker.Refresh()
end

-- Não há painel nas opções do jogo: esta é a tela de configuração do addon.
function ns.OpenOptions()
    Picker.Toggle()
end

function ns.SetupOptions()
    -- Sem painel na Settings API, de propósito.
end
