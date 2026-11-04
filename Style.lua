-- Style.lua — the Rocket design system (the same file in every Rocket addon; only this header line differs). [RocketMeter]
-- (03/11/2026) The user, with the windows of four addons side by side: "falta tudo ainda para termos uma
-- identidade, definição de texturas, cores para cada tipo de componente (...) usando as cores da blizzard, uma
-- textura agradável que não atrapalhe a visualização dos textos e componentes". The model is the game's own
-- Options panel (Blizzard_SettingControls.xml): a section title in white with the game's divider under it, the
-- option's name on the left, its control in a column on the right, the "minimal" check box. The COLOURS are the
-- Rocket SBA Lab app's (the user, 03/11: "as cores do lab do app me agradam mais, é mais blizzard"): warm dark body,
-- section titles in gold over a thin bronze line, option names in white, secondary text in the game's light grey.
-- The body art: number 5 of mockup/PREVIA Padrao visual Rocket - paleta do app.png (the user: "pode ir na sua
-- recomendação"), the warm texture of the game's housing panel. Skill wow-ui-design, "O SISTEMA DE DESIGN ROCKET".
local ADDON, ns = ...

local Style = {}
ns.Style = Style

-- (04/11/2026) THE BODY IS OUR STONE, WindowStone.png (in every addon's Textures): the stone the user generated for the
-- Rocket Mount's drawer, seamless (tools/arte_textura_gaveta.py), in the warm tone of the Journeys' stone (its centre,
-- RGB 36/32/32) and with NO dark border. History the same day: the housing panel art of 03/11 showed the world through
-- it ("tá com fundo transparente em toda janela"); the Journeys' stone (`ui-journeys-bg`) has a vignette, and on a
-- window bigger than its 792 x 432 it showed dark corners ("não gostei dos cantos com essa sombra"). One pixel per
-- point, CUT to the window's size (Style.Paint): never stretched; a window wider than 1024 scales it the same on both
-- axes.
Style.BODY_FILE = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\WindowStone.png"
Style.BODY_SIZE = 1024
Style.DIVIDER_ATLAS = "Options_HorizontalDivider"
Style.BRONZE = rawget(_G, "CreateColor") and CreateColor(0x4a / 255, 0x3f / 255, 0x2c / 255, 1) or nil   -- the app's --edge
Style.ROW = 32              -- one option per 32, as the mockup the user chose
Style.SECTION_GAP = 10      -- air above a section title
Style.SECTION_H = 38        -- the title, the divider and the air under it
Style.INDENT = 12           -- an option's name, in from its section's title

---The body of a window: the chosen art, under everything, inside the frame (or over `stone`, the template's own
---background, which it hides). One texture per art (wow-ui-design).
function Style.Body(frame, alpha, stone)
    local art = rawget(frame, "__body")
    if not art then
        art = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        if type(stone) == "table" then   -- by TYPE: a stub (or a missing key) must not pass for a texture
            art:SetAllPoints(stone)
            if stone.Hide then stone:Hide() end
        else
            art:SetPoint("TOPLEFT", 3, -3)
            art:SetPoint("BOTTOMRIGHT", -3, 3)
        end
        frame.__body = art
        Style.Paint(art, frame)
    end
    art:SetAlpha(alpha or 1)
    art:Show()
    return art
end

---Paints `tex` with the body stone, cut to `owner`'s size at one pixel per point (again whenever it changes size).
---Also for a texture that showed another art before (the Lab's Talents tab wears the spec's art): the stone's
---file and its cut replace it.
function Style.Paint(tex, owner)
    tex:SetTexture(Style.BODY_FILE)
    Style.CutBody(tex, owner or tex)
    if owner and owner.HookScript and not rawget(tex, "__cutHooked") then
        tex.__cutHooked = true
        owner:HookScript("OnSizeChanged", function()
            if tex.GetTexture and tex:GetTexture() ~= nil then Style.CutBody(tex, owner) end
        end)
    end
end

---The cut: the stone's top-left window of the owner's size, one pixel per point; scaled the same on both axes only
---when the owner is bigger than the file.
function Style.CutBody(art, frame)
    local n = Style.BODY_SIZE
    local w = tonumber((frame.GetWidth and frame:GetWidth()) or 0) or 0
    local h = tonumber((frame.GetHeight and frame:GetHeight()) or 0) or 0
    if not (w > 0 and h > 0) then return end
    local s = math.max(1, w / n, h / n)
    art:SetTexCoord(0, w / s / n, 0, h / s / n)
end

local function Tip(owner, title, text)
    if not text then return end
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, title)
        GameTooltip_AddNormalLine(GameTooltip, text, true)
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", GameTooltip_Hide)
end
Style.Tip = Tip

---A texture made into the system's divider: the game's line, tinted bronze (the app's --edge). For the rules
---that were drawn by hand (a gold colour at 25%) under the section titles of the denser forms.
function Style.Divider(texture)
    texture:SetAtlas(Style.DIVIDER_ATLAS)
    if Style.BRONZE then texture:SetVertexColor(Style.BRONZE.r, Style.BRONZE.g, Style.BRONZE.b) end
    return texture
end

---A section: the title in gold (GameFontNormalLarge, the app's h2) and the game's divider, tinted bronze, under it.
function Style.Section(parent, x, y, width, text)
    y = y - Style.SECTION_GAP
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    t:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetAtlas(Style.DIVIDER_ATLAS)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 26)
    line:SetWidth(width)
    if Style.BRONZE then line:SetVertexColor(Style.BRONZE.r, Style.BRONZE.g, Style.BRONZE.b) end
    return y - Style.SECTION_H, t, line
end

---An option's name, in white (the app's text), on the left of its row.
function Style.Label(parent, x, y, text, width)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", parent, "TOPLEFT", x + Style.INDENT, y - 13)
    if width then t:SetWidth(width - Style.INDENT) end
    t:SetJustifyH("LEFT")
    t:SetText(text)
    return t
end

---The game's "minimal" check box in the control column. `get`/`set` keep the value; returns the next y.
function Style.Check(parent, x, y, col, label, tip, get, set)
    local t = Style.Label(parent, x, y, label, col - x - 8)
    local c = CreateFrame("CheckButton", nil, parent, "MinimalCheckboxTemplate")
    c:SetSize(30, 29)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", col, y + 1)
    c:SetChecked(get() and true or false)
    c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
    Tip(c, label, tip)
    c.label = t
    return y - Style.ROW, c
end

---The game's drop-down in the control column. `values` = { { value, text }, ... }. Returns the next y.
function Style.Dropdown(parent, x, y, col, width, label, tip, values, get, set)
    local t = Style.Label(parent, x, y, label, col - x - 8)
    local d = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    d:SetPoint("TOPLEFT", parent, "TOPLEFT", col, y)
    d:SetWidth(width)
    d:SetupMenu(function(_, root)
        for _, v in ipairs(values) do
            root:CreateRadio(v.text, function() return get() == v.value end, function() set(v.value) end)
        end
    end)
    Tip(d, label, tip)
    d.label = t
    return y - Style.ROW, d
end

---The game's slider with steppers in the control column, the value in white on its right. Returns the next y.
function Style.Slider(parent, x, y, col, width, label, tip, min, max, step, fmt, get, set)
    local t = Style.Label(parent, x, y, label, col - x - 8)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetPoint("RIGHT", parent, "TOPLEFT", col + width, y - 13)
    value:SetJustifyH("RIGHT")
    local s = CreateFrame("Slider", nil, parent, "MinimalSliderWithSteppersTemplate")
    s:SetPoint("TOPLEFT", parent, "TOPLEFT", col, y - 1)
    s:SetWidth(width - 40)
    s:SetHeight(26)
    local function Write() value:SetText((fmt or "%d"):format(get())) end
    if s.Init and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Event then
        s:Init(get(), min, max, math.floor((max - min) / step + 0.5))
        s:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, v)
            if v == get() then return end
            set(v)
            Write()
        end)
    end
    Tip(s, label, tip)
    Write()
    s.label, s.value = t, value
    return y - Style.ROW, s
