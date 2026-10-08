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
        -- Without the shields: the game's healing done carries them too (Data.GetPureHealing).
        { key = "healing",    title = L["Healing"], attrs = { E.HealingDone }, pure = true },
        { key = "absorbs",    title = L["Absorbs"], attrs = { E.Absorbs } },
        -- (07/10) Of those two lists, the lines a talent of the player's own build answers for
        -- (Talents.lua). Only on the player's own line: the build of the others is not ours to read.
        { key = "talentDamage",  title = L["Your talents: direct damage"], talents = { E.DamageDone } },
        { key = "talentHealing", title = L["Your talents: direct healing"], talents = { E.HealingDone }, pure = true },
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
            local all, sum
            if spec.pure then
                all, sum = ns.Data.GetPureHealing(current.sessionType, current.guid, current.creatureId, ALL_SPELLS)
            else
                all, sum = ns.Data.GetSpellBreakdown(current.sessionType, spec.talents,
                    current.guid, current.creatureId, ALL_SPELLS)
            end
            local part
            spells, part = ns.Talents.Of(all)
            total = sum
            if sum and sum > 0 and part > 0 then share = math.floor(part / sum * 100 + 0.5) end
        end
    elseif spec.casts then
        spells, total, missed = CastRows(spec.casts)
    elseif spec.pure then
        spells, total = ns.Data.GetPureHealing(current.sessionType, current.guid, current.creatureId, MAX_PER_SECTION)
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
-- mantém o que temos"*, then *"falta as barras"*, then *"pode ser vista em combate"*.
--
-- What Details shows there was read (`class_damage.lua`, its `ToolTip_DamageDone`): the player's
-- spells, largest first, each a bar with its icon, its amount and its share. The idea is taken.
--
-- WHY IT IS A BOX OF OURS AND NOT THE GAME'S TOOLTIP. It began as `GameTooltip`, and that cannot
-- do the last two things asked:
--   * bars: the game's tooltip bars (`GameTooltip_AddStatusBar`) are a framed line of their own
--     between the text lines, not something behind a line;
--   * combat: in combat every number of the meter is a SECRET value (the client's own notes,
--     `DamageMeterDocumentation.lua`: `SecretWhenInCombat`), which may only be handed to a
--     widget -- `FontString:SetText`, `Texture:SetTexture`, `StatusBar:SetValue` take it,
--     `GameTooltip:AddDoubleLine` does not.
-- So the box is a frame with the game's tooltip border (`TooltipBackdropTemplate`) and the
-- game's tooltip fonts, with one status bar per spell -- the meter's own flat bar, in the
-- player's class colour.
--
-- IN COMBAT, WHAT THE GAME ALLOWS (same notes):
--   * the player's OWN spells: the list comes with secret ids and amounts. The name and the icon
--     are asked with the secret id (`C_Spell.GetSpellName` and `GetSpellTexture` take a secret
--     from an addon), the amount is written by the client, and the bar is the amount against
--     the largest, both handed over as they came. No share: that is a division, and a secret
--     cannot be divided. The order is the game's own.
--   * the spells of ANOTHER player: not at all. The row's identity is secret in combat, and the
--     call that lists the spells refuses a secret argument from an addon. The box says so.
local TIP = {
    WIDTH = 290, PAD = 10, ROW = 18, STEP = 19, HEAD = 18, TITLE = 20, GAP = 6,
    LIMITS = { 6, 4, 4 },          -- damage, healing, absorbs (as many as healing, at the user's word)
    REFRESH = 0.5,                 -- while the mouse stays on the row (the fight goes on)
}
Breakdown.TooltipGeometry = TIP
local tipFrame

local function TipRow(index)
    local f = tipFrame
    local row = f.rows[index]
    if row then return row end
    local skin = Skin()
    row = CreateFrame("Frame", nil, f)
    row:SetHeight(TIP.ROW)
    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetAllPoints()
    row.bar:SetStatusBarTexture(skin and skin.barTexture or "Interface\\Buttons\\WHITE8X8")
    row.bar:SetMinMaxValues(0, 1)
    row.text = CreateFrame("Frame", nil, row)
    row.text:SetAllPoints()
    row.text:SetFrameLevel(row.bar:GetFrameLevel() + 2)
    row.icon = row.text:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(TIP.ROW - 2, TIP.ROW - 2)
    row.icon:SetPoint("LEFT", 1, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.share = row.text:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    row.share:SetPoint("RIGHT", -4, 0)
    row.share:SetWidth(34)
    row.share:SetJustifyH("RIGHT")
    row.amount = row.text:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    row.amount:SetPoint("RIGHT", row.share, "LEFT", -4, 0)
    row.amount:SetWidth(56)
    row.amount:SetJustifyH("RIGHT")
    row.name = row.text:CreateFontString(nil, "OVERLAY", "GameTooltipTextSmall")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
    row.name:SetPoint("RIGHT", row.amount, "LEFT", -4, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    f.rows[index] = row
    return row
end

local function TipHead(index)
    local f = tipFrame
    local head = f.heads[index]
    if head then return head end
    head = CreateFrame("Frame", nil, f)
    head:SetHeight(TIP.HEAD)
    head.title = head:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    head.title:SetPoint("LEFT", 0, 0)
    head.total = head:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    head.total:SetPoint("RIGHT", -4, 0)
    f.heads[index] = head
    return head
end

local function CreateTip()
    if tipFrame then return tipFrame end
    local f = CreateFrame("Frame", ADDON .. "RowTooltip", UIParent, "TooltipBackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:SetWidth(TIP.WIDTH)
    f:Hide()
    f.title = f:CreateFontString(nil, "OVERLAY", "GameTooltipHeaderText")
    f.title:SetPoint("TOPLEFT", TIP.PAD, -TIP.PAD)
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameTooltipText")
    f.foot:SetWidth(TIP.WIDTH - TIP.PAD * 2)
    f.foot:SetJustifyH("LEFT")
    f.rows, f.heads = {}, {}
    -- The fight goes on while the mouse rests on the row: the box follows it.
    f:SetScript("OnUpdate", function(self, elapsed)
        self.wait = (self.wait or 0) + (elapsed or 0)
        if self.wait < TIP.REFRESH then return end
        self.wait = 0
        if self.source then pcall(Breakdown.FillTooltip) end
    end)
    tipFrame = f
    return f
end

---Writes a number of the meter on a font string: ours when it can be read, the client's own
---text when it is secret (`ns.Data.FormatSecretAmount`), the value itself as a last resort.
local function WriteAmount(fs, value)
    local text = ns.Data.FormatAmount(value)
    if text == nil and value ~= nil then
        text = ns.Data.FormatSecretAmount and ns.Data.FormatSecretAmount(value)
        if text == nil then text = value end
    end
    fs:SetText(text ~= nil and text or "")
end

---The spells of one metric, as the game lists them. nil when the game does not answer.
local function TipSpells(sessionType, attr, guid, creatureId)
    if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then return nil end
    local ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
        ns.Data.SessionValue(sessionType), attr, guid, creatureId)
    local spells = ok and type(container) == "table" and container.combatSpells or nil
    if type(spells) ~= "table" or #spells == 0 then return nil end
    -- A total that can be read and is nothing: no section. A secret one is shown as it is.
    local total = container.totalAmount
    if total ~= nil and not issecretvalue(total) and type(total) == "number" and total <= 0 then return nil end
    return spells, container
end

local lastTipLog = 0

---Fills the box for the row it is on. Returns whether any spell was listed.
function Breakdown.FillTooltip()
    local f = tipFrame
    if not (f and f.source) then return false end
    local source, sessionType = f.source, f.sessionType
    local isLocal = source.isLocalPlayer
    isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true
    local guid = source.sourceGUID
    if isLocal and UnitGUID then guid = UnitGUID("player") end
    local readable = guid ~= nil and not issecretvalue(guid)

    local name = source.name
    if isLocal and (name == nil or issecretvalue(name)) and UnitName then name = UnitName("player") end
    local r, g, b = ns.ClassColor(source.classFilename)
    f.title:SetText(name ~= nil and name or L["Player"])
    f.title:SetTextColor(r or 1, g or 1, b or 1)

    local skin = Skin()
    local k = skin and skin.barBrightness or 1
    local y = TIP.PAD + TIP.TITLE
    local rows, heads, secret = 0, 0, false
    if readable then
        local E = Enum.DamageMeterType
        local specs = { { L["Damage"], E.DamageDone }, { L["Healing"], E.HealingDone }, { L["Absorbs"], E.Absorbs } }
        for index, spec in ipairs(specs) do
            local spells, container = TipSpells(sessionType, spec[2], guid, source.sourceCreatureID)
            local title = spec[1]
            -- (!) HEALING WITHOUT THE SHIELDS (Data.GetPureHealing): the game's healing done
            -- carries them. Out of combat they are taken out; in combat the numbers are secret
            -- and cannot be subtracted, so the section is named for what it then holds.
            if spells and spec[2] == E.HealingDone then
                local first = spells[1].totalAmount
                if first ~= nil and not issecretvalue(first) then
                    local list, sum = ns.Data.GetPureHealing(sessionType, guid, source.sourceCreatureID, TIP.LIMITS[index])
                    if list then
                        spells, container = {}, { totalAmount = sum, maxAmount = list[1].amount }
                        for i, sp in ipairs(list) do spells[i] = { spellID = sp.spellID, totalAmount = sp.amount } end
                    else
                        spells = nil
                    end
                else
                    title = L["Healing and absorbs"]
                end
            end
            if spells then
                heads = heads + 1
                local head = TipHead(heads)
                head:ClearAllPoints()
                head:SetPoint("TOPLEFT", TIP.PAD, -y)
                head:SetPoint("RIGHT", f, "RIGHT", -TIP.PAD, 0)
                head.title:SetText(title)
                head.title:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
                WriteAmount(head.total, container.totalAmount)
                head.total:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
                head:Show()
                y = y + TIP.HEAD

                local total, top = container.totalAmount, container.maxAmount
                local totalReadable = total ~= nil and not issecretvalue(total) and type(total) == "number" and total > 0
                for i = 1, math.min(#spells, TIP.LIMITS[index]) do
                    local spell = spells[i]
                    local id, amount = spell.spellID, spell.totalAmount
                    rows = rows + 1
                    local row = TipRow(rows)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", TIP.PAD, -y)
                    row:SetPoint("RIGHT", f, "RIGHT", -TIP.PAD, 0)
                    -- The name and the icon are asked with the id as it came, secret or not.
                    local okN, spellName = pcall(C_Spell.GetSpellName, id)
                    local okT, texture = pcall(C_Spell.GetSpellTexture, id)
                    row.name:SetText(okN and spellName ~= nil and spellName or "?")
                    row.icon:SetTexture(okT and texture ~= nil and texture or 134400)
                    WriteAmount(row.amount, amount)
                    local amountReadable = amount ~= nil and not issecretvalue(amount) and type(amount) == "number"
                    if amountReadable and totalReadable then
                        row.share:SetText(format("%d%%", math.floor(amount / total * 100 + 0.5)))
                    else
                        row.share:SetText("")
                        secret = true
                    end
                    -- The bar: the amount against the largest, both handed over as they came.
                    local okB = pcall(function()
                        row.bar:SetMinMaxValues(0, top)
                        row.bar:SetValue(amount)
                    end)
                    if not okB then row.bar:SetMinMaxValues(0, 1); row.bar:SetValue(0) end
                    row.bar:SetStatusBarColor((r or 1) * k, (g or 1) * k, (b or 1) * k)
                    row:Show()
                    y = y + TIP.STEP
                end
                y = y + TIP.GAP
            end
        end
    end
    for i = rows + 1, #f.rows do f.rows[i]:Hide() end
    for i = heads + 1, #f.heads do f.heads[i]:Hide() end

    local combat = InCombatLockdown and InCombatLockdown() and true or false
    if rows > 0 then
        f.foot:SetText(L["Click: the full screen of this player"])
        f.foot:SetTextColor(GREEN_FONT_COLOR:GetRGB())
    elseif not readable then
        f.foot:SetText(L["In combat the game only lets your own spells be read."])
        f.foot:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    else
        f.foot:SetText(L["No spell to show yet."])
        f.foot:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
    end
    f.foot:ClearAllPoints()
    f.foot:SetPoint("TOPLEFT", TIP.PAD, -y)
    f:SetHeight(y + 30 + TIP.PAD)

    -- What the game gave in combat, for the diary: this path cannot be tried out of the game.
    if combat and ns.Log and ns.Log.Add then
        local now = GetTime and GetTime() or 0
        if now - lastTipLog >= 10 then
            lastTipLog = now
            ns.Log.Add("rowtip", { own = isLocal, readable = readable, rows = rows, secret = secret })
        end
    end
    return rows > 0
end

---The box of a row of the meter: what that player cast.
---@param owner Frame the row
---@param source table the row's source, as the meter gives it
---@return boolean shown
function Breakdown.Tooltip(owner, source, sessionType)
    if not (owner and source) then return false end
    local f = CreateTip()
    f.source, f.sessionType, f.owner, f.wait = source, sessionType, owner, 0
    -- Beside the row, on the side that has room (the same rule as the panel).
    f:ClearAllPoints()
    local right = owner.GetRight and owner:GetRight()
    local screen = UIParent and UIParent.GetWidth and UIParent:GetWidth()
    if type(right) == "number" and type(screen) == "number" and right + TIP.WIDTH + 8 > screen then
        f:SetPoint("TOPRIGHT", owner, "TOPLEFT", -4, 0)
    else
        f:SetPoint("TOPLEFT", owner, "TOPRIGHT", 4, 0)
    end
    Breakdown.FillTooltip()
    f:Show()
    return true
end

---Closes the box, when it is the one of this row (or of any, without a row given).
function Breakdown.HideTooltip(owner)
    if not tipFrame then return end
    if owner ~= nil and tipFrame.owner ~= owner then return end
    tipFrame.source, tipFrame.owner = nil, nil
    tipFrame:Hide()
end
function Breakdown.__tooltip() return tipFrame end

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
