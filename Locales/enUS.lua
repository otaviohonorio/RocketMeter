-- RocketMeter | Locales/enUS.lua
-- As chaves SÃO o texto em inglês: sem tradução, a própria chave é exibida.
-- Cada idioma novo é um arquivo que sobrescreve as chaves que quiser.
local ADDON, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, key)
        return key
    end,
})

-- Rótulos de atributo que não vêm prontos do cliente ficam aqui como referência
-- do que existe para traduzir:
--
--   Dmg, DPS, Heal, HPS, Absorb, Taken, Avoid, Interr, Dispel, Deaths, Enemies
--   Current fight, Overall, Mythic+, Raid, Damage only
--   Presets, Visible columns, Window, ...
