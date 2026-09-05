-- RocketMeter | Picker.lua
-- A única tela de configuração do addon: uma janela larga, em seções, distribuídas em duas
-- colunas.
--
-- POR QUE NÃO ABAS. Elas foram tentadas (0.58.0) e o problema não era hierarquia, era espaço: as
-- opções são poucas, e esconder metade delas atrás de uma aba deixava duas das três telas com um
-- vazio enorme. Com duas colunas tudo aparece de uma vez e a janela fica cheia.
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
--   `MinimalSliderWithSteppersTemplate`  Shared/Slider/MinimalSlider.xml
--   `WowStyle1DropdownTemplate`          Blizzard_Menu/Classic/MenuTemplates.xml
--   `MenuUtil.CreateRadioMenu`           Blizzard_Menu/MenuUtil.lua:381
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
local GUTTER = 22               -- entre as duas colunas
local COL_W = 288               -- largura útil de cada coluna
local WIDTH = MARGIN * 2 + COL_W * 2 + GUTTER

local TOP = 36                  -- abaixo da barra de título
local FOOTER = 46               -- o botão de limpar dados

-- Alturas por tipo de linha. São as MESMAS constantes usadas para posicionar e para somar a
-- altura da janela — acrescentar uma linha reacomoda tudo sem ninguém recontar à mão.
local H_SECTION = 26            -- título da seção + a régua
local H_FIELD = 46              -- rótulo em cima (16) + controle (24) + respiro (6)
local H_CHECK = 28
local H_BUTTON = 28
local H_COLUMN_ROW = 24
local GAP_SECTION = 14

local CHECK_SIZE = 24

local frame, rows
local probes = {}               -- { nome, x, largura } de cada controle, para o harness

local function Probe(name, widget, x, width)
    probes[#probes + 1] = { name = name, x = x, width = width, widget = widget }
end

local function IsEnabled(key)
    for _, id in ipairs(ns.db.columns) do
        if id == key then return true end
    end
    return false
end

local function IndexOf(key)
    for i, id in ipairs(ns.db.columns) do
        if id == key then return i end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Componentes
--------------------------------------------------------------------------------
---Título de seção, em dourado, com a régua fina que o placar já usa.
local function BuildSection(col, y, title)
    local text = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    text:SetText(title)
    text:SetTextColor(1, 0.82, 0)

    local rule = col:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y - 18)
    rule:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, -y - 18)
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    return y + H_SECTION
end

---Rótulo EM CIMA do controle, não ao lado.
---
---Numa coluna de 288px, rótulo à esquerda deixaria ~110px para o texto e ~170 para o controle,
---e "Abrir ao fim de uma corrida de Mítico+" não cabe em 110. Em cima, o rótulo tem a coluna
---inteira e o controle também.
local function BuildLabel(col, y, label)
    local text = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    text:SetWidth(COL_W)
    text:SetJustifyH("LEFT")
    text:SetText(label)
    return y + 16
end

local function BuildSlider(col, y, label, low, high, suffix, get, set)
    local at = BuildLabel(col, y, label)

    local slider = CreateFrame("Slider", nil, col, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -at)
    slider:SetWidth(COL_W)
    slider:SetHeight(22)
    Probe(label, slider, 0, COL_W)

    -- `Init(valor, min, max, passos, formatadores)`. Os passos são o número de INTERVALOS, e por
    -- isso é `high - low`: com um a mais o deslizador para em posições fracionárias e o número
    -- pisca entre dois inteiros.
    if slider.Init then
        slider:Init(get(), low, high, high - low, {
            [MinimalSliderWithSteppersMixin.Label.Right] = CreateMinimalSliderFormatter(
                MinimalSliderWithSteppersMixin.Label.Right,
                function(value) return (suffix or "%d"):format(value) end),
        })
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, value) set(value) end)
    end

    slider.Refresh = function()
        if slider.SetValue then slider:SetValue(get()) end
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
    dropdown:SetHeight(24)
    Probe(label, dropdown, 0, COL_W)

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
        check.Text:SetWidth(COL_W - CHECK_SIZE - 6)
        check.Text:SetJustifyH("LEFT")
    end
    Probe(label, check, 0, COL_W)

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
    b:SetSize(COL_W, 24)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    Probe(label, b, 0, COL_W)
    return y + H_BUTTON, b
end

