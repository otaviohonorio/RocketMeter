-- RocketMeter | SpellsPage.lua
-- The "Spells" tab of the two player screens ("My run" and the screen of another player): one
-- line per spell with how many times it was cast AND what it gave.
--
-- (!) ONE TAB WHERE THERE WERE TWO (08/10). "My run" had a "Casts" tab (each spell, how many
-- times, share, per minute) and a "Spells" tab (each spell, damage, per second, share): the same
-- spells twice, with a different number beside them. The user: *"a aba lançamentos e magias não
-- parece meio redundante? não daria para unificar?"* and, told how: *"faça e ajuste as skins
-- para ficar de acordo"*.
--
-- THE SKIN IS THE WINDOW'S. The old Spells tab was the meter's floating spell panel put inside
-- the window: its own row, its own fonts and sizes, beside four tabs made of other pieces. This
-- page is built from the same pieces as those tabs (`ns.MyRunWindow.Kit`: the bar row, the
-- game's font objects, the game's colour objects) inside the game's scroll frame.
--
-- WHAT IS JOINED, AND HOW. The casts are the run's own record (MyRun.lua), the amounts are the
-- game's meter. A cast and the line of the meter it produced are matched by spell id, and by
-- NAME when the ids differ (the spell cast and the spell that lands are often two ids with one
-- name). What was cast and gave no damage or healing of its own (a defensive, a movement spell)
-- goes to "Other casts"; what gave damage without being cast (a proc, a pet) has no count.
--
-- WHAT IS NOT THERE. The meter answers the spells of a player only for its current fight and
-- its overall: for one boss of the run, or a run of the history, there are the casts and no
-- amounts, and the note at the foot says so. Of another player there are no casts at all (the
-- game hides them), so that screen has the amounts alone.
local ADDON, ns = ...
local L = ns.L

local Page = {}
ns.SpellsPage = Page

local TITLE = 16
local HEAD = 14
local BAR = 20
local STEP = BAR + 2
local GAP = 10
local SCROLL_BAR = 24
local ALL = 200                 -- the whole breakdown: the casts and the talents are looked up in it
-- (20/10) one tab per kind (MyRunWindow): the damage and the casts get the room of a whole tab
local MAX = { damage = 20, healing = 12, absorbs = 8, casts = 12, castsAlone = 40, talent = 8, small = 8 }
-- The number columns, from the right edge inwards.
local COLS = {
    { key = "share", width = 40 }, { key = "rate", width = 64 }, { key = "amount", width = 64 },
    { key = "perMinute", width = 52 }, { key = "casts", width = 44 },
}
local COL_GAP = 4
Page.Geometry = { COLS = COLS, MAX = MAX, STEP = STEP, TITLE = TITLE, HEAD = HEAD, GAP = GAP }

local function Kit() return ns.MyRunWindow and ns.MyRunWindow.Kit end

local function SpellName(spellID)
    if not (C_Spell and C_Spell.GetSpellName) or type(spellID) ~= "number" then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

