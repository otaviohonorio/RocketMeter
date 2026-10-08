-- RocketMeter | Breakdown.lua
--
-- O detalhamento de um jogador: o que ele fez, magia por magia.
--
-- No Details isso é um tooltip que some ao tirar o mouse; aqui é um painel aberto por clique,
-- que fica onde está e acompanha a luta. Mostra as três frentes de uma vez — dano, cura e
-- controle — em vez de só a métrica da janela.
--
-- **Toda a aparência vem de `ns.Skin`** (definido em `Window.lua`): mesma arte de cabeçalho,
-- mesma altura de linha, mesmas cores. Copiar valores entre telas é o que faz elas divergirem.
local ADDON, ns = ...
local L = ns.L

local Breakdown = {}
ns.Breakdown = Breakdown

local WIDTH = 350
local HEADER_HEIGHT = 25
local SECTION_TITLE = 16
local SECTION_GAP = 8
local SIDE = 4
local MAX_PER_SECTION = 8       -- 6 until 07/10: "quais skills" asks for more than the top six
local ALL_SPELLS = 200          -- the whole breakdown, to find the talents in it

local frame, sections
local current

local function Skin()
    return ns.Skin
end

--------------------------------------------------------------------------------
-- (!) INTERRUPTS AND CROWD CONTROL HAVE SECTIONS OF THEIR OWN (30/09). The user: *"clicando na
-- linha onde já mostra as magias usadas, tem que ter essas seções ali também mostrando quais e
-- quantas vezes deram as skills de controle e também de interrupt"*. "Interrupts" is the game's
-- credit, and lists what was interrupted; "Interrupts cast" lists the player's own interrupt
-- spells, with how many of all the casts missed in the title; "Crowd control used" lists what
-- the player cast (Casts.lua). The casts are the player's own: the others' arrive secret.
-- Dispels keep the old "Control" section, alone.
-- (!) HEALING IS NOT ABSORPTION (08/10). The lists by spell added the game's two numbers --
-- healing done and damage absorbed -- under the one title "Healing", and the user, on a
-- druid, read that Matted Fur had HEALED: *"Pelagem Embaraçada curou, mas ela apenas absorve
-- dano, certo?"*. Right: the spell's own text is "absorb ... damage", and the game counts it
-- under Absorbs, a metric of its own. It was this addon that put the two together. They are
-- two sections now, each with the game's own name, for every class alike (Power Word: Shield,
-- Ignore Pain, Ice Barrier and the rest land in the same place).
local function SectionSpecs()
    local E = Enum.DamageMeterType
    return {
        { key = "damage",     title = L["Damage"],  attrs = { E.DamageDone } },
        { key = "healing",    title = L["Healing"], attrs = { E.HealingDone } },
        { key = "absorbs",    title = L["Absorbs"], attrs = { E.Absorbs } },
        -- (07/10) Of those two lists, the lines a talent of the player's own build answers for
        -- (Talents.lua). Only on the player's own line: the build of the others is not ours to read.
        { key = "talentDamage",  title = L["Your talents: direct damage"], talents = { E.DamageDone } },
        { key = "talentHealing", title = L["Your talents: direct healing"], talents = { E.HealingDone } },
        { key = "talentAbsorbs", title = L["Your talents: damage absorbed"], talents = { E.Absorbs } },
        -- The game's credit, for everyone: it lists what was INTERRUPTED (the enemy's spells).
        { key = "interrupts", title = L["Interrupts"], attrs = { E.Interrupts } },
        -- The player's own casts (Casts.lua): the others' arrive secret, so these two sections
        -- only ever show on the player's own line.
        { key = "casts",      title = L["Interrupts cast"], casts = "interrupts" },
        { key = "cc",         title = L["Crowd control used"], casts = "control" },
        { key = "control",    title = L["Dispels"], attrs = { E.Dispels } },
    }
end

