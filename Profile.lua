-- RocketMeter | Profile.lua
-- Where the settings are kept: in the account (the default) or only on this character.
--
-- `ns.db` is a stable proxy: whoever reads or writes in it never needs to know which of the two
-- stores is active. That matters because the Settings API keeps the table's reference
-- at registration time -- if `ns.db` were swapped for another table, the options panel
-- would keep writing in the old one.
local ADDON, ns = ...
local L = ns.L

local Profile = {}
ns.Profile = Profile

local active

local function Fill(store)
    for k, v in pairs(ns.defaults) do
        if store[k] == nil then
            store[k] = type(v) == "table" and CopyTable(v) or v
        end
    end
end

--- Defaults that can only be built with the client loaded (they depend on Enum).
--- Called at login and whenever the settings are swapped or reset.
function Profile.EnsureRuntimeDefaults()
    if not active then return end

    -- Columns saved in the old format (Enum ids) become keys -- and the list comes out NORMALISED
    -- (grouped by family, the total+rate pair complete, the total before the rate).
    --
    -- ⚑ BOTH THINGS ARE ALWAYS ADOPTED; only the FORMAT MIGRATION has a consequence. Regrouping
    -- does not invalidate the chosen sort nor is it news to the player: erasing `sortBy` and
    -- announcing "columns migrated" at every login, because of a reordering, would be throwing away
    -- his choice and lying in the chat about the reason.
    local migrated, changed, dropped = ns.Data.MigrateColumns(active.columns)
    if migrated then
        active.columns = migrated
        if changed then
            active.sortBy = nil
            ns.Print(L["columns migrated to the new format."])
        elseif dropped then
            ns.Print(L["columns that no longer exist were removed."])
        end
    elseif type(active.columns) == "table" and #active.columns > 0 then
        -- (14/10) Nothing of the saved list exists any more: the window stayed empty for good.
        -- The default set comes in (below), and the sort with it.
        active.columns = nil
        active.sortBy = nil
        ns.Print(L["columns that no longer exist were removed."])
    end

    if not active.columns or #active.columns == 0 then
        local preset = ns.Data.GetPresets().mplus
        active.columns = preset and CopyTable(preset.columns) or { "damage" }
    end

    if not active.sortBy or not ns.Data.GetColumn(active.sortBy) then
        active.sortBy = active.columns[1]
    end

    -- `autoScoreboard` (one key) became two: Mythic+ and raid. Whoever had turned the panel off
    -- would get it back on, because the new keys are born `true` -- so the old choice
    -- is inherited once and the old key goes away, so the inheritance does not repeat.
    local herdouDaChaveAntiga = false
    if active.autoScoreboard ~= nil then
        active.autoScoreboardMPlus = active.autoScoreboard
        active.autoScoreboardRaid = active.autoScoreboard
        active.autoScoreboard = nil
        herdouDaChaveAntiga = true
    end

    -- ⚑ THE RAID DEFAULT BECAME OFF, AND A DEFAULT DOES NOT REACH A PROFILE THAT ALREADY EXISTS. The key was
    -- written `true` at the first login of whoever already used the addon, and `Fill` only fills a
    -- MISSING key -- so, without this inheritance, the request *"o placar da raid por padrão pode deixar
    -- desabilitado"* would change nothing for whoever asked.
    --
    -- ONCE ONLY, for the same reason as the inheritance above: marked by a key of its own, so it does not turn off
    -- again if the player turns the raid one back on later. Repeating would be the settings coming back
    -- by themselves -- the defect the old key's inheritance already avoided once.
    --
    -- ⚑ AND IT DOES NOT RUN OVER WHOEVER JUST INHERITED THE OLD KEY: there was a deliberate
    -- choice there (the player had turned the panel on or off), and a choice is worth more than a new
    -- default. `raidAutoReviewed` stays OUT of `ns.defaults` on purpose: if it were there, `Fill`
    -- would mark it before this line ran and the inheritance would never happen.
    if active.raidAutoReviewed == nil then
        if not herdouDaChaveAntiga then
            active.autoScoreboardRaid = false
        end
        active.raidAutoReviewed = true
    end

    -- `fontOutline` kept WoW's FLAG ("OUTLINE"); now it keeps the player's choice
    -- ("thin"), on the same scale as the reference chat. Without this conversion the saved value matches
    -- no option of the combo and it shows **empty** -- which is exactly what showed in the
    -- first test of the new screen.
    local fromFlags = { OUTLINE = "thin", THICKOUTLINE = "thick", [""] = "none" }
    if fromFlags[active.fontOutline] then
        active.fontOutline = fromFlags[active.fontOutline]
    end

    -- ONE text became THREE (body, title, header), each with its own size, outline and shadow.
    -- The old keys were single for the whole window; inheriting each one in the three
    -- roles keeps the screen EXACTLY as the player left it -- only now separable.
    --
    -- The size is the exception: inheriting the single size in all three would flatten the hierarchy (title and
    -- header smaller than the row, which is what the native meter does). So the saved size goes
    -- to the row, and the other two keep the distance they had -- the deltas -2 and -4.
    -- (14/10) Only when there are old keys to carry over. A new (or reset) profile has none, and
    -- building `text` here gave its header the body's thin outline, against ROLE_DEFAULTS (the
    -- header's is "none"); with no `text`, every role reads ROLE_DEFAULTS.
    local old = active.fontSize ~= nil or active.fontOutline ~= nil or active.fontShadow ~= nil
    if not active.text and old then
        local size = type(active.fontSize) == "number" and active.fontSize or 16
        local outline = active.fontOutline or "thin"

        local shadow = active.fontShadow ~= false

        active.text = {
            body   = { size = size,     outline = outline, shadow = shadow },
            title  = { size = size - 2, outline = outline, shadow = shadow },
            header = { size = size - 4, outline = outline, shadow = shadow },
        }
        active.fontSize, active.fontOutline, active.fontShadow = nil, nil, nil
    end

    -- ⚑ THE SAVED "MEDIUM" BECOMES "THIN", and this is the migration that matters.
    --
    -- The option went away on 08/09 (*"tira o contorno medio das opcoes, claramente tu nao conseguiu
    -- fazer ele funcionar, sempre fica igual ao fino"*). Without this step, `ns.OutlineFor` would not
    -- find "medium" in the list of choices and would return `""` -- the outline would vanish by itself at the
    -- next login, without anyone asking, and in one role only (whichever was on medium).
    --
    -- ⚑ AND IT STAYS HERE, OUTSIDE `if not active.text`. The first version of this migration went
    -- inside that block, which only runs while the profile is still in the SINGLE font format --
    -- and whoever chose "medium" had left that format long before, by definition. It was the
    -- user's own SavedVariables that showed it: `text.header.outline = "medium"`, with
    -- `active.text` existing. The migration would have passed right by exactly whoever it exists
    -- to serve.
    --
    -- It becomes "thin", and not "thick", for the reason he gave himself: it was the thin one he was seeing all
    -- along. The migration delivers what was already on screen, not something else.
    if type(active.text) == "table" then
        for _, papel in pairs(active.text) do
            if type(papel) == "table" and papel.outline == "medium" then
                papel.outline = "thin"
            end
        end
    end
end

function Profile.Init()
    RocketMeterDB = RocketMeterDB or {}
    RocketMeterCharDB = RocketMeterCharDB or {}

    active = RocketMeterCharDB.usePerCharacter and RocketMeterCharDB or RocketMeterDB
    Fill(active)
end

function Profile.IsPerCharacter()
    return RocketMeterCharDB and RocketMeterCharDB.usePerCharacter == true
end

--- Turns this character's own settings on or off.
--- When turned on the first time, it inherits what holds now -- nobody wants to start from zero.
function Profile.SetPerCharacter(enabled)
    if enabled == Profile.IsPerCharacter() then return end

    if enabled then
        for k, v in pairs(active) do
            if k ~= "usePerCharacter" and RocketMeterCharDB[k] == nil then
                RocketMeterCharDB[k] = type(v) == "table" and CopyTable(v) or v
            end
        end
        RocketMeterCharDB.usePerCharacter = true
        active = RocketMeterCharDB
    else
        RocketMeterCharDB.usePerCharacter = false
        active = RocketMeterDB
    end

    Fill(active)
    Profile.EnsureRuntimeDefaults()
    ns.Print(enabled and L["settings for this character only."] or L["settings shared by the account."])

    -- (14/10) Everything the profile holds, not only the scale and the columns: the position, the
    -- lock, the visibility and the minimap button stayed as they were until a /reload.
    if ns.Window then
        ns.Window.ApplyScale()
        ns.Window.ApplyPosition()
        ns.Window.ApplyLock()
        ns.Window.Rebuild()
        ns.Window.ApplyVisibility()
    end
    if ns.Minimap and ns.Minimap.ApplyVisibility then ns.Minimap.ApplyVisibility() end
end

--- Sets these settings back to the factory defaults.
function Profile.Reset()
    for k in pairs(active) do
        if k ~= "usePerCharacter" then
            active[k] = nil
        end
    end
    Fill(active)
    Profile.EnsureRuntimeDefaults()
    -- (14/10) Everything the profile holds, not only the scale and the columns: the position, the
    -- lock, the visibility and the minimap button stayed as they were until a /reload.
    if ns.Window then
        ns.Window.ApplyScale()
        ns.Window.ApplyPosition()
        ns.Window.ApplyLock()
        ns.Window.Rebuild()
        ns.Window.ApplyVisibility()
    end
    if ns.Minimap and ns.Minimap.ApplyVisibility then ns.Minimap.ApplyVisibility() end
end

-- The proxy. `pairs(ns.db)` does not work on purpose: use ns.Profile.Raw() for that.
ns.db = setmetatable({}, {
    __index = function(_, key)
        return active and active[key]
    end,
    __newindex = function(_, key, value)
        if active then active[key] = value end
    end,
})

function Profile.Raw()
    return active
end
