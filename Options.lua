-- RocketMeter | Options.lua
-- O painel inteiro cabe numa tela: conjuntos prontos, uma caixa por coluna, três ajustes.
local ADDON, ns = ...
local L = ns.L

-- As colunas vivem numa lista (ns.db.columns), mas a Settings API trabalha com
-- campos de tabela. Este proxy expõe cada atributo como um booleano.
local columnProxy = setmetatable({}, {
    __index = function(_, key)
        for _, id in ipairs(ns.db.columns) do
            if id == key then return true end
        end
        return false
    end,
    __newindex = function(_, key, value)
        local isOn = columnProxy[key]
        if value ~= isOn then
            ns.Window.ToggleColumn(key)
        end
    end,
})

-- Fontes que existem no cliente, sem precisar de biblioteca de mídia.
local FONTS = {
    { path = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
    { path = "Fonts\\ARIALN.TTF",   label = "Arial Narrow" },
    { path = "Fonts\\2002.TTF",     label = "2002" },
    { path = "Fonts\\2002B.TTF",    label = "2002 Bold" },
    { path = "Fonts\\skurri.TTF",   label = "Skurri" },
    { path = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
}

-- O botão de minimapa mora em ns.db.minimap.hide; a Settings API quer um campo direto.
local minimapProxy = setmetatable({}, {
    __index = function(_, key)
        if key == "show" then return not ns.db.minimap.hide end
        return nil
    end,
    __newindex = function(_, key, value)
        if key == "show" then
            ns.db.minimap.hide = not value
            ns.Minimap.ApplyVisibility()
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

    for _, attr in ipairs(ns.Data.GetColumns()) do
        local key = attr.key
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_col" .. key, key,
            columnProxy, "boolean", attr.label, false)
        Settings.CreateCheckbox(category, setting, attr.label .. " — " .. L["Show as a column."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_minimap", "show",
            minimapProxy, "boolean", L["Minimap button"], true)
        Settings.CreateCheckbox(category, setting, L["Shows the Rocket Meter button on the minimap."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_combatOnly", "combatOnly",
            ns.db, "boolean", L["Show only in combat"], ns.defaults.combatOnly)
        Settings.SetOnValueChangedCallback(ADDON .. "_combatOnly", function()
            ns.Window.ApplyVisibility()
        end)
        Settings.CreateCheckbox(category, setting,
            L["The window appears when the fight starts and hides a few seconds after it ends."])
    end

    -- Perfil -----------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Profile"]))

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_perCharacter", "perCharacter",
            profileProxy, "boolean", L["Settings for this character only"], false)
        Settings.CreateCheckbox(category, setting,
            L["Off: every character shares the same setup. On: this character keeps its own."])
    end

    -- Aparência ---------------------------------------------------------------
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(L["Appearance"]))

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_font", "font",
            ns.db, "string", L["Font"], FONTS[1].path)
        Settings.SetOnValueChangedCallback(ADDON .. "_font", function()
            ns.Window.Rebuild()
        end)
        Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, font in ipairs(FONTS) do
                container:Add(font.path, font.label)
            end
            return container:GetData()
        end, L["Typeface used by the window."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_fontSize", "fontSize",
            ns.db, "number", L["Font size"], ns.defaults.fontSize)
        Settings.SetOnValueChangedCallback(ADDON .. "_fontSize", function()
            ns.Window.Rebuild()
        end)
        Settings.CreateSlider(category, setting,
            Settings.CreateSliderOptions(8, 20, 1), L["Size of the text in the rows."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_rowHeight", "rowHeight",
            ns.db, "number", L["Row height"], ns.defaults.rowHeight)
        Settings.SetOnValueChangedCallback(ADDON .. "_rowHeight", function()
            ns.Window.Rebuild()
        end)
        Settings.CreateSlider(category, setting,
            Settings.CreateSliderOptions(14, 32, 1), L["Thickness of each bar."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_columnWidth", "columnWidth",
            ns.db, "number", L["Column width"], ns.defaults.columnWidth)
        Settings.SetOnValueChangedCallback(ADDON .. "_columnWidth", function()
            ns.db.width = nil
            ns.Window.Rebuild()
        end)
        Settings.CreateSlider(category, setting,
            Settings.CreateSliderOptions(40, 100, 2), L["Width reserved for each metric."])
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_rowIcon", "rowIcon",
            ns.db, "string", L["Row icon"], ns.defaults.rowIcon)
        Settings.SetOnValueChangedCallback(ADDON .. "_rowIcon", function()
            ns.Window.Rebuild()
        end)
        Settings.CreateDropdown(category, setting, function()
            local container = Settings.CreateControlTextContainer()
            container:Add("spec", L["Specialization"])
            container:Add("class", L["Class"])
            return container:GetData()
        end, L["Specialization says more than class: who heals, who tanks."])
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