---The rows of a section of casts, in the shape of the others: `amount`, plus `missed` for the
---interrupts. The total is what the percent is of: interrupts credited + missed, or the casts.
local function CastRows(kind)
    local interrupts, control, missed = ns.Data.GetCastBreakdown(current.sessionType, current.source,
        current.guid, current.creatureId)
    local list = kind == "interrupts" and interrupts or control
    local total = 0
    for _, row in ipairs(list) do total = total + row.amount end
    return list, total, kind == "interrupts" and missed or nil
end

--------------------------------------------------------------------------------
-- Linha de magia: a mesma anatomia da linha da janela — barra atrás, ícone quadrado
-- preenchendo a altura, nome à esquerda, números à direita.
--------------------------------------------------------------------------------
local function BuildSpellRow(section, index)
    local skin = Skin()
    local row = section.rows[index]

    if not row then
        row = CreateFrame("Frame", nil, section)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.bar = CreateFrame("StatusBar", nil, row)
        row.bar:SetPoint("TOPLEFT")
        row.bar:SetPoint("BOTTOMLEFT")
        row.bar:SetStatusBarTexture(skin.barTexture)
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetFrameLevel(row:GetFrameLevel() + 1)

        row.text = CreateFrame("Frame", nil, row)
        row.text:SetAllPoints()
        row.text:SetFrameLevel(row.bar:GetFrameLevel() + 2)

        row.icon = row.text:CreateTexture(nil, "OVERLAY")
        row.icon:SetPoint("LEFT", 0, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.percent = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.percent:SetPoint("RIGHT", -5, 0)
        row.percent:SetWidth(36)
        row.percent:SetJustifyH("RIGHT")

        row.rate = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rate:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
        row.rate:SetWidth(54)
        row.rate:SetJustifyH("RIGHT")

        row.amount = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.amount:SetPoint("RIGHT", row.rate, "LEFT", -6, 0)
        row.amount:SetWidth(58)
        row.amount:SetJustifyH("RIGHT")

        section.rows[index] = row
    end

    local height = skin.panelRowHeight
    row:SetHeight(height)
    row:ClearAllPoints()
    local y = -(SECTION_TITLE + (index - 1) * (height + skin.rowSpacing))
    row:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, y)

    row.icon:SetSize(height, height)
    row.name:SetWidth(WIDTH - height - 172)

    ns.ApplyPanelFont(row.name, -1, "")
    ns.ApplyPanelFont(row.amount, -1, "")
    ns.ApplyPanelFont(row.rate, -2, "")
    ns.ApplyPanelFont(row.percent, -2, "")

    -- Aqui o fundo existe: o painel tem backdrop, e um preto leve separa as magias.
    local bg = skin.panelRowBackground
    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    return row
end

