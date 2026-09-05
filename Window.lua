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

-- APARENCIA FIXA. Nada aqui e configuravel: primeiro o padrao precisa estar certo.
-- Os valores saem da referencia (Details com a skin do medidor nativo).
local FONT = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE = 12
-- A skin usa `rowTextShadow = true` e deixa o contorno desligado: é **sombra**, não outline.
-- Outline engorda o traço e foi o que deixou o texto pesado.
local FONT_OUTLINE = ""
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- Estes números vêm do `styleConfig` da skin Details_Midnight, que está instalada:
--   wallpaperAlpha = 0.4      -> fundo da janela
--   barBackgroundAlpha = 0.4  -> fundo escuro atrás do preenchimento
--   barHeight = 20, barSpacingBetween = 1, barFontSize = 12
local BAR_BRIGHTNESS = 0.7          -- escurece a cor da classe para o texto branco ler
local ROW_BG_ALPHA = 0.45           -- fundo da linha; sem barra preenchida, ele sustenta o texto
local ROW_BG_TINT = 0.22            -- quanto da cor da classe entra nesse fundo
-- Fundo invisível: é a variante "No Background" da skin (`wallpaperAlpha = 0.0`).
-- Quem sustenta a leitura são os fundos das próprias linhas (ROW_BG_ALPHA).
local WINDOW_ALPHA = 0
local ROW_HEIGHT_FIXED = 20         -- skin: barHeight
local COLUMN_WIDTH_FIXED = 58

-- Proporção da referência: a skin usa faixa de 32px com texto de 13pt, ou seja, o texto
-- ocupa ~40% da altura. Com 20px e 13pt eu tinha 65% — daí a sensação de apertado.
-- Exposto para os outros painéis (detalhamento, placar) seguirem a mesma linguagem sem
-- copiar valores — cópia é o que faz as telas divergirem com o tempo.
ns.Skin = {
    font = FONT,
    fontSize = FONT_SIZE,
    barTexture = BAR_TEXTURE,
    barBrightness = BAR_BRIGHTNESS,
    rowHeight = ROW_HEIGHT_FIXED,
    rowSpacing = 1,
    rowBackground = { 0, 0, 0, ROW_BG_ALPHA },
    windowAlpha = WINDOW_ALPHA,
    -- A janela é overlay sobre o jogo e fica transparente; painel de leitura pede fundo,
    -- senão o texto disputa com o cenário. Daí dois alfas em vez de um.
    panelAlpha = 0.70,
    headerAtlas = "ui-damagemeters-header-bar",
    headerCrop = { 0.045, 0.965, 4 / 60, 56 / 60 },
    gold = { 1, 0.82, 0 },
    cream = { 1, 0.88, 0.62 },
    text = { 0.86, 0.87, 0.90 },
    dim = { 0.68, 0.69, 0.72 },
}

---Aplica a arte do cabeçalho da Blizzard numa textura, com o mesmo recorte da referência.
function ns.ApplyHeaderArt(texture)
    local info = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(ns.Skin.headerAtlas)

    if info and (info.file or info.filename) then
        texture:SetTexture(info.file or info.filename)
        local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
        local t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
        local w, h = r - l, b - t
        local crop = ns.Skin.headerCrop
        texture:SetTexCoord(l + w * crop[1], l + w * crop[2], t + h * crop[3], t + h * crop[4])
        return true
    end

    texture:SetColorTexture(0.13, 0.11, 0.07, 0.95)
    return false
end

local HEADER_HEIGHT = 25
local COLHEAD_HEIGHT = 12
local NAME_MIN_WIDTH = 96
local PADDING = 3
local PROGRESS_HEIGHT = 2       -- a linha fina de progresso no rodapé, como no medidor nativo
local MIN_ROWS = 1              -- uma linha ainda é útil: só você, no boneco de treino
local MAX_ROWS = 20             -- tamanho de uma raide; acima disso a janela toma a tela
local GRIP = 14

-- Cadeado plano: o mesmo ícone nos dois estados, distinguidos por cor e saturação. Não há
-- atlas de cadeado na família `common-icon-*`, então este é o glifo mais próximo dela.
local LOCK_ICON = "Interface\\PetBattles\\PetBattle-LockIcon"

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

