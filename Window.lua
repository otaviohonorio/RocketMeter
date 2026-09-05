-- RocketMeter | Window.lua
--
-- A linha é uma BARRA, não uma célula de planilha: fundo escuro, preenchimento na cor da
-- classe proporcional ao valor, ícone e nome por cima, número à direita — o formato do medidor
-- nativo do jogo. As métricas extras entram como colunas à direita, que é o ganho sobre abrir
-- uma janela por métrica.
--
-- Fonte, tamanho, altura de linha e largura são configuráveis; a janela redimensiona pela alça
-- do canto. Fecha só no X — nunca no ESC.
local ADDON, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window

local HEADER_HEIGHT = 22
local COLHEAD_HEIGHT = 14
local NAME_MIN_WIDTH = 110
local RANK_WIDTH = 16
local PADDING = 3
local GRIP = 14

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local frame, headerRow, rows
local dirty, throttle = false, 0
local visibleRows = -1

--------------------------------------------------------------------------------
-- Fonte e cor
--------------------------------------------------------------------------------
function ns.FontPath()
    return ns.db.font or "Fonts\\FRIZQT__.TTF"
end

---Aplica a fonte configurada. `delta` ajusta o corpo para rótulos secundários.
function ns.ApplyFont(fontString, delta, flags)
    local size = (ns.db.fontSize or 12) + (delta or 0)
    if size < 6 then size = 6 end
    fontString:SetFont(ns.FontPath(), size, flags or "")
    if flags == nil then
        fontString:SetShadowOffset(1, -1)
        fontString:SetShadowColor(0, 0, 0, 1)
    end
end

---Em combate `classFilename` pode ser secret, e indexar tabela com chave secret é proibido.
local function SafeClass(classFilename)
    if classFilename == nil or issecretvalue(classFilename) then
        return nil
    end
    return classFilename
end

function ns.ClassColor(classFilename)
    local class = SafeClass(classFilename)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
        return color.r, color.g, color.b
    end
    return 0.45, 0.5, 0.62
end

local function ApplyClassIcon(texture, classFilename)
    local class = SafeClass(classFilename)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        texture:SetTexture(CLASS_ICONS)
        texture:SetTexCoord(unpack(coords))
        texture:Show()
        return true
    end
    texture:Hide()
    return false
end

---Ícone da linha: especialização por padrão (diz mais que a classe — quem é o healer, quem
---tanka), com a classe como reserva quando a spec não veio.
function ns.ApplyRowIcon(texture, source)
    if ns.db.rowIcon ~= "class" then
        local specIcon = source.specIconID
        if specIcon ~= nil and not issecretvalue(specIcon) and specIcon ~= 0 then
            texture:SetTexture(specIcon)
            texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- corta a borda preta do ícone
            texture:Show()
            return
        end
    end
    ApplyClassIcon(texture, source.classFilename)
end

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------
local function RowHeight()
    return ns.db.rowHeight or 20
end

local function ColumnWidth()
    return ns.db.columnWidth or 58
end

local function ColumnOffsets()
    local columns = ns.db.columns
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + ColumnWidth()
    end
    return offsets, running
end

local function MinWidth()
    local _, columnsWidth = ColumnOffsets()
    return PADDING * 2 + NAME_MIN_WIDTH + columnsWidth
end

local function WindowWidth()
    local saved = ns.db.width or 0
    local minimum = MinWidth()
    return saved > minimum and saved or minimum
end

local function WindowHeight(rowCount)
    if rowCount < 1 then rowCount = 1 end
    return HEADER_HEIGHT + COLHEAD_HEIGHT + rowCount * (RowHeight() + 1) + PADDING
end

