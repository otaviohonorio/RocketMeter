-- RocketMeter | Scoreboard.lua
-- The end-of-Mythic+ and raid encounter summary.
--
-- Here the density is different: the run is over, nobody is fighting, and the screen can breathe.
-- A tall row with the specialization icon and a bar in the class colour, a header with the key level's
-- star, a footer with the run's timeline. It closes only on the X -- ESC does not close it.
--
-- WHERE THE LOOK COMES FROM. The reference is Blizzard's official end-of-M+ panel, and its art
-- was surveyed in the client's own textures. Three decisions came from that reading,
-- against what I would have done by guess:
--
--   1. **No gold frame.** Nine-slice (`DialogBorderTemplate` and relatives) is nice on a
--      narrow dialog box; on a wide panel it throws all the visual weight to the edges and
--      fights the rows' class colour. The reference panel uses a dark corner and no
--      border, and that is why it reads as modern Blizzard instead of 2008 Blizzard.
--   2. **`Fillagree` with two L's.** It is Blizzard's own typo in the atlas's name.
--      `BossBanner-LeftFiligree` fails silently -- nothing shows and nothing warns.
--   3. **There is no "+1/+2/+3" atlas.** The official panel solves it with text, and so
--      do we.
--
-- SILENCE IS THE FAILURE MODE. `SetAtlas` with a name that does not exist raises no error: the texture
-- simply does not draw. Every atlas here goes through `Atlas()`, which asks
-- `C_Texture.GetAtlasInfo` FIRST and returns false for whoever wants a plan B. `/rm atlas`
-- prints the whole resolved list, so the doubt dies with data instead of a theory.
local ADDON, ns = ...
local L = ns.L

local Scoreboard = {}
ns.Scoreboard = Scoreboard

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------
-- EVERY NUMBER OF THIS BLOCK IS A MEASURE, not an estimate. The source of truth is the measure, not
-- taste. What each number measures goes in the comment, because a number with no provenance is a number
-- the next round "fixes" by eye.
--
-- What was left out, and why, is in `ALL_COLUMNS`'s header.
local ROW_HEIGHT = 46            -- the row's height
local ROW_SPACING = 1            -- 1px between one row and the next
local LINE_INSET = 2             -- recuo da linha dentro do painel
local SIDE = 5                   -- margem lateral do painel
local HEADER_HEIGHT = 65         -- the rows start 65 below the top
-- (!) TWO LINES (30/09): the header carries the family's name
-- on the first line and the part of each column on the second ("Damage" over "per s" and
-- "total"), so 2 x 16. The user, on "Interr - Missed - CC" in one line: *"só errou na coluna
-- é confuso (...) só se tu montar uma coluna com dois valores um titulo e sub titulo"*.
local COLHEAD_HEIGHT = 32
local COLHEAD_LINE = 16
local COL_PADDING = 2            -- respiro entre colunas
-- THE FOOTER CLOSES THE SUM OF THE PANEL'S HEIGHT (14/10: the column header is 32 today):
--   65 (header) + 32 (columns) + 5 × 47 (rows) + 132 = 464.
-- It is big because the time axis does not come glued to the rows: the rows
-- end at −321 and the axis only starts at −385. Those 64px of breathing room are what
-- separates the table from the chart -- without them the axis reads as one more row of the table.
local FOOTER_HEIGHT = 132
local MAX_ROWS = 20

-- The portrait, the role icon and the item level inside the portrait column
local PORTRAIT_INSET = 2         -- recuo do retrato dentro da linha
local ROLE_SIZE = 18             -- role icon 18x18
local ROLE_X, ROLE_Y = -9, -2    -- ancorado em `bottomright` do retrato
local ILVL_FONT = 11
local ILVL_BG_HEIGHT = 14
local ILVL_BG_INSET = 7
local SPEC_ICON = 20             -- specialization icon 20x20
local KEYSTONE_ICON = 45         -- lado do quadro da pedra
local KEYSTONE_FONT = 12
-- The game's own: icon of 50 in a frame of 52 (Blizzard_ChallengesUI.xml), at our 45.
local KEYSTONE_INNER = math.floor(KEYSTONE_ICON * 50 / 52 + 0.5)
local KEYSTONE_FRAME_ATLAS = "ChallengeMode-DungeonIconFrame"
-- What the game shows for a dungeon with no icon (Blizzard_ChallengesUI.lua, `SetUp`).
local KEYSTONE_NO_ART = "Interface\\Icons\\achievement_bg_wineos_underxminutes"
local LOOT_ICON = 32             -- loot icon 32x32

-- The rows' alternating background. White at 5% and at 10% OVER the panel's background -- it is not
-- black on black: the difference between the two rows is clear even with the dungeon's art
-- showing behind, which is the real case.
local ROW_TINT_ODD = { 1, 1, 1, 0.10 }
local ROW_TINT_EVEN = { 1, 1, 1, 0.05 }

-- A column header: a cell with its own background, white text at 10.
local COLHEAD_TINT = { 0, 0, 0, 0.5 }
local COLHEAD_TINT_SORTED = { 0.3, 0.3, 0.3, 0.5 }

local TITLE_Y = -12              -- nome da masmorra, 12 abaixo do topo

-- ⚑ THE SIZES WENT UP 2, by request (*"aumente só um pouco a fonte"*, 10/09/2026). And they ALL went up
-- together, on purpose: the header's hierarchy is the ratio between them (20/16/11 ≈ 1.8 and 1.45), and
-- growing one alone would flatten it. With +2 it becomes 22/18/13, and the ratios become 1.22 and 1.38 -- closer
-- to each other, which is the effect of enlarging everything; what cannot happen is inverting, and it does not invert.
--
-- The time is what gains most in relative presence, and that is intended: it stopped being the
-- title's second line and became the right-hand block, where it has to hold up alone.
local TITLE_SIZE = 22            -- era 20
local CLOCK_SIZE = 18            -- era 16
local IDLE_SIZE = 13             -- era 11

-- The right-hand block: the time starts at the same height as the title, and the result 2px below it.
-- The 2 are the same `GAP_LABEL` that glues a label to a control on the settings screen -- here the
-- result is the time's caption, and a caption lives glued to what it describes.
local CLOCK_Y = -14
local RESULT_GAP = -2
local RESULT_SIZE = 13           -- legenda do tempo: mesmo corpo da faixa de contexto

-- ⚑ HOW FAR THE RIGHT-HAND BLOCK COMES IN. In 0.85.0 it was born at 29 (the panel's margin
-- plus a breathing room) and sat glued to the edge -- *"o tempo à direita ficou muito à direita... deixando
-- ele à direita, mas não tão à direita"* (10/09/2026).
--
-- 65 is not a number picked by eye: it is the width of a count column (**60**) plus the
-- panel's side margin (**5**). With it the block sits **over the last column** instead of
-- hanging in the corner -- that is, aligned to an edge that already exists on screen, and not to an
-- invented distance. If the columns' width changes, this number has a place to come from.
local CLOCK_RIGHT_INSET = 65

-- The key level's star: 100x100 centred at ("center", frame, "top", 0, 27). The numbers
-- were measured against the official panel -- kept, not recalibrated.
local STAR_SIZE = 100
local STAR_OFFSET_Y = 27
local FILIGREE_SIDE_W, FILIGREE_SIDE_H = 72, 43
local FILIGREE_SIDE_X = 50
local FILIGREE_BOTTOM_W, FILIGREE_BOTTOM_H = 66, 28
local FILIGREE_BOTTOM_Y = -19

-- The timeline: a 4px rail, boss markers above, deaths below, the axis last.
local RAIL_HEIGHT = 4
local BOSS_ICON = 18
local DEATH_ICON = 11
local CHEST_ICON = 26            -- native 257x226 scaled; here only the height matters
-- THE CLASS STRIP AT THE FOOT OF THE ROW WENT AWAY (it was `BAR_STRIP_HEIGHT`/`BAR_ALPHA`), and with it the
-- damage scale it drew: on an end-of-run scoreboard the comparison is made reading the
-- column, not measuring bars -- and the class's identity stays in three places on the same row (portrait,
-- specialization icon and the name's colour).

-- Every atlas the panel uses, in one place, so `/rm atlas` checks the whole list at
-- once instead of finding one broken name per test round.
ns.SCOREBOARD_ATLASES = {
    "ChallengeMode-SpikeyStar",
    "BossBanner-LeftFillagree",
    "BossBanner-RightFillagree",
    "BossBanner-BottomFillagree",
    "BossBanner-SkullCircle",
    "gficon-chest-evergreen-greatvault-collect",
    "gficon-chest-evergreen-greatvault-complete",
    "worldquest-icon-boss",
    "roleicon-tiny-tank",
    "roleicon-tiny-healer",
    "roleicon-tiny-dps",
    "ui-damagemeters-header-bar",
    "common-icon-redx",
    -- The window header's unlocked padlock (0.55.0). It comes in here because `/rm atlas` is the
    -- only way to know whether it exists: `SetAtlas` with an invalid name fails silently.
    "common-icon-move",
    -- The Mythic+ scoreboard (0.66.0). All checked in the
    -- 12.1.0 source before coming in; they stay here because `/rm atlas` is the only way to find out that one
    -- of them stopped existing in a patch -- `SetAtlas` with a dead name warns nothing.
    "auctionhouse-icon-clock",                    -- tempo fora de combate
    "bags-icon-equipment",                        -- nivel de item medio
    "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",     -- TextureUtil.lua:187-189
    "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
    "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
    "loottoast-itemborder-white",                 -- ColorConstants.lua:63-70
    "loottoast-itemborder-green",
    "loottoast-itemborder-blue",
    "loottoast-itemborder-purple",
    "loottoast-itemborder-orange",
}

--------------------------------------------------------------------------------
-- Colunas
--------------------------------------------------------------------------------
-- THE COLUMNS, IN THE ORDER AND WIDTH OF 0.66.0:
--
--   portrait 60 · specialization 25 · name 110 · keystone 60 · score 90 ·
--   loot 80 · deaths 80 · avoidable damage 80 · damage taken 100 · DPS 100 · HPS 100 ·
--   interrupts 100 · dispels 80
--
-- ⚠️ **LIKES DO NOT COME IN, and it is not laziness.** A "gg" between players would need an
-- addon channel of its own, and only whoever runs the same addon would answer. A RocketMeter with
-- that column would show **0** forever, on every row, for everyone: a
-- column that can only lie takes space and teaches the player to distrust the rest of the screen.
--
-- `render` marks the column that draws something that is not a number; without it, it is a numeric cell and the
-- short label and the format come from `Data.lua`'s catalogue, with no copy. `custom` marks the ones
-- `C_DamageMeter` does not know and the scoreboard fills on its own.
local ALL_COLUMNS = {
    { key = "portrait",   width = 60,  render = "portrait", custom = true, label = "" },
    { key = "spec",       width = 25,  render = "spec",     custom = true, label = "" },
    { key = "name",       width = 110, render = "name",     custom = true, label = "" },
    { key = "keystone",   width = 60,  render = "keystone", custom = true, label = L["Keystone"] },
    { key = "score",      width = 90,  render = "score",    custom = true, label = L["Score"] },
    { key = "loot",       width = 80,  render = "loot",     custom = true, label = L["Loot"] },

    -- ⚑ FROM HERE DOWN THE ORDER AND THE WIDTHS ARE THE USER'S DECISION (10/09/2026), not
    -- carelessness: *"tá faltando o total de dano e total de cura, e vamos ordenar
    -- isso, depois da coluna saque, vem o DPS, Dano, CPS, Cura, Interrupts, Disspel, Mortes,
    -- Evitavel, Recebido, pode diminuir só um pouco a largura das colunas"*.
    --
    -- The six above (portrait, spec, name, keystone, score, loot) stay as they were:
    -- they are identity and Mythic+.
    --
    -- THE ORDER HAS A LOGIC, and it matches the combat window's: **the rate comes before the
    -- total**, because the rate is the main reading and the total is its context -- the same decision
    -- that inverted the pair's brightness in 0.82.0. Then come the counts, and last the damage
    -- taken, which is what is least looked at at the end of a key.
    --
    -- THE WIDTHS go down in two steps, not one: a value metric (damage, healing, DPS, HPS,
    -- taken, avoidable) stays at **84**, and a COUNT metric (interrupts, dispels,
    -- deaths) at **60**. A count writes "7", not "44.4M" -- giving it the same box was what
    -- made the table look empty on the right. The floor of 60 is the label: "Dissip" and "Mortes"
    -- have to fit in the header, or the column loses its name.
    { key = "dps",        width = 84 },
    { key = "damage",     width = 84 },
    { key = "hps",        width = 84 },
    { key = "healing",    width = 84 },
    { key = "interrupts", width = 60 },
    { key = "dispels",    width = 60 },
    { key = "deaths",     width = 60 },
    { key = "avoidable",  width = 84 },
    { key = "taken",      width = 84 },
}

local DEFAULT_SORT = "dps"

