-- RocketMeter | Kicks.lua
-- (26/10) THE CLOCK OF EACH ONE'S INTERRUPT, beside the interrupts column, with the game's cooldown clock on the
-- icon, so the player knows whose kick is back before spending his own. The user: *"a coluna do
-- interrupt virar dupla e com o icone da skill de interrupt de cada classe com o CD dela (...) para eu saber quando eu
-- posso dar o meu interrupt sem que eu use depois que alguém já usou"*, chosen from three mock-ups (the clock on the
-- icon, square or round as the specialization's: `ns.IconShape`).
--
-- (!) NOT FOR THE DISPELS. The user: *"e a mesma lógica serve para o dispel"*, then *"se for possível fazer igual para
-- dispel, se não for, ai não faz"*. It is not possible the same way: a teammate's dispel has no signal like the enemy's
-- interrupted cast -- an aura gone from someone may simply have ended, and the aura itself is secret in combat -- so
-- only the player's own would be known. Left out.
--
-- WHAT THE GAME LETS AN ADDON KNOW (12.1, read before writing this):
--   * the player's own casts are readable: his kick is EXACT, the missed ones too (Casts.lua, a real key on 30/09);
--   * a teammate's cast reaches the addon with the spell SECRET (`SecretWhenUnitSpellCastRestricted`), but the event
--     itself comes, with the unit: "party2 cast something, now";
--   * an enemy's cast cut short comes as `UNIT_SPELLCAST_INTERRUPTED`, its `interruptedBy` secret too;
--   * addon messages are locked during a key and a raid boss (`SendAddonMessageResult.AddOnMessageLockdown`).
-- So a teammate's KICK is put together as the interrupt addons made for Midnight do: an enemy
-- interrupted + the ONE teammate who cast something in that instant and whose kick could be ready. Two casting in the
-- same instant: nobody is credited (better nothing than the wrong one); a kick that cut nothing is not seen; a stun that
-- cut a cast looks like a kick. Out of combat, and wherever the game does not hide it, the spell is read and it is
-- exact. Every attribution goes to the development log ("kick").
--
-- WHICH ROW. In combat the meter's row has its name and numbers secret but its CLASS readable (the log, 25/10), and
-- "this is the player" too: the row is the player's, or the only teammate of that class. Two of the same class: no
-- clock rather than one on the wrong row. The spell comes from the row's specialization (its icon, readable) and
-- `Data/Kicks.lua` (generated from the game's tables); the cooldown is the base one (a teammate's talents cannot be read).
local ADDON, ns = ...

local Kicks = {}
ns.Kicks = Kicks

local WINDOW_BEFORE = 0.4         -- a teammate's cast this long before the enemy's interruption counts
local WINDOW_AFTER = 0.15         -- ... and this long after (the two events may come in either order)
local SAME_INTERRUPT = 0.1        -- the same interruption seen through several tokens (target, nameplate, focus)
local GRACE = 0.5                 -- a kick "on cooldown" this close to its end may already be back

-- The kind: the column it sits in and its tables (one kind: see "NOT FOR THE DISPELS" above)
local KINDS = {
    kick = { column = "interrupts", spells = "KickSpells", bySpec = "KickBySpec" },
}
Kicks.KINDS = KINDS
local KIND_OF_COLUMN = { interrupts = "kick" }

local FRIENDLY = { player = "player", pet = "player", vehicle = "player" }
for i = 1, 4 do FRIENDLY["party" .. i] = "party" .. i; FRIENDLY["partypet" .. i] = "party" .. i end
local TEAM = { "party1", "party2", "party3", "party4" }

local function Readable(v) return v ~= nil and not issecretvalue(v) end
local function Now() return GetTime and GetTime() or 0 end
local function Spells(kind) return ns[KINDS[kind].spells] or {} end

local castIndex                   -- [any cast id] = { kind, main id }
local specByIcon                  -- [spec icon] = spec id
local uses = { kick = {} }      -- [kind][token] = { at = time, spell = id }
local known = { kick = {} }     -- [kind][token] = the teammate's spell as his row last told; false: his spec has none
local lastCast = {}               -- [token] = time of its last cast of anything
local lastInterrupt = -math.huge
local pending = false

local function CastIndex()
    if castIndex then return castIndex end
    castIndex = {}
    for kind in pairs(KINDS) do
        for id, k in pairs(Spells(kind)) do
            castIndex[id] = { kind, id }
            for _, other in ipairs(k.casts or {}) do castIndex[other] = { kind, id } end
        end
    end
    return castIndex
end

