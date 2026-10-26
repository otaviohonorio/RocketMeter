-- RocketMeter | Stats.lua
-- (26/10) THE STATISTICS: the keys, the Great Vault and the raids of the week and of the season, and how the player did
-- in them. The user: *"o rocketMeter ter uma janela de estatisticas, pode ser um botão na janela principal, onde mostra
-- quantas pedras fez, quantas foram no tempo e etc, tudo que tu pensar ai, pode ser geral e por semana, já que existe um
-- reset semanal, então fica um geral somando a season e por semana"*, and *"e isso pode tá nesse app também"*.
--
-- WHERE EACH NUMBER COMES FROM, the game first:
--
--   the keys       C_MythicPlus.GetRunHistory(previous weeks, incomplete, this season only): every key of the season
--                  the character did, from before this addon too (map, level, this week or not, completed, its time,
--                  its rating, the date). In time = its time within the map's limit (C_ChallengeMode.GetMapUIInfo).
--   the rating     C_ChallengeMode.GetOverallDungeonScore; per map C_MythicPlus.GetSeasonBestAffixScoreInfoForMap
--   the vault      C_WeeklyRewards.GetActivities: the three rows of the Great Vault (dungeons, raids, world)
--   the raids      GetSavedInstanceInfo: this week's lockouts, bosses defeated of the raid's total
--   the week       C_DateAndTime.GetSecondsUntilWeeklyReset: the week began 7 days before the next reset
--
-- and the player's own numbers (damage per second, rank in the group, deaths, interrupts, boss kills and wipes) only
-- from the runs this addon recorded (MyRun.Save -> Stats.NoteRun), one short line each, kept for the season and dropped
-- when the season changes. The whole picture is saved (RocketMeterRunsDB.stats, per character) for the app to show the
-- same numbers (tools/app/characters.py).
--
-- (!) `completed` OF THE GAME'S RUN HISTORY: the documentation does not say if it is "finished" or "finished in time".
-- Here it is "finished", and in time is the time against the limit; the development log keeps the first runs read
-- ("historico do jogo") to check it against a key the player knows.
local ADDON, ns = ...

local Stats = {}
ns.Stats = Stats

local WEEK = 7 * 24 * 3600
local THROTTLE = 2

local function N(v) return type(v) == "number" and v or nil end

local function Call(f, ...)
    if type(f) ~= "function" then return nil end
    local ok, a, b, c = pcall(f, ...)
    if ok then return a, b, c end
    return nil
end

local function DB()
    if RocketMeterRunsDB == nil then RocketMeterRunsDB = {} end
    return RocketMeterRunsDB
end

---The start of this week (the last weekly reset), in the clock of time().
function Stats.WeekStart()
    local left = C_DateAndTime and N(Call(C_DateAndTime.GetSecondsUntilWeeklyReset))
    local now = time and time() or 0
    if not left then return now - WEEK end
    return now + left - WEEK
end

local function Season()
    local s = C_MythicPlus and N(Call(C_MythicPlus.GetCurrentSeason))
    return (s and s > 0) and s or nil
end

--------------------------------------------------------------------------------
-- The player's own runs, one line each, for the season
--------------------------------------------------------------------------------
local function SeasonLog()
    local db = DB()
    db.seasonLog = type(db.seasonLog) == "table" and db.seasonLog or { runs = {} }
    local season = Season()
    if season and db.seasonLog.season ~= season then
        db.seasonLog = { season = season, runs = {} }
    end
    db.seasonLog.runs = db.seasonLog.runs or {}
    return db.seasonLog
end

local function Fits(f)
    local d = f and f.m and f.m.damage
    local total, rate = d and N(d.total), d and N(d.perSecond)
    if not total or not rate or rate <= 0 or not f.e or not f.s then return true end
    return total / rate <= (f.e - f.s) * 2 + 10
end

---A run just saved (MyRun.Save, the compacted run): a key or a raid goes into the season's lines.
function Stats.NoteRun(c)
    if type(c) ~= "table" or (c.kind ~= "key" and c.kind ~= "raid") then return end
    local m = c.metrics or {}
    local dmg = m.damage or {}
    local line = { at = N(c.at), kind = c.kind, cm = N(c.cm), name = c.name, level = N(c.level), detail = c.detail,
                   dps = N(dmg.perSecond), rank = N(dmg.rank), of = N(dmg.of),
                   deaths = type(c.deaths) == "table" and #c.deaths or 0,
                   interrupts = N((m.interrupts or {}).total) }
    if type(c.result) == "table" then line.onTime, line.sec = c.result.onTime, N(c.result.time) end
    if c.kind == "raid" then
        -- the meter starts again at each boss: the raid's damage is its bosses', each over its own time
        local kills, wipes, dmgSum, secs = 0, 0, 0, 0
        for _, f in ipairs(c.fights or {}) do
            if f.boss then
                if f.success then kills = kills + 1 else wipes = wipes + 1 end
                local d = f.m and f.m.damage
                local rate, dur = d and N(d.perSecond), (f.e and f.s) and (f.e - f.s) or nil
                if rate and dur and dur > 0 and Fits(f) then dmgSum, secs = dmgSum + rate * dur, secs + dur end
            end
        end
        line.kills, line.wipes = kills, wipes
        line.dps = secs > 0 and dmgSum / secs or nil
        line.rank, line.of = nil, nil
    end
    local log = SeasonLog()
    table.insert(log.runs, 1, line)