--------------------------------------------------------------------------------
-- The model: the sections and their rows, with nothing of the screen in it
--------------------------------------------------------------------------------
---@param ctx table { guid, creatureId, source, sessionType (0, 1 or nil), own (MyRun.Own, or nil), mine }
---@return table[] sections { key, title, head, rows = { { spellID, casts, perMinute, amount, rate, share, count, bar } }, top }
function Page.Model(ctx)
    local sections = {}
    local own = ctx.own
    local st = ctx.sessionType
    local E = Enum.DamageMeterType
    local minutes = own and own.combatSeconds and own.combatSeconds > 0 and own.combatSeconds / 60 or nil

    -- The casts by name, to find the cast behind a line of the meter with another id.
    local castsByName, matchedId, matchedName = {}, {}, {}
    for id, n in pairs(own and own.bySpell or {}) do
        local name = SpellName(id)
        if name then castsByName[name] = (castsByName[name] or 0) + n end
    end
    local function CastsOf(spellID)
        if not own then return nil end
        local name = SpellName(spellID)
        if name and castsByName[name] then
            matchedName[name] = true
            return castsByName[name]
        end
        local n = own.bySpell and own.bySpell[spellID]
        if n then matchedId[spellID] = true end
        return n
    end

    -- (20/10) The lists kept with the run (MyRun.ReadSpells): a boss, the trash, the whole run, a run of the
    -- history. `ctx.stored` is them, `ctx.seconds` the combat time of the scope (the rate is over it).
    local STORED = { [E.DamageDone] = "damage", [E.Absorbs] = "absorbs", [E.Interrupts] = "interrupts", [E.Dispels] = "dispels" }
    local function Stored(attrs)
        local key = attrs == "healing" and "healing" or STORED[attrs[1]]
        local list = key and ctx.stored[key]
        if not list or #list == 0 then return nil, nil end
        local all, total = {}, 0
        for _, sp in ipairs(list) do
            total = total + sp.amount
            all[#all + 1] = { spellID = sp.spellID, amount = sp.amount,
                              perSecond = sp.perSecond or (ctx.seconds and ctx.seconds > 0 and sp.amount / ctx.seconds) or nil }
        end
        if total <= 0 then return nil, nil end
        return all, total
    end

    local function Breakdown(attrs)
        if st == nil and ctx.stored then return Stored(attrs) end
        if st == nil or ctx.guid == nil then return nil, nil end
        local all, total
        if attrs == "healing" then
            -- Healing WITHOUT the shields: the game's healing done carries them (Data.lua).
            all, total = ns.Data.GetPureHealing(st, ctx.guid, ctx.creatureId, ALL)
        else
            all, total = ns.Data.GetSpellBreakdown(st, attrs, ctx.guid, ctx.creatureId, ALL)
        end
        if not all or #all == 0 or not total or total <= 0 then return nil, nil end
        return all, total
    end

    -- 1 and 2. What each spell gave, with how many times it was cast.
    local function Amounts(key, title, attrs, limit)
        local all, total = Breakdown(attrs)
        if not all then return nil, nil end
        local rows = {}
        for i, sp in ipairs(all) do
            -- Every line is looked up, shown or not: a cast matched beyond the limit is still
            -- not an "other cast".
            local casts = CastsOf(sp.spellID)
            if i <= limit then
                local row = { spellID = sp.spellID, amount = sp.amount, rate = sp.perSecond,
                    share = sp.amount / total * 100, casts = casts,
                    perMinute = casts and minutes and casts / minutes or nil, bar = sp.amount }
                rows[#rows + 1] = row
            end
        end
        sections[#sections + 1] = { key = key, title = format("%s: %s", title, ns.Data.FormatAmount(total) or "-"),
            -- (14/10) Another player: the game hides his casts, so no "Casts" and "/min" headers
            -- over columns that are always empty.
            head = own and "amounts" or "amountsOnly", rows = rows, top = rows[1].bar }
        return all, total
    end
    local damage, damageTotal = Amounts("damage", L["Damage"], { E.DamageDone }, MAX.damage)
    -- Healing and absorption apart, each with the game's own name: a shield does not heal
    -- (08/10, Matted Fur listed as healing on a druid; see Breakdown.lua).
    local healing, healingTotal = Amounts("healing", L["Healing"], "healing", MAX.healing)
    local absorbs, absorbsTotal = Amounts("absorbs", L["Absorbs"], { E.Absorbs }, MAX.absorbs)

    -- 3. What was cast and gave no damage or healing of its own. Without any amount at all (in
    -- combat, a boss of the run, a run of the history) this is the whole list of casts.
    if own and own.bySpell then
        local list = {}
        for id, n in pairs(own.bySpell) do
            local name = SpellName(id)
            -- (20/10) the Casts tab lists every cast, matched to an amount or not (Warcraft Logs' "Casts")
            if ctx.allCasts or (not matchedId[id] and not (name and matchedName[name])) then
                list[#list + 1] = { spellID = id, casts = n, share = (own.casts or 0) > 0 and n / own.casts * 100 or 0,
                    perMinute = minutes and n / minutes or nil, bar = n }
            end
        end
        table.sort(list, function(a, b)
            if a.casts == b.casts then return a.spellID < b.spellID end
            return a.casts > b.casts
        end)
        if #list > 0 then
            local alone = ctx.allCasts or (not damage and not healing and not absorbs)
            local limit = alone and MAX.castsAlone or MAX.casts
            while #list > limit do table.remove(list) end
            local K = Kit()
            sections[#sections + 1] = { key = "casts", head = "casts", rows = list, top = list[1].bar,
                title = alone and format(L["Casts — %d in %s of combat"], own.casts or 0, K and K.Clock(own.combatSeconds or 0) or "")
                    or L["Other casts"] }
        end
    end

    -- 3b. (14/10) What the game reported as a cast and the player did not press: effects it
    -- triggers (a proc reported as a cast), the world, a delve's or a zone's power. Shown so that
    -- nothing vanishes, and out of every count (casts, per minute, gaps).
    if own and own.notPressed and next(own.notPressed) then
        local list = {}
        for id, n in pairs(own.notPressed) do list[#list + 1] = { spellID = id, casts = n, bar = n } end
        table.sort(list, function(a, b)
            if a.casts == b.casts then return a.spellID < b.spellID end
            return a.casts > b.casts
        end)
        while #list > MAX.small do table.remove(list) end
        sections[#sections + 1] = { key = "notPressed", head = "casts", rows = list, top = list[1].bar,
            title = L["Not counted: automatic effects, the world and delves"] }
    end

    -- 4. (14/10) What the talents of the build gave moved to its own tab, "Build"; (20/10) that tab was removed.

    -- 5. Counts: the interrupts the game credited, the interrupts and the control cast, dispels.
    local function Counts(key, title, list)
        if not list or #list == 0 then return end
        local rows, total = {}, 0
        for _, sp in ipairs(list) do total = total + (sp.amount or 0) end
        for i = 1, math.min(#list, MAX.small) do
            local sp = list[i]
            rows[i] = { spellID = sp.spellID, count = sp.amount, share = total > 0 and sp.amount / total * 100 or nil, bar = sp.amount }
        end
        sections[#sections + 1] = { key = key, title = title, rows = rows, top = rows[1].bar }
    end
    Counts("interrupts", L["Interrupts"], (Breakdown({ E.Interrupts })))
    if st ~= nil and ctx.source and ns.Data.GetCastBreakdown then
        local interrupts, control, missed = ns.Data.GetCastBreakdown(st, ctx.source, ctx.guid, ctx.creatureId)
        Counts("interruptCasts", missed and format(L["%s (%d missed)"], L["Interrupts cast"], missed) or L["Interrupts cast"], interrupts)
        Counts("control", L["Crowd control used"], control)
    end
    Counts("dispels", L["Dispels"], (Breakdown({ E.Dispels })))

    -- (20/10) One tab per kind, after Warcraft Logs: `ctx.only` keeps the sections of the tab.
    if ctx.only then
        local kept = {}
        for _, section in ipairs(sections) do
            if ctx.only[section.key] then kept[#kept + 1] = section end
        end
        sections = kept
    end
    return sections
end

--------------------------------------------------------------------------------
-- The page
--------------------------------------------------------------------------------
---Builds the page inside `page` (a tab's frame): the game's scroll frame, and what scrolls.
function Page.Build(page, width)
    local K = Kit()
    page.scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT")
    page.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR, 0)
    page.child = CreateFrame("Frame", nil, page.scroll)
    page.contentWidth = width - SCROLL_BAR
    page.child:SetSize(page.contentWidth, 10)
    page.scroll:SetScrollChild(page.child)
    page.titles, page.heads, page.rows = {}, {}, {}
    page.note = K.Text(page.child, "GameFontDisableSmall")
    page.note:SetWordWrap(true)
    page.note:SetJustifyV("TOP")
    page.note:SetWidth(page.contentWidth - 8)
    page.empty = K.Text(page.child, "GameFontDisableSmall")
    page.empty:SetPoint("TOPLEFT", 4, -4)
    return page
end

---The number columns of a row or of a header line, right-aligned at the same places.
local function Columns(parent, anchor, template)
    local K = Kit()
    local cols, x = {}, -6
    for _, c in ipairs(COLS) do
        local fs = K.Text(parent, template, "RIGHT")
        fs:SetPoint("RIGHT", anchor, "RIGHT", x, 0)
        fs:SetWidth(c.width)
        cols[c.key] = fs
        x = x - c.width - COL_GAP
    end
    return cols, x
end

local function Row(page, index)
    local r = page.rows[index]
    if r then return r end
    local K = Kit()
    r = K.BarRow(page.child)
    r.value:SetText("")
    local left
    r.cols, left = Columns(r.text, r, "GameFontHighlightSmall")
    r.name:ClearAllPoints()
    r.name:SetPoint("LEFT", BAR + 8, 0)
    r.name:SetPoint("RIGHT", r, "RIGHT", left, 0)
    page.rows[index] = r
    return r
end

local function Head(page, index)
    local h = page.heads[index]
    if h then return h end
    h = CreateFrame("Frame", nil, page.child)
    h:SetHeight(HEAD)
    h.cols = Columns(h, h, "GameFontDisableSmall")
    page.heads[index] = h
    return h
end

local function Title(page, index)
    local t = page.titles[index]
    if t then return t end
    t = Kit().Text(page.child, "GameFontNormalSmall")
    page.titles[index] = t
    return t
end

local HEAD_LABELS = {
    amounts = { casts = L["Casts"], perMinute = L["/min"], amount = L["Total"], rate = L["Per second"], share = L["%"] },
    amountsOnly = { amount = L["Total"], rate = L["Per second"], share = L["%"] },
    casts = { casts = L["Casts"], perMinute = L["/min"], share = L["%"] },
}

---A paragraph of a section (the "Build" tab's list of talents the game does not measure).
local function Paragraph(page, index)
    page.paragraphs = page.paragraphs or {}
    local t = page.paragraphs[index]
    if t then return t end
    t = Kit().Text(page.child, "GameFontHighlightSmall")
    t:SetWordWrap(true)
    t:SetJustifyV("TOP")
    t:SetJustifyH("LEFT")
    page.paragraphs[index] = t
    return t
end

---Draws the page.
---@param ctx table what `Page.Model` takes, plus `classFilename`, `note` and `empty`; `model`
---draws another list of sections with the same pieces (the "Build" tab)
function Page.Draw(page, ctx)
    local K = Kit()
    local sections = (ctx.model or Page.Model)(ctx)
    page.sections = sections
    local cr, cg, cb = ns.ClassColor(ctx.classFilename)
    local k = K.BarBrightness()
    cr, cg, cb = (cr or 1) * k, (cg or 1) * k, (cb or 1) * k
    local width = page.contentWidth
    local y, rowsUsed, headsUsed, textsUsed = 0, 0, 0, 0

    for index, section in ipairs(sections) do
        local title = Title(page, index)
        title:ClearAllPoints()
        title:SetPoint("TOPLEFT", 2, -(y + 1))
        title:SetText(section.title)
        title:Show()
        section.titleString = title
        y = y + TITLE

        local labels = section.head and HEAD_LABELS[section.head]
        if labels then
            headsUsed = headsUsed + 1
            local h = Head(page, headsUsed)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", 0, -y)
            h:SetWidth(width)
            for key, fs in pairs(h.cols) do fs:SetText(labels[key] or "") end
            h:Show()
            y = y + HEAD
        end

        section.frames = {}
        for i, data in ipairs(section.rows) do
            rowsUsed = rowsUsed + 1
            local r = Row(page, rowsUsed)
            section.frames[i] = r
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            r:SetWidth(width)
            r.icon:SetTexture(data.icon or K.SpellIcon(data.spellID))
            r.name:SetText(data.name or K.SpellNameOf(data.spellID))
            local c = r.cols
            c.casts:SetText(data.casts and tostring(data.casts) or "")
            c.perMinute:SetText(data.perMinute and format("%.1f", data.perMinute) or "")
            c.amount:SetText(data.count and tostring(data.count) or (data.amount and K.Fmt(data.amount)) or "")
            c.rate:SetText(data.rate and data.rate > 0 and K.Fmt(data.rate) or "")
            c.share:SetText(data.share and format("%d%%", math.floor(data.share + 0.5)) or "")
            -- White for what was done and how much; the game's light grey for the rates.
            K.Colour(c.perMinute, LIGHTGRAY_FONT_COLOR)
            K.Colour(c.rate, LIGHTGRAY_FONT_COLOR)
            r.bar:SetMinMaxValues(0, math.max(1, section.top or 1))
            r.bar:SetValue(data.bar or 0)
            r.bar:SetStatusBarColor(cr, cg, cb)
            r:Show()
            y = y + STEP
        end
        if section.text then
            textsUsed = textsUsed + 1
            local t = Paragraph(page, textsUsed)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", 4, -y)
            t:SetWidth(width - 8)
            t:SetText(section.text)
            t:Show()
            section.textString = t
            y = y + math.max(STEP, (t.GetStringHeight and t:GetStringHeight() or STEP) + 4)
        end
        y = y + GAP
    end
    for i = textsUsed + 1, #(page.paragraphs or {}) do page.paragraphs[i]:Hide() end

    for i = #sections + 1, #page.titles do page.titles[i]:Hide() end
    for i = headsUsed + 1, #page.heads do page.heads[i]:Hide() end
    for i = rowsUsed + 1, #page.rows do page.rows[i]:Hide() end

    page.empty:SetShown(#sections == 0)
    page.empty:SetText(ctx.empty or "")
    if #sections == 0 then y = TITLE + GAP end

    page.note:ClearAllPoints()
    page.note:SetPoint("TOPLEFT", 4, -y)
    page.note:SetText(ctx.note or "")
    page.child:SetHeight(y + 44)
    return sections
end
