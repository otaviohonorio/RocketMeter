-- RocketMeter | Window.lua
-- Uma janela só, com a moldura nativa do jogo, e colunas escolhidas pelo usuário.
-- Cada linha é um jogador; cada coluna, uma métrica (total e por segundo são colunas
-- separadas, ligadas de forma independente).
local ADDON, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window

local ROW_HEIGHT = 18
local ROW_SPACING = 1
local HEADER_HEIGHT = 18
local COLUMN_WIDTH = 54
local NAME_MIN_WIDTH = 84
local TOP_INSET = 26          -- barra de título do DefaultPanelTemplate
local SIDE_INSET = 8

local frame, headerRow, rows
local dirty, throttle = false, 0

--------------------------------------------------------------------------------
-- Geometria das colunas
--------------------------------------------------------------------------------
local function ColumnWidth()
    return COLUMN_WIDTH
end

---Distância da borda direita até o início de cada coluna.
local function ColumnOffsets()
    local columns = ns.db.columns
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + ColumnWidth()
    end
    return offsets, running
end

local function WindowWidth()
    local _, columnsWidth = ColumnOffsets()
    return SIDE_INSET * 2 + NAME_MIN_WIDTH + columnsWidth
end

local function WindowHeight()
    return TOP_INSET + HEADER_HEIGHT + ns.db.rows * (ROW_HEIGHT + ROW_SPACING) + SIDE_INSET
end

function ns.ClassColor(classFilename)
    local color = classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if color then
        return color.r, color.g, color.b
    end
    return 0.55, 0.55, 0.58
end