---The spec id of a specialization icon (the meter's row gives the icon), from the game: every class's specs.
local function SpecByIcon(icon)
    if not specByIcon then
        specByIcon = {}
        local count = C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID
        if GetNumClasses and count and GetSpecializationInfoForClassID then
            for classID = 1, GetNumClasses() do
                for i = 1, (count(classID) or 0) do
                    local ok, id, _, _, specIcon = pcall(GetSpecializationInfoForClassID, classID, i)
                    if ok and id and specIcon then specByIcon[specIcon] = id end
                end
            end
        end
    end
    return specByIcon[icon]
end

---The spell (main id) of `kind` a specialization has, or nil.
function Kicks.SpellForSpec(specID, kind)
    local by = ns[KINDS[kind or "kick"].bySpec]
    return specID and by and by[specID] or nil
end

---The kind ("kick") a column carries the clock of, or nil.
function Kicks.KindOfColumn(key) return KIND_OF_COLUMN[key] end

---Whether the option is on (Configure; on by default).
function Kicks.Enabled()
    return not (ns.db and ns.db.kickClock == false)
end

local function ClassOf(token)
    if not UnitExists or not UnitExists(token) then return nil end
    local ok, _, class = pcall(UnitClass, token)
    return ok and Readable(class) and class or nil
end

local function NameOf(token)
    if not UnitName then return nil end
    local ok, name = pcall(UnitName, token)
    return ok and Readable(name) and name or nil
end

---The group token of a meter row: the player's, the teammate of that name (out of combat), else the only teammate of
---that class. nil when it cannot be told.
function Kicks.TokenForRow(source)
    if type(source) ~= "table" then return nil end
    local mine = source.isLocalPlayer
    if Readable(mine) and mine == true then return "player" end
    local name = source.name
    if Readable(name) then
        local short = ns.Casts and ns.Casts.Short and ns.Casts.Short(name) or name
        for _, t in ipairs(TEAM) do if NameOf(t) == short then return t end end
    end
    local class = source.classFilename
    if not Readable(class) then return nil end
    local found
    for _, t in ipairs(TEAM) do
        if ClassOf(t) == class then
            if found then return nil end      -- two of the same class: cannot tell which
            found = t
        end
    end
    return found
end

---Whether the player knows a spell, his or his pet's (the warlock's Spell Lock is the demon's): C_SpellBook.
local function Knows(id)
    if not (C_SpellBook and C_SpellBook.IsSpellKnown) then return true end
    local ok, mine = pcall(C_SpellBook.IsSpellKnown, id)
    if ok and mine == true then return true end
    local pet = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
    if pet then
        local okP, his = pcall(C_SpellBook.IsSpellKnown, id, pet)
        if okP and his == true then return true end
    end
    return false
end

local function PlayerSpell(kind)
    -- the player's spec id as the game's own UI reads it (PlayerUtil.GetCurrentSpecID, UnitUtil.lua)
    local SI = C_SpecializationInfo
    local spec = SI and SI.GetSpecialization and SI.GetSpecialization()
    local specID = spec and SI.GetSpecializationInfo and SI.GetSpecializationInfo(spec)
    local spell = Kicks.SpellForSpec(specID, kind)
    if not spell then return nil end
    -- only if he really has it (most are talents)
    if Knows(spell) then return spell end
    for _, other in ipairs((Spells(kind)[spell] or {}).casts or {}) do
        if Knows(other) then return spell end
    end
    return nil
end

---What a row's cell shows for `kind`: { spell, icon, start, duration, state = "ready" | "cooldown" } or nil (no such
---spell, a row that cannot be told).
function Kicks.ForRow(source, kind)
    kind = kind or "kick"
    if not Kicks.Enabled() or type(source) ~= "table" or not KINDS[kind] then return nil end
    local token = Kicks.TokenForRow(source)
    if not token then return nil end
    local spell
    if token == "player" then
        spell = PlayerSpell(kind)
    else
        local icon = source.specIconID
        local specID = Readable(icon) and SpecByIcon(icon) or nil
        spell = Kicks.SpellForSpec(specID, kind)
        -- a spec with no interrupt (Holy, Discipline) is remembered as such: it cannot be the one who kicked
        if specID then known[kind][token] = spell or false end
    end
    local k = spell and Spells(kind)[spell]
    if not k then return nil end
    local out = { spell = spell, token = token,
                  icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell) or nil }
    local u = uses[kind][token]
    if u and Now() < u.at + k.cd then
        out.state, out.start, out.duration = "cooldown", u.at, k.cd
    else
        out.state = "ready"
    end
    return out
end

local function BackAt(kind, token)
    local u = uses[kind][token]
    if not u then return nil end
    return u.at + ((Spells(kind)[u.spell] or {}).cd or 0)
end