--------------------------------------------------------------------------------
-- Cabeçalho das colunas
--------------------------------------------------------------------------------
local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
        headerRow.bg = headerRow:CreateTexture(nil, "BACKGROUND")
        headerRow.bg:SetAllPoints()
        headerRow.bg:SetColorTexture(1, 1, 1, 0.05)
    end

    headerRow:ClearAllPoints()
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -HEADER_HEIGHT)
    headerRow:SetHeight(COLHEAD_HEIGHT)

    for _, button in pairs(headerRow.labels) do
        button:Hide()
    end

    local offsets = ColumnOffsets()

    for c = 1, #ns.db.columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(COLHEAD_HEIGHT)
            button.text = button:CreateFontString(nil, "OVERLAY")
            button.text:SetPoint("RIGHT", -4, 0)

            -- Seta como textura: o caractere unicode não existe na fonte do jogo.
            button.arrow = button:CreateTexture(nil, "OVERLAY")
            button.arrow:SetSize(10, 10)
            button.arrow:SetPoint("RIGHT", button.text, "LEFT", -1, 0)
            button.arrow:SetVertexColor(1, 0.75, 0.4)
            button.arrow:Hide()

            button:SetScript("OnClick", function(self)
                local key = ns.db.columns[self.columnIndex]
                if IsShiftKeyDown() then
                    Window.MoveColumn(self.columnIndex, -1)
                elseif IsControlKeyDown() then
                    Window.MoveColumn(self.columnIndex, 1)
                elseif ns.db.sortBy == key then
                    ns.db.sortDesc = not ns.db.sortDesc
                    Window.Refresh(true)
                else
                    ns.db.sortBy = key
                    ns.db.sortDesc = true
                    Window.Refresh(true)
                end
            end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(ns.Data.GetAttributeLabel(ns.db.columns[self.columnIndex]), 1, 1, 1)
                GameTooltip:AddLine(L["Click to sort by this column."], 0.7, 0.7, 0.7)
                GameTooltip:AddLine(L["Click again to reverse the order."], 0.7, 0.7, 0.7)
                GameTooltip:AddLine(L["Shift-click moves it left, Ctrl-click moves it right."], 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            headerRow.labels[c] = button
        end

        local key = ns.db.columns[c]
        button.columnIndex = c
        button:SetWidth(ColumnWidth())
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -offsets[c], 0)
        ns.ApplyFont(button.text, -2, "")

        local label = ns.Data.GetShortLabel(key)
        if key == ns.db.sortBy then
            button.text:SetText(label)
            button.text:SetTextColor(1, 0.75, 0.4)
            button.arrow:SetTexture(ns.db.sortDesc
                and "Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up"
                or "Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
            button.arrow:Show()
        else
            button.text:SetText(label)
            button.text:SetTextColor(0.55, 0.55, 0.58)
            button.arrow:Hide()
        end
        button:Show()
    end
end

--------------------------------------------------------------------------------
-- Linhas: cada uma é uma barra
--------------------------------------------------------------------------------
local function BuildRow(index)
    local row = rows[index]
    if not row then
        row = CreateFrame("Button", nil, frame)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0, 0, 0, 0.55)

        -- O preenchimento: cor sólida da classe, largura proporcional ao valor.
        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT", 1, -1)
        row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        row.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)

        row.highlight = row:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.12)

        row.rank = row:CreateFontString(nil, "OVERLAY")
        row.rank:SetPoint("LEFT", 5, 0)
        row.rank:SetWidth(RANK_WIDTH)
        row.rank:SetJustifyH("LEFT")

        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetPoint("LEFT", row.rank, "RIGHT", 0, 0)

        row.name = row:CreateFontString(nil, "OVERLAY")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetJustifyH("LEFT")

        row.cells = {}
        rows[index] = row
    end

    local height = RowHeight()
    row:SetHeight(height)
    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + COLHEAD_HEIGHT + (index - 1) * (height + 1))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, offsetY)

    local iconSize = height - 4
    row.icon:SetSize(iconSize, iconSize)
    ns.ApplyFont(row.rank, -2)
    ns.ApplyFont(row.name, 0)

    for _, cell in pairs(row.cells) do
        cell:Hide()
    end

    local offsets, columnsWidth = ColumnOffsets()

    for c = 1, #ns.db.columns do
        local cell = row.cells[c]
        if not cell then
            cell = row:CreateFontString(nil, "OVERLAY")
            cell:SetJustifyH("RIGHT")
            row.cells[c] = cell
        end
        -- A coluna de ordenação é a que importa: fica no corpo cheio, as outras menores.
        ns.ApplyFont(cell, ns.db.columns[c] == ns.db.sortBy and 0 or -1)
        cell:SetWidth(ColumnWidth() - 8)
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row, "RIGHT", -offsets[c] - 4, 0)
        cell:Show()
    end

    row.name:SetWidth(WindowWidth() - PADDING * 2 - columnsWidth - RANK_WIDTH - iconSize - 14)
    return row
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------
function Window.Create()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "BackdropTemplate")
    frame:SetSize(WindowWidth(), WindowHeight(1))
    frame:SetScale(ns.db.scale)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.02, 0.02, 0.03, 0.75)
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    if header.bg.SetAtlas then
        header.bg:SetAtlas("ui-damagemeters-header-bar", false)
    end
    if not header.bg:GetTexture() then
        header.bg:SetColorTexture(0.10, 0.12, 0.18, 0.95)
    end

    header.segment = CreateFrame("Button", nil, header)
    header.segment:SetSize(110, HEADER_HEIGHT - 4)
    header.segment:SetPoint("LEFT", 6, 0)
    header.segment.text = header.segment:CreateFontString(nil, "OVERLAY")
    header.segment.text:SetPoint("LEFT")
    header.segment.text:SetTextColor(1, 0.85, 0.45)
    header.segment:SetScript("OnClick", function()
        ns.db.sessionType = ns.db.sessionType == 0 and 1 or 0
        Window.Refresh(true)
    end)
    header.segment:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Click to switch between the current fight and the overall."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header.segment:SetScript("OnLeave", GameTooltip_Hide)

    header.clock = header:CreateFontString(nil, "OVERLAY")
    header.clock:SetPoint("LEFT", header.segment, "RIGHT", 2, 0)
    header.clock:SetTextColor(0.78, 0.78, 0.8)

    frame.header = header

    local function HeaderButton(texture, tooltip, onClick)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(14, 14)
        b:SetNormalTexture(texture)
        local tex = b:GetNormalTexture()
        if tex then tex:SetVertexColor(0.72, 0.72, 0.74) end
        b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            local t = self:GetNormalTexture()
            if t then t:SetVertexColor(1, 1, 1) end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            local t = self:GetNormalTexture()
            if t then t:SetVertexColor(0.72, 0.72, 0.74) end
            GameTooltip_Hide()
        end)
        return b
    end

    frame.closeButton = HeaderButton("Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
        L["Close"], function() Window.Hide() end)
    frame.closeButton:SetPoint("RIGHT", header, "RIGHT", -4, 0)

    frame.gearButton = HeaderButton("Interface\\Buttons\\UI-OptionsButton",
        L["Configure columns"], function() ns.Picker.Toggle(frame) end)
    frame.gearButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -3, 0)

    frame.resetButton = HeaderButton("Interface\\Buttons\\UI-RefreshButton",
        L["Clear the data"], function() ns.Data.RequestReset() end)
    frame.resetButton:SetPoint("RIGHT", frame.gearButton, "LEFT", -3, 0)

    if ns.db.pos then
        frame:SetPoint(ns.db.pos.point, UIParent, ns.db.pos.relPoint, ns.db.pos.x, ns.db.pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.OpenOptions() end
    end)

    -- Alça de redimensionamento: largura livre, altura em número de linhas.
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MinWidth(), WindowHeight(1))
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function()
        if ns.db.locked then return end
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        ns.db.width = frame:GetWidth()

        -- A altura vira quantidade de linhas: é o que faz sentido num medidor.
        local usable = frame:GetHeight() - HEADER_HEIGHT - COLHEAD_HEIGHT - PADDING
        local count = math.floor(usable / (RowHeight() + 1) + 0.5)
        if count < 1 then count = 1 end
        if count > 40 then count = 40 end
        ns.db.rows = count

        Window.Rebuild()
    end)
    frame.grip = grip

    rows = {}
    Window.Rebuild()

    frame:SetScript("OnUpdate", function(_, elapsed)
        if not dirty then return end
        throttle = throttle + elapsed
        if throttle < 0.2 then return end
        throttle, dirty = 0, false
        Window.Draw()
    end)

    return frame
