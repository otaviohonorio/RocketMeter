# Rocket Meter

Damage, healing and combat statistics for World of Warcraft: Midnight (12.x).

> 🇧🇷 [Leia em português](README-ptBR.md)

## Why it exists

Details! is the standard of the genre and does everything — but it looks dated and its
configuration is a maze. Rocket Meter bets on the opposite: **good-looking in the first second,
configurable in three clicks**, covering what 95% of people actually look at.

## Why it is possible now

In Midnight, Blizzard removed `COMBAT_LOG_EVENT_UNFILTERED` and introduced *Secret Values*. In
exchange it shipped the official **`C_DamageMeter`** API, which collects and aggregates on the
game side. The hard part (parsing the combat log) stopped existing for everyone, and what
separates one meter from another became exactly **presentation and usability** — the weak spot
of Details!.

## Architecture

| File | Responsibility |
|---|---|
| `Core.lua` | lifecycle, SavedVariables, events, combat queue |
| `Data.lua` | the **only** layer that talks to `C_DamageMeter`; handles secret values |
| `Window.lua` | drawing: window, header, rows, bars |
| `Breakdown.lua` | the per-spell panel for one player |
| `Scoreboard.lua` | end-of-run board for Mythic+ and raid encounters |
| `Options.lua` | Settings API panel |
| `Commands.lua` | `/rm` and subcommands |
| `Picker.lua` | the column panel — the configuration screen that matters |
| `Minimap.lua` | own minimap button, no external library |
| `Profile.lua` | where the configuration lives: account or character |
| `Log.lua` | diagnostic diary in SavedVariables |
| `Locales/` | `enUS.lua` (keys = English) and `ptBR.lua` |

### The rule that drives everything

During combat the session fields — including `name` — are **secret values**: they cannot be
compared, summed or formatted. They can only be handed to widgets, which the engine renders.
Out of combat the same fields become readable again.

In practice:

```lua
bar:SetMinMaxValues(0, session.maxAmount)  -- accepts secret
bar:SetValue(source.totalAmount)           -- accepts secret
local text = ns.Data.FormatAmount(source.totalAmount)
row.right:SetText(text or source.totalAmount)  -- formatted out of combat, raw inside
```

No sorting in Lua: the order comes ready from the API, because comparing would be forbidden.

## The design decision: one window, many columns

Details! answers "I want to see damage and healing at the same time" by making you open a second
window. Then a third one for interrupts. Rocket Meter does the opposite: **a single window**,
where each metric is a **column** you turn on or off.

```
┌ Rocket Meter — Current fight — 02:14 ─────────────────────────────┐
│                 Damage    DPS  Healing    HPS  Interr Avoid  Deaths│
│ ███████ Thalyra   1.2M  9.1k/s      —      —       3   820k      0 │
│ █████   Brumm     980k  7.4k/s    12k   91/s       1   1.4M      1 │
└────────────────────────────────────────────────────────────────────┘
```

Total and per-second are **separate columns** — total damage, damage per second, total healing,
healing per second. If you only want the rate, enable DPS and HPS; if you want the whole run's
contribution, enable the totals; if you want both, enable all four.

Click a column header to sort by it. Ready-made presets for **Mythic+** (damage, DPS, healing,
HPS, interrupts, avoidable damage, deaths) and **Raid** (the same, with absorbs instead of
interrupts) — one click swaps everything.

### Configuring: the column panel

The gear in the title bar opens the **column panel**, attached to the window: all eleven metrics
in one list, with a checkbox to enable, arrows to reorder and the current position (1st, 2nd…)
beside each. Every click is reflected in the window behind it, immediately — no "apply", no
submenu, nothing to hunt for.

At the top, the three presets as buttons. At the bottom, a shortcut to the game options, where
scale, lock, rows, profile and the minimap button live.

The Settings API panel still exists because that is where players expect to find global options
— but you do not have to go through it to do the thing you do every day, which is changing
columns.

### Minimap button

Hand-written (~60 lines) instead of embedding LibDBIcon: it stores the position as an **angle**,
so it stays put at any minimap size, and drags around the edge.

- **Click**: show or hide the meter
- **Shift+click**: last run's scoreboard
- **Right-click**: options

It can be hidden in the options — anyone using the addon compartment does not need both.

### The view follows combat

The left corner of the header says which session is on screen — **Current fight** or **Overall**
— and clicking swaps the two (from chat: `/rm overall`).

By default this is automatic: **in combat the window shows the current fight; as soon as it ends,
it goes back to overall**. That is the reading that serves each moment — during the pull the
question is "how am I doing right now", after it the question is "how has the run gone so far".
The *"Follow combat"* checkbox, in the **Session** section of the configuration, turns this off
for anyone who prefers to pick the view by hand; switching by hand still works with it on, and
the rule applies again at the next combat transition.

### Sorting

