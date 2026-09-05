-- RocketMeter | Picker.lua
-- A única tela de configuração do addon, em três abas: Colunas, Aparência e Placar.
--
-- POR QUE ABAS. Ela nasceu com uma lista de colunas e foi ganhando caixa por caixa até virar um
-- rodapé de 236px com sete controles empilhados sem hierarquia nenhuma. O usuário apontou a
-- janela de configuração do Chattynator como o que queria: abas no topo, rótulo à direita e
-- controle à esquerda, uma coisa por linha.
--
-- OS COMPONENTES SÃO OS DA BLIZZARD, e os nomes foram conferidos na fonte do 12.1.0 — não vêm
-- de "o Chattynator usa, então existe", que é a falácia que já custou uma rodada aqui:
--
--   `PanelTopTabButtonTemplate`          SharedUIPanelTemplates.xml
--   `MinimalSliderWithSteppersTemplate`  Shared/Slider/MinimalSlider.xml
--   `WowStyle1DropdownTemplate`          Blizzard_Menu/Classic/MenuTemplates.xml
--   `PanelTemplates_TabResize` / `_SelectTab` / `_DeselectTab`   SharedUIPanelTemplates.lua
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

local WIDTH = 360
local ROW_HEIGHT = 22
local TAB_TOP = 30              -- espaço que a fileira de abas ocupa
local CONTENT_TOP = 62          -- primeira linha de conteúdo, abaixo das abas
local LINE = 30                 -- passo vertical entre controles
local FOOTER = 40               -- o botão de limpar dados, sempre visível

local frame, rows

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
-- Um layout só para os três: rótulo alinhado à DIREITA até 40% da largura, controle começando
-- logo depois. É o que dá a coluna vertical que faz a tela parecer organizada — e é o que a
-- janela do Chattynator faz.
local LABEL_RIGHT = 0.40

local function BuildLabel(container, y, text)
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y - 4)
    label:SetWidth(WIDTH * LABEL_RIGHT - 16)
    label:SetJustifyH("RIGHT")
    label:SetText(text)
    return label
end

---Caixa de opção. O rótulo vai no `Text` que o template já traz — FontString solta ao lado sai
---de sincronia com a caixa quando o painel muda de tamanho.
local function BuildCheck(container, y, label, tip, get, set)
    local check = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", container, "TOPLEFT", WIDTH * LABEL_RIGHT - 4, -y)
    check:SetSize(24, 24)

    -- Testa o TIPO, não só a verdade: um stub que devolve função aqui passa no `if` e só
    -- estoura no `SetText`. Já aconteceu neste projeto, com `frame.Inset`.
    if type(check.Text) == "table" and check.Text.SetText then
        check.Text:SetText(label)
        check.Text:SetFontObject("GameFontHighlightSmall")
    end

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
    return check
end