-- The columns VISIBLE in this run. The catalogue above is fixed; this list is recomputed at every
-- drawing because a raid scoreboard has no Mythic+ score -- showing the column empty (or
-- worse, with each one's M+ score beside the damage on a raid boss) is noise that looks
-- like data. The whole rest of the file reads from here, never from the catalogue.
local columns = ALL_COLUMNS

local frame, headerRow, rows, timeline
local sortBy, sortDesc = DEFAULT_SORT, true
local context                -- the run on screen

--- Is the run on screen a Mythic+ key? The raid scoreboard has no level, no affixes, no
--- chest, no time axis -- and showing those pieces empty around a dead boss is worse than
--- showing nothing. `level` is what separates the two cases.
local function IsKeystone()
    return context ~= nil and context.level ~= nil
end

--- Recomputes which columns show.
---
--- Outside a key the three that only exist in Mythic+ go -- keystone, score and loot. The
--- other `custom` ones (portrait, specialization, name) hold on any scoreboard and stay: a raid
--- scoreboard without the name column would be a table of numbers with no owner.
local KEYSTONE_ONLY = { keystone = true, score = true, loot = true }

local function ComputeColumns()
    if IsKeystone() then return ALL_COLUMNS end

    local out = {}
    for c = 1, #ALL_COLUMNS do
        if not KEYSTONE_ONLY[ALL_COLUMNS[c].key] then out[#out + 1] = ALL_COLUMNS[c] end
    end
    return out
end

--- The footer's height. Without a timeline it does not need the 66px -- they would be left as an
--- empty gap under the rows, the kind of space reserved for nothing that makes a window
--- look broken.
local function FooterHeight()
    return IsKeystone() and FOOTER_HEIGHT or 20
end

local function ColumnLabel(column)
    if column.label then return column.label end
    return ns.Data.GetShortLabel(column.key)
end

---The header's groups: consecutive columns of the same family (`group` in the catalogue). A
---custom column is a group by itself.
---@return table[] { first, last, label }
local function HeaderGroups()
    local groups = {}
    for c = 1, #columns do
        local column = columns[c]
        local def = not column.custom and ns.Data.GetColumn(column.key) or nil
        local key = def and def.group or nil
        local last = groups[#groups]
        if key ~= nil and last and last.key == key and last.last == c - 1 then
            last.last = c
        else
            groups[#groups + 1] = { first = c, last = c, key = key,
                label = def and def.family or ColumnLabel(column) }
        end
    end
    return groups
end

--- Each column's LEFT edge, and the total width.
---
--- From left to right, and this is the 180° turn of 0.66.0: the old scoreboard
--- stacked the columns from the RIGHT EDGE, with a fixed name block on the left. Now
--- each column starts where the previous one ended, plus the breathing room
--- (`COL_PADDING`), and the cell's content aligns to its left. Name and portrait stop
--- being an exception and become two columns like the others.
local function ColumnOffsets()
    local offsets, x = {}, 0
    for c = 1, #columns do
        offsets[c] = x
        x = x + columns[c].width + COL_PADDING
    end
    return offsets, x
end

local function PanelWidth()
    local _, columnsWidth = ColumnOffsets()
    return SIDE * 2 + columnsWidth
end

local function PanelHeight(rowCount)
    return HEADER_HEIGHT + COLHEAD_HEIGHT
        + rowCount * (ROW_HEIGHT + ROW_SPACING)
        + FooterHeight()
end

--- How many rows fit on the screen. A 20-person raid would give 866px of panel plus the star
--- on top: on a 1080 screen with the default UI scale the footer goes out at the bottom and the user
--- has no way to drag back what is outside. The floor of 3 exists for the case of the
--- UIParent's height coming odd -- better a small panel than a one-row panel.
local function MaxRowsOnScreen()
    local screen = UIParent and UIParent:GetHeight()
    if not screen or screen <= 0 then return MAX_ROWS end

    local free = screen - 160 - HEADER_HEIGHT - COLHEAD_HEIGHT - FooterHeight()
    local fits = math.floor(free / (ROW_HEIGHT + ROW_SPACING))
    if fits < 3 then fits = 3 end
    if fits > MAX_ROWS then fits = MAX_ROWS end
    return fits
end

--------------------------------------------------------------------------------
-- Art, with the silence worked around
--------------------------------------------------------------------------------
--- Applies an atlas only if it exists in this client.
---
--- `SetAtlas` with a wrong name raises no error nor returns anything -- the texture stays empty and the bug
--- shows weeks later as "that corner looks odd". Asking `GetAtlasInfo` first is
--- what allows a plan B.
--- @return boolean applied
local function Atlas(texture, name)
    if not texture or not name then return false end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    if not info then return false end
    texture:SetAtlas(name)
    return true
end

local ROLE_ATLAS = {
    TANK = "roleicon-tiny-tank",
    HEALER = "roleicon-tiny-healer",
    DAMAGER = "roleicon-tiny-dps",
}

--- A player's role (tank / healer / damage), by name.
---
--- The meter does not give the role, and without this the icon only showed in the SIMULATION -- in the real run
--- each row stayed with 19px empty on the left, which makes the panel look misaligned without
--- anyone being able to say why. Sweeping the group's units is cheap (40 calls at most) and
--- does not depend on inspection nor on communication between addons.
---
--- `UnitName` stays readable in combat (identity is not secret by default), but the client
--- can hide it case by case -- hence the check before comparing.
local function RoleFor(name)
    if name == nil or issecretvalue(name) or type(name) ~= "string" then return nil end
    if not UnitGroupRolesAssigned or not UnitName then return nil end

    local wanted = ns.SplitName(name)
    local size = GetNumGroupMembers() or 0

    local units = {}
    if IsInRaid and IsInRaid() then
        for i = 1, size do units[i] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, math.max(0, size - 1) do units[i + 1] = "party" .. i end
    end

    for i = 1, #units do
        local unitName = UnitName(units[i])
        if unitName ~= nil and not issecretvalue(unitName) and unitName == wanted then
            local role = UnitGroupRolesAssigned(units[i])
            if role and role ~= "NONE" then return role end
            return nil
        end
    end
    return nil
end

--- The panel's background: the dungeon's own art, desaturated and faded.
---
--- `GetMapUIInfo`'s 5th return is the dungeon's `backgroundTexture` -- it works for any
--- dungeon, present or future, with no table tied to a season (the other way out, a folder
--- of `.jpg` per dungeon, stops covering the season as soon as it changes). With no mapID -- which is the
--- simulation's case -- there is simply no background, and the panel stays on the plain dark.
local function ApplyBackdropArt(texture, mapID)
    texture:SetTexture(nil)
    if not mapID or not C_ChallengeMode or not C_ChallengeMode.GetMapUIInfo then return false end

    local ok, _, _, _, _, background = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
    if not ok or not background then return false end

    texture:SetTexture(background)
    texture:SetDesaturation(0.5)
    texture:SetAlpha(0.16)
    return true
end

--------------------------------------------------------------------------------
-- Dados
--------------------------------------------------------------------------------
--- A player's M+ score by name.
---
--- `GetPlayerMythicPlusRatingSummary` accepts a name or a unit token; the scoreboard only has the name the
--- meter returned. In combat the identity can be secret, and then there is nothing to look up --
--- hence the `pcall` and the check: the scoreboard shows after the run, but the user can
--- reopen it in the middle of another fight.
local function ScoreFor(name)
    if name == nil or issecretvalue(name) then return nil end
    if not C_PlayerInfo or not C_PlayerInfo.GetPlayerMythicPlusRatingSummary then return nil end

    local ok, summary = pcall(C_PlayerInfo.GetPlayerMythicPlusRatingSummary, name)
    if not ok or type(summary) ~= "table" then return nil end
    return summary.currentSeasonScore
end

--- Normalises the rows so that `values[c]` always matches `columns[c]`.
---
--- `Data.GetRows` only knows meter columns, so it gets the sublist and returns values
--- indexed by it. Remapping here is what lets the drawing have one path only, holding
--- the same for a real run and for the simulation -- two drawing paths drift apart at the third
--- change, and the project already paid for that once.
--------------------------------------------------------------------------------
-- The run's picture: from the live session to data that can be saved
--------------------------------------------------------------------------------
--- Every column key a picture keeps.
---
--- It keeps the WHOLE catalogue, not only what is visible: whoever opens the run a
--- week from now may have changed the columns, and a picture that only saved what was on screen that
--- day forces the answer "I do not have that data". Saving everything costs eight numbers per player.
local function SnapshotKeys()
    local keys = {}
    for c = 1, #ALL_COLUMNS do
        if not ALL_COLUMNS[c].custom then keys[#keys + 1] = ALL_COLUMNS[c].key end
    end
    return keys
end

--- A number that can go to disk, or nil.
---
--- A secret value **cannot be serialised** -- it is an explicit Midnight rule, and trying to write it
--- to the SavedVariables is an error. Here it simply does not go in: the cell stays empty in the picture,
--- which is honest, instead of saving garbage or bringing the capture down.
local function Storable(value)
    if value == nil or issecretvalue(value) then return nil end
    if type(value) ~= "number" then return nil end
    return value
end

--- Copies the live session into a loose table, ready to draw and to save.
--- @param base table the run's context (title, time, affixes, timeline...)
--- @return table picture
function Scoreboard.Snapshot(base)
    local keys = SnapshotKeys()
    local data = ns.Data.GetRows(base.sessionType or 1, DEFAULT_SORT, keys, MAX_ROWS, false)

    local rows = {}
    for i = 1, (data and #data or 0) do
        local source = data[i].source
        local name = source.name
        if issecretvalue(name) then name = nil end

        local values = {}
        for k = 1, #keys do
            values[keys[k]] = Storable(data[i].values[k])
        end
        if base.kind == "mplus" then
            values.score = Storable(ScoreFor(source.name))
        end

        local classFilename = source.classFilename
        if issecretvalue(classFilename) then classFilename = nil end
        local specIconID = source.specIconID
        if issecretvalue(specIconID) then specIconID = nil end
        local isLocal = source.isLocalPlayer
        isLocal = isLocal ~= nil and not issecretvalue(isLocal) and isLocal == true

        -- WHAT THE METER DOES NOT KNOW travels in the picture with the rest: item level, keystone and
        -- loot. It has to be HERE, at the moment of capture -- a run reopened next
        -- week no longer has a group to inspect nor a loot event to hear.
        local ilevel, keystoneLevel, keystoneMapID, gotLoot
        if ns.Party then
            ilevel = ns.Party.ItemLevel(source.name)
            keystoneLevel, keystoneMapID = ns.Party.Keystone(source.name)
            gotLoot = ns.Party.Loot(source.name)
        end

        rows[i] = {
            name = name or (UNKNOWN or "?"),
            classFilename = classFilename,
            specIconID = specIconID,
            role = RoleFor(source.name),
            isLocalPlayer = isLocal,
            scoreGain = isLocal and base.scoreGain or nil,
            ilevel = ilevel,
            keystoneLevel = keystoneLevel,
            keystoneMapID = keystoneMapID,
            loot = gotLoot,
            values = values,
        }
    end

    base.rows = rows
    base.recordedAt = time and time() or nil
    return base
end

--------------------------------------------------------------------------------
-- Corridas guardadas
--------------------------------------------------------------------------------
--- Where the runs live.
---
--- A SavedVariable OF ITS OWN, per character, outside `ns.db`: `Profile.Reset()` erases everything
--- in the settings, and "restore defaults" cannot mean "lose the runs". Besides,
--- the run belongs to the character who made it, not to the account.
local function Store()
    if RocketMeterRunsDB == nil then RocketMeterRunsDB = {} end
    return RocketMeterRunsDB
end

function Scoreboard.SaveRun(kind, snapshot)
    if not kind or not snapshot then return end
    Store()[kind] = snapshot
end

function Scoreboard.GetRun(kind)
    local run = Store()[kind]
    if type(run) ~= "table" or type(run.rows) ~= "table" or #run.rows == 0 then return nil end
    return run
end

--- Puts the CLASS on each death marker of the timeline -- when it can be proven which.
---
--- The request of 10/09/2026: *"a outra marcação é a morte, poderia ter o ícone da classe que morreu"*.
---
--- ⚑ THERE ARE TWO SOURCES AND NEITHER ALONE ANSWERS. `Run` knows **when** each death
--- happened, on the key's clock, but its event does not say **who**. The meter's deaths metric
--- knows **who** (one entry per death, with the class), but its clock is
--- `deathTimeSeconds`, and from here there is no confirming where it counts from.
---
--- So the clocks are not mixed: `Run` still places, and the meter's list only lends the
--- class **in order**. And that is only honest under a condition that can be checked at
--- run time: **the two lists having the same size**. If they do, each death of the meter matches
--- the marker in the same position. If not, one of the two saw something the other did not, the
--- match by order becomes a guess, and the marker stays the usual skull.
---
--- It is the difference between an icon that may be wrong and an icon that only shows when it is right.
local function AttachDeathClasses(base)
    local marks = base.deathMarks
    if type(marks) ~= "table" or #marks == 0 then return end
    if not ns.Data or not ns.Data.GetDeathList then return end

    local obitos = ns.Data.GetDeathList(base.sessionType or 1)

    if #obitos ~= #marks then
        if ns.Log then
            ns.Log.Add("mortes", {
                marcadores = #marks, medidor = #obitos,
                decisao = "contagens diferentes; marcador fica sem classe",
            })
        end
        return
    end

    -- (14/10) THE METER'S LIST IS NOT IN THE ORDER THE DEATHS HAPPENED: a real key (13 marks, 13
    -- entries) had one player's three deaths at 1649/1650/1653 s listed apart. Its own clock
    -- (`deathTimeSeconds`) ORDERS its entries — only among themselves; the marks keep the run's
    -- clock. Without every time readable there is no order to trust, and the marks stay plain.
    local ordem = {}
    for i, o in ipairs(obitos) do
        if type(o.quando) ~= "number" then return end
        ordem[i] = { o = o, i = i }
    end
    table.sort(ordem, function(a, b)
        if a.o.quando ~= b.o.quando then return a.o.quando < b.o.quando end
        return a.i < b.i
    end)
    for i = 1, #marks do
        marks[i][2] = ordem[i].o.classe
        marks[i][3] = ordem[i].o.nome
    end

    if ns.Log then
        ns.Log.Add("mortes", { marcadores = #marks, decisao = "classe casada por ordem" })
    end
end

--- The loot arrived AFTER the capture. Stitches it into the run already pictured.
---
--- ⚑ THIS IS THE DEFECT OF THE PRINT OF 10/09, and the user's log dated it with no doubt left:
---
---    00:33:16  snapshot  end of combat
---    00:33:18  raw loot  Kankerlekker  (discarded: neither weapon nor armour)
---    00:33:20  loot      Gsm
---    00:33:30  loot      Dauð
---
--- `Scoreboard.OnChallengeCompleted` runs **1.5 s** after `CHALLENGE_MODE_COMPLETED` -- that is,
--- around 00:33:18. Gsm's loot arrived 2 s later and the player's own **12 s** later.
--- The column was captured empty and never looked back; that is why it was empty for
--- **everyone**, including whoever opened the panel and knew he had won an item.
---
--- Waiting longer before capturing does not solve it: there is no guaranteed deadline for the last item to drop, and
--- any number chosen here would be a guess. Stitching afterwards solves it for any delay.
---
--- It touches BOTH places where the run exists, and that is why the function is one: the picture in
--- memory (what is on screen) and the one saved on disk (what `/rm score` reopens tomorrow).
---
--- ⚑ AND THE DRAWING DOES NOT UPDATE BY ITSELF -- what repaints is `Scoreboard.Refresh`, called at the end.
--- `Scoreboard.Refresh`, and not the local `SafeDraw`: it is only declared 1200 lines below here, and a
--- `local` referenced before its declaration becomes a global lookup -- `nil` at call time.
-- ⚑ A REDRAW CANNOT HAPPEN INSIDE A REDRAW, and this was born from a real defect:
-- `ReencostarAteCompletar` calls `RefreshExternalColumns`, which calls `Scoreboard.Refresh`. With the
-- simulator's timer running the callback **inside** whoever scheduled it (the game's does not do that), the
-- chain became 24 drawings stacked, one over the other, rewriting the shared caches
-- in the middle of their own use. The symptom was TYPE errors in places with no relation
-- at all to a timer, one every ~30 runs.
--
-- The harness's stub was fixed, but the guard stays: in the game `Refresh` can also be called
-- from an `OnClick`, from an event and from the timer, and nothing guarantees two do not cross.
local desenhando = false

-- (14/10) ONLY A RUN THAT JUST ENDED takes what arrives. Loot and scores kept stitching into the
-- last run for as long as it was the one on screen: an item of a raid boss, a delve or a dungeon
-- after the key went into the key's line (seen in the saved boards), and a keystone message at
-- the start of the NEXT key rewrote the old run's scores. The chest, the new keystones and the
-- season score all arrive in the first minutes; past this window nothing is of that run.
local STITCH_SECONDS = 300
local function Recente(run)
    return type(run) == "table" and type(run.rows) == "table" and type(run.recordedAt) == "number"
        and time and time() - run.recordedAt <= STITCH_SECONDS
end

local function Costura(mexe)
    local naTela = false
    if Recente(context) then
        naTela = mexe(context) and true or false
    end

    -- On disk, only the run of the same type as the one on screen: a key's loot cannot
    -- show on the last raid boss's scoreboard.
    local kind = context and context.kind
    local guardada = kind and Store()[kind]
    if Recente(guardada) and guardada ~= context then
        mexe(guardada)
    end

    if naTela and frame and frame:IsShown() then
        Scoreboard.Refresh()
    end
    return naTela
end

function Scoreboard.OnLoot(name, itemLink)
    if not name or not itemLink then return end

    -- (!) A NAME WITHOUT THE REALM ON BOTH SIDES (26/09). `Party.NoteLoot` sends the short name ("Bizco"),
    -- and the row of whoever is from ANOTHER realm keeps "Bizco-Quel'dorei" (a run saved on 26/09). The
    -- exact comparison left every other-realm player's item off the scoreboard -- it only
    -- came in if it arrived within the 2 minutes of `RefreshExternalColumns`'s window, which strips the realm.
    local curto = ns.SplitName(name) or name
    Costura(function(run)
        local mudou = false
        for _, row in ipairs(run.rows) do
            if (ns.SplitName(row.name) or row.name) == curto and row.loot == nil then
                row.loot = itemLink
                mudou = true
            end
        end
        return mudou
    end)
end

--- The keystone and the score arrive **later**, like the loot -- and keep arriving for minutes.
---
--- ⚑ THIS IS THE USER'S OBSERVATION ABOUT THE REFERENCE SCOREBOARD, 10/09/2026, and it reframed the
--- fix: there too nothing shows at once, but, as the players open the chest, the
--- scoreboard keeps updating until everything is right -- the keystones, the loot, the score.
---
--- That is: **it is not about getting the capture's instant right, it is about the scoreboard staying alive after
--- it.** It makes sense by the game itself -- the new keystone only exists when each one opens the chest, and it is
--- that one LibOpenRaid broadcasts; the season's score is recomputed on the server. Capturing
--- later would only swap one wrong instant for another.
---
--- So this function re-reads the three columns that depend on outside, and it is called both by
--- the lib's notice and by a window of attempts after the end of the run.
--- @return boolean something changed
function Scoreboard.RefreshExternalColumns()
    if not ns.Party then return false end

    return Costura(function(run)
        local mudou = false
        for _, row in ipairs(run.rows) do
            if row.name then
                if row.keystoneLevel == nil then
                    local nivel, mapa = ns.Party.Keystone(row.name)
                    if nivel then
                        row.keystoneLevel, row.keystoneMapID = nivel, mapa
                        mudou = true
                    end
                end
                if row.loot == nil then
                    local item = ns.Party.Loot(row.name)
                    if item then
                        row.loot = item
                        mudou = true
                    end
                end
                -- THE ITEM LEVEL GOES INTO THE SAME LIST, for the same reason: the inspection at the start
                -- of the key fails silently (distance, phase, a burst of requests), and
                -- LibOpenRaid's answer may arrive later. The report of 10/09: *"não aparece o ilvl dos
                -- outros"*.
                if row.ilevel == nil then
                    local nivel = ns.Party.ItemLevel(row.name)
                    if nivel then
                        row.ilevel = nivel
                        mudou = true
                    end
                end
                -- THE SCORE IS THE ONLY ONE THAT IS OVERWRITTEN, and on purpose: it does not "arrive", it
                -- **changes** -- the server recomputes the season's after the run. Keeping the
                -- first reading would be showing the old number on purpose.
                local nova = ScoreFor(row.name)
                if nova and row.values and row.values.score ~= nova then
                    row.values.score = nova
                    mudou = true
                end
            end
        end
        return mudou
    end)
end

--- How long ago the run was done, in short text ("há 2 dias").
local function RunAge(snapshot)
    if not snapshot or not snapshot.recordedAt or not time then return nil end

    local seconds = time() - snapshot.recordedAt
    if seconds < 0 then return nil end
    if seconds < 3600 then
        return format(L["%d min ago"], math.max(1, math.floor(seconds / 60)))
    end
    if seconds < 86400 then
        return format(L["%d h ago"], math.floor(seconds / 3600))
    end
    return format(L["%d d ago"], math.floor(seconds / 86400))
end

--- Converts the picture (values by KEY) to the format the drawing uses (by POSITION).
---
--- The scoreboard no longer reads the live session. It always reads a picture: of the run that ended, of a
--- run kept on disk, or of the simulation. Three reasons:
---
---  1. The `C_DamageMeter` session is reset by the next fight. "See the last scoreboard" is only
---     possible if the numbers were copied out of it at the right moment.
---  2. A picture is dead data: it has no secret value, no reference to an API table,
---     and so it can be saved in the SavedVariables.
---  3. One drawing path. A real run, a kept run and the simulation draw through the
---     same code -- which makes the simulation count as a test of the real panel.
local function CollectRows(rowCount)
    local stored = context and context.rows
    if not stored then return {} end

    local out = {}
    local limit = #stored
    if rowCount and rowCount < limit then limit = rowCount end

    for i = 1, limit do
        local entry = stored[i]
        local values = {}
        for c = 1, #columns do
            values[c] = entry.values and entry.values[columns[c].key]
        end
        out[i] = {
            source = entry,          -- name, class, icon: the picture has the same fields
            row = entry,
            values = values,
            best = {},
        }
    end

    -- The highlight comes from `Data` itself, not from a copy of the rule: if what counts as
    -- leadership changes there (today it needs a value > 0 and at least two rows), the scoreboard follows by itself.
    if ns.Data.MarkColumnLeaders then
        local keys = {}
        for c = 1, #columns do keys[c] = columns[c].key end
        pcall(ns.Data.MarkColumnLeaders, out, keys)
    end

    return out
end

--- Re-sorts the rows already built. It only runs when the value is readable -- in combat the fields are
--- secret and comparing raises an error.
local function SortRows(list, columnIndex)
    local readable = true
    for i = 1, #list do
        local v = list[i].values[columnIndex]
        if v ~= nil and (issecretvalue(v) or type(v) ~= "number") then
            readable = false
            break
        end
    end
    if not readable then return end

    local pos = {}
    for i = 1, #list do pos[list[i]] = i end
    table.sort(list, function(a, b)
        local x = a.values[columnIndex] or -1
        local y = b.values[columnIndex] or -1
        if x == y then return pos[a] < pos[b] end
        if sortDesc then return x > y end
        return x < y
    end)
end

--------------------------------------------------------------------------------
-- The column header
--------------------------------------------------------------------------------
--- The column header: each column is a CELL with its own background, small white text
--- against the left.
---
--- The gold rule that was here went away. The cells' own background (black at 0.5,
--- `COLHEAD_TINT`), darker than the rows', separates header from rows -- and so the
--- division shows without needing a line.
---
--- The click to sort STAYS, and changes nothing of what is seen: the sorted column swaps its
--- background's tone for the selection tone (`COLHEAD_TINT_SORTED`).
local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
    end

    headerRow:ClearAllPoints()
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE, -HEADER_HEIGHT)
    headerRow:SetHeight(COLHEAD_HEIGHT)

    local offsets = ColumnOffsets()

    -- (!) A PAIR IS ONE BLOCK (01/10). The sorted column's header is a shade lighter, and in a
    -- family of two columns ("Damage": per s, total) only the sorted half was: the user, *"nas
    -- colunas duplas fica estranho (...) a coluna dupla tem que ficar igual"*. The shade is now
    -- the FAMILY's: every column of the group the sorted one is in. And the columns of a group
    -- have no seam between them: each but the last reaches the next one.
    local groupOf, sortedGroup = {}, nil
    for g, group in ipairs(HeaderGroups()) do
        for c = group.first, group.last do
            groupOf[c] = group
            if columns[c].key == sortBy then sortedGroup = group end
        end
    end

    for c = 1, #columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(COLHEAD_HEIGHT)
            -- (25/10) the game's tooltip background, as a texture of the button (it was a SetBackdrop of it: the
            -- same look, no backdrop -- the workspace rules)
            button.bg = button:CreateTexture(nil, "BACKGROUND")
            button.bg:SetAllPoints()
            button.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
            -- The PART of the column, on the second line; the family goes on the first, over
            -- the whole group (`headerRow.families`, below).
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            button.text:SetPoint("BOTTOMLEFT", COL_PADDING, 0)
            button.text:SetHeight(COLHEAD_LINE)
            button.text:SetJustifyH("LEFT")
            button.text:SetWordWrap(false)
            button:SetScript("OnClick", function(self)
                local column = columns[self.columnIndex]
                if column.render and column.render ~= "score" then return end
                local key = column.key
                if sortBy == key then sortDesc = not sortDesc else sortBy, sortDesc = key, true end
                -- Through the public function, not a raw `Draw()`: `SafeDraw` is local and declared
                -- further down, so here it would not even be visible -- and a drawing error
                -- fired from inside an OnClick vanishes without a trace when
                -- `scriptErrors` is off, which is the game's default.
                Scoreboard.Refresh()
            end)
            button:SetScript("OnEnter", function(self)
                local column = columns[self.columnIndex]
                local label = ColumnLabel(column)
                if label == "" then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip_SetTitle(GameTooltip, column.custom and label
                    or ns.Data.GetAttributeLabel(column.key))
                if not column.render or column.render == "score" then
                    GameTooltip_AddInstructionLine(GameTooltip, L["Click: sort by this column"])
                end
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            headerRow.labels[c] = button
        end

        button.columnIndex = c
        local group = groupOf[c]
        button:SetWidth(columns[c].width + ((group and c < group.last) and COL_PADDING or 0))
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", headerRow, "TOPLEFT", offsets[c], 0)

        local sorted = group ~= nil and group == sortedGroup
        button.bg:SetVertexColor(unpack(sorted and COLHEAD_TINT_SORTED or COLHEAD_TINT))

        -- Size 10, applied by the addon's ladder so the font picker
        -- still holds.
        ns.ApplyScoreboardFont(button.text, 10 - ns.Skin.scoreboardFontSize, "")
        local def = not columns[c].custom and ns.Data.GetColumn(columns[c].key) or nil
        button.text:SetText(def and def.part or "")
        button.text:SetTextColor(0.62, 0.62, 0.66, 1)
        button:Show()
    end

    for c = #columns + 1, #headerRow.labels do
        headerRow.labels[c]:Hide()
    end

    -- THE FIRST LINE: one label per group, over the group's columns. A group of one column has
    -- no part, so its name takes the two lines: centred on them, and a long name ("Controle
    -- coletivo") wraps into the second line instead of running over the next column.
    headerRow.families = headerRow.families or {}
    local groups = HeaderGroups()
    for g = 1, #groups do
        local group = groups[g]
        local label = headerRow.families[g]
        if not label then
            label = headerRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetJustifyH("LEFT")
            headerRow.families[g] = label
        end
        local width = offsets[group.last] - offsets[group.first] + columns[group.last].width
        label:ClearAllPoints()
        label:SetWidth(width - COL_PADDING)
        ns.ApplyScoreboardFont(label, 10 - ns.Skin.scoreboardFontSize, "")
        label:SetText(group.label)
        label:SetTextColor(1, 1, 1, 1)
        if group.last > group.first then
            -- (!) CENTRED OVER THE PAIR (30/09). Left-aligned, the family sat over its first
            -- column and read as that column's own title, and the second column looked like a
            -- stranger under a grey word; the user: *"tem coluna que é dupla mas no cabeçalho
            -- do título estão separadas"*. Centred on the span of the group, the name belongs
            -- to both columns, as in the meter window's header.
            label:SetJustifyH("CENTER")
            label:SetWordWrap(false)
            label:SetHeight(COLHEAD_LINE)
            label:SetPoint("TOPLEFT", headerRow, "TOPLEFT", offsets[group.first] + COL_PADDING, 0)
        else
            -- A family of one column sits over its numbers, which are left-aligned.
            label:SetJustifyH("LEFT")
            label:SetWordWrap(true)
            label:SetHeight(COLHEAD_HEIGHT)
            label:SetJustifyV("MIDDLE")
            label:SetPoint("TOPLEFT", headerRow, "TOPLEFT", offsets[group.first] + COL_PADDING, 0)
        end
        label:SetShown(group.label ~= "")
    end
    for g = #groups + 1, #headerRow.families do
        headerRow.families[g]:Hide()
    end
end

---For the harness: the header's groups as drawn.
function Scoreboard.__headerGroups()
    return HeaderGroups(), headerRow and headerRow.families or {}, headerRow and headerRow.labels or {}
end

--------------------------------------------------------------------------------
-- Linhas
--------------------------------------------------------------------------------
--- A cell's pieces, by column type. Each builder returns the object the drawing
--- will fill, and all of them live inside a cell frame with the column's width -- so
--- whoever changes a column's width does not need to know what is inside it.
local CellBuilders = {}

--- A round portrait + role icon + item level.
function CellBuilders.portrait(cell)
    local size = ROW_HEIGHT - PORTRAIT_INSET * 2

    cell.portrait = cell:CreateTexture(nil, "ARTWORK")
    cell.portrait:SetSize(size, size)
    cell.portrait:SetPoint("LEFT", COL_PADDING, 0)

    cell.role = cell:CreateTexture(nil, "OVERLAY", nil, 6)
    cell.role:SetSize(ROLE_SIZE, ROLE_SIZE)
    cell.role:SetPoint("BOTTOMLEFT", cell.portrait, "BOTTOMRIGHT", ROLE_X, ROLE_Y)

    -- The dark plate behind the item level. `LoC-ShadowBG` is the game's own texture, not
    -- addon art.
    cell.ilvlBg = cell:CreateTexture(nil, "OVERLAY", nil, 5)
    cell.ilvlBg:SetTexture("Interface\\Cooldown\\LoC-ShadowBG")
    cell.ilvlBg:SetPoint("BOTTOMLEFT", cell.portrait, "BOTTOMLEFT", -ILVL_BG_INSET, -1)
    cell.ilvlBg:SetPoint("BOTTOMRIGHT", cell.portrait, "BOTTOMRIGHT", ILVL_BG_INSET, -1)
    cell.ilvlBg:SetHeight(ILVL_BG_HEIGHT)

    cell.ilvl = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.ilvl:SetPoint("BOTTOM", cell.portrait, "BOTTOM", 0, 0)
end

function CellBuilders.spec(cell)
    cell.icon = cell:CreateTexture(nil, "OVERLAY")
    cell.icon:SetSize(SPEC_ICON, SPEC_ICON)
    cell.icon:SetPoint("LEFT", COL_PADDING, 0)

    -- A second texture because a specialization is an icon id and a class is an atlas cut, and
    -- `SetMask` does not get along with `SetTexCoord`. The old scoreboard applied a mask here and the class
    -- icon vanished -- it is the defect that rewrite fixed, and it cannot come back.
    cell.iconClass = cell:CreateTexture(nil, "OVERLAY")
    cell.iconClass:SetSize(SPEC_ICON, SPEC_ICON)
    cell.iconClass:SetPoint("LEFT", COL_PADDING, 0)
    cell.iconClass:Hide()
end

function CellBuilders.name(cell)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.text:SetPoint("LEFT", COL_PADDING, 0)
    cell.text:SetPoint("RIGHT", -COL_PADDING, 0)
    cell.text:SetJustifyH("LEFT")
    cell.text:SetWordWrap(false)
end

--- The keystone's dungeon icon + level.
function CellBuilders.keystone(cell)
    -- (!) THE GAME'S OWN DUNGEON ICON, DRAWN AS THE GAME DRAWS IT (05/10). The user: *"as pedras
    -- (keystone) a imagem ta bem zoada, mal da pra entender que pedra e"*. The image is the 4th
    -- return of `C_ChallengeMode.GetMapUIInfo`, the icon of the Mythic+ tab -- and it was being
    -- cut with borrowed numbers (36..375 by 50..290 of 512), which were measured for ANOTHER
    -- image: the Adventure Guide's painting of the instance (`iconLore`).
    -- On the game's icon that cut is two thirds of the width by half of the
    -- height, stretched into a square. The game shows this icon WHOLE, 50 inside a frame of 52
    -- (`ChallengesDungeonIconFrameTemplate`, Blizzard_ChallengesUI.xml): here the same, at 45.
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(KEYSTONE_INNER, KEYSTONE_INNER)
    cell.icon:SetPoint("LEFT", COL_PADDING + (KEYSTONE_ICON - KEYSTONE_INNER) / 2, 0)
    cell.icon:SetTexCoord(0, 1, 0, 1)

    cell.frameArt = cell:CreateTexture(nil, "ARTWORK", nil, 2)
    cell.frameArt:SetAtlas(KEYSTONE_FRAME_ATLAS)
    cell.frameArt:SetSize(KEYSTONE_ICON, KEYSTONE_ICON)
    cell.frameArt:SetPoint("CENTER", cell.icon, "CENTER", 0, 0)

    cell.levelBg = cell:CreateTexture(nil, "ARTWORK", nil, 6)
    cell.levelBg:SetTexture("Interface\\Cooldown\\LoC-ShadowBG")
    cell.levelBg:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMLEFT", -5, -1)
    cell.levelBg:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 5, -1)
    cell.levelBg:SetHeight(ILVL_BG_HEIGHT)

    cell.level = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.level:SetPoint("BOTTOM", cell.icon, "BOTTOM", 0, -1)
end

---Shows the game's tooltip for the item on the hovered loot icon (`self.link`). The link is
---the whole item link that `ENCOUNTER_LOOT_RECEIVED` gave (`Party.NoteLoot`); when it is not
---one the tooltip understands, the item id still shows the base item.
function Scoreboard.__lootEnter(self)
    local link = self and self.link
    if not link then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local ok = type(link) == "string" and pcall(GameTooltip.SetHyperlink, GameTooltip, link)
    if not ok then
        local id = tonumber(link)
        if not id and C_Item and C_Item.GetItemInfoInstant then
            local okId, itemID = pcall(C_Item.GetItemInfoInstant, link)
            id = okId and itemID or nil
        end
        if not id then GameTooltip:Hide(); return end
        GameTooltip:SetItemByID(id)
    end
    GameTooltip:Show()
end

--- The loot square: a 32 icon with a border in the quality's colour and the item's level on top.
function CellBuilders.loot(cell)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetSize(LOOT_ICON, LOOT_ICON)
    cell.icon:SetPoint("LEFT", COL_PADDING, 0)

    cell.border = cell:CreateTexture(nil, "OVERLAY")
    cell.border:SetSize(LOOT_ICON, LOOT_ICON)
    cell.border:SetPoint("CENTER", cell.icon, "CENTER", 0, 0)
    -- A borda nasce escondida: quem escolhe o atlas e a QUALIDADE do item, no desenho.
    cell.border:Hide()

    cell.ilvlBg = cell:CreateTexture(nil, "OVERLAY", nil, 5)
    cell.ilvlBg:SetTexture("Interface\\Cooldown\\LoC-ShadowBG")
    cell.ilvlBg:SetPoint("BOTTOMLEFT", cell.icon, "BOTTOMLEFT", -3, -1)
    cell.ilvlBg:SetPoint("BOTTOMRIGHT", cell.icon, "BOTTOMRIGHT", 3, -1)
    cell.ilvlBg:SetHeight(ILVL_BG_HEIGHT)

    cell.ilvl = cell:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cell.ilvl:SetPoint("BOTTOM", cell.icon, "BOTTOM", 0, 0)

    -- (!) THE ITEM'S OWN TOOLTIP ON MOUSE OVER (24/10). The user, 13/10: *"quando passa o mouse
    -- em cima do item que alguém ganhou não mostra a popup dele (…) o padrão do jogo"*. The game
    -- does it the same way on its loot banner (BossBannerToast.lua:213, 12.1.0): owner + the
    -- link itself, so bonus ids and item level are the ones that dropped. Only the icon takes
    -- the mouse, and only while there is an item (the painter turns it on), so the rest of the
    -- row still drags the panel; a drag that starts on the icon is handed to the panel too.
    local hit = CreateFrame("Frame", nil, cell)
    hit:SetAllPoints(cell.icon)
    hit:EnableMouse(false)
    hit:RegisterForDrag("LeftButton")
    hit:SetScript("OnDragStart", function(self) self.dragged = true; if frame then frame:StartMoving() end end)
    hit:SetScript("OnDragStop", function() if frame then frame:StopMovingOrSizing() end end)
    hit:SetScript("OnMouseDown", function(self) self.dragged = nil end)
    hit:SetScript("OnEnter", Scoreboard.__lootEnter)
    hit:SetScript("OnLeave", GameTooltip_Hide)
    -- Shift-click links it in chat, Ctrl-click tries it on: the game's own item click. A plain
    -- click does what a click on the row does (the player's own row opens "My run").
    hit:SetScript("OnMouseUp", function(self, button)
        if button ~= "LeftButton" or self.dragged or not self.link then return end
        if HandleModifiedItemClick and HandleModifiedItemClick(self.link) then return end
        local row = cell:GetParent()
        if row and row.open then row.open() end
    end)
    cell.hit = hit
end

--- A number cell -- and the score's, which is a number with the gain stuck on.
function CellBuilders.value(cell)
    cell.text = cell:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cell.text:SetPoint("LEFT", COL_PADDING, 0)
    cell.text:SetPoint("RIGHT", -COL_PADDING, 0)
    -- ON THE LEFT, and it is the change that shows most. The old scoreboard aligned numbers to the right, which
    -- is right for comparing stacked quantities; here everything aligns to the left, glued
    -- to the column's label.
    cell.text:SetJustifyH("LEFT")
    cell.text:SetWordWrap(false)
end

-- THE SCORE CELL IS A NUMBER CELL, and the builder was not told so.
--
-- It was the defect of the print of 07/09 20:22: the column declares `render = "score"`, there is a
-- `CellPainters.score` to write `2863 (+0)`, and **there was no `CellBuilders.score`**. The
-- `BuildRow` does `CellBuilders[kind](cell)`, so on the first row it called nil and the whole drawing
-- aborted -- with the header and the column labels already on screen, because they are
-- drawn before. The panel opened pretty and **empty**, the most misleading symptom possible:
-- it does not look like a Lua error, it looks like "there is no data".
--
-- The comment right above already said "and the score's, which is a number with the gain stuck on". The intent
-- was written; only the routing was not.
CellBuilders.score = CellBuilders.value

local function BuildRow(index)
    local row = rows[index]

    if not row then
        -- A Frame, not a Button: the scoreboard's row does nothing when clicked. As a Button it
        -- captured the mouse and the panel stopped being draggable over the rows -- which is
        -- exactly where the person grabs it.
        row = CreateFrame("Frame", nil, frame)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(false)
        -- (!) THE PLAYER'S OWN ROW OPENS "MY RUN" (05/10). The user: *"poder clicar na linha e
        -- ver sua performance individual"*. Only that row takes the mouse (`DrawRows` turns it
        -- on when there is something to open), and it still drags the panel: the drag is
        -- handed to the frame, which is why the row could not be a Button before.
        row:RegisterForDrag("LeftButton")
        row:SetScript("OnDragStart", function(self) self.dragged = true; frame:StartMoving() end)
        row:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
        row:SetScript("OnMouseDown", function(self) self.dragged = nil end)
        row:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and not self.dragged and self.open then self.open() end
        end)
        row:SetScript("OnEnter", function(self)
            if not self.open then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
            GameTooltip_SetTitle(GameTooltip, L["My run"])
            GameTooltip_AddInstructionLine(GameTooltip, L["Click: your own performance in this run"])
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()

        row.cells = {}
        rows[index] = row
    end

    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + COLHEAD_HEIGHT
        + (index - 1) * (ROW_HEIGHT + ROW_SPACING) + 1)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", SIDE + LINE_INSET, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SIDE - LINE_INSET, offsetY)

    local offsets = ColumnOffsets()

    for c = 1, #columns do
        local cell = row.cells[c]
        local kind = columns[c].render or "value"

        -- The cell keeps the TYPE it was built with. The columns change between a key's
        -- run and a raid scoreboard, and a cell reused with the wrong builder
        -- would draw a portrait where there should be a number -- with no error at all, just wrong.
        if cell and cell.kind ~= kind then
            cell:Hide()
            cell = nil
            row.cells[c] = nil
        end

        if not cell then
            cell = CreateFrame("Frame", nil, row)
            cell.kind = kind
            cell:SetHeight(ROW_HEIGHT)
            CellBuilders[kind](cell)
            row.cells[c] = cell
        end

        cell:SetWidth(columns[c].width)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", row, "TOPLEFT", offsets[c], 0)

        if cell.text then ns.ApplyScoreboardFont(cell.text, 0, "") end
        if cell.ilvl then ns.ApplyScoreboardFont(cell.ilvl, ILVL_FONT - ns.Skin.scoreboardFontSize, "") end
        if cell.level then ns.ApplyScoreboardFont(cell.level, KEYSTONE_FONT - ns.Skin.scoreboardFontSize, "") end
        cell:Show()
    end

    for c = #columns + 1, #row.cells do
        if row.cells[c] then row.cells[c]:Hide() end
    end

    return row
end

--- Writes the score cell: `2847 (+16)`, with the gain in green.
--- The gain only exists for whoever the client can tell about -- in the real run, only the player himself
--- (it comes from `oldOverallDungeonScore`/`newOverallDungeonScore`). With no gain, it shows only the number.
local function ScoreText(entry, index)
    local value = entry.values[index]
    if value == nil then return "—" end
    -- A secret goes WHOLE to the FontString: the engine can render it, Lua cannot read it. A
    -- `math.floor` here would bring down the whole row's drawing.
    if issecretvalue(value) then return value end
    if type(value) ~= "number" then return tostring(value) end

    local text = tostring(math.floor(value + 0.5))
    -- The gain is per player in the picture: only the player himself has that number (it comes from
    -- `oldOverallDungeonScore`/`newOverallDungeonScore`, which the client only gives about itself).
    local gain = entry.row and entry.row.scoreGain
    if gain and gain > 0 then
        text = text .. " |cff40d878(+" .. gain .. ")|r"
    end
    return text
end

--------------------------------------------------------------------------------
-- The timeline
--------------------------------------------------------------------------------
--- Draws the footer: the run's rail, the boss and death markers, the time axis and the chest.
---
--- The rail's green/red is NOT the key's pace -- it is in/out of combat. Green is fighting,
--- red is walking. What says "in time" is the chest at the end, green or red.
local function DrawTimeline()
    if not timeline then return end

    -- The Great Vault chest, the time axis and the closed-key marker are
    -- Mythic+ vocabulary. On a raid encounter scoreboard they showed the same way -- a green chest
    -- saying "in time" under a boss that has no timer. The whole footer goes.
    local total = context and context.durationSeconds
    if not IsKeystone() or not total or issecretvalue(total) or total <= 0 then
        timeline:Hide()
        return
    end
    timeline:Show()

    local limit = context.timeLimit

    -- The axis goes up to the key's limit when it is bigger than the run: so one can see
    -- how much time was left, which is the information the player looks for first.
    local span = total
    if limit and limit > span then span = limit end

    local width = timeline:GetWidth()
    if not width or width <= 0 then width = PanelWidth() - SIDE * 2 end
    local function X(seconds)
        local at = seconds / span
        if at < 0 then at = 0 elseif at > 1 then at = 1 end
        return at * width
    end

    -- Segmentos de combate.
    timeline.segments = timeline.segments or {}
    for _, seg in ipairs(timeline.segments) do seg:Hide() end

    -- THE STRETCH THE ADDON DID NOT SEE STAYS NEUTRAL, neither green nor red. In a resumed run
    -- the rail painted red -- "walking" -- the minutes before the `/reload`, which is the
    -- same lie as the out-of-combat number, only drawn.
    local desde = context.knownFrom or 0
    if desde > 0 then
        timeline.unknown = timeline.unknown or timeline:CreateTexture(nil, "ARTWORK")
        timeline.unknown:SetHeight(RAIL_HEIGHT)
        timeline.unknown:ClearAllPoints()
        timeline.unknown:SetPoint("LEFT", timeline.rail, "LEFT", 0, 0)
        timeline.unknown:SetWidth(math.max(1, X(desde)))
        timeline.unknown:SetColorTexture(0.45, 0.45, 0.48, 0.55)
        timeline.unknown:Show()
    elseif timeline.unknown then
        timeline.unknown:Hide()
    end

    local marks = (context.combatTimeline or {})
    local used = 0
    for i = 1, #marks do
        local startAt = marks[i][1]
        local inCombat = marks[i][2]
        local stopAt = marks[i + 1] and marks[i + 1][1] or total
        if stopAt > startAt then
            used = used + 1
            local seg = timeline.segments[used]
            if not seg then
                seg = timeline:CreateTexture(nil, "ARTWORK")
                seg:SetHeight(RAIL_HEIGHT)
                timeline.segments[used] = seg
            end
            seg:ClearAllPoints()
            seg:SetPoint("LEFT", timeline.rail, "LEFT", X(startAt), 0)
            seg:SetWidth(math.max(1, X(stopAt) - X(startAt)))
            if inCombat then
                seg:SetColorTexture(0.10, 0.70, 0.10, 0.85)
            else
                seg:SetColorTexture(0.70, 0.10, 0.10, 0.70)
            end
            seg:Show()
        end
    end

    -- Marcadores de boss, acima do trilho.
    timeline.bosses = timeline.bosses or {}
    for _, marker in ipairs(timeline.bosses) do marker:Hide() end

    for i, boss in ipairs(context.bosses or {}) do
        local marker = timeline.bosses[i]
        if not marker then
            marker = CreateFrame("Frame", nil, timeline)
            marker:SetSize(BOSS_ICON, BOSS_ICON)
            marker.icon = marker:CreateTexture(nil, "ARTWORK")
            marker.icon:SetAllPoints()
            marker.label = marker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            marker.label:SetPoint("LEFT", marker, "RIGHT", 1, 0)
            marker.tick = marker:CreateTexture(nil, "ARTWORK")
            marker.tick:SetSize(1, 4)
            marker.tick:SetPoint("TOP", marker, "BOTTOM", 0, 1)
            marker.tick:SetColorTexture(1, 1, 1, 0.5)
            timeline.bosses[i] = marker
        end

        if not Atlas(marker.icon, "worldquest-icon-boss") then
            marker.icon:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
        end
        ns.ApplyFont(marker.label, -3, "")
        marker.label:SetText(SecondsToClock(boss[1]))
        marker.label:SetTextColor(0.86, 0.87, 0.90)

        -- Near the end of the axis the label on the right goes out of the panel, and still bumps into the chest.
        -- It turns to the left of the icon; it is the only side left.
        local at = X(boss[1])
        marker.label:ClearAllPoints()
        if at > width - 56 then
            marker.label:SetPoint("RIGHT", marker, "LEFT", -1, 0)
            marker.label:SetJustifyH("RIGHT")
        else
            marker.label:SetPoint("LEFT", marker, "RIGHT", 1, 0)
            marker.label:SetJustifyH("LEFT")
        end

        marker:ClearAllPoints()
        marker:SetPoint("BOTTOM", timeline.rail, "TOPLEFT", at, 3)
        marker:Show()
    end

    -- Deaths, below the rail: they are bad news and must not compete with the bosses.
    timeline.deaths = timeline.deaths or {}
    for _, mark in ipairs(timeline.deaths) do mark:Hide() end

    for i, death in ipairs(context.deathMarks or {}) do
        local mark = timeline.deaths[i]
        if not mark then
            mark = timeline:CreateTexture(nil, "OVERLAY")
            mark:SetSize(DEATH_ICON, DEATH_ICON)
            timeline.deaths[i] = mark
        end
        -- ⚑ THE CLASS ICON WHEN IT IS KNOWN WHICH IT WAS, the skull when it is not. The class only
        -- gets here if `AttachDeathClasses` managed to prove the match (the two
        -- lists the same size) -- so `death[2]` present already means "this is right".
        --
        -- The art is the game's own class sheet, cut by `CLASS_ICON_TCOORDS`, which is
        -- how the row's portrait already does it in this file. No invented atlas: the cut comes from the same
        -- table Blizzard uses on the character sheet.
        local classe = death[2]
        local coords = classe and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classe]
        if coords then
            mark:SetTexture("Interface\\WorldStateFrame\\ICONS-CLASSES")
            mark:SetTexCoord(unpack(coords))
        else
            -- `SetTexCoord` is sticky: a texture that was once a class icon keeps the
            -- cut, and the next atlas would come out cut in the same square. It undoes it first.
            mark:SetTexCoord(0, 1, 0, 1)
            if not Atlas(mark, "BossBanner-SkullCircle") then
                mark:SetColorTexture(0.85, 0.25, 0.25, 0.9)
            end
        end
        mark:ClearAllPoints()
        mark:SetPoint("TOP", timeline.rail, "BOTTOMLEFT", X(death[1]), -3)
        mark:Show()
    end

    -- The end-of-run chest: green if it was in time, red if it went over.
    local chest = timeline.chest
    local onTime = context.onTime
    if not Atlas(chest, onTime and "gficon-chest-evergreen-greatvault-collect"
        or "gficon-chest-evergreen-greatvault-complete") then
        chest:SetTexture("Interface\\Icons\\INV_Box_01")
    end
    chest:ClearAllPoints()
    chest:SetPoint("CENTER", timeline.rail, "LEFT", X(total), 0)

    -- The axis: a mark every 5 minutes, plus the end.
    timeline.ticks = timeline.ticks or {}
    for _, tick in ipairs(timeline.ticks) do tick:Hide() end

    local step = 300
    if span > 2400 then step = 600 end
    local count = 0
    local at = 0
    while at <= span do
        count = count + 1
        local tick = timeline.ticks[count]
        if not tick then
            tick = CreateFrame("Frame", nil, timeline)
            tick:SetSize(1, 4)
            tick.line = tick:CreateTexture(nil, "ARTWORK")
            tick.line:SetAllPoints()
            tick.line:SetColorTexture(1, 1, 1, 0.25)
            tick.label = tick:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            tick.label:SetPoint("TOP", tick, "BOTTOM", 0, -1)
            timeline.ticks[count] = tick
        end
        ns.ApplyFont(tick.label, -4, "")
        tick.label:SetText(SecondsToClock(at))
        tick:ClearAllPoints()
        tick:SetPoint("TOP", timeline.rail, "BOTTOMLEFT", X(at), -20)
        tick:Show()
        at = at + step
    end
end

--------------------------------------------------------------------------------
-- The header's numbers
--------------------------------------------------------------------------------
--- How much of the run was spent OUT of combat.
---
--- It comes from the same axis that draws the green and red rail, so the two can never disagree:
--- the number in the header is the sum of what is painted red below.
local function OutOfCombatSeconds()
    local total = context and context.durationSeconds
    if not total or issecretvalue(total) or total <= 0 then return nil end

    local marks = context.combatTimeline
    if type(marks) ~= "table" or #marks == 0 then return nil end

    -- AN INCOMPLETE RECORD DOES NOT BECOME A NUMBER. `knownFrom > 0` is a run resumed after a
    -- `/reload`: the addon knows how long the key lasted (the world timer says), but only saw the
    -- combat from there on. Adding the rest as "out of combat" is what produced
    -- **"Fora de combate: 26:13"** on a 26:13 key.
    --
    -- It vanishes from the screen instead of showing a qualified number: the top strip has four things
    -- competing for space, and "8:12 (partial)" asks for an explanation that does not fit there. Absence
    -- explains itself; a wrong number does not.
    local desde = context.knownFrom or 0
    if desde > 0 then return nil end

    local idle = 0
    for i = 1, #marks do
        local startAt, inCombat = marks[i][1], marks[i][2]
        local stopAt = marks[i + 1] and marks[i + 1][1] or total
        if not inCombat and stopAt > startAt then idle = idle + (stopAt - startAt) end
    end
    return idle
end

--- The group's average item level, from the ones the picture managed to know.
---
--- An average only of what is known, and nil when nothing is known of anyone. Counting whoever was not
--- inspected as zero would pull the average down and give a wrong number that looks right.
local function AverageItemLevel()
    local rows = context and context.rows
    if type(rows) ~= "table" then return nil end

    local sum, count = 0, 0
    for i = 1, #rows do
        local level = rows[i].ilevel
        if level and level > 0 then
            sum = sum + level
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return sum / count
end

--------------------------------------------------------------------------------
-- Building the panel
--------------------------------------------------------------------------------
local function CreateHeaderArt()
    -- The level star: it sits OUTSIDE the frame, biting the top edge. It is what gives the
    -- official panel's air; without it the header is just a dark strip with gold text.
    frame.star = frame:CreateTexture(nil, "OVERLAY")
    frame.star:SetSize(STAR_SIZE, STAR_SIZE)
    frame.star:SetPoint("CENTER", frame, "TOP", 0, STAR_OFFSET_Y)
    if not Atlas(frame.star, "ChallengeMode-SpikeyStar") then
        frame.star:Hide()
    end

    frame.level = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    frame.level:SetPoint("CENTER", frame.star, "CENTER", 0, 0)
    frame.level:SetTextColor(1, 0.94, 0.72)

    local function Filigree(atlas, w, h, point, relPoint, x, y)
        local tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetSize(w, h)
        tex:SetPoint(point, frame, relPoint, x, y)
        if not Atlas(tex, atlas) then tex:Hide() end
        return tex
    end

    -- The spelling `Fillagree` with two L's: that is how it is in the client. `Filigree` vanishes without warning.
    frame.filigreeLeft = Filigree("BossBanner-LeftFillagree",
        FILIGREE_SIDE_W, FILIGREE_SIDE_H, "BOTTOM", "TOP", -FILIGREE_SIDE_X, -2)
    frame.filigreeRight = Filigree("BossBanner-RightFillagree",
        FILIGREE_SIDE_W, FILIGREE_SIDE_H, "BOTTOM", "TOP", FILIGREE_SIDE_X, -2)
    frame.filigreeBottom = Filigree("BossBanner-BottomFillagree",
        FILIGREE_BOTTOM_W, FILIGREE_BOTTOM_H, "BOTTOM", "BOTTOM", 0, FILIGREE_BOTTOM_Y)
end

local function CreateTimeline()
    timeline = CreateFrame("Frame", nil, frame)
    -- 63 do fundo: o eixo fica em −385 num painel de 452 e tem 4px de altura.
    timeline:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", SIDE + LINE_INSET * 2, 63)
    timeline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE - LINE_INSET * 2 - 1, 63)
    timeline:SetHeight(RAIL_HEIGHT)

    -- The two gradients are what makes the axis look like art instead of a line: dark
    -- coming down from above and going up from below, with the rail in the middle.
    timeline.glowTop = timeline:CreateTexture(nil, "BACKGROUND")
    timeline.glowTop:SetPoint("BOTTOMLEFT", timeline, "TOPLEFT", 0, 0)
    timeline.glowTop:SetPoint("BOTTOMRIGHT", timeline, "TOPRIGHT", 0, 0)
    timeline.glowTop:SetHeight(28)
    timeline.glowTop:SetColorTexture(1, 1, 1, 1)
    if timeline.glowTop.SetGradient and CreateColor then
        timeline.glowTop:SetGradient("VERTICAL",
            CreateColor(0, 0, 0, 0.55), CreateColor(0, 0, 0, 0))
    else
        timeline.glowTop:SetColorTexture(0, 0, 0, 0.3)
    end

    timeline.rail = timeline:CreateTexture(nil, "BORDER")
    timeline.rail:SetAllPoints()
    timeline.rail:SetColorTexture(0, 0, 0, 0.83)

    timeline.chest = timeline:CreateTexture(nil, "OVERLAY")
    timeline.chest:SetSize(CHEST_ICON, CHEST_ICON)