Click the header to sort by that column; click again to **reverse the direction** (the ▼/▲ arrow
shows which is active). Reversing walks the API list backwards — reversing requires no
comparison, so it works even with secret values during combat.

**Shift+click** moves the column one slot to the left, **Ctrl+click** to the right. From chat:
`/rm move 3 left`.

### Per-character profile

By default the configuration belongs to the whole account. The *"Configuration for this character
only"* option stores everything in `SavedVariablesPerCharacter` — and when first enabled the
character **inherits** what was in effect, instead of starting from scratch. Turning it off goes
back to the account configuration without losing the character's.

`ns.db` is a proxy pointing at the active storage. That is not decoration: the Settings API keeps
the table reference from registration time, so replacing `ns.db` with another table would leave
the options panel writing to the old one.

Commands: `/rm profile char`, `/rm profile account`, `/rm profile reset`.

### Languages

English and Brazilian Portuguese. The translation keys **are** the English text, so a language
without a file falls back to English instead of showing raw keys. `Locales/ptBR.lua` only loads
when `GetLocale() == "ptBR"`. Metric names the client already translates keep coming from it.

### Look: the native meter, with columns

The visuals copy Midnight's built-in meter: a header using the **`ui-damagemeters-header-bar`**
atlas (the same art Blizzard uses), a dark body with no heavy frame, flat 16px rows colored by
class. No skin to configure.

And the window **shrinks to the number of players that exist**: solo is one row, a party of five
is five. An empty box waiting for people is exactly what made the window look like a stray panel
— Blizzard's meter does not do that, and now Rocket Meter does not either.

### What can be cross-referenced in combat, and what cannot

Each metric is a separate query. Crossing two requires matching the same player between them —
and this is where Midnight draws a hard line:

> `GetCombatSessionSourceFromType(...)`: **Secret values are only allowed during untainted**

In combat the `sourceGUID` is secret, and **an addon may not hand a secret value back to the
API**. Only Blizzard code may. That kills the obvious idea of crossing metrics by GUID during
the fight.

What is left, and what the addon does:

| Situation | How the columns are filled |
|---|---|
| **Out of combat** | GUID is readable: crosses everything, all columns for everyone |
| **In combat, your row** | `isLocalPlayer` stays readable: crosses everything for you |
| **In combat, others** | only the sorted column; the rest show `-` |

This is not an implementation limit: it is what the API allows. During the fight you see the
ranking of the sorted metric for everyone plus your own full detail; leaving combat completes
the whole table.

## Per-spell breakdown

**Click a row** and the player panel opens: what they did, spell by spell, with icon, name,
total, per second, percentage and a proportional bar behind it.

Three sections at once, instead of only the window's metric:

| Section | Aggregates |
|---|---|
| Damage | damage done |
| Healing | healing + absorbs |
| Control | interrupts + dispels |

In Details! this is a tooltip that vanishes when the mouse leaves. Here it is a panel: it stays
open, you can read it at your own pace, and it follows the window while the fight continues.

**In combat it only works for your own row** — other players' GUIDs come in *secret* and the API
refuses to take them back; yours comes from `UnitGUID("player")`, which is readable. Out of
combat, everyone is available.

## End-of-run scoreboard

At the end of a Mythic+ (`CHALLENGE_MODE_COMPLETED`) or a won raid encounter (`ENCOUNTER_END`),
a panel opens by itself with the whole group and **every** metric at once — damage, healing,
interrupts, dispels, damage taken, avoidable damage and deaths. It is the equivalent of
`Details_MythicPlus`'s scoreboard, but native, with no extra addon.

The title carries the dungeon and keystone level (or the boss name), with the time and whether it
beat the timer. In M+ the data comes from the **overall** session (the whole run); in raid, from
the fight that just ended. Reopen it with `/rm score`; turn it off in the options.

### Commands

Commands and their arguments are **always in English**, whatever the client language — only the
help descriptions are translated. That way a command copied from a guide, a video or a friend
works on any installation.

```
/rm                             show or hide the window
/rm col [n]                     list the columns, or toggle one
/rm move <n> left|right         move a column
/rm preset mplus|raid|damage    switch the column preset
/rm score                       last run's scoreboard
/rm overall                     switch current fight / overall
/rm profile char|account|reset  account or character configuration
/rm reset                       clear the sessions
/rm log                         the diagnostic diary
/rm config                      open the options
```

## Roadmap

- [ ] Measure the cost of cross-referencing in a 20-player raid (rows × columns queries per refresh)
- [ ] Segment history (`GetAvailableCombatSessions` / `GetCombatSessionFromID`)
- [ ] M+ specific columns: damage on priority adds, defensive usage, missed dispels
- [ ] Scoreboard: per-player M+ score and loot received (`ENCOUNTER_LOOT_RECEIVED`)
- [ ] Scoreboard: history of the last runs (`GetAvailableCombatSessions`)
- [ ] Chat report (out of combat only — the data is secret during)

## License

MIT — see `LICENSE`.