--------------------------------------------------------------------------------
-- Cabeçalho: rótulo por coluna, clicável para trocar a ordenação.
--------------------------------------------------------------------------------
local function BuildHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
    end

    headerRow:ClearAllPoints()
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_INSET, -TOP_INSET)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_INSET, -TOP_INSET)
    headerRow:SetHeight(HEADER_HEIGHT)

    for _, button in pairs(headerRow.labels) do
        button:Hide()
    end

    local offsets = ColumnOffsets()

    for c = 1, #ns.db.columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(HEADER_HEIGHT)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("RIGHT", -4, 0)
            button:SetScript("OnClick", function(self)
                local attributeId = ns.db.columns[self.columnIndex]

                if IsShiftKeyDown() then
                    Window.MoveColumn(self.columnIndex, -1)
                elseif IsControlKeyDown() then
                    Window.MoveColumn(self.columnIndex, 1)
                elseif ns.db.sortBy == attributeId then
                    ns.db.sortDesc = not ns.db.sortDesc   -- mesma coluna: inverte a direção
                    Window.Refresh(true)
                else
                    ns.db.sortBy = attributeId
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

        local attributeId = ns.db.columns[c]
        button.columnIndex = c
        button:SetWidth(ColumnWidth())
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -offsets[c], 0)

        local label = ns.Data.GetShortLabel(attributeId)
        if attributeId == ns.db.sortBy then
            local arrow = ns.db.sortDesc and "|TInterface\Buttons\Arrow-Down-Up:12|t"
                or "|TInterface\Buttons\Arrow-Up-Up:12|t"
            button.text:SetText("|cffff6a00" .. label .. "|r" .. arrow)
        else
            button.text:SetText("|cffb0b0b0" .. label .. "|r")
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
        row = CreateFrame("StatusBar", nil, frame)
        row:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row:SetMinMaxValues(0, 1)
        row:SetValue(0)
        row:SetHeight(ROW_HEIGHT)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.04)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetJustifyH("LEFT")

        row.cells = {}
        rows[index] = row
    end

    row:ClearAllPoints()
    local offsetY = -(TOP_INSET + HEADER_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_SPACING))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_INSET, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_INSET, offsetY)

    for _, cell in pairs(row.cells) do
        cell:Hide()
    end

    local offsets, columnsWidth = ColumnOffsets()

    for c = 1, #ns.db.columns do
        local cell = row.cells[c]
        if not cell then
            cell = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetJustifyH("RIGHT")
            row.cells[c] = cell
        end
        cell:SetWidth(ColumnWidth() - 6)
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row, "RIGHT", -offsets[c] - 4, 0)
        cell:Show()
    end

    row.name:SetWidth(WindowWidth() - SIDE_INSET * 2 - columnsWidth - 8)
    return row
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------
function Window.Create()
    if frame then return frame end

    -- DefaultPanelTemplate = moldura padrão do jogo (borda, barra de título, fundo).
    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WindowWidth(), WindowHeight())
    frame:SetScale(ns.db.scale)
    frame:SetClampedToScreen(true)
    if frame.SetTitle then
        frame:SetTitle("Rocket Meter")
    end

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton = close

    -- Engrenagem: abre o painel de colunas colado na janela. A configuração que importa
    -- fica a um clique da janela, não escondida no menu do jogo.
    local gear = CreateFrame("Button", nil, frame)
    gear:SetSize(16, 16)
    gear:SetPoint("RIGHT", close, "LEFT", 0, 0)
    gear:SetNormalTexture("Interface\Buttons\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\Buttons\UI-Common-MouseHilight")
    gear:SetScript("OnClick", function()
        ns.Picker.Toggle(frame)
    end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Configure columns"], 1, 1, 1)
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", GameTooltip_Hide)
    frame.gearButton = gear

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

    rows = {}
    Window.Rebuild()

    frame:SetScript("OnUpdate", function(_, elapsed)
        if not dirty then return end
        throttle = throttle + elapsed
        if throttle < 0.2 then return end
        throttle, dirty = 0, false
        Window.Draw()
    end)

    tinsert(UISpecialFrames, frame:GetName())
    return frame
end

---Refaz cabeçalho e linhas — chamado quando as colunas ou a quantidade de linhas mudam.
function Window.Rebuild()
    if not frame then return end

    frame:SetSize(WindowWidth(), WindowHeight())
    BuildHeader()

    for i = 1, ns.db.rows do
        BuildRow(i)
    end
    for i = ns.db.rows + 1, #rows do
        rows[i]:Hide()
    end

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

---Escreve um valor que pode ser secret: formatado fora de combate, cru dentro.
---@param fontString table
---@param value any
---@param suffix string|nil sufixo aplicado só quando o valor é legível
function ns.SetAmountText(fontString, value, suffix)
    if value == nil then
        fontString:SetText("|cff5a5a5a—|r")
        return
    end
    local text = ns.Data.FormatAmount(value)
    if text then
        fontString:SetText(suffix and (text .. suffix) or text)
    else
        fontString:SetText(value)
    end
end

function Window.Draw()
    if not frame or not frame:IsShown() then return end

    local data, session = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
        ns.db.rows, not ns.db.sortDesc)
    local maxAmount = session and session.maxAmount

    if frame.SetTitle then
        local duration = ns.Data.GetDuration(ns.db.sessionType)
        local clock = (duration and not issecretvalue(duration)) and (" — " .. SecondsToClock(duration)) or ""
        local scope = ns.db.sessionType == 0 and L["Current fight"] or L["Overall"]
        frame:SetTitle("Rocket Meter |cff909090" .. scope .. clock .. "|r")
    end

    for i = 1, ns.db.rows do
        local row = rows[i]
        local entry = data and data[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source

            -- Barra: preenchida pela métrica de ordenação. Widget aceita secret value.
            row:SetMinMaxValues(0, maxAmount or 1)
            row:SetValue(source.totalAmount or 0)
            row:SetStatusBarColor(ns.ClassColor(source.classFilename))

            -- Nome pode ser secret em combate; o motor renderiza mesmo assim.
            row.name:SetText(source.name)

            for c = 1, #ns.db.columns do
                local suffix = ns.Data.IsRateColumn(ns.db.columns[c]) and "/s" or nil
                ns.SetAmountText(row.cells[c], entry.values[c], suffix)
            end

            row:Show()
        end
    end
end

function Window.Toggle()
    if not frame then Window.Create() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        Window.Refresh(true)
    end
end

function Window.ApplyScale()
    if frame then frame:SetScale(ns.db.scale) end
end

---Liga ou desliga uma coluna.
function Window.ToggleColumn(attributeId)
    local columns = ns.db.columns
    for i = 1, #columns do
        if columns[i] == attributeId then
            if #columns == 1 then
                ns.Print(L["at least one column must stay."])
                return
            end
            tremove(columns, i)
            if ns.db.sortBy == attributeId then
                ns.db.sortBy = columns[1]
            end
            Window.Rebuild()
            return
        end
    end

    columns[#columns + 1] = attributeId
    Window.Rebuild()
end

---Move uma coluna uma casa para a esquerda (-1) ou direita (+1).
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
    Window.Rebuild()
    return true
end
