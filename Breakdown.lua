-- RocketMeter | Breakdown.lua
--
-- O detalhamento de um jogador: o que ele fez, magia por magia.
--
-- No Details isso é um tooltip que aparece ao passar o mouse e some ao tirar; aqui é um painel
-- **aberto por clique**, que fica onde está até ser fechado — dá para ler com calma, comparar e
-- rolar. E mostra as três frentes de uma vez (dano, cura, controle), em vez de só a métrica da
-- janela em que se passou o mouse.
local ADDON, ns = ...
local L = ns.L

local Breakdown = {}
ns.Breakdown = Breakdown

local WIDTH = 340
local ROW_HEIGHT = 20
local SECTION_GAP = 10
local SECTION_HEADER = 18
local TOP = 44
local BOTTOM = 10
local MAX_PER_SECTION = 6

local frame, sections
local current            -- { guid, creatureId, name, classFilename, sessionType }

--------------------------------------------------------------------------------
-- Quais seções e o que cada uma agrega
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
local function BuildSpellRow(section, index)
    local row = section.rows[index]
    if not row then
        row = CreateFrame("Frame", nil, section)
        row:SetHeight(ROW_HEIGHT)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetPoint("TOPLEFT")
        row.bar:SetPoint("BOTTOMLEFT")
        row.bar:SetColorTexture(1, 1, 1, 0.10)

        row.icon = row:CreateTexture(nil, "OVERLAY")
        row.icon:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
        row.icon:SetPoint("LEFT", 3, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row.percent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.percent:SetPoint("RIGHT", -6, 0)
        row.percent:SetWidth(42)
        row.percent:SetJustifyH("RIGHT")

        row.rate = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rate:SetPoint("RIGHT", row.percent, "LEFT", -6, 0)
        row.rate:SetWidth(52)
        row.rate:SetJustifyH("RIGHT")

        row.amount = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.amount:SetPoint("RIGHT", row.rate, "LEFT", -6, 0)
        row.amount:SetWidth(56)
        row.amount:SetJustifyH("RIGHT")

        row:SetPoint("TOPLEFT", section, "TOPLEFT", 0, -(SECTION_HEADER + (index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", section, "TOPRIGHT", 0, -(SECTION_HEADER + (index - 1) * ROW_HEIGHT))
        section.rows[index] = row
    end

    ns.ApplyFont(row.name, -1, "")
    ns.ApplyFont(row.amount, -1, "")
    ns.ApplyFont(row.rate, -2, "")
    ns.ApplyFont(row.percent, -2, "")

    row.bg:SetColorTexture(0, 0, 0, index % 2 == 0 and 0.25 or 0.40)
    return row
end

---Desenha uma seção e devolve a altura que ela ocupou.
local function DrawSection(section, spec)
    local spells, total = ns.Data.GetSpellBreakdown(current.sessionType, spec.attrs,
        current.guid, current.creatureId, MAX_PER_SECTION)

    section.title:SetText(spec.title)

    if not spells or #spells == 0 then
        section.empty:Show()
        for _, row in pairs(section.rows) do row:Hide() end
        section:SetHeight(SECTION_HEADER + ROW_HEIGHT)
        return SECTION_HEADER + ROW_HEIGHT + SECTION_GAP
    end

    section.empty:Hide()

    local maximum = spells[1] and spells[1].amount or 1
    for i = 1, MAX_PER_SECTION do
        local row = BuildSpellRow(section, i)
        local spell = spells[i]

        if not spell then
            row:Hide()
        else
            local info = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spell.spellID)
            if not info and C_Spell and C_Spell.RequestLoadSpellData then
                -- Dado assíncrono: pede e desenha o que dá agora; o refresh seguinte completa.
                C_Spell.RequestLoadSpellData(spell.spellID)
            end

            row.icon:SetTexture(info and info.iconID or 134400)
            row.name:SetText(info and info.name or ("#" .. tostring(spell.spellID)))
            row.name:SetTextColor(0.92, 0.92, 0.94)

            row.amount:SetText(ns.Data.FormatAmount(spell.amount) or "-")
            row.amount:SetTextColor(1, 0.88, 0.62)

            row.rate:SetText(ns.Data.FormatAmount(spell.perSecond) or "-")
            row.rate:SetTextColor(0.78, 0.79, 0.82)

            local share = total and total > 0 and (spell.amount / total * 100) or nil
            row.percent:SetText(share and format("%.1f%%", share) or "-")
            row.percent:SetTextColor(0.72, 0.73, 0.76)

            -- Barra proporcional ao maior da seção, atrás do texto.
            local fraction = maximum > 0 and (spell.amount / maximum) or 0
            row.bar:SetWidth(math.max(1, (WIDTH - 24) * fraction))

            row:Show()
        end
    end

    local used = math.min(#spells, MAX_PER_SECTION)
    section:SetHeight(SECTION_HEADER + used * ROW_HEIGHT)
    return SECTION_HEADER + used * ROW_HEIGHT + SECTION_GAP
end

--------------------------------------------------------------------------------
local function CreatePanel()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Breakdown", UIParent, "BackdropTemplate")
    frame:SetSize(WIDTH, 400)
    frame:SetFrameStrata("DIALOG")
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
    frame:SetBackdropColor(0.04, 0.04, 0.05, 0.94)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()

    -- Cabeçalho com a mesma arte da janela principal.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(24)

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    local info = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo("ui-damagemeters-header-bar")
    if info and (info.file or info.filename) then
        header.bg:SetTexture(info.file or info.filename)
        local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
        local t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
        local w, h = r - l, b - t
        header.bg:SetTexCoord(l + w * 0.045, l + w * 0.965, t + h * (4 / 60), t + h * (56 / 60))
    else
        header.bg:SetColorTexture(0.13, 0.11, 0.07, 0.95)
    end

    -- Duas texturas, como nas linhas da janela: uma para o ícone de especialização e outra
    -- para o de classe (que precisa de texCoord). Passar a mesma nas duas pontas fazia a
    -- função mostrá-la e escondê-la em seguida.
    frame.icon = header:CreateTexture(nil, "OVERLAY")
    frame.icon:SetSize(18, 18)
    frame.icon:SetPoint("LEFT", 5, 0)

    frame.iconClass = header:CreateTexture(nil, "OVERLAY")
    frame.iconClass:SetSize(18, 18)
    frame.iconClass:SetPoint("LEFT", 5, 0)
    frame.iconClass:Hide()

    frame.title = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 5, 0)

    frame.close = CreateFrame("Button", nil, header)
    frame.close:SetSize(14, 14)
    frame.close:SetPoint("RIGHT", -5, 0)
    frame.close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    frame.close:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    frame.subtitle:SetPoint("TOPLEFT", 12, -28)
    frame.subtitle:SetTextColor(0.7, 0.71, 0.74)

    -- Seções
    sections = {}
    for _, spec in ipairs(SectionSpecs()) do
        local section = CreateFrame("Frame", nil, frame)
        section:SetPoint("LEFT", 12, 0)
        section:SetPoint("RIGHT", -12, 0)
        section.rows = {}

        section.title = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        section.title:SetPoint("TOPLEFT", 0, -2)
        section.title:SetTextColor(1, 0.82, 0)

        section.line = section:CreateTexture(nil, "ARTWORK")
        section.line:SetPoint("TOPLEFT", 0, -SECTION_HEADER + 3)
        section.line:SetPoint("TOPRIGHT", 0, -SECTION_HEADER + 3)
        section.line:SetHeight(1)
        section.line:SetColorTexture(1, 0.82, 0, 0.25)

        section.empty = section:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        section.empty:SetPoint("TOPLEFT", 2, -SECTION_HEADER - 3)
        section.empty:SetTextColor(0.5, 0.5, 0.53)
        section.empty:SetText(L["nothing here"])

        sections[spec.key] = section
    end

    return frame
end

--------------------------------------------------------------------------------
function Breakdown.Draw()
    if not frame or not current then return end

    -- Fonte primeiro, texto depois: FontString sem fonte responde "Font not set" no SetText.
    ns.ApplyFont(frame.title, 1, "")
    ns.ApplyFont(frame.subtitle, -2, "")

    frame.title:SetText(current.name)
    frame.title:SetTextColor(ns.ClassColor(current.classFilename))

    local scope = current.sessionType == 0 and L["Current fight"] or L["Overall"]
    frame.subtitle:SetText(scope)

    ns.ApplyRowIcon(frame.icon, frame.iconClass, current.source)

    local offset = TOP
    for _, spec in ipairs(SectionSpecs()) do
        local section = sections[spec.key]
        ns.ApplyFont(section.title, 0, "")
        ns.ApplyFont(section.empty, -2, "")

        section:ClearAllPoints()
        section:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -offset)
        section:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -offset)

        offset = offset + DrawSection(section, spec)
    end

    frame:SetHeight(offset + BOTTOM)
end

---Abre o detalhamento de um jogador. `source` é a linha clicada.
function Breakdown.Show(source, sessionType, anchorTo)
    if not source then return end

    local guid = source.sourceGUID
    local readable = guid ~= nil and not issecretvalue(guid)

    -- Em combate o GUID é secret e a API recusa recebê-lo de volta. Para a própria linha
    -- ainda dá: `UnitGUID("player")` é legível e vale como identificação.
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

    -- Onde cabe: à direita da janela se houver espaço, à esquerda se não houver.
    --
    -- Ancorar sempre à direita colocava o painel **fora da tela** quando a janela está
    -- encostada na borda — e o sintoma era "clico e não acontece nada", porque o painel abria
    -- num lugar invisível.
    frame:ClearAllPoints()
    local placed = false

    if anchorTo and anchorTo.GetRight and UIParent and UIParent.GetWidth then
        local right = anchorTo:GetRight()
        local screen = UIParent:GetWidth()
        if type(right) == "number" and type(screen) == "number" then
            if right + WIDTH + 8 <= screen then
                frame:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 8, 0)
            else
                frame:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", -8, 0)
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

---Atualiza junto com a janela, se estiver aberto.
function Breakdown.Refresh()
    if Breakdown.IsShown() then
        Breakdown.Draw()
    end
end

function Breakdown.Hide()
    if frame then frame:Hide() end
end
