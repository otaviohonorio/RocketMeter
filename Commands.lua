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

-- Instrumentação, não conveniência. `SetAtlas` com nome inexistente falha em SILÊNCIO: a
-- textura não desenha e nada avisa. A pesquisa que embasou o placar novo confirmou os nomes
-- lendo addons instalados, mas addon referenciar um nome não prova que o cliente o conhece.
-- Este comando resolve a categoria inteira com uma linha em vez de uma rodada de teste por
-- nome quebrado.
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

commands["log"] = function(rest)
    local arg = rest and rest:lower():match("^%S*")
    if arg == "clear" then
        ns.Log.Clear()
        ns.Print(L["log cleared."])
        return
    end

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

-- Instrumentacao, pelo mesmo motivo do `/rm atlas`: `FROM_GAME` depende de globais do cliente,
-- e global que nao existe nao avisa nada — o rotulo apenas continua em ingles, o que e
-- indistinguivel de "esta certo assim". Uma linha de saida encerra a duvida.
-- Instrumentacao de QUEM ENTRA NA LISTA. Relato: numa masmorra de seguidores o healer cura e nao
-- aparece no medidor. O laco que monta as linhas nao filtra ninguem -- ele lista o que a sessao da
-- METRICA ORDENADA devolve -- entao ha duas causas possiveis e elas se distinguem lendo:
--
--   A. o healer nao esta na sessao de DANO (ele nao causa dano), e a lista sai da metrica pela
--      qual a janela esta ordenada. Aparecer ordenando por Cura confirma;
--   B. aliado NPC nao entra em `combatSources` de jeito nenhum -- e num calabouco de seguidores o
--      healer E um NPC. Nao aparecer em NENHUMA metrica confirma.
--
-- A estrutura tem campos que o addon nao usava e que respondem isso de cara: `sourceDisplayType`
-- (`None`/`Ally`/`Enemy`), `sourceCreatureID` (so NPC tem) e `classification`
-- (`DamageMeterDocumentation.lua:199-212`). O aliado NPC aparece como `Ally` sem classe -- e assim
-- que o medidor nativo o desenha, com cor de aliado em vez de cor de classe
-- (`DamageMeterEntry.lua:365-369`).
commands["fontes"] = function()
    if not ns.Data.IsAvailable() then
        ns.Print("|cffff5555C_DamageMeter nao esta disponivel agora.|r")
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

    -- TODAS as metricas, e nao so a que esta na tela: e a comparacao entre elas que responde.
    for _, coluna in ipairs({ "damage", "healing", "damagetaken", "interrupts", "deaths" }) do
        local def = ns.Data.GetColumn(coluna)
        if def then
            local sessao = ns.Data.GetSession(0, def.attr)
            local fontes = sessao and sessao.combatSources or {}

            ns.Print(("|cffffd100%s|r: %d ator(es)"):format(coluna, #fontes))
            for i, fonte in ipairs(fontes) do
                print(("   %d. %-14s %-10s cria=%-8s tipo=%-6s local=%-5s total=%s"):format(
                    i,
                    Texto(fonte.name),
                    Texto(fonte.classFilename),
                    Texto(fonte.sourceCreatureID),
                    tipoFonte[fonte.sourceDisplayType] or Texto(fonte.sourceDisplayType),
                    Texto(fonte.isLocalPlayer),
                    Texto(fonte.totalAmount)))
            end
        end
    end

    ns.Print("se o healer aparece em |cffffd100healing|r e nao em |cffffd100damage|r,")
    print("   a lista da janela sai da metrica ORDENADA -- ordene por Cura para ve-lo.")
    print("   se nao aparece em NENHUMA, aliado NPC nao entra na API e nao ha o que fazer.")
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
    print("  /rm columns                     " .. L["opens the column panel"])
    print("  /rm col [n]                     " .. L["lists the columns or toggles one"])
    print("  /rm move <n> left|right         " .. L["moves a column left or right"])
    print("  /rm preset mplus|raid|damage    " .. L["switches the column preset"])
    print("  /rm score                       " .. L["opens the scoreboard of the last run"])
    print("  /rm score mplus                 " .. L["opens the last Mythic+ scoreboard"])
    print("  /rm score raid                  " .. L["opens the last raid scoreboard"])
    print("  /rm score demo                  " .. L["opens the scoreboard with invented data"])
    print("  /rm atlas [name]                " .. L["checks whether the panel art exists"])
    print("  /rm i18n                        " .. L["checks the labels taken from the game"])
    print("  /rm overall                     " .. L["switches current fight / overall"])
    print("  /rm profile char|account|reset  " .. L["account-wide or per-character settings"])
    print("  /rm reset                       " .. L["clears the sessions"])
    print("  /rm config                      " .. L["opens the options"])
    print("  /rm fontes                      " .. L["lists who the API reports in each metric"])
    print("  /rm debug                       " .. L["prints what the API is returning"])
    print("  /rm log [clear]                 " .. L["records a diagnostic snapshot"])
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