end

--------------------------------------------------------------------------------
-- What the game says, read now
--------------------------------------------------------------------------------
local function MapInfo(cm, cache)
    if cache[cm] then return cache[cm] end
    -- name, id, time limit, texture (Blizzard_ChallengesUI: the dungeon's icon)
    local all = { pcall(C_ChallengeMode and C_ChallengeMode.GetMapUIInfo, cm) }
    local name, limit, icon = all[1] and all[2], all[1] and all[4], all[1] and all[5]
    local info = { name = type(name) == "string" and name or nil, limit = N(limit), icon = N(icon) }
    local _, best = Call(C_MythicPlus and C_MythicPlus.GetSeasonBestAffixScoreInfoForMap, cm)
    info.rating = N(best)
    local intime = Call(C_MythicPlus and C_MythicPlus.GetSeasonBestForMap, cm)
    if type(intime) == "table" then info.bestLevel, info.bestSec = N(intime.level), N(intime.durationSec) end
    cache[cm] = info
    return info
end

local function DateText(d)
    if type(d) ~= "table" or not N(d.year) then return nil end
    return format("%04d-%02d-%02d %02d:%02d", d.year, (d.month or 0), (d.monthDay or 0), (d.hour or 0), (d.minute or 0))
end

local function ReadGame(snap)
    local maps = {}
    for _, cm in ipairs(Call(C_ChallengeMode and C_ChallengeMode.GetMapTable) or {}) do
        if N(cm) then MapInfo(cm, maps) end
    end
    local runs = {}
    local list = Call(C_MythicPlus and C_MythicPlus.GetRunHistory, true, true, true)
    for _, r in ipairs(type(list) == "table" and list or {}) do
        local cm = N(r.mapChallengeModeID)
        if cm then
            local info = MapInfo(cm, maps)
            runs[#runs + 1] = { cm = cm, level = N(r.level), week = r.thisWeek == true, done = r.completed == true,
                                score = N(r.runScore), sec = N(r.durationSec), date = DateText(r.completionDate),
                                limit = info.limit }
        end
    end
    -- (26/10) WHAT `completed` MEANS, measured: the first reading in game (Dauð, 133 keys) gave 92 completed in time, 0
    -- completed over time and 41 not completed -- over-time keys may be the ones counted as "not completed". Every key
    -- is counted here by (completed?, its time within the limit?), with the times of the not-completed ones, so one
    -- /reload answers it
    if ns.Log and ns.Log.Add and #runs > 0 then
        local c = { feitaNoTempo = 0, feitaFora = 0, naoFeitaNoTempo = 0, naoFeitaFora = 0, semTempo = 0 }
        local tempos = {}
        for _, r in ipairs(runs) do
            if not r.sec or r.sec <= 0 or not r.limit then
                c.semTempo = c.semTempo + 1
            elseif r.done then
                if r.sec <= r.limit then c.feitaNoTempo = c.feitaNoTempo + 1 else c.feitaFora = c.feitaFora + 1 end
            else
                if r.sec <= r.limit then c.naoFeitaNoTempo = c.naoFeitaNoTempo + 1 else c.naoFeitaFora = c.naoFeitaFora + 1 end
                if #tempos < 12 then tempos[#tempos + 1] = format("%d/%d", r.sec, r.limit) end
            end
        end
        c.quantas, c.temposNaoFeitas = #runs, table.concat(tempos, " ")
        ns.Log.Add("historico do jogo", c)
    end
    snap.maps, snap.runs = maps, runs
    snap.score = C_ChallengeMode and N(Call(C_ChallengeMode.GetOverallDungeonScore))

    local vault = {}
    if C_WeeklyRewards and C_WeeklyRewards.GetActivities then
        for _, a in ipairs(Call(C_WeeklyRewards.GetActivities) or {}) do
            vault[#vault + 1] = { type = N(a.type), index = N(a.index), threshold = N(a.threshold),
                                  progress = N(a.progress), level = N(a.level) }
        end
    end
    snap.vault = vault

    local raids = {}
    for i = 1, N(Call(GetNumSavedInstances)) or 0 do
        -- name, lockout id, reset, difficulty id, locked, extended, id most sig, is raid, max players, difficulty
        -- name, encounters, encounters done (Blizzard_RaidFrame/RaidFrame.lua); all[1] is pcall's own
        local all = { pcall(GetSavedInstanceInfo, i) }
        if all[1] then
            local name, reset, difficulty, locked, isRaid, difficultyName, numEncounters, progress =
                all[2], all[4], all[5], all[6], all[9], all[11], all[12], all[13]
            if isRaid and locked and type(name) == "string" then
                raids[#raids + 1] = { name = name, difficulty = N(difficulty), difficultyName = difficultyName,
                                      done = N(progress), total = N(numEncounters), reset = N(reset) }
            end
        end
    end
    snap.raids = raids
end

--------------------------------------------------------------------------------
-- The numbers of a scope: "week" or "season"
--------------------------------------------------------------------------------
local function Avg(sum, n) return n > 0 and sum / n or nil end

---The statistics of `scope` ("week" or "season") from a picture (Stats.Picture) -- a table the window and the app draw.
function Stats.Compute(snap, scope)
    snap = snap or {}
    local week = scope == "week"
    local weekStart = snap.weekStart or 0
    local out = { scope = scope, mplus = {}, dungeons = {}, raids = {}, perf = {} }

    -- the keys, from the game
    local m = { keys = 0, inTime = 0, overTime = 0, notDone = 0, seconds = 0, levels = 0 }
    local byMap = {}
    for _, r in ipairs(snap.runs or {}) do
        if not week or r.week then
            m.keys = m.keys + 1
            local d = byMap[r.cm] or { cm = r.cm, keys = 0, inTime = 0 }
            byMap[r.cm] = d
            d.keys = d.keys + 1
            if r.sec then m.seconds = m.seconds + r.sec end
            if r.level then m.levels = m.levels + r.level end
            local timed = r.done and r.sec and r.limit and r.sec <= r.limit
            if timed then
                m.inTime = m.inTime + 1
                d.inTime = d.inTime + 1
                if r.level and (not m.highest or r.level > m.highest.level) then m.highest = { level = r.level, cm = r.cm } end
                if r.level and (not d.bestLevel or r.level > d.bestLevel or (r.level == d.bestLevel and r.sec < (d.bestSec or math.huge))) then
                    d.bestLevel, d.bestSec = r.level, r.sec
                end
            elseif r.done then
                m.overTime = m.overTime + 1
            else
                m.notDone = m.notDone + 1
            end
        end
    end
    m.avgLevel = Avg(m.levels, m.keys)
    m.levels = nil
    if m.highest then m.highest.name = ((snap.maps or {})[m.highest.cm] or {}).name end
    if week then
        local before = snap.weekScore and snap.weekScore[weekStart]
        m.gained = (snap.score and before) and (snap.score - before) or nil
    else
        m.rating = snap.score
    end
    out.mplus = m
    for cm, info in pairs(snap.maps or {}) do
        local d = byMap[cm] or { cm = cm, keys = 0, inTime = 0 }
        d.name = info.name
        if not week then d.rating = info.rating end
        out.dungeons[#out.dungeons + 1] = d
        byMap[cm] = nil
    end
    for _, d in pairs(byMap) do
        d.name = ((snap.maps or {})[d.cm] or {}).name
        out.dungeons[#out.dungeons + 1] = d
    end
    table.sort(out.dungeons, function(a, b) return tostring(a.name or a.cm) < tostring(b.name or b.cm) end)

    -- the vault (this week only: the game's three rows)
    if week then
        local rows = {}
        for _, a in ipairs(snap.vault or {}) do
            local r = rows[a.type] or { type = a.type, progress = 0, slots = 0, unlocked = 0, threshold = 0 }
            rows[a.type] = r
            r.slots = r.slots + 1
            r.progress = math.max(r.progress, a.progress or 0)
            r.threshold = math.max(r.threshold, a.threshold or 0)
            if (a.progress or 0) >= (a.threshold or math.huge) then r.unlocked = r.unlocked + 1 end
        end
        out.vault = {}
        for _, t in ipairs({ 1, 3, 6 }) do if rows[t] then out.vault[#out.vault + 1] = rows[t] end end
    end

    -- the player's own: the runs this addon recorded
    local p = { keys = 0, raids = 0 }
    local dps, rank, deaths, interrupts, nDps, nRank, nInt = 0, 0, 0, 0, 0, 0, 0
    local bossDps, nBoss, kills, wipes = 0, 0, 0, 0
    local raidRows = {}
    for _, r in ipairs((snap.seasonLog or {}).runs or {}) do
        if not week or (r.at or 0) >= weekStart then
            if r.kind == "key" then
                p.keys = p.keys + 1
                if r.dps then dps, nDps = dps + r.dps, nDps + 1 end
                if r.rank then rank, nRank = rank + r.rank, nRank + 1 end
                deaths = deaths + (r.deaths or 0)
                if r.interrupts then interrupts, nInt = interrupts + r.interrupts, nInt + 1 end
            elseif r.kind == "raid" then
                p.raids = p.raids + 1
                if r.dps then bossDps, nBoss = bossDps + r.dps, nBoss + 1 end
                kills, wipes = kills + (r.kills or 0), wipes + (r.wipes or 0)
                local key = tostring(r.name) .. "|" .. tostring(r.detail)
                local row = raidRows[key] or { name = r.name, detail = r.detail, kills = 0, wipes = 0 }
                raidRows[key] = row
                row.kills, row.wipes = row.kills + (r.kills or 0), row.wipes + (r.wipes or 0)
            end
        end
    end
    p.dps, p.rank = Avg(dps, nDps), Avg(rank, nRank)
    p.deaths = p.keys > 0 and deaths / p.keys or nil
    p.interrupts = Avg(interrupts, nInt)
    p.bossDps, p.kills, p.wipes = Avg(bossDps, nBoss), kills, wipes
    out.perf = p

    -- the raids: this week's lockouts (the game), the season's from the runs recorded
    if week then
        for _, r in ipairs(snap.raids or {}) do out.raids[#out.raids + 1] = r end
    else
        for _, r in pairs(raidRows) do out.raids[#out.raids + 1] = r end
        table.sort(out.raids, function(a, b) return tostring(a.name) < tostring(b.name) end)
    end
    return out
end

--------------------------------------------------------------------------------
-- The picture: read, kept, saved for the app
--------------------------------------------------------------------------------
local lastCapture = -math.huge

---Reads the game again and saves the picture (out of combat; at most once every THROTTLE seconds unless `force`).
function Stats.Capture(force)
    if InCombatLockdown and InCombatLockdown() then return Stats.Picture() end
    local now = GetTime and GetTime() or 0
    if not force and now - lastCapture < THROTTLE then return Stats.Picture() end
    lastCapture = now
    local db = DB()
    local snap = type(db.stats) == "table" and db.stats or {}
    snap.at = time and time() or nil
    snap.season = Season() or snap.season
    snap.weekStart = Stats.WeekStart()
    local ok = pcall(ReadGame, snap)
    if not ok and ns.Log and ns.Log.Add then ns.Log.Add("estatisticas", { erro = "a leitura do jogo falhou" }) end
    -- the rating when this week was first seen: what the week gained is the rating now less this one
    snap.weekScore = type(snap.weekScore) == "table" and snap.weekScore or {}
    if snap.score and snap.weekStart and not snap.weekScore[snap.weekStart] then
        for k in pairs(snap.weekScore) do if k < snap.weekStart - 8 * WEEK then snap.weekScore[k] = nil end end
        snap.weekScore[snap.weekStart] = snap.score
    end
    SeasonLog()                                  -- a new season starts its own lines
    snap.seasonLog = nil
    db.stats = snap
    -- what the window and the app show, worked out once (the app reads it from the saved file)
    local view = Stats.Picture()
    snap.computed = { week = Stats.Compute(view, "week"), season = Stats.Compute(view, "season") }
    return view
end

---The picture with the season's own runs beside it (not saved twice).
function Stats.Picture()
    local db = DB()
    local snap = type(db.stats) == "table" and db.stats or {}
    local view = {}
    for k, v in pairs(snap) do view[k] = v end
    view.seasonLog = db.seasonLog
    return view
end

---Asks the game for what it loads late (the keys' maps, the vault, the lockouts); the events below capture.
function Stats.Request()
    if C_MythicPlus and C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end
    if RequestRaidInfo then pcall(RequestRaidInfo) end
end

function Stats.Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    f:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    f:RegisterEvent("UPDATE_INSTANCE_INFO")
    f:RegisterEvent("PLAYER_LOGOUT")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            Stats.Request()
        elseif event == "CHALLENGE_MODE_COMPLETED" then
            if C_Timer and C_Timer.After then C_Timer.After(5, function() Stats.Request() end) end
        else
            pcall(Stats.Capture, event == "PLAYER_LOGOUT")
            if ns.StatsWindow and ns.StatsWindow.Refresh then pcall(ns.StatsWindow.Refresh) end
        end
    end)
end

function Stats.__reset() lastCapture = -math.huge end
