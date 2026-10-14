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

    -- (!) THE GAME'S RING AND THE ICON, AT THE NUMBERS EVERY OTHER BUTTON USES (06/10). Reported
    -- with a screenshot: our drawing sat off-centre inside the gold ring. The button had the ring
    -- at 53 and the icon at 19, shifted (-1, 1) -- numbers of the OLD clients. On retail the
    -- common minimap-button library (its `WOW_PROJECT_MAINLINE`
    -- branch) draws the ring at 50 from the top left, the game's dark disc at 24 and the icon at
    -- 18, both at the button's very centre. With the game's square icons nobody saw the 1.5
    -- points; with a ring of our own inside the gold one, it shows.
    local disc = button:CreateTexture(nil, "BACKGROUND")
    disc:SetSize(24, 24)
    disc:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    disc:SetPoint("CENTER", button, "CENTER")

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", button, "CENTER")
    icon:SetTexture(ns.LOGO_MINIMAP)
    button.icon, button.disc = icon, disc
    icon:SetTexCoord(0, 1, 0, 1)
    icon:SetMask("Interface\\CharacterFrame\\TempPortraitAlphaMask")

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border = border

    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    -- LEFT CLICK OPENS THE OPTIONS (25/09). The user: *"quero que o clique esquerdo do mouse no
    -- icone do minimapa abra a config dele e não remova a janela de medição"*. Hiding the meter
    -- went to Shift-click -- *"geralmente ninguem esconde medidor de dano"* -- (and stays on `/rm`),
    -- and the scoreboard to the right button.
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            ns.Scoreboard.Toggle()
        elseif IsShiftKeyDown() then
            ns.Window.Toggle()
        else
            ns.OpenOptions()
        end
    end)

    button:SetScript("OnEnter", function(self)
        -- (!) THE MINIMAP TOOLTIP OF EVERY ROCKET ADDON (13/10, the visual identity): the user, *"os ícones do
        -- minimap não precisam do texto arraste para mover (...) cada um com um tempo de escrita, um com texto
        -- verde, outro cinza (...) vamos padronizar"*. The game's tooltip helpers, in one order: the title;
        -- the state, white; a blank line; one green line per action ("Click: ...", "Right-click: ...",
        -- "Shift-click: ..."), the verb in the infinitive. No "drag to move".
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip_SetTitle(GameTooltip, ns.TITLE)
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
        GameTooltip_AddInstructionLine(GameTooltip, L["Click: open the options"])
        GameTooltip_AddInstructionLine(GameTooltip, L["Shift-click: show or hide the meter"])
        GameTooltip_AddInstructionLine(GameTooltip, L["Right-click: open the scoreboard of the last run"])
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