--------------------------------------------------------------------------------
-- Linha da lista de colunas
--------------------------------------------------------------------------------
local function BuildRow(index, column, col, y)
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, col)
        row:SetSize(COL_W, H_COLUMN_ROW)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetScript("OnClick", function(self)
            ns.Window.ToggleColumn(self.columnKey)
            Picker.Refresh()
        end)

        row.down = CreateFrame("Button", nil, row)
        row.down:SetSize(18, 18)
        row.down:SetPoint("RIGHT", -2, 0)
        row.down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        row.down:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        row.down:SetScript("OnClick", function(self)
            local at = IndexOf(self.columnKey)
            if at then
                ns.Window.MoveColumn(at, 1)
                Picker.Refresh()
            end
        end)

        row.up = CreateFrame("Button", nil, row)
        row.up:SetSize(18, 18)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -2, 0)
        row.up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        row.up:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        row.up:SetScript("OnClick", function(self)
            local at = IndexOf(self.columnKey)
            if at then
                ns.Window.MoveColumn(at, -1)
                Picker.Refresh()
            end
        end)

        row.order = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.order:SetPoint("RIGHT", row.up, "LEFT", -6, 0)

        -- Largura EXPLÍCITA para o rótulo, pelo mesmo motivo do checkbox: sem ela um nome longo
        -- empurra as setas para fora da coluna.
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.label:SetWidth(COL_W - 22 - 4 - 18 - 18 - 28)
        row.label:SetJustifyH("LEFT")

        row:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
        rows[index] = row
    end

    row.check.columnKey = column.key
    row.up.columnKey = column.key
    row.down.columnKey = column.key

    local enabled = IsEnabled(column.key)
    row.check:SetChecked(enabled)
    row.label:SetText(column.label)

    if enabled then
        local position = IndexOf(column.key)
        row.label:SetTextColor(1, 1, 1)
        -- "1." e não "1º": o ordinal masculino só existe em algumas línguas latinas, e em
        -- inglês, alemão ou coreano vira lixo. O ponto é o que o próprio medidor nativo usa
        -- para numerar linha (`DAMAGE_METER_SOURCE_NAME = "%d. %s"`).
        row.order:SetText(position .. ".")
        row.order:Show()
        row.up:Show()
        row.down:Show()
        row.up:SetEnabled(position > 1)
        row.down:SetEnabled(position < #ns.db.columns)
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

    local columns = ns.Data.GetColumns()
    rows, probes = {}, {}

    -- ALTURA: soma de cada coluna, e a janela fica com a maior. Contar aqui, com as MESMAS
    -- constantes que posicionam os controles, é o que impede a janela de sobrar ou faltar
    -- espaço quando uma linha é acrescentada.
    local leftHeight = H_SECTION + #columns * H_COLUMN_ROW
    local rightHeight = H_SECTION + H_FIELD * 4 + H_CHECK * 2          -- Aparência
        + GAP_SECTION + H_SECTION + H_CHECK * 2 + 4 + H_BUTTON * 2     -- Placar
    local content = math.max(leftHeight, rightHeight)

    frame = CreateFrame("Frame", ADDON .. "Picker", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WIDTH, TOP + content + FOOTER)
    frame:SetFrameStrata("DIALOG")
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

    ---Uma coluna é um Frame de largura fixa. Todo controle é posicionado em relação a ELA, e
    ---nunca à janela — foi posicionar em relação à janela que fez o rótulo sair pela borda.
    local function Column(index)
        local col = CreateFrame("Frame", nil, frame)
        col:SetWidth(COL_W)
        col:SetPoint("TOPLEFT", frame, "TOPLEFT",
            MARGIN + (index - 1) * (COL_W + GUTTER), -TOP)
        col:SetPoint("BOTTOM", frame, "BOTTOM", 0, FOOTER)
        return col
    end

    local left, right = Column(1), Column(2)
    frame.leftColumn, frame.rightColumn = left, right

    -- Coluna 1: quais colunas a janela mostra, e em que ordem.
    frame.columnsTop = BuildSection(left, 0, L["Columns"])

    -- Coluna 2: aparência e placar.
    local y = BuildSection(right, 0, L["Appearance"])

    local fontEntries = {}
    for _, choice in ipairs(ns.FONT_CHOICES) do
        fontEntries[#fontEntries + 1] = { label = choice.label, value = choice.path }
    end
    y, frame.fontDrop = BuildDropdown(right, y, L["Font"], fontEntries,
        function() return ns.FontPath() end,
        function(v) ns.Window.SetFont(v) end)

    y, frame.sizeSlider = BuildSlider(right, y, L["Text size"],
        ns.Skin.fontSizeMin, ns.Skin.fontSizeMax, "%dpx",
        function() return ns.Window.GetFontSize() end,
        function(v) ns.Window.SetFontSize(v) end)

    y, frame.outlineDrop = BuildDropdown(right, y, L["Font outline"], {
        { label = L["None"],  value = "none" },
        { label = L["Thin"],  value = "thin" },
        { label = L["Thick"], value = "thick" },
    },
        function() return ns.db.fontOutline or "thin" end,
        function(v) ns.Window.SetOutline(v) end)

    y, frame.rowsSlider = BuildSlider(right, y, L["Rows"],
        ns.Skin.rowsMin, ns.Skin.rowsMax, "%d",
        function() return ns.Window.GetRows() or 5 end,
        function(v) ns.Window.SetRows(v) end)

    y, frame.shadowCheck = BuildCheck(right, y, L["Font shadow"],
        L["A 1px black shadow below the text. Carries the letters over any background."],
        function() return ns.db.fontShadow ~= false end,
        function(v) ns.Window.SetShadow(v) end)

    y, frame.realmCheck = BuildCheck(right, y, L["Show the realm next to the name"],
        L["Off by default: the realm eats the column and the name is what ends up cut."],
        function() return ns.db.showRealm end,
        function(v)
            ns.db.showRealm = v
            ns.Window.Refresh()
        end)

    y = BuildSection(right, y + GAP_SECTION, L["Scoreboard"])

    y, frame.autoMPlus = BuildCheck(right, y, L["Open at the end of a Mythic+ run"],
        L["When the keystone ends, the summary of the run opens by itself."],
        function() return ns.db.autoScoreboardMPlus end,
        function(v) ns.db.autoScoreboardMPlus = v end)

    y, frame.autoRaid = BuildCheck(right, y, L["Open when a raid boss dies"],
        L["When an encounter is defeated, the summary of the fight opens by itself."],
        function() return ns.db.autoScoreboardRaid end,
        function(v) ns.db.autoScoreboardRaid = v end)

    -- Os dois últimos placares. Apagados quando não há corrida guardada: botão que responde com
    -- erro no chat ensina menos que botão apagado.
    y, frame.lastMPlus = BuildButton(right, y + 4, L["Last Mythic+"],
        L["Opens the scoreboard of the last Mythic+ run finished on this character."],
        function() ns.Scoreboard.ShowLast("mplus") end)
    frame.lastMPlus.hasRun = "mplus"

    y, frame.lastRaid = BuildButton(right, y, L["Last raid"],
        L["Opens the scoreboard of the last raid boss defeated on this character."],
        function() ns.Scoreboard.ShowLast("raid") end)
    frame.lastRaid.hasRun = "raid"

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(WIDTH - MARGIN * 2, 24)
    clear:SetPoint("BOTTOMLEFT", MARGIN, 12)
    clear:SetText(L["Clear the data"])
    clear:SetScript("OnClick", function() ns.Data.RequestReset() end)

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
    top = TOP,
    footer = FOOTER,
    checkSize = CHECK_SIZE,
    field = H_FIELD,
    check = H_CHECK,
}

---Cada controle e onde ele fica DENTRO da coluna. É com isso que o harness confere que nada
---vaza pela borda.
function Picker.__probe()
    return probes
end

function Picker.__frameHeight()
    return frame and frame:GetHeight() or 0
end

--------------------------------------------------------------------------------
function Picker.RefreshRows()
    if not frame then return end
    for _, widget in ipairs({ frame.rowsSlider, frame.sizeSlider }) do
        if widget and widget.Refresh then widget.Refresh() end
    end
end

function Picker.Refresh()
    if not frame or not frame:IsShown() then return end

    for _, widget in ipairs({ frame.rowsSlider, frame.sizeSlider, frame.fontDrop,
                             frame.outlineDrop, frame.shadowCheck, frame.realmCheck,
                             frame.autoMPlus, frame.autoRaid }) do
        if widget and widget.Refresh then widget.Refresh() end
    end

    for _, b in ipairs({ frame.lastMPlus, frame.lastRaid }) do
        if b then b:SetEnabled(ns.Scoreboard.HasRun(b.hasRun)) end
    end

    local columns = ns.Data.GetColumns()
    for i = 1, #columns do
        BuildRow(i, columns[i], frame.leftColumn,
            frame.columnsTop + (i - 1) * H_COLUMN_ROW)
    end
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