---Desenha uma seção e devolve a altura ocupada.
local function DrawSection(section, spec)
    local skin = Skin()
    local spells, total, missed, share
    if spec.talents then
        -- Only the player's own build can be read; the share in the title is of ALL the damage
        -- (or healing), so the line says how much of it the talents answer for directly.
        local mine = current.source and current.source.isLocalPlayer
        mine = mine ~= nil and not issecretvalue(mine) and mine == true
        if mine and ns.Talents then
            local all, sum = ns.Data.GetSpellBreakdown(current.sessionType, spec.talents,
                current.guid, current.creatureId, ALL_SPELLS)
            local part
            spells, part = ns.Talents.Of(all)
            total = sum
            if sum and sum > 0 and part > 0 then share = math.floor(part / sum * 100 + 0.5) end
        end
    elseif spec.casts then
        spells, total, missed = CastRows(spec.casts)
    else
        spells, total = ns.Data.GetSpellBreakdown(current.sessionType, spec.attrs,
            current.guid, current.creatureId, MAX_PER_SECTION)
    end

    -- The casts of interrupts carry, in the title, how many of them missed (casts minus the
    -- interrupts the game credited), when that can be known.
    section.title:SetText(missed and format(L["%s (%d missed)"], spec.title, missed)
        or (share and format(L["%s (%d%% of the total)"], spec.title, share)) or spec.title)

    -- Seção sem nada não aparece: "Controle — nada aqui" ocupa espaço para dizer que não há
    -- informação. Quem não interrompeu simplesmente não tem a seção.
    if not spells or #spells == 0 then
        for _, row in pairs(section.rows) do row:Hide() end
        section:Hide()
        return 0
    end

    section:Show()

    -- A barra usa a cor da classe do jogador, como as linhas da janela.
    local r, g, b = ns.ClassColor(current.classFilename)
    local k = skin.barBrightness
    local maximum = spells[1] and spells[1].amount or 1
    if maximum <= 0 then maximum = 1 end

    for i = 1, MAX_PER_SECTION do
        local row = BuildSpellRow(section, i)
        local spell = spells[i]

        if not spell then
            row:Hide()
        else
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell.spellID)
            if not info and C_Spell and C_Spell.RequestLoadSpellData then
                C_Spell.RequestLoadSpellData(spell.spellID)
            end

            row.icon:SetTexture(info and info.iconID or 134400)
            row.name:SetText(info and info.name or ("#" .. tostring(spell.spellID)))
            row.name:SetTextColor(skin.text[1], skin.text[2], skin.text[3])

            row.amount:SetText(ns.Data.FormatAmount(spell.amount) or "-")
            row.amount:SetTextColor(skin.cream[1], skin.cream[2], skin.cream[3])

            local share
            if spec.casts then
                row.rate:SetText("")
                share = total and total > 0 and (spell.amount / total * 100) or nil
            else
                row.rate:SetText(ns.Data.FormatAmount(spell.perSecond) or "-")
                share = total and total > 0 and (spell.amount / total * 100) or nil
            end
            row.rate:SetTextColor(skin.dim[1], skin.dim[2], skin.dim[3])
            row.percent:SetText(share and format("%.0f%%", share) or "-")
            row.percent:SetTextColor(skin.dim[1], skin.dim[2], skin.dim[3])

            row.bar:SetMinMaxValues(0, maximum)
            row.bar:SetValue(spell.amount)
            row.bar:SetStatusBarColor(r * k, g * k, b * k)
            row.bar:SetWidth(WIDTH - SIDE * 2)

            row:Show()
        end
    end

    local used = math.min(#spells, MAX_PER_SECTION)
    local height = SECTION_TITLE + used * (skin.panelRowHeight + skin.rowSpacing)
    section:SetHeight(height)
    return height + SECTION_GAP
end

--------------------------------------------------------------------------------
local function CreatePanel()
    if frame then return frame end
    local skin = Skin()

    frame = CreateFrame("Frame", ADDON .. "Breakdown", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 400)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    -- Mesma decisão da janela: sem fundo e sem moldura. Quem sustenta a leitura são os
    -- Sem fundo, o texto disputaria com o cenário do jogo.
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.03, 0.03, 0.04, skin.panelAlpha)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()

    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)
    frame.header = header

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    ns.ApplyHeaderArt(header.bg)

    frame.icon = header:CreateTexture(nil, "OVERLAY")
    frame.icon:SetSize(HEADER_HEIGHT - 8, HEADER_HEIGHT - 8)
    frame.icon:SetPoint("LEFT", 5, 0)

    frame.iconClass = header:CreateTexture(nil, "OVERLAY")
    frame.iconClass:SetSize(HEADER_HEIGHT - 8, HEADER_HEIGHT - 8)
    frame.iconClass:SetPoint("LEFT", 5, 0)
    frame.iconClass:Hide()

    frame.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 6, 0)

    frame.scope = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.scope:SetPoint("RIGHT", -24, 0)

    frame.close = CreateFrame("Button", nil, header)
    frame.close:SetSize(14, 14)
    frame.close:SetPoint("RIGHT", -5, 0)
    -- Mesmo X do conjunto da janela, no mesmo tom e tamanho.
    frame.close:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    local closeTexture = frame.close:GetNormalTexture()
    if closeTexture then
        if closeTexture.SetAtlas then closeTexture:SetAtlas("common-icon-redx", false) end
        if closeTexture.SetDesaturated then closeTexture:SetDesaturated(true) end
        closeTexture:SetVertexColor(0.78, 0.73, 0.58)
    end
    frame.close:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    sections = {}
    for _, spec in ipairs(SectionSpecs()) do
        local section = CreateFrame("Frame", nil, frame)
        section.rows = {}

        section.title = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        section.title:SetPoint("TOPLEFT", 2, -1)

        section.empty = section:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        section.empty:SetPoint("TOPLEFT", 4, -SECTION_TITLE)

        sections[spec.key] = section
    end

    return frame
