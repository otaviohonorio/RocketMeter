-- RocketMeter | Window.lua
--
-- The row is a BAR, not a spreadsheet cell: a dark background, a fill in the class colour
-- proportional to the value, the icon and name on top, the number on the right -- the format of the game's
-- native meter. The extra metrics come in as columns on the right, which is the gain over opening
-- one window per metric.
--
-- Each text's font, size and outline, the distances and the width are configurable; the window
-- resizes by the corner handle. There is no X: it hides through `/rm`, the minimap or the
-- addon compartment -- and never on ESC.
local ADDON, ns = ...
local L = ns.L

local Window = {}
ns.Window = Window

-- (14/10) The constants below are the skin (it follows the game's own meter); the player's
-- choices (font, sizes, outline, distances) live in `ns.db` and `ROLE_DEFAULTS`.
-- THE GAME'S CHAT FONT, because it was the reference the user gave: *"olha na primeira
-- imagem como tá o meu chat, como fica bem legível ele"*.
--
-- It is not a guess about which it is: `ChatFontNormal` inherits from `NumberFont_Shadow_Med`, which is
-- `Fonts\ARIALN.TTF` with `height="14"` and a black (1,−1) shadow
-- (`Blizzard_Fonts_Shared/Mainline/Fonts.xml:775-777`). The shadow was already ours; the
-- family and the size were missing.
--
-- Swapping the family settles the tension 0.50.0 left recorded. There, copying the native
-- meter's size (16, in Friz) was rejected in the game: its window shows ONE metric, ours
-- shows six columns, and more size became more ink. Arial Narrow is **condensed** -- it gives
-- a taller cap height (12px against Friz 13's 9px) spending LESS width per character. It grows
-- in height, which is where it was missing, and shrinks in width, which is where space was missing.
local FONT = "Fonts\\ARIALN.TTF"

-- THE FONTS THE GAME BRINGS, for the Roman alphabet. Only names that appear in the
-- declarations of `Blizzard_Fonts_Shared` come in -- inventing a font path gives no visible error, it gives
-- text that vanishes.
--
-- Morpheus and Skurri are decorative (quest titles and combat text) and look bad in a
-- column of numbers; they come in because the choice is the player's, not mine.
ns.FONT_CHOICES = {
    { path = "Fonts\\ARIALN.TTF",   label = "Arial Narrow" },
    { path = "Fonts\\FRIZQT__.TTF", label = "Friz Quadrata" },
    { path = "Fonts\\MORPHEUS.TTF", label = "Morpheus" },
    { path = "Fonts\\skurri.ttf",   label = "Skurri" },
}

-- Outline: the three levels WoW has, with names the player understands. The same scale as the
-- chat the user gave as reference (none / thin / thick).
-- THE THICKNESS OF THE MIDDLE GROUND, and it is continuous: the copies sit 1px from the glyph, so the envelope
ns.OUTLINE_CHOICES = {
    { value = "none",  flags = "" },
    { value = "thin",  flags = "OUTLINE" },
    { value = "thick", flags = "THICKOUTLINE" },
}
-- Measured on the official print side by side: the native meter's digits have an 11px cap
-- height; ours, at size 13, had 9px. FRIZQT gives ~0.69px of cap per point,
-- so 11px would ask for size 16 -- and 16 was tested in the game and rejected for being big.
--
-- The reason for not copying its number: Blizzard's window shows **one** metric, ours
-- shows six columns of numbers. The same letter height gives much more ink here, and
-- what is comfortable there becomes a block here. Matching the size would not match the density.
--
-- The search was 16 -> 14 -> 13 -> 12 -> **13**, each step seen in the game. 12 was tested and the
-- user went back: "aumenta para 13px, acho que fica melhor o tamanho do texto para a janela de
-- combate". (14/10: after that the body's default became 16, `ROLE_DEFAULTS.body`, with Arial
-- Narrow; the 13 holds as the search's history, not as today's number.)
--
-- It holds for the WHOLE row: the name and every cell, highlighted or not, in the sorted column or
-- not. That takes the font size off the list of highlight signals -- what is left to mark the
-- leader of a column is the colour (the class's own, lightened) and, for the sorted column, the
-- gold in the header. A size varying within the same row made the numbers' ruler dance.
--
-- In px of cap height, by the measured rate (~0.69px per point): 13 gives 9px, 12 gave ~8px.
-- THE DEFAULT SIZE. 16, and not the chat's 17: the chat takes the screen's width with one column of
-- text, and this window carries six columns of numbers at the same row height. It is the same
-- correction 0.50.0 made in the other direction -- a measure from outside counts as a starting point, not
-- as a target, because the density of the two screens is different.
local FONT_SIZE_DEFAULT = 16

-- THE CONFIGURABLE SIZE'S LIMITS, and both come from arithmetic, not taste.
--
-- CEILING 20 -- it comes from the CELL'S WIDTH. The cell is 50px (`COLUMN_WIDTH_FIXED` minus 8), and the
-- longest text `Data.FormatAmount` produces has 5 characters ("-339M", "10.0K"). In Arial
-- Narrow a digit advances ~0.5 of the size, so 5 digits take ~2.5×size:
--
--     2.5 × 20 = 50px   <- exactly the cell
--
-- One point above that and the number turns into an ellipsis again, which was the complaint of 0.54.0.
-- That is why the ceiling is 20 and not a round number chosen by eye.
--
-- FLOOR 10 -- below it the cap height is ~7px and the text stops being read at a glance in a
-- window that sits in the corner of the screen. There is no exact arithmetic reason here; it is the point where
-- the addon's very function gets lost.
-- The row's geometry. It moves up here because `ns.RowHeightFor` uses it, and a `local` declared after
-- a function resolves as a GLOBAL inside it -- that is, nil.
-- HOW MUCH THE NUMBER AND THE RATE RESERVE to the right of the bar. It is a fixed reserve, not a measure: measuring the
-- text at every frame would give a width that changes as the number grows ("9K" -> "12K" ->
-- "134K"), and the name would jump in size in the middle of the fight.
--
-- 96 = ~56 for the total (fits "1.2B") + ~34 for the rate + the slack between the two.
-- THE GUTTER between the end of the name and the first column. It already existed as a loose `10` inside the
-- name's arithmetic; it became a constant because now TWO sums depend on it -- the name's area and the
-- window's minimum width --, and a `10` typed in two places is the recipe for them to
-- drift apart, which is exactly the defect this file just had.
local NAME_GUTTER = 10

local NUMBER_RESERVE = 96

-- THE COLUMN CELL, now that it is a bar.
--
-- `CELL_GAP` separates a column from its neighbour: without it the bars touch and become one continuous strip,
-- and the eye loses where one metric ends and the other begins -- which is exactly the reading this
-- design exists to give.
--
-- `CELL_INSET` leaves the bar a bit lower than the row, so the bars of neighbouring rows
-- do not touch vertically.
--
-- THE DARK TRACK BEHIND THE BAR WENT AWAY, at the user's request: *"tira o fundo preto com algum
-- percentual de opacidade"*.
--
-- It existed to give the number ground on the EMPTY part of the bar -- which is where the number falls for
-- everyone but the column's leader. Without it, that part is the game's scenery.
--
-- ⚠️ So what holds the reading becomes ONLY the text's shadow. It is the same bet the
-- window already makes on the name and the clock (`ROW_BG_ALPHA = 0`, `WINDOW_ALPHA = 0`) and that the user already
-- approved there; if the number reads badly over light scenery, the fix is ITS outline/shadow, and
-- not bringing the box back -- it was the box he had taken out.
-- THE SLACK BETWEEN FAMILIES. The user's complaint: *"me incomodou a divisao das colunas, ta muito em
-- cima da anterior o comando da proxima, mais ainda o interrupt, comeca em cima do CPS"*.
--
-- He is describing the law of proximity broken. Damage+DPS are ONE bar and Healing+HPS are
-- another, but the space between the two families was the same 4px that separated anything: with no
-- difference of gap, the eye has no way of knowing where one metric ends and the other begins.
--
-- 10 is not a new number: it is `NAME_GUTTER`, which is already the gutter between the NAME and the metrics --
-- that is, the gap this addon already uses to say "here the subject changes". A family is another
-- subject for the same reason. One gap vocabulary, instead of two.
--
-- ⚑ AND IT COMES OFF THE GROUP'S LEFT, not both sides. Taking it from both, the bar's right edge
-- would move away from the column's right edge and the HEADER (which is anchored on the column, not on the
-- group) would stop sitting over the number it names. Coming only off the left, the gap shows
-- exactly where it needs to show -- between one family and the previous -- and the alignment of
-- header with number stays intact.
--
-- ⚑ 09/09/2026: IT BECAME CONFIGURABLE, with a default of **8** (the number the user gave). The old 10
-- becomes only the historical starting point.
--
-- What the default respects, and the slider cannot make respected: the ratio over the `CELL_GAP` of 4.
-- It is that -- and not the absolute value -- that makes the gap read as "the subject changes", and the floor
-- practised is **2×**. At 8 the ratio is exactly 2.0; at 6 it would be 1.5, which is literally the ratio
-- that produced the original complaint. Whoever takes the slider below 8 is choosing that, and the
-- control's minimum (4) exists so the choice is possible without being accidental.
local GROUP_GAP_DEFAULT = 8
local GROUP_GAP_MIN, GROUP_GAP_MAX = 4, 20
local CELL_GAP = 4
local CELL_INSET = 2

--- The slack between families, as the player left it.
local function GroupGap()
    local v = ns.db and ns.db.groupGap
    if type(v) ~= "number" then return GROUP_GAP_DEFAULT end
    if v < GROUP_GAP_MIN then return GROUP_GAP_MIN end
    if v > GROUP_GAP_MAX then return GROUP_GAP_MAX end
    return v
end

local TOTAL_WIDTH_DEFAULT = 84
-- 50 and 99 by request (10/09/2026). The default of 84 sits comfortably inside the range.
--
-- ⚑ WHAT CHANGES WITH THE FLOOR AT 50, said because it cannot be fixed from here: `ColumnWidthFor` returns
-- `math.max(resolution, measured text)`, so the column never gets smaller than the number needs. The
-- slider breaks nothing below the text's demand -- it **stops having an effect**, because the
-- text comes to rule. Measured on the print of 09/09 (1:1 with the game), "999.9M" in Arial Narrow 16
-- asks for ~51 px with the insets, so at 50 the end of the travel is already the real floor.
--
-- And the range changes with the typography: in a wide font, or at size 20, the text asks more and the
-- slider's silent stretch grows. That was already true with the floor at 56 -- the request only makes it a bit
-- more visible. If he drags to the end and the window does not shrink any more, it is this, and not a defect.
local TOTAL_WIDTH_MIN, TOTAL_WIDTH_MAX = 50, 99

---A largura da coluna de total, como o jogador deixou.
local function TotalWidth()
    local v = ns.db and ns.db.totalWidth
    if type(v) ~= "number" then return TOTAL_WIDTH_DEFAULT end
    if v < TOTAL_WIDTH_MIN then return TOTAL_WIDTH_MIN end
    if v > TOTAL_WIDTH_MAX then return TOTAL_WIDTH_MAX end
    return v
end

local ROW_HEIGHT_FIXED = 25   -- medido no nativo: linha de y=68 a y=92
local COLUMN_WIDTH_FIXED = 58
-- ⚑ THESE 3px WERE THE CLASS COLOUR STRIP at the foot of the row, removed at the user's request
-- on 08/09/2026 (*"remove a linha da cor da classe da coluna do nome"*). They STAYED, and on
-- purpose: taking them out reduces the row's height from 29 to 26 at the default size and re-spaces the whole
-- window -- a visible change nobody asked for. Today they are breathing room at the foot.
--
-- The name changed with it: a constant that describes what no longer exists is the cheapest way for the
-- next person to look for a strip that is not there.
local ROW_BOTTOM_ROOM = 3

local FONT_SIZE_MIN = 10
local FONT_SIZE_MAX = 20

-- Below here the outline GOES by itself. A 1px outline over a ~9px cap height is 11% of the
-- letter's height and closes the holes of the "a", the "e" and the "8" -- it becomes a blot. It is the same reason
-- why the scoreboard (size 12) never had an outline.
local OUTLINE_MIN_SIZE = 13

-- THREE INDEPENDENT TEXTS, each with its own size, outline and shadow.
--
-- They were deltas of a single size (−2, −3, −4), and the user rejected it for the right reason:
-- *"mudo um e ele faz pra tudo e fica ruim"*. A column header and the body of a row
-- of numbers have no reason to go together -- the first is a static label read once, the
-- second changes every second and is what is read at a glance.
--
-- The deltas become only each role's DEFAULT; from there each one is its own.
local ROLES = { "body", "title", "header" }

local ROLE_DEFAULTS = {
    body   = { size = 16, outline = "thin", shadow = true },
    title  = { size = 14, outline = "thin", shadow = true },
    header = { size = 12, outline = "none", shadow = true },
}

-- The clock lives in the title bar and follows the title, one point below. It did not become a fourth
-- control because nobody thinks of it as a separate text -- it is the title's time.
local CLOCK_DELTA = -1

--- The row height for a given size.
---
--- 25px is the measure taken from the native meter and is still the **floor**. With a
--- configurable size it cannot be only that: at 20 the text passes 20px between cap height,
--- descenders and outline, and there are still 3px of breathing room at the foot -- without growing along, the text
--- would touch the row below and the one above.
---
--- The factor 1.45 covers cap height + descender in Arial Narrow; the +2 are the outline's slack.
function ns.RowHeightFor(size)
    local needed = math.ceil(size * 1.45) + 2 + ROW_BOTTOM_ROOM
    if needed > ROW_HEIGHT_FIXED then return needed end
    return ROW_HEIGHT_FIXED
end

--- Rewrites in `ns.Skin` the values that depend on the size.
---
--- `ns.Skin` is a TABLE read by other screens, and they read the field, not a function. With a
--- fixed size that was enough; now it has to be redone at each change, or the scoreboard would keep
--- computing its delta against the old size.
function ns.RefreshSkin()
    ns.Skin.font = ns.FontPath()
    ns.Skin.fontSize = ns.RoleSize("body")
    ns.Skin.titleFontSize = ns.RoleSize("title")
    ns.Skin.clockFontSize = ns.RoleSize("title") + CLOCK_DELTA
    ns.Skin.colheadFontSize = ns.RoleSize("header")
    ns.Skin.fontOutline = ns.OutlineFor("body")
    ns.Skin.rowHeight = ns.RowHeightFor(ns.RoleSize("body"))
end

--- A role's settings, always complete and always within the limits.
---
--- It reads from the settings at every call instead of keeping them: so the configurator's step shows
--- on screen without `/reload`. And it falls back on the role's default when the key does not exist -- which is the case of
--- whoever updates the addon before the migration runs.
--- A text role's settings. **It never returns an incomplete table** -- and the guarantee
--- exists because its absence became an intermittent lock-up.
---
--- ⚠️ AN UNEXPLAINED SYMPTOM, and it stays recorded so on purpose. In ~3 of 12 harness rounds,
--- `ns.OutlineFor("body")` got from here a `config` with `size` AND `outline` nil and blew up at
--- `size < OUTLINE_MIN_SIZE` ("attempt to compare nil with number"), always at different points
--- of the test. I investigated with instrumentation, not with theory:
---
---  * `ns.db.text.body` was INTACT at the instant of the failure (size 16, outline "thin");
---  * `ROLE_DEFAULTS.body` too: 25 rounds with a write trap and none fired,
---    and a check inside this function never saw `base.size` stop being a number.
---
--- That is: both sources were right and the output came out wrong. I did not find the mechanism, and so
--- the comment says so instead of inventing a cause -- the next person deserves to know that the
--- armour below is a NET, and that the hole is still open.
---
--- The net is cheap and right on its own: whoever reads settings has the right to complete
--- settings, and no path from here should produce a missing field.
--- A role's SIZE, guaranteed to be a number.
---
--- It exists because `ns.RoleConfig(role).size` arrived nil at THREE different callers
--- (`ApplyRoleFont` and `OutlineFor`), in ~3 of 30 harness rounds, and the
--- investigation did not find the mechanism -- see the long comment in `RoleConfig`. Until it
--- is found, nobody reads a raw `.size`: they read through here.
function ns.RoleSizeSafe(role)
    local config = ns.RoleConfig(role)
    local size = config and config.size
    if type(size) ~= "number" then return FONT_SIZE_MIN end
    return size
end

function ns.RoleConfig(role)
    local base = ROLE_DEFAULTS[role] or ROLE_DEFAULTS.body
    -- Ate o `base` passa a ser conferido: se o padrao chegar quebrado, o piso de fonte responde.
    local baseSize = type(base.size) == "number" and base.size or FONT_SIZE_MIN
    local baseOutline = base.outline or "none"

    local saved = ns.db and ns.db.text and ns.db.text[role]
    if type(saved) ~= "table" then
        return { size = baseSize, outline = baseOutline, shadow = base.shadow ~= false }
    end

    local size = saved.size
    if type(size) ~= "number" then size = baseSize end
    if size < FONT_SIZE_MIN then size = FONT_SIZE_MIN end
    if size > FONT_SIZE_MAX then size = FONT_SIZE_MAX end

    return {
        size = size,
        outline = saved.outline or baseOutline,
        shadow = saved.shadow ~= false,
    }
end

function ns.RoleSize(role)
    return ns.RoleConfig(role).size
end

ns.ROLES = ROLES
ns.ROLE_DEFAULTS = ROLE_DEFAULTS

--- A ROLE's outline, already considering its size.
---
--- It takes the role and not the size because now each text has its own outline -- that was what
--- was missing, and the user rejected the single outline with the right reason: "quero mexer no contorno de
--- cada um tambem".
function ns.OutlineFor(role)
    local config = ns.RoleConfig(role)
    -- BELT AND BRACES, and the reason is in `RoleConfig`'s comment: this comparison
    -- blew up in production with a nil `size`, and the origin was not found. Until it is,
    -- the window cannot stop drawing because of it.
    local size = ns.RoleSizeSafe(role)
    local wanted = config.outline

    local flags = ""
    for _, choice in ipairs(ns.OUTLINE_CHOICES) do
        if choice.value == wanted then flags = choice.flags end
    end

    -- ONE STEP DOWN BELOW THE THRESHOLD, instead of obeying raw. The player chooses the intent; what he
    -- has no way of predicting is that the column header comes out four points smaller than the row, and
    -- that at a small size the outline closes the holes of the "a", the "e" and the "8". So each
    -- text that falls below the threshold goes down one level -- only it, not the whole window.
    if size < OUTLINE_MIN_SIZE then
        if flags == "THICKOUTLINE" then return "OUTLINE" end
        return ""
    end
    return flags
end

--- A role's shadow: alpha 0.8 when on, 0 when not.
function ns.ShadowAlphaFor(role)
    return ns.RoleConfig(role).shadow and 0.8 or 0
end

--- The chosen size, always within the limits.
---
--- It reads from the settings at every call instead of keeping it in a constant: so the
--- configurator's step shows on screen without `/reload`.
local FontSize

--- The ROWS' size. It stayed as a shortcut to `ns.RoleSize("body")` because half the file already
--- called it, and swapping everything for a longer name would only make a typing difference.
function FontSize()
    return ns.RoleSize("body")
end

-- THE SCOREBOARD does not follow this window. It was seen and approved at size 12, and the rise to 13
-- was asked for "a janela de combate" -- changing both together would undo an approval that already
-- exists. The same reason as `PANEL_FONT_SIZE`: a different screen, a different density, a size of its own.
local SCOREBOARD_FONT_SIZE = 12
-- The strip's title and the column header are ABSOLUTE values, not deltas: they do not follow the
-- row's size. In the native one the title measures 9px of cap against the row's 11px, and it is that difference
-- that gives its window's hierarchy.
--
-- TITLE, CLOCK AND HEADER FOLLOW THE ROW, as deltas -- not as loose numbers.
--
-- They were three absolutes, inherited from when the row was 13. Every time the row's size changed
-- (and it changed six times), the hierarchy came undone by itself: it got to the point of the title (13)
-- **tying** with the row (13), when in the native meter it is smaller -- it is exactly the smaller that
-- gives the hierarchy. The old comment here said "if it ends up shouting, the fix is here", which
-- is the description of a value that should have been derived and was not.
--
-- As a delta, the relation survives the next size change without anyone remembering it. Measured
-- in the native one: title ~0.82 of the content, which with the row at 16 gives 13-14.

-- Computed at reading time, not once at load: with a configurable size, keeping
-- the result would freeze the hierarchy at the value that held when the file loaded.
-- The breakdown panel has no equivalent in Blizzard's meter, so it does not follow the
-- row's size: it keeps its own, which is what was already approved. Growing along by inheritance
-- would be changing a screen nobody asked to change.
local PANEL_FONT_SIZE = 13
local PANEL_ROW_HEIGHT = 22
-- OUTLINE ON, and the decision is the user's -- not my inference.
--
-- I had measured the print of his chat and concluded "no outline, only a shadow". Wrong: the
-- chat is not Blizzard's, it is a chat addon, and the font was tuned by him. The setting
-- is on disk and says what he chose:
--
--     font      = ChatFontNormal
--     size      = 17           -- GetFontScalingFactor() = 17/14
--     outline   = thin         -- -> "OUTLINE"
--     shadow    = yes          -- -> "SHADOW"
--
-- That is: a **real** `OUTLINE`, plus a shadow, at size 17. That reverses two earlier
-- conclusions of this file, and it is worth recording why:
--
--   * "`OUTLINE` on everything got heavy" (0.48.0) was measured in **Friz 13**. In Arial Narrow 17
--     the outline's stroke is the same 1px over a much bigger glyph -- proportionally much
--     lighter. What weighed was the outline/glyph ratio, not the outline.
--   * The drawn halo existed to give a middle ground between "nothing" and `OUTLINE`. With the bigger size
--     the middle ground stopped being needed, and it stays off -- adding the two would double
--     the stroke.
-- There is no outline constant any more: `ns.OutlineFor(size)` decides, because with a
-- configurable size the right answer depends on each text's size. Calling `ns.ApplyFont` without the
-- third argument is the normal way; passing `""` is for whoever explicitly wants none
-- (the halo's copies).
-- The realm's name always comes one point below the character's name. Outside one's own realm the
-- server returns "Name-Realm", and at full size the two competed: the print of 05/09 showed
-- "Magicpandá-Tic…" -- name and realm fighting over the same width, and the ellipsis eating
-- both. Hierarchy by size solves it without hiding where the person is from.
local REALM_FONT_DELTA = -1
ns.REALM_FONT_DELTA = REALM_FONT_DELTA
-- Measuring the print side by side corrects what I had concluded before: the native meter's row
-- measures RGB(23,42,51) and the scenery beside it RGB(27,46,54) -- that is, **it is
-- transparent too**. So the black around its letters does not come from a dark background: it is a real
-- outline. Around the glyphs: median 10 in the name and 0 in the numbers. Our name already measures 0,
-- the numbers measured 34 -- the halo was right, it lacked font size to cover.
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"
-- The starting numbers, chosen to imitate the native meter:
--   0.4 -> the window's background
--   0.4 -> the dark background behind the fill
--   a bar of 20, 1 between bars, font 12
local BAR_BRIGHTNESS = 0.7          -- escurece a cor da classe para o texto branco ler
-- The native one's thin strip **is not flat**. Measured along it, over the same class colour
-- ours uses (163,164,255): 52% at the left end, 67% in the middle, 84% on the right. Ours
-- was flat at 100% -- that was exactly the difference of "o nosso tá mais claro".
-- THE TRACK and the SPARK.
--
-- `TRACK_ALPHA` = 0.15: the track tints the row's background with the class colour, and discreetly because
-- it shares space with the numbers.
--
-- `SPARK_ALPHA` = 0.35 is the gradient's peak, on the tip's side.
--
-- It DROPPED from 0.55 when the glow stopped having a fixed width. With a 10px trail, 0.55 was the
-- peak of a small smudge; now the gradient stretches over the whole fill, and the same 0.55
-- would wash the leader's bar white. 0.35 keeps the tip clearly lighter than the middle without
-- erasing the class colour underneath -- which is what the bar has to say who is who.
-- The breathing room between the number and the bar's edge. 3px is the same inset the text already had
-- when it was right-aligned -- what changed was the tip, not the margin.
local TEXT_INSET = 3

-- The breathing room BEYOND the inset, so the number does not touch its neighbour when the font is wide. 4px is the
-- same slack that separates two cells today (`CELL_GAP`), applied to the text.
local TEXT_ROOM = 4

-- ⚑ THE FONT SIZE IS NOT A SIGNAL. It did not become one now, and it cannot go back to being one.
--
-- It is the user's decision of 05/09/2026, already written in this file -- and which I disrespected on 09/09
-- by making the pair's companion three points smaller. He had it undone the same day, with a print:
-- *"o texto cada um parece em uma escala ou tamanho de fonte diferente, ficou bizarro, esse tipo
-- de erro nao pode mais acontecer"*.
--
-- Two reasons, and the second only showed on screen:
--
-- 1. **The vertical ruler dances.** Numbers of the same column changing size from row to
--    row take away the reference that makes a table readable at a glance.
-- 2. **The step crossed the OUTLINE's threshold.** With size 13 and `OUTLINE_MIN_SIZE` also 13, the
--    companion dropped to 10 and lost the outline ALONG with the size -- two changes at
--    once, and that is why it read as "different scales" instead of hierarchy.
--
-- The hierarchy left is COLOUR, which touches no metric. Weaker on purpose: it is the
-- price of not touching the size, and the size is not in play.
--
-- The constant stays at ZERO, and does not go away, so the next one who thinks of using the size as a signal reads
-- this before trying.
local PAIR_DELTA = 0

-- The trio's SEPARATOR. A middle dot, in the dimmed colour, between neighbouring numbers.
--
-- It only shows with THREE members, at the user's request. With two it would be worse than nothing: they are
-- at the two ends of the bar, far from each other, and a loose dot in the middle would separate nothing --
-- it would look like dirt. With three, the neighbours come closer and the mark gets a job.
local DOT_TEXT = "\194\183"     -- U+00B7 MIDDLE DOT, em UTF-8
local DOT_DELTA = -4

local TRACK_ALPHA = 0.15
local SPARK_ALPHA = 0.35

local BAR_GRADIENT_MIN = 0.52
local BAR_GRADIENT_MAX = 0.84
-- The row's background fully transparent: with the window without a background, a partial black behind
-- each row is a halfway thing -- it shows as a grey rectangle floating over the scenery. What
-- holds the reading is the text's shadow, and the separation between rows comes from the progress strip.
local ROW_BG_ALPHA = 0

-- An invisible background: the "No Background" variant approved by the user, like the native meter.
-- What holds the reading is the text's shadow; the separation comes from the progress strip.
local WINDOW_ALPHA = 0

-- Proportion: in a 32px strip with 13pt text, the text takes ~40% of the height. With 20px and 13pt I had 65% -- hence the cramped feeling.
-- Exposed for the other panels (breakdown, scoreboard) to follow the same language without
-- copying values -- copying is what makes screens drift apart over time.
ns.Skin = {
    font = FONT,
    fontSize = ROLE_DEFAULTS.body.size,
    -- The COMBAT WINDOW's outline. The scoreboard (size 12) and the breakdown panel (13)
    -- pass `""` on purpose: a 1px outline over a ~8px glyph closes the letter's holes,
    -- and both were already seen and approved without it. If one day they have to follow,
    -- the fix is swapping their `""` for `ns.Skin.fontOutline`.
    fontOutline = "OUTLINE",
    -- Sizes with a value of their own, exposed so the other screens do not retype the literal: the
    -- scoreboard had an `11` hard-coded that would have had to be hunted by hand if this changed.
    colheadFontSize = ROLE_DEFAULTS.header.size,
    titleFontSize = ROLE_DEFAULTS.title.size,
    clockFontSize = ROLE_DEFAULTS.title.size + CLOCK_DELTA,
    -- The size's limits, exposed so the configurator does not retype the numbers.
    fontSizeMin = FONT_SIZE_MIN,
    fontSizeMax = FONT_SIZE_MAX,
    rowsMin = 1,
    rowsMax = 20,
    -- The limits of the two configurable distances. Exposed for the same reason as the font's: the
    -- screen reads from here, so there is no way for the slider to offer a value the drawing refuses.
    groupGapMin = GROUP_GAP_MIN,
    groupGapMax = GROUP_GAP_MAX,
    totalWidthMin = TOTAL_WIDTH_MIN,
    totalWidthMax = TOTAL_WIDTH_MAX,
    -- Exposed because the size's ceiling comes from it: a cell's longest text has to
    -- fit here, and that is what the harness checks.
    columnWidth = COLUMN_WIDTH_FIXED,
    -- A folga entre familias de metrica. Exposta porque o teste afirma sobre ela, e travar
    -- o numero no teste faria a proxima mudanca de folga reprovar por design.
    groupGap = GROUP_GAP_DEFAULT,
    scoreboardFontSize = SCOREBOARD_FONT_SIZE,
    barTexture = BAR_TEXTURE,
    barBrightness = BAR_BRIGHTNESS,
    rowHeight = ROW_HEIGHT_FIXED,
    panelRowHeight = PANEL_ROW_HEIGHT,
    rowSpacing = 1,
    rowBackground = { 0, 0, 0, ROW_BG_ALPHA },
    -- The reading panel has a background of its own, so there the rows get a light black to
    -- separate. In the transparent window that would become a grey stripe -- hence two values.
    panelRowBackground = { 0, 0, 0, 0.25 },
    windowAlpha = WINDOW_ALPHA,
    -- The window is an overlay over the game and stays transparent; a reading panel asks for a background,
    -- or the text competes with the scenery. Hence two alphas instead of one.
    panelAlpha = 0.70,
    -- The scoreboard is the most opaque of the three: it opens over everything at the end of the run, takes
    -- half the screen and carries the dungeon's background art. A value of its own, not `panelAlpha + 0.22`
    -- added at the place of use -- a token that becomes a sum loses its role as the single source of truth.
    scoreboardAlpha = 0.92,
    headerAtlas = "ui-damagemeters-header-bar",
    -- NO CROPPING AT ALL -- neither vertical nor horizontal.
    --
    -- Vertical: the 4/60 crop I used ate the atlas's edge rows. In the native one
    -- they show whole -- a faint 2px gold on top and a strong 2px one at the bottom, peak
    -- RGB(197,169,3); with the crop our peak fell to 131.
    --
    -- Horizontal: the 0.045..0.965 I used went unchecked,
    -- with the excuse that "the ends are the corners". Measured in the atlas's own PNG
    -- (`ui-damagemeters-header-bar`, 560x56), the ends are
    -- **the alpha ramp** -- the tapering that makes the strip look like a ribbon:
    --
    --     x 0..16    alpha 0        (transparent padding)
    --     x 17..~70  alpha 0 -> 154 (the ramp: the tapered tip)
    --     x ~70..484 alpha 154      (the body)
    --     x 484..545 alpha 154 -> 0 (the ramp on the other side)
    --
    -- 0.045 of 560 is x=25, that is **in the middle of the ramp**, where the alpha is already 40. Cutting there
    -- throws away the tapering and leaves a vertical wall of alpha 40 -- the straight cut the
    -- user circled on the print of 05/09 comparing with the quest tracker, which shows
    -- the same art with the whole tip.
    headerCrop = { 0, 1, 0, 1 },
    gold = { 1, 0.82, 0 },
    cream = { 1, 0.88, 0.62 },
    text = { 0.86, 0.87, 0.90 },
    dim = { 0.68, 0.69, 0.72 },
}

--- Applies Blizzard's header art to a texture, with the crop measured in the atlas itself.
function ns.ApplyHeaderArt(texture)
    local info = C_Texture and C_Texture.GetAtlasInfo
        and C_Texture.GetAtlasInfo(ns.Skin.headerAtlas)

    if info and (info.file or info.filename) then
        texture:SetTexture(info.file or info.filename)
        local l, r = info.leftTexCoord or 0, info.rightTexCoord or 1
        local t, b = info.topTexCoord or 0, info.bottomTexCoord or 1
        local w, h = r - l, b - t
        local crop = ns.Skin.headerCrop
        texture:SetTexCoord(l + w * crop[1], l + w * crop[2], t + h * crop[3], t + h * crop[4])

        -- No tinting: the art is the same as the native meter's, and it draws it raw. The 0.78
        -- I applied to darken the strip's body erased the gold edges along with it --
        -- our body 32 against its 35 (a hit of 3), our edge 131 against its 197 (a miss
        -- of 66). Trading a hit of 3 for a miss of 66 is the wrong deal.
        texture:SetVertexColor(1, 1, 1)
        return true
    end

    texture:SetColorTexture(0.13, 0.11, 0.07, 0.95)
    return false
end

local HEADER_HEIGHT = 27        -- medido no nativo: faixa de y=41 a y=67
local COLHEAD_HEIGHT = 12
local NAME_MIN_WIDTH = 96
-- The minimum width of the button that switches session ("Combate atual" / "Geral"). It is a MINIMUM, not fixed:
-- when the scroll indicator goes into the text the button grows along (see Window.Draw).
local SEGMENT_MIN_WIDTH = 120
local PADDING = 3
-- In the native one the text sits **centred on the row**, not raised: the glyphs' centre at y=81 against
-- the row's centre at y=80.5. The slack to the coloured strip comes from the row being taller (25px),
-- not from pushing the text up -- there 1px is left between the letter's base and the strip.
local TEXT_LIFT = 0
local MIN_ROWS = 1              -- one row is still useful: only you, on the training dummy
local MAX_ROWS = 20             -- a raid's size; above that the window takes the screen
local GRIP = 14

-- THE PADLOCK HAS TO CHANGE SHAPE, NOT COLOUR.
--
-- Until 0.54.0 the two states used the SAME texture and only swapped the tone: gold when
-- locked, grey when not. On a 14px glyph that cannot be read -- the user said he could not
-- tell. And the lesson was already recorded in this project, in the saga of the leader
-- highlight: **colour alone was weak**.
--
-- There is no padlock in the `common-icon-*` family (checked: they are 26 glyphs and none is).
-- `Interface\Buttons\LockButton-Locked-Up` / `-Unlocked-Up` exist and make an open/
-- closed pair, but they are **button art** with a frame and relief -- they were rejected in 0.43.1 for the
-- "Windows XP button in the middle of flat icons" effect.
--
-- The way out is saying the same thing with another pair:
--
--   unlocked -> `common-icon-move`, the cross of arrows. A flat glyph, of the SAME family as the
--               header's other buttons, and it says exactly what the state means:
--               "it can be dragged". Confirmed in the 12.1.0 source, in
--               `Blizzard_HouseEditor/Blizzard_HouseEditorLayoutModePin.xml:289`, used
--               as `iconAtlas`.
--   locked   -> the usual padlock, which is already on screen and therefore known valid.
--
-- The two shapes are unmistakable at 14px. If the atlas does not exist in this client, the fallback
-- is the old behaviour (the same icon, different tones) -- never an empty button. `/rm atlas`
-- says which of the two paths holds.
local LOCK_ICON = "Interface\\PetBattles\\PetBattle-LockIcon"
local UNLOCK_ATLAS = "common-icon-move"

local CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

function ns.BarTexture()
    return BAR_TEXTURE
end

--- Does this atlas exist in this client?
---
--- `SetAtlas` with a name that does not exist **fails silently**: the texture stays as it was and
--- nothing warns. Asking first is what separates "the icon changed" from "the icon stays the same and I
--- do not know why". The same guard the scoreboard already uses; `/rm atlas` lists the checked names.
function ns.AtlasExists(name)
    if name == nil then return false end
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    return info ~= nil
end

-- Where each column lives inside its group, from the header's last drawing. Kept so the
-- test door can compare the label with the number -- without it, "they start at the same x"
-- would be a sum redone, and a sum redone agrees with itself.
local ondeFicaCache = {}

--- A frame's RIGHT margin, read from its anchors.
---
--- ⚑ IT EXISTS SO THE TEST DOORS DO NOT MEASURE THE FORMULA. The first version of `inkX` repeated
--- `PADDING` by hand on both sides -- and so the sabotage "the header gets its own margin
--- back" went unnoticed: changing `headerRow`'s `SetPoint` did not touch a number that did not come
--- from it. A sum redone agrees with itself.
local function MargemDireita(frame_)
    for i = 1, (frame_.GetNumPoints and frame_:GetNumPoints() or 0) do
        local ponto, _, _, x = frame_:GetPoint(i)
        if ponto == "TOPRIGHT" or ponto == "RIGHT" or ponto == "BOTTOMRIGHT" then
            return -(x or 0)
        end
    end
    return PADDING
end

local frame, headerRow, rows
local dirty, throttle = false, 0
local visibleRows = -1
local scrollOffset = 0      -- quantas linhas foram roladas para fora do topo
local totalRows = 0         -- quantos atores existem ao todo, para limitar a rolagem

--------------------------------------------------------------------------------
-- Fonte e cor
--------------------------------------------------------------------------------
--- The chosen font, or the default one if the chosen one is no longer available.
---
--- A font coming from another addon (through LibSharedMedia) goes away when that addon is uninstalled,
--- and the path saved here keeps pointing at a file that does not exist. `SetFont` with an
--- invalid path **does not draw** -- the text vanishes, with no error. That is why the choice is always
--- validated before becoming the drawing default (see `ns.ApplyFont`).
function ns.FontPath()
    local chosen = ns.db and ns.db.font
    if type(chosen) == "string" and chosen ~= "" then return chosen end
    return FONT
end

--- The font that REALLY draws. If the chosen one fails, it falls back on the default and warns once.
local fontWarned
local function SafeSetFont(fontString, path, size, flags)
    local ok = pcall(fontString.SetFont, fontString, path, size, flags)
    -- `SetFont` returns `false` when the file does not serve (`RequiresValidFontAsset = true` in the
    -- API documentation). Testing both covers both ways of failing.
    if ok and fontString:GetFont() then return true end

    if path ~= FONT then
        if not fontWarned then
            fontWarned = true
            ns.Print(format(L["the font %s could not be loaded; using the default."],
                tostring(path)))
        end
        return pcall(fontString.SetFont, fontString, FONT, size, flags)
    end
    return false
end

--- Applies a ROLE's font. `delta` adjusts the size for secondary texts of the same role
--- (the clock, the realm), which keep following the role they belong to.
---
--- The signature takes the role, and not the size, and that is what allows the three independent
--- texts: each call says **who it is**, and that role's settings decide size,
--- outline and shadow. With one size only, changing one changed all -- which was the rejection.
function ns.ApplyRoleFont(fontString, role, delta, flagsOverride)
    local config = ns.RoleConfig(role)
    local size = ns.RoleSizeSafe(role) + (delta or 0)
    if size < 6 then size = 6 end

    local flags = flagsOverride
    if flags == nil then flags = ns.OutlineFor(role) end

    SafeSetFont(fontString, ns.FontPath(), size, flags)

    -- A 1px shadow carries the white text over the coloured bar without the outline's weight.
    -- Alpha 0.8, not 1: it is what the reference chat uses on the shadow, and the
    -- legibility reference was that chat window. Full black added to the outline
    -- thickens the stroke twice on the same pixel.
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, config.shadow and 0.8 or 0)

end

--- The rows' size, for whoever has a size of its own and only needs to inherit outline and shadow: the
--- scoreboard and the breakdown panel come in here.
function ns.ApplyFont(fontString, delta, flags)
    local size = ns.RoleSize("body") + (delta or 0)
    if size < 6 then size = 6 end

    if flags == nil then flags = ns.OutlineFor("body") end

    SafeSetFont(fontString, ns.FontPath(), size, flags)
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, ns.ShadowAlphaFor("body"))
end

