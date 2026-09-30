-- RocketMeter | Casts.lua
--
-- What the meter's API does not count: the crowd control each one USED, and the interrupts that
-- MISSED. Both are casts, read from `UNIT_SPELLCAST_SUCCEEDED`, and both come with the limits
-- the client sets (12.1.0), which decide the design:
--
--   1. The cast of a unit that is "not the player or their pet" reaches an addon SECRET
--      (`SecretWhenUnitSpellCastRestricted`, UnitDocumentation.lua), unless the spell itself is
--      flagged otherwise. A secret spellID cannot be compared, so it cannot be counted as
--      anything: it is counted as "secret", and the cell of that player stays EMPTY, which is
--      honest. Only a real run says for which units this happens (the probe in Log.lua).
--   2. A cast says the spell went out, not what it did. A stun on an immune target, a kick on a
--      target that was not casting: both are casts. So control is "control used", and the missed
--      interrupts are the casts of an interrupt spell minus the interrupts the game credited,
--      which is exactly the kick that cut nothing. The user's words (30/09): *"vamos contar
--      controle de grupo (explicando que não necessariamente deu certo) os interrupts com
--      sucesso e os que falharam"*.
--   3. The pet's casts go to the OWNER (`pet` -> `player`, `partypetN` -> `partyN`): the
--      warlock's kick is the felhunter's, and the user asked for it on the warlock's line.
--
-- WHICH SPELLS. Crowd control is the game's word: `C_Spell.IsSpellCrowdControl`. Interrupts have
-- no such question, so the table `Data/InterruptSpells.lua` (generated from the game's spell
-- tables) says which casts are interrupts, and the meter TEACHES the rest: a spell the game
-- credited an interrupt to is an interrupt spell (`Casts.Learn`, from Data.lua).
--
-- WHO. A cast names a unit token ("party2"), and the meter's rows are named. The token is
-- resolved to a name when the name can be read (out of combat it can); until then the casts
-- wait under the token and move to the name at the first resolution. A roster change forgets
-- the tokens: "party2" may be someone else now.
--
-- WHEN. Two tallies, like the meter's sessions: `current` starts over at every combat start,
-- `overall` at the meter's reset (`DAMAGE_METER_RESET`). Casts between fights go to both.
local ADDON, ns = ...

local Casts = {}
ns.Casts = Casts

local OWNER_OF = {
    player = "player", pet = "player",
    party1 = "party1", partypet1 = "party1",
    party2 = "party2", partypet2 = "party2",
    party3 = "party3", partypet3 = "party3",
    party4 = "party4", partypet4 = "party4",
}
local TOKENS = { "player", "party1", "party2", "party3", "party4" }

local learned = {}           -- [spellID] = true, taught by the meter
local controlCache = {}      -- [spellID] = true/false, the game's answer
local names = {}             -- [token] = name (short) once it could be read
local tallies = { current = {}, overall = {} }   -- [which][name or token] = { control = {}, interrupt = {} }

local function Readable(value)
    return value ~= nil and not issecretvalue(value)
end

---The name without the realm: the meter names its rows so, and so does the roster.
local function Short(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^%-]+)") or name
end
Casts.Short = Short

local function IsControl(spellID)
    local known = controlCache[spellID]
    if known ~= nil then return known end
    local is = false
    if C_Spell and C_Spell.IsSpellCrowdControl then
        local ok, answer = pcall(C_Spell.IsSpellCrowdControl, spellID)
        is = ok and Readable(answer) and answer == true
    end
    controlCache[spellID] = is
    return is
end

local function IsInterrupt(spellID)
    return (ns.InterruptSpells and ns.InterruptSpells[spellID]) or learned[spellID] or false
end

function Casts.IsInterruptSpell(spellID)
    return Readable(spellID) and IsInterrupt(spellID) or false
end

---The meter credited an interrupt to this spell: from now on its casts count as interrupts.
function Casts.Learn(spellID)
    if Readable(spellID) and type(spellID) == "number" then learned[spellID] = true end
end

local function Bucket(which, key)
    local list = tallies[which]
    local bucket = list[key]
    if not bucket then
        bucket = { control = {}, interrupt = {} }
        list[key] = bucket
    end
    return bucket
end

local function Merge(into, from)
    for kind, spells in pairs(from) do
        local dest = into[kind]
        for spellID, n in pairs(spells) do dest[spellID] = (dest[spellID] or 0) + n end
    end