end

local function CreatePanel()
    if frame then return frame end

    -- (25/10) the game's tooltip border (TooltipBorderBackdropTemplate: a NineSlice, an empty centre) around the
    -- dark art (ns.DarkBody), instead of a flat WHITE8X8 backdrop with a 1-pixel black edge: the workspace rules
    -- (no hand-painted panel; "escuro em tudo", the app as the reference). The dungeon's own art stays above it
    frame = CreateFrame("Frame", ADDON .. "Scoreboard", UIParent, "TooltipBorderBackdropTemplate")
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("HIGH")
    -- IN FRONT WHEN OPENED OR CLICKED (27/09). Every Rocket window shares the HIGH strata, and
    -- inside a strata the order is the frame LEVEL: without this, the rows of a window opened
    -- earlier (deeper children, higher levels) drew over the background of the one opened on
    -- top -- the user's print had RocketMount's list showing through RocketSwap. `toplevel`
    -- raises on click; `Raise` on show.
    frame:SetToplevel(true)
    frame:HookScript("OnShow", function(self) self:Raise() end)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    -- A reading panel, not an overlay: here the background is required, or the text competes with the
    -- scenery. `ns.Skin.scoreboardAlpha` is the value reserved for that.
    ns.DarkBody(frame, ns.Skin.scoreboardAlpha)
    frame:Hide()

    frame.art = frame:CreateTexture(nil, "BACKGROUND")
    frame.art:SetPoint("TOPLEFT", 3, -3)
    frame.art:SetPoint("BOTTOMRIGHT", -3, 3)

    frame.headerArt = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    frame.headerArt:SetPoint("TOPLEFT", 3, -3)
    frame.headerArt:SetPoint("TOPRIGHT", -3, -3)
    frame.headerArt:SetHeight(HEADER_HEIGHT - 6)
    ns.ApplyHeaderArt(frame.headerArt)
    frame.headerArt:SetAlpha(0.9)

    CreateHeaderArt()

    -- ⚑ THE CENTRAL STACK BECAME TWO COLUMNS, and the measurement on the print of 10/09 is the reason.
    --
    -- The stack had three things in the centre -- title (-12, size 20), time (-8, size 16)
    -- and, below, the result. The font comes from `ns.Skin.scoreboardFontSize` with the family the
    -- player chose, and it renders taller. The stack did not fit in the header's 65, and the print shows exactly that:
    --
    --     column header strip ........... y 80 to 106
    --     "no tempo +1" .................. y 93 to 99   <- inside it
    --
    -- Squeezing the gaps would fix one pixel and leave the same trap for the next one who
    -- touched the font's size. **Taking it off the axis solves it by construction**: the centre keeps only the
    -- title, and the time -- which is a run's main number -- goes to the RIGHT, with the
    -- result under it. It is what the user asked for (*"o tempo da dungeon não está em um lugar
    -- bom, pode ficar melhor alinhado na direita"*), and it is also the right way out: the left is already a
    -- context strip (out of combat, ilvl, deaths), so the right was the screen's empty space.
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", frame, "TOP", 0, TITLE_Y)
    frame.title:SetTextColor(1, 0.82, 0)

    -- THE TIME, on the right, aligned by the edge. Below the close button so as not to compete with
    -- it, and with the same side margin as the rest of the panel.
    frame.clock = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.clock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -CLOCK_RIGHT_INSET, CLOCK_Y)
    frame.clock:SetJustifyH("RIGHT")

    -- And the result right below it, on the same edge: the two make ONE block, and the eye reads
    -- "30:47 / no tempo +1" as one thing, which is what they are.
    frame.result = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.result:SetPoint("TOPRIGHT", frame.clock, "BOTTOMRIGHT", 0, RESULT_GAP)
    frame.result:SetJustifyH("RIGHT")

    -- THE TOP LEFT CORNER: the clock of time OUT of combat and the group's average item
    -- level. They are the run's two context lines, and both answer questions the rest of the panel does not: how much time was
    -- spent walking, and with what gear the group came in.
    frame.idleIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.idleIcon:SetSize(24, 24)
    frame.idleIcon:SetPoint("TOPLEFT", SIDE, -5)
    -- `auctionhouse-icon-clock` is not a clock picked by eye: it is what Blizzard uses in
    -- three places (`Blizzard_AuctionHouseUtil.lua:8`, `CovenantMissionTemplates.xml:588`,
    -- `Blizzard_ProfessionsTemplates.lua:114`), checked in the 12.1.0 source.
    if not Atlas(frame.idleIcon, "auctionhouse-icon-clock") then
        frame.idleIcon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    end
    frame.idleIcon:SetVertexColor(0.75, 0.75, 0.78)

    frame.idle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.idle:SetPoint("LEFT", frame.idleIcon, "RIGHT", 6, -3)
    frame.idle:SetJustifyH("LEFT")
    frame.idle:SetTextColor(0.75, 0.75, 0.78)

    frame.ilvlIcon = frame:CreateTexture(nil, "ARTWORK")
    frame.ilvlIcon:SetSize(20, 20)
    frame.ilvlIcon:SetPoint("LEFT", frame.idleIcon, "RIGHT", 260, 0)
    -- `bags-icon-equipment` (`ContainerFrame.lua:219`): the art the game has for this is the
    -- bags' equipment icon.
    if not Atlas(frame.ilvlIcon, "bags-icon-equipment") then
        frame.ilvlIcon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17")
    end
    frame.ilvlIcon:SetVertexColor(0.9, 0.9, 0.9)
    frame.ilvlIcon:SetAlpha(0.834)

    frame.ilvl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.ilvl:SetPoint("LEFT", frame.ilvlIcon, "RIGHT", 6, 0)
    frame.ilvl:SetJustifyH("LEFT")

    -- Affixes: right below the clock, small. They and the key's result in text are two
    -- things the panel already had before 0.66.0, and taking them out would be LOSING information.
    frame.affixes = {}
    for i = 1, 4 do
        local icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(18, 18)
        icon:SetPoint("TOPLEFT", SIDE + (i - 1) * 21, -34)
        icon:Hide()
        frame.affixes[i] = icon
    end

    -- THE DEATH COUNT STAYED IN THE HEADER, and it is worth saying why: the number of deaths became a
    -- column, but the **time lost with them** -- the `(-00:10)` -- is in no column, and it is
    -- the data that answers "did the deaths cost the key?".
    --
    -- It goes to the right of the item level, which is the free space of the top strip.
    frame.deaths = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.deaths:SetPoint("LEFT", frame.ilvl, "RIGHT", 24, 0)
    frame.deaths:SetJustifyH("LEFT")

    -- A flat glyph, not a framed button: the addon's icon family is flat.
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -8, -8)
    local closeTex = close:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    if not Atlas(closeTex, "common-icon-redx") then
        closeTex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    end
    close:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    close:SetScript("OnClick", function() frame:Hide() end)

    -- The hint (and the simulation notice) goes in the HEADER, not in the footer: down there it would compete
    -- for space with the time axis, and the axis is information, the hint is only a hint.
    -- ⚑ THE FOOTER WENT TO THE FOOTER, and that fixes a collision I created in 0.85.0.
    --
    -- It sat at `TOPRIGHT, -10, -38` -- inside the HEADER, despite its name -- and was the only
    -- occupant of the right there. When the run's time moved to that corner, the two came to
    -- compete for the same space: the report was *"tem texto embaixo"*, and the arithmetic matches -- the result
    -- ("no tempo +1") ends around −39 and it started at −38.
    --
    -- The right place is below, and for two reasons beyond not colliding: it is what its name says, and
    -- what it writes -- *"há 20 min"* or the drag hint -- is the screen's lowest-priority
    -- information. The time axis sits 63 from the bottom, so there is a free strip below it.
    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -SIDE - 6, 6)
    frame.footer:SetJustifyH("RIGHT")

    CreateTimeline()

    rows = {}
    return frame
