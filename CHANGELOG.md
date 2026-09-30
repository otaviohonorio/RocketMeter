# Rocket Meter 0.90.0

- **Two new columns, counted from casts: "Missed" and "CC".** *Missed* is the interrupts that
  cut nothing: the casts of an interrupt spell minus the interrupts the game credited. *CC* is
  the crowd control used (stuns, fears, roots and the like), which counts the cast, not whether
  it landed. Both are off by default: turn them on in the column panel.
- **The pet counts for its owner.** The warlock's felhunter kick goes on the warlock's line.
- **The player panel** (click a row) gains two sections: the interrupts spell by spell, with how
  many were credited and how many missed, and the crowd control used, spell by spell. Dispels
  keep a section of their own.
- What the game hides stays empty, never zero: the game gives the casts of other players to an
  addon only in some places, and a cell that could not be counted shows "-".
- The addon's chat lines start with "Rocket Meter", with the space, like the rest of the addon.