end

--------------------------------------------------------------------------------
function Breakdown.Draw()
    if not frame or not current then return end
    local skin = Skin()

    ns.ApplyPanelFont(frame.title, 0, "")
    ns.ApplyPanelFont(frame.scope, -2, "")

    frame.title:SetText(current.name)
    frame.title:SetTextColor(ns.ClassColor(current.classFilename))

    frame.scope:SetText(current.sessionType == 0 and L["Current fight"] or L["Overall"])
    -- Claro: a arte do cabeçalho escurece para a direita, e texto escuro sumia justo ali.
    frame.scope:SetTextColor(0.82, 0.76, 0.56)

    ns.ApplyRowIcon(frame.icon, frame.iconClass, current.source)

    -- Embedded in "Minha corrida" there is no header of its own: the sections start at the top.
    local offset = (frame.embedded and 0 or HEADER_HEIGHT) + 4
    for _, spec in ipairs(SectionSpecs()) do
        local section = sections[spec.key]

        ns.ApplyPanelFont(section.title, -1, "")
        ns.ApplyPanelFont(section.empty, -2, "")
        section.title:SetTextColor(skin.gold[1], skin.gold[2], skin.gold[3])
        section.empty:SetText(L["nothing here"])

        section:ClearAllPoints()
        section:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -offset)
        section:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -offset)

        offset = offset + DrawSection(section, spec)
    end

    frame:SetHeight(offset + 4)
    -- Embedded, the container is the child of a scroll frame: it takes the panel's height, and
    -- what does not fit in the window is reached by scrolling.
    if frame.embedded and frame.embedContainer then frame.embedContainer:SetHeight(offset + 4) end
end

---(!) THE SPELL PANEL INSIDE "MINHA CORRIDA" (01/10). The user: *"quando clica no magias ele muda
---o quadro de posição e tamanho e depois não consigo voltar"*. The "Spells" tab no longer opens
---this panel beside the window: the panel is drawn INSIDE the screen, in the same place and
---size, without its header, backdrop or close button; the screen's tabs bring the summary back.
---@param container Frame the area of the screen the panel fills
function Breakdown.Embed(container, source, sessionType)
    CreatePanel()
    frame.embedded = true
    -- (!) NOT CLAMPED WHILE EMBEDDED (08/10). The user: *"na aba de magias o scroll tá
    -- funcionando, mas a tela não rola"*. The panel is created clamped to the screen, for when
    -- it floats beside the meter. Inside the scroll frame it is as tall as its content -- with
    -- every section full, some 1,000 points, taller than the screen (768) -- and a clamped frame
    -- that does not fit the screen is held in place by the game: the bar moved and the page
    -- stayed. The scroll frame is what keeps it in sight here.
    frame:SetClampedToScreen(false)
    frame:SetParent(container)
    frame:SetFrameStrata(container:GetFrameStrata())
    frame:SetFrameLevel(container:GetFrameLevel() + 1)
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)
    frame:EnableMouse(false)
    frame.header:Hide()
    -- (!) AS TALL AS ITS CONTENT, NOT AS THE WINDOW (01/10). Anchored to the four corners of the
    -- page, the sections ran out under the window: the user, in the game, *"tá saindo conteúdo
    -- pra fora da janela para baixo"*. The panel hangs from the top of the container, sets its
    -- own height, and the container (a scroll child) follows it.
    frame.embedContainer = container
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    frame:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
    Breakdown.Show(source, sessionType, nil, true)
