# Rocket Meter 0.88.0

**The end-of-key scoreboard now waits for the chest, like Details.** It used to open a second and a
half after the key ended — before anyone had opened the chest, so there was no loot and no new
keystone for anybody yet. It now opens when you close the chest's loot window, already with the
items and the new keys, and keeps updating for two minutes for whoever loots later.

- **Other players' keystones show up again.** They came only from a library bundled with Details;
  the scoreboard now also reads the keystone protocol used by DBM and BigWigs, so anyone running
  one of those three shares their key.
- **Loot from players of another realm** now appears on their row (it was missed unless it arrived
  in the first two minutes).
- **Minimap button:** left-click opens the options, Shift-click shows or hides the meter (also
  `/rm`), right-click opens the last run's scoreboard.
- **Support the project:** a small link in the corner of the options window opens the PayPal link ready to copy —
  in reais when the game is in Portuguese, in dollars otherwise.
- The published addon no longer writes a debug log to your disk.
