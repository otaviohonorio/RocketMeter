-- RocketMeter | Commands.lua
local ADDON, ns = ...

local commands = {}

commands[""] = function()
    ns.Window.Toggle()
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

commands["attr"] = function(rest)
    local list = ns.Data.GetAttributes()
    local wanted = tonumber(rest)
    if wanted and list[wanted] then
        ns.Window.SetAttribute(list[wanted].id)
        ns.Print("exibindo " .. list[wanted].label .. ".")
        return
    end
    ns.Print("atributos disponíveis:")
    for i, attr in ipairs(list) do
        print("  " .. i .. " - " .. attr.label)
    end
end

commands["help"] = function()
    ns.Print("versão " .. ns.version .. " — comandos:")
    print("  /rm            abre ou fecha a janela")
    print("  /rm attr [n]   lista ou escolhe o que medir")
    print("  /rm geral      alterna combate atual / geral")
    print("  /rm reset      zera as sessões")
    print("  /rm config     abre as opções")
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
