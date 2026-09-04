-- RocketMeter | Options.lua
-- O painel inteiro cabe numa tela: conjuntos prontos, uma caixa por coluna, três ajustes.
local ADDON, ns = ...

-- As colunas vivem numa lista (ns.db.columns), mas a Settings API trabalha com
-- campos de tabela. Este proxy expõe cada atributo como um booleano.
local columnProxy = setmetatable({}, {
    __index = function(_, key)
        local attributeId = tonumber(key)
        if not attributeId then return nil end
        for _, id in ipairs(ns.db.columns) do
            if id == attributeId then return true end
        end
        return false
    end,
    __newindex = function(_, key, value)
        local attributeId = tonumber(key)
        if not attributeId then return end
        local isOn = columnProxy[key]
        if value ~= isOn then
            ns.Window.ToggleColumn(attributeId)
        end
    end,
})

function ns.SetupOptions()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Rocket Meter")
    ns.category = category

    -- Conjuntos prontos ------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Conjuntos prontos"))

    local presets = ns.Data.GetPresets()
    local presetOrder = { "mplus", "raid", "dano" }

    local presetSetting = Settings.RegisterAddOnSetting(category, ADDON .. "_preset", "preset",
        ns.db, "string", "Aplicar conjunto", "")
    Settings.SetOnValueChangedCallback(ADDON .. "_preset", function(_, setting, value)
        if value ~= "" and ns.Window.ApplyPreset(value) then
            ns.Print("colunas de " .. presets[value].label .. " aplicadas.")
        end
    end)
    Settings.CreateDropdown(category, presetSetting, function()
        local container = Settings.CreateControlTextContainer()
        container:Add("", "—")
        for _, key in ipairs(presetOrder) do
            if presets[key] then
                container:Add(key, presets[key].label)
            end
        end
        return container:GetData()
    end, "Troca todas as colunas de uma vez.")

    -- Colunas ----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Colunas visíveis"))

    for _, attr in ipairs(ns.Data.GetAttributes()) do
        local key = tostring(attr.id)
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_col" .. key, key,
            columnProxy, "boolean", attr.label, false)
        Settings.CreateCheckbox(category, setting, "Mostra " .. attr.label .. " como coluna.")
    end

    -- Janela -----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Janela"))

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_autoScoreboard", "autoScoreboard",
            ns.db, "boolean", "Placar ao fim de M+ e raide", ns.defaults.autoScoreboard)
        Settings.CreateCheckbox(category, setting, "Abre sozinho o resumo da corrida quando ela termina.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_locked", "locked",
            ns.db, "boolean", "Travar posição", ns.defaults.locked)
        Settings.CreateCheckbox(category, setting, "Impede arrastar a janela sem querer.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_rows", "rows",
            ns.db, "number", "Linhas", ns.defaults.rows)
        Settings.SetOnValueChangedCallback(ADDON .. "_rows", function()
            ns.Window.Rebuild()
        end)
        Settings.CreateSlider(category, setting,
            Settings.CreateSliderOptions(3, 25, 1), "Quantos jogadores mostrar.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_scale", "scale",
            ns.db, "number", "Escala", ns.defaults.scale)
        Settings.SetOnValueChangedCallback(ADDON .. "_scale", function()
            ns.Window.ApplyScale()
        end)
        Settings.CreateSlider(category, setting,
            Settings.CreateSliderOptions(0.6, 2.0, 0.05), "Tamanho da janela.")
    end

    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if ns.category then
        Settings.OpenToCategory(ns.category:GetID())
    end
end
