-- RocketMeter | Picker.lua
-- The addon's only settings screen: one wide window, in sections, spread over three
-- columns -- the meter's columns, the window and the scoreboard, and the three texts.
--
-- WHY NOT TABS. They were tried (0.58.0) and the problem was not hierarchy, it was space: the
-- options are few, and hiding half of them behind a tab left two of the three screens with a
-- huge gap. With columns everything shows at once and the window stays full.
--
-- THE POSITION RULE IS ONE ONLY, and it exists because breaking it was the reported defect: the
-- checkbox was born at 40% of the WINDOW's width -- in the middle -- and its label went out through the
-- right edge. Now every control lives inside a COLUMN, and it is the column that says where it starts and
-- where it ends; nothing is placed relative to the whole window. `Picker.__probe()` returns
-- each control's rectangle for the harness to check that none leaks.
--
-- THE COMPONENTS ARE BLIZZARD'S, with the names checked in the 12.1.0 source -- seeing a name
-- in use does not prove it exists, and that fallacy already cost a round here:
--
--   `MinimalSliderWithSteppersTemplate`  Blizzard_SharedXML/Shared/Slider/MinimalSlider.xml
--   `WowStyle1DropdownTemplate`          Blizzard_Menu/Mainline/MenuTemplates.xml
--   `MenuUtil.CreateRadioMenu`           Blizzard_Menu/MenuUtil.lua:381
--
-- (`Mainline`, not `Classic`: the template exists in both folders and it is `Mainline`'s that
-- retail loads. The wrong quote had been here since 0.58.0.)
--
-- WHAT IS CONFIGURED AND WHAT IS NOT. The rule of 0.20.0 -- the look is not configured, the default is what
-- has to be right -- still holds for colour, texture, border and opacity. Typography is the
-- deliberate exception: the size was adjusted on request six times, because the right value depends on
-- resolution, interface scale and how well the player sees. The LIMITS are what is not
-- negotiated, and the reason for each one is in `Window.lua`.
local ADDON, ns = ...
local L = ns.L

local Picker = {}
ns.Picker = Picker

--------------------------------------------------------------------------------
-- Grade
--------------------------------------------------------------------------------
local MARGIN = 18               -- from the window's edge to the content
local GUTTER = 20               -- entre as colunas
local COL_W = 262               -- the usable width of each column
local COLUMNS = 3
local WIDTH = MARGIN * 2 + COL_W * COLUMNS + GUTTER * (COLUMNS - 1)

local TOP = 36                  -- below the title bar
-- Only the bottom margin: the "Clear data" button left here by request -- the data is cleared in
-- the meter's own window, and a full-width button at the foot of a settings screen
-- gave it a weight it does not have.
-- 14 of margin under the columns, plus the support line (Donate.lua, `DONATE_ROW`, 27/09).
local FOOTER = 14 + (ns.DONATE_ROW or 0)

-- THE VERTICAL RHYTHM. Every number here was read in the 12.1.0 source, and none was rounded.
--
-- THERE IS NO GRID OF 4 ON THIS SCREEN, and that is a decision, not carelessness. The attempt before imposed a
-- unit of 4 and had to bend the values to fit it -- but **no** Blizzard number
-- is a multiple of 4: 9, 25, 45, 5, 15, 37, 26. Rounding 9 to 8 buys no alignment
-- and loses the exact match with the native one, which is precisely the goal.
--
-- THE ROW HEIGHT IS ONE, and the widget fits into it. Blizzard's NINE option templates
-- (`Blizzard_SettingControls.xml:108-164` -- checkbox, slider, combo, button, colour and the
-- combinations) are all **280×26**, and it is the panel that imposes the width on the control
-- (`Blizzard_SettingControls.lua:656,741`), never the other way round.
local H_CONTROL = 26
local H_LABEL = 12              -- caixa de `GameFontHighlightSmall` (fonte 10, `Fonts.xml:41`)

-- THE REPORTED DEFECT WAS A RATIO, NOT A NUMBER. The space INSIDE a field (label -> its
-- control) was 4 and the space BETWEEN fields was 6 -- 1.5×. At 1.5× the eye cannot decide whether the label
-- belongs to the control below it or continues the line above, and the result is literally
-- "tudo muito junto e grudado, é feio, confuso". Gestalt's law of proximity, and it has a number.
--
-- THE NUMBER COMES FROM BLIZZARD'S ONLY STACKED FORM, the one for creating a community
-- (`Blizzard_Communities/CommunitiesSettings.xml`): the field is born at `y="-2"` from its label
-- (`:79`), and the next label at `y="-34"` from the previous label (`:25`) over a 22 field
-- (`:77`) -- that is, **2 inside and 10 outside, a ratio of 5×**.
--
-- (A round before "fixed" this to 4 and 12 = 3×, to fit the grid of 4. It was the reverse:
-- it moved away from the measured value for the sake of a grid Blizzard does not use.)
local GAP_LABEL = 2
local GAP_FIELD = 10

