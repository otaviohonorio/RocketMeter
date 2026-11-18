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
    -- (17/11) only a FRAME has OnSizeChanged: a texture given as its own owner (the Lab's Talents tab, Window.lua)
    -- made the game raise "Cannot assign script handler for 'onsizechanged'" five times on 04/11
    local isFrame = owner and owner.GetObjectType and owner:GetObjectType() ~= "Texture"
    if isFrame and owner.HookScript and not rawget(tex, "__cutHooked") then
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

---A section: the title in gold (GameFontNormalLarge) on the band of the game's quest tracker secondary header (18/11,
---the modern identity; at its own proportion, 300 x 30, never stretched). Returns the next y, the title, the band.
function Style.Section(parent, x, y, width, text)
    y = y - Style.SECTION_GAP
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 8, y - 4)
    t:SetText(text)
    local band = parent:CreateTexture(nil, "ARTWORK", nil, -1)
    band:SetAtlas("ui-questtracker-secondary-objective-header")
    local bw = math.min(320, math.max(120, (width or 300) * 0.92))
    band:SetSize(bw, bw * 30 / 300)
    band:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 4, y + 2)
    return y - Style.SECTION_H, t, band
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
    Style.SkinCheck(c)
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
    Style.SkinDropdown(d)
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
    Style.SkinSlider(s)
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

---The bronze button (Style.NewButton). Returns the next y.
function Style.Button(parent, x, y, width, label, tip, onClick)
    local b = Style.NewButton(parent, label, width, Style.BUTTON_H)
    b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 4)
    b:SetScript("OnClick", onClick)
    Tip(b, label, tip)
    return y - 4 - 22 - 10, b
end

-- (18/11/2026) THE MODERN ROCKET IDENTITY (the user approved the component sheet, mockup/PREVIA Rocket componentes.png,
-- and the mockup of every addon: "ficou lindo, parabéns, pode fazer"). The pieces below dress the windows and the
-- controls in our own art (tools/rocket_pele.py, the same Textures/Rocket*.png in every addon): the window is our dark
-- panel with a light-bronze filete, the body stone, a header with the SEAL (the logo round in the game's gold ring), the
-- name and a subtitle on the band of the game's quest tracker; the buttons, drop-downs, check boxes, sliders and fields
-- are the bronze button with volume and its family; tabs are a segmented row on top; sections sit on the tracker's
-- secondary band. The game's own templates stay underneath (behaviour, menus, scroll bars, tooltips): only their art
-- changes, with one call (Style.Skin*). Skill wow-ui-design, "A IDENTIDADE MODERNA".
Style.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
Style.ART_SCALE = 0.5            -- our art is drawn at 2 pixels per point
Style.BUTTON_H = 22
Style.HEAD = 58                  -- the header: the seal (9..47) and the band; the content starts under it
Style.INSET = 4                  -- the body, inside the panel's filete
Style.SEAL = 38
Style.ORANGE = { 1, 0x6a / 255, 0 }
Style.BRONZE_LIGHT = { 0x80 / 255, 0x6c / 255, 0x4a / 255 }

---Our 9-slice art at half scale: the corners keep their size in points. `margin` in the file's pixels; `pad` in points,
---how far the art goes past the frame (negative: inside it).
function Style.Slice(parent, file, margin, pad, layer, sub)
    local t = parent:CreateTexture(nil, layer or "BACKGROUND", nil, sub or -7)
    t:SetTexture(Style.MEDIA .. file)
    t:SetTextureSliceMargins(margin, margin, margin, margin)
    t:SetScale(Style.ART_SCALE)
    local o = (pad or 0) / Style.ART_SCALE
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", -o, o)
    t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", o, -o)
    return t
end

local function Hide(p)
    if type(p) == "table" and p.Hide then p:Hide() end
end
local function Clear(p)
    if type(p) == "table" and p.SetAlpha then p:SetAlpha(0) end
end

---The button's three looks on any Button: our art under it (normal), the gold border on the HIGHLIGHT layer (the game
---shows it under the mouse, no script), sunk while pressed (hooks: the callers keep their own scripts), grey disabled.
local function ButtonArt(b, pad)
    b.__bg = Style.Slice(b, "RocketButton.png", 10, pad or 0)
    b.__hover = Style.Slice(b, "RocketButtonHover.png", 10, pad or 0, "HIGHLIGHT", 0)
    b.__pressed = Style.Slice(b, "RocketButtonPressed.png", 10, pad or 0, "BACKGROUND", -6)
    b.__pressed:Hide()
    b:HookScript("OnMouseDown", function(self)
        if self.IsEnabled and not self:IsEnabled() then return end
        self.__pressed:Show()
        self.__hover:Hide()
    end)
    local function Up(self)
        self.__pressed:Hide()
        self.__hover:Show()
    end
    b:HookScript("OnMouseUp", Up)
    b:HookScript("OnHide", Up)
    local function Paint(self)
        local on = not self.IsEnabled or self:IsEnabled()
        self.__bg:SetDesaturated(not on)
        self.__bg:SetAlpha(on and 1 or 0.6)
    end
    b:HookScript("OnDisable", Paint)
    b:HookScript("OnEnable", Paint)
    b.__paint = Paint
    Paint(b)
