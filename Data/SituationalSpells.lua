-- RocketMeter | Data/SituationalSpells.lua
-- Written by hand (01/10/2026); each id read on the spell's own page.
--
-- Cooldowns that are pressed WHEN SOMETHING ASKS FOR THEM, and not as often as they come back.
-- "My run" counted how many times each cooldown of the game's list fitted in the fight and
-- showed the ones left idle. The user, with a combat resurrection on the screen as "used 0 of
-- 7": *"poderia ter usado 7 vezes, mas talvez não precisasse ou não tem 7 mortes (...) tem que
-- ser mais analítico nesse sentido"*. Nobody is behind for not resurrecting when nobody died.
--
--   rez     a combat resurrection: asks for a death, and its charges are shared by the group
--   haste   Bloodlust and its kin: once per fight, and every player is locked out for 10 minutes
--
-- Two more kinds come from what the game already says and need no list here (MyRun.lua):
-- interrupts (`Data/InterruptSpells.lua`) and crowd control (`C_Spell.IsSpellCrowdControl`).
local ADDON, ns = ...

ns.SituationalSpells = {
    [20484] = "rez",     -- Rebirth (DRUID)
    [61999] = "rez",     -- Raise Ally (DEATHKNIGHT)
    [20707] = "rez",     -- Soulstone (WARLOCK)
    [391054] = "rez",    -- Intercession (PALADIN)
    [2825] = "haste",    -- Bloodlust (SHAMAN)
    [32182] = "haste",   -- Heroism (SHAMAN)
    [80353] = "haste",   -- Time Warp (MAGE)
    [264667] = "haste",  -- Primal Rage (HUNTER)
    [390386] = "haste",  -- Fury of the Aspects (EVOKER)
}
