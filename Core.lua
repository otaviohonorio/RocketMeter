-- RocketMeter | Core.lua
local ADDON, ns = ...

-- (!) THE ADDON'S OWN ICON (06/10/2026). The three addons had the game's icons (two of them the
-- SAME one, so the list of addons showed them alike). The art is ours and ships in `Textures/`:
-- the rocket of the three addons with this addon's badge. One file serves every place: the
-- addon list (`## IconTexture`), the minimap button (masked round) and the window's portrait.
ns.LOGO = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Logo.png"
-- The minimap button is some 20 points wide: there the rocket would be a smudge, so it takes
-- the BADGE alone, large (06/10: "no icone do minimap tem que ficar apenas o redondo que fica
-- no canto sem o foguete, pq e muito pequeno pra ver qual e").
ns.LOGO_MINIMAP = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\Minimap.png"
local L = ns.L

ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "0.0.0"

ns.defaults = {
    -- columns/sortBy use Enum.DamageMeterType, resolved at PLAYER_LOGIN (the Enum does not
    -- exist yet when the files load). The default: the Mythic+ set.
    columns = nil,
    sortBy = nil,
    sessionType = 0,      -- 0 = the current session; 1 = overall

    -- THE VIEW FOLLOWS THE COMBAT: in combat, the current fight; out of it, the overall. **On by
    -- default**, by request -- and the default is right because the two views answer different
    -- questions at different moments. During the fight the only question is "how am I doing NOW";
    -- once it is over, the question becomes "how did the run go so far", and switching that by hand at every
    -- pull is work the machine does better.
    --
    -- Switching by hand still works (`/rm overall` and the click on the header); what the option
    -- guarantees is where the view goes back at the NEXT combat transition.
    autoSession = true,
    sortDesc = true,      -- maior primeiro
    rows = 5,                 -- visible rows; the handle changes it
    scale = 1.0,
    font = nil,               -- caminho da fonte; nil = a padrao (ns.FONT_CHOICES[1])
    -- THREE independent texts: the rows' body, the title and the column header. Each with its own
    -- size, outline and shadow -- changing one cannot change the others, which was the
    -- rejection of the single body. Limits and the reason for each in `Window.lua`
    -- (FONT_SIZE_MIN/MAX); the defaults sit in `ROLE_DEFAULTS`, their single source.
    --
    -- `nil` here on purpose: `Profile.EnsureRuntimeDefaults` builds the table, inheriting the
    -- old keys of whoever already had saved settings.
    text = nil,

    -- THE ROW'S TWO DISTANCES, configurable by request (09/09/2026), with a print and rectangles
    -- pointing at both: *"são das distância entre colunas e entre valores nas colunas
    -- mescladas"*. The defaults are the numbers he gave.
    --
    --   `groupGap`   the white space BETWEEN metric families (Damage+DPS | Healing+HPS | Interr | Deaths)
    --   `totalWidth` the TOTAL column's width, which is what governs the distance between the two
    --                values of a double column -- each one is anchored at one end of the bar, so
    --                bringing the two closer is shortening the bar, not touching a spacing
    --
    -- ⚑ The units are game pixels, and the print of 09/09 came out 1:1: the gap measured on it (10 px)
    -- was exactly the code's `GROUP_GAP`. Measuring on screen and typing here works.
    groupGap = 8,
    totalWidth = 84,
    width = nil,              -- width chosen with the handle; nil = the columns' minimum
    -- (14/10) Twelve keys that nothing read went away (the skin is constants, Window.lua): row
    -- height, column width, row icon, bar texture, row border, window and bar alpha, round icons,
    -- value format, column header, bar brightness, auto height. Saved values of them are ignored.
    highlightBest = true,     -- highlights who leads each column
    locked = false,
    shown = true,             -- the window comes back as the user left it
    combatOnly = false,       -- only shows in combat
    hideDelay = 5,            -- seconds to hide after the fight, in the mode above
    minimap = { hide = false, angle = 200 },

    -- The player's realm ("-Tichondrius") beside the name. **Off by default**: it eats the
    -- column's width and the name is what turns into an ellipsis. Whoever plays cross-realm turns it on in
    -- `/rm columns`.
    showRealm = false,

    -- (19/10) The specialization icon in the rows (meter, breakdown, scoreboard): "square" (the
    -- game's meter, the default) or "round" (the user's option). Not the old `roundIcons`, which
    -- nothing read since 14/10: a saved value of it would flip nobody's icons now.
    iconShape = "square",
    -- (26/10) the interrupts' clock beside the interrupts column (Kicks.lua): on by default
    kickClock = true,

    -- Does the end-of-run panel open by itself? Two keys, not one: whoever does Mythic+ every
    -- night may want the summary there and not at every raid boss, and vice versa. The old key
    -- `autoScoreboard` is still read once, so as not to turn off the panel of whoever had already
    -- chosen (see `Profile.MigrateScoreboard`).
    --
    -- ⚑ RAID IS BORN OFF (request of 11/09: *"o placar da raid por padrão pode deixar
    -- desabilitado"*). The lopsidedness has a reason of use: a Mythic+ run ends ONCE, and the
    -- summary is its close; a raid night has one boss after another, and the panel opening at
    -- each one becomes a nuisance in the middle of progression.
    autoScoreboardMPlus = true,
    autoScoreboardRaid = false,

    -- (20/10) The game's combat log on by itself inside an instance, for Warcraft Logs (MyRun.CombatLogByPlace).
    -- ON by default, the user's choice: *"Ligada"*.
    combatLog = true,

    pos = nil,
}

-- THE LOG IS A DEVELOPMENT TOOL, AND IT DOES NOT GO IN THE PACKAGE. The user's rule (23/09):
-- *"quando forem publicados não devem gerar os logs, por que vai ficar consumindo espaço e disco
-- do usuário, apenas aqui para desenvolvimento"*. `Log.lua` and `RocketMeterLogDB` sit in
-- `#@debug@` in the .toc, which the packager removes from EVERY build (alpha included), and the `.pkgmeta`
-- takes the file out of the zip. The meter was the one that wrote most: a picture at every combat.
--
-- This stand-in is what the player gets: every call answers nothing, so the calls to the
-- log spread over the addon need no guard. In development `Log.lua`, loaded
-- after this file, swaps it for the real one.
ns.Log = setmetatable({ enabled = false }, {
    __index = function() return function() end end,
})

-- the name on screen, the same in every Rocket addon (the minimap tooltip, 13/10)
ns.TITLE = "|cffff6a00Rocket|r Meter"

function ns.Print(...)
    print(ns.TITLE .. ":", ...)
end

--------------------------------------------------------------------------------
-- Fila de combate
--------------------------------------------------------------------------------
local queue = {}

function ns.RunWhenSafe(fn)
    if InCombatLockdown() then
        queue[#queue + 1] = fn
    else
        fn()
    end
end

local function FlushQueue()
    -- (14/10) Emptied BEFORE running, and each one in its own pcall: an error in one used to
    -- stop the rest of the end of combat and stay in the queue, to fail again at every fight.
    local pending = queue
    queue = {}
    for i = 1, #pending do
        local ok, err = pcall(pending[i])
        if not ok then geterrorhandler()(err) end
    end
end

--------------------------------------------------------------------------------
-- Eventos
--------------------------------------------------------------------------------
local handlers = {}

function handlers:ADDON_LOADED(addon)
    if addon ~= ADDON then return end

    -- The profile decides whether the settings come from the account or from this character.
    ns.Profile.Init()
    ns.Log.Init()
    -- Casts.lua is a NEW file in the .toc: nil until the client restarts (see RunCall).
    if ns.Casts and ns.Casts.Init then ns.Casts.Init() end
    if ns.MyRun and ns.MyRun.Init then ns.MyRun.Init() end
    -- (26/10) Stats.lua is a NEW file too: nil until the client restarts
    if ns.Stats and ns.Stats.Init then ns.Stats.Init() end
    -- (26/10) Kicks.lua, the interrupts' clock: a NEW file too
    if ns.Kicks and ns.Kicks.Init then ns.Kicks.Init() end
end

function handlers:PLAYER_LOGIN()
    -- The default columns depend on Enum, which only exists with the client loaded.
    ns.Profile.EnsureRuntimeDefaults()

    if not ns.Data.IsAvailable() then
        ns.Print(L["the native meter (C_DamageMeter) is not available on this client."])
        return
    end

    ns.Window.Create()
    ns.Minimap.Create()
    ns.SetupOptions()

    -- The saved view may be the one of the combat before the `/reload`. Applying the rule at login is
    -- what keeps the window from opening on "Current combat" standing still out of combat -- a state the
    -- option exists exactly to prevent.
    ns.Window.ApplyAutoSession()

    ns.Window.ApplyVisibility()
end

-- The data of the session under way changed (it fires a lot during combat).
function handlers:DAMAGE_METER_CURRENT_SESSION_UPDATED()
    ns.Window.Refresh()
end

-- A recorded session changed (end of combat, a new segment).
function handlers:DAMAGE_METER_COMBAT_SESSION_UPDATED()
    ns.Window.Refresh(true)
end

function handlers:DAMAGE_METER_RESET()
    ns.Window.Refresh(true)
end

--------------------------------------------------------------------------------
-- Recording the run and the end-of-content scoreboard
--------------------------------------------------------------------------------
-- `Run.lua` is a NEW file, and a new file in the `.toc` only comes in after going out to the
-- character screen -- `/reload` is not enough. Between updating the addon and restarting the client, `ns.Run`
-- is nil, and a raw `ns.Run.OnCombatStart()` would bring down `PLAYER_REGEN_DISABLED` at EVERY FIGHT,
-- taking the window's refresh with it. The whole addon would look broken because of a
-- file that has not loaded yet. `Window.lua` already uses this guard for the same reason.
local function RunCall(method, ...)
    local run = ns.Run
    if not run or not run[method] then return end
    local ok, err = pcall(run[method], ...)
    if not ok then ns.Print("Run." .. method .. ": " .. tostring(err)) end
end

function handlers:CHALLENGE_MODE_START()
    -- Recording the timeline does not depend on `autoScoreboard`: whoever turns off the automatic
    -- panel can still open it later with `/rm score`, and then the footer needs data.
    RunCall("Start")

    -- And it asks for the others' keystone at the start of the key, not at the end: the answer travels through the
    -- addon channel and takes an instant. Asking at capture time would be asking too late -- the same timing
    -- mistake that left the loot column empty.
    --
    -- ⚑ AND IT SUBSCRIBES TO THE CHANGE NOTICE, which is what makes the scoreboard get it right by itself later: each one's NEW
    -- keystone only exists when he opens the chest, and that is when the lib broadcasts.
    if ns.Party then
        if ns.Party.RequestKeystones then pcall(ns.Party.RequestKeystones) end
        if ns.Party.WatchKeystones then pcall(ns.Party.WatchKeystones) end
    end
end

function handlers:CHALLENGE_MODE_RESET()
    RunCall("Start")    -- redoing the key starts the run again from zero
end

function handlers:CHALLENGE_MODE_DEATH_COUNT_UPDATED()
    RunCall("OnDeathCountUpdated")
end

-- Entering the world covers the two sides that were missing:
--   * `/reload` in the middle of the key -- `CHALLENGE_MODE_START` has already gone by and the recording would never
--     turn on; `Resume` turns it back on and recovers the zero instant from the world timer (or marks
--     the run as partial and silences the footer, instead of showing a marker out of place);
--   * leaving the dungeon without completing it -- nothing disarmed the recording, and it would keep noting
--     the open world's fights as if they were the run's.
function handlers:PLAYER_ENTERING_WORLD()
    local active
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        active = ok and mapID and mapID ~= 0
    end

    if active then
        RunCall("Resume")
    else
        RunCall("Stop")
    end
end

function handlers:CHALLENGE_MODE_COMPLETED()
    -- WHEN the scoreboard opens, measured (26/09): *"o scoreboard final dele demora um pouco para
    -- aparecer"*, and nothing saved could say where the time went -- the 1.5 s below, or the wait
    -- for the end of combat (`RunWhenSafe`). Scoreboard.lua logs the other two instants.
    ns.scoreboardClock = GetTime and GetTime() or 0
    ns.Log.Add("placar", { fase = "fim da chave", emCombate = InCombatLockdown() and true or false })
    RunCall("Stop")
    -- The same: always records, shows according to the preference.
    -- A short wait: the session is still being closed when the event fires.
    C_Timer.After(1.5, function()
        ns.Scoreboard.OnChallengeCompleted()
    end)
end

function handlers:ENCOUNTER_END(encounterID, encounterName, difficultyID, groupSize, success)
    -- Inside a run, every boss becomes a marker on the timeline -- including when the
    -- automatic scoreboard is off.
    RunCall("OnEncounterEnd", encounterName, success)

    if success ~= 1 and success ~= true then return end
    if not IsInRaid() then return end   -- in M+ CHALLENGE_MODE_COMPLETED rules

    -- The capture happens even with the automatic panel off: "see the last raid
    -- scoreboard" only works if the run was recorded when it happened. What decides whether the
    -- window shows is `autoScoreboard`, in there.
    C_Timer.After(1, function()
        ns.Scoreboard.OnEncounterEnd(encounterName, difficultyID)
    end)
end

-- Leaving combat the values stop being secret: a full refresh is worth it.
function handlers:PLAYER_REGEN_ENABLED()
    FlushQueue()
    ns.Window.Refresh(true)
    ns.Window.OnCombatEnd()
    ns.Log.OnCombatEnd()
    RunCall("OnCombatEnd")
end

function handlers:PLAYER_REGEN_DISABLED()
    ns.Window.OnCombatStart()
    ns.Window.Refresh(true)
    ns.Log.OnCombatStart()
    RunCall("OnCombatStart")
end

local frame = CreateFrame("Frame", ADDON .. "EventFrame")
for event in pairs(handlers) do
    frame:RegisterEvent(event)
end
frame:SetScript("OnEvent", function(self, event, ...)
    handlers[event](self, ...)
end)

ns.frame = frame

function RocketMeter_OnCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        ns.OpenOptions()
    else
        ns.Window.Toggle()
    end
end


-- (25/10) DARK EVERYWHERE (the workspace rules, visual identity: the user chose the app's look as the reference and,
-- asked, "escuro em tudo"): a window's body wears the Specialization tab's dark art (spec-background), as the
-- RocketLab's tabs. Over a template's panel stone (ButtonFrameTemplate's or DefaultPanelTemplate's `Bg`, tiled): a
-- texture of its own at the stone's place, and the stone hidden -- one texture tiled and then given an atlas shows the
-- whole atlas file (RocketLab, 13/10). `stone`: the template's stone to cover (its `Bg`, said by the caller: a frame
-- without one answers nil in the game and a function in the harness); none (a panel on TooltipBorderBackdropTemplate,
-- the game's tooltip border with an empty centre): the art 3 points in from the frame's edges, inside the border.
function ns.DarkBody(frame, alpha, stone)
    local art = frame.__dark
    if not art then
        art = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
        art:SetAtlas("spec-background")
        if stone then
            art:SetAllPoints(stone)
            stone:Hide()
        else
            art:SetPoint("TOPLEFT", 3, -3)
            art:SetPoint("BOTTOMRIGHT", -3, 3)
        end
        frame.__dark = art
    end
    art:SetAlpha(alpha or 1)
    art:Show()
    return art
end
