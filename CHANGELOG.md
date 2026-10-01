# Rocket Meter 0.90.0

- **"My run": your own screen.** Click your row and, instead of the spell panel, a window in
  the game's own style opens with what you did in the key or raid and what it cost. Five tabs:
  - **Summary**: four headline numbers with your place in the group; a ranked list of what cost
    (a death with what killed you, avoidable damage and the spell that gave most of it,
    interrupts that cut nothing, a cooldown left idle, gaps without casting, potions missed on
    bosses); the game's own cooldown list with "used / fitted"; damage taken by spell with the
    game's avoidable mark; your rhythm; and a timeline with a chart by fight, the band of time
    casting with its gaps, bosses, your deaths and potions, and one line per cooldown with every
    use.
  - **Casts**: every spell you cast, with count, share and casts per minute.
  - **Deaths**: every death of yours: what killed you and from whom, the hardest blow when it is
    another, in how many seconds and how much damage, and the blow by blow with the life left.
  - **Spells**: the spell panel, in the same window, with a scroll bar when it is taller than
    the window.
  - **History**: your last 8 runs; click one to open it.
  Two combos pick the run and the fight (whole run, this fight, each boss, trash). The numbers
  of each fight are kept when it ends, so a boss can be looked at later. What it shows follows
  your role: tank, healer or DPS.
- **The scoreboard opens from the meter.** A magnifier in the meter's title bar opens the
  scoreboard with the session the window is on (current fight or overall), without what only a
  finished key has: keystone, score, loot, level, affixes and timeline.
- **The scoreboard's column header has two lines.** The family on top ("Damage", "Healing")
  and the part of each column under it ("total", "per s"). A family with one column keeps its
  name alone; a family of two has its name centred over both, and the lighter shade of the
  sorted column covers the whole pair.
- **Your own interrupts and crowd control, in the Spells tab of "My run".** *Interrupts
  cast* lists each interrupt spell you cast, with how many of all of them cut nothing (casts
  minus the interrupts the game credited), and *Crowd control used* lists each control spell
  (stuns, fears, roots and the like) with the times you cast it, whether or not it landed. A
  shapeshift form is not control, whatever the game's flag says. The *Interrupts* section is
  the game's credit, for everyone, and names what was interrupted.
  These are yours only: the game gives an addon the casts of the other players as secret
  values (every one of them, in a real key), so there is no column of it on the scoreboard.
- The addon's chat lines start with "Rocket Meter", with the space, like the rest of the addon.