end

--------------------------------------------------------------------------------
-- Desenho
--------------------------------------------------------------------------------
local function DrawHeader()
    -- The header's sizes, applied by the addon's ladder so the font picker still
    -- holds: title 20, time 16, idle clock 11.
    ns.ApplyScoreboardFont(frame.title, TITLE_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.clock, CLOCK_SIZE - ns.Skin.scoreboardFontSize, "")
    -- THE RESULT WAS LEFT OUT of this list, and so it was the only header text that did not
    -- follow the font the player chose -- it stayed on the template's `GameFontNormalSmall`. It went
    -- unnoticed because "not following the font" does not look like a defect, it looks like a choice.
    ns.ApplyScoreboardFont(frame.result, RESULT_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.idle, IDLE_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.ilvl, IDLE_SIZE - ns.Skin.scoreboardFontSize, "")
    ns.ApplyScoreboardFont(frame.deaths, IDLE_SIZE - ns.Skin.scoreboardFontSize, "")

    frame.title:SetText(context.title or L["Dungeon"])

    -- The star is the seal of "what content this is". In Mythic+ it carries the keystone's level; in
    -- a raid, the difficulty's initial (N / H / M), which is the equivalent information -- without it the
    -- raid scoreboard does not say whether that boss fell on normal or on mythic.
    local badge = context.level and tostring(context.level) or context.badge
    if badge and badge ~= "" then
        frame.level:SetText(badge)
        -- Three characters ("LFR") do not fit in the same size as a two-digit number.
        frame.level:SetFont(ns.Skin.font, #badge > 2 and 20 or 28, "OUTLINE")
        frame.level:Show()
        if frame.star:GetTexture() then frame.star:Show() end
    else
        frame.level:SetText("")
        frame.star:Hide()
    end

    local duration = context.durationSeconds
    if duration and not issecretvalue(duration) then
        frame.clock:SetText(SecondsToClock(duration))
        frame.clock:SetTextColor(1, 0.94, 0.72)
    else
        frame.clock:SetText("--:--")
    end

    -- The result: with no "+1/+2/+3" atlas in the client, the official panel uses text -- and so do we.
    if context.onTime == nil then
        -- (14/10) The subtitle was saved and never drawn: a raid boss's difficulty by name (the
        -- star has only its initial) and a session's "Overall" / "Current fight".
        frame.result:SetText(context.result or context.subtitle or "")
    elseif context.onTime then
        local upgrades = context.upgrades or 1
        frame.result:SetText("|cff40d878" .. L["on time"]
            .. (upgrades > 0 and ("  +" .. upgrades) or "") .. "|r")
    else
        frame.result:SetText("|cffe06060" .. L["over time"] .. "|r")
    end

    -- TIME OUT OF COMBAT: the sum of the axis's red stretches, shown as
    -- *"Not in combat"*. It answers the question the duration alone does not
    -- answer -- how much of the run was walking.
    local idle = OutOfCombatSeconds()
    frame.idle:SetShown(idle ~= nil)
    if idle then
        frame.idle:SetText(format(L["Not in combat: %s"], SecondsToClock(idle)))
    end

    -- THE GROUP'S AVERAGE ITEM LEVEL, from the picture itself. With none known, it vanishes: a "0" there
    -- would be read as a naked group instead of "could not inspect".
    local average = AverageItemLevel()
    frame.ilvlIcon:SetShown(average ~= nil)
    frame.ilvl:SetShown(average ~= nil)
    frame.ilvl:SetText(average and tostring(math.floor(average + 0.5)) or "")

    local deaths = context.deaths
    if deaths and not issecretvalue(deaths) then
        local text = format(deaths == 1 and L["%d death"] or L["%d deaths"], deaths)   -- (14/10) not "1 mortes"
        local lost = context.timeLostToDeaths
        if lost and lost > 0 then
            text = text .. "  (-" .. SecondsToClock(lost) .. ")"
        end
        frame.deaths:SetText(text)
    else
        frame.deaths:SetText("")
    end

    for i = 1, #frame.affixes do
        local icon = frame.affixes[i]
        local id = context.affixes and context.affixes[i]
        local shown = false
        if id and C_ChallengeMode and C_ChallengeMode.GetAffixInfo then
            local ok, _, _, fileID = pcall(C_ChallengeMode.GetAffixInfo, id)
            if ok and fileID then
                icon:SetTexture(fileID)
                icon:Show()
                shown = true
            end
        end
        if not shown then icon:Hide() end
    end

    ApplyBackdropArt(frame.art, context.mapID)