end

---The name of a token, if it can be read now. The first time it can, what waited under the
---token moves to the name.
local function Resolve(token)
    local name = names[token]
    if name then return name end
    if not UnitExists(token) then return nil end
    local raw = UnitName(token)
    if not Readable(raw) then return nil end
    name = Short(raw)
    if not name then return nil end
    names[token] = name
    for _, which in ipairs({ "current", "overall" }) do
        local waiting = tallies[which][token]
        if waiting then
            Merge(Bucket(which, name), waiting)
            tallies[which][token] = nil
        end
    end
    return name
end

---One cast of the group. Everything secret is counted as secret and nothing else.
function Casts.OnCast(unit, spellID)
    if not Readable(unit) or type(unit) ~= "string" then return end
    local owner = OWNER_OF[unit]
    if not owner then return end
    if not Readable(spellID) or type(spellID) ~= "number" then
        for _, which in ipairs({ "current", "overall" }) do
            local bucket = Bucket(which, Resolve(owner) or owner)
            bucket.secret = (bucket.secret or 0) + 1
        end
        return
    end

    local control = IsControl(spellID)
    local interrupt = IsInterrupt(spellID)
    if not control and not interrupt then return end

    local key = Resolve(owner) or owner
    for _, which in ipairs({ "current", "overall" }) do
        local bucket = Bucket(which, key)
        if control then bucket.control[spellID] = (bucket.control[spellID] or 0) + 1 end
        if interrupt then bucket.interrupt[spellID] = (bucket.interrupt[spellID] or 0) + 1 end
    end
end

---What one player did, by name (the meter's row) or by `isLocal`.
---@return table|nil { control = {[spellID]=n}, interrupt = {[spellID]=n}, controlTotal, interruptTotal, secret }
function Casts.For(which, name, isLocal)
    local key
    if isLocal then
        key = Resolve("player") or "player"
    else
        key = Short(name)
        if not key then return nil end
        -- The name may still be waiting under a token: resolve what can be resolved.
        if not tallies[which][key] then
            for _, token in ipairs(TOKENS) do Resolve(token) end
        end
    end
    local bucket = tallies[which][key]
    if not bucket then return nil end
    local out = { control = bucket.control, interrupt = bucket.interrupt,
        controlTotal = 0, interruptTotal = 0, secret = bucket.secret or 0 }
    for _, n in pairs(bucket.control) do out.controlTotal = out.controlTotal + n end
    for _, n in pairs(bucket.interrupt) do out.interruptTotal = out.interruptTotal + n end
    return out
end

---Has this player any cast counted at all? Tells "zero" from "nothing was seen".
function Casts.Seen(which, name, isLocal)
    return Casts.For(which, name, isLocal) ~= nil
end

function Casts.OnCombatStart()
    tallies.current = {}
end

function Casts.OnReset()
    tallies.current = {}
    tallies.overall = {}
end

---The roster changed: a token may be someone else now. What has a name keeps it.
function Casts.OnRoster()
    for _, token in ipairs(TOKENS) do
        if token ~= "player" then
            names[token] = nil
            tallies.current[token] = nil
            tallies.overall[token] = nil
        end
    end
end

---`which` of the meter's session type: `Data.SessionValue` speaks numbers, this file speaks names.
function Casts.Which(sessionType)
    if sessionType == 1 or sessionType == "overall" then return "overall" end
    return "current"
end

function Casts.Init()
    local frame = CreateFrame("Frame", ADDON .. "CastsFrame")
    frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    frame:RegisterEvent("DAMAGE_METER_RESET")
    frame:RegisterEvent("PLAYER_REGEN_DISABLED")
    frame:SetScript("OnEvent", function(_, event, unit, _, spellID)
        -- In `pcall`: this runs at every cast of everyone around.
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            pcall(Casts.OnCast, unit, spellID)
        elseif event == "GROUP_ROSTER_UPDATE" then
            Casts.OnRoster()
        elseif event == "DAMAGE_METER_RESET" then
            Casts.OnReset()
        elseif event == "PLAYER_REGEN_DISABLED" then
            Casts.OnCombatStart()
        end
    end)
end

-- For the harness: the tallies as they are.
function Casts.__tallies() return tallies end
function Casts.__reset()
    tallies = { current = {}, overall = {} }
    names = {}
    learned = {}
    controlCache = {}
end
