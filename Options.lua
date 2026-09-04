-- RocketMeter | Options.lua
local ADDON, ns = ...

function ns.SetupOptions()
    local category = Settings.RegisterVerticalLayoutCategory("Rocket Meter")
    ns.category = category

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_locked", "locked",
            ns.db, "boolean", "Travar a janela", ns.defaults.locked)
        Settings.CreateCheckbox(category, setting, "Impede arrastar a janela sem querer.")
    end

    do
        local setting = Settings.RegisterAddOnSetting(category, ADDON .. "_showPercent", "showPercent",
            ns.db, "boolean", "Mostrar percentual", ns.defaults.showPercent)
        Settings.CreateCheckbox(category, setting, "Exibe a fatia de cada um do total (só fora de combate).")
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
