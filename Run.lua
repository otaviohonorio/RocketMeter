-- RocketMeter | Run.lua
-- Records a Mythic+ run's timeline while it happens.
--
-- WHY IT HAS TO RECORD. At the end of the run the client gives the result (time, in time,
-- deaths, score), but it does not give the *history*: when each boss fell, when the group
-- entered and left combat, when someone died. None of it can be looked up afterwards. Either it is
-- noted during, or the scoreboard's footer stays empty.
--
-- AND THE COMBAT LOG CANNOT BE USED. `COMBAT_LOG_EVENT_UNFILTERED` was removed in Midnight, and
-- with it the classic way of knowing who died and when. What is left, and what this
-- file uses, are plain frame events:
--
--   CHALLENGE_MODE_START             -> resets and marks the zero instant
--   PLAYER_REGEN_DISABLED/ENABLED    -> the stretches in and out of combat
--   ENCOUNTER_END (success)          -> the instant of each boss
--   CHALLENGE_MODE_DEATH_COUNT_UPDATED -> when the deaths counter goes up
--
-- The death event gives **when**, not **who**. Who died comes from the meter's list of deaths
-- (`Scoreboard.AttachDeathClasses`), which lends class and name to the marker when the two
-- lists match -- otherwise the marker stays the skull with no name.
local ADDON, ns = ...

local Run = {}
ns.Run = Run

local active = false
local startedAt
local partial = false        -- a run whose start was not recorded (joined after the start)

-- FROM WHEN THE RECORD HOLDS, in seconds of run. `nil` (or 0) means "since the
-- first instant"; any other number is a RESUMED run, and the stretch before it the
-- addon did not see.
--
-- This exists because of a defect reported with a print (07/09 20:22): the panel announced
-- **"Fora de combate: 26:13"** on a 26:13 key -- that is, the whole run. The cause was the
-- `/reload` in the middle of the key, which is routine for whoever tinkers with addons: `Run.Resume` recovers the
-- total time from the world timer, but the combat record starts again empty. Adding up "what is not
-- marked as combat" over a record that only covers the end of the run gives all the time.
--
-- The file itself already had the rule written, for the offsets: *"um rodape ausente e honesto, um
-- rodape com os bosses todos deslocados e mentira -- e mentira com aparencia de dado e o pior
-- resultado possivel"*. It was missing for the CONTENT too.
local knownFrom = 0
local combatTimeline = {}
local bosses = {}
local deaths = {}
local lastDeathCount = 0

--- Seconds since the start of the run. Outside a run it returns nil, and the caller simply
--- does not record -- it is what makes this module inert when there is no M+ under way.
local function Elapsed()
    if not active or not startedAt then return nil end
    local now = GetTime()
    local at = now - startedAt
    if at < 0 then at = 0 end
    return at
end

function Run.Start()
    active = true
    partial = false
    knownFrom = 0
    startedAt = GetTime()
    combatTimeline = {}
    bosses = {}
    deaths = {}
    lastDeathCount = 0

    -- The seed: the run starts out of combat. Without this entry the rail's first stretch
    -- would have no colour until the first `PLAYER_REGEN_DISABLED`.
    combatTimeline[1] = { 0, InCombatLockdown() and true or false }

    -- WHAT THE SCOREBOARD NEEDS AND THE METER DOES NOT KNOW (0.66.0): the loot is the run's that
    -- starts now, and each one's item level is asked for HERE, at the start -- the inspection is
    -- spaced on purpose and takes a few seconds, and at the end of the key the group is already
    -- breaking up.
    if ns.Party then
        ns.Party.ResetLoot()
        ns.Party.RefreshItemLevels()
    end
end

function Run.Stop()
    active = false
end

