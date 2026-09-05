-- RocketMeter | Commands.lua
local ADDON, ns = ...
local L = ns.L

local commands = {}

commands[""] = function()
    ns.Window.Toggle()
end

commands["show"] = function()
    ns.Window.Show()
end

commands["hide"] = function()
    ns.Window.Hide()
end

commands["score"] = function()
    ns.Scoreboard.Toggle()
end

commands["columns"] = function()
    ns.Picker.Toggle()
end

commands["config"] = function()
    ns.OpenOptions()
end

commands["reset"] = function()
    ns.Data.ResetAll()
    ns.Window.Refresh(true)
    ns.Print(L["sessions cleared."])
end

commands["overall"] = function()
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
    local list = ns.Data.GetColumns()
    local index = tonumber(rest)
    if index and list[index] then
        ns.Window.ToggleColumn(list[index].key)
        ns.Print(L["column toggled:"] .. " " .. list[index].label)
        return
    end

    ns.Print(L["columns (type the number to toggle):"])
    for i, attr in ipairs(list) do
        local isOn = false
        for _, id in ipairs(ns.db.columns) do
            if id == attr.key then isOn = true break end
        end
        print(("  %d - %s%s|r"):format(i, isOn and "|cff33ff99" or "|cff808080", attr.label))
    end
end

commands["profile"] = function(rest)
    local arg = rest:lower():match("^%S*")
    if arg == "char" then
        ns.Profile.SetPerCharacter(true)
    elseif arg == "account" then
        ns.Profile.SetPerCharacter(false)
    elseif arg == "reset" then
        ns.Profile.Reset()
        ns.Print(L["settings restored to the defaults."])
    else
        ns.Print(ns.Profile.IsPerCharacter()
            and L["settings for this character only."]
            or L["settings shared by the account."])
        print("  /rm profile char|account|reset")
    end
end

commands["move"] = function(rest)
    local from, direction = rest:match("^(%d+)%s*(%S*)$")
    from = tonumber(from)
    if not from then
        ns.Print("/rm move <column> <left|right>")
        return
    end
    ns.Window.MoveColumn(from, direction == "right" and 1 or -1)
end

commands["help"] = function()
    ns.Print(L["version"] .. " " .. ns.version .. " — " .. L["commands:"])
    print("  /rm                             " .. L["opens or closes the window"])
    print("  /rm columns                     " .. L["opens the column panel"])
    print("  /rm col [n]                     " .. L["lists the columns or toggles one"])
    print("  /rm move <n> left|right         " .. L["moves a column left or right"])
    print("  /rm preset mplus|raid|damage    " .. L["switches the column preset"])
    print("  /rm score                       " .. L["opens the scoreboard of the last run"])
    print("  /rm overall                     " .. L["switches current fight / overall"])
    print("  /rm profile char|account|reset  " .. L["account-wide or per-character settings"])
    print("  /rm reset                       " .. L["clears the sessions"])
    print("  /rm config                      " .. L["opens the options"])
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