end

--------------------------------------------------------------------------------
-- Drawing a cell, by type
--------------------------------------------------------------------------------
-- `GetMicroIconForRole` (`Blizzard_SharedXMLBase/TextureUtil.lua:193`) is the game's global for
-- this, and it **raises an error** for an unknown role -- hence the table beside it
-- instead of a direct call with whatever comes from the picture.
local ROLE_MICRO_ATLAS = {
    TANK = "UI-LFG-RoleIcon-Tank-Micro-GroupFinder",
    HEALER = "UI-LFG-RoleIcon-Healer-Micro-GroupFinder",
    DAMAGER = "UI-LFG-RoleIcon-DPS-Micro-GroupFinder",
}

local CellPainters = {}

--- The portrait: the real face of whoever is still in the group; the class circle for the rest.
---
--- The degradation matters because the
--- kept scoreboard is opened days later -- when `SetPortraitTexture` no longer has a unit to
--- ask and the only identity left is the class.
function CellPainters.portrait(cell, entry)
    local row = entry.row or {}
    local class = row.classFilename

    local drew = false
    local name = row.name
    if name and not issecretvalue(name) and UnitExists and UnitExists(name) and SetPortraitTexture then
        drew = pcall(SetPortraitTexture, cell.portrait, name)
        if drew then cell.portrait:SetTexCoord(0, 1, 0, 1) end
    end

    if not drew or not cell.portrait:GetTexture() then
        local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
        if coords then
            cell.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
            cell.portrait:SetTexCoord(unpack(coords))
        else
            cell.portrait:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
            cell.portrait:SetTexCoord(0, 1, 0, 1)
        end
    end

    local role = row.role
    if role and ROLE_MICRO_ATLAS[role] and Atlas(cell.role, ROLE_MICRO_ATLAS[role]) then
        cell.role:Show()
    else
        cell.role:Hide()
    end

    -- The item level in the class colour. With no number, a dash: the
    -- dark plate stays, because the hole in the column is worse than the dash.
    local ilevel = row.ilevel
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    cell.ilvl:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    cell.ilvl:SetText(ilevel and ilevel > 0 and tostring(math.floor(ilevel + 0.5)) or "-")
end

