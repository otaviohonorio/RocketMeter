-- RocketMeter | Picker.lua
-- O configurador: duas abas num painel só, colado na janela.
--
--   Colunas    — quais métricas aparecem e em que ordem
--   Aparência  — cor, transparência, textura, fonte, tamanhos
--
-- Tudo aplica ao vivo na janela atrás: sem "aplicar", sem submenu, sem sair da tela.
local ADDON, ns = ...
local L = ns.L

local Picker = {}
ns.Picker = Picker

local WIDTH = 300
local ROW_HEIGHT = 22
local CONTROL_HEIGHT = 30
local TOP = 58          -- título + abas
local BOTTOM = 34       -- rodapé

local frame, tabs, panes

--------------------------------------------------------------------------------
-- Colunas
--------------------------------------------------------------------------------
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

local function BuildColumnRow(pane, index, column)
    local row = pane.rows[index]
    if not row then
        row = CreateFrame("Frame", nil, pane)
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

        row:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -((index - 1) * ROW_HEIGHT))
        pane.rows[index] = row
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
end

--------------------------------------------------------------------------------
-- Aparência: controles que aplicam ao vivo
--------------------------------------------------------------------------------
local controls = {}

---Slider com rótulo e valor à direita.
local function AddSlider(pane, index, label, key, minimum, maximum, step, onChange)
    local slider = pane.controls[index]
    if not slider then
        slider = CreateFrame("Slider", ADDON .. "PickerSlider" .. index, pane, "OptionsSliderTemplate")
        slider:SetWidth(WIDTH - 60)
        slider:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -((index - 1) * CONTROL_HEIGHT) - 12)

        slider.readout = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        slider.readout:SetPoint("LEFT", slider, "RIGHT", 8, 0)

        pane.controls[index] = slider
    end

    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    local low = _G[slider:GetName() .. "Low"]
    local high = _G[slider:GetName() .. "High"]
    local text = _G[slider:GetName() .. "Text"]
    if low then low:SetText("") end
    if high then high:SetText("") end
    if text then text:SetText(label) end

    local current = ns.db[key] or minimum
    slider:SetValue(current)
    slider.readout:SetText(step < 1 and format("%.2f", current) or tostring(math.floor(current)))

    slider:SetScript("OnValueChanged", function(self, value)
        if step >= 1 then value = math.floor(value + 0.5) end
        ns.db[key] = value
        self.readout:SetText(step < 1 and format("%.2f", value) or tostring(value))
        if onChange then onChange() end
    end)

    slider:Show()
    return slider
end