local function Changed(kind, token)
    if ns.Window and ns.Window.Refresh then pcall(ns.Window.Refresh, true) end
    local back = BackAt(kind, token)
    if back and C_Timer and C_Timer.After then
        -- the clock runs by itself; the "ready" look needs a redraw when it ends
        C_Timer.After(math.max(0.05, back - Now() + 0.05), function()
            if ns.Window and ns.Window.Refresh then pcall(ns.Window.Refresh, true) end
        end)
    end
end

local function Use(kind, token, spell, how)
    uses[kind][token] = { at = Now(), spell = spell }
    if ns.Log and ns.Log.Add then ns.Log.Add("kick", { tipo = kind, quem = token, magia = spell, como = how }) end
    Changed(kind, token)
end

---An enemy's cast was cut: who of the team cast something in that instant, and could have kicked?
local function Attribute(at)
    pending = false
    -- (26/10, review) a kick READ in that instant -- the player's own, always readable, or a teammate's the game let be
    -- read -- is the one that cut it: no guessing. Without this the player's own kick went to a teammate who happened
    -- to cast something at the same moment (the player is not among the candidates)
    for token, u in pairs(uses.kick) do
        if u.at >= at - WINDOW_BEFORE and u.at <= at + WINDOW_AFTER then
            if ns.Log and ns.Log.Add then ns.Log.Add("kick-correlacao", { candidatos = "", escolhido = token .. " (lido)" }) end
            return
        end
    end
    local found, candidates = nil, {}
    for _, t in ipairs(TEAM) do
        local c = lastCast[t]
        if c and c >= at - WINDOW_BEFORE and c <= at + WINDOW_AFTER then
            local back = BackAt("kick", t)
            if known.kick[t] ~= false and not (back and at < back - GRACE) then candidates[#candidates + 1] = t end
        end
    end
    if #candidates == 1 then
        found = candidates[1]
        local spell = known.kick[found]
        if spell then Use("kick", found, spell, "correlacao") end
    end
    if ns.Log and ns.Log.Add then
        ns.Log.Add("kick-correlacao", { candidatos = table.concat(candidates, ","), escolhido = found or "ninguem" })
    end
end

function Kicks.OnCast(unit, spellID)
    local owner = FRIENDLY[unit]
    if not owner then return end
    lastCast[owner] = Now()
    if Readable(spellID) then
        local hit = CastIndex()[spellID]
        if hit then Use(hit[1], owner, hit[2], owner == "player" and "proprio" or "lido") end
    end
end

function Kicks.OnInterrupted(unit)
    if type(unit) ~= "string" or FRIENDLY[unit] or unit:match("^raid") then return end
    -- an ally's cast cut by an enemy (the target or a nameplate may be a friend): not an enemy interrupted
    if UnitIsFriend then
        local ok, friend = pcall(UnitIsFriend, "player", unit)
        if ok and Readable(friend) and friend == true then return end
    end
    local at = Now()
    if at - lastInterrupt < SAME_INTERRUPT then return end
    lastInterrupt = at
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(WINDOW_AFTER, function() Attribute(at) end) else Attribute(at) end
end

function Kicks.Reset()
    uses, lastCast, pending = { kick = {} }, {}, false
end

function Kicks.ForgetRoster()
    Kicks.Reset()
    known = { kick = {} }
end

-- who is in each token: GROUP_ROSTER_UPDATE also comes when nobody changed (a role, someone going offline), and then
-- the clocks stay
local roster = ""
local function Roster()
    local parts = {}
    for _, t in ipairs(TEAM) do
        local ok, guid = pcall(UnitGUID, t)
        parts[#parts + 1] = (ok and Readable(guid) and guid) or NameOf(t) or "-"
    end
    return table.concat(parts, "|")
end

function Kicks.OnRoster()
    local now = Roster()
    if roster == "" then roster = now return end    -- the first: nothing to compare with yet
    if now ~= roster then
        roster = now
        Kicks.ForgetRoster()                    -- "party2" may be someone else now
    end
end

function Kicks.Init()
    local f = CreateFrame("Frame")
    f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:RegisterEvent("CHALLENGE_MODE_START")
    f:SetScript("OnEvent", function(_, event, unit, _, spellID)
        if event == "UNIT_SPELLCAST_SUCCEEDED" then
            pcall(Kicks.OnCast, unit, spellID)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            pcall(Kicks.OnInterrupted, unit)
        elseif event == "GROUP_ROSTER_UPDATE" then
            pcall(Kicks.OnRoster)
        else
            Kicks.Reset()
        end
    end)
end

-- For the harness.
function Kicks.__uses() return uses end
function Kicks.__known() return known end
function Kicks.__attribute(at) return Attribute(at) end
