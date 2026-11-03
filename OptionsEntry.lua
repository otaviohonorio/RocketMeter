-- RocketMeter | OptionsEntry.lua
-- The game's Options > AddOns list only points to the addon's own window: the settings live there, never in the
-- game's panel (user, 03/11/2026: "não queria ter as configurações dos addons no menu opções aba addons (...) nessa
-- tela em opções addons, só abre a janela com as configurações do addon"). The button's label is the game's own
-- word (SETTINGS), so it reads right in every language with no translation of ours.
-- The game's panel is not closed from here: closing it from addon code would commit its settings from tainted code.
-- The window is raised instead (both sit in the HIGH strata).
local ADDON, ns = ...

local function Register(open)
    local name = ns.TITLE:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(ns.TITLE)
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetText(SETTINGS)
    local label = button:GetFontString()
    button:SetSize(math.max(160, (label and label:GetStringWidth() or 0) + 40), 22)
    button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    button:SetScript("OnClick", open)
    local category = Settings.RegisterCanvasLayoutCategory(panel, name)
    Settings.RegisterAddOnCategory(category)
    ns.optionsEntry = category
    ns.optionsEntryOpen = open
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event)
    if event ~= "PLAYER_LOGIN" then return end
    self:UnregisterAllEvents()
    Register(function()
        local f = _G.RocketMeterPicker
        if not (f and f:IsShown()) then ns.OpenOptions() end
        f = _G.RocketMeterPicker
        if f then f:Raise() end
    end)
end)