-- Texturas do próprio jogo (nenhum arquivo nosso, nenhuma biblioteca de mídia).
ns.BAR_TEXTURES = {
    { key = "flat",     path = "Interface\\Buttons\\WHITE8X8",                        label = "Chapada" },
    { key = "blizzard", path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",              label = "Blizzard" },
    { key = "classic",  path = "Interface\\TargetingFrame\\UI-StatusBar",             label = "Clássica" },
    { key = "skills",   path = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", label = "Perícias" },
    { key = "score",    path = "Interface\\WorldStateFrame\\WORLDSTATEFINALSCORE-HIGHLIGHT", label = "Placar" },
}

function ns.BarTexture()
    return BAR_TEXTURE
end

local frame, headerRow, rows
local dirty, throttle = false, 0
local visibleRows = -1
local scrollOffset = 0      -- quantas linhas foram roladas para fora do topo
local totalRows = 0         -- quantos atores existem ao todo, para limitar a rolagem

--------------------------------------------------------------------------------
-- Fonte e cor
--------------------------------------------------------------------------------
function ns.FontPath()
    return FONT
end

---Aplica a fonte configurada. `delta` ajusta o corpo para rótulos secundários.
function ns.ApplyFont(fontString, delta, flags)
    local size = FONT_SIZE + (delta or 0)
    if size < 6 then size = 6 end

    fontString:SetFont(FONT, size, flags or FONT_OUTLINE)

    -- Sombra de 1px carrega o texto branco sobre a barra colorida sem o peso do contorno.
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 1)
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

---Cor do preenchimento da barra.
---
---A cor pura da classe é clara demais atrás de texto branco — no medidor da Blizzard e no
---Details a barra é uma versão **escurecida** dela. `barBrightness` controla o quanto.
function ns.BarColor(classFilename)
    local r, g, b = ns.ClassColor(classFilename)
    return r * BAR_BRIGHTNESS, g * BAR_BRIGHTNESS, b * BAR_BRIGHTNESS
end

---Fundo da linha: a mesma cor, bem apagada, para a parte vazia não ser um buraco preto.
---Fundo da linha: **preto fixo**, não tingido pela classe.
---A skin usa `texture_background_class_color = false` com
---`barBackgroundColor = {0, 0, 0, 0.4}` — tingir pela classe, como eu fazia, deixava a parte
---vazia da barra colorida e embaralhava a leitura de quem tinha pouco.
function ns.RowBackdropColor()
    return 0, 0, 0, ROW_BG_ALPHA
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
-- Sem máscara: `SetMask` e `SetTexCoord` não convivem ("Cannot set tex coords when texture
-- has mask"), e a referência usa ícone quadrado mesmo. Duas texturas por linha: uma para o
-- ícone de especialização (id inteiro) e outra para o de classe (recorte de atlas).

---@param spec texture redonda, para o ícone de especialização (id inteiro, sem recorte)
---@param class texture com texcoord, para o recorte do atlas de classes
function ns.ApplyRowIcon(spec, class, source)
    local specIcon = source.specIconID
    if specIcon ~= nil and not issecretvalue(specIcon) and specIcon ~= 0 then
        spec:SetTexture(specIcon)
        spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- tira a borda preta do ícone
        spec:Show()
        class:Hide()
        return
    end

    local name = SafeClass(source.classFilename)
    local coords = name and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[name]
    if coords then
        class:SetTexture(CLASS_ICONS)
        class:SetTexCoord(unpack(coords))
        class:Show()
        spec:Hide()
        return
    end

    spec:Hide()
    class:Hide()
end

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------
local function RowHeight()
    return ROW_HEIGHT_FIXED
end

local function ColumnWidth()
    return COLUMN_WIDTH_FIXED
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

local function ColumnHeaderHeight()
    return COLHEAD_HEIGHT
end

---Altura da janela para N linhas.
---
---A janela **mantém o tamanho que o usuário deu**, como no Details: as barras preenchem de cima
---para baixo e o resto fica de fundo. Encolher para o conteúdo, como eu tinha feito, tornava a
---alça inútil — com um jogador só, arrastar não mudava nada e parecia travado.
local function WindowHeight(rowCount)
    if rowCount < 1 then rowCount = 1 end
    return HEADER_HEIGHT + ColumnHeaderHeight() + rowCount * (RowHeight() + 1) + PADDING
end

--------------------------------------------------------------------------------
-- Cabeçalho das colunas
--------------------------------------------------------------------------------
local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
        -- Sem fundo: com a janela transparente, uma faixa escura aqui vira um segundo
        -- retângulo opaco logo abaixo do título e pesa a tela.
        headerRow.bg = headerRow:CreateTexture(nil, "BACKGROUND")
        headerRow.bg:SetAllPoints()
        headerRow.bg:SetColorTexture(0, 0, 0, 0)
    end

    headerRow:ClearAllPoints()
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING + 2, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING - 2, -HEADER_HEIGHT)
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
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetPoint("RIGHT", -4, 0)

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
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(L["The leader of each column is highlighted, out of combat."], 0.5, 0.7, 1, true)
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
            -- Só a cor marca a coluna ordenada: o dourado já diz tudo, e uma seta aqui
            -- repetia a informação ocupando espaço.
            button.text:SetText(label)
            button.text:SetTextColor(1, 0.82, 0)
        else
            button.text:SetText(label)
            button.text:SetTextColor(0.78, 0.74, 0.60)
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
        row = CreateFrame("Button", nil, frame, "BackdropTemplate")

        -- Sem isto o clique atravessa a linha e cai no frame da janela: o mouse precisa ser
        -- habilitado explicitamente, mesmo em Button criado por código.
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")

        row:SetScript("OnClick", function(self)
            if not self.source then return end

            -- Arquivo .lua novo no .toc só entra depois de sair para a tela de personagens;
            -- com /reload o módulo fica ausente e o clique morreria calado.
            if not ns.Breakdown then
                ns.Print(L["restart the client: the breakdown module was not loaded yet."])
                return
            end

            local ok, err = pcall(ns.Breakdown.Show, self.source, ns.db.sessionType, frame)
            if not ok then
                ns.Print("|cffff5555" .. L["error while drawing:"] .. "|r " .. tostring(err))
            end
        end)

        -- Realce ao passar o mouse, no lugar de tooltip: mostra que a linha é clicável sem
        -- cobrir a tela com uma caixa de texto.
        row:SetScript("OnEnter", function(self)
            if self.hover then self.hover:Show() end
        end)
        row:SetScript("OnLeave", function(self)
            if self.hover then self.hover:Hide() end
        end)
        row:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0, 0, 0, 0.55)

        -- Como no medidor nativo: nada de preenchimento tomando a linha inteira. O valor
        -- aparece como uma **linha fina no rodapé**, na cor da classe.
        --
        -- Isso muda mais do que a estética: com o fundo neutro, a cor da classe fica livre
        -- para ser usada no texto da coluna liderada — o que antes era impossível, porque
        -- texto colorido sobre barra da mesma cor some.
        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("BOTTOMLEFT", 1, 1)
        row.bar:SetPoint("BOTTOMRIGHT", -1, 1)
        row.bar:SetHeight(PROGRESS_HEIGHT)
        row.bar:SetStatusBarTexture(ns.BarTexture())
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(0)
        row.bar:SetFrameLevel(row:GetFrameLevel() + 1)

        -- Camada de texto ACIMA da barra. Sem isso o texto some: a StatusBar e um frame
        -- filho, e frame filho desenha por cima dos FontStrings do pai — foi exatamente o
        -- bug da 0.11.0, em que a linha aparecia como uma barra vazia.
        row.text = CreateFrame("Frame", nil, row)
        row.text:SetAllPoints()
        row.text:SetFrameLevel(row.bar:GetFrameLevel() + 2)

        row.hover = row.text:CreateTexture(nil, "ARTWORK")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.10)
        row.hover:Hide()

        -- Ícone quadrado ocupando a linha inteira, como na referência: a skin usa
        -- `icon_mask = ""` e `icon_size_offset = 0`. A máscara circular que eu tinha posto
        -- encolhia o ícone e o deixava solto no meio da barra.
        row.icon = row.text:CreateTexture(nil, "OVERLAY")
        row.icon:SetPoint("LEFT", 0, 0)

        -- Segunda textura só para o ícone de classe, que precisa de texCoord.
        row.iconClass = row.text:CreateTexture(nil, "OVERLAY")
        row.iconClass:SetPoint("LEFT", 0, 0)
        row.iconClass:Hide()

        row.name = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetJustifyH("LEFT")
        -- Nome comprido corta em vez de quebrar linha ou invadir a coluna de números.
        row.name:SetWordWrap(false)

        row.cells = {}
        rows[index] = row
    end

    local height = RowHeight()
    row:SetHeight(height)
    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + ColumnHeaderHeight() + (index - 1) * (height + 1))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, offsetY)

    row.bar:SetStatusBarTexture(ns.BarTexture())

    if row.SetBackdropBorderColor then
        -- A referência não tem borda na linha: o espaçamento de 1px já separa as barras.
        row:SetBackdropBorderColor(0, 0, 0, 0)
    end

    local iconSize = height          -- preenche a linha inteira, como no Details
    row.icon:SetSize(iconSize, iconSize)
    row.iconClass:SetSize(iconSize, iconSize)
    row.bar:SetHeight(PROGRESS_HEIGHT)
    ns.ApplyFont(row.name, 0)

    for _, cell in pairs(row.cells) do
        cell:Hide()
    end

    local offsets, columnsWidth = ColumnOffsets()

    for c = 1, #ns.db.columns do
        local cell = row.cells[c]
        if not cell then
            cell = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cell:SetJustifyH("RIGHT")
            row.cells[c] = cell
        end
        -- A coluna de ordenação é a que importa: fica no corpo cheio, as outras menores.
        ns.ApplyFont(cell, ns.db.columns[c] == ns.db.sortBy and 0 or -1)
        cell:SetWidth(ColumnWidth() - 8)
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", row.text, "RIGHT", -offsets[c] - 4, 0)
        cell:Show()
    end

    row.name:SetWidth(WindowWidth() - PADDING * 2 - columnsWidth - iconSize - 10)
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
    frame:SetBackdropColor(0.03, 0.03, 0.04, WINDOW_ALPHA)
    frame:SetBackdropBorderColor(0, 0, 0, 0)      -- sem retângulo preto em volta


    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)

    -- A referência (medidor nativo / Details com a skin dele) tem faixa bege-oliva com
    -- texto escuro. Tenta o atlas do jogo; se ele não existir neste cliente, desenha o
    -- mesmo tom à mão para o resultado ser igual de qualquer jeito.
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()

    -- A arte é o atlas do medidor nativo, recortada como na skin de referência.
    ns.ApplyHeaderArt(header.bg)

    header.segment = CreateFrame("Button", nil, header)
    header.segment:SetSize(120, HEADER_HEIGHT - 6)
    header.segment:SetPoint("LEFT", 7, 1)
    header.segment.text = header.segment:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.segment.text:SetPoint("LEFT")
    header.segment.text:SetTextColor(1, 0.82, 0)      -- dourado padrão da Blizzard
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

    header.clock = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.clock:SetPoint("LEFT", header.segment, "RIGHT", 6, 0)
    header.clock:SetTextColor(0.85, 0.72, 0.36)

    frame.header = header

    -- Um só tratamento para todos os ícones: mesmo tamanho, mesmo tom, mesma reação ao
    -- mouse. A família vem do próprio jogo — `questlog-icon-setting` é a engrenagem do
    -- rastreador de missões, da mesma UI de onde sai a arte da faixa de título.
    local ICON_TINT = { 0.78, 0.73, 0.58 }
    local ICON_HOVER = { 1, 0.95, 0.80 }

    local function HeaderButton(spec, tooltip, onClick)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(14, 14)

        -- Uma textura vazia primeiro: `SetAtlas` precisa de textura existente para atuar.
        b:SetNormalTexture(spec.texture or "Interface\\Buttons\\WHITE8X8")
        local tex = b:GetNormalTexture()
        if tex and spec.atlas and tex.SetAtlas then
            tex:SetAtlas(spec.atlas, false)
        end
        if tex then
            -- Dessaturar primeiro: cada atlas traz cor própria (o X é vermelho, a engrenagem
            -- puxa dourado) e o `SetVertexColor` **multiplica** em cima dela — sem tirar a cor
            -- de origem, os botões nunca ficam do mesmo tom.
            if tex.SetDesaturated then tex:SetDesaturated(true) end
            tex:SetVertexColor(ICON_TINT[1], ICON_TINT[2], ICON_TINT[3])
        end

        b.SetTint = function(_, color)
            local t = b:GetNormalTexture()
            if t then t:SetVertexColor(color[1], color[2], color[3]) end
        end

        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            self:SetTint(ICON_HOVER)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(tooltip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self:SetTint(self.activeTint or ICON_TINT)
            GameTooltip_Hide()
        end)

        b.baseTint = ICON_TINT
        return b
    end

    frame.closeButton = HeaderButton(
        { atlas = "common-icon-redx", texture = "Interface\\Buttons\\UI-GroupLoot-Pass-Up" },
        L["Close"], function() Window.Hide() end)
    frame.closeButton:SetPoint("RIGHT", header, "RIGHT", -5, 0)

    frame.gearButton = HeaderButton(
        { atlas = "questlog-icon-setting", texture = "Interface\\Buttons\\UI-OptionsButton" },
        L["Configure columns"], function() ns.Picker.Toggle(frame) end)
    frame.gearButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -5, 0)

    frame.resetButton = HeaderButton(
        { atlas = "common-icon-undo", texture = "Interface\\Buttons\\UI-RefreshButton" },
        L["Clear the data"], function() ns.Data.RequestReset() end)
    frame.resetButton:SetPoint("RIGHT", frame.gearButton, "LEFT", -5, 0)

    frame.lockButton = HeaderButton(
        { texture = LOCK_ICON },
        L["Lock position"], function()
            ns.db.locked = not ns.db.locked
            Window.ApplyLock()
        end)
    frame.lockButton:SetPoint("RIGHT", frame.resetButton, "LEFT", -5, 0)

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
    -- Sem atalho de configuração no clique: o botão direito atravessava a linha e caía aqui,
    -- abrindo as opções quando o usuário só queria o detalhamento. A engrenagem do cabeçalho e
    -- o botão do minimapa já dão acesso.

    -- Rolagem pela roda do mouse, sem barra: a barra ocuparia largura e apareceria mesmo
    -- quando não há o que rolar, que é o caso quase sempre.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maximum = totalRows - ns.db.rows
        if maximum < 0 then maximum = 0 end

        local wanted = scrollOffset - delta
        if wanted < 0 then wanted = 0 end
        if wanted > maximum then wanted = maximum end

        if wanted ~= scrollOffset then
            scrollOffset = wanted
            Window.Refresh(true)
        end
    end)

    -- Alça de redimensionamento: largura livre, altura em número de linhas.
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        -- Máximo generoso: quem arrasta decide, o limite é só para não virar tela cheia.
        frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
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
        Window.SetRows(math.floor(usable / (RowHeight() + 1) + 0.5))
        frame:SetHeight(WindowHeight(ns.db.rows))
    end)
    frame.grip = grip

    rows = {}
    Window.Rebuild()
    Window.ApplyLock()

    frame:SetScript("OnUpdate", function(_, elapsed)
        if not dirty then return end
        throttle = throttle + elapsed
        if throttle < 0.2 then return end
        throttle, dirty = 0, false
        Window.SafeDraw()
    end)

    return frame