function CellPainters.spec(cell, entry)
    ns.ApplyRowIcon(cell.icon, cell.iconClass, entry.source)
end

function CellPainters.name(cell, entry)
    local row = entry.row or {}
    -- A CLASS COLOUR ON THE NAME, which is the opposite of the combat window's rule -- there the class colours
    -- the BAR and the text stays white, because text in the class colour VANISHES inside a bar of the
    -- same colour. Here there is no bar: the name takes the colour and the
    -- background is neutral, so the collision that motivated that rule does not exist.
    local color = row.classFilename and RAID_CLASS_COLORS and RAID_CLASS_COLORS[row.classFilename]
    cell.text:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
    cell.text:SetText(ns.SplitName(row.name) or row.name or "?")
end

function CellPainters.keystone(cell, entry)
    local row = entry.row or {}
    local level = row.keystoneLevel
    local mapID = row.keystoneMapID

    local drew = false
    if mapID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local ok, _, _, _, texture = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok and texture then
            -- 0 is the game's "this dungeon has no icon": its own fallback, as its own tab does.
            if texture == 0 then texture = KEYSTONE_NO_ART end
            cell.icon:SetTexture(texture)
            cell.icon:SetTexCoord(0, 1, 0, 1)
            drew = true
        end
    end

    -- WITH NO KEYSTONE, THE CELL STAYS EMPTY -- and not with a dimmed generic icon. The reason is that here the absence has two different causes that cannot be told apart
    -- on screen: the player may have no keystone, or RocketMeter may have no way of knowing
    -- (see `KeystoneFor`). Drawing an icon in both cases would state the first.
    cell.icon:SetShown(drew)
    if cell.frameArt then cell.frameArt:SetShown(drew) end
    cell.levelBg:SetShown(drew and level ~= nil and level > 0)
    if drew and level and level > 0 then
        cell.level:SetText("+" .. level)
        cell.level:Show()
    else
        cell.level:Hide()
    end
end

Scoreboard.__paintKeystone = CellPainters.keystone

function CellPainters.score(cell, entry, index)
    cell.text:SetText(ScoreText(entry, index))
    cell.text:SetTextColor(1, 1, 1)
end