---Deslizador com os dois passos e o valor à direita, como na referência.
local function BuildSlider(container, y, label, low, high, suffix, get, set)
    BuildLabel(container, y, label)

    local slider = CreateFrame("Slider", nil, container, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("TOPLEFT", container, "TOPLEFT", WIDTH * LABEL_RIGHT, -y)
    slider:SetPoint("RIGHT", container, "RIGHT", -46, 0)
    slider:SetHeight(20)

    -- `Init(valor, min, max, passos, formatadores)`. Os passos são o número de INTERVALOS, e
    -- por isso é `high - low` e não a contagem de valores: com um a mais o deslizador para em
    -- posições fracionárias e o número pisca entre dois inteiros.
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
    return slider
end

---Combo de escolha única.
---
---`MenuUtil.CreateRadioMenu(dropdown, isSelected, setSelected, ...)` recebe os itens como pares
---`{ rótulo, valor }`. A marca de seleção sai de `isSelected`, então não há estado duplicado
---aqui dentro — ela é sempre a resposta de quem guarda a configuração.
local function BuildDropdown(container, y, label, entries, get, set)
    BuildLabel(container, y, label)

    local dropdown = CreateFrame("DropdownButton", nil, container, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", container, "TOPLEFT", WIDTH * LABEL_RIGHT, -y)
    dropdown:SetPoint("RIGHT", container, "RIGHT", -8, 0)
    dropdown:SetHeight(24)

    if MenuUtil and MenuUtil.CreateRadioMenu then
        local pairsList = {}
        for _, entry in ipairs(entries) do
            pairsList[#pairsList + 1] = { entry.label, entry.value }
        end
        MenuUtil.CreateRadioMenu(dropdown,
            function(value) return get() == value end,
            function(value) set(value) end,
            unpack(pairsList))
    end

    dropdown.Refresh = function()
        if dropdown.GenerateMenu then dropdown:GenerateMenu() end
    end
    return dropdown
end

--------------------------------------------------------------------------------
-- Linha da lista de colunas
--------------------------------------------------------------------------------
local function BuildRow(index, column, container)
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, container)
        row:SetSize(WIDTH - 40, ROW_HEIGHT)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetScript("OnClick", function(self)
            ns.Window.ToggleColumn(self.columnKey)
            Picker.Refresh()
        end)

        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.label:SetJustifyH("LEFT")

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
        row.order:SetPoint("RIGHT", row.up, "LEFT", -4, 0)

        row:SetPoint("TOPLEFT", container, "TOPLEFT", 8, -((index - 1) * ROW_HEIGHT))
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
-- Abas
--------------------------------------------------------------------------------
local tabs, panels = {}, {}

local function SelectTab(index)
    for i, tab in ipairs(tabs) do
        if i == index then
            PanelTemplates_SelectTab(tab)
            panels[i]:Show()
        else
            PanelTemplates_DeselectTab(tab)
            panels[i]:Hide()
        end
    end
    frame.activeTab = index
    Picker.__activeTab = index
    Picker.__tabCount = #tabs
    Picker.Refresh()
end

-- Ganchos para o harness. A troca de aba é a parte testável desta tela: sem eles o teste teria
-- que redescobrir os frames por `_G` e passaria a testar o simulador em vez do addon.
Picker.__selectTab = function(index) SelectTab(index) end
Picker.__panelShown = function(index) return panels[index] and panels[index]:IsShown() or false end

local function BuildTab(index, label)
    local tab = CreateFrame("Button", ADDON .. "PickerTab" .. index, frame,
        "PanelTopTabButtonTemplate")
    tab:SetText(label)
    tab:SetScript("OnClick", function() SelectTab(index) end)

    -- `PanelTemplates_TabResize` mede o texto e ajusta a largura. Sem ela, o botão fica no
    -- tamanho do template e o rótulo vaza para fora.
    if PanelTemplates_TabResize then PanelTemplates_TabResize(tab, 15, nil, 10) end

    if index == 1 then
        tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -TAB_TOP)
    else
        tab:SetPoint("LEFT", tabs[index - 1], "RIGHT", -14, 0)
    end

    tabs[index] = tab

    local panel = CreateFrame("Frame", nil, frame)
    panel:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -CONTENT_TOP)
    panel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -14, FOOTER)
    panels[index] = panel
    return panel
end