end

---Refaz cabeçalho, linhas e medidas — depois de mudar colunas, fonte, tamanho ou largura.
function Window.Rebuild()
    if not frame then return end

    frame:SetBackdropColor(0.03, 0.03, 0.04, WINDOW_ALPHA)
    frame:SetBackdropBorderColor(0, 0, 0, 0)

    -- Sem contorno no cabeçalho: texto escuro sobre faixa clara fica sujo com outline.
    ns.ApplyFont(frame.header.segment.text, 0, "")   -- proporcional à faixa
    ns.ApplyFont(frame.header.clock, -1, "")

    BuildColumnHeader()
    for i = 1, ns.db.rows do
        BuildRow(i)
    end
    for i = ns.db.rows + 1, #rows do
        rows[i]:Hide()
    end

    frame:SetWidth(WindowWidth())
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
    end

    visibleRows = -1
    Window.Refresh(true)
end

function Window.Refresh(immediate)
    if not frame then return end
    if immediate then
        dirty, throttle = false, 0
        Window.SafeDraw()
    else
        dirty = true
    end
end

---Desenha protegido. Um erro dentro de OnUpdate deixaria a janela congelada e sem pista
---nenhuma — este envelope transforma isso numa mensagem, uma única vez por erro.
local lastError
function Window.SafeDraw()
    local ok, err = pcall(Window.Draw)
    if not ok and err ~= lastError then
        lastError = err
        ns.Print("|cffff5555" .. L["error while drawing:"] .. "|r " .. tostring(err))
    end