--- Resumes recording when the addon loads INSIDE a run already under way -- the case of
--- `/reload` in the middle of the key, which is routine when tinkering with addons.
---
--- Without this `CHALLENGE_MODE_START` has already gone by, `Run` never turns on, and at the end of the run the scoreboard's
--- footer shows empty without explaining anything.
---
--- The zero instant is recovered from the world timer. If it does not come, the run is marked
--- as PARTIAL and the getters return nil: an absent footer is honest, a footer with the bosses
--- all shifted is a lie -- and a lie that looks like data is the worst possible result.
function Run.Resume()
    if active then return end
    if not C_ChallengeMode or not C_ChallengeMode.GetActiveChallengeMapID then return end

    local ok, mapID = pcall(C_ChallengeMode.GetActiveChallengeMapID)
    if not ok or not mapID or mapID == 0 then return end

    Run.Start()

    -- (14/10) The deaths before the /reload were not seen: the counter starts from what the game
    -- already counts, or the next death drew all of them at once, piled on its instant.
    if C_ChallengeMode.GetDeathCount then
        local okCount, count = pcall(C_ChallengeMode.GetDeathCount)
        if okCount and type(count) == "number" then lastDeathCount = count end
    end

    local elapsed = Run.ElapsedFromWorldTimer()
    if elapsed then
        startedAt = GetTime() - elapsed
        -- THE RECORD ONLY HOLDS FROM HERE ON. The seed goes in at the instant of resuming, not
        -- at zero: marking zero as "out of combat" would be stating something about the 20 minutes the
        -- addon did not follow.
        knownFrom = elapsed
        combatTimeline[1] = { elapsed, InCombatLockdown() and true or false }
    else
        partial = true
    end
end

--- Seconds already elapsed of the key, read from the world timer.
---
--- It uses `Enum.WorldElapsedTimerTypes.ChallengeMode`, not the legacy global
--- `LE_WORLD_ELAPSED_TIMER_TYPE_CHALLENGE_MODE`: that legacy constant is probably nil
--- in this client -- and
--- `timerType ~= nil` would always be true, making the search never find the timer.
function Run.ElapsedFromWorldTimer()
    if not GetWorldElapsedTimers or not GetWorldElapsedTime then return nil end
    local wanted = Enum and Enum.WorldElapsedTimerTypes and Enum.WorldElapsedTimerTypes.ChallengeMode
    if wanted == nil then return nil end

    local ok, timers = pcall(GetWorldElapsedTimers)
    if not ok or type(timers) ~= "table" then return nil end

    for i = 1, #timers do
        local got, _, elapsed, kind = pcall(GetWorldElapsedTime, timers[i])
        if got and kind == wanted and type(elapsed) == "number" and elapsed > 0 then
            return elapsed
        end
    end
    return nil
end

--- From which second of the run the record can be read as true.
---
--- 0 in a run followed from the start; the instant of resuming when there was a `/reload` midway.
--- Whoever draws uses this so as not to state anything about the stretch nobody saw.
function Run.GetKnownFrom()
    if partial then return nil end
    return knownFrom
end

function Run.OnCombatStart()
    local at = Elapsed()
    if not at then return end
    combatTimeline[#combatTimeline + 1] = { at, true }
end

function Run.OnCombatEnd()
    local at = Elapsed()
    if not at then return end
    combatTimeline[#combatTimeline + 1] = { at, false }
end

---Um boss caiu. `success` do `ENCOUNTER_END` vem como 1 ou true dependendo do cliente.
function Run.OnEncounterEnd(encounterName, success)
    if success ~= 1 and success ~= true then return end
    local at = Elapsed()
    if not at then return end
    bosses[#bosses + 1] = { at, encounterName }
end

--- The dungeon's deaths counter went up. It can go up more than one at once (the whole group
--- dying together), and then it records one marker per death at the same instant.
function Run.OnDeathCountUpdated()
    local at = Elapsed()
    if not at then return end

    local count = 0
    if C_ChallengeMode and C_ChallengeMode.GetDeathCount then
        local ok, value = pcall(C_ChallengeMode.GetDeathCount)
        if ok and type(value) == "number" then count = value end
    end

    -- With no readable counter, it records one death and goes on: better one marker less than
    -- a loop that does not end.
    if count <= lastDeathCount then
        deaths[#deaths + 1] = { at }
        lastDeathCount = lastDeathCount + 1
        return
    end

    for _ = lastDeathCount + 1, count do
        deaths[#deaths + 1] = { at }
    end
    lastDeathCount = count
end

-- The three getters return nil when the run is PARTIAL. The timestamp of everything
-- recorded depends on the zero instant, and in a partial run that instant is unknown: the
-- markers would all come out shifted, and the user would have no way of knowing it by looking.
function Run.GetCombatTimeline()
    if partial or #combatTimeline == 0 then return nil end
    return combatTimeline
end

function Run.GetBosses()
    if partial or #bosses == 0 then return nil end
    return bosses
end

function Run.GetDeaths()
    if partial or #deaths == 0 then return nil end
    return deaths
end