function CellPainters.loot(cell, entry)
    local link = entry.row and entry.row.loot
    if link == "" then link = nil end
    -- The tooltip only needs the link, so it is set before the icon (which waits for the cache).
    if cell.hit then
        cell.hit.link = link
        cell.hit:EnableMouse(link ~= nil)
    end
    if not link or not Item or not Item.CreateFromItemLink then
        cell.icon:Hide(); cell.border:Hide(); cell.ilvlBg:Hide(); cell.ilvl:Hide()
        return
    end

    -- `ContinueOnItemLoad` BECAUSE THE ITEM MAY NOT BE CACHED. Reading the icon and quality on the spot
    -- returns nil for an item the client has not downloaded yet, and the result is an empty square
    -- that is only fixed by reopening the panel -- which is how this defect would show.
    local ok, item = pcall(Item.CreateFromItemLink, Item, link)
    if not ok or not item then
        cell.icon:Hide(); cell.border:Hide(); cell.ilvlBg:Hide(); cell.ilvl:Hide()
        return
    end

    item:ContinueOnItemLoad(function()
        local quality = item:GetItemQuality()
        cell.icon:SetTexture(item:GetItemIcon())
        cell.icon:Show()
        cell.ilvl:SetText(item:GetCurrentItemLevel() or "")
        cell.ilvl:Show()
        cell.ilvlBg:Show()

        local atlas = LOOT_BORDER_BY_QUALITY and LOOT_BORDER_BY_QUALITY[quality]
        if atlas and Atlas(cell.border, atlas) then
            cell.border:Show()
        else
            cell.border:Hide()
        end
    end)
end

Scoreboard.__paintLoot = CellPainters.loot

function CellPainters.value(cell, entry, index)
    ns.SetCellText(cell.text, entry.values[index], columns[index].key)

    local best = entry.best and entry.best[index]
    -- The highlight colour: {230, 204, 128}/255. It is cream, not gold --
    -- and the workspace's skill explains why that matters: cream collides with no class colour
    -- at all, so it highlights without being read as "this is a rogue".
    if best and ns.db.highlightBest ~= false then
        cell.text:SetTextColor(230 / 255, 204 / 255, 128 / 255)
    else
        cell.text:SetTextColor(1, 1, 1)
    end
end

---The saved "My run" of the key on the board: same dungeon, same level, the newest one.
local function MyRunOf(ctx)
    if not (ctx and ns.MyRun and ns.MyRun.History) then return nil end
    for _, saved in ipairs(ns.MyRun.History()) do
        if type(saved) == "table" and saved.name ~= nil and saved.name == ctx.title
            and (ctx.level == nil or saved.level == nil or saved.level == ctx.level) then
            return saved
        end
    end
    return nil
end

---What a click on this row opens, or nil. Only the player's own row: of the others the game
---keeps nothing once the session is gone, and the board itself is all there is.
local function RowAction(entry)
    local mine = entry and entry.row and entry.row.isLocalPlayer
    if mine ~= true or not (ns.MyRunWindow and ns.MyRunWindow.Show) then return nil end
    if context and context.kind == "session" then
        return function() ns.MyRunWindow.Show() end
    end
    local saved = MyRunOf(context)
    if saved and ns.MyRunWindow.ShowRun then
        return function() ns.MyRunWindow.ShowRun(saved) end
    end
    return nil
end
Scoreboard.__rowAction = RowAction

local function DrawRows(list, rowCount)
    for i = 1, rowCount do
        local row = BuildRow(i)
        local entry = list[i]

        if not entry then
            row:Hide()
        else
            -- The alternating background, and only it. The class strip at the foot of the row went away. The class's identity
            -- stays in three places on the same row -- portrait, icon and the name's colour.
            row.bg:SetColorTexture(unpack(i % 2 == 1 and ROW_TINT_ODD or ROW_TINT_EVEN))

            for c = 1, #columns do
                local cell = row.cells[c]
                local painter = CellPainters[cell.kind]
                if painter then painter(cell, entry, c) end
            end

            row.open = RowAction(entry)
            row:EnableMouse(row.open ~= nil)
            row:Show()
        end
    end

    for i = rowCount + 1, #rows do
        rows[i]:Hide()
    end
end

--- The scoreboard's measures, so the test can check them.
---
--- What is locked with this is NOT "it looks nice" -- it is that the numbers are still the measured ones.
--- A refactoring that touches any of them starts failing, and that is what this door
--- exists for: a measure with no check becomes a memory.
function Scoreboard.__frame()
    return frame
end