end

function Window.GetLastError()
    return lastError
end

-- Como realçar quem lidera cada coluna sem inventar cor nem enfeite:
--
--   1ª tentativa — cor dourada: virava "amarelo de ladino", competia com a cor de classe.
--   2ª tentativa — seta ao lado: ancorada no vão entre colunas, parecia sujeira solta.
--   3ª e atual  — **brilho**: o líder em branco puro, os demais levemente apagados.
--
-- Brilho é neutro (não carrega significado de classe), não ocupa espaço e o olho encontra
-- sozinho o número mais forte de cada coluna. É a mesma hierarquia que a UI do jogo usa para
-- separar informação principal de secundária.
-- Equilíbrio entre "todo mundo legível" e "dá para achar o líder":
--
--   O cinza 0.66 da tentativa anterior destacava o líder às custas dos outros, que ficaram
--   difíceis de ler. A diferença de brilho sozinha só funciona se o piso for baixo demais.
--
-- Agora o piso sobe para 0.86 (legível de verdade) e o líder ganha, além do branco puro, uma
-- **placa neutra** atrás — branco a 8%, sem cor, sem ícone, sem ocupar espaço extra.
-- O líder é pintado com a **cor da própria classe** — e isso não repete o erro do dourado:
-- lá a cor era arbitrária e parecia dizer "ladino"; aqui ela diz exatamente o que a cor de
-- classe sempre diz, "este jogador". O vocabulário é usado, não contrariado.
--
-- Só que cor de classe crua não serve para texto: vermelho de cavaleiro da morte e roxo de
-- bruxo são escuros demais sobre fundo escuro. A cor é **clareada em direção ao branco**, o
-- que preserva a identidade e garante a leitura.
-- Com a linha fina no rodapé, o fundo da linha ficou **neutro** — e aí a cor da classe pode
-- voltar para o texto da coluna liderada. Era o objetivo desde o começo e não funcionava
-- enquanto a barra preenchida ocupava o fundo com a mesma cor.
--
-- Continua valendo o cuidado de sempre: cor crua é escura demais para algumas classes
-- (cavaleiro da morte, bruxo). Um **piso de luminância** corrige só quem precisa, e só o
-- necessário — clarear todas por igual devolveria o tom lavado que já foi reprovado.
local LEADER_MIN_LUMA = 0.55
local LEADER_FALLBACK = { 1, 0.88, 0.62 }
local NORMAL = { 0.80, 0.81, 0.84 }