--------------------------------------------------------------------------------
function Picker.Create()
    if frame then return frame end

    local columns = ns.Data.GetColumns()
    -- A altura é a da aba mais alta — a de colunas, que tem uma linha por métrica.
    local height = CONTENT_TOP + #columns * ROW_HEIGHT + LINE + FOOTER + 10

    frame = CreateFrame("Frame", ADDON .. "Picker", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WIDTH, height)
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

    rows = {}

    ----------------------------------------------------------------------------
    -- Aba 1: colunas
    ----------------------------------------------------------------------------
    local colunas = BuildTab(1, L["Columns"])
    frame.columnsPanel = colunas

    frame.rowsSlider = BuildSlider(colunas, #columns * ROW_HEIGHT + 6, L["Rows"],
        ns.Skin.rowsMin, ns.Skin.rowsMax, "%d",
        function() return ns.Window.GetRows() or 5 end,
        function(v) ns.Window.SetRows(v) end)

    ----------------------------------------------------------------------------
    -- Aba 2: aparência
    ----------------------------------------------------------------------------
    local aparencia = BuildTab(2, L["Appearance"])

    local fontEntries = {}
    for _, choice in ipairs(ns.FONT_CHOICES) do
        fontEntries[#fontEntries + 1] = { label = choice.label, value = choice.path }
    end
    frame.fontDrop = BuildDropdown(aparencia, 0, L["Font"], fontEntries,
        function() return ns.FontPath() end,
        function(v) ns.Window.SetFont(v) end)

    frame.sizeSlider = BuildSlider(aparencia, LINE, L["Text size"],
        ns.Skin.fontSizeMin, ns.Skin.fontSizeMax, "%dpx",
        function() return ns.Window.GetFontSize() end,
        function(v) ns.Window.SetFontSize(v) end)

    frame.outlineDrop = BuildDropdown(aparencia, LINE * 2, L["Font outline"], {
        { label = L["None"],  value = "none" },
        { label = L["Thin"],  value = "thin" },
        { label = L["Thick"], value = "thick" },
    },
        function() return ns.db.fontOutline or "thin" end,
        function(v) ns.Window.SetOutline(v) end)

    frame.shadowCheck = BuildCheck(aparencia, LINE * 3, L["Font shadow"],
        L["A 1px black shadow below the text. Carries the letters over any background."],
        function() return ns.db.fontShadow ~= false end,
        function(v) ns.Window.SetShadow(v) end)

    frame.realmCheck = BuildCheck(aparencia, LINE * 4, L["Show the realm next to the name"],
        L["Off by default: the realm eats the column and the name is what ends up cut."],
        function() return ns.db.showRealm end,
        function(v)
            ns.db.showRealm = v
            ns.Window.Refresh()
        end)

    ----------------------------------------------------------------------------
    -- Aba 3: placar
    ----------------------------------------------------------------------------
    local placar = BuildTab(3, L["Scoreboard"])

    frame.autoMPlus = BuildCheck(placar, 0, L["Open at the end of a Mythic+ run"],
        L["When the keystone ends, the summary of the run opens by itself."],
        function() return ns.db.autoScoreboardMPlus end,
        function(v) ns.db.autoScoreboardMPlus = v end)

    frame.autoRaid = BuildCheck(placar, LINE, L["Open when a raid boss dies"],
        L["When an encounter is defeated, the summary of the fight opens by itself."],
        function() return ns.db.autoScoreboardRaid end,
        function(v) ns.db.autoScoreboardRaid = v end)

    -- Os dois últimos placares. Ficam aqui porque esta é a única tela de configuração do addon
    -- e o painel não tem outro ponto de entrada além do slash. Apagados quando não há corrida
    -- guardada: botão que responde com erro no chat ensina menos que botão apagado.
    local function ScoreButton(y, label, tip, kind)
        local b = CreateFrame("Button", nil, placar, "UIPanelButtonTemplate")
        b:SetSize(WIDTH - 60, 22)
        b:SetPoint("TOPLEFT", placar, "TOPLEFT", 8, -y)
        b:SetText(label)
        b:SetScript("OnClick", function() ns.Scoreboard.ShowLast(kind) end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b.hasRun = kind
        return b
    end

    frame.lastMPlus = ScoreButton(LINE * 2 + 6, L["Last Mythic+"],
        L["Opens the scoreboard of the last Mythic+ run finished on this character."], "mplus")
    frame.lastRaid = ScoreButton(LINE * 3 + 6, L["Last raid"],
        L["Opens the scoreboard of the last raid boss defeated on this character."], "raid")

    ----------------------------------------------------------------------------
    -- Rodapé, fora das abas: vale para o addon todo.
    ----------------------------------------------------------------------------
    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(WIDTH - 28, 22)
    clear:SetPoint("BOTTOMLEFT", 14, 10)
    clear:SetText(L["Clear the data"])
    clear:SetScript("OnClick", function() ns.Data.RequestReset() end)

    SelectTab(1)
    return frame
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
        BuildRow(i, columns[i], frame.columnsPanel)
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
