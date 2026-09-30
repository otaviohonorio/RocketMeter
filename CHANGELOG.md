# Rocket Meter 0.90.0

- **The scoreboard opens from the meter.** A magnifier in the meter's title bar opens the
  scoreboard with the session the window is on (current fight or overall), without what only a
  finished key has: keystone, score, loot, level, affixes and timeline.
- **The scoreboard's column header has two lines.** The family on top ("Damage",
  "Interrupts") and the part of each column under it ("total", "per s", "hits", "misses"). A
  family with one column keeps its name alone; a family of two has its name centred over both.
- **Two new columns, counted from casts.** *Interrupts: misses* is the interrupts that cut
  nothing (casts of an interrupt spell minus the interrupts the game credited). *CC* is the
  crowd control cast (stuns, fears, roots and the like), which counts the cast, not whether it
  landed. Both are on the scoreboard, and off by default in the meter's window.
- **The pet counts for its owner.** The warlock's felhunter kick goes on the warlock's line.
- **The player panel** (click a row) gains two sections: the interrupts spell by spell, with how
  many were credited and how many missed, and the crowd control used, spell by spell.
- What the game hides stays empty, never zero: the game gives the casts of other players to an
  addon only in some places, and a cell that could not be counted shows "-".
- The addon's chat lines start with "Rocket Meter", with the space, like the rest of the addon.
