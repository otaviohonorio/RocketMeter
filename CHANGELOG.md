# Rocket Meter 0.97.0

- Much lighter in combat: the window no longer redraws on every update the game's meter sends during a fight (it could send about 150 a second). Measured in a Mythic+ key, from about 10 ms to about 0.15 ms per frame.
- The interrupt icon stays on the row of a player who left the group after the key.
- When an enemy's cast is cut by crowd control (a stun, fear or similar left on it), a teammate's interrupt is not put on cooldown.
