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
local MAX_PER_SECTION = 6

local frame, sections
local current

local function Skin()
    return ns.Skin
end

--------------------------------------------------------------------------------
local function SectionSpecs()
    local E = Enum.DamageMeterType
    return {
        { key = "damage",  title = L["Damage"],  attrs = { E.DamageDone } },
        { key = "healing", title = L["Healing"], attrs = { E.HealingDone, E.Absorbs } },
        { key = "control", title = L["Control"], attrs = { E.Interrupts, E.Dispels } },
    }
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

    local height = skin.rowHeight
    row:SetHeight(height)
    row:ClearAllPoints()
    local y = -(SECTION_TITLE + (index - 1) * (height + skin.rowSpacing))
    row:SetPoint("TOPLEFT", section, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, y)

    row.icon:SetSize(height, height)
    row.name:SetWidth(WIDTH - height - 172)

    ns.ApplyFont(row.name, -1, "")
    ns.ApplyFont(row.amount, -1, "")
    ns.ApplyFont(row.rate, -2, "")
    ns.ApplyFont(row.percent, -2, "")

    local bg = skin.rowBackground
    row.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    return row
end

---Desenha uma seção e devolve a altura ocupada.
local function DrawSection(section, spec)
    local skin = Skin()
    local spells, total = ns.Data.GetSpellBreakdown(current.sessionType, spec.attrs,
        current.guid, current.creatureId, MAX_PER_SECTION)

    section.title:SetText(spec.title)

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

            row.rate:SetText(ns.Data.FormatAmount(spell.perSecond) or "-")
            row.rate:SetTextColor(skin.dim[1], skin.dim[2], skin.dim[3])

            local share = total and total > 0 and (spell.amount / total * 100) or nil
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
    local height = SECTION_TITLE + used * (skin.rowHeight + skin.rowSpacing)
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

    ns.ApplyFont(frame.title, 0, "")
    ns.ApplyFont(frame.scope, -2, "")

    frame.title:SetText(current.name)
    frame.title:SetTextColor(ns.ClassColor(current.classFilename))

    frame.scope:SetText(current.sessionType == 0 and L["Current fight"] or L["Overall"])
    -- Claro: a arte do cabeçalho escurece para a direita, e texto escuro sumia justo ali.
    frame.scope:SetTextColor(0.82, 0.76, 0.56)

    ns.ApplyRowIcon(frame.icon, frame.iconClass, current.source)

    local offset = HEADER_HEIGHT + 4
    for _, spec in ipairs(SectionSpecs()) do
        local section = sections[spec.key]

        ns.ApplyFont(section.title, -1, "")
        ns.ApplyFont(section.empty, -2, "")
        section.title:SetTextColor(skin.gold[1], skin.gold[2], skin.gold[3])
        section.empty:SetText(L["nothing here"])

        section:ClearAllPoints()
        section:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -offset)
        section:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -offset)

        offset = offset + DrawSection(section, spec)
    end

    frame:SetHeight(offset + 4)
end

---Abre o detalhamento de um jogador.
function Breakdown.Show(source, sessionType, anchorTo)
    if not source then return end

    local guid = source.sourceGUID
    local readable = guid ~= nil and not issecretvalue(guid)

    local isLocal = source.isLocalPlayer
    isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true

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

function Breakdown.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Breakdown.Refresh()
    if Breakdown.IsShown() then
        Breakdown.Draw()
    end
end

function Breakdown.Hide()
    if frame then frame:Hide() end
end
