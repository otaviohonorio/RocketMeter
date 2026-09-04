-- RocketMeter | Scoreboard.lua
-- O painel de fim de Mítico+ e de encontro de raide: a foto completa da corrida,
-- com todas as métricas de uma vez, sem precisar configurar coluna nenhuma.
local ADDON, ns = ...

local Scoreboard = {}
ns.Scoreboard = Scoreboard

local ROW_HEIGHT = 24
local ROW_SPACING = 1
local HEADER_HEIGHT = 20
local COLUMN_WIDTH = 54
local DUAL_COLUMN_WIDTH = 68
local NAME_WIDTH = 120
local TOP_INSET = 46          -- título + subtítulo
local SIDE_INSET = 10
local MAX_ROWS = 20

local frame, headerRow, rows
local columns, sortBy
local lastContext

--------------------------------------------------------------------------------
-- Colunas fixas: aqui o objetivo é ver tudo, não configurar.
--------------------------------------------------------------------------------
local function DefaultColumns()
    local E = Enum.DamageMeterType
    return {
        E.DamageDone,
        E.HealingDone,
        E.Interrupts,
        E.Dispels,
        E.DamageTaken,
        E.AvoidableDamageTaken,
        E.Deaths,
    }
end

local function ColumnWidth(attributeId)
    return ns.Data.IsDualColumn(attributeId) and DUAL_COLUMN_WIDTH or COLUMN_WIDTH
end

local function ColumnOffsets()
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + ColumnWidth(columns[c])
    end
    return offsets, running
end

local function PanelWidth()
    local _, columnsWidth = ColumnOffsets()
    return SIDE_INSET * 2 + NAME_WIDTH + columnsWidth
end

local function PanelHeight(rowCount)
    return TOP_INSET + HEADER_HEIGHT + rowCount * (ROW_HEIGHT + ROW_SPACING) + SIDE_INSET + 6
end

--------------------------------------------------------------------------------
-- Construção
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

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(HEADER_HEIGHT)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("RIGHT", -4, 0)
            button:SetScript("OnClick", function(self)
                sortBy = columns[self.columnIndex]
                Scoreboard.Draw()
            end)
            headerRow.labels[c] = button
        end

        local attributeId = columns[c]
        button.columnIndex = c
        button:SetWidth(ColumnWidth(attributeId))
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -offsets[c], 0)

        local label = ns.Data.GetShortLabel(attributeId)
        button.text:SetText((attributeId == sortBy and "|cffff6a00" or "|cffb0b0b0") .. label .. "|r")
        button:Show()
    end
end

local function BuildRow(index)
    local row = rows[index]
    if not row then
        row = CreateFrame("StatusBar", nil, frame)
        row:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        row:SetMinMaxValues(0, 1)
        row:SetHeight(ROW_HEIGHT)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 1, 1, 0.05)

        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.rank:SetPoint("LEFT", 4, 0)
        row.rank:SetWidth(18)
        row.rank:SetJustifyH("LEFT")

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", 24, 0)
        row.name:SetWidth(NAME_WIDTH - 26)
        row.name:SetJustifyH("LEFT")

        row.cells = {}
        rows[index] = row
    end

    row:ClearAllPoints()
    local offsetY = -(TOP_INSET + HEADER_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_SPACING))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE_INSET, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE_INSET, offsetY)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local attributeId = columns[c]
        local cell = row.cells[c]
        if not cell then
            cell = {
                main = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
                sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"),
            }
            cell.main:SetJustifyH("RIGHT")
            cell.sub:SetJustifyH("RIGHT")
            row.cells[c] = cell
        end

        local width = ColumnWidth(attributeId) - 6
        cell.main:SetWidth(width)
        cell.sub:SetWidth(width)
        cell.main:ClearAllPoints()
        cell.sub:ClearAllPoints()

        if ns.Data.IsDualColumn(attributeId) then
            cell.main:SetPoint("TOPRIGHT", row, "TOPRIGHT", -offsets[c] - 4, -2)
            cell.sub:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -offsets[c] - 4, 2)
            cell.sub:Show()
        else
            cell.main:SetPoint("RIGHT", row, "RIGHT", -offsets[c] - 4, 0)
            cell.sub:Hide()
        end
        cell.main:Show()
    end

    return row
