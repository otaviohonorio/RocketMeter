-- RocketMeter | Picker.lua
-- A única tela de configuração: quais colunas aparecem, em que ordem, e quantas linhas a
-- janela mostra.
--
-- Aparência não se configura — está fixa no código (ver o topo de `Window.lua`). Primeiro o
-- padrão precisa estar certo; opção de layout só espalha o problema em vez de resolvê-lo.
local ADDON, ns = ...
local L = ns.L

local Picker = {}
ns.Picker = Picker

local WIDTH = 260
local ROW_HEIGHT = 22
local TOP = 34
-- Rodapé, de baixo para cima: limpar dados, os dois últimos placares, a seção Placar com
-- as duas caixas de abertura automática, a caixa do reino e o contador de linhas.
local BOTTOM = 210

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

---Caixa de opção com rótulo à direita e dica.
---
---`UICheckButtonTemplate` já traz um `Text` posicionado; escrever nele evita uma FontString
---solta que sai de sincronia com a caixa quando o painel muda de tamanho.
local function BuildCheck(parent, y, label, tip, get, set)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetPoint("BOTTOMLEFT", 10, y)
    check:SetSize(24, 24)
    -- Testa o TIPO, não só a verdade: um stub que devolve função aqui passa no `if` e só
    -- estoura no `SetText`. Já aconteceu neste projeto, com `frame.Inset`.
    if type(check.Text) == "table" and check.Text.SetText then
        check.Text:SetText(label)
        check.Text:SetFontObject("GameFontHighlightSmall")
    end
    check:SetChecked(get())
    check:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
    end)
    check:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    check:SetScript("OnLeave", GameTooltip_Hide)
    check.Refresh = function(self) self:SetChecked(get()) end
    return check
end

---Divisória com título, no dourado que o addon usa para cabeçalho.
local function BuildSection(parent, y, title)
    local rule = parent:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", 12, y + 20)
    rule:SetPoint("BOTTOMRIGHT", -12, y + 20)
    rule:SetColorTexture(1, 0.82, 0, 0.20)

    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("BOTTOMLEFT", 12, y)
    text:SetText(title)
    text:SetTextColor(1, 0.82, 0)
    return text
end

local function BuildRow(index, column)
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, frame)
        row:SetSize(WIDTH - 24, ROW_HEIGHT)

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

        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(TOP + (index - 1) * ROW_HEIGHT))
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

function Picker.Create()
    if frame then return frame end

    local columns = ns.Data.GetColumns()

    frame = CreateFrame("Frame", ADDON .. "Picker", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WIDTH, TOP + #columns * ROW_HEIGHT + BOTTOM)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    if frame.SetTitle then
        frame:SetTitle(L["Configure"])
    end

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Quantas linhas mostrar: dois passos e o número no meio. Um slider aqui seria maior que
    -- o painel inteiro, e o valor é discreto (3 a 25) — steppers cabem melhor.
    local rowsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rowsLabel:SetPoint("BOTTOMLEFT", 12, 180)
    rowsLabel:SetText(L["Rows"])

    local function StepperButton(offsetX, delta, symbol)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(22, 20)
        b:SetPoint("BOTTOMLEFT", offsetX, 178)
        b:SetText(symbol)
        b:SetScript("OnClick", function()
            ns.Window.SetRows((ns.Window.GetRows() or 5) + delta)
            Picker.RefreshRows()
        end)
        return b
    end

    frame.rowsMinus = StepperButton(WIDTH - 92, -1, "-")

    frame.rowsValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.rowsValue:SetPoint("BOTTOMLEFT", WIDTH - 68, 180)
    frame.rowsValue:SetWidth(24)
    frame.rowsValue:SetJustifyH("CENTER")

    frame.rowsPlus = StepperButton(WIDTH - 42, 1, "+")

    -- Os dois últimos placares, lado a lado.
    --
    -- Não há botão de simulação aqui: ele existiu enquanto a aparência do placar estava sendo
    -- ajustada e foi removido depois de validada (05/09/2026). A simulação continua viva em
    -- `/rm score demo` — custa zero de tela e é o que economiza uma masmorra por rodada de
    -- ajuste, se a aparência voltar à mesa. Ficam aqui porque esta é a única tela de
    -- configuração do addon, e o placar não tem outro ponto de entrada além do slash.
    -- Desabilitados quando não há corrida guardada: botão que responde com uma mensagem de
    -- erro no chat ensina menos que um botão apagado.
    local function ScoreButton(offsetX, width, label, tip, onClick, hasRun)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("BOTTOMLEFT", offsetX, 38)
        b:SetText(label)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label, 1, 1, 1)
            GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        b.hasRun = hasRun
        return b
    end

    local half = math.floor((WIDTH - 28) / 2)

    frame.lastMPlus = ScoreButton(12, half, L["Last Mythic+"],
        L["Opens the scoreboard of the last Mythic+ run finished on this character."],
        function() ns.Scoreboard.ShowLast("mplus") end, "mplus")

    frame.lastRaid = ScoreButton(16 + half, half, L["Last raid"],
        L["Opens the scoreboard of the last raid boss defeated on this character."],
        function() ns.Scoreboard.ShowLast("raid") end, "raid")

    -- Seção Placar: quando o painel de fim de corrida abre sozinho. Duas caixas, porque quem
    -- quer o resumo de toda chave não necessariamente quer o de todo chefe de raide.
    BuildSection(frame, 126, L["Scoreboard"])

    frame.autoMPlus = BuildCheck(frame, 98,
        L["Open at the end of a Mythic+ run"],
        L["When the keystone ends, the summary of the run opens by itself."],
        function() return ns.db.autoScoreboardMPlus end,
        function(v) ns.db.autoScoreboardMPlus = v end)

    frame.autoRaid = BuildCheck(frame, 74,
        L["Open when a raid boss dies"],
        L["When an encounter is defeated, the summary of the fight opens by itself."],
        function() return ns.db.autoScoreboardRaid end,
        function(v) ns.db.autoScoreboardRaid = v end)

    -- O reino fica fora da seção: é da janela, não do placar.
    frame.showRealm = BuildCheck(frame, 150,
        L["Show the realm next to the name"],
        L["Off by default: the realm eats the column and the name is what ends up cut."],
        function() return ns.db.showRealm end,
        function(v)
            ns.db.showRealm = v
            ns.Window.Refresh()
        end)

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(WIDTH - 24, 22)
    clear:SetPoint("BOTTOMLEFT", 12, 10)
    clear:SetText(L["Clear the data"])
    clear:SetScript("OnClick", function() ns.Data.RequestReset() end)

    rows = {}
    return frame
end

---Atualiza só o contador de linhas.
function Picker.RefreshRows()
    if not frame or not frame.rowsValue then return end
    frame.rowsValue:SetText(tostring(ns.Window.GetRows() or 5))
end

function Picker.Refresh()
    if not frame or not frame:IsShown() then return end
    Picker.RefreshRows()

    for _, b in ipairs({ frame.lastMPlus, frame.lastRaid }) do
        b:SetEnabled(ns.Scoreboard.HasRun(b.hasRun))
    end

    local columns = ns.Data.GetColumns()
    for i = 1, #columns do
        BuildRow(i, columns[i])
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
