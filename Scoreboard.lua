-- RocketMeter | Scoreboard.lua
-- O resumo de fim de Mítico+ e de encontro de raide.
--
-- Aqui a densidade é outra: a corrida acabou, ninguém está lutando, e a tela pode respirar.
-- Linhas altas com ícone de classe, cabeçalho grande com o resultado da corrida, destaque para
-- quem liderou. Fecha só no X — ESC não fecha.
local ADDON, ns = ...
local L = ns.L

local Scoreboard = {}
ns.Scoreboard = Scoreboard

local ROW_HEIGHT = 26
local ROW_SPACING = 2
local HEADER_HEIGHT = 56          -- título + subtítulo do resultado
local COLHEAD_HEIGHT = 18
local FOOTER_HEIGHT = 32
local COLUMN_WIDTH = 62
local NAME_WIDTH = 150
local RANK_WIDTH = 18
local ICON_SIZE = 20
local SIDE = 12
local MAX_ROWS = 20

local frame, headerRow, rows
local columns, sortBy
local sortDesc = true
local lastContext

--------------------------------------------------------------------------------
local function DefaultColumns()
    return {
        "damage", "dps", "damagepct", "healing", "hps",
        "interrupts", "dispels", "taken", "avoidable", "deaths",
    }
end

local function ColumnOffsets()
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + COLUMN_WIDTH
    end
    return offsets, running
end

local function PanelWidth()
    local _, columnsWidth = ColumnOffsets()
    return SIDE * 2 + NAME_WIDTH + columnsWidth
end

local function PanelHeight(rowCount)
    return HEADER_HEIGHT + COLHEAD_HEIGHT + rowCount * (ROW_HEIGHT + ROW_SPACING) + FOOTER_HEIGHT
end

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
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -HEADER_HEIGHT)
    headerRow:SetHeight(COLHEAD_HEIGHT)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(COLHEAD_HEIGHT)
            button:SetWidth(COLUMN_WIDTH)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            button.text:SetPoint("RIGHT", -4, 0)
            button:SetScript("OnClick", function(self)
                local attributeId = columns[self.columnIndex]
                if sortBy == attributeId then
                    sortDesc = not sortDesc
                else
                    sortBy, sortDesc = attributeId, true
                end
                Scoreboard.Draw()
            end)
            button:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(ns.Data.GetAttributeLabel(columns[self.columnIndex]), 1, 1, 1)
                GameTooltip:AddLine(L["Click to sort by this column."], 0.7, 0.7, 0.7)
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            headerRow.labels[c] = button
        end

        local attributeId = columns[c]
        button.columnIndex = c
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -offsets[c], 0)

        -- Só a cor marca a coluna ordenada; seta aqui repetia a informação.
        local label = ns.Data.GetShortLabel(attributeId)
        if attributeId == sortBy then
            button.text:SetText("|cffffd100" .. label .. "|r")
        else
            button.text:SetText("|cffb8ac8a" .. label .. "|r")
        end
        button:Show()
    end
end

local function BuildRow(index)
    local row = rows[index]
    if not row then
        row = CreateFrame("Button", nil, frame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        row:SetBackdropBorderColor(0, 0, 0, 0.9)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT", 1, -1)
        row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        row.bar:SetStatusBarTexture(ns.BarTexture())
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)
        row.bar:SetFrameLevel(row:GetFrameLevel() + 1)

        -- Texto acima da barra (ver o comentario em Window.lua: frame filho cobre o pai).
        row.text = CreateFrame("Frame", nil, row)
        row.text:SetAllPoints()
        row.text:SetFrameLevel(row.bar:GetFrameLevel() + 2)

        row.highlight = row.text:CreateTexture(nil, "HIGHLIGHT")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(1, 1, 1, 0.08)

        row.rank = row.text:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.rank:SetPoint("LEFT", 6, 0)
        row.rank:SetWidth(RANK_WIDTH)
        row.rank:SetJustifyH("LEFT")

        row.icon = row.text:CreateTexture(nil, "OVERLAY")
        row.icon:SetSize(ICON_SIZE, ICON_SIZE)
        row.icon:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
        if row.icon.SetMask then
            row.icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        end

        row.iconClass = row.text:CreateTexture(nil, "OVERLAY")
        row.iconClass:SetSize(ICON_SIZE, ICON_SIZE)
        row.iconClass:SetPoint("LEFT", row.rank, "RIGHT", 2, 0)
        row.iconClass:Hide()

        row.name = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
        row.name:SetWidth(NAME_WIDTH - RANK_WIDTH - ICON_SIZE - 18)
        row.name:SetJustifyH("LEFT")

        row.cells = {}
        rows[index] = row
    end

    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + COLHEAD_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_SPACING))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, offsetY)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local cell = row.cells[c]
        if not cell then
            cell = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetJustifyH("RIGHT")
            row.cells[c] = cell
        end
        cell:SetWidth(COLUMN_WIDTH - 8)
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row, "RIGHT", -offsets[c] - 4, 0)
        cell:Show()
    end

    return row
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
    frame:SetBackdropColor(0.03, 0.03, 0.045, 0.95)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()

    -- Faixa superior com a arte do medidor nativo, mais alta que a da janela.
    frame.headerArt = frame:CreateTexture(nil, "BACKGROUND")
    frame.headerArt:SetPoint("TOPLEFT", 1, -1)
    frame.headerArt:SetPoint("TOPRIGHT", -1, -1)
    frame.headerArt:SetHeight(HEADER_HEIGHT - 8)
    if frame.headerArt.SetAtlas then
        frame.headerArt:SetAtlas("ui-damagemeters-header-bar", false)
    end
    if not frame.headerArt:GetTexture() then
        frame.headerArt:SetColorTexture(0.10, 0.12, 0.18, 0.95)
    end
    frame.headerArt:SetAlpha(0.85)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", SIDE, -12)
    frame.title:SetTextColor(1, 0.85, 0.4)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.subtitle:SetPoint("TOPLEFT", SIDE, -32)
    frame.subtitle:SetTextColor(0.8, 0.8, 0.83)

    frame.result = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.result:SetPoint("TOPRIGHT", -SIDE - 20, -14)

    -- Fecha só aqui: fora de UISpecialFrames, ESC não fecha.
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    close:SetScript("OnClick", function() frame:Hide() end)

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize(120, 22)
    clear:SetPoint("BOTTOMRIGHT", -SIDE, 8)
    clear:SetText(L["Clear the data"])
    clear:SetScript("OnClick", function() ns.Data.RequestReset() end)

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMLEFT", SIDE, 10)
    frame.footer:SetText(L["Click a column header to sort. Drag to move."])

    rows = {}
    return frame
