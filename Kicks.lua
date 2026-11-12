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
local history = {}                -- [token] = the times of its last casts (development probe only)
local lastChoice                  -- what Attribute decided last, for the probe
local noIconSeen = {}             -- [class/icon/reason] = true: each "no icon" reason logged once

local PROBE_SPAN = 1.5            -- (10/11) the probe writes every cast this close to an enemy's interruption
local HISTORY = 8

local function Probing() return ns.Log and ns.Log.enabled and ns.Log.Kick end

--------------------------------------------------------------------------------
-- (12/11) A CUT BY CROWD CONTROL IS NOT A KICK. The user: "se identificar com 100% de certeza que usou outra skill
-- para o interrupt, o icone da skill nativa de interrupt dele nao entra em CD". Checked against the combat log of a
-- key (11/11): of 18 teammate clocks the guess started, 13 were on the wrong one, many of them a stun or a fear that
-- cut the cast while the stunner "cast something" in that instant.
-- HOW: one hidden AuraContainer per enemy plate (nameplate1..40), HARMFUL, filtered by the marks a control leaves
-- (Data/CutMarks.lua). The game lets an addon filter an ENEMY's harmful auras by id, and the container grows when one
-- is there: `IsMouseOver` reads that geometry (the technique proven in a key on 11/11, 45 of 45 screenshots, workspace
-- skill wow-grupo-recargas). The answer is SECRET in combat: Lua never learns it. It goes straight to the screen --
-- C_CurveUtil.EvaluateColorValueFromBoolean picks the clock's alpha (0 with the mark) and the "ready" look (1 with
-- it) -- so a teammate cut by control keeps his interrupt shown as ready, and nothing else changes.
-- The interrupts whose own mark is the interrupt (Silence, Solar Beam, Avenger's Shield, Axe Toss) are not in the
-- list. Lost: the credit cannot go to the right one (Lua does not know), and the guessed teammate still counts as
-- "on cooldown" for the next guesses.
--------------------------------------------------------------------------------
local CUT_PLATES = 40
local WIDE = 50000
local E = C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean
local cutSensors = {}             -- [plate index] = container on nameplate<index>
local cutBuilt = false            -- tried (once: a failure is logged, not retried every interruption)
local cutPlate                    -- the plate of the interruption being attributed

local function Quiet(button)
    pcall(button.SetSize, button, 1, 1)
    pcall(button.SetAlpha, button, 0)
    pcall(button.EnableMouse, button, false)
end

---Builds the 40 sensors, out of combat (a container is not created in combat). Idempotent.
function Kicks.BuildCutSensors()
    if cutBuilt or not ns.CUT_MARKS or not E then return end
    if InCombatLockdown and InCombatLockdown() then return end
    cutBuilt = true
    if C_AddOns and C_AddOns.LoadAddOn then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
    local ids = {}
    for _, id in ipairs(ns.CUT_MARKS) do ids[id] = true end
    for i = 1, CUT_PLATES do
        local ok, c = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
        if not ok or not c then
            if ns.Log and ns.Log.Add then ns.Log.Add("kick-sensor", { erro = tostring(c), placa = i }) end
            return
        end
        c:SetSize(1, 1)
        c:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -11, 0)  -- one pixel wide, left of the screen
        pcall(c.EnableMouse, c, false)
        local okG, err = pcall(c.AddAuraGroup, c, "cut", "HARMFUL", {
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = ids },
            initializeFrame = Quiet,
            layout = { elementWidth = WIDE, elementHeight = 1, elementSpacing = 0, lineSpacing = 0 },
        })
        if not okG then
            if ns.Log and ns.Log.Add then ns.Log.Add("kick-sensor", { erro = tostring(err), placa = i }) end
            return
        end
        pcall(c.SetUnit, c, "nameplate" .. i)
        pcall(c.SetEnabled, c, true)
        pcall(c.UpdateAllAuras, c)
        cutSensors[i] = c
    end