-- A field's ink and its slot: the slot is the ink PLUS the breathing room after it. The two
-- names exist because the harness measures the gap between inks, and slot minus slot would always give zero.
local INK_FIELD = H_LABEL + GAP_LABEL + H_CONTROL              -- 40
local INK_SECTION = H_LABEL + 4                                -- title and rule

local H_FIELD = INK_FIELD + GAP_FIELD                          -- 50
local H_CHECK = H_CONTROL + GAP_FIELD                          -- 36: the label lives on the line
local H_BUTTON = H_CONTROL + GAP_FIELD                         -- 36
local H_COLUMN_ROW = H_CONTROL                                 -- lista densa, sem folga extra

-- BETWEEN GROUPS, the white space Blizzard opens above a section title: **25** = the 9 of
-- row breathing room (`Blizzard_SettingsList.lua:46`) plus the 16 of the title's indent inside the
-- 45 header block (`Blizzard_SettingControls.xml:14,19`). It is 2.5× the space between
-- fields -- above the floor of 2× below which a group's border stops being perceived.
--
-- And the corollary that matters more than the ratio: **a group is not separated by air alone**. Blizzard spends
-- a block with a title; that is why `BuildSection` draws a title and a rule, and not a bigger gap.
local GAP_SECTION = 25
local H_SECTION = H_LABEL + 4 + GAP_FIELD                      -- title, rule and breathing room

-- 28, and not a number chosen by me: it is the size Blizzard itself gives
-- `UICheckButtonTemplate` when it wraps it in `ResizeCheckButtonTemplate`
-- (`SharedUIPanelTemplates.xml:1322`). The template is born 32×32; 28 is the measure it uses in
-- forms.
local CHECK_SIZE = 28

-- THE LIST OF COLUMNS is a dense list, not a form: a smaller box and no slack between lines, like the
-- panel's categories column (`Blizzard_CategoryList.xml:51`, a 20 line).
local ROW_CHECK = 22
local ARROW = 18                -- seta de reordenar
local ARROW_GAP = 6             -- 18 + 6 = 24 centro a centro (WCAG 2.2 SC 2.5.8)
local ORDER_W = 14              -- the position's number, to the left of the arrows

-- `UICheckButtonTemplate`'s `Text` is anchored `LEFT` on the box's `RIGHT` with **x = −2**
-- (`CheckButtonTemplates.xml:56`) -- it starts 2px BEFORE the end of the box. That −2 is calibrated
-- for the original template's **32×32** art, which has a transparent margin; shrinking the box
-- to 28 the margin goes too and the text really touches it.
--
-- Blizzard itself solves it where it makes the same swap: in `ResizeCheckButtonTemplate` it uses
-- 28×28 and **re-anchors** the label at `+2` (`SharedUIPanelTemplates.xml:1322,1337`). The two numbers
-- go in a pair, and the version before here copied only the 28 -- it fixed the width and left the anchor
-- wrong, which is what decides where the text starts.
local CHECK_TEXT_OFFSET = 2

local frame, rows

-- EACH CONTROL'S WHOLE RECTANGLE, for the harness. Keeping only `x` and `width` was the hole that
-- let three rejections through: all three were a VERTICAL collision (overlapping tabs, a field
-- riding on the next), and without `y`/`height` there was nothing to check. The column goes too, so
-- that the neighbourhood check compares who really are neighbours.
--
-- THE HEIGHT RECORDED IS THE INK'S, not the slot's. Recording the slot (which already includes the breathing room)
-- would make the gap between neighbours always zero, and the test would pass by construction measuring nothing --
-- which is the same defect, again, one level up.
local probes = {}

local function Probe(name, widget, x, width, y, height, column, isSection)
    probes[#probes + 1] = {
        name = name, widget = widget,
        x = x, width = width,
        y = y, height = height, column = column,
        isSection = isSection or false,
    }
end

---Este grupo desenhado contem esta coluna?
local function GroupHasKey(grupo, key)
    for _, id in ipairs(grupo.keys) do
        if id == key then return true end
    end
    return false
end

