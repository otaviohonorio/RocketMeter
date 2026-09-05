-- RocketMeter | Options.lua
--
-- **Um único lugar para configurar**: o painel de opções do próprio jogo.
-- Não existe painel próprio — ter dois lugares para mexer na mesma coisa confunde e obriga a
-- manter dois códigos em sincronia. A engrenagem da janela abre este painel.
--
-- Campos que não são um valor simples do banco (colunas, perfil, minimapa, opacidades aninhadas)
-- entram pela Settings API através de tabelas-proxy com __index/__newindex.
local ADDON, ns = ...
local L = ns.L

-- Fontes que existem no cliente, sem precisar de biblioteca de mídia.
local FONTS = {
    { path = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
    { path = "Fonts\\ARIALN.TTF",   label = "Arial Narrow" },
    { path = "Fonts\\2002.TTF",     label = "2002" },
    { path = "Fonts\\2002B.TTF",    label = "2002 Bold" },
    { path = "Fonts\\skurri.TTF",   label = "Skurri" },
    { path = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
}

--------------------------------------------------------------------------------
-- Proxies: expõem para a Settings API coisas que não são campo simples do banco
--------------------------------------------------------------------------------
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

local profileProxy = setmetatable({}, {
    __index = function(_, key)
        if key == "perCharacter" then return ns.Profile.IsPerCharacter() end
        return nil
    end,
    __newindex = function(_, key, value)
        if key == "perCharacter" then ns.Profile.SetPerCharacter(value and true or false) end
    end,
})

--------------------------------------------------------------------------------
-- Helpers para encurtar o registro de cada controle
--------------------------------------------------------------------------------
local category, layout

local function Section(title)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
end

local function Check(key, label, tooltip, store, onChange)
    local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key,
        store or ns.db, "boolean", label, ns.defaults[key])
    if onChange then
        Settings.SetOnValueChangedCallback(ADDON .. "_" .. key, onChange)
    end
    Settings.CreateCheckbox(category, setting, tooltip)
    return setting
end

local function Slider(key, label, tooltip, minimum, maximum, step, onChange)
    local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key,
        ns.db, "number", label, ns.defaults[key])
    if onChange then
        Settings.SetOnValueChangedCallback(ADDON .. "_" .. key, onChange)
    end
    Settings.CreateSlider(category, setting,
        Settings.CreateSliderOptions(minimum, maximum, step), tooltip)
    return setting
end

local function Dropdown(key, label, tooltip, options, onChange)
    local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_" .. key, key,
        ns.db, "string", label, ns.defaults[key])
    if onChange then
        Settings.SetOnValueChangedCallback(ADDON .. "_" .. key, onChange)
    end
    Settings.CreateDropdown(category, setting, function()
        local container = Settings.CreateControlTextContainer()
        for _, option in ipairs(options) do
            container:Add(option.value, option.label)
        end
        return container:GetData()
    end, tooltip)
    return setting
end

--------------------------------------------------------------------------------
function ns.SetupOptions()
    local rebuild = function() ns.Window.Rebuild() end
    local repaint = function() ns.Window.Refresh(true) end

    category, layout = Settings.RegisterVerticalLayoutCategory("Rocket Meter")
    ns.category = category

    ----------------------------------------------------------------- Colunas
    Section(L["Visible columns"])

    for _, column in ipairs(ns.Data.GetColumns()) do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_col_" .. column.key,
            column.key, columnProxy, "boolean", column.label, false)
        Settings.CreateCheckbox(category, setting, column.label .. " — " .. L["Show as a column."])
    end

    --------------------------------------------------------------- Aparência
    Section(L["Appearance"])

    Dropdown("font", L["Font"], L["Typeface used by the window."], (function()
        local options = {}
        for _, entry in ipairs(FONTS) do
            options[#options + 1] = { value = entry.path, label = entry.label }
        end
        return options
    end)(), rebuild)

    Slider("fontSize", L["Font size"], L["Size of the text in the rows."], 8, 20, 1, rebuild)

    Dropdown("fontOutline", L["Text outline"],
        L["Outline keeps the text readable over any bar colour."], {
            { value = "OUTLINE", label = L["Thin"] },
            { value = "THICKOUTLINE", label = L["Thick"] },
            { value = "none", label = L["None"] },
        }, rebuild)

    Dropdown("barTexture", L["Bar texture"], L["Look of the filled bar."], (function()
        local options = {}
        for _, entry in ipairs(ns.BAR_TEXTURES) do
            options[#options + 1] = { value = entry.key, label = entry.label }
        end
        return options
    end)(), rebuild)

    Slider("barBrightness", L["Bar brightness"],
        L["Lower values darken the bar so the white text reads better."], 0.3, 1.0, 0.05, repaint)
    Slider("barAlpha", L["Bar opacity"], L["Opacity of the coloured fill."], 0.2, 1.0, 0.05, repaint)
    Slider("windowAlpha", L["Window opacity"], L["Opacity of the window background."], 0.2, 1.0, 0.05, rebuild)

    Slider("rowHeight", L["Row height"], L["Thickness of each bar."], 14, 32, 1, rebuild)
    Slider("columnWidth", L["Column width"], L["Width reserved for each metric."], 40, 100, 2, function()
        ns.db.width = nil
        ns.Window.Rebuild()
    end)

    Dropdown("rowIcon", L["Row icon"],
        L["Specialization says more than class: who heals, who tanks."], {
            { value = "spec", label = L["Specialization"] },
            { value = "class", label = L["Class"] },
        }, rebuild)

    Check("roundIcons", L["Round icons"], L["Circular icon, like the built-in meter."], nil, rebuild)
    Check("rowBorder", L["Row border"], L["Separates one bar from the next."], nil, rebuild)
    Check("showColumnHeader", L["Column header"], L["Strip with the column names."], nil, rebuild)
    Check("highlightBest", L["Highlight the leader of each column"],
        L["Gold for what is good to lead, red for damage taken and deaths."], nil, repaint)

    ------------------------------------------------------------------ Janela
    Section(L["Window"])

    Check("locked", L["Lock position"], L["Prevents dragging the window by accident."], nil, nil)
    Check("autoHeight", L["Fit height to the rows"],
        L["The window shrinks to the number of players with data."], nil, rebuild)
    Slider("rows", L["Rows"], L["How many players to show."], 3, 25, 1, rebuild)
    Slider("scale", L["Scale"], L["Window size."], 0.6, 2.0, 0.05, function()
        ns.Window.ApplyScale()
    end)
    Check("combatOnly", L["Show only in combat"],
        L["The window appears when the fight starts and hides a few seconds after it ends."],
        nil, function() ns.Window.ApplyVisibility() end)
    Check("autoScoreboard", L["Scoreboard at the end of M+ and raid"],
        L["Opens the run summary automatically when it ends."], nil, nil)

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_minimap", "show",
            minimapProxy, "boolean", L["Minimap button"], true)
        Settings.CreateCheckbox(category, setting, L["Shows the Rocket Meter button on the minimap."])
    end

    ------------------------------------------------------------------ Perfil
    Section(L["Profile"])

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_perCharacter", "perCharacter",
            profileProxy, "boolean", L["Settings for this character only"], false)
        Settings.CreateCheckbox(category, setting,
            L["Off: every character shares the same setup. On: this character keeps its own."])
    end

    Settings.RegisterAddOnCategory(category)
end

function ns.OpenOptions()
    if ns.category then
        Settings.OpenToCategory(ns.category:GetID())
    end
end