--- The reading panel's font, which has a size of its own (see `PANEL_FONT_SIZE`).
function ns.ApplyPanelFont(fontString, delta, flags)
    -- `FontSize()`, not the constant: the delta is relative to the window's CURRENT size. With the
    -- constant, changing the window's size would drag along a panel that has its own size.
    ns.ApplyFont(fontString, (delta or 0) + PANEL_FONT_SIZE - FontSize(), flags)
end

--- The end-of-run scoreboard's font, which also has a size of its own.
function ns.ApplyScoreboardFont(fontString, delta, flags)
    ns.ApplyFont(fontString, (delta or 0) + SCOREBOARD_FONT_SIZE - FontSize(), flags)
end

--------------------------------------------------------------------------------
-- An outline with an adjustable thickness
--------------------------------------------------------------------------------
-- WoW only has three outline levels (none, `OUTLINE`, `THICKOUTLINE`) -- nothing in between.
-- For a middle ground, the outline is **drawn**: black copies of the text shifted 1px behind

--
-- IT IS OFF (an empty list), and the reason is measured, not taste.
--
-- The user pointed at his chat window as the legibility standard -- "olha na primeira
-- imagem como tá o meu chat". Measured on the print of 05/09/2026: the chat **has no outline**, only
-- a black `SetShadowOffset(1, -1)`, which is exactly the shadow `ns.ApplyFont` already applies. What
-- was left here was the halo ON TOP of it.
--
-- And it was lopsided: `{-1,0}` and `{0,1}` put a copy to the left and above, while the shadow
-- sits below and to the right. Three sides covered, one not -- hence "umas colunas parece tá com mais
-- borda a fonte, outras não". It was not an impression: it depended on which side of the glyph touched the
-- neighbour, and changed from column to column.
--
-- That was written in 0.49.0 and ended in "if one day it is missed". It was: the user tested the
-- two outlines and asked for the middle ground -- "são bem gritantes as diferenças, senti falta de um
-- 'meio termo' dos dois". The machine comes back, with the TWO fixes that had turned it off:
--
--   1. Symmetry: the two offsets before ({-1,0} and {0,1}) covered left and top and
--      left right and bottom to the shadow -- three sides one way, one another. That was the
--      "umas colunas parece tá com mais borda a fonte, outras não": it was not an impression,
--      it depended on which side of the glyph touched the neighbour.
--   2. It only comes in when the role asks ("medium"). Before it added to the shadow on every text, and
--      two strokes on the same pixel thicken twice.
--
-- AND THE MEDIUM'S FIRST ATTEMPT WAS GEOMETRICALLY WRONG -- the report: "o contorno médio tá
-- igual ao fino". It was, and by construction. It put four copies shifted **1px**,
-- which is EXACTLY where the text's own `OUTLINE` already paints solid black. The copies fell
-- under what was already there and could not show. Shifting thickens nothing while the
-- shift fits inside the outline that already exists.
--
-- THE RIGHT CONSTRUCTION DOES NOT SHIFT: it stacks. `OUTLINE` paints a 1px ring; `THICKOUTLINE`
-- paints a 2px one. The middle ground is the 2px ring **at partial opacity** under the solid
-- 1px one:
--
--     copy  (behind, alpha α):  THICKOUTLINE  -> black from 0 to 2px
--     text  (in front):         OUTLINE       -> black from 0 to 1px, solid, + the glyph on top
--     seen:                     solid up to 1px, α from 1px to 2px
--
-- The copy's black body stays hidden under the original's glyph, which has the same size,
-- same font and same position -- only the outer ring is left, which is what was wanted. And it costs **one**
-- copy, not four: with zero shift there is no uncovered side, so symmetry stops being
-- a problem to solve and becomes a consequence.
--- Splits `"Name-Realm"` into name and realm.
---
--- The realm **does not vanish**. The first attempt erased it with `Ambiguate`, and it was wrong: the
--- user wants to see where the person is from (decision of 05/09/2026). The problem in that day's print
--- -- `Magicpandá-Tic…`, `Huntwave-Stor…` -- was not the realm existing, it was the realm taking the same
--- letter width as the name and pushing both into the ellipsis. The solution is hierarchy, not
--- removal: the realm comes in **one point smaller** than the name.
---
--- In combat the name can be secret. `string.match` on a secret is forbidden, so in that case it
--- comes back whole in the first return and with no realm -- the widget knows how to draw the raw value, which is
--- exactly the right behaviour.
--- @return string|nil name
--- @return string|nil realm  without the hyphen; nil when the name has no realm
function ns.SplitName(full)
    if full == nil or issecretvalue(full) or type(full) ~= "string" then
        return full, nil
    end

    -- The hyphen separates; a character name has no hyphen, a realm name may have a space.
    local name, realm = full:match("^([^%-]+)%-(.+)$")
    if name and realm ~= "" then return name, realm end
    return full, nil