--- Is the item on? ONE of its columns being in the list is enough.
---
--- "One is enough" on purpose: a list saved before this version may have only the total. The box
--- shows on, and turning it off takes both -- which is what "one item" means. The list
--- completes itself at the next normalisation.
local function IsEnabled(item)
    for _, id in ipairs(ns.db.columns) do
        for _, key in ipairs(item.keys) do
            if id == key then return true end
        end
    end
    return false
end

--- The item's position among the DRAWN GROUPS -- which is the index `Window.MoveColumn` expects.
---
--- ⚑ THIS WAS THE DEFECT. The screen returned the position in `ns.db.columns` and `MoveColumn` indexed the
--- list of groups: with {damage, DPS, healing, HPS, interr} (5 columns, 3 groups), the arrow of the
--- "DPS" row moved the HEALING group and the "HPS" one did nothing, overflowing the list. Nothing wrong
--- showed on screen -- the arrow simply moved the wrong column.
local function IndexOf(item)
    local grupos = ns.Data.GroupColumns(ns.db.columns)
    for i, grupo in ipairs(grupos) do
        -- IT MATCHES BY THE ITEM'S KEYS, not by its `attr`.
        --
        -- Today both give the same result, and it is worth saying why instead of letting it look like
        -- a defect fix: the drawn groups are PER FAMILY, so the "Damage share" falls
        -- in the same group as the "Damage total / DPS" pair anyway. What changes is the
        -- dependency -- matching by key asks "does this group contain any column OF THIS item?",
        -- which stays right if a group one day stops being a whole family. Matching by
        -- `attr` only works while group and family are synonyms.
        for _, key in ipairs(item.keys) do
            if GroupHasKey(grupo, key) then return i, #grupos end
        end
    end
    return nil, #grupos
end

--- The outline options, built from `ns.OUTLINE_CHOICES`.
---
--- The list was written by hand here, and so it did not follow when `Window.lua` gained a level:
--- two sources of truth for the same list drift apart at the first change. Now the order and the
--- set come from there; here only the label stays, the only part that needs translating.
---
--- The labels stay INSIDE the function and with the key written out in full, and that is a requirement, not
--- style: `tests/locales.lua` looks for exactly that form to know which keys are in use.
--- Building the key from a variable (`L[MAPA[v]]`) takes the four off the radar and the test declares them dead.
local function OutlineEntries()
    local label = {
        none   = L["None"],
        thin   = L["Thin"],
        thick  = L["Thick"],
    }

    local entries = {}
    for _, choice in ipairs(ns.OUTLINE_CHOICES) do
        entries[#entries + 1] = { label = label[choice.value] or choice.value, value = choice.value }
    end
    return entries
end

--------------------------------------------------------------------------------
-- Componentes
--------------------------------------------------------------------------------
--- A section title, in gold, with the thin rule the scoreboard already uses.
local function BuildSection(col, y, title)
    Probe("secao: " .. title, nil, 0, COL_W, y, INK_SECTION, col.index, true)
    local text = col:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    text:SetText(title)
    text:SetTextColor(1, 0.82, 0)

    local rule = col:CreateTexture(nil, "ARTWORK")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y - H_LABEL - 4)
    rule:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, -y - H_LABEL - 4)
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    return y + H_SECTION
end

--- The label ABOVE the control, not beside it.
---
--- In a narrow column, a label on the left would leave ~100px for the text and the rest for the
--- control, and "Abrir ao fim de uma corrida de Mítico+" does not fit in 100. Above, the label has the
--- whole column and the control too.
local function BuildLabelText(col, y)
    local text = col:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    text:SetWidth(COL_W)
    text:SetJustifyH("LEFT")
    return text
end

local function BuildLabel(col, y, label)
    BuildLabelText(col, y):SetText(label)
    return y + H_LABEL + GAP_LABEL
end

--- A slider with the value **in the label**, not beside the control.
---
--- The template draws the value in a `RightText` anchored to `Slider.RIGHT` with **x=25**
--- (`MinimalSlider.xml:73-77`), and the `Slider` already sits 19px inside the frame -- that is, the
--- text starts **6px OUTSIDE** the width we give, and still grows by its own width. That is
--- why "13px" and "5" showed outside the window.
---
--- The template's labels are born `hidden="true"` and only show if a formatter is passed to
--- `Init`. So we pass none: the value goes into the label above, which already exists and is already
--- inside the column. Zero leaking **by construction**, and the number sits beside its name.
local function BuildSlider(col, y, label, low, high, suffix, get, set)
    local text = BuildLabelText(col, y)
    local at = y + H_LABEL + GAP_LABEL

    local slider = CreateFrame("Slider", nil, col, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -at)
    slider:SetWidth(COL_W)
    slider:SetHeight(H_CONTROL)
    Probe(label, slider, 0, COL_W, y, INK_FIELD, col.index)

    local function write()
        text:SetText(format("%s   |cffffd100%s|r", label, (suffix or "%d"):format(get())))
    end

    -- `Init(value, min, max, steps, formatters)`. The steps are the number of INTERVALS, and so
    -- it is `high - low`: with one more the slider stops at fractional positions and the number
    -- blinks between two integers.
    if slider.Init then
        -- No formatters table: the template's labels stay hidden and nothing leaves the
        -- column. The value is written by `write()`, in the label above.
        slider:Init(get(), low, high, high - low)
        slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged,
            function(_, value)
                set(value)
                write()
            end)
    end

    write()
    slider.Refresh = function()
        if slider.SetValue then slider:SetValue(get()) end
        write()
    end
    return y + H_FIELD, slider