function Scoreboard.DebugLayout()
    local widths = {}
    for c = 1, #ALL_COLUMNS do
        widths[ALL_COLUMNS[c].key] = ALL_COLUMNS[c].width
    end
    return {
        rowHeight = ROW_HEIGHT,
        rowSpacing = ROW_SPACING,
        lineInset = LINE_INSET,
        side = SIDE,
        headerHeight = HEADER_HEIGHT,
        colheadHeight = COLHEAD_HEIGHT,
        colheadLine = COLHEAD_LINE,
        colPadding = COL_PADDING,
        footerHeight = FOOTER_HEIGHT,
        titleY = TITLE_Y,
        titleSize = TITLE_SIZE,
        clockSize = CLOCK_SIZE,
        -- The context strip's size (out of combat, ilvl, deaths). It comes in because what the
        -- harness locks now is the HIERARCHY between the three, and not each one's numbers.
        idleSize = IDLE_SIZE,
        -- And what the harness needs to check that the stack FITS in the header strip, which is
        -- the defect the print of 10/09 showed: "no tempo +1" drawn inside the columns'
        -- strip. Without these three, one could only state things about loose font sizes.
        clockY = CLOCK_Y,
        resultGap = RESULT_GAP,
        resultSize = RESULT_SIZE,
        widths = widths,
        order = (function()
            local out = {}
            for c = 1, #ALL_COLUMNS do out[c] = ALL_COLUMNS[c].key end
            return out
        end)(),
        panelWidth = (function()
            local total = 0
            for c = 1, #ALL_COLUMNS do total = total + ALL_COLUMNS[c].width + COL_PADDING end
            return SIDE * 2 + total
        end)(),
        panelHeight = HEADER_HEIGHT + COLHEAD_HEIGHT + 5 * (ROW_HEIGHT + ROW_SPACING) + FOOTER_HEIGHT,

        -- The THREE sets that have to agree with each other: each `render` declared on a column
        -- has to have a builder and a painter. It was the lack of that agreement that left the
        -- score column without a builder and the panel without a body (print of 07/09 20:22).
        renders = (function()
            local vistos, out = {}, {}
            for c = 1, #ALL_COLUMNS do
                local kind = ALL_COLUMNS[c].render or "value"
                if not vistos[kind] then
                    vistos[kind] = true
                    out[#out + 1] = kind
                end
            end
            return out
        end)(),
        builders = (function()
            local out = {}
            for kind in pairs(CellBuilders) do out[kind] = true end
            return out
        end)(),
        painters = (function()
            local out = {}
            for kind in pairs(CellPainters) do out[kind] = true end
            return out
        end)(),
    }
end

--- What the top strip is SHOWING. It exists because the difference between "the number is right" and
--- "the number should not be there" can only be seen by asking the widget.
--- The run that is on screen, for the harness to make assertions about it.
---
--- `context` is local to the file and the loot test needs to see the row BEFORE and AFTER the item
--- arrives -- without this door, it would have to reopen the panel and infer from the drawing, which is measuring
--- something else.
function Scoreboard.DebugContext()
    return context
end

--- The real anchoring of the header's texts, read from the widgets.
---
--- ⚑ THEY ARE NOT THE CONSTANTS AGAIN. The defect of 10/09 was one of ARRANGEMENT -- three texts stacked on the
--- same axis, the last falling inside the columns' strip --, and a test that only adds constants
--- would keep passing if someone stacked everything again. Here what is read is where the widget really ended up.
function Scoreboard.DebugHeaderAnchors()
    if not frame then return nil end
    local function ancora(fs)
        if not fs or not fs.GetPoint then return nil end
        local ponto, relativo, relPonto = fs:GetPoint(1)
        return { point = ponto, relativeTo = relativo, relativePoint = relPonto }
    end
    return {
        title = ancora(frame.title),
        clock = ancora(frame.clock),
        result = ancora(frame.result),
        -- The footer comes in here because it COMPETED for this space: while it was anchored at the top
        -- right, the time block fell on it. Only a test that sees both catches that.
        footer = ancora(frame.footer),
        titleWidget = frame.title,
        clockWidget = frame.clock,
        clockInset = CLOCK_RIGHT_INSET,
    }
end

function Scoreboard.DebugHeader()
    if not frame then return {} end
    return {
        idleShown = frame.idle and frame.idle:IsShown() and true or false,
        idleText = frame.idle and frame.idle:GetText() or nil,
        ilvlShown = frame.ilvl and frame.ilvl:IsShown() and true or false,
    }
end

--- A row's drawn cells, so the test can state that it really exists.
function Scoreboard.DebugRow(index)
    local row = rows and rows[index]
    return row and row.cells or nil
end

function Scoreboard.Draw()
    if not frame or not context then return end

    -- Before everything: which columns this run has. The whole rest of the drawing reads from `columns`.
    columns = ComputeColumns()

    local rowCount = context.rowCount or 5
    local ceiling = MaxRowsOnScreen()
    if rowCount > ceiling then rowCount = ceiling end

    local list = CollectRows(rowCount) or {}

    -- (14/10) The board is a SNAPSHOT (its numbers are kept, readable): it is sorted here, by
    -- any column. Only the custom columns and the simulation were, from when the board read the
    -- live session in the API's order; a click on Interrupts gilded the header and moved nothing.
    -- `SortRows` keeps the order when a value cannot be read.
    local sortIndex
    for c = 1, #columns do
        if columns[c].key == sortBy then sortIndex = c end
    end
    if sortIndex then SortRows(list, sortIndex) end
    Scoreboard.lastList, Scoreboard.lastSortIndex = list, sortIndex

    if #list > 0 and #list < rowCount then rowCount = #list end
    if rowCount < 1 then rowCount = 1 end

    frame:SetSize(PanelWidth(), PanelHeight(rowCount))

    DrawHeader()
    BuildColumnHeader()
    DrawRows(list, rowCount)

    if context.demo then
        frame.footer:SetText(L["Simulation — invented data."])
        frame.footer:SetTextColor(1, 0.72, 0.2)
    else
        -- "há 2 dias" matters when the panel shows a kept run: without it there is no
        -- knowing whether that is from now or from last week.
        local age = RunAge(context)
        frame.footer:SetText(age or L["Click a column header to sort. Drag to move."])
        frame.footer:SetTextColor(0.5, 0.5, 0.5)
    end

    DrawTimeline()
end

--- A safety envelope: an error in the drawing loop cannot bring the whole panel down without
--- leaving a clue. The same defence the window uses.
---
--- It is a **public function** because the click on a column header needs it: calling a raw `Draw()`
--- from inside an `OnClick` makes the error vanish silently when `scriptErrors` is off
--- (the game's default), and then the user sees the column change colour and the rows not change.
function Scoreboard.Refresh()
    -- ⚑ IT DOES NOT RE-ENTER. See the note on `desenhando`: a drawing fired from inside another rewrites
    -- the caches in the middle of their use, and the error comes out somewhere else, with another face.
    if desenhando then return end
    desenhando = true

    local ok, err = pcall(Scoreboard.Draw)

    desenhando = false

    if not ok then
        Scoreboard.lastError = err
        ns.Print(L["error while drawing:"] .. " " .. tostring(err))
    end
end

local SafeDraw = Scoreboard.Refresh

function Scoreboard.Show(newContext)
    -- Opened by hand (or by the chest): nothing is waiting any more. Through the table: the wait
    -- is declared further down the file, and a local named here would be a nil global.
    if Scoreboard.CancelChestWait then Scoreboard.CancelChestWait() end
    context = newContext or context
    if not context then
        ns.Print(L["no run recorded in this session yet."])
        return
    end

    CreatePanel()
    SafeDraw()
    frame:Show()
end

function Scoreboard.Toggle()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end

    -- After a `/reload` there is no run in memory, but there may be one on disk. Without this
    -- `/rm score` answered "no run recorded" with the recorded run right beside it.
    if not context and Scoreboard.ShowMostRecent() then return end

    Scoreboard.Show()
end

--------------------------------------------------------------------------------
-- Simulation
--------------------------------------------------------------------------------
--- Opens the scoreboard with a made-up run.
---
--- It touches nothing real: `ns.Demo.Run` returns a loose table, and it is **not** saved to
--- disk. It exists to see the panel without running a dungeon -- testing the look of an
--- end-of-M+ scoreboard cost half an hour of play per tweak.
function Scoreboard.ShowDemo()
    if not ns.Demo then
        ns.Print(L["restart the client: the demo module was not loaded yet."])
        return
    end
    Scoreboard.Show(ns.Demo.Run())
end

--- Opens the last kept run of a type ("mplus" or "raid").
function Scoreboard.ShowLast(kind)
    local run = Scoreboard.GetRun(kind)
    if not run then
        ns.Print(kind == "raid" and L["no raid encounter recorded yet."]
            or L["no Mythic+ run recorded yet."])
        return
    end
    Scoreboard.Show(run)
end

---Abre a mais recente entre as duas guardadas.
function Scoreboard.ShowMostRecent()
    local mplus, raid = Scoreboard.GetRun("mplus"), Scoreboard.GetRun("raid")
    if mplus and raid then
        local a, b = mplus.recordedAt or 0, raid.recordedAt or 0
        Scoreboard.Show(a >= b and mplus or raid)
        return true
    end
    if mplus or raid then
        Scoreboard.Show(mplus or raid)
        return true
    end
    return false
end

function Scoreboard.HasRun(kind)
    return Scoreboard.GetRun(kind) ~= nil
end

--- Captures the run that ended, keeps it on disk and shows it.
---
--- The capture goes through `ns.RunWhenSafe`: in combat the session's numbers are secret and the picture
--- would come out empty. `Core.lua`'s queue already drains on `PLAYER_REGEN_ENABLED`, so the scoreboard of a
--- raid boss killed with adds still alive shows when the fight really ends -- which is
--- also when it is useful.
--- The death classes' guard, for the harness to exercise both branches.
---
--- A declared hook, in the style of `Picker.__probe`: it runs inside the capture, and without this door the
--- test of the "the counts disagree" branch would have to forge a whole run to get to it.
Scoreboard.__attachDeathClasses = AttachDeathClasses

--- The window in which the scoreboard keeps re-reading the columns that come from outside.
---
--- ⚑ IT EXISTS BECAUSE THERE IS NO EVENT FOR "THE GROUP FINISHED OPENING THE CHEST". Each one's new keystone
--- arrives when he opens it; the score, when the server recomputes. LibOpenRaid's notice covers
--- the keystone of whoever runs a compatible addon -- this window covers the rest, and also covers the case of the
--- lib not being present.
---
--- Two minutes, every 5 seconds, and **it stops as soon as nothing is missing**: while there is a
--- row with no keystone or no loot it keeps trying; once complete, it ends. (14/10) In practice it almost
--- always goes to the end: being without loot is normal for part of the group. The cost is one redraw
--- every 5 s for 2 minutes, once per key.
local JANELA_EXTERNA_SEGUNDOS = 120
local JANELA_EXTERNA_PASSO = 5

local reencostoAtual = 0
local function ReencostarAteCompletar(restante, corrente)
    -- (14/10) One chain at a time: the automatic path started one at the capture and another
    -- when the chest closed, two timers running side by side.
    if corrente ~= reencostoAtual then return end
    if not context or type(context.rows) ~= "table" then return end

    pcall(Scoreboard.RefreshExternalColumns)

    local falta = false
    for _, row in ipairs(context.rows) do
        if row.keystoneLevel == nil or row.loot == nil or row.ilevel == nil then
            falta = true
            break
        end
    end

    if not falta then
        if ns.Log then ns.Log.Add("placar", { externas = "completou" }) end
        return
    end

    restante = restante - JANELA_EXTERNA_PASSO
    if restante <= 0 then
        if ns.Log then
            ns.Log.Add("placar", { externas = "prazo esgotado; alguma linha ficou sem pedra ou saque" })
        end
        return
    end

    C_Timer.After(JANELA_EXTERNA_PASSO, function() ReencostarAteCompletar(restante, corrente) end)
end

local function Desde()
    local t0 = ns.scoreboardClock
    if not t0 or not GetTime then return nil end
    return math.floor((GetTime() - t0) * 10 + 0.5) / 10
end

--------------------------------------------------------------------------------
-- (!) THE KEYSTONE SCOREBOARD OPENS WHEN THE CHEST IS LOOTED (26/09)
--
-- The user asked for the items and the other players' keystones to show right on the
-- scoreboard. Ours opened 1.5 s after the key ended, before
-- anyone had opened the chest -- so there was no loot and no NEW key yet for anybody.
-- So the scoreboard captures at the end but SHOWS on `LOOT_CLOSED`:
-- by the time the player closes the chest the loot has
-- been handed out and every key has changed and been announced. Same here: the run becomes the
-- current one at once (so loot and keys stitch into it), and the panel appears on the first
-- LOOT_CLOSED; leaving the instance first cancels (`/rm score` still opens it).
--------------------------------------------------------------------------------
local pendente               -- the run waiting for the chest
local esperaBau = CreateFrame("Frame")

local function IniciarReencosto()
    if ns.Party and ns.Party.RequestKeystones then pcall(ns.Party.RequestKeystones) end
    reencostoAtual = reencostoAtual + 1
    ReencostarAteCompletar(JANELA_EXTERNA_SEGUNDOS, reencostoAtual)
end

esperaBau:SetScript("OnEvent", function(self, event, isLogin, isReload)
    if event == "LOOT_CLOSED" then
        self:UnregisterAllEvents()
        local run = pendente
        pendente = nil
        if run and context == run then
            pcall(Scoreboard.RefreshExternalColumns)
            Scoreboard.Show(run)
            if ns.Log then ns.Log.Add("placar", { fase = "aberto ao fechar o bau", segundos = Desde() }) end
            IniciarReencosto()
        end
    elseif event == "PLAYER_ENTERING_WORLD" and not isLogin and not isReload then
        self:UnregisterAllEvents()
        if pendente and ns.Log then ns.Log.Add("placar", { fase = "saiu sem abrir o bau" }) end
        pendente = nil
    end
end)

---True while a finished key waits for its chest (for the harness and `/rm score`).
function Scoreboard.IsWaitingForChest() return pendente ~= nil end

function Scoreboard.CancelChestWait()
    pendente = nil
    esperaBau:UnregisterAllEvents()
end

local function CaptureAndShow(base, kind, auto)
    base.kind = kind
    if ns.Log then
        ns.Log.Add("placar", { fase = "pedido", segundos = Desde(), emCombate = InCombatLockdown() and true or false })
    end
    ns.RunWhenSafe(function()
        if ns.Log then ns.Log.Add("placar", { fase = "captura", segundos = Desde() }) end
        -- Each death's class goes in BEFORE the picture, to travel with it to disk:
        -- a run reopened next week no longer has a meter session to ask.
        pcall(AttachDeathClasses, base)

        local ok, snapshot = pcall(Scoreboard.Snapshot, base)
        if not ok or not snapshot then
            ns.Print(L["error while drawing:"] .. " " .. tostring(snapshot))
            return
        end

        Scoreboard.SaveRun(kind, snapshot)
        -- (14/10) The newest run becomes the current one unless another is ON SCREEN: with the
        -- automatic board off, `/rm score` and the minimap reopened the run before, and the loot
        -- of this one stitched into that one.
        if not (frame and frame:IsShown()) then context = snapshot end

        -- `auto == false` is the opening asked for by hand (a button, `/rm score`): that one always shows.
        -- The automatic one obeys the content type's box -- there are two, because whoever wants the
        -- summary of every key does not necessarily want that of every raid boss.
        local wanted = kind == "mplus" and ns.db.autoScoreboardMPlus or ns.db.autoScoreboardRaid
        -- A KEY, opened by itself: wait for the chest (see above). The run is the current one
        -- already, so what arrives before the panel stitches into it.
        if kind == "mplus" and auto ~= false and wanted then
            context = snapshot
            pendente = snapshot
            esperaBau:RegisterEvent("LOOT_CLOSED")
            esperaBau:RegisterEvent("PLAYER_ENTERING_WORLD")
            if ns.Log then ns.Log.Add("placar", { fase = "esperando o bau", segundos = Desde() }) end
            IniciarReencosto()
            return
        end

        if auto == false or wanted then
            pendente = nil
            Scoreboard.Show(snapshot)
            if ns.Log then ns.Log.Add("placar", { fase = "aberto", segundos = Desde() }) end
        end

        -- And from here on the scoreboard stays alive: keystone, loot and score arrive in the following
        -- minutes, as each one opens the chest. Only in Mythic+ -- on a raid boss those three
        -- columns do not even exist.
        if kind == "mplus" then
            IniciarReencosto()
        end
    end)
end

--------------------------------------------------------------------------------
-- Gatilhos
--------------------------------------------------------------------------------
local function GroupRowCount()
    local size = GetNumGroupMembers()
    if not size or size < 1 then size = 1 end
    return math.min(size, MAX_ROWS)
end

function Scoreboard.OnChallengeCompleted()
    -- In 12.1.0 this function returns A TABLE. The positional branch stays
    -- because the client already changed the shape before and the cost of keeping it is one line.
    local a, level, timeMs, onTime, upgrades, _, scoreBefore, scoreAfter =
        C_ChallengeMode.GetChallengeCompletionInfo()

    local mapID = a
    if type(a) == "table" then
        mapID, level, timeMs, onTime = a.mapChallengeModeID, a.level, a.time, a.onTime
        upgrades = a.keystoneUpgradeLevels
        scoreBefore, scoreAfter = a.oldOverallDungeonScore, a.newOverallDungeonScore
    end

    -- A sanity guard: after a /reload inside the dungeon the client returns the table
    -- with mapChallengeModeID = 0, and the panel would open with an empty run.
    if mapID == nil or mapID == 0 then return end

    local mapName, timeLimit
    if mapID and C_ChallengeMode.GetMapUIInfo then
        local ok, name, _, limit = pcall(C_ChallengeMode.GetMapUIInfo, mapID)
        if ok then mapName, timeLimit = name, limit end
    end

    local deaths, timeLost
    if C_ChallengeMode.GetDeathCount then
        local ok, count, lost = pcall(C_ChallengeMode.GetDeathCount)
        if ok then deaths, timeLost = count, lost end
    end

    -- Affixes: `GetActiveKeystoneInfo`'s 2nd return is the list of ids. But the keystone is
    -- consumed on completion, so this call may come back empty exactly here -- hence the
    -- fallback to the week's affixes, which come as a list of tables with an `.id` field.
    -- Never hard-code an affix id: Midnight's family did not exist before.
    local affixes
    if C_ChallengeMode.GetActiveKeystoneInfo then
        local ok, _, ids = pcall(C_ChallengeMode.GetActiveKeystoneInfo)
        if ok and type(ids) == "table" and #ids > 0 then affixes = ids end
    end
    if not affixes and C_MythicPlus and C_MythicPlus.GetCurrentAffixes then
        -- `GetCurrentAffixes` returns nil while the client has not asked the server for the data.
        -- The request is asynchronous: waiting here is no use, but it leaves the list ready for
        -- the next run. `RequestMapInfo` is the trigger.
        if C_MythicPlus.RequestMapInfo then pcall(C_MythicPlus.RequestMapInfo) end

        local ok, week = pcall(C_MythicPlus.GetCurrentAffixes)
        if ok and type(week) == "table" then
            affixes = {}
            for i = 1, #week do affixes[i] = week[i].id end
        end
    end

    local seconds
    if timeMs and not issecretvalue(timeMs) then seconds = timeMs / 1000 end

    CaptureAndShow({
        title = mapName or L["Dungeon"],
        mapID = mapID,
        level = level,
        durationSeconds = seconds,
        timeLimit = timeLimit,
        onTime = onTime,
        upgrades = upgrades,
        deaths = deaths,
        timeLostToDeaths = timeLost,
        scoreBefore = scoreBefore,
        scoreAfter = scoreAfter,
        scoreGain = (scoreBefore and scoreAfter and scoreAfter > scoreBefore)
            and (scoreAfter - scoreBefore) or nil,
        affixes = affixes,
        combatTimeline = ns.Run and ns.Run.GetCombatTimeline(),
        knownFrom = ns.Run and ns.Run.GetKnownFrom() or 0,
        bosses = ns.Run and ns.Run.GetBosses(),
        deathMarks = ns.Run and ns.Run.GetDeaths(),
        sessionType = 1,   -- geral: a corrida inteira
        rowCount = GroupRowCount(),
    }, "mplus")
end

--- The star's seal for a raid difficulty: the initial, as the game does on its own
--- indicators (N / H / M).
---
--- It comes from `displayHeroic` / `displayMythic`, which are the fields the client gives precisely
--- for this -- instead of a table of difficulty ids, which changes from expansion to expansion. The
--- localised name's initial is the fallback, and it works in pt-BR (Normal, Heroico, Mítico).
local function DifficultyBadge(difficultyID)
    if not difficultyID or not GetDifficultyInfo then return nil, nil end

    local ok, name, _, _, _, displayHeroic, displayMythic = pcall(GetDifficultyInfo, difficultyID)
    if not ok then return nil, nil end

    if displayMythic then return "M", name end
    if displayHeroic then return "H", name end
    if type(name) == "string" and name ~= "" then
        return name:sub(1, 1):upper(), name
    end
    return nil, name
end

-- (!) THE SESSION BOARD (30/09). The user: *"podemos por um icone na janela do medidor que abra
-- o parcial da tela de scoreboard, sem a informação de chave e itens"*. The same board, with
-- what the meter's window shows now (the session the window is on), and without what only a
-- finished key has: keystone, score, loot, level, affixes, result, timeline. A snapshot, like
-- the others: opening again takes a new one.
function Scoreboard.ShowSession(sessionType)
    sessionType = sessionType or (ns.db and ns.db.sessionType) or 1
    local duration = ns.Data.GetDuration(sessionType)
    local seconds = (duration and not issecretvalue(duration)) and duration or nil

    -- The place: the key's dungeon when in one (with its art), else the instance or zone.
    local title, mapID
    if C_ChallengeMode and C_ChallengeMode.GetActiveChallengeMapID then
        local ok, id = pcall(C_ChallengeMode.GetActiveChallengeMapID)
        if ok and id and id ~= 0 and C_ChallengeMode.GetMapUIInfo then
            local okName, name = pcall(C_ChallengeMode.GetMapUIInfo, id)
            if okName and name then title, mapID = name, id end
        end
    end
    if not title and GetInstanceInfo then
        local ok, name = pcall(GetInstanceInfo)
        if ok and type(name) == "string" and name ~= "" then title = name end
    end

    CaptureAndShow({
        title = title or L["Session"],
        subtitle = sessionType == 0 and L["Current fight"] or L["Overall"],
        durationSeconds = seconds,
        result = sessionType == 0 and L["Current fight"] or L["Overall"],
        sessionType = sessionType,
        mapID = mapID,
        rowCount = GroupRowCount(),
    }, "session", false)
end

---The meter window's button. With something measured: the board of the session. With nothing
---measured (never fought, or the data was cleared): the last key, as its final board.
---
---(!) The user, 05/10: *"o botão do quadro parcial se não houver medição ou for resetado, faz
---ele mostrar a última pedra como se fosse o quadro final"*. An empty board answers nothing;
---the last key is what the player wants to look at when the meter has nothing to show.
function Scoreboard.ShowSessionOrLast(sessionType)
    sessionType = sessionType or (ns.db and ns.db.sessionType) or 1
    local duration = ns.Data.GetDuration(sessionType)
    -- A secret duration is a fight going on: there is something measured.
    local vazio = duration == nil or (not issecretvalue(duration) and (tonumber(duration) or 0) <= 0)
    if vazio then
        local ultima = Scoreboard.GetRun("mplus")
        if ultima then
            Scoreboard.Show(ultima)
            return "last"
        end
    end
    Scoreboard.ShowSession(sessionType)
    return "session"
end

function Scoreboard.OnEncounterEnd(encounterName, difficultyID)
    local duration = ns.Data.GetDuration(0)
    local seconds = (duration and not issecretvalue(duration)) and duration or nil
    local badge, difficultyName = DifficultyBadge(difficultyID)

    CaptureAndShow({
        title = encounterName or L["Encounter"],
        -- With no key level, the star carries the difficulty: it is the same role, and without it the
        -- raid scoreboard would not say whether the boss fell on normal or on mythic.
        badge = badge,
        subtitle = difficultyName,
        durationSeconds = seconds,
        result = "|cff40d878" .. L["defeated"] .. "|r",
        sessionType = 0,
        rowCount = GroupRowCount(),
    }, "raid")
end
