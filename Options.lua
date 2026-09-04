-- RocketMeter | Options.lua
-- O painel inteiro cabe numa tela: conjuntos prontos, uma caixa por coluna, três ajustes.
local ADDON, ns = ...
local L = ns.L

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

-- A opção de perfil não é um campo do banco: liga e desliga o próprio banco ativo.
local profileProxy = setmetatable({}, {
    __index = function(_, key)
        if key == "perCharacter" then return ns.Profile.IsPerCharacter() end
        return nil
    end,
    __newindex = function(_, key, value)
        if key == "perCharacter" then ns.Profile.SetPerCharacter(value and true or false) end
    end,
})

function ns.SetupOptions()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Rocket Meter")
    ns.category = category

    -- Conjuntos prontos ------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Presets"]))

    local presets = ns.Data.GetPresets()
    local presetOrder = { "mplus", "raid", "damage" }

    local presetSetting = Settings.RegisterAddOnSetting(category, ADDON .. "_preset", "preset",
        ns.db, "string", L["Apply preset"], "")
    Settings.SetOnValueChangedCallback(ADDON .. "_preset", function(_, setting, value)
        if value ~= "" and ns.Window.ApplyPreset(value) then
            ns.Print(L["columns applied:"] .. " " .. presets[value].label)
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
    end, L["Changes every column at once."])

    -- Colunas ----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Visible columns"]))

    for _, attr in ipairs(ns.Data.GetAttributes()) do
        local key = tostring(attr.id)
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_col" .. key, key,
            columnProxy, "boolean", attr.label, false)
        Settings.CreateCheckbox(category, setting, attr.label .. " — " .. L["Show as a column."])
    end

    -- Perfil -----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Profile"]))

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_perCharacter", "perCharacter",
            profileProxy, "boolean", L["Settings for this character only"], false)
        Settings.CreateCheckbox(category, setting,
            L["Off: every character shares the same setup. On: this character keeps its own."])
    end

    -- Janela -----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Window"]))

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_autoScoreboard", "autoScoreboard",
            ns.db, "boolean", L["Scoreboard at the end of M+ and raid"], ns.defaults.autoScoreboard)
        Settings.CreateCheckbox(category, setting, L["Opens the run summary automatically when it ends."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_locked", "locked",
            ns.db, "boolean", L["Lock position"], ns.defaults.locked)
        Settings.CreateCheckbox(category, setting, L["Prevents dragging the window by accident."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_rows", "rows",
            ns.db, "number", L["Rows"], ns.defaults.rows)
        Settings.SetOnValueChangedCallback(ADDON .. "_rows", function()
            ns.Window.Rebuild()
        end)
        Settings.CreateSlider(category, setting,
            Settings.CreateSliderOptions(3, 25, 1), L["How many players to show."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_scale", "scale",
            ns.db, "number", L["Scale"], ns.defaults.scale)
        Settings.SetOnValueChangedCallback(ADDON .. "_scale", function()
            ns.Window.ApplyScale()
        end)
        Settings.CreateSlider(category, setting,
            Settings.CreateSliderOptions(0.6, 2.0, 0.05), L["Window size."])
    end

    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if ns.category then
        Settings.OpenToCategory(ns.category:GetID())
    end
end