end

--- Writes name and realm on one row, splitting the width between the two.
---
--- The split cannot be fixed: it depends on the text. `row.name` gets the width of its
--- own text (limited by the area) so the realm sticks right after it; without that the realm
--- would show at the end of the name's box, with a gap in the middle. What is left goes to the realm, which
--- cuts into an ellipsis when it does not fit -- cutting the realm is acceptable, cutting the name is not.
---
--- Whoever has both fields is `row` because the window and the scoreboard build the row the same way;
--- the function lives here so the two screens do not drift apart.
--- @param row table a row with `name`, `realm` and `nameArea`
--- Writes the name (and, if the player wants, the realm) inside the row's area.
---
--- **The halo's width has to be changed along with the text's, in BOTH branches.** Only the branch
--- with a realm did it; the branch without one changed the text's width and left the black
--- copies with the previous row's width. Since the halo is the outline, the effect was the name coming out
--- with a stroke different from the others -- and it showed precisely on the player's own
--- character, who usually is on the same realm and therefore has no suffix.
local function SetNameWidth(row, width)
    row.name:SetWidth(width)

end

local function SetRealmWidth(row, width)
    row.realm:SetWidth(width)

end

function ns.DrawName(row, full)
    local name, realm = ns.SplitName(full)

    -- The realm is optional and comes OFF: it eats the width of what matters and, with a narrow
    -- column, turned "Frenchmiku-Tichondrius" into "Frenchmiku-Tich…". Whoever plays in
    -- cross-realm groups and wants to see where the person is from turns it on in `/rm columns`.
    if not ns.db.showRealm then realm = nil end

    local area = row.nameArea or 0
    SetNameWidth(row, area)
    row.name:SetText(name)
    row.name:SetTextColor(1, 1, 1)

    if not realm or area <= 0 then
        row.realm:SetText("")
        SetRealmWidth(row, 0)
        return
    end

    -- `GetStringWidth` measures the text ignoring the box, so it tells how much it
    -- really takes before deciding the split.
    local used = row.name:GetStringWidth() or 0
    if used > area then used = area end
    SetNameWidth(row, used)

    local left = area - used
    if left < 12 then
        -- The name alone already takes the area: the realm does not fit and goes away. Better to vanish whole than
        -- show up as a loose hyphen followed by an ellipsis.
        row.realm:SetText("")
        SetRealmWidth(row, 0)
        return
    end

    SetRealmWidth(row, left)
    row.realm:SetText("-" .. realm)
    row.realm:SetTextColor(unpack(ns.Skin.dim))
end

--- In combat `classFilename` can be secret, and indexing a table with a secret key is forbidden.
local function SafeClass(classFilename)
    if classFilename == nil or issecretvalue(classFilename) then
        return nil
    end
    return classFilename
end

function ns.ClassColor(classFilename)
    local class = SafeClass(classFilename)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if color then
        return color.r, color.g, color.b
    end
    return 0.45, 0.5, 0.62
end

--- Paints the thin strip with the native meter's horizontal gradient.
---
--- Its strip darkens to the left: 52% of the class colour at the start, 84% at the end. Flat at
--- 100%, as I did, is what made ours visibly lighter than its.
---
--- Order matters: `SetStatusBarColor` touches the vertex colour, and that is what the gradient replaces --
--- calling them in the reverse order would erase the gradient.
function ns.ApplyBarColor(bar, classFilename)
    local r, g, b = ns.ClassColor(classFilename)
    local texture = bar:GetStatusBarTexture()

    if texture and texture.SetGradient and CreateColor then
        bar:SetStatusBarColor(1, 1, 1)
        texture:SetGradient("HORIZONTAL",
            CreateColor(r * BAR_GRADIENT_MIN, g * BAR_GRADIENT_MIN, b * BAR_GRADIENT_MIN, 1),
            CreateColor(r * BAR_GRADIENT_MAX, g * BAR_GRADIENT_MAX, b * BAR_GRADIENT_MAX, 1))
        bar.__gradient = true
        return
    end

    -- A client without gradients: the average of the two ends is the tone the eye reads overall.
    local k = (BAR_GRADIENT_MIN + BAR_GRADIENT_MAX) / 2
    bar:SetStatusBarColor(r * k, g * k, b * k)
end

--- A bar's TRACK: the whole path, in the class colour, very faded.
---
--- ⚠️ IT IS NOT THE BLACK BACKGROUND. The user rejected that one twice (*"tira o fundo preto com algum
--- percentual de opacidade"*, *"o fundo preto é feio"*) and asked for this one (*"eu quero ... Pista
--- tingida. Sem fundo preto"*). The difference is not of opacity, it is of colour: black stacks a dark
--- block per row and kills the window's transparency; the faded class colour reads as the
--- **rest of the path** of the bar itself.
---
--- `mostrar = false` leaves the track invisible -- that is the "zeroed" case, where there is no path at all.
function ns.ApplyTrackColor(texture, classFilename, mostrar)
    if not mostrar then
        texture:SetColorTexture(0, 0, 0, 0)
        return
    end
    local r, g, b = ns.ClassColor(classFilename)
    texture:SetColorTexture(r, g, b, TRACK_ALPHA)
end

--- THE SPARK: the fill lights up towards the tip.
---
--- It is white and additive, with the alpha rising from left to right -- the glow lives at the
--- **end**, which is where the bar got to. And it takes exactly the fill, no more no
--- less: both ends are pinned to it, so a 2px bar has 2px of glow. It is not a class colour: class colour is reserved vocabulary
--- in this project (gold reads as "rogue", not as "leader"), and additive white over the bar itself
--- lightens the colour already there instead of introducing another.
---
--- The amplitude comes from the scale measured in the client: Blizzard uses alpha up to **0.15** for "available,
--- discreet" (a selectable talent) and **0.45->0.55 over 14s** for ambience, against 0.75->0.20 in half
--- a second for low health. A highlight that shows on twenty rows at once belongs to the
--- first group, not the third.
function ns.ApplySparkColor(texture, classFilename, mostrar)
    if not mostrar then
        texture:Hide()
        return
    end

    texture:SetColorTexture(1, 1, 1, 1)
    if texture.SetGradient and CreateColor then
        texture:SetGradient("HORIZONTAL",
            CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, SPARK_ALPHA))
    else
        -- A client without gradients: the trail becomes a flat glow, weaker to compensate.
        texture:SetColorTexture(1, 1, 1, SPARK_ALPHA * 0.5)
    end
    texture:Show()
end

--- The row's background: the same colour, very faded, so the empty part is not a black hole.
--- The row's background: **fixed black**, not tinted by the class.
--- Tinting by the class, as I did, left the empty part
--- of the bar coloured and scrambled the reading of whoever had little.
function ns.RowBackdropColor()
    return 0, 0, 0, ROW_BG_ALPHA
end

--- The row's icon: specialization by default (it says more than the class -- who is the healer, who
--- tanks), with the class as the fallback when the spec did not come.
-- `SetMask` and `SetTexCoord` do not live together ("Cannot set tex coords when texture has mask"); the
-- round shape uses `AddMaskTexture` (below). Two textures per row: one for the
-- specialization icon (a whole id) and another for the class one (an atlas crop).

-- (19/10) The icon's shape is a choice: square by default, round as an option (the user asked for
-- both). Round is drawn the game's way: the portrait mask over the icon, clamped to black outside
-- (`TempPortraitAlphaMask`, CLAMPTOBLACKADDITIVE -- the PvP screen's icons, Blizzard_PVPUI.xml).
-- A MaskTexture added with `AddMaskTexture` keeps `SetTexCoord` working (an icon cut from an
-- atlas sheet takes the mask the same way); it was the old `SetMask` that refused the cut.
-- The icon keeps its size: only the corners go.
local ROUND_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
ns.ROUND_MASK = ROUND_MASK

function ns.IconShape()
    return (ns.db and ns.db.iconShape == "round") and "round" or "square"
end

local ApplyShape

-- (27/10) THE READY FRAME AROUND THE ICON, measured on the art (`ui-cooldownmanager-activeglow`, 64 x 64, alpha across
-- its middle: 0 0 5 15 30 51 76 107 142 183 229 255 255, then clear from px 13). The user's print: drawn 4 px past the
-- icon, the gold line fell 1.3 px INSIDE it and the icon's edge stuck out of the frame. The outer 3 px are cut (alpha up
-- to 15: cut at 8, mid-fade, the frame showed a hard square edge in the mockup), and the line's inner edge then sits at
-- f = (13/64 - 3/64) / (58/64) = 0.172 of the drawn art; on the icon's edge, f x (size + 2 pad) = pad, so
-- pad = f / (1 - 2f) = 0.263 of the icon's size on each side (6 px on the icon of 23).
local KICK_GLOW_CROP = 3 / 64
local KICK_GLOW_INNER = (13 / 64 - KICK_GLOW_CROP) / (1 - 2 * KICK_GLOW_CROP)
local KICK_GLOW_PAD = KICK_GLOW_INNER / (1 - 2 * KICK_GLOW_INNER)
ns.KICK_GLOW_PAD = KICK_GLOW_PAD
-- (27/10) THE ROW ICON'S FRAME: the same art cut down to its line, in the class colour. The user: *"no icone da classe,
-- vamos fazer essa borda igual do interrupt mas sem parecer 'brilhar' com a cor da classe"*. The cut keeps px 11-52
-- (the line is px 11-12; the gold fade outside it is the glow, and goes); desaturated (the line is 255,244,147, which
-- desaturates to 0.93) and tinted with the class colour. The line's inner edge is at f = 2/42 of the drawn art, so
-- pad = f / (1 - 2f) = 0.053 of the icon (1.2 px on the icon of 23), the line just outside the icon.
local CLASS_BORDER_CROP = 11 / 64
local CLASS_BORDER_INNER = (13 / 64 - CLASS_BORDER_CROP) / (1 - 2 * CLASS_BORDER_CROP)
local CLASS_BORDER_PAD = CLASS_BORDER_INNER / (1 - 2 * CLASS_BORDER_INNER)
ns.CLASS_BORDER_PAD = CLASS_BORDER_PAD
---(26/10) The interrupt's icon of a strip: the spell's icon, the game's cooldown clock over it (CooldownFrameTemplate,
---the action bars' own), the seconds in the middle, and the Cooldown Manager's gold frame when it is ready.
local function KickIcon(faixa)
    if faixa.kick then return faixa.kick end
    local b = CreateFrame("Frame", nil, faixa.top)
    b:EnableMouse(false)                               -- the row's click and tooltip go through
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b.cd:SetDrawEdge(false)
    if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
    b.over = CreateFrame("Frame", nil, b)
    b.over:SetAllPoints()
    b.over:SetFrameLevel(b.cd:GetFrameLevel() + 2)
    b.num = b.over:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.num:SetPoint("CENTER", 0, 0)
    b.glow = b.over:CreateTexture(nil, "OVERLAY")
    b.glow:SetAtlas("ui-cooldownmanager-activeglow")
    -- (27/10) the art's faint outer 3 px cut away (KICK_GLOW_CROP).
    -- After SetAtlas the coords are fractions of the art itself (ui-design skill).
    b.glow:SetTexCoord(KICK_GLOW_CROP, 1 - KICK_GLOW_CROP, KICK_GLOW_CROP, 1 - KICK_GLOW_CROP)
    b.glow:Hide()
    faixa.kick = b
    return b
end
ns.KickIcon = KickIcon               -- the harness draws one on a strip of its own

---The seconds left over the icon, while the clock runs (only then: the frame has no OnUpdate when ready).
local function KickTick(self)
    local left = (self.endAt or 0) - GetTime()
    if left <= 0 then
        self.num:SetText("")
        self:SetScript("OnUpdate", nil)
        return
    end
    self.num:SetText(left >= 10 and tostring(math.floor(left + 0.5)) or tostring(math.ceil(left)))
end

---Draws a row's interrupt (Kicks.ForRow's answer) on its strip's icon; hides it when there is none.
function ns.DrawKick(faixa, state)
    local b = faixa.kick
    if not b then return end
    if not state then b:Hide(); b:SetScript("OnUpdate", nil); return end
    b.tex:SetTexture(state.icon or 134400)
    -- (27/10) ALWAYS SQUARE, whatever the specialization icons' shape option says. The user: *"vamos deixar padrão o
    -- icone do interrupt quadrado mesmo, sem opção de redondo pra ele"* -- the shape of the action bars and of the
    -- Cooldown Manager, whose clock and gold frame it uses.
    b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if b.cd.SetSwipeTexture then b.cd:SetSwipeTexture("Interface\\Buttons\\WHITE8X8", 0, 0, 0, 0.75) end
    if b.cd.SetUseCircularEdge then b.cd:SetUseCircularEdge(false) end
    if state.state == "cooldown" then
        b.cd:SetCooldown(state.start, state.duration)
        b.tex:SetDesaturated(true)
        b.glow:Hide()
        b.endAt = state.start + state.duration
        b:SetScript("OnUpdate", KickTick)
        KickTick(b)
    else
        b.cd:Clear()
        b.tex:SetDesaturated(false)
        b.num:SetText("")
        b:SetScript("OnUpdate", nil)
        b.glow:Show()                                  -- ready: the Cooldown Manager's gold frame
    end
    b:Show()
end

function ApplyShape(texture)
    local round = ns.IconShape() == "round"
    local mask = texture.roundMask
    if round and not mask then
        mask = texture:GetParent():CreateMaskTexture()
        mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(texture)
        texture.roundMask = mask
    end
    if mask and texture.roundMasked ~= round then
        if round then texture:AddMaskTexture(mask) else texture:RemoveMaskTexture(mask) end
        texture.roundMasked = round
    end
end

--- @param spec texture for the specialization icon (a whole id)
--- @param class texture with texcoord, for the class atlas crop
function ns.ApplyRowIcon(spec, class, source)
    ApplyShape(spec)
    ApplyShape(class)
    local specIcon = source.specIconID
    if specIcon ~= nil and not issecretvalue(specIcon) and specIcon ~= 0 then
        spec:SetTexture(specIcon)
        spec:SetTexCoord(0.08, 0.92, 0.08, 0.92)   -- removes the icon's black border
        spec:Show()
        class:Hide()
        return
    end

    local name = SafeClass(source.classFilename)
    local coords = name and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[name]
    if coords then
        class:SetTexture(CLASS_ICONS)
        class:SetTexCoord(unpack(coords))
        class:Show()
        spec:Hide()
        return
    end

    spec:Hide()
    class:Hide()
end

--------------------------------------------------------------------------------
-- Geometria
--------------------------------------------------------------------------------
local function RowHeight()
    return ns.RowHeightFor(FontSize())
end

-- THE WIDTH OF EACH COLUMN, BY FORMAT FAMILY.
--
-- The user's request: *"precisa aumentar um pouco a largura das colunas, principalmente nas colunas
-- onde o resultado e maior, Dano e Cura por exemplo"*.
--
-- He pointed at the defect through its consequence: the width was **one for all** (58), so the
-- column that writes "339M" and the one that writes "8" got the same space -- the first cramped, the
-- second half empty. A uniform width only makes sense with uniform content.
--
-- ⚠️ THE NUMBERS ARE RELATIVE TO THE 58 THAT WERE ALREADY ON SCREEN, not a glyph measurement. I tried
-- to derive them from character width first and the arithmetic gave widths SMALLER than the current ones -- because
-- the digit's width depends on the chosen font (the default today is Arial Narrow, and the player
-- can swap it), and that I cannot measure from here. Anchoring on the value that already worked is honest;
-- inventing a measurement would be worse than assuming the reference.
--
--   total      "339M", "1.2B"   -> +18   it is the column he mentioned (Damage, Healing, Taken)
--   perSecond  "299K"           -> +6    one digit less than the total
--   percent    "100%"           -> +6
--   count      "19"             -> −10   two digits do not need 58
-- THE WIDTH BY FORMAT, and the three requests of 08/09 fit in this table and in `DEFAULT_SLACK`:
-- *"a coluna do nome ta meio grande, acho que da pra reduzir um pouco so e aumentar as outras,
-- alem de deixa os nomes das colunas mescladas um pouco mais perto"*.
--
-- **THE TOTAL GROWS** (76 -> 92) because it is where the bar lives. The width here is not about fitting the
-- text -- "1.2B" always fit -- it is about the bar's RESOLUTION: 16px more is the difference between
-- telling 78% from 84% and not telling.
--
-- **THE RATE SHRINKS** (64 -> 56), and that is what brings the labels closer. The header is aligned to
-- the right of its column, so what separates "Dano" from "DPS" is exactly the width of the
-- DPS column: narrowing it pulls the two towards each other. The pair's two numbers come to group in the
-- right half of the bar, which is how the pair should be read -- a duo, not two columns.
--
-- **THE COUNT GROWS** (48 -> 56) because it was the most cramped one and it is where the pair does not exist.
--
-- The arithmetic closes at today's width: 92+56+92+56+56 = 352 against 328, and the extra 24 come out of
-- `DEFAULT_SLACK`. The window stays at 517.
-- ⚑ THE TOTAL LEFT HERE AND BECAME CONFIGURABLE (`ns.db.totalWidth`, default **84**), because what it
-- controls is not the width of just any column: it is **the distance between the two values of a
-- double column**. Request of 09/09/2026, with a print: *"são das distância entre colunas e entre
-- valores nas colunas mescladas"*.
--
-- WHY IT, AND NOT A SPACING OF ITS OWN. The pair is ONE bar, with a number anchored at each
-- end of it (see `MemberAlign`). So the gap between the two is the bar's width minus the ink of the
-- two numbers -- there is no "space between values" to adjust. Shortening the bar is the only
-- way to bring them closer, and the bar is the sum of the pair's two columns.
--
-- Measured on the print of 09/09, which came out 1:1 with the game: a bar from x=217 to x=355 (138 px), "93.2M"
-- ending at 255, "116K" starting at 321 -- **a 65 px gap**, with the total at 92. The ink of the
-- two numbers plus the insets eats a fixed 74 px, so the gap is `total + 56 - groupGap - 74`. At 84
-- with a slack of 8 it gives **58 px**, which is the "60" he asked for, within the error of whoever measures on screen.
--
-- WHAT IT COSTS, said in the same line where it is charged: the 92 existed for the BAR'S RESOLUTION,
-- not for the text (*"92px contra 56px é a diferença entre distinguir 78% de 84% e não distinguir"*).
-- At 84 the damage slice drops from 86 to 79 px -- 1 px comes to be worth 1.3% instead of 1.2%.
--
-- ⚑ AND THE FLOOR OF 56 IS NOT AESTHETIC. `ColumnWidthFor` returns `math.max(resolution, measured text)`, and
-- "999.9M" in Arial Narrow 16 asks for ~50 px with the breathing room; in a wide font, more. Below that the
-- text comes to rule and **the slider stops having an effect on screen** -- the player would drag and nothing
-- would change. The control's minimum exists so that bottom cannot be reached by accident.
local COLUMN_WIDTH_BY_FIELD = {
    total = TOTAL_WIDTH_DEFAULT,   -- only the default; what rules at drawing time is `TotalWidth()`
    perSecond = 56,
    percent = 56,
    count = 56,
}

--- The width of ONE column, by the format of what it writes.
---
--- It follows the font size: whoever enlarges the text enlarges the column along, or the number grows
--- inside a box that did not grow -- which is the same defect, only caused by the settings.
--- The GROUPS the window draws, cached per drawing.
---
--- `ns.db.columns` is still the list the player ticks; what goes on screen is its
--- grouping by metric. Recomputing at every use would be cheap, but the cache keeps the four
--- consumers (offsets, header, cell, drawing) looking at exactly the same list -- and it was
--- precisely two calculations drifting apart that cost the last version.
local grupos = {}

local function RefreshGroups()
    grupos = ns.Data.GroupColumns(ns.db.columns)
    return grupos