end

local function PlateIndex(unit)
    return type(unit) == "string" and tonumber(unit:match("^nameplate(%d+)$")) or nil
end

---A plate came: its sensor reads the new enemy at once (proven in combat on 11/11).
function Kicks.OnPlate(unit)
    local c = cutSensors[PlateIndex(unit) or 0]
    if c then pcall(c.UpdateAllAuras, c) end
end

---"The interrupted enemy carries a control's mark": a boolean, SECRET in combat; nil when it cannot be read (no plate).
local function CutByControl()
    local c = cutSensors[cutPlate or 0]
    if not c then return nil end
    local ok, lit = pcall(c.IsMouseOver, c, 1e5, -1e5, 0, 0)
    if ok then return lit end
end

---(10/11) Why a row got no interrupt icon, once per class/icon/reason: in a key (10/11) a Retribution paladin and a
---Devourer demon hunter had none while both shamans and the mage had theirs. Development log only.
local function NoIcon(source, reason)
    if not Probing() then return end
    local class, icon = source.classFilename, source.specIconID
    class = Readable(class) and class or "SECRET"
    icon = Readable(icon) and icon or "SECRET"
    local key = tostring(class) .. "/" .. tostring(icon) .. "/" .. reason
    if noIconSeen[key] then return end
    noIconSeen[key] = true
    local name = source.name
    ns.Log.Kick("sem-icone", { classe = class, icone = icon, motivo = reason,
                               nomeLegivel = Readable(name) and true or false })
end

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
    -- (11/11) built again while empty: asked before the game has the classes, an empty table would stay for the session
    if not specByIcon or next(specByIcon) == nil then
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
    if not token then
        -- (11/11) NO TOKEN, THE ICON STAYS, WITHOUT A CLOCK. The user, after a key: "depois do /reload o icone do
        -- paladino sumiu" -- the paladin had LEFT the group (the Radar's diary: his frame gone at 20:10:49), and the
        -- key's rows stay on the meter. Two of a class is the same case. The row's specialization still tells which
        -- interrupt it is; only whether it is ready cannot be known, so neither clock nor the "ready" frame.
        local icon = source.specIconID
        local specID = Readable(icon) and SpecByIcon(icon) or nil
        local spell = Kicks.SpellForSpec(specID, kind)
        if not (spell and Spells(kind)[spell]) then NoIcon(source, "sem token"); return nil end
        return { spell = spell, state = "unknown",
                 icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell) or nil }
    end
    local spell
    if token == "player" then
        spell = PlayerSpell(kind)
    else
        local icon = source.specIconID
        local specID = Readable(icon) and SpecByIcon(icon) or nil
        spell = Kicks.SpellForSpec(specID, kind)
        -- a spec with no interrupt (Holy, Discipline) is remembered as such: it cannot be the one who kicked
        if specID then known[kind][token] = spell or false end
        if not specID then NoIcon(source, "especializacao nao achada pelo icone") end
    end
    local k = spell and Spells(kind)[spell]
    if not k then
        NoIcon(source, spell and ("magia " .. spell .. " fora da tabela") or ("sem interrupt (" .. token .. ")"))
        return nil
    end
    local out = { spell = spell, token = token,
                  icon = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spell) or nil }
    local u = uses[kind][token]
    if u and Now() < u.at + k.cd then
        out.state, out.start, out.duration, out.veto = "cooldown", u.at, k.cd, u.veto
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

