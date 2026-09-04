-- RocketMeter | Commands.lua
local ADDON, ns = ...

local commands = {}

commands[""] = function()
    ns.Window.Toggle()
end

commands["score"] = function()
    ns.Scoreboard.Toggle()
end

commands["config"] = function()
    ns.OpenOptions()
end

commands["reset"] = function()
    ns.Data.ResetAll()
    ns.Window.Refresh(true)
    ns.Print("sessões zeradas.")
end

commands["geral"] = function()
    ns.db.sessionType = ns.db.sessionType == 0 and 1 or 0
    ns.Window.Refresh(true)
    ns.Print(ns.db.sessionType == 0 and "mostrando o combate atual." or "mostrando o geral.")
end

commands["preset"] = function(rest)
    local presets = ns.Data.GetPresets()
    local key = rest:lower():match("^%S*")
    if presets[key] and ns.Window.ApplyPreset(key) then
        ns.Print("colunas de " .. presets[key].label .. " aplicadas.")
        return
    end
    ns.Print("conjuntos disponíveis:")
    for name, preset in pairs(presets) do
        print("  /rm preset " .. name .. "  —  " .. preset.label)
    end
end

commands["col"] = function(rest)
    local list = ns.Data.GetAttributes()
    local index = tonumber(rest)
    if index and list[index] then
        ns.Window.ToggleColumn(list[index].id)
        ns.Print("coluna " .. list[index].label .. " alternada.")
        return
    end

    ns.Print("colunas (número liga/desliga):")
    for i, attr in ipairs(list) do
        local isOn = false
        for _, id in ipairs(ns.db.columns) do
            if id == attr.id then isOn = true break end
        end
        print(("  %d - %s%s|r"):format(i, isOn and "|cff33ff99" or "|cff808080", attr.label))
    end
end

commands["help"] = function()
    ns.Print("versão " .. ns.version .. " — comandos:")
    print("  /rm              abre ou fecha a janela")
    print("  /rm col [n]      lista as colunas ou liga/desliga uma")
    print("  /rm preset mplus|raid|dano   troca o conjunto de colunas")
    print("  /rm score        abre o placar da última corrida")
    print("  /rm geral        alterna combate atual / geral")
    print("  /rm reset        zera as sessões")
    print("  /rm config       abre as opções")
    print("  (clique num cabeçalho de coluna para ordenar por ela)")
end

SLASH_ROCKETMETER1 = "/rocketmeter"
SLASH_ROCKETMETER2 = "/rm"

SlashCmdList["ROCKETMETER"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    local handler = commands[cmd:lower()]
    if handler then
        handler(rest)
    else
        commands["help"]()
    end
end