end

local function Groups()
    if #grupos == 0 then RefreshGroups() end
    return grupos
end

--- What a group's CELL writes: "65.1M - 48K".
---
--- Each metric formats its own number (`SetCellText` knows about percentage, secret values and the
--- K/M/B ranges), and the result is joined with the same separator as the header -- it is what makes the
--- player read "Dano - DPS" on top and "65.1M - 48K" below as the same duo.
---
--- Does the group contain this column?
---
--- It serves the single bar: it needs to know whether the metric that SORTS the window is one of its own, to
--- draw that one's proportion -- and not the total's, which would give the longest bar to whoever is not
--- at the top of the list.
local function GroupHas(grupo, key)
    for i = 1, #grupo.keys do
        if grupo.keys[i] == key then return true end
    end
    return false
end

--- The index of the GROUP a column belongs to.
---
--- ⚑ IT EXISTS BECAUSE THE HEADER AND MOVE SPEAK DIFFERENT LANGUAGES. `button.columnIndex` is a position
--- in `ns.db.columns`; `Window.MoveColumn` indexes the list of GROUPS. With a total+rate pair on,
--- the two lists have different sizes -- always -- and the click passed the wrong index.
---
--- The same defect had already been fixed in the settings screen (`Picker.IndexOf`) and came back
--- through the header when it stopped being per group. The translation lives here now, in one place.
local function GroupIndexFor(key)
    local lista = ns.Data.GroupColumns(ns.db.columns)
    for i = 1, #lista do
        if GroupHas(lista[i], key) then return i end
    end
    return nil
end

-- THE LONGEST TEXT each format gets to write. It is not a guess: they are the ranges
-- `Data.FormatAmount` produces (one decimal place, cut at K/M/B) and `Data.FormatPercent`.
local COLUMN_SAMPLE = {
    total = "999.9M",
    perSecond = "999.9K",
    percent = "100.0%",
    count = "999",
}

-- THE RULER: a hidden FontString, only for measuring. The result is cached per
-- font+size, so the measuring happens once per change of look -- not per drawing.
local regua, larguraCache, larguraChave = nil, {}, nil

local function MedirTexto(texto)
    if not regua then
        regua = UIParent:CreateFontString(nil, "BACKGROUND", "GameFontHighlightSmall")
        regua:Hide()
    end
    ns.ApplyRoleFont(regua, "body", 0)
    regua:SetText(texto)
    local w = regua:GetStringWidth()
    return (type(w) == "number" and w > 0) and w or nil
end