end

local function CreatePanel()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Scoreboard", UIParent, "DefaultPanelTemplate")
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function() frame:Hide() end)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.subtitle:SetPoint("TOPLEFT", SIDE_INSET + 2, -26)
    frame.subtitle:SetTextColor(0.75, 0.75, 0.78)

    rows = {}
    tinsert(UISpecialFrames, frame:GetName())
    return frame
end

--------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------
function Scoreboard.Draw()
    if not frame or not lastContext then return end

    local rowCount = lastContext.rowCount
    local data, session = ns.Data.GetRows(lastContext.sessionType, sortBy, columns, rowCount)
    local maxAmount = session and session.maxAmount

    frame:SetSize(PanelWidth(), PanelHeight(rowCount))
    if frame.SetTitle then
        frame:SetTitle(lastContext.title)
    end
    frame.subtitle:SetText(lastContext.subtitle or "")

    BuildHeader()

    for i = 1, rowCount do
        local row = BuildRow(i)
        local entry = data and data[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source
            row:SetMinMaxValues(0, maxAmount or 1)
            row:SetValue(source.totalAmount or 0)
            row:SetStatusBarColor(ns.ClassColor(source.classFilename))
            row.rank:SetText(i .. ".")
            row.name:SetText(source.name)

            for c = 1, #columns do
                local cell = row.cells[c]
                local value = entry.values[c]
                ns.SetAmountText(cell.main, value and value.total)
                if ns.Data.IsDualColumn(columns[c]) then
                    ns.SetAmountText(cell.sub, value and value.perSecond, "/s")
                end
            end
            row:Show()
        end
    end

    for i = rowCount + 1, #rows do
        rows[i]:Hide()
    end
end

---Abre o painel para um contexto (fim de M+, fim de encontro, ou reabertura manual).
function Scoreboard.Show(context)
    if not ns.Data.IsAvailable() then return end

    lastContext = context or lastContext
    if not lastContext then
        ns.Print("nenhuma corrida registrada nesta sessão ainda.")
        return
    end

    CreatePanel()
    columns = columns or DefaultColumns()
    sortBy = sortBy or columns[1]

    Scoreboard.Draw()
    frame:Show()
end

function Scoreboard.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Scoreboard.Show()
    end
end

--------------------------------------------------------------------------------
-- Gatilhos
--------------------------------------------------------------------------------
local function GroupRowCount()
    local size = GetNumGroupMembers()
    if not size or size < 1 then size = 1 end
    return math.min(size, MAX_ROWS)
end

---Fim de Mítico+. A API devolve os dados em tabela em versões recentes e em valores
---soltos em versões antigas — tratamos os dois casos.
function Scoreboard.OnChallengeCompleted()
    local a, b, c, d = C_ChallengeMode.GetChallengeCompletionInfo()
    local mapID, level, timeMs, onTime
    if type(a) == "table" then
        mapID, level, timeMs, onTime = a.mapChallengeModeID, a.level, a.time, a.onTime
    else
        mapID, level, timeMs, onTime = a, b, c, d
    end

    local mapName = mapID and C_ChallengeMode.GetMapUIInfo(mapID) or "Masmorra"
    local clock = timeMs and SecondsToClock(timeMs / 1000) or "?"
    local result = onTime and "|cff33ff99no tempo|r" or "|cffff5555fora do tempo|r"

    -- sessionType 1 = geral: a corrida inteira, não só o último pacote.
    Scoreboard.Show({
        title = "Rocket Meter — " .. mapName .. (level and (" +" .. level) or ""),
        subtitle = clock .. "  •  " .. result,
        sessionType = 1,
        rowCount = GroupRowCount(),
    })
end

---Fim de encontro de raide (só quando vence).
function Scoreboard.OnEncounterEnd(encounterName, difficultyName)
    Scoreboard.Show({
        title = "Rocket Meter — " .. (encounterName or "Encontro"),
        subtitle = difficultyName or "",
        sessionType = 0,   -- o combate que acabou de terminar
        rowCount = GroupRowCount(),
    })
end