local function Luminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

local function LeaderColor(classFilename)
    local class = SafeClass(classFilename)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then
        return LEADER_FALLBACK[1], LEADER_FALLBACK[2], LEADER_FALLBACK[3]
    end

    local r, g, b = color.r, color.g, color.b
    local luma = Luminance(r, g, b)
    if luma >= LEADER_MIN_LUMA then
        return r, g, b
    end

    local k = (LEADER_MIN_LUMA - luma) / (1 - luma)
    return r + (1 - r) * k, g + (1 - g) * k, b + (1 - b) * k
end

---Estiliza a célula de quem lidera a coluna. O realce mora **no texto**: tom mais fechado e
---um ponto de corpo a mais. Sem placa atrás — ela clareava a célula inteira e virava um bloco
---estranho no meio da linha.
---
---`OUTLINE` foi testado e reprovado: engrossa o traço da letra, o que é peso na tinta e não
---hierarquia — fica pesado mesmo numa célula só. O que funciona é **corpo de fonte**: +1pt no
---líder aumenta a presença sem mudar a espessura do traço.
function ns.StyleCell(row, index, isBest)
    local cell = row.cells[index]
    local highlight = isBest and ns.db.highlightBest ~= false

    -- A coluna ordenada já usa o corpo cheio; as demais, um ponto menor.
    local delta = ns.db.columns[index] == ns.db.sortBy and 0 or -1

    if highlight then
        ns.ApplyFont(cell, delta + 1, "")

        cell:SetTextColor(LeaderColor(row.classFilename))
        cell:SetShadowColor(0, 0, 0, 1)
    else
        ns.ApplyFont(cell, delta, "")
        cell:SetTextColor(NORMAL[1], NORMAL[2], NORMAL[3])
        cell:SetShadowColor(0, 0, 0, 1)
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
        -- Valor secret: tenta a estratégia de formatação que funcionou neste cliente.
        local secretText = ns.Data.FormatSecretAmount(value)
        if secretText ~= nil then
            fontString:SetText(secretText)
        else
            fontString:SetText(value)
        end
        return
    end

    -- Sem sufixo "/s": o rótulo da coluna (DPS, CPS) já diz que é por segundo, e repetir
    -- em cada linha só rouba espaço da coluna.
    fontString:SetText(text)
