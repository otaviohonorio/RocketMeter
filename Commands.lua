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

commands["details"] = function()
    ns.Breakdown.Hide()
end

commands["score"] = function(rest)
    local arg = rest and rest:lower():match("^%S*")

    if arg == "demo" then
        ns.Scoreboard.ShowDemo()
    elseif arg == "mplus" or arg == "m+" or arg == "key" then
        ns.Scoreboard.ShowLast("mplus")
    elseif arg == "raid" then
        ns.Scoreboard.ShowLast("raid")
    else
        ns.Scoreboard.Toggle()
    end
end

-- Instrumentation, not convenience. `SetAtlas` with a name that does not exist fails SILENTLY: the
-- texture does not draw and nothing warns. Seeing a name in use does not prove the client knows it.
-- This command settles the whole category with one line instead of a test round per
-- broken name.
commands["atlas"] = function(rest)
    local wanted = rest and rest:match("^%S+")
    local list = wanted and { wanted } or ns.SCOREBOARD_ATLASES

    ns.Print(format(L["checking %d atlas name(s):"], #list))
    local missing = 0
    for _, name in ipairs(list) do
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
        if info then
            print(format("  |cff33ff99ok|r    %s  (%dx%d)",
                name, info.width or 0, info.height or 0))
        else
            missing = missing + 1
            print(format("  |cffff5555--|r    %s", name))
        end
    end
    if missing > 0 then
        ns.Print(format(L["%d name(s) do not exist on this client."], missing))
    end
end

commands["columns"] = function()
    ns.OpenOptions()
end

commands["config"] = function()
    ns.OpenOptions()
end

commands["reset"] = function(rest)
    -- "/rm reset now" pula a confirmacao.
    ns.Data.RequestReset(rest and rest:lower():match("^now"))
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

    -- ⚑ A FIXED ORDER, and not `pairs`'s. It varies between runs, so the same list came out in
    -- a different order at each `/rm preset` -- for the player it is only odd; for `sabotar.py`, which
    -- matches the harness's output by text, it was a suite that changed its result without the code changing.
    local nomes = {}
    for name in pairs(presets) do nomes[#nomes + 1] = name end
    table.sort(nomes)

    for _, name in ipairs(nomes) do
        print("  /rm preset " .. name .. "  —  " .. presets[name].label)
    end
end

commands["col"] = function(rest)
    -- ITEMS, the same list as the settings screen. Numbering here by the catalogue and there by the items
    -- would give two different "number 4" for the same person.
    local list = ns.Data.GetColumnItems()
    local index = tonumber(rest)
    if index and list[index] then
        ns.Window.ToggleColumn(list[index].key)
        ns.Print(L["column toggled:"] .. " " .. list[index].label)
        return
    end

    ns.Print(L["columns (type the number to toggle):"])
    for i, item in ipairs(list) do
        local isOn = false
        for _, id in ipairs(ns.db.columns) do
            for _, key in ipairs(item.keys) do
                if id == key then isOn = true end
            end
        end
        print(("  %d - %s%s|r"):format(i, isOn and "|cff33ff99" or "|cff808080", item.label))
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
    direction = direction and direction:lower()
    -- (14/10) The number is the place ON SCREEN, which is not the `/rm col` list (that one has
    -- every item, on or off): the places are listed here, and a move needs its direction (without
    -- one it went left).
    if not from or (direction ~= "left" and direction ~= "right") then
        ns.Print("/rm move <n> left|right")
        for i, group in ipairs(ns.Data.GroupColumns(ns.db.columns)) do
            local names = {}
            for _, key in ipairs(group.keys) do
                local def = ns.Data.GetColumn(key)
                names[#names + 1] = def and (def.label or key) or key
            end
            print(("  %d - %s"):format(i, table.concat(names, " / ")))
        end
        return
    end
    ns.Window.MoveColumn(from, direction == "right" and 1 or -1)
end

commands["log"] = function(rest)
    -- So existe fora do pacote (ver Core.lua).
    if not ns.Log.enabled then
        ns.Print(L["the log only exists in development builds."])
        return
    end
    local arg = rest and rest:lower():match("^%S*")
    if arg == "clear" then
        ns.Log.Clear()
        ns.Log.ClearErrors()
        ns.Print(L["log cleared."])
        return
    end

    -- THE ERRORS FIRST, and in the chat. Reading the file needs `/reload` and leaving the game; the
    -- count here answers "did anything happen?" without any of that.
    ns.PrintErrorSummary()

    ns.Log.Snapshot("requested by the user")
    ns.Print(format(L["snapshot saved (%d entries). Type /reload so the file is written."],
        ns.Log.Count()))
    print("  WTF\\Account\\<account>\\SavedVariables\\RocketMeter.lua")
end

commands["debug"] = function()
    ns.Print("--- diagnostics ---")
    print("  C_DamageMeter available:", tostring(ns.Data.IsAvailable()))
    print("  in combat:", tostring(InCombatLockdown()))
    print("  session:", ns.db.sessionType == 0 and "current" or "overall",
        "| sorting by:", tostring(ns.db.sortBy))

    local def = ns.Data.GetColumn(ns.db.sortBy)
    if not def then
        print("  |cffff5555invalid sort column:|r", tostring(ns.db.sortBy))
        return
    end

    print("  paths:", ns.Data.DescribeSources(ns.db.sessionType, def.attr))
    print("  secret formatter:", ns.Data.GetFormatterName())
    print("  rows clickable:", tostring(ns.Window.RowsAreClickable()))
    print("  session types:", ns.Data.DescribeSessionEnum())

    -- Varredura na tela: qual tipo tem o grupo.
    local def2 = ns.Data.GetColumn(ns.db.sortBy)
    for candidate = 0, 3 do
        local probe = C_DamageMeter.GetCombatSessionFromType(candidate, def2.attr)
        local list = probe and probe.combatSources
        print(format("  type %d -> %d source(s)", candidate, list and #list or 0))
    end

    local erro = ns.Window.GetLastError()
    if erro then
        print("  |cffff5555last draw error:|r", tostring(erro))
    end

    local session = ns.Data.GetSession(ns.db.sessionType, def.attr)
    if not session then
        print("  |cffff5555the API returned no session|r")
        return
    end

    local sources = session.combatSources
    print("  sources in session:", sources and #sources or 0)
    print("  duration:", tostring(ns.Data.GetDuration(ns.db.sessionType)))

    local first = sources and sources[1]
    if first then
        print("  first source — name secret?", tostring(issecretvalue(first.name)),
            "| total secret?", tostring(issecretvalue(first.totalAmount)))
        local amount = ns.Data.FormatAmount(first.totalAmount)
        print("  readable value:", amount or "(secret)")
    end
end

-- Instrumentation, for the same reason as `/rm atlas`: `FROM_GAME` depends on the client's globals,
-- and a global that does not exist warns nothing -- the label just stays in English, which cannot be
-- told from "that is right". One line of output settles it.
-- Instrumentation of WHO GETS INTO THE LIST. The report: in a followers dungeon the healer heals and does not
-- show in the meter. The loop that builds the rows filters no one -- it lists what the session of the
-- SORTED METRIC returns -- so there are two possible causes and they are told apart by reading:
--
--   A. the healer is not in the DAMAGE session (he deals no damage), and the list comes from the metric
--      the window is sorted by. Showing when sorted by Healing confirms it;
--   B. an NPC ally does not get into `combatSources` at all -- and in a followers dungeon the
--      healer IS an NPC. Not showing in ANY metric confirms it.
--
-- The structure has fields the addon did not use and that answer it right away: `sourceDisplayType`
-- (`None`/`Ally`/`Enemy`), `sourceCreatureID` (only an NPC has it) and `classification`
-- (`DamageMeterDocumentation.lua:199-212`). The NPC ally shows as `Ally` with no class -- and that is
-- how the native meter draws it, with an ally's colour instead of a class colour
-- (`DamageMeterEntry.lua:365-369`).
commands["fontes"] = function()
    if not ns.Data.IsAvailable() then
        ns.Print("|cffff5555C_DamageMeter não está disponível agora.|r")
        return
    end

    local function Texto(v)
        if v == nil then return "nil" end
        if issecretvalue(v) then return "|cffff5555secret|r" end
        return tostring(v)
    end

    local tipoFonte = {}
    if Enum and Enum.DamageMeterSourceDisplayType then
        for nome, valor in pairs(Enum.DamageMeterSourceDisplayType) do
            tipoFonte[valor] = nome
        end
    end

    -- ALL the metrics, and not only the one on screen: it is the comparison between them that answers.
    for _, coluna in ipairs({ "damage", "healing", "damagetaken", "interrupts", "deaths" }) do
        local def = ns.Data.GetColumn(coluna)
        if def then
            local sessao = ns.Data.GetSession(0, def.attr)
            local fontes = sessao and sessao.combatSources or {}

            ns.Print(("|cffffd100%s|r: %d ator(es)"):format(coluna, #fontes))
            for i, fonte in ipairs(fontes) do
                -- `recap` comes in here because of the report of the 19 deaths: in the deaths metric it is
                -- what tells a death from any entry, and `recap=0` is what does NOT count.
                print(("   %d. %-14s %-10s cria=%-8s tipo=%-6s recap=%-6s local=%-5s total=%s"):format(
                    i,
                    Texto(fonte.name),
                    Texto(fonte.classFilename),
                    Texto(fonte.sourceCreatureID),
                    tipoFonte[fonte.sourceDisplayType] or Texto(fonte.sourceDisplayType),
                    Texto(fonte.deathRecapID),
                    Texto(fonte.isLocalPlayer),
                    Texto(fonte.totalAmount)))
            end
        end
    end

    ns.Print("se o curador aparece em |cffffd100healing|r e não em |cffffd100damage|r,")
    print("   a lista da janela sai da métrica ORDENADA: ordene por Cura para vê-lo.")
    print("   se não aparece em NENHUMA, aliado NPC não entra na API e não há o que fazer.")
end

commands["i18n"] = function()
    local report = ns.CheckGameStrings()
    ns.Print(format(L["locale %s, %d game label(s):"], GetLocale(), #report))

    local broken = 0
    for _, row in ipairs(report) do
        if row.text then
            print(format("  |cff33ff99ok|r    %-46s %s", row.tag, row.text))
        else
            broken = broken + 1
            print(format("  |cffff5555--|r    %-46s %s  (%s)", row.tag, row.key, row.why))
        end
    end

    if broken > 0 then
        ns.Print(format(L["%d game label(s) are not usable here."], broken))
    end
end

commands["help"] = function()
    ns.Print(L["version"] .. " " .. ns.version .. " — " .. L["commands:"])
    print("  /rm                             " .. L["opens or closes the window"])
    print("  /rm show | hide                 " .. L["shows or hides the meter"])
    print("  /rm config                      " .. L["opens or closes the settings"])
    print("  /rm col [n]                     " .. L["lists the columns or toggles one"])
    print("  /rm move <n> left|right         " .. L["moves a column left or right"])
    print("  /rm preset mplus|raid|damage    " .. L["switches the column preset"])
    print("  /rm score                       " .. L["opens the scoreboard of the last run"])
    print("  /rm score mplus                 " .. L["opens the last Mythic+ scoreboard"])
    print("  /rm score raid                  " .. L["opens the last raid scoreboard"])
    print("  /rm score demo                  " .. L["opens the scoreboard with invented data"])
    print("  /rm overall                     " .. L["switches current fight / overall"])
    print("  /rm profile char|account|reset  " .. L["account-wide or per-character settings"])
    print("  /rm reset                       " .. L["clears the sessions"])
    -- (14/10) The development tools only in a development build: their output is for us (some of
    -- it in Portuguese whatever the language), and the package has no diary to go with them.
    if ns.Log.enabled then
        print("  /rm atlas [name]                " .. L["checks whether the panel art exists"])
        print("  /rm i18n                        " .. L["checks the labels taken from the game"])
        print("  /rm fontes                      " .. L["lists who the API reports in each metric"])
        print("  /rm debug                       " .. L["prints what the API is returning"])
        print("  /rm log [clear]                 " .. L["records a diagnostic snapshot"])
    end
    print("  " .. L["(click a column header to sort by it)"])
end

SLASH_ROCKETMETER1 = "/rocketmeter"
SLASH_ROCKETMETER2 = "/rm"

local DEV_ONLY = { atlas = true, i18n = true, fontes = true, debug = true }

SlashCmdList["ROCKETMETER"] = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    local handler = commands[cmd:lower()]
    if DEV_ONLY[cmd:lower()] and not ns.Log.enabled then handler = nil end
    if handler then
        handler(rest)
    else
        commands["help"]()
    end
end