end

--------------------------------------------------------------------------------
function Scoreboard.Draw()
    if not frame or not lastContext then return end

    local rowCount = lastContext.rowCount
    local data, session = ns.Data.GetRows(lastContext.sessionType, sortBy, columns, rowCount, not sortDesc)
    local maxAmount = session and session.maxAmount

    frame:SetSize(PanelWidth(), PanelHeight(rowCount))
    frame.title:SetText(lastContext.title)
    frame.subtitle:SetText(lastContext.subtitle or "")
    frame.result:SetText(lastContext.result or "")

    BuildColumnHeader()

    for i = 1, rowCount do
        local row = BuildRow(i)
        local entry = data and data[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source

            local top = maxAmount
            if top == nil then top = 1 end
            local value = source.totalAmount
            if value == nil then value = 0 end
            row.bar:SetStatusBarTexture(ns.BarTexture())
            row.bar:SetMinMaxValues(0, top)
            row.bar:SetValue(value)
            row.bar:SetStatusBarColor(ns.BarColor(source.classFilename))

            -- Quem lidera a métrica ordenada ganha um fundo dourado discreto.
            row.bg:SetColorTexture(0, 0, 0, i % 2 == 0 and 0.10 or 0.22)
            row.rank:SetTextColor(0.6, 0.6, 0.62)

            row.rank:SetText(i)
            ns.ApplyRowIcon(row.icon, row.iconClass, source)
            row.name:SetText(source.name)

            for c = 1, #columns do
                ns.SetCellText(row.cells[c], entry.values[c], columns[c])
                ns.ColorCell(row.cells[c], columns[c], entry.best and entry.best[c])
            end
            row:Show()
        end
    end

    for i = rowCount + 1, #rows do
        rows[i]:Hide()
    end
end

function Scoreboard.Show(context)
    if not ns.Data.IsAvailable() then return end

    lastContext = context or lastContext
    if not lastContext then
        ns.Print(L["no run recorded in this session yet."])
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

function Scoreboard.OnChallengeCompleted()
    local a, b, c, d = C_ChallengeMode.GetChallengeCompletionInfo()
    local mapID, level, timeMs, onTime
    if type(a) == "table" then
        mapID, level, timeMs, onTime = a.mapChallengeModeID, a.level, a.time, a.onTime
    else
        mapID, level, timeMs, onTime = a, b, c, d
    end

    local mapName = mapID and C_ChallengeMode.GetMapUIInfo(mapID) or L["Dungeon"]
    local clock = timeMs and SecondsToClock(timeMs / 1000) or "?"

    Scoreboard.Show({
        title = mapName .. (level and ("  +" .. level) or ""),
        subtitle = L["Total time"] .. ": " .. clock,
        result = onTime and ("|cff40d878" .. L["on time"] .. "|r")
            or ("|cffe06060" .. L["over time"] .. "|r"),
        sessionType = 1,   -- geral: a corrida inteira
        rowCount = GroupRowCount(),
    })
end

function Scoreboard.OnEncounterEnd(encounterName, difficultyName)
    local duration = ns.Data.GetDuration(0)
    local clock = (duration and not issecretvalue(duration)) and SecondsToClock(duration) or "?"

    Scoreboard.Show({
        title = encounterName or L["Encounter"],
        subtitle = (difficultyName and (difficultyName .. "  •  ") or "") .. L["Total time"] .. ": " .. clock,
        result = "|cff40d878" .. L["defeated"] .. "|r",
        sessionType = 0,
        rowCount = GroupRowCount(),
    })
end
