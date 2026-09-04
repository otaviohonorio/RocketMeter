-- RocketMeter | Window.lua
-- A janela. Tudo aqui é apresentação: recebe dados do Data.lua e desenha.
local ADDON, ns = ...

local Window = {}
ns.Window = Window

local ROW_HEIGHT = 20
local ROW_SPACING = 1
local HEADER_HEIGHT = 22
local BAR_TEXTURE = "Interface\\AddOns\\" .. ADDON .. "\\Media\\bar"  -- cai no padrão se não existir

local frame, rows
local dirty, throttle = false, 0

local function ClassColor(classFilename)
    local color = classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if color then
        return color.r, color.g, color.b
    end
    return 0.55, 0.55, 0.58
end

local function CreateRow(index, parent)
    local row = CreateFrame("StatusBar", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetStatusBarTexture(BAR_TEXTURE)
    if not row:GetStatusBarTexture() or not row:GetStatusBarTexture():GetTexture() then
        row:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    end
    row:SetMinMaxValues(0, 1)
    row:SetValue(0)

    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 1, 1, 0.05)

    row.left = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.left:SetPoint("LEFT", 6, 0)
    row.left:SetJustifyH("LEFT")

    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("RIGHT", -6, 0)
    row.right:SetJustifyH("RIGHT")

    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -(HEADER_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_SPACING)))
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, -(HEADER_HEIGHT + (index - 1) * (ROW_HEIGHT + ROW_SPACING)))
    return row
end

function Window.Create()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "BackdropTemplate")
    frame:SetSize(240, HEADER_HEIGHT + ns.db.rows * (ROW_HEIGHT + ROW_SPACING) + 6)
    frame:SetScale(ns.db.scale)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
    frame:SetBackdropBorderColor(0, 0, 0, 0.9)

    if ns.db.pos then
        frame:SetPoint(ns.db.pos.point, UIParent, ns.db.pos.relPoint, ns.db.pos.x, ns.db.pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
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
    frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then ns.OpenOptions() end
    end)

    -- Cabeçalho
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)

    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    header.bg:SetColorTexture(1, 0.42, 0, 0.75)

    header.title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.title:SetPoint("LEFT", 6, 0)
    header.title:SetTextColor(1, 1, 1)

    header.info = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header.info:SetPoint("RIGHT", -6, 0)
    header.info:SetTextColor(1, 1, 1)

    frame.header = header

    rows = {}
    for i = 1, ns.db.rows do
        rows[i] = CreateRow(i, frame)
    end

    -- Throttle: DAMAGE_METER_CURRENT_SESSION_UPDATED dispara muitas vezes por segundo.
    frame:SetScript("OnUpdate", function(_, elapsed)
        if not dirty then return end
        throttle = throttle + elapsed
        if throttle < 0.2 then return end
        throttle, dirty = 0, false
        Window.Draw()
    end)

    tinsert(UISpecialFrames, frame:GetName())
    return frame
end

function Window.Refresh(immediate)
    if not frame then return end
    if immediate then
        dirty, throttle = false, 0
        Window.Draw()
    else
        dirty = true
    end
end

function Window.Draw()
    if not frame or not frame:IsShown() then return end

    local session = ns.Data.GetSession(ns.db.sessionType, ns.db.attribute)
    local sources = session and session.combatSources or nil
    local total = session and session.totalAmount
    local maxAmount = session and session.maxAmount

    frame.header.title:SetText(ns.Data.GetAttributeLabel(ns.db.attribute))

    local duration = ns.Data.GetDuration(ns.db.sessionType)
    if duration and not issecretvalue(duration) then
        frame.header.info:SetText(SecondsToClock(duration))
    else
        frame.header.info:SetText("")
    end

    for i = 1, #rows do
        local row = rows[i]
        local source = sources and sources[i]

        if not source then
            row:Hide()
        else
            -- Barra: o widget aceita secret value. Nada de dividir por maxAmount no Lua.
            row:SetMinMaxValues(0, maxAmount or 1)
            row:SetValue(source.totalAmount or 0)
            row:SetStatusBarColor(ClassColor(source.classFilename))

            -- Nome pode ser secret em combate: SetText repassa e o motor renderiza.
            row.left:SetText(source.name)

            local amount = ns.Data.FormatAmount(source.totalAmount)
            if amount then
                local percent = ns.db.showPercent and ns.Data.FormatPercent(source.totalAmount, total)
                row.right:SetText(percent and (amount .. "  " .. percent) or amount)
            else
                -- Em combate: sem formatação possível, repassa o valor cru.
                row.right:SetText(source.totalAmount)
            end

            row:Show()
        end
    end
end

function Window.Toggle()
    if not frame then Window.Create() end
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
        Window.Refresh(true)
    end
end

function Window.SetAttribute(attributeId)
    ns.db.attribute = attributeId
    Window.Refresh(true)
end

function Window.ApplyScale()
    if frame then frame:SetScale(ns.db.scale) end
end