end

---Refaz cabeçalho, linhas e medidas — depois de mudar colunas, fonte, tamanho ou largura.
function Window.Rebuild()
    if not frame then return end

    ns.ApplyFont(frame.header.segment.text, 0)
    ns.ApplyFont(frame.header.clock, -1)

    BuildColumnHeader()
    for i = 1, ns.db.rows do
        BuildRow(i)
    end
    for i = ns.db.rows + 1, #rows do
        rows[i]:Hide()
    end

    frame:SetWidth(WindowWidth())
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MinWidth(), WindowHeight(1))
    end

    visibleRows = -1
    Window.Refresh(true)
end

function Window.Refresh(immediate)
    if not frame then return end
    if immediate then
        dirty, throttle = false, 0
        Window.Draw()
    else
        dirty = true
    end
end

---Escreve o valor de uma célula. Fora de combate formata; dentro, repassa o valor cru ao
---FontString (o motor renderiza secret values que o Lua não pode ler).
function ns.SetCellText(fontString, value, columnKey)
    if value == nil then
        fontString:SetText("|cff4a4a4a-|r")
        return
    end

    if ns.Data.IsPercentColumn(columnKey) then
        fontString:SetText(ns.Data.FormatPercent(value) or "|cff4a4a4a-|r")
        return
    end

    local text = ns.Data.FormatAmount(value)
    if not text then
        fontString:SetText(value)
        return
    end

    if ns.Data.IsRateColumn(columnKey) then
        fontString:SetText(text .. "|cff777777/s|r")
    else
        fontString:SetText(text)
    end