local function Use(kind, token, spell, how, veto)
    uses[kind][token] = { at = Now(), spell = spell, veto = veto }
    if ns.Log and ns.Log.Add then
        local marca = veto == nil and "-" or (issecretvalue(veto) and "secreta" or tostring(veto))
        ns.Log.Add("kick", { tipo = kind, quem = token, magia = spell, como = how, placa = cutPlate, marca = marca })
    end
    -- development: a screenshot of the meter a moment later, to check the veto against the combat log
    if veto ~= nil and Probing() and ns.DevShot then pcall(ns.DevShot, "kick-veto") end
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
            lastChoice = token .. " (lido)"
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
        if spell then Use("kick", found, spell, "correlacao", CutByControl()) end
    end
    lastChoice = (found or "ninguem") .. " [" .. table.concat(candidates, ",") .. "]"
    if ns.Log and ns.Log.Add then
        ns.Log.Add("kick-correlacao", { candidatos = table.concat(candidates, ","), escolhido = found or "ninguem" })
    end
end

---(10/11) THE PROBE OF ONE INTERRUPTION, written 1.5 s after it: every group member's casts within 1.5 s of it, as
---"party2(PALADIN) -0.31 +0.05". It answers what the empty candidate lists could not: do the teammates' casts come
---at all near an interruption, how far from it, and how many at once (the window is -0.4 to +0.15 s).
local function Probe(at)
    if not Probing() then return end
    local parts, near = {}, 0
    for _, t in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
        if UnitExists and UnitExists(t) then
            local deltas = {}
            for _, c in ipairs(history[t] or {}) do
                if c >= at - PROBE_SPAN and c <= at + PROBE_SPAN then
                    deltas[#deltas + 1] = string.format("%+.2f", c - at)
                    if c >= at - WINDOW_BEFORE and c <= at + WINDOW_AFTER then near = near + 1 end
                end
            end
            parts[#parts + 1] = t .. "(" .. (ClassOf(t) or "?") .. ") " .. (#deltas > 0 and table.concat(deltas, " ") or "-")
        end
    end
    ns.Log.Kick("corte", { lancamentos = table.concat(parts, " | "), naJanela = near, escolhido = lastChoice or "?" })
end

function Kicks.OnCast(unit, spellID)
    local owner = FRIENDLY[unit]
    if not owner then return end
    lastCast[owner] = Now()
    if Probing() then
        local h = history[owner] or {}
        history[owner] = h
        h[#h + 1] = lastCast[owner]
        while #h > HISTORY do table.remove(h, 1) end
    end
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
    local plate = PlateIndex(unit)
    if at - lastInterrupt < SAME_INTERRUPT then
        -- the same interruption through another token (target first, its plate after): keep the plate
        if plate and not cutPlate then cutPlate = plate end
        return
    end
    lastInterrupt = at
    if not pending then cutPlate = plate end
    if Probing() and C_Timer and C_Timer.After then
        C_Timer.After(PROBE_SPAN, function() pcall(Probe, at) end)
    end
    if pending then return end
    pending = true
    if C_Timer and C_Timer.After then C_Timer.After(WINDOW_AFTER, function() Attribute(at) end) else Attribute(at) end
end

function Kicks.Reset()
    uses, lastCast, pending, history = { kick = {} }, {}, false, {}
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
    f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    Kicks.BuildCutSensors()
    f:SetScript("OnEvent", ns.Timed("kicks", function(_, event, unit, _, spellID)
        if event == "NAME_PLATE_UNIT_ADDED" then
            pcall(Kicks.OnPlate, unit)
        elseif event == "PLAYER_ENTERING_WORLD" or event == "PLAYER_REGEN_ENABLED" then
            pcall(Kicks.BuildCutSensors)
        elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
            pcall(Kicks.OnCast, unit, spellID)
        elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
            pcall(Kicks.OnInterrupted, unit)
        elseif event == "GROUP_ROSTER_UPDATE" then
            pcall(Kicks.OnRoster)
        else
            Kicks.Reset()
        end
    end))
end

-- For the harness.
function Kicks.__uses() return uses end
function Kicks.__known() return known end
function Kicks.__forgetSpecs() specByIcon = nil end
function Kicks.__attribute(at) return Attribute(at) end
function Kicks.__cutSensors() return cutSensors end
function Kicks.__setCurve(f) E = f end
function Kicks.__rebuildCut() cutBuilt = false; cutSensors = {} end