end

---A colour in the control column: the game's own swatch (ColorSwatchTemplate, Blizzard_SharedXMLBase) opening the
---game's colour picker (ColorPickerFrame). `get()` gives r, g, b (the colour in use: the user's or the game's);
---`set(r, g, b)` keeps one, `set(nil)` goes back to the game's. A click picks, a right click goes back to the game's
---colour. Several on one row: pass `dx` (the swatch's offset in the column) and `label = nil` after the first.
---Returns the next y (the same y when `stay`).
function Style.Color(parent, x, y, col, label, tip, get, set, dx, stay)
    local t = label and Style.Label(parent, x, y, label, col - x - 8) or nil
    local b = CreateFrame("Button", nil, parent, "ColorSwatchTemplate")
    b:SetSize(24, 24)   -- the swatch is 14; the click target is 24 (WCAG 2.5.8)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", col + (dx or 0), y - 1)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    local function Paint()
        local r, g, bl = get()
        if b.SetColorRGB then b:SetColorRGB(r or 1, g or 1, bl or 1) end
    end
    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            set(nil)
            Paint()
            return
        end
        local r, g, bl = get()
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = bl, hasOpacity = false,
            swatchFunc = function()
                set(ColorPickerFrame:GetColorRGB())
                Paint()
            end,
            cancelFunc = function(prev)
                set(prev.r, prev.g, prev.b)
                Paint()
            end,
        })
    end)
    b:SetScript("OnEnter", function(self)
        if self.SetBorderColor then self:SetBorderColor(NORMAL_FONT_COLOR) end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip_SetTitle(GameTooltip, tip and tip.title or label or "")
        if tip and tip.text then GameTooltip_AddNormalLine(GameTooltip, tip.text, true) end
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        GameTooltip_AddInstructionLine(GameTooltip, tip and tip.click or "")
        GameTooltip_AddInstructionLine(GameTooltip, tip and tip.reset or "")
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        if self.SetBorderColor then self:SetBorderColor(HIGHLIGHT_FONT_COLOR) end
        GameTooltip_Hide()
    end)
    Paint()
    b.label, b.Paint = t, Paint
    return stay and y or (y - Style.ROW), b
end

---The game's red button. Returns the next y.
function Style.Button(parent, x, y, width, label, tip, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    Tip(b, label, tip)
    return y - 4 - 22 - 10, b
end