end

function Window.Draw()
    if not frame or not frame:IsShown() then return end

    local data, session, total = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
        ns.db.rows, not ns.db.sortDesc, scrollOffset)
    local maxAmount = session and session.maxAmount

    totalRows = total or 0

    -- Se gente saiu do grupo (ou a lista encolheu), a rolagem tem que voltar junto.
    local maximum = totalRows - ns.db.rows
    if maximum < 0 then maximum = 0 end
    if scrollOffset > maximum then
        scrollOffset = maximum
        data, session = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
            ns.db.rows, not ns.db.sortDesc, scrollOffset)
        maxAmount = session and session.maxAmount
    end

    local scope = ns.db.sessionType == 0 and L["Current fight"] or L["Overall"]
    if totalRows > ns.db.rows then
        -- Sem barra de rolagem: a contagem no título é o que avisa que há mais gente.
        scope = format("%s  |cff909090%d-%d/%d|r", scope,
            scrollOffset + 1, math.min(scrollOffset + ns.db.rows, totalRows), totalRows)
    end
    frame.header.segment.text:SetText(scope)

    local duration = ns.Data.GetDuration(ns.db.sessionType)
    if duration ~= nil and not issecretvalue(duration) and duration > 0 then
        frame.header.clock:SetText(SecondsToClock(duration))
    elseif InCombatLockdown() then
        frame.header.clock:SetText("|cff909090" .. L["in combat"] .. "|r")
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

            local top = maxAmount
            if top == nil then top = 1 end
            local value = source.totalAmount
            if value == nil then value = 0 end
            row.bar:SetMinMaxValues(0, top)
            row.bar:SetValue(value)
            -- Cor cheia: não há texto por cima da linha, então não precisa escurecer.
            row.bar:SetStatusBarColor(ns.ClassColor(source.classFilename))
            row.bg:SetColorTexture(ns.RowBackdropColor())

            ns.ApplyRowIcon(row.icon, row.iconClass, source)
            row.name:SetText(source.name)
            row.name:SetTextColor(1, 1, 1)
            row.classFilename = source.classFilename
            row.source = source

            for c = 1, #ns.db.columns do
                local key = ns.db.columns[c]
                ns.SetCellText(row.cells[c], entry.values[c], key)
                ns.StyleCell(row, c, entry.best and entry.best[c])
            end

            row:Show()
        end
    end

    -- Altura fixa, definida pela alça: as linhas vazias mostram o fundo, como no Details.
    if ns.Breakdown and ns.Breakdown.Refresh then
        ns.Breakdown.Refresh()
    end

    if visibleRows ~= ns.db.rows then
        visibleRows = ns.db.rows
        frame:SetHeight(WindowHeight(ns.db.rows))
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