--- The width of ONE column.
---
--- ⚑ IT STOPPED SCALING WITH THE FONT SIZE, and came to MEASURE the text. The user's complaint,
--- 08/09: *"percebi que trocar tamanho de fonte e a fonte bagunca muito a largura das colunas, as
--- vezes ate desproporcional"*.
---
--- He described the symptom; the cause is two errors in the same old line
--- (`base * RoleSizeSafe("body") / 16`):
---
--- 1. **The width scaled with the SIZE**, but it exists to give the BAR RESOLUTION -- 92px against
---   56px is the difference between telling 78% from 84% and not telling. Bar resolution has
---   nothing to do with the letter's size. Scaling, changing the size from 13 to 20 inflated the whole
---   window by ~54%, and that was the "desproporcional".
--- 2. **The font's FAMILY did not enter the arithmetic.** The factor came from 16 assuming the proportions of
---   Arial Narrow; in a wide font (FRIZQT, Morpheus) the same size asks for much more ink, and the
---   text overflowed with nothing warning. In a narrow one, air was left over.
---
--- Now they are two independent demands, and the width is the bigger of the two:
---
---    resolution  -- `COLUMN_WIDTH_BY_FIELD`, FIXED, because it is about the bar
---    the text    -- MEASURED in the font and size in effect, plus the breathing room
---
--- That also answers what he offered as an alternative (*"podemos por limite no tamanho da
--- fonte... o limite por fonte pode mudar"*): with the column measuring its own text, the limit stops
--- being needed -- it follows any font at any size, instead of assuming one.
local KICK_GAP = 3                -- (27/10) between the end of the interrupts' bar and the icon: the bar never runs under it

---(27/10) The interrupt icon's size: the row's height less 1 above and below -- it reaches past the bar's strip --, up
---to 26 with a large font. The user: *"aumenta um pouco o icone de interrupt"* (it was the strip's height less 2: 19 in a
---row of 25, now 23).
local function KickSize()
    return math.min(RowHeight() - 2, 26)
end
ns.KickSize = KickSize

---The room the interrupts' clock adds to its column: the icon, the gaps at its sides, and 2 so the count keeps the room
---it had before the clock (26 with the icon at 18).
local function KickRoom()
    return KickSize() + TEXT_INSET + KICK_GAP + 2
end
ns.KickRoom = KickRoom

local function ColumnWidthFor(key)
    if ns.Kicks and ns.Kicks.KindOfColumn(key) and ns.Kicks.Enabled() and key ~= "dispels" then
        return ColumnWidthFor("dispels") + KickRoom()
    end
    local def = ns.Data.GetColumn(key)

    -- A COUNT METRIC COMES FIRST, and not by `field`: interrupts and dispels are also
    -- `total`, only of a count -- so classifying by format gave them the width of
    -- "1.2B" to write "8". Whoever knows that is the catalogue, which marks the metric with `counts`.
    local formato = "total"
    if def and def.counts then
        formato = "count"
    elseif def and def.field then
        formato = def.field
    end

    -- ⚑ THE CONFIGURED WIDTH GOES INTO THE CACHE KEY. Without it, dragging the slider changes
    -- nothing on screen until the next font change -- the old value stays cached and the player concludes
    -- the option does not work. It is the same kind of defect as a `SetAtlas` that fails silently.
    local chave = tostring(ns.FontPath()) .. ":" .. tostring(ns.RoleSizeSafe("body"))
        .. ":" .. tostring(TotalWidth())
    if chave ~= larguraChave then
        larguraCache, larguraChave = {}, chave
    end
    if larguraCache[formato] then return larguraCache[formato] end

    local resolucao = COLUMN_WIDTH_BY_FIELD[formato] or COLUMN_WIDTH_FIXED
    if formato == "total" then resolucao = TotalWidth() end

    -- THE TEXT, measured. If the ruler does not answer (a client without `GetStringWidth`, a font that did not
    -- load), the resolution alone decides -- which is exactly the behaviour before this
    -- change. A fallback that makes nothing worse.
    local tinta = MedirTexto(COLUMN_SAMPLE[formato] or COLUMN_SAMPLE.total)
    local pedidoDoTexto = tinta and math.ceil(tinta + TEXT_INSET * 2 + TEXT_ROOM) or 0

    local largura = math.max(resolucao, pedidoDoTexto)

    -- FLOOR: below this the header's label ("Interr", "Dissip") does not fit, and a column whose name
    -- cannot be read serves no purpose.
    if largura < 44 then largura = 44 end

    larguraCache[formato] = largura
    return largura
end

--- A GROUP's width: the SUM of its columns.
---
--- Each column has its own number again (the version that joined the two in a single string was
--- undone on request), so the group takes exactly its columns' space. What it gains is
--- something else: **a single bar**, crossing from the total's column to the rate's.
local function GroupWidth(grupo)
    local largura = 0
    for i = 1, #grupo.keys do
        largura = largura + ColumnWidthFor(grupo.keys[i])
    end
    return largura
end

--- Each column's offset from the RIGHT, and the total width.
---
--- Each column has ITS OWN width now, so the accumulated offset is no longer
--- `index * width`: it is the sum of the widths of the columns to its right.
--- WHERE EACH NUMBER OF A GROUP SITS INSIDE ITS BAR.
---
--- The user's idea, 08/09: *"se cada um ficasse alinhado em cada canto, ou seja, dano a esquerda,
--- dps a direita"*, and right after *"quando a coluna tiver apenas um valor, fica centralizado"*.
---
--- ⚑ WHAT CHANGES IS THE PRINCIPLE THAT BINDS THE TWO NUMBERS. Before they were right-aligned, each
--- in its column's box, and what joined them would be PROXIMITY -- except it did not join them: the gap
--- between them was the REMAINDER of the rate's width, averaged 35.8px and varied 11px per row, while the
--- gap between different families was 33. Two numbers of the same family sat farther apart
--- than two of different families -- a ratio of 0.92, inverted.
---
--- Now they go to the ENDS, and what binds them is the COMMON REGION: two things at the two
--- ends of a container belong to the container. It only works because the bar gained a tinted track
--- in 0.73.0 -- without a visible container, they would be two loose numbers in the dark.
---
--- And the rule extends by itself, which is the test that it is a rule and not a case:
---
---    1 member   -> centre                 (interrupts, deaths, absorbed)
---    2 members  -> left, right            (damage + DPS)
---    3 members  -> left, centre, right    (damage + DPS + damage%, which comes in two presets)
---
--- Without that the window would have two grammars -- one for whoever has a pair and another for whoever does not
--- --, which usually comes out worse than the original problem.
---
--- @return string justification "LEFT", "CENTER" or "RIGHT"
local function MemberAlign(indice, total)
    if total <= 1 then return "CENTER" end
    if indice == 1 then return "LEFT" end
    if indice == total then return "RIGHT" end
    return "CENTER"
end

--- A member's SLICE inside the group's bar: where it starts (from the right) and how much it takes.
---
--- It serves the HEADER, and that is why it exists. The label has to sit on top of the number it names
--- and the button on top of the slice it sorts -- otherwise clicking "DPS" would sort by damage, which is
--- exactly the defect that already came back once through here.
---
--- The slice is proportional to the column's declared width (`COLUMN_WIDTH_BY_FIELD`), and not a blind
--- third: that way the total, which asks for more space, also gains the bigger click target -- and it is the
--- family's primary.
---
--- @return number offset from the strip's right, number width
local function MemberSlice(grupo, indice, larguraFaixa)
    local soma = 0
    for _, key in ipairs(grupo.keys) do soma = soma + ColumnWidthFor(key) end
    if soma <= 0 then return 0, larguraFaixa end

    local depois = 0
    for i = #grupo.keys, indice + 1, -1 do
        depois = depois + ColumnWidthFor(grupo.keys[i])
    end

    local escala = larguraFaixa / soma
    local offset = math.floor(depois * escala + 0.5)
    local largura = math.floor(ColumnWidthFor(grupo.keys[indice]) * escala + 0.5)
    return offset, largura
end

--- Each COLUMN's offset from the right, and the total width.
---
--- It is per column again: the header and the number went back to being one per column. What goes per
--- group is only the bar, and its span comes from `GroupSpans`, which reads these same offsets -- the two
--- calculations cannot diverge because only one exists.
local function ColumnOffsets()
    local columns = ns.db.columns
    local offsets, running = {}, 0
    for c = #columns, 1, -1 do
        offsets[c] = running
        running = running + ColumnWidthFor(columns[c])
    end
    return offsets, running
end

--- EACH GROUP'S SPAN: where the single bar starts and how far it crosses.
---
--- The user's idea: *"a barra que progride conforme quem ta melhor, ela vai desde a coluna de
--- dano ate o DPS, e mesma coisa pra Cura e CPS, como se fosse apenas uma barra"*.
---
--- ⚑ THIS ONLY CLOSES BECAUSE THE ORDER IS LOCKED. A family's columns are contiguous in
--- `ns.db.columns` (`Data.NormalizeColumns` guarantees it), so a group is a CONTINUOUS STRIP -- from the
--- right edge of its last column to the left edge of its first. With the interleaved list
--- the previous version allowed ({damage, healing, DPS}), the damage bar would have to cross
--- under a healing number, and "one single bar" would stop meaning anything.
---
--- @return table spans `{ group, offset (from the right), width }`, in screen order
local function GroupSpans()
    local offsets = ColumnOffsets()
    local columns = ns.db.columns

    local posicaoDe = {}
    for i = 1, #columns do posicaoDe[columns[i]] = i end

    local vaos = {}
    for _, grupo in ipairs(Groups()) do
        local largura, ultima = 0, nil
        for _, key in ipairs(grupo.keys) do
            local at = posicaoDe[key]
            if at then
                largura = largura + ColumnWidthFor(key)
                if ultima == nil or at > ultima then ultima = at end
            end
        end
        if ultima then
            vaos[#vaos + 1] = { grupo = grupo, offset = offsets[ultima], width = largura }
        end
    end
    return vaos
end

--- The window's minimum width.
---
--- It summed the columns' width (7 x 58 = 406), which made the window be born with a 508px
--- minimum width because of columns that are no longer drawn. Now it is what the ROW needs:
--- icon, a readable name and the number's space.
--- The minimum width: below it the window does not fit what it draws.
---
--- ⚠️ IT WENT BACK TO SUMMING THE COLUMNS, and the story of that is the lesson: when the drawing in SECTIONS
--- took the columns off the screen, I took their sum out of here -- and wrote in the comment that "the
--- columns are no longer drawn". Later the drawing went back to having columns and the sum did not come back
--- along. **The premise lapsed and the comment stayed**, stating as fact something that had stopped
--- being true.
---
--- The damage was big and silent: with the default Mythic+ set (7 columns x 58 = 406px)
--- in a 340 window, the name's area gave **−111** and the clamp put it at 40px; the first cell
--- was anchored at x = −70, that is ENTIRELY outside the window, and since nothing clips, it drew over
--- the icon, the name and the scenery. Four of the seven columns fell outside.
---
--- And it was not only a clean install: with the width the user had already dragged (491px, 6
--- columns), switching to the Mythic+ set gave a name area of 44 -- inside the clamp, names
--- cut, with no reset at all.
---
--- THE GUTTER GOES INTO THE ARITHMETIC, and forgetting it reproduces a defect this file already documented: without
--- it the minimum guarantees 96 for the name, but the layout takes the gutter OUT OF THOSE 96 and 86 are left -- the
--- same 86 of `DEFAULT_WIDTH`'s comment.
local function MinWidth()
    local _, columnsWidth = ColumnOffsets()
    return PADDING * 2 + RowHeight() + NAME_GUTTER + NAME_MIN_WIDTH + columnsWidth
end

-- The default width's SLACK over the minimum.
--
-- The default CANNOT BE THE MINIMUM: the minimum guarantees `NAME_MIN_WIDTH` (96) for the name, which is the
-- legibility floor, not a comfortable size. Being born at the floor means being born at the limit.
--
-- 48 comes from measurement: "Frenchmiku-Tichondrius" -- a name with a realm, which is the real long case of the user's
-- group -- measures ~139px in Arial Narrow 16, against the floor's 96. The slack covers the difference.
--
-- And it is ADDED to the minimum, not an absolute number: the minimum depends on how many columns the player
-- ticked, so a fixed default width would stop fitting again as soon as he ticked one more.
-- THE DEFAULT WIDTH'S SLACK, and it goes ENTIRELY to the name.
--
-- ⚑ THAT IS WHY THE NAME COLUMN IS NOT A CONSTANT. It is what is left:
-- `nameArea = width - columns - icon - gutter`, and the default width is `MinWidth + DEFAULT_SLACK`
-- -- where `MinWidth` already includes `NAME_MIN_WIDTH`. Substituting, the name's area at the default width is
-- always `NAME_MIN_WIDTH + DEFAULT_SLACK`, **regardless of the columns' size**. Enlarging the
-- columns alone would not shrink the name by one pixel: the window would grow along.
--
-- So the request *"a coluna do nome ta meio grande"* is met here, and only here. 24 leaves the area
-- at 120px: a 12-character name (the game's limit) takes ~77px at the default size, so there are still
-- 43 left for the realm and the breathing room. 48 was more air than the longest name asks for.
local DEFAULT_SLACK = 24

local function WindowWidth()
    local saved = ns.db.width or 0
    local minimum = MinWidth()
    if saved <= 0 then saved = minimum + DEFAULT_SLACK end
    return saved > minimum and saved or minimum
end

local function ColumnHeaderHeight()
    return COLHEAD_HEIGHT
end

--- The window's height for N rows.
---
--- The window **keeps the size the user gave it**: the bars fill from top
--- to bottom and the rest is background. Shrinking to the content, as I had done, made the
--- handle useless -- with a single player, dragging changed nothing and looked stuck.
local function WindowHeight(rowCount)
    return HEADER_HEIGHT + ColumnHeaderHeight() + rowCount * (RowHeight() + 1) + PADDING
end

-- The height the last drawing applied. It comes BEFORE whoever reads it -- it was the seventh trap of
-- declaration below use in this session, and the one that left a whole fix inert.
local alturaDesenhada

--- The height the window should have NOW. Four paths (releasing the handle, changing columns, changing the
--- font, dragging) called the formula directly and disagreed with the drawing; one place decides, and it
--- asks what was drawn.
local function CurrentHeight()
    return alturaDesenhada or WindowHeight(ns.db.rows)
end

Window.__WindowHeight = WindowHeight

--- How much height a row takes, with the separation.
local function RowStep()
    return RowHeight() + 1
end

--- How many WHOLE rows fit in this height.
---
--- It is the EXACT INVERSE of `WindowHeight`, and it has to stay so: the handle calls this one, the drawing
--- calls that one, and if the two disagree the drag does not converge -- the window grows, the drawing
--- grows more, and the handle asks for even more. That is what happened while one of them measured sections and the
--- other measured columns.
---
--- `floor`, and not `floor(x + 0.5)`: rounding to the nearest accepts a height in which the
--- last row **does not fit**, and the player sees half a row. The request was literal -- "para não cortar
--- a linha de um jogador".
local function RowsThatFit(height)
    local usable = height - HEADER_HEIGHT - ColumnHeaderHeight() - PADDING
    local n = math.floor(usable / RowStep())
    if n < MIN_ROWS then n = MIN_ROWS end
    if n > MAX_ROWS then n = MAX_ROWS end
    return n
end

-- Hooks for the harness: the geometry is the testable part of this screen, and without them the test would have
-- to recompute the formulas from outside -- which would confirm the copy, not the code.
Window.__WindowHeight = WindowHeight
Window.__RowsThatFit = RowsThatFit
Window.__RowStep = RowStep

--------------------------------------------------------------------------------
-- Column header
--------------------------------------------------------------------------------

local function BuildColumnHeader()
    if not headerRow then
        headerRow = CreateFrame("Frame", nil, frame)
        headerRow.labels = {}
        -- No background: with the window transparent, a dark strip here becomes a second
        -- opaque rectangle right below the title and weighs the screen down.
        headerRow.bg = headerRow:CreateTexture(nil, "BACKGROUND")
        headerRow.bg:SetAllPoints()
        headerRow.bg:SetColorTexture(0, 0, 0, 0)
    end

    headerRow:ClearAllPoints()
    -- ⚑ THE SAME MARGIN AS THE ROW, and not `PADDING + 2`.
    --
    -- While the number was right-aligned and the label too, 2px of difference went
    -- unnoticed. With both touching the LEFT (0.76.0), the difference became a visible
    -- misalignment -- and that is what the user reported with a print on 09/09: *"o alinhamento do titulo do
    -- header com o comeco no inicio da barra, nao ta bem alinhado"*.
    --
    -- Two different references for things that need to line up is divergence waiting to
    -- happen. Now the header and the row start from the same `PADDING`.
    headerRow:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, -HEADER_HEIGHT)
    headerRow:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, -HEADER_HEIGHT)
    headerRow:SetHeight(COLHEAD_HEIGHT)

    for _, button in pairs(headerRow.labels) do
        button:Hide()
    end

    local offsets = ColumnOffsets()

    -- WHERE EACH COLUMN LIVES INSIDE ITS GROUP. The header can no longer be positioned
    -- by the columns' running sum: the numbers now go to the bar's ENDS, and the label has
    -- to go along.
    ondeFicaCache = {}
    local ondeFica = ondeFicaCache
    for _, vao in ipairs(GroupSpans()) do
        local larguraFaixa = vao.width - GroupGap()
        for i, key in ipairs(vao.grupo.keys) do
            local off, larg = MemberSlice(vao.grupo, i, larguraFaixa)
            ondeFica[key] = {
                -- ⚑ WITHOUT `GROUP_GAP / 2`. The slack between families comes ENTIRELY off the group's
                -- left (`faixa:SetPoint("RIGHT", ..., -vao.offset)`), and this calculation had stayed
                -- on the old model, which split it between the two sides. They were 5px that shifted
                -- every label to the left of the number it names.
                offset = vao.offset + off,
                largura = larg,
                lado = MemberAlign(i, #vao.grupo.keys),
            }
        end
    end

    for c = 1, #ns.db.columns do
        local button = headerRow.labels[c]
        if not button then
            button = CreateFrame("Button", nil, headerRow)
            button:SetHeight(COLHEAD_HEIGHT)
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetPoint("RIGHT", -4, 0)

            button:SetScript("OnClick", function(self)
                -- `columnIndex` and `sortKey` went back to speaking of the same column: there is one header
                -- per column again. `sortKey` stays because it is what separates "which position on
                -- screen" from "which metric" -- reading `ns.db.columns[index]` in here was what
                -- broke when the index came to be a group's.
                local key = self.sortKey
                if IsShiftKeyDown() then
                    -- The clicked column's GROUP, not its position in the list: total and rate go
                    -- together, so moving is always a family operation.
                    local g = GroupIndexFor(key)
                    if g then Window.MoveColumn(g, -1) end
                elseif IsControlKeyDown() then
                    local g = GroupIndexFor(key)
                    if g then Window.MoveColumn(g, 1) end
                elseif ns.db.sortBy == key then
                    ns.db.sortDesc = not ns.db.sortDesc
                    Window.Refresh(true)
                else
                    ns.db.sortBy = key
                    ns.db.sortDesc = true
                    Window.Refresh(true)
                end
            end)
            button:SetScript("OnEnter", function(self)
                -- (14/10) The workspace standard: the title, one green line per action (verb in
                -- the infinitive). The line promising a highlighted leader went: nothing draws it.
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip_SetTitle(GameTooltip, ns.Data.GetAttributeLabel(self.sortKey))
                GameTooltip_AddInstructionLine(GameTooltip, L["Click: sort by this column"])
                GameTooltip_AddInstructionLine(GameTooltip, L["Click again: reverse the order"])
                GameTooltip_AddInstructionLine(GameTooltip, L["Shift-click: move left"])
                GameTooltip_AddInstructionLine(GameTooltip, L["Ctrl-click: move right"])
                GameTooltip:Show()
            end)
            button:SetScript("OnLeave", GameTooltip_Hide)
            headerRow.labels[c] = button
        end

        local key = ns.db.columns[c]
        -- Position on SCREEN (one per column), which is what the test clicks. It does not serve for moving:
        -- for that there is `GroupIndexFor`.
        button.columnIndex = c
        button.sortKey = key
        local onde = ondeFica[key] or { offset = offsets[c],
            largura = ColumnWidthFor(key), lado = "RIGHT" }
        button:SetWidth(onde.largura)
        button:ClearAllPoints()
        button:SetPoint("RIGHT", headerRow, "RIGHT", -onde.offset, 0)

        -- THE LABEL TOUCHES THE SAME END AS THE NUMBER. Without this the button would be in the right place
        -- and its text would not -- "Dano" would show to the right of the damage slice, stuck to "DPS", and
        -- the two labels would gather in the middle again while the numbers sit at the ends.
        button.text:ClearAllPoints()
        button.text:SetJustifyH(onde.lado)
        if onde.lado == "LEFT" then
            button.text:SetPoint("LEFT", button, "LEFT", TEXT_INSET, 0)
        elseif onde.lado == "RIGHT" then
            button.text:SetPoint("RIGHT", button, "RIGHT", -TEXT_INSET, 0)
        else
            button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
        end
        ns.ApplyRoleFont(button.text, "header", 0)

        local label = ns.Data.GetShortLabel(key)
        if key == ns.db.sortBy then
            -- Only the colour marks the sorted column: the gold already says it all, and an arrow here
            -- repeated the information while taking space.
            button.text:SetText(label)
            button.text:SetTextColor(1, 0.82, 0)
        else
            button.text:SetText(label)
            button.text:SetTextColor(0.78, 0.74, 0.60)
        end
        button:Show()
    end
end

--------------------------------------------------------------------------------
-- Rows: each one is a bar
--------------------------------------------------------------------------------
local function BuildRow(index)
    local row = rows[index]
    if not row then
        row = CreateFrame("Button", nil, frame, "BackdropTemplate")

        -- Without this the click goes through the row and lands on the window's frame: the mouse has to be
        -- enabled explicitly, even on a Button created in code.
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp")

        row:SetScript("OnClick", function(self)
            if not self.source then return end

            -- A new .lua file in the .toc only comes in after going out to the character screen;
            -- with /reload the module stays absent and the click would die silently.
            if not ns.Breakdown then
                ns.Print(L["restart the client: the breakdown module was not loaded yet."])
                return
            end

            -- (!) ANOTHER PLAYER OPENS THE PLAYER'S SCREEN (01/10): the same window as "My run",
            -- with what the game gives of someone else (PlayerWindow.lua). In combat the row's
            -- identity is secret and the spell panel's own message says so, as before.
            local src = self.source
            local mine = src.isLocalPlayer
            mine = mine ~= nil and not issecretvalue(mine) and mine == true
            local guid = src.sourceGUID
            if not mine and guid ~= nil and not issecretvalue(guid) and ns.PlayerWindow and ns.PlayerWindow.Show then
                local okP, shown = pcall(ns.PlayerWindow.Show, src, ns.db.sessionType)
                if okP and shown then
                    if ns.MyRunWindow and ns.MyRunWindow.Hide then ns.MyRunWindow.Hide() end
                    return
                end
            end
            if not mine and ns.PlayerWindow and ns.PlayerWindow.Hide then ns.PlayerWindow.Hide() end

            local ok, err = pcall(ns.Breakdown.Show, self.source, ns.db.sessionType, frame)
            if not ok then
                ns.Print("|cffff5555" .. L["error while drawing:"] .. "|r " .. tostring(err))
            end
        end)

        -- Highlight on mouse-over: shows that the row is clickable.
        -- (08/10) And the tooltip with what the player cast (Breakdown.Tooltip):
        -- the highlight alone said "clickable" and nothing of the player.
        row:SetScript("OnEnter", function(self)
            if self.hover then self.hover:Show() end
            if self.source and ns.Breakdown and ns.Breakdown.Tooltip then
                pcall(ns.Breakdown.Tooltip, self, self.source, ns.db.sessionType)
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.hover then self.hover:Hide() end
            if ns.Breakdown and ns.Breakdown.HideTooltip then ns.Breakdown.HideTooltip(self) end
        end)
        row:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })

        -- CLIPS WHAT GOES PAST THE EDGE. IT IS A NET, NOT A FIX -- and the difference matters: with the
        -- right arithmetic nothing goes past, and with it wrong this turns "a column drawing over the
        -- scenery" into "a column that vanishes silently". The second is harder to diagnose.
        --
        -- It comes in anyway because the drawing depends on arithmetic that already lapsed once, and
        -- because the native meter itself clips its entry (`DamageMeterEntry.xml:3`).
        if row.SetClipsChildren then row:SetClipsChildren(true) end

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(0, 0, 0, 0)

        -- Like the native meter: no fill taking the whole row. The value
        -- shows as a **thin line at the foot**, in the class colour.
        --
        -- That changes more than the looks: with a neutral background, the class colour becomes free
        -- to be used in the led column's text -- which was impossible before, because
        -- coloured text over a bar of the same colour vanishes.
        -- A text layer ABOVE the columns' bars. Without it the text vanishes: a StatusBar is a
        -- child frame, and a child frame draws over the parent's FontStrings -- that was exactly
        -- the bug of 0.11.0, in which the row showed as an empty bar.
        row.text = CreateFrame("Frame", nil, row)
        row.text:SetAllPoints()
        row.text:SetFrameLevel(row:GetFrameLevel() + 2)

        row.hover = row.text:CreateTexture(nil, "ARTWORK")
        row.hover:SetAllPoints()
        row.hover:SetColorTexture(1, 1, 1, 0.10)
        row.hover:Hide()

        -- A square icon taking the whole row. The circular mask I had put on
        -- shrank the icon and left it loose in the middle of the bar.
        row.icon = row.text:CreateTexture(nil, "OVERLAY")
        row.icon:SetPoint("LEFT", 0, 0)

        -- A second texture only for the class icon, which needs texCoord.
        row.iconClass = row.text:CreateTexture(nil, "OVERLAY")
        row.iconClass:SetPoint("LEFT", 0, 0)
        row.iconClass:Hide()

        -- (27/10) the class-coloured line around the icon (CLASS_BORDER_PAD), over both textures
        row.iconBorder = row.text:CreateTexture(nil, "OVERLAY", nil, 1)
        row.iconBorder:SetAtlas("ui-cooldownmanager-activeglow")
        row.iconBorder:SetTexCoord(CLASS_BORDER_CROP, 1 - CLASS_BORDER_CROP, CLASS_BORDER_CROP, 1 - CLASS_BORDER_CROP)
        row.iconBorder:SetDesaturated(true)
        row.iconBorder:Hide()

        row.name = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        -- 2px above the centre: opens breathing room between the text and the coloured strip at the foot.
        row.name:SetPoint("LEFT", row.icon, "RIGHT", 5, TEXT_LIFT)
        row.name:SetJustifyH("LEFT")
        -- A long name cuts instead of wrapping or invading the numbers' column.
        row.name:SetWordWrap(false)

        -- The realm is a SECOND FontString, not part of the first: the smaller size is what
        -- separates it from the name, and a FontString has only one size. It is stuck to the end of the name's
        -- text, not to its box -- that is why the name's width is fitted to the content in the
        -- drawing (see `Window.Draw`), or the realm would show far ahead, at the end of the box.
        row.realm = row.text:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.realm:SetPoint("LEFT", row.name, "RIGHT", 0, TEXT_LIFT)
        row.realm:SetJustifyH("LEFT")
        row.realm:SetWordWrap(false)

        -- THE VALUE GOES INSIDE THE BAR, against the right. The user's request: *"o texto hoje
        -- das colunas pode ficar dentro das barras para maximizar o uso de espaco"* -- and it is what
        -- the native meter does, name on one side and number on the other, both over the bar.
        --
        -- One strip per GROUP (the bar that crosses), each with its columns' numbers.
        -- Total and rate are TWO numbers with the same size: they share the bar, not the hierarchy
        -- -- making the rate smaller and grey would demote it to a footnote, and it is the second half of the
        -- same reading.
        row.groups = {}
        rows[index] = row
    end

    local height = RowHeight()
    row:SetHeight(height)
    row:ClearAllPoints()
    local offsetY = -(HEADER_HEIGHT + ColumnHeaderHeight() + (index - 1) * (height + 1))
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", PADDING, offsetY)
    row:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PADDING, offsetY)

    if row.SetBackdropBorderColor then
        -- No border around the row: what separates one row from the other is the 1px gap.
        row:SetBackdropBorderColor(0, 0, 0, 0)
    end

    local iconSize = height          -- the icon's slot: the whole row
    -- (27/10) the icon itself 1 px in from every side, like the interrupt's (KickSize): its frame then fits in the row
    -- and does not touch the next one
    local drawn = iconSize - 2
    row.icon:SetSize(drawn, drawn)
    row.icon:SetPoint("LEFT", 1, 0)
    row.iconClass:SetSize(drawn, drawn)
    row.iconClass:SetPoint("LEFT", 1, 0)
    local pad = drawn * CLASS_BORDER_PAD
    row.iconBorder:ClearAllPoints()
    row.iconBorder:SetPoint("TOPLEFT", row.icon, "TOPLEFT", -pad, pad)
    row.iconBorder:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", pad, -pad)

    -- A FULL BAR, and it is worth explaining why it came back.
    --
    -- It had already been rejected: *"a cor de fundo de cada classe fica ruim para ver os numeros
    -- da tabela, tem que tirar"* -- and it was right, IN THAT context: a table with six columns
    -- of numbers on top of saturated class colour. Here the row has a name and two numbers, which is
    -- the native meter's design, and the request was precisely to put the number inside the bar.
    --
    -- What makes it readable is measured in the skill: a **darkened** fill (~0.65 of the class
    -- colour), a tinted row background so the empty part does not become a hole, and a shadow on the text.
    -- Without the three, it is the earlier rejection again.
    -- THE CLASS STRIP COMES TO COVER ONLY THE NAME COLUMN, at the user's request.
    --
    -- It is the answer to a question that was open: the class colour showed up in THREE places
    -- on the same row -- the icon, each column's bar, and this strip crossing the whole row. Three
    -- times the same information, and the strip was the one that competed the most, because it ran under the
    -- numbers of every column.
    --
    -- Now the identity lives where the person is identified: under the icon and the name. From the name
    -- column to the right it is only metrics.
    --
    -- It IS STILL a progress bar of the sorted metric, not a flat rectangle:
    -- it is what gives the list its vertical shape, and now that shape lives in the same block as the name.
    -- THE NAME'S AREA IS COMPUTED ONCE, HERE, and not down below: the class strip needs it
    -- to know where to stop, and reading `row.nameArea` before it was written returned the value of the
    -- PREVIOUS call (nil on the first). A number computed at two moments is the same
    -- divergence that already cost a version in this file.
    local _, columnsWidth = ColumnOffsets()
    row.nameArea = WindowWidth() - PADDING * 2 - columnsWidth - iconSize - NAME_GUTTER
    if row.nameArea < 40 then row.nameArea = 40 end

    ns.ApplyRoleFont(row.name, "body", 0)
    -- The realm always one point below the name (the user's decision, 05/09/2026): with the row
    -- at 12, the realm stays at 11. It is a delta, not a fixed value -- if the row's size changes again,
    -- the one-point difference follows by itself.
    ns.ApplyRoleFont(row.realm, "body", REALM_FONT_DELTA)

    -- EACH COLUMN IS A BAR WITH THE NUMBER INSIDE.
    --
    -- It is the design the user chose, and what it solves: **three rankings on the same
    -- row**. Each column is scaled by its OWN metric's ruler, so that column's leader
    -- is its only full bar. No comparison in Lua -- which matters, because in combat
    -- the values are secret and comparing raises an error. The geometry answers what Lua cannot.
    --
    -- The bar is a child frame of the cell and the number sits ABOVE it, on the text layer: a child
    -- frame draws over the parent's FontString, and that is how 0.11.0 came out with empty
    -- bars.
    -- ONE BAR PER GROUP, CROSSING ITS COLUMNS.
    --
    -- The user's idea: *"a barra que progride conforme quem ta melhor, ela vai desde a coluna de
    -- dano ate o DPS, e mesma coisa pra Cura e CPS, como se fosse apenas uma barra"*.
    --
    -- The structure that asks for has three levels, and not two: the STRIP (the group's frame, which is the
    -- whole span), the BAR inside it (`SetAllPoints`, so it crosses the span) and one NUMBER per
    -- column on top. Before there were two levels because cell and column were the same thing.
    --
    -- ⚑ THE TEXT IS A CHILD OF THE TOP LAYER, NEVER OF THE STRIP. A StatusBar is a child frame and draws
    -- above any FontString of its own parent -- it is the 0.11.0 bug (rows as empty bars)
    -- recorded right above. `faixa.top` exists only to beat the bar in frame level.
    local vaos = GroupSpans()

    for _, faixa in pairs(row.groups) do
        faixa:Hide()
    end

    for gi = 1, #vaos do
        local vao = vaos[gi]
        local faixa = row.groups[gi]
        if not faixa then
            faixa = CreateFrame("Frame", nil, row.text)

            -- THE TRACK: the rest of the path, in the class's OWN colour, very faded.
            --
            -- The user's request, in two steps: first *"tira o fundo preto com algum
            -- percentual de opacidade"*, then *"o fundo preto e feio"* and *"eu quero ... Pista
            -- tingida. Sem fundo preto"*. He did not reject the idea of a track -- he rejected the BLACK.
            --
            -- Tinting with the class colour solves both: the empty part stops being a
            -- hole and becomes "the rest of the path", in the same colour family as the bar, very faded,
            -- instead of stacking a black rectangle.
            faixa.track = faixa:CreateTexture(nil, "BACKGROUND")
            faixa.track:SetAllPoints()

            faixa.bar = CreateFrame("StatusBar", nil, faixa)
            faixa.bar:SetAllPoints()
            faixa.bar:SetStatusBarTexture(ns.BarTexture())
            faixa.bar:SetMinMaxValues(0, 1)
            faixa.bar:SetValue(0)

            -- THE SPARK, on the bar's highest layer: a trail that lights up to the tip.
            --
            -- No atlas on purpose. The alpha gradient on a white texture in `ADD` gives the glow
            -- without depending on art that may not exist in this client -- and an atlas that does not exist
            -- fails SILENTLY, which already cost a blue header in this project.
            faixa.spark = faixa:CreateTexture(nil, "OVERLAY")
            faixa.spark:SetTexture("Interface\\Buttons\\WHITE8X8")
            faixa.spark:SetBlendMode("ADD")

            faixa.top = CreateFrame("Frame", nil, faixa)
            faixa.top:SetAllPoints()
            faixa.top:SetFrameLevel(faixa.bar:GetFrameLevel() + 2)

            -- ⚑ THE NUMBERS ARE INDEXED BY POSITION INSIDE THE GROUP, not by the column's position
            -- in the list. The slot (group 1, number 2) belongs to this strip forever; a global
            -- index would change strips when the player unticked a column, and a widget that changes
            -- parent midway is how one gets defects that only show up when touching the
            -- columns -- the most expensive to reproduce.
            faixa.texts = {}
            row.groups[gi] = faixa
        end

        faixa:SetSize(vao.width - GroupGap(), height - CELL_INSET * 2)
        faixa:ClearAllPoints()
        faixa:SetPoint("RIGHT", row.text, "RIGHT", -vao.offset, 0)
        faixa.bar:SetStatusBarTexture(ns.BarTexture())

        -- THE SPARK IS RE-ANCHORED AT EVERY REBUILD, and not only at birth.
        --
        -- It is pinned to the FILL TEXTURE, and that is what makes it follow the tip by itself:
        -- whoever resizes the texture is the engine, so the spark moves without Lua reading any value.
        -- It is the only highlight that survives a secret value, and the 12.1.0 source proves it in six
        -- places (the encounter timeline, the cooldown manager, the honor bar, widget
        -- bars) -- in one of them moved by a secret value.
        --
        -- Re-anchoring here is cheap (once per row per rebuild) and spares us from depending on
        -- the texture surviving `SetStatusBarTexture` right above.
        -- ⚑ BOTH ENDS PINNED TO THE FILL, and not only the right one with a fixed width.
        --
        -- A defect reported on 08/09, with a print: *"o brilho quando a barra ta quase num tamanho
        -- minimo, ta ficando parecendo que vai andar pra tras"*. And it was exactly that. With a
        -- fixed width of 10px and a bar of ~2px (2.9M against the leader's 224M), the trail came out
        -- through the LEFT of the bar -- and since it is light on the right and fades on the left, it read as
        -- an arrow pointing backwards.
        --
        -- It cannot be fixed by measuring: `GetWidth()` on the fill texture is SECRET,
        -- because it is anchored by an opaque value (`SecretWhenAnchoringSecret`). "Hide when the
        -- trail is bigger than the bar" is a comparison Lua cannot make.
        --
        -- Pinning BOTH ends, the glow's width comes to BE the fill's -- by
        -- construction, at any size, without Lua knowing which it is. A small bar, a small glow;
        -- and there is never anything to the left of the start.
        faixa.spark:ClearAllPoints()
        local preenchimento = faixa.bar:GetStatusBarTexture()
        faixa.spark:SetPoint("LEFT", preenchimento, "LEFT", 0, 0)
        faixa.spark:SetPoint("RIGHT", preenchimento, "RIGHT", 0, 0)
        faixa.spark:SetHeight(height - CELL_INSET * 2)

        -- EVERY NUMBER HIDES FIRST, and only this drawing's come back.
        --
        -- `faixa.texts` survives between drawings (it is the slots' cache). Without hiding everything, a
        -- slot the current drawing does not touch stays on screen with the previous drawing's text -- and the
        -- test, which reads the widget, would count a number nobody wrote.
        for _, fs in ipairs(faixa.texts) do fs:Hide() end

        -- EACH NUMBER AT ONE END OF THE BAR (see `MemberAlign`). Each one's box is the slice
        -- proportional to its column's declared width -- so `COLUMN_WIDTH_BY_FIELD`
        -- still governs how much space each metric asks for, even though the POSITION now comes
        -- from the end and not from the running sum.
        local quantos = #vao.grupo.keys
        local larguraFaixa = vao.width - GroupGap()

        for i = 1, quantos do
            local fs = faixa.texts[i]
            if not fs then
                fs = faixa.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetWordWrap(false)
                faixa.texts[i] = fs
            end

            -- CORPO UNICO NA LINHA INTEIRA, sem excecao. Ver `PAIR_DELTA`.
            ns.ApplyRoleFont(fs, "body", PAIR_DELTA)

            local lado = MemberAlign(i, quantos)
            fs:SetJustifyH(lado)
            fs:ClearAllPoints()

            -- THE BOX NEVER GOES PAST HALF (or a third) of the strip: with two texts anchored at
            -- opposite ends, boxes that are too generous overlap in the middle -- and overlapping
            -- text raises no error, it only becomes unreadable.
            local fatia = math.floor((larguraFaixa - 6) / quantos)
            fs:SetWidth(fatia)

            if lado == "LEFT" then
                fs:SetPoint("LEFT", faixa, "LEFT", TEXT_INSET, 0)
            elseif lado == "RIGHT" then
                fs:SetPoint("RIGHT", faixa, "RIGHT", -TEXT_INSET, 0)
            else
                fs:SetPoint("CENTER", faixa, "CENTER", 0, 0)
            end
            fs:Show()
        end

        -- OS PONTINHOS DO TRIO, entre numeros vizinhos. Ver `DOT_TEXT`.
        faixa.dots = faixa.dots or {}
        for _, d in ipairs(faixa.dots) do d:Hide() end

        if quantos >= 3 then
            for i = 1, quantos - 1 do
                local d = faixa.dots[i]
                if not d then
                    d = faixa.top:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    d:SetJustifyH("CENTER")
                    faixa.dots[i] = d
                end
                ns.ApplyRoleFont(d, "body", DOT_DELTA)
                d:SetText(DOT_TEXT)
                d:SetTextColor(unpack(ns.Skin.dim))

                -- AT THE BORDER BETWEEN THE TWO SLICES, which is where the separation is needed.
                local off = select(1, MemberSlice(vao.grupo, i, larguraFaixa))
                d:ClearAllPoints()
                d:SetPoint("CENTER", faixa, "RIGHT", -off, 0)
                d:Show()
            end
        end

        for i = #vao.grupo.keys + 1, #faixa.texts do faixa.texts[i]:SetText("") end

        -- (26/10) THE INTERRUPTS' CLOCK (Kicks.lua): on the interrupts' strip, the icon at the left end and the
        -- count beside it; on any other strip, or with the option off, no icon
        faixa.kickKind = nil
        if ns.Kicks and ns.Kicks.Enabled() and quantos == 1 then
            faixa.kickKind = ns.Kicks.KindOfColumn(vao.grupo.keys[1])
        end
        -- the bar and its track take the whole strip, except on the interrupts' one (below). Every drawing says it: a
        -- strip is reused when the player changes the columns, and it would keep the cut of the column it had
        faixa.bar:ClearAllPoints()
        faixa.bar:SetAllPoints()
        faixa.track:ClearAllPoints()
        faixa.track:SetAllPoints()
        if faixa.kickKind then
            local size = KickSize()
            local b = KickIcon(faixa)
            b:SetSize(size, size)
            -- the gold line's inner edge exactly on the icon's edge (KICK_GLOW_PAD): no corner of the icon outside it
            local pad = size * KICK_GLOW_PAD
            b.glow:ClearAllPoints()
            b.glow:SetPoint("TOPLEFT", b, "TOPLEFT", -pad, pad)
            b.glow:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", pad, -pad)
            b:ClearAllPoints()
            -- (27/10) THE ICON FIRST, THEN THE COUNT AND ITS BAR (the user: "deixa icone do interrupt na frente do
            -- valor e o valor com a barra depois, só inverter"): it used to sit at the right end
            b:SetPoint("LEFT", faixa, "LEFT", TEXT_INSET, 0)
            -- (27/10) THE BAR STOPS BEFORE THE ICON. The user's print ("a barra do interrupt está em cima do ícone"):
            -- the bar crossed the whole strip, and with 18 or 19 interrupts it ran under the icon, which sank into it
            -- (measured on the print: the icon was drawn on top, the bar's end behind it). The icon gets its own room
            -- at the left end; the bar, its track and the count take the rest, after it.
            local cut = size + TEXT_INSET + KICK_GAP
            faixa.bar:ClearAllPoints()
            faixa.bar:SetPoint("TOPLEFT", faixa, "TOPLEFT", cut, 0)
            faixa.bar:SetPoint("BOTTOMRIGHT", faixa, "BOTTOMRIGHT", 0, 0)
            faixa.track:ClearAllPoints()
            faixa.track:SetPoint("TOPLEFT", faixa, "TOPLEFT", cut, 0)
            faixa.track:SetPoint("BOTTOMRIGHT", faixa, "BOTTOMRIGHT", 0, 0)
            ns.ApplyRoleFont(b.num, "body", PAIR_DELTA)
            -- the count stays centred (the user: *"quando a coluna tiver apenas um valor, fica centralizado"*), in the
            -- part of the strip right of the icon: over the bar, centred on it
            local fs = faixa.texts[1]
            fs:ClearAllPoints()
            fs:SetJustifyH("CENTER")
            fs:SetWidth(math.max(10, larguraFaixa - cut))
            fs:SetPoint("LEFT", faixa, "LEFT", cut, 0)
        elseif faixa.kick then
            faixa.kick:Hide()
            faixa.kick:SetScript("OnUpdate", nil)
        end

        faixa:Show()
    end

    -- THE NAME'S AREA is what is left after the columns -- and now the columns EXIST again,
    -- so taking their width off went back to being the right arithmetic. (In 0.67.x it took off 406px
    -- of columns that were no longer being drawn, and the name was left with 57px.)
    row.name:SetWidth(row.nameArea)
    row.realm:SetWidth(0)
    return row
end

--------------------------------------------------------------------------------
-- Montagem
--------------------------------------------------------------------------------
function Window.Create()
    -- `ns.Skin` is born with the default (the files load before `ns.db` exists). Here the
    -- settings have already been read, so the values derived from the size have to be redone --
    -- or the scoreboard would compute its delta against the wrong size for the whole session.
    ns.RefreshSkin()

    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "Frame", UIParent, "BackdropTemplate")
    frame:SetSize(WindowWidth(), WindowHeight(1))
    frame:SetScale(ns.db.scale)
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0.03, 0.03, 0.04, WINDOW_ALPHA)
    frame:SetBackdropBorderColor(0, 0, 0, 0)      -- no black rectangle around it


    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(HEADER_HEIGHT)

    -- The native meter has a beige-olive strip with
    -- dark text. It tries the game's atlas; if it does not exist in this client, it draws the
    -- same tone by hand so the result is the same either way.
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()

    -- The art is the native meter's atlas, cropped by `ns.ApplyHeaderArt`.
    ns.ApplyHeaderArt(header.bg)

    header.segment = CreateFrame("Button", nil, header)
    header.segment:SetSize(SEGMENT_MIN_WIDTH, HEADER_HEIGHT - 6)
    header.segment:SetPoint("LEFT", 7, 1)
    header.segment.text = header.segment:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.segment.text:SetPoint("LEFT")
    header.segment.text:SetTextColor(1, 0.82, 0)      -- Blizzard's standard gold
    header.segment:SetScript("OnClick", function()
        ns.db.sessionType = ns.db.sessionType == 0 and 1 or 0
        Window.Refresh(true)
    end)
    header.segment:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Click to switch between the current fight and the overall."], 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    header.segment:SetScript("OnLeave", GameTooltip_Hide)

    header.clock = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    header.clock:SetPoint("LEFT", header.segment, "RIGHT", 6, 0)
    header.clock:SetTextColor(0.85, 0.72, 0.36)

    frame.header = header

    -- A single treatment for every icon: same size, same tone, same reaction to the
    -- mouse. The family comes from the game itself -- `questlog-icon-setting` is the quest
    -- tracker's gear, from the same UI the title strip's art comes from.
    local ICON_TINT = { 0.78, 0.73, 0.58 }
    local ICON_HOVER = { 1, 0.95, 0.80 }

    local function HeaderButton(spec, tooltip, onClick)
        local b = CreateFrame("Button", nil, header)
        b:SetSize(14, 14)

        -- An empty texture first: `SetAtlas` needs an existing texture to act on.
        b:SetNormalTexture(spec.texture or "Interface\\Buttons\\WHITE8X8")
        local tex = b:GetNormalTexture()
        if tex and spec.atlas and tex.SetAtlas then
            tex:SetAtlas(spec.atlas, false)
        end
        if tex then
            -- Desaturate first: each atlas brings its own colour (the X is red, the gear
            -- leans gold) and `SetVertexColor` **multiplies** on top of it -- without removing the source
            -- colour, the buttons never end up the same tone.
            if tex.SetDesaturated then tex:SetDesaturated(true) end
            tex:SetVertexColor(ICON_TINT[1], ICON_TINT[2], ICON_TINT[3])
        end

        b.iconAtlas = spec.atlas   -- for the harness: which art the button asked for
        b.SetTint = function(_, color)
            local t = b:GetNormalTexture()
            if t then t:SetVertexColor(color[1], color[2], color[3]) end
        end

        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            self:SetTint(ICON_HOVER)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            -- `tooltipText` overrides the fixed text when the button has a state. It is the padlock's second
            -- channel: even if the icon is not read, the tooltip says it in words.
            GameTooltip:SetText(self.tooltipText or tooltip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self:SetTint(self.activeTint or ICON_TINT)
            GameTooltip_Hide()
        end)

        b.baseTint = ICON_TINT
        return b
    end

    -- No close button: nobody closes the meter in the middle of play, and an X next to the
    -- clear-data icon invites the wrong click -- one hides the window, the other erases
    -- what was recorded. To hide: `/rm` or a click on the minimap button.

    frame.gearButton = HeaderButton(
        { atlas = "questlog-icon-setting", texture = "Interface\\Buttons\\UI-OptionsButton" },
        L["Configure"], function() ns.Picker.Toggle(frame) end)
    frame.gearButton:SetPoint("RIGHT", header, "RIGHT", -5, 0)

    frame.resetButton = HeaderButton(
        { atlas = "common-icon-undo", texture = "Interface\\Buttons\\UI-RefreshButton" },
        L["Clear the data"], function() ns.Data.RequestReset() end)
    frame.resetButton:SetPoint("RIGHT", frame.gearButton, "LEFT", -5, 0)

    -- THE SESSION BOARD (30/09): the scoreboard's wide table, with the session the window is
    -- on, without what only a finished key has. Magnifier: "see this larger".
    frame.boardButton = HeaderButton(
        { atlas = "common-icon-zoomin", texture = "Interface\\Buttons\\UI-Panel-ExpandButton-Up" },
        L["Open the scoreboard of this session"], function()
            -- Nothing measured (or cleared): the last key, as its final board (05/10).
            if ns.Scoreboard and ns.Scoreboard.ShowSessionOrLast then
                ns.Scoreboard.ShowSessionOrLast(ns.db.sessionType)
            elseif ns.Scoreboard and ns.Scoreboard.ShowSession then
                ns.Scoreboard.ShowSession(ns.db.sessionType)
            end
        end)
    frame.boardButton:SetPoint("RIGHT", frame.resetButton, "LEFT", -5, 0)

    -- (26/10) THE STATISTICS: the week's and the season's keys, vault and raids (StatsWindow.lua). The user: *"pode ser
    -- um botão na janela principal"*. A new file: absent until the client restarts, and then no button rather than one
    -- that does nothing. THE ART: the achievement's shield (in the game, Statistics is a tab of the Achievements
    -- window), the one of the game's own achievement alert (AlertFrameSystems.xml), with the small shield file as the
    -- fallback. The first choice, `house-chest-trophy-icon_32`, is in the atlas table but no screen of the game uses it,
    -- and in game it was a white square (the user's print, 26/10): an atlas is chosen from one the game itself draws.
    local leftmost = frame.boardButton
    if ns.StatsWindow then
        frame.statsButton = HeaderButton({ atlas = "ui-achievement-shield-1",
                                           texture = "Interface\\AchievementFrame\\UI-Achievement-TinyShield" },
            L["Statistics"], function() ns.StatsWindow.Toggle() end)
        frame.statsButton:SetPoint("RIGHT", frame.boardButton, "LEFT", -5, 0)
        leftmost = frame.statsButton
    end

    frame.lockButton = HeaderButton(
        { texture = LOCK_ICON },
        L["Lock position"], function()
            ns.db.locked = not ns.db.locked
            Window.ApplyLock()
        end)
    frame.lockButton:SetPoint("RIGHT", leftmost, "LEFT", -5, 0)

    Window.ApplyPosition()

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not ns.db.locked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y }
    end)
    -- No settings shortcut on click: the right button went through the row and landed here,
    -- opening the options when the user only wanted the breakdown. The header's gear and
    -- the minimap button already give access.

    -- Scrolling by the mouse wheel, with no bar: the bar would take width and would show even
    -- when there is nothing to scroll, which is the case almost always.
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(_, delta)
        local maximum = totalRows - ns.db.rows
        if maximum < 0 then maximum = 0 end

        local wanted = scrollOffset - delta
        if wanted < 0 then wanted = 0 end
        if wanted > maximum then wanted = maximum end

        if wanted ~= scrollOffset then
            scrollOffset = wanted
            Window.Refresh(true)
        end
    end)

    -- Resize handle: free width, height in number of rows.
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        -- A generous maximum: whoever drags decides, the limit is only so it does not become full screen.
        frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(GRIP, GRIP)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetScript("OnMouseDown", function()
        if ns.db.locked then return end
        frame.sizing = true
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        frame.sizing = false
        ns.db.width = frame:GetWidth()
        Window.SetRows(RowsThatFit(frame:GetHeight()))
        frame:SetHeight(CurrentHeight())
        -- (14/10) Resizing moves the corner too: the position is kept as dragging keeps it, or a
        -- /reload put the window back off by the change of size. And the rows are drawn again
        -- for the new width (the name's room is measured when a row is drawn, and out of combat
        -- nothing else draws).
        local point, _, relPoint, x, y = frame:GetPoint()
        if point then ns.db.pos = { point = point, relPoint = relPoint, x = x, y = y } end
        Window.Refresh(true)
    end)

    -- LIVE SNAPPING. Before, the adjustment only happened on RELEASING the mouse, so the row stayed
    -- cut for the whole drag and only got right at the end -- which gives the impression that the window
    -- does not obey. Here the height becomes a number of rows at every frame of the drag, and the window
    -- follows in steps of one row.
    --
    -- `frame.sizing` avoids re-entry: `SetHeight` fires `OnSizeChanged` again.
    frame:SetScript("OnSizeChanged", function(self)
        if not self.sizing or self.snapping then return end
        local wanted = RowsThatFit(self:GetHeight())
        if wanted == ns.db.rows then return end

        self.snapping = true
        Window.SetRows(wanted)
        self.snapping = false
    end)

    frame.grip = grip

    -- A hook for the harness: without it the padlock test would have to rediscover the frame through
    -- `_G`, and would come to test the simulator instead of the addon.
    Window.__frame = frame

    rows = {}
    Window.Rebuild()
    Window.ApplyLock()

    frame:SetScript("OnUpdate", function(_, elapsed)
        if not dirty then return end
        throttle = throttle + elapsed
        if throttle < 0.2 then return end
        throttle, dirty = 0, false
        Window.SafeDraw()
    end)

    return frame