end

---Back to a panel of its own, beside the meter's rows.
function Breakdown.Unembed()
    if not frame or not frame.embedded then return end
    local skin = Skin()
    frame.embedded = nil
    frame.embedContainer = nil
    frame:Hide()
    frame:SetParent(UIParent)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdropColor(0.03, 0.03, 0.04, skin.panelAlpha)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:EnableMouse(true)
    frame.header:Show()
    frame:ClearAllPoints()
    frame:SetSize(WIDTH, 400)
end

---Abre o detalhamento de um jogador.
function Breakdown.Show(source, sessionType, anchorTo, raw)
    if not source then return end

    local guid = source.sourceGUID
    local readable = guid ~= nil and not issecretvalue(guid)

    local isLocal = source.isLocalPlayer
    isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true

    -- (!) THE PLAYER'S OWN ROW OPENS "MINHA CORRIDA" (01/10): the user, *"substitui o painel"*.
    -- The spell panel of the own row is its "Spells" tab (`raw`).
    if isLocal and not raw and ns.MyRunWindow and ns.MyRunWindow.Show then
        if frame then frame:Hide() end
        if ns.PlayerWindow and ns.PlayerWindow.Hide then ns.PlayerWindow.Hide() end
        ns.MyRunWindow.Show(anchorTo)
        return
    end

    if not readable then
        if isLocal then
            guid = UnitGUID("player")
        else
            ns.Print(L["the spell breakdown of other players is only available out of combat."])
            return
        end
    end

    CreatePanel()

    current = {
        guid = guid,
        creatureId = source.sourceCreatureID,
        name = source.name,
        classFilename = source.classFilename,
        sessionType = sessionType,
        source = source,
    }

    if frame.embedded then
        Breakdown.Draw()
        frame:Show()
        return
    end

    -- Abre do lado que tiver espaço: ancorar sempre à direita jogava o painel para fora da
    -- tela quando a janela está encostada na borda.
    frame:ClearAllPoints()
    local placed = false
    if anchorTo and anchorTo.GetRight and UIParent and UIParent.GetWidth then
        local right = anchorTo:GetRight()
        local screen = UIParent:GetWidth()
        if type(right) == "number" and type(screen) == "number" then
            if right + WIDTH + 6 <= screen then
                frame:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 6, 0)
            else
                frame:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", -6, 0)
            end
            placed = true
        end
    end
    if not placed then
        frame:SetPoint("CENTER")
    end

    Breakdown.Draw()
    frame:Show()
end