end

--- A single-choice combo.
---
--- `MenuUtil.CreateRadioMenu(dropdown, isSelected, setSelected, ...)` takes the items as pairs
--- `{ label, value }`. The selection mark comes from `isSelected`, so there is no duplicated state
--- here -- it is always the answer of whoever keeps the setting. If the saved value matches
--- no item, the button draws **blank**; it happened in 0.58.0, and the fix is migrating the
--- key, not patching here.
local function BuildDropdown(col, y, label, entries, get, set)
    local at = BuildLabel(col, y, label)

    local dropdown = CreateFrame("DropdownButton", nil, col, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -at)
    dropdown:SetWidth(COL_W)
    dropdown:SetHeight(H_CONTROL)
    Probe(label, dropdown, 0, COL_W, y, INK_FIELD, col.index)

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

--- An option box: the box at the COLUMN'S MARGIN and the label to its right.
---
--- Here was the reported defect. The box was born at 40% of the window's width and the label went out through the
--- edge. Now the box starts at 0 of the column, and the label gets an EXPLICIT width: what is left
--- of the column after the box. Without that width, the FontString grows as far as the text asks and
--- crosses the edge instead of wrapping.
local function BuildCheck(col, y, label, tip, get, set)
    local check = CreateFrame("CheckButton", nil, col, "UICheckButtonTemplate")
    check:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
    check:SetSize(CHECK_SIZE, CHECK_SIZE)

    -- It tests the TYPE, not only truth: a stub that returns a function here passes the `if` and only
    -- blows up at `SetText`. It already happened in this project, with `frame.Inset`.
    if type(check.Text) == "table" and check.Text.SetText then
        check.Text:SetText(label)
        check.Text:SetFontObject("GameFontHighlightSmall")
        -- RE-ANCHOR, and not only measure. `SetWidth` fixes the arithmetic; what decides where the text
        -- starts is the anchor, and the one inherited from the template is −2 (see `CHECK_TEXT_OFFSET`).
        check.Text:ClearAllPoints()
        check.Text:SetPoint("LEFT", check, "RIGHT", CHECK_TEXT_OFFSET, 0)
        check.Text:SetWidth(COL_W - CHECK_SIZE - CHECK_TEXT_OFFSET)
        check.Text:SetJustifyH("LEFT")
    end
    Probe(label, check, 0, COL_W, y, H_CONTROL, col.index)

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
    b:SetSize(COL_W, H_CONTROL)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(label, 1, 1, 1)
        GameTooltip:AddLine(tip, 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    Probe(label, b, 0, COL_W, y, H_CONTROL, col.index)
    return y + H_BUTTON, b
end

--------------------------------------------------------------------------------
-- Linha da lista de colunas
--------------------------------------------------------------------------------
local function BuildRow(index, item, col, y)
    local row = rows[index]
    if not row then
        row = CreateFrame("Frame", nil, col)
        row:SetSize(COL_W, H_COLUMN_ROW)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetSize(ROW_CHECK, ROW_CHECK)
        row.check:SetPoint("LEFT", 0, 0)
        row.check:SetScript("OnClick", function(self)
            ns.Window.ToggleColumn(self.columnKey)
            Picker.Refresh()
        end)

        -- THE ARROWS ARE CLICK TARGETS, and a small target has a norm: WCAG 2.2 SC 2.5.8 (AA) asks for
        -- 24×24, **or** 24 of distance CENTRE TO CENTRE to the neighbouring target -- the exception is measured
        -- between centres, not between edges. With 18×18 and a gap of 2 it gives 20, and fails; with a gap of 6 it gives
        -- 18 + 6 = 24 and passes, without needing to swell the button in an already dense list.
        row.down = CreateFrame("Button", nil, row)
        row.down:SetSize(ARROW, ARROW)
        row.down:SetPoint("RIGHT", -2, 0)
        row.down:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        row.down:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        row.down:SetScript("OnClick", function(self)
            local at = IndexOf(self.item)
            if at then
                ns.Window.MoveColumn(at, 1)
                Picker.Refresh()
            end
        end)

        row.up = CreateFrame("Button", nil, row)
        row.up:SetSize(ARROW, ARROW)
        row.up:SetPoint("RIGHT", row.down, "LEFT", -ARROW_GAP, 0)
        row.up:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
        row.up:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        row.up:SetScript("OnClick", function(self)
            local at = IndexOf(self.item)
            if at then
                ns.Window.MoveColumn(at, -1)
                Picker.Refresh()
            end
        end)

        row.order = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.order:SetTextColor(LIGHTGRAY_FONT_COLOR:GetRGB())   -- (14/10) light grey, not the disabled one
        row.order:SetPoint("RIGHT", row.up, "LEFT", -ARROW_GAP, 0)

        -- An EXPLICIT width for the label, for the same reason as the checkbox: without it a long name
        -- pushes the arrows out of the column.
        row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", row.check, "RIGHT", 4, 0)
        row.label:SetWidth(COL_W - ROW_CHECK - 4 - (2 + ARROW + ARROW_GAP + ARROW + ARROW_GAP + ORDER_W))
        row.label:SetJustifyH("LEFT")

        row:SetPoint("TOPLEFT", col, "TOPLEFT", 0, -y)
        rows[index] = row
    end

    -- THE ROW SPEAKS OF AN ITEM. `columnKey` is still a key -- `ToggleColumn` turns on the
    -- whole item from any of them -- and `item` is what the arrows use to find the
    -- matching group in the window.
    row.check.columnKey = item.key
    row.up.item, row.down.item = item, item

    local enabled = IsEnabled(item)
    row.check:SetChecked(enabled)
    row.label:SetText(item.label)

    if enabled then
        local position, quantos = IndexOf(item)
        row.label:SetTextColor(1, 1, 1)
        -- "1." and not "1º": the masculine ordinal only exists in some Latin languages, and in
        -- English, German or Korean it becomes garbage. The dot is what the native meter itself uses
        -- to number a row (`DAMAGE_METER_SOURCE_NAME = "%d. %s"`).
        row.order:SetText(position .. ".")
        row.order:Show()
        row.up:Show()
        row.down:Show()
        row.up:SetEnabled(position > 1)
        row.down:SetEnabled(position < quantos)
    else
        row.label:SetTextColor(LIGHTGRAY_FONT_COLOR:GetRGB())
        row.order:Hide()
        row.up:Hide()
        row.down:Hide()
    end

    row:Show()
end

--------------------------------------------------------------------------------
function Picker.Create()
    if frame then return frame end

    local columns = ns.Data.GetColumnItems()
    rows, probes = {}, {}

    -- HEIGHT: the sum of each column, and the window takes the biggest. Counting here, with the SAME
    -- constants that place the controls, is what keeps the window from having space left over or
    -- missing when a line is added.
    local h1 = H_SECTION + #columns * H_COLUMN_ROW
    -- Aparencia: fonte, linhas, os dois deslizadores de distancia, (19/10) o formato do icone,
    -- o reino e (14/10) o botao do minimapa.
    local h2 = H_SECTION + H_FIELD * 5 + H_CHECK * 2                   -- Aparencia
        + GAP_SECTION + H_SECTION + H_CHECK                            -- Sessao
        + GAP_SECTION + H_SECTION + H_CHECK * 2 + 4 + H_BUTTON * 2     -- Placar
        + GAP_SECTION + H_SECTION + H_CHECK                            -- (20/10) Registro de combate
    -- Tres secoes de texto identicas: titulo + deslizador + combo + caixa.
    local h3 = (H_SECTION + H_FIELD * 2 + H_CHECK) * 3 + GAP_SECTION * 2
    local content = math.max(h1, math.max(h2, h3))

    frame = CreateFrame("Frame", ADDON .. "Picker", UIParent, "DefaultPanelTemplate")
    frame:SetSize(WIDTH, TOP + content + FOOTER)
    ns.DarkBody(frame, 1, frame.Bg)       -- (25/10) the dark body, as every Rocket window (Core.lua: "escuro em tudo")
    frame:SetFrameStrata("DIALOG")
    -- IN FRONT WHEN OPENED OR CLICKED (27/09). Every Rocket window shares the HIGH strata, and
    -- inside a strata the order is the frame LEVEL: without this, the rows of a window opened
    -- earlier (deeper children, higher levels) drew over the background of the one opened on
    -- top -- the user's print had RocketMount's list showing through RocketSwap. `toplevel`
    -- raises on click; `Raise` on show.
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self) self:Raise() end)
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

    -- "Support the project" (27/09): a line of its own at the very bottom (Donate.lua).
    frame.donate = ns.DonateFooter(frame)

    --- A column is a Frame of fixed width. Every control is placed relative to IT, and
    --- never to the window -- placing relative to the window is what made the label go out through the edge.
    local function Column(index)
        local col = CreateFrame("Frame", nil, frame)
        col:SetWidth(COL_W)
        col:SetPoint("TOPLEFT", frame, "TOPLEFT",
            MARGIN + (index - 1) * (COL_W + GUTTER), -TOP)
        col:SetPoint("BOTTOM", frame, "BOTTOM", 0, FOOTER)
        col.index = index       -- the harness uses it to compare only who really are neighbours
        return col
    end

    local colColumns, colWindow, colText = Column(1), Column(2), Column(3)
    frame.leftColumn = colColumns

    -- Column 1: which columns the window shows, and in what order.
    frame.columnsTop = BuildSection(colColumns, 0, L["Columns"])

    ----------------------------------------------------------------------------
    -- Coluna 2: a janela e o placar
    ----------------------------------------------------------------------------
    local y = BuildSection(colWindow, 0, L["Appearance"])

    -- The FAMILY is one only for the whole addon, on purpose. A different font per element does not
    -- give hierarchy, it gives a patchwork -- what separates title from row here is size,
    -- outline and shadow, which are the three the user asked for.
    local fontEntries = {}
    for _, choice in ipairs(ns.FONT_CHOICES) do
        fontEntries[#fontEntries + 1] = { label = choice.label, value = choice.path }
    end
    y, frame.fontDrop = BuildDropdown(colWindow, y, L["Font"], fontEntries,
        function() return ns.FontPath() end,
        function(v) ns.Window.SetFont(v) end)

    y, frame.rowsSlider = BuildSlider(colWindow, y, L["Rows"],
        ns.Skin.rowsMin, ns.Skin.rowsMax, "%d",
        function() return ns.Window.GetRows() or 5 end,
        function(v) ns.Window.SetRows(v) end)

    -- THE ROW'S TWO DISTANCES, in the window's look section because that is what it is about:
    -- density. A request of 09/09/2026, with a print and rectangles pointing at both.
    --
    -- THE CAPTION "N px between the two values" WENT AWAY by request (10/09/2026). It existed to tie
    -- an abstract control (the column's width) to the number the player sees in the window -- but the
    -- effect is already in sight: the window redraws at every drag, with the two values coming closer
    -- on screen behind the settings. A caption that describes what is already seen is weight, not help.
    y, frame.gapSlider = BuildSlider(colWindow, y, L["Space between columns"],
        ns.Skin.groupGapMin, ns.Skin.groupGapMax, "%dpx",
        function() return ns.Window.GetGroupGap() end,
        function(v) ns.Window.SetGroupGap(v) end)

    y, frame.pairSlider = BuildSlider(colWindow, y, L["Width of the total column"],
        ns.Skin.totalWidthMin, ns.Skin.totalWidthMax, "%dpx",
        function() return ns.Window.GetTotalWidth() end,
        function(v) ns.Window.SetTotalWidth(v) end)

    -- (19/10) The specialization icon's shape (the user: square as the default, round as an option).
    y, frame.iconShapeDrop = BuildDropdown(colWindow, y, L["Specialization icon"],
        { { label = L["Square"], value = "square" }, { label = L["Round"], value = "round" } },
        function() return ns.IconShape() end,
        function(v)
            ns.db.iconShape = v
            ns.Window.Refresh()
            if ns.Breakdown and ns.Breakdown.Draw then ns.Breakdown.Draw() end
            if ns.Scoreboard and ns.Scoreboard.Refresh then ns.Scoreboard.Refresh() end
        end)

    y, frame.realmCheck = BuildCheck(colWindow, y, L["Show the realm next to the name"],
        L["Off by default: the realm eats the column and the name is what ends up cut."],
        function() return ns.db.showRealm end,
        function(v)
            ns.db.showRealm = v
            ns.Window.Refresh()
        end)

    -- (14/10) `minimap.hide` existed with no way to change it. The addon compartment (the game's
    -- list of addons by the minimap) keeps opening the meter with the button hidden.
    y, frame.minimapCheck = BuildCheck(colWindow, y, L["Show the minimap button"],
        L["The addon compartment, by the minimap, keeps opening the meter without it."],
        function() return not (ns.db.minimap and ns.db.minimap.hide) end,
        function(v)
            ns.db.minimap = ns.db.minimap or {}
            ns.db.minimap.hide = not v
            if ns.Minimap and ns.Minimap.ApplyVisibility then ns.Minimap.ApplyVisibility() end
        end)

    -- A SECTION OF ITS OWN, and not a fourth line in "Appearance". The screen's rule is that a section is a
    -- SUBJECT, not a quantity: font, rows and realm say how the window LOOKS; which session
    -- it shows is another subject, and putting it under "Appearance" would make the title lie. A section with
    -- one control only is what Blizzard does when the subject is one only.
    y = BuildSection(colWindow, y + GAP_SECTION, L["Session"])

    y, frame.autoSession = BuildCheck(colWindow, y, L["Follow the combat"],
        L["In combat, the current fight; when it ends, back to the overall."],
        function() return ns.db.autoSession end,
        function(v)
            ns.db.autoSession = v
            -- Ticking the box out of combat has to SHOW the effect right away. Ticking and seeing
            -- nothing happen until the next fight is what makes the player think the option does not take.
            if ns.Window.ApplyAutoSession() then
                ns.Window.Refresh(true)
            end
        end)

    y = BuildSection(colWindow, y + GAP_SECTION, L["Scoreboard"])

    y, frame.autoMPlus = BuildCheck(colWindow, y, L["Open at the end of a Mythic+ run"],
        L["When the keystone ends, the summary of the run opens by itself."],
        function() return ns.db.autoScoreboardMPlus end,
        function(v) ns.db.autoScoreboardMPlus = v end)

    y, frame.autoRaid = BuildCheck(colWindow, y, L["Open when a raid boss dies"],
        L["When an encounter is defeated, the summary of the fight opens by itself."],
        function() return ns.db.autoScoreboardRaid end,
        function(v) ns.db.autoScoreboardRaid = v end)

    -- The last two scoreboards. Dimmed when there is no run kept: a button that answers with
    -- an error in the chat teaches less than a dimmed button.
    y, frame.lastMPlus = BuildButton(colWindow, y + 4, L["Last Mythic+"],
        L["Opens the scoreboard of the last Mythic+ run finished on this character."],
        function() ns.Scoreboard.ShowLast("mplus") end)
    frame.lastMPlus.hasRun = "mplus"

    y, frame.lastRaid = BuildButton(colWindow, y, L["Last raid"],
        L["Opens the scoreboard of the last raid boss defeated on this character."],
        function() ns.Scoreboard.ShowLast("raid") end)
    frame.lastRaid.hasRun = "raid"

    -- (20/10) The game's combat log, on by itself inside an instance (MyRun.CombatLogByPlace). On by default: the
    -- user's choice (*"Ligada"*), so whoever uploads to Warcraft Logs has the file without remembering /combatlog.
    y = BuildSection(colWindow, y + GAP_SECTION, L["Combat log"])

    y, frame.combatLog = BuildCheck(colWindow, y, L["Record the combat log in instances"],
        L["On in dungeons, raids and delves, off when leaving: the file Warcraft Logs uploads (its own app sends it; it also asks for the game's advanced combat log). A log you turned on yourself is left alone."],
        function() return ns.db.combatLog end,
        function(v)
            ns.db.combatLog = v
            if ns.MyRun and ns.MyRun.CombatLogByPlace then pcall(ns.MyRun.CombatLogByPlace) end
        end)

    ----------------------------------------------------------------------------
    -- Column 3: the THREE texts, each with its own size, outline and shadow
    ----------------------------------------------------------------------------
    -- One section per role, with the same three controls in the same order. Repeating the form is what
    -- makes the column readable: the player learns once and reads the other two at a glance.
    frame.roleWidgets = {}

    local ROLE_LABELS = {
        body   = L["Row text"],
        title  = L["Title"],
        header = L["Column header"],
    }

    local ry = 0
    for i, role in ipairs(ns.ROLES) do
        ry = BuildSection(colText, ry + (i > 1 and GAP_SECTION or 0), ROLE_LABELS[role])

        local widgets = {}
        ry, widgets.size = BuildSlider(colText, ry, L["Text size"],
            ns.Skin.fontSizeMin, ns.Skin.fontSizeMax, "%dpx",
            function() return ns.Window.GetRoleSize(role) end,
            function(v) ns.Window.SetRoleSize(role, v) end)

        ry, widgets.outline = BuildDropdown(colText, ry, L["Font outline"], OutlineEntries(),
            function() return ns.Window.GetRoleOutline(role) end,
            function(v) ns.Window.SetRoleOutline(role, v) end)

        ry, widgets.shadow = BuildCheck(colText, ry, L["Font shadow"],
            L["A 1px black shadow below the text. Carries the letters over any background."],
            function() return ns.Window.GetRoleShadow(role) end,
            function(v) ns.Window.SetRoleShadow(role, v) end)

        frame.roleWidgets[role] = widgets
    end

    return frame
end

--------------------------------------------------------------------------------
-- Hooks for the harness. What is checked is GEOMETRY -- it is what failed twice
-- in a row in the in-game test, and it is what can be checked without drawing anything.
--------------------------------------------------------------------------------
Picker.__layout = {
    width = WIDTH,
    margin = MARGIN,
    gutter = GUTTER,
    columnWidth = COL_W,
    columns = COLUMNS,
    top = TOP,
    footer = FOOTER,
    checkSize = CHECK_SIZE,
    checkTextOffset = CHECK_TEXT_OFFSET,
    arrow = ARROW,
    arrowGap = ARROW_GAP,
    control = H_CONTROL,
    label = H_LABEL,
    gapLabel = GAP_LABEL,
    gapField = GAP_FIELD,
    gapSection = GAP_SECTION,
    field = H_FIELD,
    check = H_CHECK,
    section = H_SECTION,
}

---A lista de contorno como o combo a monta, para o harness conferir contra `ns.OUTLINE_CHOICES`.
function Picker.__outlineEntries()
    return OutlineEntries()
end

--- Each control and where it sits INSIDE the column. It is with this that the harness checks that nothing
--- leaks through the edge.
--- What the LIST OF COLUMNS offers, in the screen's order.
---
--- It stopped listing the catalogue and came to list ITEMS -- damage+DPS on one line. The door
--- returns what the screen draws, not what `Data` computes: it is the difference between stating that the list
--- of items exists and stating that the screen uses it.
function Picker.__items()
    local out = {}
    for i, row in ipairs(rows) do
        if row:IsShown() then
            out[i] = { key = row.check.columnKey, label = row.label:GetText() }
        end
    end
    return out
end

--- The index a row's ARROW passes to `Window.MoveColumn`.
---
--- ⚑ THIS EXISTS BECAUSE OF A REAL DEFECT: the screen returned the position in `ns.db.columns` and
--- `MoveColumn` indexed the list of GROUPS. With {damage, DPS, healing, HPS, interr} the arrow of the
--- "damage/DPS" row arrived right by coincidence and the healing one moved another family. Nothing showed
--- wrong -- the arrow only moved the wrong thing.
function Picker.__arrowTarget(key)
    for _, row in ipairs(rows) do
        if row.check.columnKey == key and row.up.item then
            return IndexOf(row.up.item)
        end
    end
    return nil
end

function Picker.__probe()
    return probes
end

function Picker.__frame()
    return frame
end

function Picker.__frameHeight()
    return frame and frame:GetHeight() or 0
end

--------------------------------------------------------------------------------
function Picker.RefreshRows()
    if not frame then return end
    if frame.rowsSlider and frame.rowsSlider.Refresh then frame.rowsSlider.Refresh() end
end

function Picker.Refresh()
    if not frame or not frame:IsShown() then return end

    for _, widget in ipairs({ frame.rowsSlider, frame.fontDrop, frame.iconShapeDrop, frame.realmCheck, frame.minimapCheck,
                             frame.gapSlider, frame.pairSlider,
                             frame.autoSession, frame.autoMPlus, frame.autoRaid, frame.combatLog }) do
        if widget and widget.Refresh then widget.Refresh() end
    end

    for _, widgets in pairs(frame.roleWidgets or {}) do
        for _, widget in pairs(widgets) do
            if widget.Refresh then widget.Refresh() end
        end
    end

    for _, b in ipairs({ frame.lastMPlus, frame.lastRaid }) do
        if b then b:SetEnabled(ns.Scoreboard.HasRun(b.hasRun)) end
    end

    -- ITEMS, not columns: damage+DPS and healing+HPS take ONE line each.
    local items = ns.Data.GetColumnItems()
    for i = 1, #items do
        BuildRow(i, items[i], frame.leftColumn,
            frame.columnsTop + (i - 1) * H_COLUMN_ROW)
    end

    -- A row left over from a bigger list cannot stay on screen: `rows` is a cache by index, and the
    -- catalogue shrank from 14 entries to 11 items.
    for i = #items + 1, #rows do rows[i]:Hide() end
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

-- There is no panel in the game's options: this is the addon's settings screen.
function ns.OpenOptions()
    Picker.Toggle()
end

function ns.SetupOptions()
    -- No Settings API panel, on purpose.
end
