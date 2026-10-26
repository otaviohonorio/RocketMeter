-- RocketMeter | Demo.lua
-- A made-up Mythic+ run, to see the scoreboard without running a dungeon.
--
-- WHY THIS EXISTS: the scoreboard only shows at the end of a real M+. Testing the look
-- that way costs 30 minutes of play per tweak round, and that is why it went months
-- without anyone looking. With the simulation, the cycle becomes `/rm score demo` + `/reload`.
--
-- A HARD RULE: nothing here touches the API or the real data. `ns.Demo.Run()` returns a loose
-- table; whoever draws decides to use it. There is no path by which a number from here gets into a
-- `C_DamageMeter` session or into the runs' SavedVariables.
--
-- The numbers are not random: they come from a print the user sent of a real run
-- (a +14 of 27:34), with the totals rebuilt by
-- `total = rate * timeInCombat`. So the columns agree with each other -- DPS matches damage,
-- and each column's leader is who the print shows leading.
local ADDON, ns = ...
local L = ns.L

local Demo = {}
ns.Demo = Demo

-- 27:07 of run with 18:00 in combat (66%). The ratio matters: if the time in combat
-- were the wall time, the rebuilt DPS would come out ~1/3 lower than the print's.
local RUN_SECONDS = 1627
local COMBAT_SECONDS = 1080
local TIME_LIMIT = 1800          -- 30:00, a key's typical limit
local KEY_LEVEL = 14

-- Lore character names, as is the custom in test bars: it makes it obvious
-- that it is a simulation and is not confused with people in the group.
local MEMBERS = {
    {
        name = "Bölva", class = "DEATHKNIGHT", role = "TANK", specIconID = 135771,
        dps = 103000, hps = 99000, taken = 215e6, avoidable = 1.9e6,
        deaths = 1, interrupts = 6, dispels = 0,
        score = 2847, scoreGain = 16, ilevel = 691, isLocalPlayer = true,
        keystoneLevel = 15, loot = "item:19019",
    },
    {
        name = "Drakaris", class = "EVOKER", role = "HEALER", specIconID = 4622448,
        dps = 49000, hps = 150000, taken = 44e6, avoidable = 1.3e6,
        deaths = 2, interrupts = 3, dispels = 15,
        score = 2795, scoreGain = 71, ilevel = 688, keystoneLevel = 13,
    },
    {
        name = "Kaelvorn", class = "MAGE", role = "DAMAGER", specIconID = 135810,
        dps = 299000, hps = 18000, taken = 60e6, avoidable = 134000,
        deaths = 0, interrupts = 8, dispels = 2,
        score = 2910, scoreGain = 13, ilevel = 693, keystoneLevel = 16, loot = "item:19019",
    },
    {
        name = "Sargath", class = "WARLOCK", role = "DAMAGER", specIconID = 136150,
        dps = 280000, hps = 12000, taken = 51e6, avoidable = 256000,
        deaths = 1, interrupts = 4, dispels = 0,
        score = 2862, scoreGain = 67, ilevel = 690, keystoneLevel = 14,
    },
    {
        name = "Lilianvoss", class = "ROGUE", role = "DAMAGER", specIconID = 132320,
        dps = 268000, hps = 21000, taken = 49e6, avoidable = 767000,
        deaths = 0, interrupts = 11, dispels = 5,
        score = 2888, scoreGain = 17, ilevel = 689, keystoneLevel = 12,
    },
}

--- Builds the rows in the scoreboard's PICTURE format: `values` indexed by the column's **key**,
--- not by position.
---
--- The key is what lets the picture survive a change in the column list: a run
--- recorded last week still draws right even if today the order is different or a
--- new column came in. A position does not survive that -- and the scoreboard keeps runs on disk.
local function BuildRows()
    local rows = {}

    for i = 1, #MEMBERS do
        local member = MEMBERS[i]

        rows[i] = {
            name = member.name,
            classFilename = member.class,
            specIconID = member.specIconID,
            role = member.role,
            isLocalPlayer = member.isLocalPlayer == true,
            scoreGain = member.scoreGain,
            -- The three columns that arrived in 0.66.0 (item level, keystone and loot). The
            -- simulation HAS to fill them: it is the only way to see the panel without spending
            -- 30 minutes on a key, and a simulation that leaves three columns empty hides
            -- exactly the three that are new.
            ilevel = member.ilevel,
            keystoneLevel = member.keystoneLevel,
            -- `keystoneMapID` stays nil for the same reason as the run's `mapID`: a made-up id
            -- resolves no art, and a real id would tie the simulation to a season.
            keystoneMapID = nil,
            loot = member.loot,
            values = {
                score = member.score,
                deaths = member.deaths,
                taken = member.taken,
                avoidable = member.avoidable,
                dps = member.dps,
                hps = member.hps,
                interrupts = member.interrupts,
                dispels = member.dispels,
                damage = member.dps * COMBAT_SECONDS,
                healing = member.hps * COMBAT_SECONDS,
            },
        }
    end

    return rows
end

--- A whole run, ready for `ns.Scoreboard.Show`.
---
--- `mapID` stays **nil on purpose**: with a made-up id, `C_ChallengeMode.GetMapUIInfo` would return
--- nothing and the panel would fall back anyway; with a real id, the simulation would come to
--- depend on which dungeon exists in the current season. The name goes in as text.
function Demo.Run()
    return {
        demo = true,
        kind = "mplus",
        title = L["Ruins of the Ember Court"],
        mapID = nil,
        level = KEY_LEVEL,
        durationSeconds = RUN_SECONDS,
        combatSeconds = COMBAT_SECONDS,
        timeLimit = TIME_LIMIT,
        onTime = true,
        upgrades = 1,                 -- +1: dentro do limite, fora dos 80%
        deaths = 4,
        timeLostToDeaths = 60,
        scoreBefore = 2831,
        scoreAfter = 2847,
        -- Affixes by id. Resolved by `C_ChallengeMode.GetAffixInfo` at drawing time;
        -- if the client does not know the id, the panel simply does not show the icon.
        affixes = { 10, 152, 148 },
        rows = BuildRows(),
        -- The timeline: the same contract the real run produces.
        --   bosses  = { seconds, name }
        --   deaths  = { seconds, name of who died }
        --   combat  = { seconds, true = entered combat / false = left }
        bosses = {
            { 606, L["First boss"] },
            { 1021, L["Second boss"] },
            { 1523, L["Last boss"] },
        },
        deathMarks = {
            { 342, "Drakaris" },
            { 655, "Bölva" },
            { 1088, "Sargath" },
            { 1402, "Drakaris" },
        },
        combatTimeline = {
            -- The seed of the zero instant exists in the real run (`Run.Start`) and was missing here:
            -- without it the rail's first stretch had no colour, and the simulation stopped
            -- showing the panel as it really looks -- which is the only thing it does.
            { 0, false },
            { 48, true }, { 190, false },
            { 262, true }, { 402, false },
            { 520, true }, { 700, false },
            { 812, true }, { 1040, false },
            { 1120, true }, { 1290, false },
            { 1380, true }, { 1600, false },
        },
    }
end

