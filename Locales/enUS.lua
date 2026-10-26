-- RocketMeter | Locales/enUS.lua
-- The localization base. This file ALWAYS loads, in any client language.
--
-- Two layers, in this order:
--
--   1. THE KEY IS THE ENGLISH TEXT. Without a translation, the key itself shows on screen -- so
--      English is the automatic fallback of every language that does not have a file here yet, with
--      no line of code for it.
--
--   2. `FROM_GAME` pulls from the client itself the labels Blizzard already translated. That holds
--      for the ~12 languages at once, and -- what matters more -- uses **the word the player
--      already reads in the game's interface**, not our version of it.
--
-- After this file the language's file loads (ptBR.lua), which overrides what it wants. The
-- final precedence is: our explicit choice > the game's word > the English key.
local ADDON, ns = ...

local L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

ns.L = L

--------------------------------------------------------------------------------
-- Labels the game already translated
--------------------------------------------------------------------------------
-- Blizzard's native meter has a global for EACH attribute this addon shows, and it is the
-- same data source (`C_DamageMeter`). The table below mirrors
-- `Blizzard_DamageMeter/DamageMeterSessionWindow.lua:34-46`:
--
--     local DAMAGE_METER_TYPE_NAMES = {
--         [Enum.DamageMeterType.DamageDone] = DAMAGE_METER_TYPE_DAMAGE_DONE,
--         [Enum.DamageMeterType.Dps]        = DAMAGE_METER_TYPE_DPS,
--         ...
--
-- ONLY LONG LABELS COME IN HERE (tooltip, title, button). The column headers stay
-- ours: they are ~50px wide, and "Dano evitável recebido" does not fit where "Evitáv" fits. Blizzard
-- has no short form of these names -- its meter shows one metric per window, we
-- show six columns. Where the global IS already short (DPS, HPS, Deaths), it comes in.
local FROM_GAME = {
    -- Metric names, from the native meter
    ["Total damage"]        = "DAMAGE_METER_TYPE_DAMAGE_DONE",
    ["Damage done"]         = "DAMAGE_METER_TYPE_DAMAGE_DONE",   -- (20/10) a aba do Meu combate: o "Damage Done" do Warcraft Logs
    ["Total healing"]       = "DAMAGE_METER_TYPE_HEALING_DONE",
    ["Absorbs"]             = "DAMAGE_METER_TYPE_ABSORBS",
    ["Damage taken"]        = "DAMAGE_METER_TYPE_DAMAGE_TAKEN",
    ["Avoidable damage"]    = "DAMAGE_METER_TYPE_AVOIDABLE_DAMAGE_TAKEN",
    ["Interrupts"]          = "DAMAGE_METER_TYPE_INTERRUPTS",
    ["Dispels"]             = "DAMAGE_METER_TYPE_DISPELS",
    ["Player deaths"]       = "DAMAGE_METER_TYPE_DEATHS",
    ["Damage on enemies"]   = "DAMAGE_METER_TYPE_ENEMY_DAMAGE_TAKEN",
    ["Damage per second"]   = "DAMAGE_PER_SECOND",

    -- A short header. Only a global that is short in all ELEVEN languages comes in -- see the note on
    -- DPS/HPS right below, which is the reason only this one is left.
    ["Deaths"]              = "DAMAGE_METER_TYPE_DEATHS",   -- max. 7 (esES)

    -- Sections of the per-spell breakdown
    ["Damage"]              = "DAMAGE_METER_CATEGORY_DAMAGE",
    ["Healing"]             = "DAMAGE_METER_CATEGORY_HEALING",

    -- (20/10) the combat log option's section: the game's own name (the chat tab)
    ["Combat log"]          = "COMBAT_LOG",

    -- (20/10) a linha de atributos do Resumo do Meu combate: a palavra da ficha do personagem do jogo
    ["Attributes"]          = "STAT_CATEGORY_ATTRIBUTES",

    -- Session, content and controls
    ["Overall"]             = "DAMAGE_METER_OVERALL_SESSION",
    ["Clear the data"]      = "DAMAGE_METER_RESET_ALL_SESSIONS",
    ["Lock position"]       = "DAMAGE_METER_LOCK_WINDOW",
    ["Configure"]           = "SETTINGS",
    ["in combat"]           = "HUD_EDIT_MODE_SETTING_DAMAGE_METER_VISIBILITY_IN_COMBAT",
    ["Mythic+"]             = "PLAYER_DIFFICULTY_MYTHIC_PLUS",
    ["Raid"]                = "RAID",
    ["Dungeon"]             = "LFG_TYPE_DUNGEON",
    ["defeated"]            = "BOSS_DEAD",
    ["version"]             = "GAME_VERSION_LABEL",
}

-- What did NOT come in, and why -- so nobody "fixes" it later without knowing:
--
--   "Current fight"  DAMAGE_METER_CURRENT_SESSION is "Segmento atual". "Combate atual" is
--                    clearer and was approved in-game over several rounds of visual tuning.
--   "Control"        DAMAGE_METER_CATEGORY_ACTIONS is "Ações", and Blizzard's group includes
--                    deaths; ours is interrupt + dispel. A different word, a different
--                    set -- swapping would change what the panel means.
--   "Score"          PROVING_GROUNDS_SCORE carries a built-in colon -- "Score:" in English and
--                    "Pontuação:" in Portuguese. A label with punctuation inside breaks the layout.
--   "Absorb"         ABSORB is "Absorver", 8 characters, in a ~58px header. It does not fit.
--   "Enemies"        SPELL_TARGET_TYPE13_DESC is "inimigos", lowercase and from another domain.
--   "Heal"           only exists in WOW_LABS_HEAL_TOOLTIP, from a game mode that may go away.
--
--   "DPS" and "HPS"  THIS IS THE CASE THAT TEACHES THE MOST, and I had already got it wrong here. In enUS and ptBR
--                    `DAMAGE_METER_TYPE_DPS` is the acronym "DPS", so the global looks perfect
--                    for the header. In the other nine languages it is NOT an acronym:
--
--                        deDE  "Schadensklassen"       15 characters -- and it means
--                                                      *damage classes*: the translator read DPS
--                                                      as a ROLE, not as a metric
--                        ruRU  "Бойцы"                 *fighters* -- the same mistake
--                        koKR  "초당 피해량"             a phrase, not an acronym
--
--                    `DAMAGE_METER_TYPE_HPS` likewise: esMX "Sanación por segundo" (20),
--                    ruRU "Ед. здоровья в сек." (19). The header is 58px.
--
--                    The lesson is not about these two globals: it is that **checking enUS and ptBR does not
--                    test a promise about eleven languages**. Every entry of this table was
--                    measured in the eleven, and the widths noted beside are the maximum found.
--
--   "version"        `VERSION` exists and the text is right, but it has `Flags=2` in the DB2 -- without the
--                    bit that ALL the other globals confirmed here carry -- and zero
--                    reads in the 12.1.0 source. Two independent
--                    signals that it does not become a Lua global. Replaced by
--                    `GAME_VERSION_LABEL` (Flags=1), the same text in the eleven languages.

ns.FROM_GAME = FROM_GAME

--- Does this global serve as a label?
---
--- Three guards, each one against a different failure:
---
---  * **not a string** -> the global does not exist in this client. This is the guard that **cannot**
---    be simplified: without it, `text:find` receives `nil` and **raises an error at file
---    load**. Since `ns.L` is born here, the whole addon dies with it -- it is not a blank
---    label, it is the whole screen. Locked by a test (sabotage verified: *"attempt to index
---    local 'text' (a nil value)"*).
---  * **empty string** -> it exists but has no text; it would become a blank label.
---  * **has `%s`/`%d`** -> it is a sentence template, not a label (`DAMAGE_METER_SOURCE_NAME` = `"%d. %s"`),
---    and would show raw on screen.
---
--- In all three cases the key is left alone and the English still holds. Worth noting that
--- `rawset(L, key, nil)` would be harmless by itself -- deleting the key returns it to `__index`; the
--- real danger is indexing the `nil`, not the hole in the table.
--- @return string|nil text, string|nil reason for refusal
local function Usable(tag)
    local text = _G[tag]
    if type(text) ~= "string" then return nil, "ausente" end
    if text == "" then return nil, "vazia" end
    if text:find("%%") then return nil, "modelo de frase" end
    return text
end

--- Writes the game's labels into `L`. It runs **once**, when this file loads, before the
--- language file -- which overrides what it wants afterwards.
function ns.ApplyGameStrings()
    for key, tag in pairs(FROM_GAME) do
        local text = Usable(tag)
        if text then
            rawset(L, key, text)
        end
    end
end

--- The report for `/rm i18n`. **Read only.**
---
--- It cannot apply anything: this command runs long after loading, and reapplying here would erase
--- the translations the language file wrote on top -- on a pt-BR client, "Absorções"
--- would become "Absorve" until the next `/reload`, with nobody understanding why.
--- @return table a list of { key, tag, text, why }, sorted by global
function ns.CheckGameStrings()
    local report = {}
    for key, tag in pairs(FROM_GAME) do
        local text, why = Usable(tag)
        report[#report + 1] = { key = key, tag = tag, text = text, why = why }
    end
    -- ⚑ THE TIE-BREAK BY KEY IS NOT DECORATION. `DAMAGE_METER_TYPE_DEATHS` is in `FROM_GAME`
    -- TWICE -- once for "Player deaths" and once for "Deaths" --, and a comparator that returns
    -- `false` for both leaves their order undefined: `table.sort` is not stable.
    --
    -- That looked harmless (the two lines say the same thing), and it was not: the output of `/rm
    -- i18n` changed order between runs, the harness prints it, and `sabotar.py` matches the output
    -- by TEXT to decide which check failed first. **A sabotage suite that changes its
    -- result without the code changing cannot tell "the test does not catch it" from "bad luck this time"** -- and it was
    -- exactly that symptom that showed up on 10/09/2026, with different sabotages failing at
    -- each round.
    table.sort(report, function(a, b)
        if a.tag ~= b.tag then return a.tag < b.tag end
        return a.key < b.key
    end)
    return report
end

ns.ApplyGameStrings()
