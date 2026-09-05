-- RocketMeter | Picker.lua
-- O painel de colunas: a tela que a configuração do addon precisava ser.
-- Abre colado na janela, mostra as onze métricas de uma vez, e cada mudança aparece
-- na hora atrás dele — sem menu aninhado, sem "aplicar", sem procurar.
local ADDON, ns = ...
local L = ns.L

local Picker = {}
ns.Picker = Picker

local ROW_HEIGHT = 22
local WIDTH = 250
local TOP = 58        -- título + linha de conjuntos
local BOTTOM = 34     -- rodapé

local frame, rows, presetButtons

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
local function BuildRow(index, attr)
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, frame)
        row:SetSize(WIDTH - 20, ROW_HEIGHT)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(22, 22)
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetScript("OnClick", function(self)
            ns.Window.ToggleColumn(self.attributeId)
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
            local at = IndexOf(self.attributeId)
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
            local at = IndexOf(self.attributeId)
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

    row.check.attributeId = attr.key
    row.up.attributeId = attr.key
    row.down.attributeId = attr.key

    local enabled = IsEnabled(attr.key)
    row.check:SetChecked(enabled)
    row.label:SetText(attr.label)

    if enabled then
        local position = IndexOf(attr.key)
        row.label:SetTextColor(1, 1, 1)
        row.order:SetText(position .. "º")
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
    return row
end

--------------------------------------------------------------------------------
function Picker.Create()
    if frame then return frame end

    local attributes = ns.Data.GetColumns()

    frame = CreateFrame("Frame", ADDON .. "Picker", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WIDTH, TOP + #attributes * ROW_HEIGHT + BOTTOM)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    if frame.SetTitle then
        frame:SetTitle(L["Columns"])
    end

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 1)
    close:SetScript("OnClick", function() frame:Hide() end)

    -- Conjuntos prontos, como botões de verdade e não item de menu escondido.
    presetButtons = {}
    local presets = ns.Data.GetPresets()
    local order = { "mplus", "raid", "damage" }
    local x = 12
    for _, key in ipairs(order) do
        local preset = presets[key]
        if preset then
            local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
            b:SetSize(74, 20)
            b:SetPoint("TOPLEFT", x, -30)
            b:SetText(preset.label)
            b:SetScript("OnClick", function()
                ns.Window.ApplyPreset(key)
                Picker.Refresh()
            end)
            presetButtons[key] = b
            x = x + 76
        end
    end

    local more = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    more:SetSize(WIDTH - 24, 22)
    more:SetPoint("BOTTOMLEFT", 12, 10)
    more:SetText(L["More options"])
    more:SetScript("OnClick", function() ns.OpenOptions() end)

    rows = {}
    tinsert(UISpecialFrames, frame:GetName())
    return frame
end

function Picker.Refresh()
    if not frame or not frame:IsShown() then return end
    local attributes = ns.Data.GetColumns()
    for i = 1, #attributes do
        BuildRow(i, attributes[i])
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
