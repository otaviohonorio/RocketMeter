-- RocketMeter | Commands.lua
local ADDON, ns = ...
local L = ns.L

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
    ns.Print(L["sessions cleared."])
end

commands["geral"] = function()
    ns.db.sessionType = ns.db.sessionType == 0 and 1 or 0
    ns.Window.Refresh(true)
    ns.Print(ns.db.sessionType == 0 and L["showing the current fight."] or L["showing the overall."])
end

commands["preset"] = function(rest)
    local presets = ns.Data.GetPresets()
    local key = rest:lower():match("^%S*")
    if presets[key] and ns.Window.ApplyPreset(key) then
        ns.Print(L["columns applied:"] .. " " .. presets[key].label)
        return
    end
    ns.Print(L["available presets:"])
    for name, preset in pairs(presets) do
        print("  /rm preset " .. name .. "  —  " .. preset.label)
    end
end

commands["col"] = function(rest)
    local list = ns.Data.GetAttributes()
    local index = tonumber(rest)
    if index and list[index] then
        ns.Window.ToggleColumn(list[index].id)
        ns.Print(L["column toggled:"] .. " " .. list[index].label)
        return
    end

    ns.Print(L["columns (type the number to toggle):"])
    for i, attr in ipairs(list) do
        local isOn = false
        for _, id in ipairs(ns.db.columns) do
            if id == attr.id then isOn = true break end
        end
        print(("  %d - %s%s|r"):format(i, isOn and "|cff33ff99" or "|cff808080", attr.label))
    end
end

commands["help"] = function()
    ns.Print(L["version"] .. " " .. ns.version .. " — " .. L["commands:"])
    print("  /rm                          " .. L["opens or closes the window"])
    print("  /rm col [n]                  " .. L["lists the columns or toggles one"])
    print("  /rm preset mplus|raid|dano   " .. L["switches the column preset"])
    print("  /rm score                    " .. L["opens the scoreboard of the last run"])
    print("  /rm geral                    " .. L["switches current fight / overall"])
    print("  /rm reset                    " .. L["clears the sessions"])
    print("  /rm config                   " .. L["opens the options"])
    print("  " .. L["(click a column header to sort by it)"])
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