end

--- Redoes header, rows and measures -- after changing columns, font, size or width.
function Window.Rebuild()
    if not frame then return end

    RefreshGroups()
    -- (14/10) The settings window, when open, follows what changed elsewhere: the rows by the
    -- grip, a column moved by Shift/Ctrl-click, `/rm col`, `/rm preset`, a profile.
    if ns.Picker and ns.Picker.Refresh then pcall(ns.Picker.Refresh) end

    frame:SetBackdropColor(0.03, 0.03, 0.04, WINDOW_ALPHA)
    frame:SetBackdropBorderColor(0, 0, 0, 0)

    -- No outline on the header: dark text over a light strip gets dirty with an outline.
    -- Title and clock have a size of their own: in the native one they are smaller than the row's text.
    ns.ApplyRoleFont(frame.header.segment.text, "title", 0)
    ns.ApplyRoleFont(frame.header.clock, "title", CLOCK_DELTA)

    for i = 1, ns.db.rows do
        BuildRow(i)
    end
    for i = ns.db.rows + 1, #rows do
        rows[i]:Hide()
    end

    frame:SetWidth(WindowWidth())
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
    end

    visibleRows = -1
    Window.Refresh(true)
end

function Window.Refresh(immediate)
    if not frame then return end
    if immediate then
        dirty, throttle = false, 0
        Window.SafeDraw()
    else
        dirty = true
    end
end

--- Draws protected. An error inside OnUpdate would leave the window frozen with no clue
--- at all -- this wrapper turns that into a message, a single time per error.
local lastError
function Window.SafeDraw()
    local ok, err = pcall(Window.Draw)
    if not ok and err ~= lastError then
        lastError = err
        ns.Print("|cffff5555" .. L["error while drawing:"] .. "|r " .. tostring(err))
    end
end

function Window.GetLastError()
    return lastError
end

-- How to highlight who leads each column without inventing a colour or ornament:
--
--   1st attempt -- gold colour: it became "rogue yellow", competing with the class colour.
--   2nd attempt -- an arrow beside it: anchored in the gap between columns, it looked like loose dirt.
--   3rd and current -- **brightness**: the leader in pure white, the others slightly dimmed.
--
-- Brightness is neutral (it carries no class meaning), takes no space and the eye finds
-- by itself the strongest number of each column. It is the same hierarchy the game's UI uses to
-- separate main information from secondary.
-- A balance between "everyone readable" and "you can find the leader":
--
--   The 0.66 grey of the previous attempt highlighted the leader at the others' expense, who became
--   hard to read. The brightness difference alone only works if the floor is too low.
--
-- Now the floor rises to 0.86 (truly readable) and the leader gains, besides pure white, a
-- **neutral plate** behind -- white at 8%, no colour, no icon, taking no extra space.
-- The leader is painted with **its own class colour** -- and that does not repeat the gold's mistake:
-- there the colour was arbitrary and seemed to say "rogue"; here it says exactly what the class
-- colour always says, "this player". The vocabulary is used, not contradicted.
--
-- Except raw class colour does not serve for text: death knight red and warlock
-- purple are too dark over a dark background. The colour is **lightened towards white**, which
-- preserves the identity and guarantees the reading.
-- With the thin line at the foot, the row's background became **neutral** -- and then the class colour can
-- go back to the led column's text. It was the goal from the start and did not work
-- while the filled bar took the background with the same colour.
--
-- The usual care still holds: raw colour is too dark for some classes
-- (death knight, warlock). A **luminance floor** fixes only who needs it, and only what is
-- necessary -- lightening all of them equally would bring back the washed tone that was already rejected.
-- The highlight's luminance floor. It dropped from 0.55 to 0.45 together with the switch from "mixing with
-- white" to "multiplying": the request was *"precisa tá mais escuro"*, and multiplying lets
-- the floor go down without losing legibility, because the colour stops being washed out.
local LEADER_MIN_LUMA = 0.45
local LEADER_FALLBACK = { 1, 0.88, 0.62 }
-- The native one's glyphs measure ~227/255; our numbers measured ~210. 0.88 closes the difference.
local NORMAL = { 0.88, 0.88, 0.90 }

local function Luminance(r, g, b)
    return 0.299 * r + 0.587 * g + 0.114 * b
end

local function LeaderColor(classFilename)
    local class = SafeClass(classFilename)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if not color then
        return LEADER_FALLBACK[1], LEADER_FALLBACK[2], LEADER_FALLBACK[3]
    end

    local r, g, b = color.r, color.g, color.b
    local luma = Luminance(r, g, b)
    if luma >= LEADER_MIN_LUMA then
        return r, g, b
    end

    -- MULTIPLIES, does not mix with white.
    --
    -- Mixing with white (`r + (1-r)*k`) lightens but **desaturates**, and desaturated dark red
    -- is literally pink. Measured on the 12.x class colours: the Death
    -- Knight is RGB(196,31,59) with saturation 0.84; the mix took it to RGB(216,105,124) with
    -- saturation 0.51 -- that is what the user saw as "parece até rosa".
    --
    -- Multiplying the three channels by the same factor keeps the ratio between them, and a constant ratio
    -- is constant hue and saturation (in HSV, it is raising V without touching H and S). The same Death Knight
    -- becomes RGB(255,39,76): bright red, saturation 0.84 intact -- and **darker** than before
    -- (luma 0.42 against 0.55), which was the other request.
    --
    -- Only four classes get here (Death Knight, Demon Hunter, Evoker and Shaman); the
    -- other nine already pass the floor and come out untouched.
    local k = LEADER_MIN_LUMA / luma
    r, g, b = r * k, g * k, b * k
    if r > 1 then r = 1 end
    if g > 1 then g = 1 end
    if b > 1 then b = 1 end
    return r, g, b
end

-- Exposed for the harness: it is the only part of the highlight that can be checked outside the game, and it was
-- precisely here that the old formula produced the pink.
ns.LeaderColor = LeaderColor