---Caixa de marcação simples.
local function AddCheck(pane, index, label, key, onChange)
    local check = pane.checks[index]
    if not check then
        check = CreateFrame("CheckButton", nil, pane, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check.label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        check.label:SetPoint("LEFT", check, "RIGHT", 4, 0)
        pane.checks[index] = check
    end

    check:SetPoint("TOPLEFT", pane, "TOPLEFT", 6, -pane.nextY)
    pane.nextY = pane.nextY + 24

    check.label:SetText(label)
    check:SetChecked(ns.db[key] ~= false)
    check:SetScript("OnClick", function(self)
        ns.db[key] = self:GetChecked() and true or false
        if onChange then onChange() end
    end)
    check:Show()
    return check
end

---Botão que cicla entre opções de uma lista (mais compacto que dropdown).
local function AddCycler(pane, index, label, key, options, onChange)
    local button = pane.cyclers[index]
    if not button then
        button = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
        button:SetSize(WIDTH - 130, 22)
        button.label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.label:SetPoint("RIGHT", button, "LEFT", -6, 0)
        pane.cyclers[index] = button
    end

    button:SetPoint("TOPLEFT", pane, "TOPLEFT", 118, -pane.nextY)
    pane.nextY = pane.nextY + 26

    button.label:SetText(label)

    local function CurrentIndex()
        for i, option in ipairs(options) do
            if option.value == ns.db[key] then return i end
        end
        return 1
    end

    button:SetText(options[CurrentIndex()].label)
    button:SetScript("OnClick", function(self)
        local nextIndex = CurrentIndex() + 1
        if nextIndex > #options then nextIndex = 1 end
        ns.db[key] = options[nextIndex].value
        self:SetText(options[nextIndex].label)
        if onChange then onChange() end
    end)
    button:Show()
    return button
end

local function BuildAppearance(pane)
    local function redraw() ns.Window.Rebuild() end
    local function repaint() ns.Window.Refresh(true) end

    AddSlider(pane, 1, L["Window opacity"], "windowAlpha", 0.2, 1.0, 0.05, redraw)
    AddSlider(pane, 2, L["Bar opacity"], "barAlpha", 0.2, 1.0, 0.05, repaint)
    AddSlider(pane, 3, L["Bar brightness"], "barBrightness", 0.3, 1.0, 0.05, repaint)
    AddSlider(pane, 4, L["Row height"], "rowHeight", 14, 32, 1, redraw)
    AddSlider(pane, 5, L["Column width"], "columnWidth", 40, 100, 2, function()
        ns.db.width = nil
        ns.Window.Rebuild()
    end)
    AddSlider(pane, 6, L["Font size"], "fontSize", 8, 20, 1, redraw)

    pane.nextY = 6 * CONTROL_HEIGHT + 10

    local textures = {}
    for _, entry in ipairs(ns.BAR_TEXTURES) do
        textures[#textures + 1] = { value = entry.key, label = entry.label }
    end
    AddCycler(pane, 1, L["Bar texture"], "barTexture", textures, redraw)

    AddCycler(pane, 2, L["Font"], "font", {
        { value = "Fonts\\FRIZQT__.TTF", label = "Friz" },
        { value = "Fonts\\ARIALN.TTF", label = "Arial N." },
        { value = "Fonts\\2002.TTF", label = "2002" },
        { value = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
    }, redraw)

    AddCycler(pane, 3, L["Text outline"], "fontOutline", {
        { value = "OUTLINE", label = L["Thin"] },
        { value = "THICKOUTLINE", label = L["Thick"] },
        { value = "none", label = L["None"] },
    }, redraw)

    AddCycler(pane, 4, L["Row icon"], "rowIcon", {
        { value = "spec", label = L["Specialization"] },
        { value = "class", label = L["Class"] },
    }, redraw)

    AddCheck(pane, 1, L["Round icons"], "roundIcons", redraw)
    AddCheck(pane, 2, L["Row border"], "rowBorder", redraw)
    AddCheck(pane, 3, L["Column header"], "showColumnHeader", redraw)
    AddCheck(pane, 5, L["Fit height to the rows"], "autoHeight", redraw)
    AddCheck(pane, 4, L["Highlight the leader of each column"], "highlightBest", repaint)
end

--------------------------------------------------------------------------------
-- Painel
--------------------------------------------------------------------------------
local function ShowPane(name)
    for key, pane in pairs(panes) do
        if key == name then pane:Show() else pane:Hide() end
    end
    for key, tab in pairs(tabs) do
        if key == name then
            tab:SetNormalFontObject("GameFontNormalSmall")
            tab.underline:Show()
        else
            tab:SetNormalFontObject("GameFontDisableSmall")
            tab.underline:Hide()
        end
    end

    local columnCount = #ns.Data.GetColumns()
    local height = name == "columns"
        and (TOP + columnCount * ROW_HEIGHT + BOTTOM)
        or (TOP + 6 * CONTROL_HEIGHT + 4 * 26 + 4 * 24 + BOTTOM + 10)
    frame:SetSize(WIDTH, height)

    if name == "appearance" then
        BuildAppearance(panes.appearance)
    else
        Picker.Refresh()
    end
end

function Picker.Create()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Picker", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WIDTH, 400)
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

    -- Abas
    tabs, panes = {}, {}
    local function AddTab(name, label, offsetX)
        local tab = CreateFrame("Button", nil, frame)
        tab:SetSize(96, 22)
        tab:SetPoint("TOPLEFT", offsetX, -28)
        tab:SetText(label)
        tab:SetNormalFontObject("GameFontDisableSmall")
        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetPoint("BOTTOMLEFT", 4, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -4, 0)
        tab.underline:SetHeight(2)
        tab.underline:SetColorTexture(1, 0.6, 0.2, 1)
        tab.underline:Hide()
        tab:SetScript("OnClick", function() ShowPane(name) end)
        tabs[name] = tab

        local pane = CreateFrame("Frame", nil, frame)
        pane:SetPoint("TOPLEFT", 12, -TOP)
        pane:SetPoint("BOTTOMRIGHT", -12, BOTTOM)
        pane.rows, pane.controls, pane.checks, pane.cyclers, pane.nextY = {}, {}, {}, {}, 0
        pane:Hide()
        panes[name] = pane
    end

    AddTab("columns", L["Columns"], 12)
    AddTab("appearance", L["Appearance"], 112)

    local clear = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clear:SetSize((WIDTH - 28) / 2, 22)
    clear:SetPoint("BOTTOMLEFT", 12, 10)
    clear:SetText(L["Clear the data"])
    clear:SetScript("OnClick", function() ns.Data.RequestReset() end)

    local more = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    more:SetSize((WIDTH - 28) / 2, 22)
    more:SetPoint("BOTTOMRIGHT", -12, 10)
    more:SetText(L["More options"])
    more:SetScript("OnClick", function() ns.OpenOptions() end)

    return frame
end

function Picker.Refresh()
    if not frame or not frame:IsShown() then return end
    if not panes.columns:IsShown() then return end

    local columns = ns.Data.GetColumns()
    for i = 1, #columns do
        BuildColumnRow(panes.columns, i, columns[i])
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
    ShowPane("columns")
end

---Abre direto na aba de aparência (usado pelo botão de layout da janela).
function Picker.ToggleAppearance(anchorTo)
    Picker.Create()
    if frame:IsShown() and panes.appearance:IsShown() then
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
    ShowPane("appearance")
end