end

---A new button: the bronze with volume, the text in the game's gold 12 (white under the mouse). `width`: at least it;
---it grows to the text plus 30.
function Style.NewButton(parent, text, width, height)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width or 90, height or Style.BUTTON_H)
    ButtonArt(b)
    b:SetNormalFontObject("GameFontNormal")
    b:SetHighlightFontObject("GameFontHighlight")
    b:SetDisabledFontObject("GameFontDisable")
    if b.SetPushedTextOffset then b:SetPushedTextOffset(0, -1) end
    b:SetText(text or "")
    local fs = b:GetFontString()
    if width and fs and fs.GetStringWidth then b:SetWidth(math.max(width, (fs:GetStringWidth() or 0) + 30)) end
    return b
end

---A button made with the game's UIPanelButtonTemplate, dressed as ours: its red pieces cleared (the template keeps
---changing their file on press and on show; their alpha stays 0), our art under it.
function Style.SkinButton(b)
    if rawget(b, "__bg") then return b end
    for _, k in ipairs({ "Left", "Middle", "Right" }) do Clear(b[k]) end
    if b.ClearHighlightTexture then b:ClearHighlightTexture() end
    ButtonArt(b)
    return b
end

---A check box (the game's MinimalCheckboxTemplate or UICheckButtonTemplate) dressed as ours: an 18-point box of the
---button's art (gold under the mouse) with the game's own gold tick (checkmark-minimal).
function Style.SkinCheck(c)
    if rawget(c, "__bg") then return c end
    for _, f in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = c[f] and c[f](c)
        Clear(t)
    end
    local w = c.GetWidth and c:GetWidth() or 24
    local pad = -math.max(0, ((w > 0 and w or 24) - 18) / 2)
    c.__bg = Style.Slice(c, "RocketButton.png", 10, pad)
    c.__hover = Style.Slice(c, "RocketButtonHover.png", 10, pad, "HIGHLIGHT", 0)
    for _, f in ipairs({ "GetCheckedTexture", "GetDisabledCheckedTexture" }) do
        local t = c[f] and c[f](c)
        if t and t.SetAtlas then
            t:SetAtlas(f == "GetCheckedTexture" and "checkmark-minimal" or "checkmark-minimal-disabled")
            t:ClearAllPoints()
            t:SetPoint("CENTER")
            t:SetSize(22, 21)
            t:SetAlpha(1)
        end
    end
    c:HookScript("OnDisable", function(self) self.__bg:SetDesaturated(true); self.__bg:SetAlpha(0.6) end)
    c:HookScript("OnEnable", function(self) self.__bg:SetDesaturated(false); self.__bg:SetAlpha(1) end)
    return c
end

-- The drop-down's open menu: our panel (with the filete) instead of the game's background; the items stay the game's.
local menuMixin
local function MenuMixin()
    if menuMixin then return menuMixin end
    local base = rawget(_G, "MenuStyle1Mixin") or rawget(_G, "MenuStyleMixin")
    if not (base and CreateFromMixins) then return nil end
    menuMixin = CreateFromMixins(base)
    function menuMixin:Generate()
        local t = self:AttachTexture()
        t:SetTexture(Style.MEDIA .. "RocketPanel.png")
        t:SetTextureSliceMargins(28, 28, 28, 28)
        t:SetScale(Style.ART_SCALE)
        local o = 8 / Style.ART_SCALE
        t:SetPoint("TOPLEFT", self, "TOPLEFT", -o + 2, o - 2)
        t:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", o - 2, -o + 2)
    end
    return menuMixin
end

---A drop-down (the game's WowStyle1DropdownTemplate) dressed as ours: the bronze button, the value in white on the left,
---the game's minimal arrow on the right (up while the menu is open), the menu on our panel.
function Style.SkinDropdown(d)
    if rawget(d, "__bg") then return d end
    Clear(d.Background)
    Clear(d.Arrow)
    if d.SetHeight then d:SetHeight(Style.BUTTON_H) end
    ButtonArt(d)
    local arrow = d:CreateTexture(nil, "OVERLAY")
    arrow:SetAtlas("minimal-scrollbar-arrow-bottom")
    arrow:SetSize(13, 8)
    arrow:SetPoint("RIGHT", -9, 0)
    d.__arrow = arrow
    if type(d.Text) == "table" then
        d.Text:ClearAllPoints()
        d.Text:SetPoint("LEFT", 9, 0)
        d.Text:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
        d.Text:SetJustifyH("LEFT")
        if d.Text.SetFontObject then d.Text:SetFontObject("GameFontHighlight") end
    end
    -- (18/11, found on the Rocket Mount's Filter) the game paints the text gold again when the drop-down is enabled:
    -- the value stays white (an option's value is white in the family)
    if type(d.Text) == "table" then
        d:HookScript("OnEnable", function(self) self.Text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB()) end)
    end
    local mm = MenuMixin()
    if mm then d.menuMixin = mm end
    local ev = rawget(_G, "DropdownButtonMixin") and DropdownButtonMixin.Event
    if ev and d.RegisterCallback then
        d:RegisterCallback(ev.OnMenuOpen, function()
            arrow:SetAtlas("minimal-scrollbar-arrow-top")
            d.__pressed:Show()
        end, d)
        d:RegisterCallback(ev.OnMenuClose, function()
            arrow:SetAtlas("minimal-scrollbar-arrow-bottom")
            d.__pressed:Hide()
        end, d)
    end
    return d
end

---A slider (the game's MinimalSliderWithSteppersTemplate) dressed as ours: a dark track with a bronze border, the
---part up to the value in bronze-gold, our round thumb (gold ring under the mouse); the game's minimal steppers stay.
function Style.SkinSlider(s)
    local sl = type(s.Slider) == "table" and s.Slider or s
    if rawget(sl, "__track") then return s end
    for _, k in ipairs({ "Left", "Middle", "Right" }) do Clear(sl[k]) end
    local track = CreateFrame("Frame", nil, sl)
    track:SetPoint("LEFT", sl, "LEFT", 0, 0)
    track:SetPoint("RIGHT", sl, "RIGHT", 0, 0)
    track:SetHeight(6)
    track:SetFrameLevel(math.max(0, (sl:GetFrameLevel() or 1) - 1))
    track.bg = Style.Slice(track, "RocketField.png", 6, 0)
    sl.__track = track
    local thumb = sl.GetThumbTexture and sl:GetThumbTexture()
    if type(thumb) == "table" then
        thumb:SetTexture(Style.MEDIA .. "RocketKnob.png")
        thumb:SetSize(14, 14)
        local fill = sl:CreateTexture(nil, "ARTWORK", nil, -1)
        fill:SetColorTexture(1, 1, 1, 1)
        if fill.SetGradient and CreateColor then
            fill:SetGradient("VERTICAL", CreateColor(0.55, 0.40, 0.18, 1), CreateColor(0.80, 0.62, 0.30, 1))
        end
        fill:SetPoint("LEFT", track, "LEFT", 1, 0)
        fill:SetPoint("RIGHT", thumb, "CENTER", 0, 0)
        fill:SetHeight(4)
        sl.__fill = fill
        sl:HookScript("OnEnter", function() thumb:SetTexture(Style.MEDIA .. "RocketKnobHover.png") end)
        sl:HookScript("OnLeave", function() thumb:SetTexture(Style.MEDIA .. "RocketKnob.png") end)
    end
    return s
end

local function FieldArt(e, left)
    e.__bg = Style.Slice(e, "RocketField.png", 8, 0, "BACKGROUND", -7)
    e.__focus = Style.Slice(e, "RocketFieldFocus.png", 8, 0, "BACKGROUND", -6)
    for _, t in ipairs({ e.__bg, e.__focus }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", e, "TOPLEFT", -(left or 0) / Style.ART_SCALE, 0)
        t:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", 0, 0)
    end
    e.__focus:Hide()
    e:HookScript("OnEditFocusGained", function(self) self.__focus:Show() end)
    e:HookScript("OnEditFocusLost", function(self) self.__focus:Hide() end)
end

---A text field (the game's InputBoxTemplate or SearchBoxTemplate) dressed as ours: dark, a bronze border, gold with the
---focus; the search box keeps the game's magnifying glass and clear button.
function Style.SkinField(e)
    if rawget(e, "__bg") then return e end
    for _, k in ipairs({ "Left", "Middle", "Right" }) do Clear(e[k]) end
    FieldArt(e, type(e.searchIcon) == "table" and 0 or 5)       -- InputBoxTemplate draws its border 5 to the left of the text
    return e
end

---A new text field of ours (an EditBox with the field's art), `width` x 22.
function Style.NewField(parent, width)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width, 22)
    e:SetAutoFocus(false)
    e:SetFontObject("GameFontHighlight")
    e:SetTextInsets(8, 8, 0, 0)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    FieldArt(e, 0)
    return e
end

---The tabs: a segmented row of buttons on top (one per tab). The active one sunk, its text gold with a gold line under
---it; the others light grey (white under the mouse). `onSelect(i)`. Returns the row (row.tabs, row:Select(i), its width).
function Style.Tabs(parent, x, y, labels, onSelect)
    local row = CreateFrame("Frame", nil, parent)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    row:SetHeight(24)
    row.tabs = {}
    local xx = 0
    for i, text in ipairs(labels) do
        local b = CreateFrame("Button", nil, row)
        b:SetHeight(24)
        ButtonArt(b)
        b:SetNormalFontObject("GameFontHighlight")
        b:SetHighlightFontObject("GameFontHighlight")
        b:SetText(text)
        local fs = b:GetFontString()
        b:SetWidth(((fs and fs:GetStringWidth()) or 60) + 28)
        b:SetPoint("TOPLEFT", row, "TOPLEFT", xx, 0)
        b.line = b:CreateTexture(nil, "OVERLAY")
        b.line:SetColorTexture(NORMAL_FONT_COLOR:GetRGB())
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 6, 2)
        b.line:SetPoint("BOTTOMRIGHT", -6, 2)
        b.index = i
        b:SetScript("OnClick", function(self) row:Select(self.index, true) end)
        row.tabs[i] = b
        xx = xx + b:GetWidth() + 2
    end
    row:SetWidth(math.max(1, xx - 2))
    function row:Select(i, user)
        self.selected = i
        for j, b in ipairs(self.tabs) do
            local on = (j == i)
            b.line:SetShown(on)
            b.__pressed:SetShown(on)
            local fs = b:GetFontString()
            if fs then fs:SetTextColor((on and NORMAL_FONT_COLOR or LIGHTGRAY_FONT_COLOR):GetRGB()) end
        end
        if user and onSelect then onSelect(i) end
    end
    return row
end

---A list row / card of ours: the card art; under the mouse a light-bronze ring (HIGHLIGHT layer); selected
---(card:SetSelected(true)) a gold ring and the family's orange accent on the left.
function Style.Card(parent, template)
    local c = CreateFrame("Button", nil, parent, template)
    c.__bg = Style.Slice(c, "RocketCard.png", 16, 0)
    c.__hover = Style.Slice(c, "RocketCardRing.png", 16, 0, "HIGHLIGHT", 0)
    c.__hover:SetVertexColor(Style.BRONZE_LIGHT[1], Style.BRONZE_LIGHT[2], Style.BRONZE_LIGHT[3])
    c.__ring = Style.Slice(c, "RocketCardRing.png", 16, 0, "OVERLAY", 7)
    c.__ring:SetVertexColor(NORMAL_FONT_COLOR:GetRGB())
    c.__ring:Hide()
    c.__accent = c:CreateTexture(nil, "BORDER")
    c.__accent:SetColorTexture(Style.ORANGE[1], Style.ORANGE[2], Style.ORANGE[3], 1)
    c.__accent:SetWidth(3)
    c.__accent:SetPoint("TOPLEFT", 1, -4)
    c.__accent:SetPoint("BOTTOMLEFT", 1, 4)
    c.__accent:Hide()
    function c:SetSelected(on)
        self.__ring:SetShown(on and true or false)
        self.__accent:SetShown(on and true or false)
    end
    return c
end

---THE WINDOW in the modern identity, over a frame made with the game's ButtonFrameTemplate (or any frame): the
---template's frame, portrait, title bar, red close and stone hidden (the template stays for its Inset and behaviour);
---our panel with the filete, the body stone 4 in, the header (the seal, ns.TITLE or `opts.title` in 12, a subtitle in
---gold 16 on the tracker's band) and the close X 10 from the edge. opts: { subtitle, title, seal = false (a small
---notice: no seal, the title at the left), onClose, noClose, noBody }. Returns the header (head:SetSubtitle(text)).
function Style.Window(f, opts)
    opts = opts or {}
    for _, p in ipairs({ f.NineSlice, f.Bg, f.TopTileStreaks, f.PortraitContainer, f.TitleContainer, f.CloseButton,
                         rawget(f, "portrait"), rawget(f, "TitleBg") }) do
        Hide(p)
    end
    if type(f.Inset) == "table" then
        Hide(f.Inset.Bg)
        Hide(f.Inset.NineSlice)
    end
    f.__panel = Style.Slice(f, "RocketPanel.png", 28, 8, "BACKGROUND", -8)
    if not opts.noBody then
        local body = Style.Body(f, 1)
        body:ClearAllPoints()
        body:SetPoint("TOPLEFT", Style.INSET, -Style.INSET)
        body:SetPoint("BOTTOMRIGHT", -Style.INSET, Style.INSET)
    end
    local head = CreateFrame("Frame", nil, f)
    head:SetPoint("TOPLEFT")
    head:SetPoint("TOPRIGHT")
    local seal = opts.seal ~= false
    head:SetHeight(seal and Style.HEAD or 34)
    local tx = seal and 62 or 14
    if seal then
        head.logo = head:CreateTexture(nil, "ARTWORK")
        head.logo:SetTexture(ns.LOGO)
        head.logo:SetSize(Style.SEAL * 0.8, Style.SEAL * 0.8)
        head.logo:SetPoint("CENTER", head, "TOPLEFT", 10 + Style.SEAL / 2, -(9 + Style.SEAL / 2))
        if head.CreateMaskTexture then
            local mask = head:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(head.logo)
            head.logo:AddMaskTexture(mask)
        end
        head.ring = head:CreateTexture(nil, "OVERLAY")
        head.ring:SetAtlas("communities-ring-gold")
        head.ring:SetSize(Style.SEAL, Style.SEAL)
        head.ring:SetPoint("TOPLEFT", 10, -9)
        head.banner = head:CreateTexture(nil, "BORDER")
        head.banner:SetAtlas("ui-questtracker-primary-objective-header")
        head.banner:SetSize(240, 32)
        head.banner:SetPoint("TOPLEFT", 42, -21)
    end
    head.title = head:CreateFontString(nil, "ARTWORK", seal and "GameFontNormal" or "GameFontNormalLarge")
    head.title:SetPoint("TOPLEFT", tx, -10)
    head.title:SetText(opts.title or ns.TITLE)
    head.subtitle = head:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    head.subtitle:SetPoint("TOPLEFT", tx, -29)
    head.subtitle:SetPoint("RIGHT", head, "RIGHT", -40, 0)
    head.subtitle:SetJustifyH("LEFT")
    head.subtitle:SetWordWrap(false)
    function head.SetSubtitle(text)
        head.subtitle:SetText(text or "")
    end
    head.SetSubtitle(opts.subtitle)
    if not opts.noClose then
        local close = CreateFrame("Button", nil, f)
        close:SetSize(20, 20)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -7)
        close.icon = close:CreateTexture(nil, "ARTWORK")
        close.icon:SetAtlas("common-icon-redx")
        close.icon:SetSize(14, 14)
        close.icon:SetPoint("CENTER")
        close:SetScript("OnClick", function() if opts.onClose then opts.onClose() else f:Hide() end end)
        close:SetScript("OnEnter", function(self) self.icon:SetAlpha(0.75) end)
        close:SetScript("OnLeave", function(self) self.icon:SetAlpha(1) end)
        f.__close = close
        head.close = close
    end
    f.__head = head
    return head
end