end

function Window.Draw()
    if not frame or not frame:IsShown() then return end

    local data, session = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
        ns.db.rows, not ns.db.sortDesc)
    local maxAmount = session and session.maxAmount

    local scope = ns.db.sessionType == 0 and L["Current fight"] or L["Overall"]
    frame.header.segment.text:SetText(scope)

    local duration = ns.Data.GetDuration(ns.db.sessionType)
    if duration and not issecretvalue(duration) and duration > 0 then
        frame.header.clock:SetText(SecondsToClock(duration))
    else
        frame.header.clock:SetText("")
    end

    local shown = 0
    for i = 1, ns.db.rows do
        local row = rows[i]
        local entry = data and data[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source
            shown = i

            row.bar:SetMinMaxValues(0, maxAmount or 1)
            row.bar:SetValue(source.totalAmount or 0)
            local r, g, b = ns.ClassColor(source.classFilename)
            row.bar:SetStatusBarColor(r, g, b, 1)

            row.rank:SetText(i .. ".")
            row.rank:SetTextColor(0.85, 0.85, 0.88)
            ns.ApplyRowIcon(row.icon, source)
            row.name:SetText(source.name)
            row.name:SetTextColor(1, 1, 1)

            for c = 1, #ns.db.columns do
                ns.SetCellText(row.cells[c], entry.values[c], ns.db.columns[c])
            end

            row:Show()
        end
    end

    if shown ~= visibleRows then
        visibleRows = shown
        frame:SetHeight(WindowHeight(shown))
    end
end

--------------------------------------------------------------------------------
-- Visibilidade
--------------------------------------------------------------------------------
function Window.Show(remember)
    if not frame then Window.Create() end
    frame:Show()
    if remember ~= false then ns.db.shown = true end
    Window.Refresh(true)
end

function Window.Hide(remember)
    if not frame then return end
    frame:Hide()
    if remember ~= false then ns.db.shown = false end
end

function Window.Toggle()
    if not frame then Window.Create() end
    if frame:IsShown() then
        Window.Hide()
    else
        Window.Show()
    end
end

function Window.ApplyVisibility()
    if not frame then return end

    if ns.db.combatOnly and not InCombatLockdown() then
        frame:Hide()
        return
    end

    if ns.db.shown then
        frame:Show()
        Window.Refresh(true)
    else
        frame:Hide()
    end
end

function Window.OnCombatStart()
    if ns.db.combatOnly and ns.db.shown then
        Window.Show(false)
    end
end

function Window.OnCombatEnd()
    if ns.db.combatOnly then
        C_Timer.After(ns.db.hideDelay or 5, function()
            if ns.db.combatOnly and not InCombatLockdown() then
                Window.Hide(false)
            end
        end)
    end
end

function Window.ApplyScale()
    if frame then frame:SetScale(ns.db.scale) end
end

--------------------------------------------------------------------------------
-- Colunas
--------------------------------------------------------------------------------
function Window.ToggleColumn(key)
    local columns = ns.db.columns
    for i = 1, #columns do
        if columns[i] == key then
            if #columns == 1 then
                ns.Print(L["at least one column must stay."])
                return
            end
            tremove(columns, i)
            if ns.db.sortBy == key then
                ns.db.sortBy = columns[1]
            end
            ns.db.width = nil        -- deixa a largura voltar ao mínimo das colunas
            Window.Rebuild()
            return
        end
    end

    columns[#columns + 1] = key
    ns.db.width = nil
    Window.Rebuild()
end

function Window.MoveColumn(index, direction)
    local columns = ns.db.columns
    local target = index + direction
    if target < 1 or target > #columns then return end

    columns[index], columns[target] = columns[target], columns[index]
    Window.Rebuild()
end

function Window.ApplyPreset(name)
    local preset = ns.Data.GetPresets()[name]
    if not preset then return false end
    ns.db.columns = CopyTable(preset.columns)
    ns.db.sortBy = ns.db.columns[1]
    ns.db.width = nil
    Window.Rebuild()
    return true
end
