-- RocketMeter | Minimap.lua
-- Botão de minimapa próprio, sem LibDBIcon: são ~60 linhas e evita embutir biblioteca.
-- Guarda a posição como ângulo, então continua no lugar em qualquer tamanho de minimapa.
local ADDON, ns = ...
local L = ns.L

local Minimap_ = {}
ns.Minimap = Minimap_

local RADIUS = 80
local button

local function UpdatePosition()
    if not button then return end
    local angle = math.rad(ns.db.minimap.angle or 200)
    button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function OnDragUpdate(self)
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local px, py = GetCursorPosition()
    px, py = px / scale, py / scale
    ns.db.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
    UpdatePosition()
end

function Minimap_.Create()
    if button then return button end

    button = CreateFrame("Button", ADDON .. "MinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", -1, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_MissileLarge_Red")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- LEFT CLICK OPENS THE OPTIONS (25/09). The user: *"quero que o clique esquerdo do mouse no
    -- icone do minimapa abra a config dele e não remova a janela de medição"*. Showing and hiding
    -- the meter moved to the right button (and stays on `/rm`), away from the everyday click.
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Window.Toggle()
        elseif IsShiftKeyDown() then
            ns.Scoreboard.Toggle()
        else
            ns.OpenOptions()
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cffff6a00Rocket|r Meter", 1, 1, 1)
        GameTooltip:AddLine(L["Left-click: options"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Shift-click: scoreboard of the last run"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Right-click: show or hide the meter"], 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Drag to move around the minimap."], 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    UpdatePosition()
    Minimap_.ApplyVisibility()
    return button
end

function Minimap_.ApplyVisibility()
    if not button then return end
    if ns.db.minimap.hide then
        button:Hide()
    else
        button:Show()
    end
end
