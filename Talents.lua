-- RocketMeter | Talents.lua
-- Which talents of the player's build show up in the meter's numbers.
--
-- (!) WHAT CAN BE SAID, AND WHAT CANNOT (07/10). The user: *"se der até quais talentos de build
-- ajudou mais"*. The game gives an addon the player's own build (`C_ClassTalents`, `C_Traits`:
-- every node taken, with the spell it teaches) and, out of combat, the meter's numbers spell by
-- spell. Put together they answer ONE thing honestly: of the damage (or the healing) the meter
-- lists, how much came from a spell that a talent of this build teaches or is named after --
-- the talent that IS an ability, a proc or a damage-over-time effect of its own.
--
-- What no addon can measure is the talent that only makes another spell stronger ("X deals 10%
-- more damage"): the meter has one number per spell, not a number per cause. Those talents are
-- not in the list, and the section says so in its title ("direct"). Nothing is estimated.
--
-- A talent and the line of the meter are matched by spell id, and by NAME when the ids differ:
-- the spell a talent teaches and the spell that lands the damage are often two ids with one
-- name (the cast and its hit).
local ADDON, ns = ...

local Talents = {}
ns.Talents = Talents

local cache, cachedAt
local CACHE_SECONDS = 5

local function SpellName(spellID)
    if not (C_Spell and C_Spell.GetSpellName) or type(spellID) ~= "number" then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

---The talents of the active build that are taken: `{ byId = { [spellID] = true }, byName =
---{ [name] = spellID }, count = n }`. Empty when the game does not answer.
function Talents.Active()
    local now = GetTime and GetTime() or 0
    if cache and cachedAt and now - cachedAt < CACHE_SECONDS then return cache end
    local out = { byId = {}, byName = {}, count = 0 }
    pcall(function()
        if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return end
        local configID = C_ClassTalents.GetActiveConfigID()
        local config = configID and C_Traits.GetConfigInfo(configID)
        for _, treeID in ipairs(config and config.treeIDs or {}) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                local entryID = node and node.activeEntry and node.activeEntry.entryID
                if entryID and type(node.activeRank) == "number" and node.activeRank > 0 then
                    local entry = C_Traits.GetEntryInfo(configID, entryID)
                    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                    local spellID = def and (def.spellID or def.overriddenSpellID)
                    if type(spellID) == "number" then
                        local name = (type(def.overrideName) == "string" and def.overrideName ~= "" and def.overrideName)
                            or SpellName(spellID)
                        out.byId[spellID] = true
                        if name then out.byName[name] = spellID end
                        out.count = out.count + 1
                    end
                end
            end
        end
    end)
    cache, cachedAt = out, now
    return out
end

---Of the lines of a spell breakdown, the ones a talent of the build answers for.
---@param spells table[]|nil `{ spellID, amount, perSecond }`, as `ns.Data.GetSpellBreakdown` gives
---@return table[] rows the same shape, largest first
---@return number total their sum
function Talents.Of(spells)
    local active = Talents.Active()
    local rows, total = {}, 0
    if active.count == 0 then return rows, total end
    for _, spell in ipairs(spells or {}) do
        local id = spell.spellID
        local mine = active.byId[id]
        if not mine then
            local name = SpellName(id)
            mine = name ~= nil and active.byName[name] ~= nil
        end
        if mine and type(spell.amount) == "number" and spell.amount > 0 then
            rows[#rows + 1] = spell
            total = total + spell.amount
        end
    end
    table.sort(rows, function(a, b) return a.amount > b.amount end)
    return rows, total
end

-- For the harness.
function Talents.__reset() cache, cachedAt = nil, nil end
