-- RocketMeter | Window.lua
-- Visual do medidor nativo do Midnight: cabeçalho com o atlas `ui-damagemeters-header-bar`,
-- corpo escuro sem moldura pesada, linhas chapadas e finas. A janela **encolhe** para o número
-- de jogadores que existem de verdade — nada de caixa vazia esperando gente.
--
-- Cada linha é um jogador; cada coluna, uma métrica (total e por segundo são colunas
-- separadas, ligadas de forma independente).
local ADDON, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window

local ROW_HEIGHT = 16
local ROW_SPACING = 1
local HEADER_HEIGHT = 21        -- barra de título, como a do medidor da Blizzard
local COLHEAD_HEIGHT = 13       -- faixa dos rótulos de coluna
local COLUMN_WIDTH = 54
local NAME_MIN_WIDTH = 84
local PADDING = 3

local frame, headerRow, rows
local dirty, throttle = false, 0
local visibleRows = -1

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------
local function ColumnOffsets()
    local columns = ns.db.columns
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + COLUMN_WIDTH
    end
    return offsets, running
end

local function WindowWidth()
    local _, columnsWidth = ColumnOffsets()
    return PADDING * 2 + NAME_MIN_WIDTH + columnsWidth
end

---Altura para N linhas de verdade: a janela acompanha o grupo, não a configuração.
local function WindowHeight(rowCount)
    if rowCount < 1 then rowCount = 1 end
    return HEADER_HEIGHT + COLHEAD_HEIGHT + rowCount * (ROW_HEIGHT + ROW_SPACING) + PADDING
end

function ns.ClassColor(classFilename)
    local color = classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if color then
        return color.r, color.g, color.b
    end
    return 0.55, 0.55, 0.58
end

--------------------------------------------------------------------------------
-- Cabeçalho das colunas
--------------------------------------------------------------------------------
local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
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
            button:SetWidth(COLUMN_WIDTH)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            button.text:SetPoint("RIGHT", -3, 0)

            button:SetScript("OnClick", function(self)
                local attributeId = ns.db.columns[self.columnIndex]
                if IsShiftKeyDown() then
                    Window.MoveColumn(self.columnIndex, -1)
                elseif IsControlKeyDown() then
                    Window.MoveColumn(self.columnIndex, 1)
                elseif ns.db.sortBy == attributeId then
                    ns.db.sortDesc = not ns.db.sortDesc
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
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -offsets[c], 0)

        local label = ns.Data.GetShortLabel(attributeId)
        if attributeId == ns.db.sortBy then
            local arrow = ns.db.sortDesc and "|TInterface\\Buttons\\Arrow-Down-Up:10|t"
                or "|TInterface\\Buttons\\Arrow-Up-Up:10|t"
            button.text:SetText("|cffffb060" .. label .. "|r" .. arrow)
        else
            button.text:SetText("|cff909090" .. label .. "|r")
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
        row:SetHeight(ROW_HEIGHT)
        -- Textura chapada: é o que dá o ar do medidor nativo, sem relevo nem gradiente.
        row:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        row:SetMinMaxValues(0, 1)
        row:SetValue(0)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 4, 0)
        row.name:SetJustifyH("LEFT")

        row.cells = {}
        rows[index] = row
    end

    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + COLHEAD_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_SPACING))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, offsetY)

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
        cell:SetWidth(COLUMN_WIDTH - 6)
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row, "RIGHT", -offsets[c] - 3, 0)
        cell:Show()
    end

    row.name:SetWidth(WindowWidth() - PADDING * 2 - columnsWidth - 8)
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
    frame:SetBackdropColor(0.04, 0.04, 0.05, 0.85)
    frame:SetBackdropBorderColor(0, 0, 0, 1)

    -- Barra de título com o atlas do medidor nativo do jogo.
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

    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.title:SetPoint("LEFT", 6, 0)
    header.title:SetTextColor(1, 0.82, 0.35)

    frame.header = header

    -- Botões pequenos à direita do título, como no medidor da Blizzard.
    local function HeaderButton(texture, tooltip, onClick)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(14, 14)
        b:SetNormalTexture(texture)
        local tex = b:GetNormalTexture()
        if tex then tex:SetVertexColor(0.75, 0.75, 0.75) end
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
            if t then t:SetVertexColor(0.75, 0.75, 0.75) end
            GameTooltip_Hide()
        end)
        return b
    end

    frame.closeButton = HeaderButton("Interface\\Buttons\\UI-Panel-MinimizeButton-Up",
        L["Close"], function() frame:Hide() end)
    frame.closeButton:SetPoint("RIGHT", header, "RIGHT", -4, 0)

    frame.gearButton = HeaderButton("Interface\\Buttons\\UI-OptionsButton",
        L["Configure columns"], function() ns.Picker.Toggle(frame) end)
    frame.gearButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -3, 0)

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

function Window.Rebuild()
    if not frame then return end

    BuildColumnHeader()
    for i = 1, ns.db.rows do
        BuildRow(i)
    end
    for i = ns.db.rows + 1, #rows do
        rows[i]:Hide()
    end

    frame:SetWidth(WindowWidth())
    visibleRows = -1          -- força recalcular a altura no próximo desenho
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
function ns.SetAmountText(fontString, value, suffix)
    if value == nil then
        fontString:SetText("|cff4a4a4a-|r")
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

    local duration = ns.Data.GetDuration(ns.db.sessionType)
    local clock = (duration and not issecretvalue(duration)) and SecondsToClock(duration) or ""
    local scope = ns.db.sessionType == 0 and L["Current fight"] or L["Overall"]
    frame.header.title:SetText(clock ~= "" and (clock .. "  " .. scope) or scope)

    local shown = 0
    for i = 1, ns.db.rows do
        local row = rows[i]
        local entry = data and data[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source
            shown = i

            row:SetMinMaxValues(0, maxAmount or 1)
            row:SetValue(source.totalAmount or 0)
            local r, g, b = ns.ClassColor(source.classFilename)
            row:SetStatusBarColor(r, g, b, 0.75)

            row.name:SetText(source.name)

            for c = 1, #ns.db.columns do
                local suffix = ns.Data.IsRateColumn(ns.db.columns[c]) and "/s" or nil
                ns.SetAmountText(row.cells[c], entry.values[c], suffix)
            end

            row:Show()
        end
    end

    -- A janela acompanha quantos jogadores existem de verdade.
    if shown ~= visibleRows then
        visibleRows = shown
        frame:SetHeight(WindowHeight(shown))
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