--------------------------------------------------------------------------------
-- (!) THE MOUSE OVER A ROW SAYS WHAT THE PLAYER CAST (08/10). The user: *"ao passar o mouse em
-- cima da linha, ele faz igual o details, mostra o que o usuário lançou (...) e no clique sim,
-- mantém o que temos"*. What Details shows there was read (`class_damage.lua`, its
-- `ToolTip_DamageDone`): the player's spells, largest first, each with its icon, its amount and
-- its share. The idea is taken; the box is the game's own tooltip, with the game's helpers and
-- colours, not a skin of ours. Damage first, then healing when there is any; the click keeps
-- opening the full screen, and the last line says so.
--
-- In combat the game hides every number (and the others' identity): the tooltip then says only
-- that, instead of an empty box.
local TOOLTIP_DAMAGE, TOOLTIP_HEALING, TOOLTIP_ABSORBS = 6, 4, 3
local TOOLTIP_WIDTH = 260       -- the least the tooltip is wide, so a bar has a length to read
local TOOLTIP_BAR_ALPHA = 0.7

-- (!) A BAR BEHIND EACH SPELL (08/10). The first tooltip had the numbers and no bars; the user:
-- *"no passar ao mouse por cima, falta as barras"* -- in Details each line of the tooltip is a
-- bar, as long as the spell's share of the largest. The game's own tooltip bars
-- (`GameTooltip_AddStatusBar`) are a framed line of their OWN between the text lines, not
-- something behind a line, so the bars are ours: the meter's flat bar, in the player's class
-- colour, the same one the rows of the window are made of. They are textures of the tooltip
-- itself, one layer under its text (a child frame would cover the text), put behind the lines
-- once the tooltip has laid itself out, and hidden when it hides or is cleared for another use.
local tipBars, tipHooked = {}, {}

local function HideTooltipBars()
    for _, bar in ipairs(tipBars) do bar:Hide() end
end

local function TooltipLine(tip, n)
    if tip.GetLeftLine then
        local ok, line = pcall(tip.GetLeftLine, tip, n)
        if ok and line then return line end
    end
    local name = tip.GetName and tip:GetName()
    return name and _G[name .. "TextLeft" .. n] or nil
end

---Puts a bar behind each of `marks` (`{ line = n, share = 0..1 }`), in the colour given.
local function LayTooltipBars(tip, marks, r, g, b)
    if not tipHooked[tip] and tip.HookScript then
        tipHooked[tip] = true
        tip:HookScript("OnHide", HideTooltipBars)
        tip:HookScript("OnTooltipCleared", HideTooltipBars)
    end
    local width = (tip.GetWidth and tip:GetWidth() or TOOLTIP_WIDTH) - 20
    local skin = Skin()
    local k = skin and skin.barBrightness or 1
    local used = 0
    for _, mark in ipairs(marks) do
        local line = TooltipLine(tip, mark.line)
        if line then
            used = used + 1
            local bar = tipBars[used]
            if not bar then
                bar = tip:CreateTexture(nil, "BORDER")
                tipBars[used] = bar
            end
            bar:SetTexture(skin and skin.barTexture or "Interface\\Buttons\\WHITE8X8")
            bar:SetVertexColor((r or 1) * k, (g or 1) * k, (b or 1) * k, TOOLTIP_BAR_ALPHA)
            bar:ClearAllPoints()
            bar:SetPoint("TOPLEFT", line, "TOPLEFT", -2, 1)
            bar:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", -2, -1)
            bar:SetWidth(math.max(1, width * math.min(1, math.max(0, mark.share))))
            bar:Show()
        end
    end
    for i = used + 1, #tipBars do tipBars[i]:Hide() end
    return used
end
function Breakdown.__tooltipBars() return tipBars end

local function TooltipSection(tip, marks, title, sessionType, attrs, guid, creatureId, limit)
    local spells, total = ns.Data.GetSpellBreakdown(sessionType, attrs, guid, creatureId, limit)
    if not spells or #spells == 0 or not total or total <= 0 then return false end
    GameTooltip_AddBlankLineToTooltip(tip)
    GameTooltip_AddNormalLine(tip, format("%s: %s", title, ns.Data.FormatAmount(total) or "-"))
    for _, spell in ipairs(spells) do
        local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell.spellID)
        local name = info and info.name or ("#" .. tostring(spell.spellID))
        local icon = info and info.iconID or 134400
        tip:AddDoubleLine(format("|T%s:14:14:0:0:64:64:5:59:5:59|t %s", tostring(icon), name),
            format("%s  %d%%", ns.Data.FormatAmount(spell.amount) or "-", math.floor(spell.amount / total * 100 + 0.5)),
            HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b,
            HIGHLIGHT_FONT_COLOR.r, HIGHLIGHT_FONT_COLOR.g, HIGHLIGHT_FONT_COLOR.b)
        -- The bar of this line: its share of the LARGEST of the section, as in the window.
        if tip.NumLines and spells[1].amount > 0 then
            marks[#marks + 1] = { line = tip:NumLines(), share = spell.amount / spells[1].amount }
        end
    end
    return true
end

---The tooltip of a row of the meter.
---@param owner Frame the row
---@param source table the row's source, as the meter gives it
---@return boolean shown
function Breakdown.Tooltip(owner, source, sessionType)
    if not (owner and source and GameTooltip) then return false end
    local tip = GameTooltip
    local guid = source.sourceGUID
    local isLocal = source.isLocalPlayer
    isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true
    if (guid == nil or issecretvalue(guid)) and isLocal and UnitGUID then guid = UnitGUID("player") end
    local readable = guid ~= nil and not issecretvalue(guid)

    -- Beside the row, on the side that has room (the same rule as the panel).
    tip:SetOwner(owner, "ANCHOR_NONE")
    tip:ClearAllPoints()
    local right = owner.GetRight and owner:GetRight()
    local screen = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if type(right) == "number" and type(screen) == "number" and right + 300 > screen then
        tip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
    else
        tip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    end

    local name = source.name
    if name == nil or issecretvalue(name) then name = isLocal and UnitName and UnitName("player") or nil end
    local r, g, b = ns.ClassColor(source.classFilename)
    tip:SetText(name or L["Player"], r, g, b)

    local any = false
    local marks = {}
    HideTooltipBars()
    if readable then
        local E = Enum.DamageMeterType
        local creature = source.sourceCreatureID
        any = TooltipSection(tip, marks, L["Damage"], sessionType, { E.DamageDone }, guid, creature, TOOLTIP_DAMAGE) or any
        any = TooltipSection(tip, marks, L["Healing"], sessionType, { E.HealingDone }, guid, creature, TOOLTIP_HEALING) or any
        any = TooltipSection(tip, marks, L["Absorbs"], sessionType, { E.Absorbs }, guid, creature, TOOLTIP_ABSORBS) or any
    end
    if any then
        GameTooltip_AddBlankLineToTooltip(tip)
        GameTooltip_AddInstructionLine(tip, L["Click: the full screen of this player"])
    else
        GameTooltip_AddNormalLine(tip, L["The spells can only be read out of combat."], true)
    end
    if #marks > 0 and tip.SetMinimumWidth then tip:SetMinimumWidth(TOOLTIP_WIDTH) end
    tip:Show()
    -- After `Show`: only then has the tooltip its width and its lines their places.
    if #marks > 0 and tip.CreateTexture then pcall(LayTooltipBars, tip, marks, r, g, b) end
    return true
end

---The spell panel of the player's own row, as the "Spells" tab of "Minha corrida" opens it.
function Breakdown.ShowOwn(anchorTo, container)
    local class
    if UnitClassBase then
        local ok, c = pcall(UnitClassBase, "player")
        if ok and type(c) == "string" then class = c end
    end
    local source = { isLocalPlayer = true, sourceGUID = UnitGUID and UnitGUID("player") or nil,
                     name = UnitName and UnitName("player") or nil, classFilename = class, sourceCreatureID = 0 }
    local sessionType = ns.db and ns.db.sessionType or 1
    if container then
        Breakdown.Embed(container, source, sessionType)
    else
        Breakdown.Show(source, sessionType, anchorTo, true)
    end
end

function Breakdown.IsShown()
    return frame ~= nil and frame:IsShown()
end

---For the harness: the sections as drawn (`sections[key]`, with `rows` and `title`).
function Breakdown.__frame() return frame end
function Breakdown.__sections()
    return sections
end

function Breakdown.Refresh()
    if Breakdown.IsShown() then
        Breakdown.Draw()
    end
end

function Breakdown.Hide()
    if frame then frame:Hide() end
end