---Diagnóstico: as linhas estão recebendo clique? Responde sem depender de tentativa e erro.
function Window.RowsAreClickable()
    local row = rows and rows[1]
    if not row then return false end
    return row:IsMouseEnabled() and row:GetScript("OnClick") ~= nil and row.source ~= nil
end

---Aplica o estado travado: ícone do cadeado e visibilidade da alça.
---
---A alça só faz sentido destravada — deixá-la visível travada convida a arrastar algo que não
---vai se mexer. Some junto.


function Window.ApplyLock()
    if not frame then return end

    local locked = ns.db.locked and true or false

    if frame.grip then
        frame.grip:SetShown(not locked)
    end

    local button = frame.lockButton
    if not button then return end

    button:SetNormalTexture(LOCK_ICON)
    local texture = button:GetNormalTexture()
    if not texture then return end

    texture:SetDesaturated(true)   -- sem a cor original do ícone, para entrar na família

    -- Travado chama atenção; destravado fica no tom dos outros ícones.
    local tint = locked and { 1, 0.82, 0.30 } or button.baseTint
    button.activeTint = tint
    button:SetTint(tint)
end

---Define quantas linhas a janela mostra, ajustando a altura.
---
---Ponto único usado pela alça de redimensionar e pelo painel de configuração — sem isto os dois
---caminhos calculariam a altura de formas diferentes.
function Window.SetRows(count)
    if type(count) ~= "number" then return end
    if count < MIN_ROWS then count = MIN_ROWS end
    if count > MAX_ROWS then count = MAX_ROWS end
    if count == ns.db.rows then return end

    ns.db.rows = count
    Window.Rebuild()
    if frame then
        frame:SetHeight(WindowHeight(count))
    end
end

function Window.GetRows()
    return ns.db.rows
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