--- Styles the cell of whoever leads the column. The highlight lives **only in the colour**: the tone of the class
--- itself, lightened enough to read. No plate behind -- it lightened the whole cell and
--- became a strange block in the middle of the row.
---
--- `OUTLINE` was tested and rejected: it thickens the letter's stroke, which is weight in the ink and not
--- hierarchy -- it gets heavy even on a single cell.
---
--- **Font size left the list of signals** (the user's decision, 05/09/2026): the whole row
--- stays at `FONT_SIZE`, with or without highlight. The +1pt that existed here gave the leader presence, but
--- at the cost of the numbers of the same column changing size from row to row -- the vertical
--- ruler danced. If the highlight turns out too weak in-game, the next signal to try is the neutral
--- plate behind the cell, not the size.
--- @param delta number|nil a size adjustment for screens with their own typography (the scoreboard uses -1)
function ns.StyleCell(row, index, isBest, delta)
    local cell = row.cells[index]
    local highlight = isBest and ns.db.highlightBest ~= false

    -- The `delta` exists because this function is shared: it reapplies the font at every
    -- drawing, and without it the scoreboard (size 12) would have its cells pulled back to the
    -- window's size (13) -- name at 12 and numbers at 13 on the same row.
    ns.ApplyRoleFont(cell, "body", delta or 0)
    cell:SetShadowColor(0, 0, 0, 1)

    if highlight then
        cell:SetTextColor(LeaderColor(row.classFilename))
    else
        cell:SetTextColor(NORMAL[1], NORMAL[2], NORMAL[3])
    end
end

--- Writes a cell's value. Out of combat it formats; in combat, it passes the raw value to the
--- FontString (the engine renders secret values Lua cannot read).
--- @param halo table|nil the cell's outline copies, when there are any
function ns.SetCellText(fontString, value, columnKey)
    local function write(text)
        fontString:SetText(text)
    end

    if value == nil then
        write("|cff4a4a4a-|r")
        return
    end

    if ns.Data.IsPercentColumn(columnKey) then
        write(ns.Data.FormatPercent(value) or "|cff4a4a4a-|r")
        return
    end

    local text = ns.Data.FormatAmount(value)
    if not text then
        -- A secret value: tries the formatting strategy that worked in this client.
        local secretText = ns.Data.FormatSecretAmount(value)
        write(secretText ~= nil and secretText or value)
        return
    end

    -- No "/s" suffix: the column's label (DPS, HPS) already says it is per second, and repeating it
    -- on every row only steals space from the column.
    write(text)
end

function Window.Draw()
    if not frame or not frame:IsShown() then return end

    local data, session, total = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
        ns.db.rows, not ns.db.sortDesc, scrollOffset)

    totalRows = total or 0

    -- Se gente saiu do grupo (ou a lista encolheu), a rolagem tem que voltar junto.
    local maximum = totalRows - ns.db.rows
    if maximum < 0 then maximum = 0 end
    if scrollOffset > maximum then
        scrollOffset = maximum
        data = ns.Data.GetRows(ns.db.sessionType, ns.db.sortBy, ns.db.columns,
            ns.db.rows, not ns.db.sortDesc, scrollOffset)
    end

    local scope = ns.db.sessionType == 0 and L["Current fight"] or L["Overall"]
    if totalRows > ns.db.rows then
        -- No scroll bar: the count in the title is what warns that there are more people.
        scope = format("%s  |cff909090%d-%d/%d|r", scope,
            scrollOffset + 1, math.min(scrollOffset + ns.db.rows, totalRows), totalRows)
    end
    frame.header.segment.text:SetText(scope)

    -- The button has a fixed width, but its text GROWS when the scroll indicator comes in
    -- ("Combate atual" becomes "Combate atual  1-5/8"). Since the clock is anchored to the right of the
    -- BUTTON and not of the text, the excess ran under the clock and the two drew
    -- over each other -- the print of 05/09 shows "1-5" and "02:58" stacked, unreadable.
    -- Following the text solves both problems at once: the clock gets out of the way and the
    -- clickable area comes to cover everything that is written.
    local textWidth = frame.header.segment.text:GetStringWidth()
    if textWidth and textWidth > 0 then
        frame.header.segment:SetWidth(math.max(SEGMENT_MIN_WIDTH, textWidth + 6))
    end

    local duration = ns.Data.GetDuration(ns.db.sessionType)
    if duration ~= nil and not issecretvalue(duration) and duration > 0 then
        frame.header.clock:SetText(SecondsToClock(duration))
    elseif InCombatLockdown() then
        frame.header.clock:SetText("|cff909090" .. L["in combat"] .. "|r")
    else
        frame.header.clock:SetText("")
    end

    -- ONE ROW PER PERSON, one bar per column.
    --
    -- The list is ONE, sorted by the column the player chose -- as it always was. What
    -- changed is the cell: each column became a bar scaled by its OWN metric's ruler, with the
    -- number inside. And that answers the question that motivated the design -- *"quem esta melhor em
    -- Dano/DPS, Cura/CPS e Interrupts"* -- without reordering anything: the leader of each column is the only
    -- FULL bar of that column.
    --
    -- ⚑ And it works in combat, which is where almost everything here fails. Finding the biggest would require
    -- comparing, and comparing a secret value raises an error; scaling by the ruler the game hands over
    -- (`session.maxAmount`, one per metric) requires reading nothing. The geometry answers what Lua
    -- cannot compute.
    -- THIS DRAWING'S SPANS. `entry.values` is indexed by the list the player ticked
    -- (`ns.db.columns`), which is what `Data.GetRows` returns; `posicaoDe` translates key -> position,
    -- and it is through it that each number and each bar find their value.
    --
    -- ⚑ REDOES, DOES NOT READ THE CACHE. The previous version of this trusted a contract -- "whoever writes
    -- `ns.db.columns` calls `Rebuild`" -- and it broke at the first caller that only drew: the
    -- screen was left with the previous drawing's five groups over a three-column list. A contract
    -- that depends on every caller remembering is not a guarantee; redoing it here is.
    --
    -- The cost is one pass through the columns per DRAWING (not per row), which is what the cache exists
    -- to avoid -- it still serves the four consumers within the same drawing.
    RefreshGroups()

    -- THE HEADER IS PAINTED IN THE DRAWING, not only in the rebuild.
    --
    -- ⚑ A DEFECT OLDER THAN THE MERGE, which only showed now: it was built once in `Rebuild`, and
    -- the click that changes the sorting calls `Refresh` -- the rows reordered and the gold
    -- stayed on the PREVIOUS column until something rebuilt the window. The gold is the only signal of which
    -- column sorts (there is no arrow, by design decision), so it pointing at the wrong column
    -- is the window lying about what it is showing.
    --
    -- The lesson is the same as the cache's right above: a signal that depends on everyone remembering to repaint
    -- goes wrong at the first one that forgets. Painting where the truth is READ has no way to diverge.
    BuildColumnHeader()

    local vaosDesenho = GroupSpans()

    local posicaoDe = {}
    for i = 1, #ns.db.columns do posicaoDe[ns.db.columns[i]] = i end

    local escalas = ns.Data.GetColumnScales(ns.db.sessionType, ns.db.columns)

    -- WHAT EACH BAR MEASURES, AND AGAINST WHAT. (14/10, revised)
    --
    -- In combat the values are secret: no comparing, no maximum in Lua. Then the bar is the
    -- group's TOTAL over the ruler the game hands out (`session.maxAmount`, one per metric), as
    -- the game's own meter does, and the list is in the API's order — the total's.
    --
    -- Out of combat the numbers can be read (`rows.readMax`, the largest of each column over the
    -- whole list), and two things the total's ruler got wrong are put right:
    --   * sorted by a rate (DPS, HPS), the list is in the RATE's order — the log showed total and
    --     per-second in opposite orders — and a bar by the total made the 1st shorter than the 2nd;
    --     the bar fills with the column that sorts;
    --   * a group with no total (deaths, a share alone) has no ruler from the game: the deaths'
    --     maxAmount is 0. Their numbers are readable even in combat (deaths are counted here).
    local readMax = data and data.readMax or {}
    local encheCom, reguaDe = {}, {}
    local sortAt = posicaoDe[ns.db.sortBy]
    for g = 1, #vaosDesenho do
        local grupo = vaosDesenho[g].grupo
        local at = posicaoDe[grupo.key]
        local inGroup = false
        for _, key in ipairs(grupo.keys or {}) do
            if posicaoDe[key] == sortAt then inGroup = true end
        end
        if inGroup and sortAt and readMax[sortAt] then
            at = sortAt
        end
        local def = at and ns.Data.GetColumn(ns.db.columns[at])
        if at and readMax[at] and (at == sortAt or not (def and def.field == "total")) then
            reguaDe[g] = readMax[at] > 0 and readMax[at] or 1
        end
        encheCom[g] = at
    end

    local shown = 0
    for i = 1, ns.db.rows do
        local row = BuildRow(i)
        local entry = data and data[i]

        if not entry then
            row:Hide()
        else
            local source = entry.source
            shown = i

            row.bg:SetColorTexture(ns.RowBackdropColor())

            ns.ApplyRowIcon(row.icon, row.iconClass, source)
            -- (27/10) the frame in the class colour, on the square icon only (the line is square: on the round one it
            -- would cut across the corners the mask took away)
            if ns.IconShape() == "square" and (row.icon:IsShown() or row.iconClass:IsShown()) then
                row.iconBorder:SetVertexColor(ns.ClassColor(source.classFilename))
                row.iconBorder:Show()
            else
                row.iconBorder:Hide()
            end
            ns.DrawName(row, source.name)
            row.classFilename = source.classFilename
            row.source = source

            for g = 1, #vaosDesenho do
                local grupo = vaosDesenho[g].grupo
                local faixa = row.groups[g]

                -- A BARRA, uma so, atravessando o vao do grupo inteiro.
                local at = encheCom[g]
                local escala = reguaDe[g] or (at and escalas[at])
                if escala == nil then escala = 1 end
                faixa.bar:SetMinMaxValues(0, escala)
                local valor = at and entry.values[at] or 0
                faixa.bar:SetValue(valor)
                ns.ApplyBarColor(faixa.bar, source.classFilename)

                -- THE TRACK ONLY SHOWS WHEN THERE IS A VALUE. The user's request: *"se tiver zerado fica
                -- sem a pista tingida, somente quando tiver algum valor"*. He is right: an empty
                -- track under a dash announces a path nobody started.
                --
                -- ⚑ AND IT CAN BE KNOWN IN COMBAT, which looks impossible at first sight.
                -- When the player is ABSENT from a metric, whoever writes the zero is the
                -- addon itself (`Data.lua`: *"Ausente numa lista que sabemos ler = o jogador nao pontuou
                -- ali. E zero."*) -- a plain Lua number, always readable. Only the PRESENT value comes
                -- secret, and that one by definition is not the "zeroed" case.
                --
                -- The guard is written backwards on purpose: it hides only when it can PROVE
                -- there is no value. With an opaque value the track STAYS -- erring by showing is better than
                -- taking the reference away precisely in combat, which is when it serves.
                local vazio = valor == nil
                    or (not issecretvalue(valor) and valor == 0)

                ns.ApplyTrackColor(faixa.track, source.classFilename, not vazio)
                ns.ApplySparkColor(faixa.spark, source.classFilename, not vazio)

                -- IT IS ONE NUMBER PER COLUMN, each formatted by its metric's rule.
                --
                -- Each text goes alone through `SetCellText`, which knows about percentage, a nil
                -- value and probing a secret value. It was the version that joined the two in a single
                -- string that needed a special path in combat -- separated, each one
                -- survives the fight on its own.
                if faixa.kickKind then
                    local okK, st = pcall(ns.Kicks.ForRow, source, faixa.kickKind)
                    ns.DrawKick(faixa, okK and st or nil)
                end

                for i = 1, #grupo.keys do
                    local key = grupo.keys[i]
                    local pos = posicaoDe[key]
                    local fs = faixa.texts[i]

                    ns.SetCellText(fs, pos and entry.values[pos], key)

                -- THE NUMBER GETS NO CLASS COLOUR, and the reason is the user's: *"a ideia e que o
                -- tamanho da barra ja vai dizer qual ta na frente, e a linha de baixo que e da
                -- classe"*.
                --
                -- He is right on two levels. The first is redundancy: the FULL bar already marks
                -- that column's leader, and the strip at the foot already marks the class -- painting the
                -- number was a third signal saying what two already said.
                --
                -- The second is the rule the workspace's skill records after three failed
                -- attempts: **class colour is reserved vocabulary**. A gold number next to
                -- coloured bars reads as "rogue", not as "this is the best". Here it was worse,
                    -- because the number's colour and the bar's colour on the SAME row competed with each other.
                    --
                    -- WHAT VARIES IS THE BRIGHTNESS, and only that: whoever SORTS stays in `Skin.text`, the
                    -- companion on the same bar in `Skin.dim`. It is the only hierarchy signal
                    -- left after the size left the list, and it touches no metric --
                    -- so the vertical ruler does not dance.
                    --
                    -- ⚑ THE PAIR'S PRIMARY IS THE RATE, and no longer whoever sorts. Request of 10/09/2026:
                    -- *"a coluna de dano e cura e um texto em branco, a coluna de DPS e CPS parece
                    -- meio cinza e nao branco, o que pedi foi para inverter isso"*.
                    --
                    -- CONFIRMED ON BOTH SIDES before touching it. In the code, the old rule was
                    -- "whoever SORTS stays light", and his profile sorts by `damage` -- that is why
                    -- Damage came out light and DPS dimmed; on Healing, the sorted metric is not in the
                    -- group, so it fell on the total. On the print, the ink's peak gave (253,255,255) on the
                    -- total against (205,208,216) on the rate: a ratio of **0.81**, against the 0.79 of
                    -- `dim`/`text`. The screen was doing exactly what the code told it.
                    --
                    -- AND WHY THAT DOES NOT LOSE THE SORTING SIGNAL: it never lived here. What
                    -- says which column sorts is the HEADER, in gold -- and the workspace's skill
                    -- already records that repeating the same signal in two places adds nothing.
                    -- The row's brightness comes to say something else, which is what he reads first:
                    -- in a family, the RATE is the main reading and the total is its context.
                    --
                    -- A one-column family (Interr, Deaths) has no rate: it falls on 1 and stays
                    -- light, as it always was.
                    local primario = 1
                    for k = 1, #grupo.keys do
                        local def = ns.Data.GetColumn(grupo.keys[k])
                        if def and def.field == "perSecond" then
                            primario = k
                            break
                        end
                    end

                    if i == primario then
                        fs:SetTextColor(unpack(ns.Skin.text))
                    else
                        fs:SetTextColor(unpack(ns.Skin.dim))
                    end
                end
            end

            row:Show()
        end
    end

    for i = ns.db.rows + 1, #rows do rows[i]:Hide() end

    -- The height is that of ONE list with a column header, which is what is drawn.
    local altura = WindowHeight(ns.db.rows)
    if altura ~= alturaDesenhada then
        alturaDesenhada = altura
        frame:SetHeight(altura)
    end

    -- A fixed height, set by the handle: the empty rows show the background.
    if ns.Breakdown and ns.Breakdown.Refresh then
        ns.Breakdown.Refresh()
    end
    if ns.PlayerWindow and ns.PlayerWindow.Refresh then pcall(ns.PlayerWindow.Refresh) end

end

--- Is the COLUMN header on screen? (14/10) Today it is `true`: it came back as the
--- families' header, drawn at every drawing (`BuildColumnHeader`).
function Window.DebugColumnHeaderShown()
    return headerRow ~= nil and headerRow:IsShown() and true or false
end

--- The horizontal geometry of what was drawn: the window's width, the name's area, and the
--- LEFT edge of each cell measured from the row's left edge.
---
--- The left edge is the number that matters: negative means a cell drawing OUTSIDE the window,
--- which was the defect of 08/09 -- four of the seven columns of the default set fell outside and
--- painted over the name and the scenery, because `MinWidth` had stopped counting the columns.
function Window.DebugGeometry()
    local largura = WindowWidth()
    local offsets, columnsWidth = ColumnOffsets()
    local row = rows and rows[1]

    -- THE LEFT EDGE OF EACH BAR, which is what can fall outside the window.
    --
    -- The numbers come from `GroupSpans`, the SAME function that anchors the strip in the drawing -- the previous
    -- version repeated the arithmetic here, and `MinWidth`'s comment tells what it cost to let
    -- two calculations of the same number diverge.
    local bordas = {}
    for c, vao in ipairs(GroupSpans()) do
        local util = largura - PADDING * 2
        bordas[c] = util - vao.offset - CELL_GAP / 2 - (vao.width - CELL_GAP)
    end

    return {
        width = largura,
        minWidth = MinWidth(),
        columnsWidth = columnsWidth,
        nameArea = row and row.nameArea or nil,
        nameFloor = NAME_MIN_WIDTH,
        cellLeft = bordas,
    }
end

--- The width the window reserves for a set of columns, grouped.
---
--- It serves the test that the text FITS: without this it would have to reimplement `GroupWidth`, and a
--- test that redoes the code's arithmetic only checks that it knows how to add.
function Window.DebugGroupWidths(columns)
    local out = {}
    for _, grupo in ipairs(ns.Data.GroupColumns(columns)) do
        out[#out + 1] = { keys = grupo.keys, width = GroupWidth(grupo) }
    end
    return out
end

--- What the HEADER writes, in screen order: label, width and whether it is gold.
---
--- It exists because of the merge. "Dano - DPS" is a label built at drawing time from
--- two columns, and the only way to check that it came out together -- and that the width followed -- is
--- to ask the widget. Reading `GroupLabel` in the test would only prove that the function concatenates.
function Window.DebugHeaders()
    local out = {}
    if not (headerRow and headerRow.labels) then return out end

    for c = 1, #ns.db.columns do
        local button = headerRow.labels[c]
        if button and button:IsShown() then
            local r, g, b = button.text:GetTextColor()
            -- WHERE THE LABEL'S INK STARTS, measured from the window's right edge. It is the only way
            -- to compare header with number: the two are anchored on different frames, with
            -- margins that already diverged once silently.
            local onde = ondeFicaCache[ns.db.columns[c]]
            out[c] = {
                inkX = onde
                    and (MargemDireita(headerRow) + onde.offset + onde.largura - TEXT_INSET)
                    or nil,
                text = button.text:GetText(),
                width = button:GetWidth(),
                -- The label touches the same end as the number it names.
                align = button.text:GetJustifyH(),
                -- O dourado (1, 0.82, 0) e o unico sinal da coluna ordenada.
                sorted = (r == 1 and g == 0.82 and b == 0),
            }
        end
    end
    return out
end

--- Fires the click on a column's header, as the player would.
---
--- It exists because "does sorting still work?" is not answered by reading the code: the click writes
--- `sortBy`, the drawing reads it, and between the two there is a `Refresh` and an API query. Only a test that
--- clicks and looks at the resulting list answers.
function Window.DebugClickColumn(index)
    local button = headerRow and headerRow.labels and headerRow.labels[index]
    if not button then return false end
    local handler = button:GetScript("OnClick")
    if not handler then return false end
    handler(button)
    return true
end

--- The drawn names, in the order they are on screen.
function Window.DebugRowNames()
    local out = {}
    for i = 1, #rows do
        if rows[i]:IsShown() then out[#out + 1] = rows[i].name:GetText() end
    end
    return out
end

--- A row's CELLS, with the ruler and the value each bar got.
---
--- They are the two numbers that decide the drawing: the ruler says against what that column is measured, and the
--- value says how much of the bar fills. `value == ruler` is the definition of "this person leads
--- this column" -- and that is why the test manages to state who leads without comparing anything,
--- exactly as the window does.
function Window.DebugCells(index)
    local row = rows and rows[index]
    if not row or not row:IsShown() then return {} end

    -- ONE ENTRY PER COLUMN, with the bar it SHARES.
    --
    -- Column and bar stopped being the same thing: two columns of a family share a single
    -- bar. The door returns each column's own text and, along with it, the value/ruler/width of its
    -- group's bar -- and `group` says which columns are in the same one. Without that field, "the two
    -- share the bar" would be indistinguishable from "the two have equal bars by coincidence".
    local out, c = {}, 0
    for gi, vao in ipairs(GroupSpans()) do
        local faixa = row.groups[gi]
        if faixa and faixa:IsShown() then
            local _, escala = faixa.bar:GetMinMaxValues()
            for i = 1, #vao.grupo.keys do
                local fs = faixa.texts[i]
                if fs and fs:IsShown() then
                    c = c + 1
                    local r, g, b = fs:GetTextColor()
                    local _, _, _, ancora = fs:GetPoint(1)
                    out[c] = {
                        key = vao.grupo.keys[i],
                        group = gi,
                        text = fs:GetText(),
                        color = { r, g, b },
                        width = fs:GetWidth(),
                        -- The END the number touches, which is what the corners proposal
                        -- decides. Measuring only the width would not distinguish "both at the ends" from
                        -- "both at the same end with smaller boxes".
                        align = fs:GetJustifyH(),
                        -- Where the ink starts, measured from the window's right edge: the same
                        -- reference `DebugHeaders` uses, so the two are comparable.
                        -- It comes out of the DRAWING's path; the header's comes out of the header's path.
                        -- Two independent calculations -- which is what makes the comparison worth something.
                        inkX = (i == 1)
                            and (MargemDireita(row) + vao.offset + vao.width - GroupGap()
                                - TEXT_INSET)
                            or nil,
                        -- Each number's SIZE: it is what separates whoever SORTS from the companion.
                        -- Without it, "the step exists" is indistinguishable from "the two are equal".
                        size = select(2, fs:GetFont()),
                        anchorX = ancora,
                        -- Da barra do grupo, iguais para as colunas irmas:
                        scale = escala,
                        value = faixa.bar:GetValue(),
                        barWidth = faixa:GetWidth(),
                    }
                end
            end
        end
    end
    return out
end

--- The width reserved for ONE column.
---
--- Without it the test of the crossing bar would have to reimplement `ColumnWidthFor` to say
--- "the bar measures the two added up" -- and a test that redoes the code's arithmetic only checks that it knows how to
--- add.
function Window.DebugColumnWidth(key)
    return ColumnWidthFor(key)
end

--- The row's two gaps: between families and within a family.
---
--- It exists for the harness to lock the RATIO between them, and not the raw numbers -- the numbers change
--- when the user asks for another density (they already changed on 09/09), the ratio is what cannot break.
function Window.DebugGaps()
    return GroupGap(), CELL_GAP
end

--------------------------------------------------------------------------------
-- The two configurable distances
--------------------------------------------------------------------------------
function Window.GetGroupGap()
    return GroupGap()
end

function Window.SetGroupGap(value)
    value = math.floor(tonumber(value) or GROUP_GAP_DEFAULT)
    if value < GROUP_GAP_MIN then value = GROUP_GAP_MIN end
    if value > GROUP_GAP_MAX then value = GROUP_GAP_MAX end
    ns.db.groupGap = value
    Window.Rebuild()
    return value
end

function Window.GetTotalWidth()
    return TotalWidth()
end

function Window.SetTotalWidth(value)
    value = math.floor(tonumber(value) or TOTAL_WIDTH_DEFAULT)
    if value < TOTAL_WIDTH_MIN then value = TOTAL_WIDTH_MIN end
    if value > TOTAL_WIDTH_MAX then value = TOTAL_WIDTH_MAX end
    ns.db.totalWidth = value
    -- ⚑ THE WIDTH CACHE DIES ALONG. `Rebuild` alone would redraw with the old value until the
    -- cache key changed for another reason -- the player would drag and nothing would happen.
    larguraCache, larguraChave = {}, nil
    Window.Rebuild()
    return value
end

--- How much is left BETWEEN the two numbers of a double column, with what is in effect now.
---
--- ⚑ IT IS A TEST HOOK, and the name says so since 10/09/2026. It was born feeding a caption on
--- screen ("N px between the two values"), which the user had taken out -- the effect already shows in the window
--- behind the settings, which redraws at every drag. Without the `Debug` in the name, the next reading
--- would look for the screen that shows this number and would not find it.
---
--- What it measures is not directly adjustable: it comes from the pair's width minus the ink of the two
--- numbers, because each one is anchored at one end of the bar.
function Window.DebugPairValueGap()
    local tintaDosDois = (MedirTexto(COLUMN_SAMPLE.total) or 40)
        + (MedirTexto(COLUMN_SAMPLE.perSecond) or 34)
    local vao = TotalWidth() + COLUMN_WIDTH_BY_FIELD.perSecond
        - GroupGap() - tintaDosDois - TEXT_INSET * 2
    return math.max(0, math.floor(vao + 0.5))
end

--- The drawn SPANS: where each bar starts and how far it crosses.
---
--- It is the door of the user's idea -- *"como se fosse apenas uma barra"*. Without it, one could only
--- state that two columns exist; that the bar goes from one to the other is something only the span says.
function Window.DebugSpans()
    local out = {}
    for gi, vao in ipairs(GroupSpans()) do
        local faixa = rows and rows[1] and rows[1].groups and rows[1].groups[gi]
        -- `anchorX` is read from the WIDGET, not recomputed: it is the difference between stating that the
        -- bar is in place and stating that the arithmetic that puts it there knows how to add.
        -- In two lines on purpose: `x and x:GetPoint(1)` would truncate the multiple returns
        -- to the FIRST -- `and` returns a single value. The anchor always came out nil.
        local ancora
        if faixa then local _, _, _, ax = faixa:GetPoint(1) ; ancora = ax end
        out[gi] = {
            keys = vao.grupo.keys,
            offset = vao.offset,
            width = vao.width,
            barWidth = faixa and faixa:GetWidth() or nil,
            anchorX = ancora,
            textos = faixa and faixa.texts and #faixa.texts or 0,
        }
    end
    return out
end

--- The first drawn row. Without this, "switching variant does not blow up" would be all one could
--- state -- and a variant that changes nothing does not blow up either.
--- The drawn row `index`. `DebugFirstRow()` is case 1, which is the most asked for.
---
--- It came to take an index because the conditional track can only be tested on a row that has NO value
--- in that metric -- and that is never the first, which by construction leads the sorted column.
function Window.DebugRow(index)
    local row = rows and rows[index or 1]
    if not row or not row:IsShown() then return nil end
    local cor = row.bg.GetColorTexture and row.bg:GetColorTexture()
    return {
        nameArea = row.nameArea or 0,
        -- (27/10) the icon's class-coloured frame
        border = row.iconBorder and {
            shown = row.iconBorder:IsShown(), color = row.iconBorder.__vertex, coords = row.iconBorder.__texcoord,
            pad = select(4, row.iconBorder:GetPoint(1)), iconWidth = row.icon:GetWidth(), rowHeight = row:GetHeight(),
            class = row.classFilename,
        },
        bgAlpha = cor and cor[4] or nil,
        rowWidth = row:GetWidth(),
        -- THE CLASS COLOUR STAYS ON THE ROW, and now in one place only: the metrics' bars. Without
        -- this door, "I removed the strip" and "I removed the class colour from the whole row" would be
        -- indistinguishable to the test.
        -- ⚑ IT READS `__gradient`, and not `GetStatusBarColor`. The simulator does not implement the getter --
        -- it falls into the generic `__index` and returns a TABLE, which is never nil and never equal to
        -- another: any comparison would give "has colour" and the test would pass for nothing. `__gradient` is
        -- written by `ns.ApplyBarColor` on the real path.
        barColored = (function()
            local faixa = row.groups and row.groups[1]
            return faixa ~= nil and faixa.bar ~= nil and faixa.bar.__gradient == true
        end)(),
        -- (14/10) Each group's bar: what it holds and against what ruler.
        bars = (function()
            local out = {}
            for g, faixa in ipairs(row.groups or {}) do
                if faixa.bar and faixa.bar.GetMinMaxValues then
                    local _, hi = faixa.bar:GetMinMaxValues()
                    out[g] = { value = faixa.bar:GetValue(), max = hi }
                end
            end
            return out
        end)(),
        -- EACH COLUMN'S WIDTH, in screen order: it is the NUMBER's box, which is what decides
        -- whether it fits or becomes an ellipsis.
        cellWidths = (function()
            local out, c = {}, 0
            for gi, vao in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                for i = 1, #vao.grupo.keys do
                    c = c + 1
                    out[c] = faixa and faixa.texts[i] and faixa.texts[i]:GetWidth() or 0
                end
            end
            return out
        end)(),
        -- ⚑ IT MEASURES THE INK, NOT THE FIELD'S NAME. Until 08/09 this door counted `faixa.track`, a
        -- field that was never created -- the check passed with any track of another name, and an
        -- adversarial review found it empty. Now that the track EXISTS (tinted with the class
        -- colour, on request), what cannot come back is the BLACK.
        cellTracksBlack = (function()
            local n = 0
            for _, faixa in pairs(row.groups) do
                local c = faixa.track and faixa.track.GetColorTexture
                    and faixa.track:GetColorTexture()
                if c and (c[4] or 0) > 0 and c[1] == 0 and c[2] == 0 and c[3] == 0 then
                    n = n + 1
                end
            end
            return n
        end)(),
        -- Each group's track, in screen order: `nil` when invisible.
        cellTracks = (function()
            local out = {}
            for gi, vao in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                local c = faixa and faixa.track and faixa.track:GetColorTexture()
                out[gi] = (c and (c[4] or 0) > 0) and { c[1], c[2], c[3], c[4] } or nil
                out[gi] = out[gi] or false
                if vao then end
            end
            return out
        end)(),
        -- A FAISCA ESTA PRESA NO PREENCHIMENTO? E a afirmacao central da proposta: ancorada na
        -- moldura, ela ficaria parada na borda direita e nao diria nada sobre progresso.
        cellSparkOnFill = (function()
            local out = {}
            for gi in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                if faixa and faixa.spark then
                    -- ⚑ BOTH ANCHORS, and not only the first. It is the second that keeps the glow from
                    -- being bigger than the bar: with a fixed width and a 2px bar, the trail came out
                    -- through the left and read as an arrow pointing backwards (the user's print, 08/09).
                    -- Checking only the right anchor would let that defect come back silently.
                    local fill = faixa.bar:GetStatusBarTexture()
                    local presas, lados = 0, {}
                    for i = 1, faixa.spark:GetNumPoints() do
                        local ponto, rel = faixa.spark:GetPoint(i)
                        if rel == fill then
                            presas = presas + 1
                            lados[ponto] = true
                        end
                    end
                    out[gi] = presas == 2 and lados.LEFT == true and lados.RIGHT == true
                else
                    out[gi] = false
                end
            end
            return out
        end)(),
        -- OS PONTINHOS do trio, por grupo: quantos estao na tela.
        cellDots = (function()
            local out = {}
            for gi in ipairs(GroupSpans()) do
                local faixa, n = row.groups[gi], 0
                for _, d in ipairs(faixa and faixa.dots or {}) do
                    if d:IsShown() then n = n + 1 end
                end
                out[gi] = n
            end
            return out
        end)(),
        -- E a faisca: visivel ou nao, por grupo.
        cellSparks = (function()
            local out = {}
            for gi in ipairs(GroupSpans()) do
                local faixa = row.groups[gi]
                out[gi] = faixa ~= nil and faixa.spark ~= nil and faixa.spark:IsShown() and true
                    or false
            end
            return out
        end)(),
    }
end

function Window.DebugFirstRow()
    return Window.DebugRow(1)
end

---(27/10) A row's interrupts strip: where its bar and track start and where the icon sits, as offsets from the strip's
---left edge; nil when no strip carries the interrupts' clock. `others` counts the strips whose bar does not cross the
---whole strip -- only the interrupts' one may be cut.
function Window.DebugKickStrip(index)
    local row = rows and rows[index or 1]
    if not row or not row:IsShown() then return nil end
    local out, others = nil, 0
    for _, faixa in pairs(row.groups) do
        if faixa:IsShown() then
            if faixa.kickKind and faixa.kick then
                local _, _, _, barX = faixa.bar:GetPoint(1)
                local _, _, _, barEndX = faixa.bar:GetPoint(2)
                local _, _, _, trackX = faixa.track:GetPoint(1)
                local iconPoint, _, _, iconX = faixa.kick:GetPoint(1)
                local _, _, _, textX = faixa.texts[1]:GetPoint(1)
                local _, _, _, glowX = faixa.kick.glow:GetPoint(1)
                out = { barLeft = barX, barRight = barEndX, trackLeft = trackX, iconPoint = iconPoint, iconLeft = iconX,
                        textLeft = textX, iconWidth = faixa.kick:GetWidth(),
                        glowPad = glowX and -glowX, glowCoords = faixa.kick.glow.__texcoord }
            elseif faixa.bar:GetNumPoints() ~= 1 then
                others = others + 1
            end
        end
    end
    if out then out.others = others end
    return out, others
end

--------------------------------------------------------------------------------
-- Visibilidade
--------------------------------------------------------------------------------
function Window.Show(remember)
    if not frame then Window.Create() end
    frame:Show()
    if remember ~= false then ns.db.shown = true end
    Window.Refresh(true)
end

function Window.Hide(remember)
    if not frame then return end
    frame:Hide()
    if remember ~= false then ns.db.shown = false end
end

function Window.Toggle()
    if not frame then Window.Create() end
    if frame:IsShown() then
        Window.Hide()
    else
        Window.Show()
    end
end

---(14/10) Where the saved position puts the window: at creation, and when the profile changes.
function Window.ApplyPosition()
    if not frame then return end
    frame:ClearAllPoints()
    if ns.db.pos then
        frame:SetPoint(ns.db.pos.point, UIParent, ns.db.pos.relPoint, ns.db.pos.x, ns.db.pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end
end

function Window.ApplyVisibility()
    if not frame then return end

    if ns.db.combatOnly and not InCombatLockdown() then
        frame:Hide()
        return
    end

    if ns.db.shown then
        frame:Show()
        Window.Refresh(true)
    else
        frame:Hide()
    end
end

--- The view follows combat: in combat, the current fight (0); out of it, the overall (1).
---
--- It returns `true` when the view CHANGED, and the caller decides whether to redraw. Returning that instead of
--- redrawing in here avoids the doubled drawing on the addon's hottest path: the
--- `PLAYER_REGEN_DISABLED` already calls `Refresh` right after this function.
---
--- ⚑ THE COMBAT STATE COMES BY PARAMETER on both events, and not from `InCombatLockdown()`. It is not
--- distrust of the API -- it is that the right value is already in the caller's hand, and passing it makes the
--- rule testable outside the game: the harness has no way of entering real combat.
--- With no argument (the option turned on in the screen, login), then it does ask the client.
function Window.ApplyAutoSession(inCombat)
    if not ns.db.autoSession then return false end

    if inCombat == nil then
        inCombat = InCombatLockdown() and true or false
    end

    local wanted = inCombat and 0 or 1
    if ns.db.sessionType == wanted then return false end

    ns.db.sessionType = wanted
    return true
end

function Window.OnCombatStart()
    Window.ApplyAutoSession(true)

    if ns.db.combatOnly and ns.db.shown then
        Window.Show(false)
    end
end

function Window.OnCombatEnd()
    -- ⚑ THE REDRAW IS FROM HERE, and not from `Core`. It calls `Refresh` BEFORE this function (the values
    -- stop being secret on leaving combat), so the view switch made now would only show
    -- on the next refresh -- which can take a whole fight, with the window stuck on "Combate
    -- atual" after combat has ended.
    if Window.ApplyAutoSession(false) then
        Window.Refresh(true)
    end

    if ns.db.combatOnly then
        C_Timer.After(ns.db.hideDelay or 5, function()
            if ns.db.combatOnly and not InCombatLockdown() then
                Window.Hide(false)
            end
        end)
    end
end

--- Diagnostics: are the rows receiving clicks? It answers without depending on trial and error.
function Window.RowsAreClickable()
    local row = rows and rows[1]
    if not row then return false end
    return row:IsMouseEnabled() and row:GetScript("OnClick") ~= nil and row.source ~= nil
end

--- Applies the locked state: the padlock icon and the handle's visibility.
---
--- The handle only makes sense unlocked -- leaving it visible while locked invites dragging something that will not
--- move. It goes away along.


function Window.ApplyLock()
    if not frame then return end

    local locked = ns.db.locked and true or false

    if frame.grip then
        frame.grip:SetShown(not locked)
    end

    local button = frame.lockButton
    if not button then return end

    -- Texture first: `SetAtlas` needs an already existing texture to act on, and it is also
    -- the fallback when the atlas does not exist in this client.
    button:SetNormalTexture(LOCK_ICON)
    local texture = button:GetNormalTexture()
    if not texture then return end

    -- Unlocked gets the cross of arrows; locked keeps the padlock. See the comment on
    -- `UNLOCK_ATLAS` at the top: the difference has to be of SHAPE, because colour on a 14px glyph
    -- cannot be read. If the atlas is missing, the old behaviour is left -- never an empty button.
    if not locked and texture.SetAtlas and ns.AtlasExists(UNLOCK_ATLAS) then
        texture:SetAtlas(UNLOCK_ATLAS, false)
    end

    texture:SetDesaturated(true)   -- without the icon's original colour, to join the family

    -- The colour REINFORCES the shape, it does not replace it: locked calls attention, unlocked stays in the tone of the
    -- other icons.
    local tint = locked and { 1, 0.82, 0.30 } or button.baseTint
    button.activeTint = tint
    button:SetTint(tint)

    -- The third channel, and the only one that does not depend on the player interpreting a 14px drawing.
    button.tooltipText = locked and L["Locked — click to unlock and resize"]
        or L["Unlocked — drag to move, corner to resize"]
end

--- Sets how many rows the window shows, adjusting the height.
---
--- A single point used by the resize handle and by the settings panel -- without it the two
--- paths would compute the height in different ways.
--- Changes the text's size, within the limits.
---
--- The row's height and the hierarchy (title, clock, header) follow by themselves, because the
--- three are derived -- that was the reason they became deltas in 0.56.1. `Rebuild` is
--- needed because the row's height changes and the rows already built have to be redone.
--- @return boolean changed
--- Writes one key of a role and redraws.
---
--- A single path for the three keys (size, outline, shadow) and for the three roles: they change
--- the same thing -- how the text is drawn -- and need the same work afterwards. Having one
--- function per combination would be nine, and nine paths is where the screens start to diverge.
local function SetRoleField(role, field, value)
    if not ROLE_DEFAULTS[role] then return false end

    ns.db.text = ns.db.text or {}
    local saved = ns.db.text[role]
    if type(saved) ~= "table" then
        saved = CopyTable(ROLE_DEFAULTS[role])
        ns.db.text[role] = saved
    end

    if saved[field] == value then return false end
    saved[field] = value

    ns.RefreshSkin()
    Window.Rebuild()
    if frame then
        frame:SetHeight(CurrentHeight())
        if frame.SetResizeBounds then
            frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
        end
    end
    return true
end

function Window.SetRoleSize(role, size)
    if type(size) ~= "number" then return false end
    size = math.floor(size + 0.5)
    if size < ns.Skin.fontSizeMin then size = ns.Skin.fontSizeMin end
    if size > ns.Skin.fontSizeMax then size = ns.Skin.fontSizeMax end
    return SetRoleField(role, "size", size)
end

function Window.SetRoleOutline(role, value)
    for _, choice in ipairs(ns.OUTLINE_CHOICES) do
        if choice.value == value then
            return SetRoleField(role, "outline", value)
        end
    end
    return false
end

function Window.SetRoleShadow(role, on)
    return SetRoleField(role, "shadow", on and true or false)
end

function Window.GetRoleSize(role)
    return ns.RoleSize(role)
end

function Window.GetRoleOutline(role)
    return ns.RoleConfig(role).outline
end

function Window.GetRoleShadow(role)
    return ns.RoleConfig(role).shadow
end

--- Applies a look choice and redraws.
---
--- A single path for the three: they change the same thing (how the text is drawn) and need
--- the same work afterwards -- redoing the Skin, rebuilding the rows and recomputing the height,
--- because switching fonts changes the width of what fits.
local function ApplyAppearance()
    ns.RefreshSkin()
    Window.Rebuild()
    if frame then
        frame:SetHeight(CurrentHeight())
        if frame.SetResizeBounds then
            frame:SetResizeBounds(MinWidth(), WindowHeight(MIN_ROWS), 1400, WindowHeight(MAX_ROWS))
        end
    end
end

function Window.SetFont(path)
    if type(path) ~= "string" or path == "" then return end
    if path == ns.db.font then return end
    ns.db.font = path
    ApplyAppearance()
end

function Window.SetRows(count)
    if type(count) ~= "number" then return end
    if count < MIN_ROWS then count = MIN_ROWS end
    if count > MAX_ROWS then count = MAX_ROWS end
    if count == ns.db.rows then return end

    ns.db.rows = count
    Window.Rebuild()
    if frame and not frame.sizing then
        -- During the drag, the height is not nailed down here: the drawing adjusts it in steps of one
        -- row (the live snapping, `OnSizeChanged`), and the final snap is made on release, in
        -- the handle's `OnMouseUp`.
        frame:SetHeight(CurrentHeight())
    end
end

function Window.GetRows()
    return ns.db.rows
end

function Window.ApplyScale()
    if frame then frame:SetScale(ns.db.scale) end
end

--------------------------------------------------------------------------------
-- Colunas
--------------------------------------------------------------------------------
--- Turns an ITEM on or off -- which can stand for two columns.
---
--- The user's request: *"onde escolhe as colunas na configuracao o dano e dps e cura e cps tem que
--- ser um so item"*. The atomicity lives HERE, and not on the screen, because the screen is not the only path:
--- `/rm col 2` reaches the same place. A rule split between two paths is a rule that holds in only one.
function Window.ToggleColumn(key)
    local item = ns.Data.GetItemFor(key)
    local chaves = item and item.keys or { key }

    local presente = {}
    for _, id in ipairs(ns.db.columns) do presente[id] = true end

    local ligado = false
    for _, id in ipairs(chaves) do
        if presente[id] then ligado = true end
    end

    local novo = {}
    if ligado then
        for _, id in ipairs(ns.db.columns) do
            local sai = false
            for _, fora in ipairs(chaves) do
                if id == fora then sai = true end
            end
            if not sai then novo[#novo + 1] = id end
        end

        -- THE WINDOW CANNOT BE LEFT WITHOUT A COLUMN. With a two-column item, "one is left" stopped
        -- being the right arithmetic: turning off the last item takes BOTH at once.
        if #novo == 0 then
            ns.Print(L["at least one column must stay."])
            return
        end
    else
        for _, id in ipairs(ns.db.columns) do novo[#novo + 1] = id end
        for _, id in ipairs(chaves) do novo[#novo + 1] = id end
    end

    ns.db.columns = ns.Data.NormalizeColumns(novo)

    -- A ordenacao pode ter ido embora junto com o item.
    local aindaTem = false
    for _, id in ipairs(ns.db.columns) do
        if id == ns.db.sortBy then aindaTem = true end
    end
    if not aindaTem then ns.db.sortBy = ns.db.columns[1] end

    ns.db.width = nil
    Window.Rebuild()
end

--- Moves a GROUP (Shift/Ctrl-click on the header).
---
--- The index that arrives is the header's, which is the group's -- and the total and the rate move TOGETHER: the
--- player drags "Dano - DPS", not "DPS" away from "Dano".
---
--- The column list is rewritten from the groups' order. That has a wanted
--- side effect: if `ns.db.columns` was interleaved ({damage, healing, DPS, HPS} -- possible by ticking the
--- boxes out of order), it comes back grouped. What the screen shows is what is kept.
function Window.MoveColumn(index, direction)
    -- ⚑ REDOES THE GROUPS BEFORE READING. The cache is the previous drawing's, and `ns.db.columns` may have
    -- changed since then without going through a drawing -- SavedVariables come in that way. Reading the cache,
    -- this function rewrote the CURRENT list from groups of a list that no longer exists, and
    -- the result was the old list back on screen.
    local lista = RefreshGroups()
    local target = index + direction

    -- THE ORIGIN IS VALIDATED TOO. Only the destination was checked, and an `index` above the number of
    -- groups got through: the swap left a HOLE in the middle of the list (the origin slot became nil),
    -- `#list` changed value and the flattening right below indexed nil. A Lua blow-up, with the
    -- window dying in the middle of the drawing.
    if index < 1 or index > #lista then return end
    if target < 1 or target > #lista then return end

    lista[index], lista[target] = lista[target], lista[index]

    local novo = {}
    for g = 1, #lista do
        for k = 1, #lista[g].keys do
            novo[#novo + 1] = lista[g].keys[k]
        end
    end
    -- NORMALIZES BACK. Swapping two groups cannot undo the order WITHIN them, and the
    -- normalization is cheap enough to be the last word on every write path.
    ns.db.columns = ns.Data.NormalizeColumns(novo)

    Window.Rebuild()
end

function Window.ApplyPreset(name)
    local preset = ns.Data.GetPresets()[name]
    if not preset then return false end
    ns.db.columns = ns.Data.NormalizeColumns(CopyTable(preset.columns))
    ns.db.sortBy = ns.db.columns[1]
    ns.db.width = nil
    Window.Rebuild()
    return true
end
