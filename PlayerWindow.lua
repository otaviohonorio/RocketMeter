-- RocketMeter | PlayerWindow.lua
-- The screen of ANOTHER player: what the game lets an addon know about someone who is not you.
--
-- (!) WHY IT IS NOT "MY RUN" WITH ANOTHER NAME (01/10). The user, after "My run": *"e essa tela
-- de detalhamento, tem como fazer para os outros players? é possível pegar?"* -- and, told what
-- the game gives and what it hides: *"então faz com o que tem, as informações da tela pode ficar
-- um pouco diferente, mas segue o padrão de janela"*.
--
-- What the game gives of another player, out of combat: the meter's numbers (damage, healing,
-- damage taken, avoidable damage, interrupts, dispels, deaths), each with the group's total and
-- so with a rank and a share; the spells behind each number; and when each death was. What it
-- hides: the casts (measured on 30/09: 3,035 casts of party members, every spell id secret), so
-- no cast list, no rhythm, no cooldown use, no potion; the Cooldown Manager's list (it is the
-- player's own spec's); and the blows of a death (the recap is the local player's).
--
-- So this screen has two tabs where "My run" has five, and says at the foot what is missing and
-- why. The window is the same: the game's frame and inset, its tabs, its boxes and its
-- dropdown, the meter's flat bars, the support line -- built from the same pieces
-- (`ns.MyRunWindow.Kit`).
local ADDON, ns = ...
local L = ns.L

local Win = {}
ns.PlayerWindow = Win

local WIDTH = 760
local PAD = 12
local TOP_BAND = 60
local TILE_HEIGHT = 46
local TITLE = 16
local BAR_HEIGHT = 20
local GAP = 10
local INNER = WIDTH - 16 - PAD * 2
local LEFT_WIDTH = 420
local RIGHT_WIDTH = INNER - LEFT_WIDTH - GAP
local MAX_TAKEN = 8
local MAX_DEATHS = 6
local SCROLL_BAR = 24
local TABS = { "summary", "spells" }
local TAB_LABEL = { summary = "Summary", spells = "Spells" }
-- The share of the group, one bar each: what the number is, and the key of `Win.Numbers`.
local SHARES = {
    { key = "damage", label = "Damage" }, { key = "healing", label = "Healing" },
    { key = "taken", label = "Damage taken" }, { key = "avoidable", label = "Avoidable damage" },
}

local frame
local view = { tab = "summary", source = nil, sessionType = 1 }

local function Readable(v) return v ~= nil and not issecretvalue(v) end
local function Num(v) return Readable(v) and type(v) == "number" and v or nil end
local function Kit() return ns.MyRunWindow and ns.MyRunWindow.Kit end

--------------------------------------------------------------------------------
-- The numbers
--------------------------------------------------------------------------------
---One metric of a player: total, per second, rank in the group, the group's size and total.
---nil when the meter cannot answer (in combat every number is secret).
local function Metric(sessionType, attr, guid)
    local session = ns.Data.GetSession(sessionType, attr)
    local list = session and session.combatSources
    if type(list) ~= "table" then return nil end
    local theirs, hidden
    for i = 1, #list do
        local g = list[i].sourceGUID
        if not Readable(g) then
            hidden = true
        elseif g == guid then
            theirs = list[i]
            break
        end
    end
    local group = Num(session.totalAmount)
    -- (!) "NOT IN THE LIST" IS ONLY AN ANSWER WHEN THE LIST CAN BE READ. In combat every identity
    -- is secret: the player is not FOUND, which is not the same as having done nothing. A zero
    -- there would be the addon saying "0 damage" of someone in the middle of a fight.
    if not theirs then
        if hidden then return nil end
        return { total = 0, perSecond = 0, of = #list, groupTotal = group }
    end
    local total, per = Num(theirs.totalAmount), Num(theirs.amountPerSecond)
    if not total then return nil end
    local rank = 0
    for i = 1, #list do
        local other = Num(list[i].totalAmount)
        if other and other > total then rank = rank + 1 end
    end
    return { total = total, perSecond = per or 0, rank = rank + 1, of = #list, groupTotal = group }
end

---What the game gives of a player, for a session type (0 current fight, 1 overall).
---@return table|nil numbers nil when the meter is not answering (in combat)
function Win.Numbers(source, sessionType)
    if not (source and ns.Data and ns.Data.IsAvailable and ns.Data.IsAvailable()) then return nil end
    local guid = source.sourceGUID
    if not Readable(guid) then return nil end
    local E = Enum.DamageMeterType
    local out = {
        damage = Metric(sessionType, E.DamageDone, guid), healing = Metric(sessionType, E.HealingDone, guid),
        taken = Metric(sessionType, E.DamageTaken, guid), avoidable = Metric(sessionType, E.AvoidableDamageTaken, guid),
        interrupts = Metric(sessionType, E.Interrupts, guid), dispels = Metric(sessionType, E.Dispels, guid),
    }
    if not out.damage then return nil end

    -- The damage taken, by spell, with the game's own marks (avoidable, deadly).
    out.takenSpells = {}
    if C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType then
        local ok, container = pcall(C_DamageMeter.GetCombatSessionSourceFromType,
            ns.Data.SessionValue(sessionType), E.DamageTaken, guid, source.sourceCreatureID)
        local spells = ok and type(container) == "table" and container.combatSpells or nil
        for i = 1, (spells and #spells or 0) do
            local sp = spells[i]
            local amount = Num(sp.totalAmount)
            if amount then
                local d = sp.combatSpellDetails
                out.takenSpells[#out.takenSpells + 1] = {
                    spellID = Num(sp.spellID), amount = amount,
                    avoidable = sp.isAvoidable == true, deadly = sp.isDeadly == true,
                    creature = Readable(sp.creatureName) and sp.creatureName ~= "" and sp.creatureName
                        or (type(d) == "table" and Readable(d.unitName) and d.unitName) or nil,
                }
            end
        end
        table.sort(out.takenSpells, function(a, b) return a.amount > b.amount end)
    end

    -- The deaths: one entry each in the meter, with the second the game gives it.
    out.deaths = {}
    for _, d in ipairs(ns.Data.GetDeathList(sessionType)) do
        local mine = (d.guid ~= nil and d.guid == guid) or (d.guid == nil and d.nome ~= nil and d.nome == source.name)
        if mine then out.deaths[#out.deaths + 1] = { t = d.quando } end
    end
    table.sort(out.deaths, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return out
end

--------------------------------------------------------------------------------
-- The window
--------------------------------------------------------------------------------
local function CreatePanel()
    if frame then return frame end
    local K = Kit()

    frame = CreateFrame("Frame", ADDON .. "Player", UIParent, "ButtonFrameTemplate")
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db and type(point) == "string" then ns.db.playerPos = { point = point, relPoint = relPoint, x = x, y = y } end
    end)
    frame:Hide()
    ButtonFrameTemplate_HidePortrait(frame)
    tinsert(UISpecialFrames, frame:GetName())
    frame:SetScript("OnHide", function()
        if ns.Breakdown and ns.Breakdown.Unembed then ns.Breakdown.Unembed() end
    end)

    -- The band above the inset: who at the left, which fight at the right.
    frame.context = K.Text(frame, "GameFontHighlightSmall")
    frame.context:SetPoint("TOPLEFT", 14, -36)
    frame.sessionCombo = K.Dropdown(frame, 170)
    frame.sessionCombo:SetPoint("TOPRIGHT", -12, -30)
    frame.context:SetPoint("RIGHT", frame.sessionCombo, "LEFT", -10, 0)
    frame.sessionCombo:SetupMenu(function(_, root)
        for _, s in ipairs({ { 1, L["Overall"] }, { 0, L["Current fight"] } }) do
            root:CreateRadio(s[2], function() return view.sessionType == s[1] end,
                function() view.sessionType = s[1]; Win.SetTab(view.tab) end, s[1])
        end
    end)

    local inset = frame.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 8, -TOP_BAND)
    inset:SetPoint("BOTTOMRIGHT", -8, ns.DONATE_ROW + 6)
    frame.body = CreateFrame("Frame", nil, inset)
    frame.body:SetPoint("TOPLEFT", PAD, -PAD)
    frame.body:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    frame.pages = {}
    for _, key in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, frame.body)
        page:SetAllPoints()
        page:Hide()
        frame.pages[key] = page
    end
    local sp = frame.pages.spells
    sp.scroll = CreateFrame("ScrollFrame", nil, sp, "ScrollFrameTemplate")
    sp.scroll:SetPoint("TOPLEFT")
    sp.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR, 0)
    sp.child = CreateFrame("Frame", nil, sp.scroll)
    sp.child:SetSize(INNER - SCROLL_BAR, 10)
    sp.scroll:SetScrollChild(sp.child)

    -- The summary: four boxes, the damage taken at the left, the share of the group and the
    -- deaths at the right, and at the foot what the game does not tell.
    local page = frame.pages.summary
    local y = 0
    frame.tiles = {}
    local tileWidth = (INNER - 6 * 3) / 4
    for i = 1, 4 do
        local t = K.Tile(page)
        t:SetSize(tileWidth, TILE_HEIGHT)
        t:SetPoint("TOPLEFT", (i - 1) * (tileWidth + 6), -y)
        frame.tiles[i] = t
    end
    y = y + TILE_HEIGHT + GAP

    local taken = K.Block(page, L["Damage taken"])
    taken:SetPoint("TOPLEFT", 0, -y)
    taken:SetSize(LEFT_WIDTH, TITLE + MAX_TAKEN * (BAR_HEIGHT + 2) + 14)
    taken.rows = {}
    for i = 1, MAX_TAKEN do
        local r = K.BarRow(taken)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        taken.rows[i] = r
    end
    taken.note = K.Text(taken, "GameFontDisableSmall")
    taken.note:SetPoint("BOTTOMLEFT", 4, 0)
    taken.note:SetPoint("RIGHT")
    frame.taken = taken

    local share = K.Block(page, L["Share of the group"])
    share:SetPoint("TOPLEFT", LEFT_WIDTH + GAP, -y)
    share:SetSize(RIGHT_WIDTH, TITLE + #SHARES * (BAR_HEIGHT + 2))
    share.rows = {}
    for i = 1, #SHARES do
        local r = K.BarRow(share, false)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        share.rows[i] = r
    end
    frame.share = share

    local deaths = K.Block(page, L["Deaths"])
    deaths:SetPoint("TOPLEFT", LEFT_WIDTH + GAP, -(y + share:GetHeight() + GAP))
    deaths:SetSize(RIGHT_WIDTH, TITLE + MAX_DEATHS * 16)
    deaths.rows = {}
    for i = 1, MAX_DEATHS do
        local r = CreateFrame("Frame", nil, deaths)
        r:SetHeight(16)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * 16))
        r:SetPoint("RIGHT")
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(14, 14)
        r.icon:SetPoint("LEFT", 2, 0)
        r.icon:SetAtlas("deathrecap-icon-tombstone")
        r.text = K.Text(r, "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 22, 0)
        r.text:SetPoint("RIGHT")
        deaths.rows[i] = r
    end
    deaths.empty = K.Text(deaths, "GameFontDisableSmall")
    deaths.empty:SetPoint("TOPLEFT", 4, -TITLE)
    frame.deaths = deaths

    local bodyHeight = y + taken:GetHeight() + GAP + 28
    frame.missing = K.Text(page, "GameFontDisableSmall")
    frame.missing:SetPoint("BOTTOMLEFT", 2, 0)
    frame.missing:SetPoint("RIGHT")
    frame.missing:SetWordWrap(true)
    frame.missing:SetText(L["Casts, cooldowns, rhythm and the blows of a death are only readable for your own character: the game hides them for other players."])

    frame:SetHeight(TOP_BAND + PAD + bodyHeight + PAD + ns.DONATE_ROW + 6)
    frame.donate = ns.DonateFooter(frame)

    frame.tabs = {}
    for i, key in ipairs(TABS) do
        local tab = CreateFrame("Button", frame:GetName() .. "Tab" .. i, frame, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(L[TAB_LABEL[key]])
        tab:SetScript("OnClick", function() Win.SetTab(key) end)
        if i == 1 then tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2) end
        PanelTemplates_TabResize(tab, 0)
        frame.tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(frame, #TABS)
    return frame
end

function Win.SetTab(tab)
    if not frame then return end
    view.tab = tab
    for i, key in ipairs(TABS) do
        frame.pages[key]:SetShown(key == tab)
        if key == tab then PanelTemplates_SetTab(frame, i) end
    end
    if tab == "spells" then
        if ns.Breakdown and ns.Breakdown.Embed and view.source then
            ns.Breakdown.Embed(frame.pages.spells.child, view.source, view.sessionType)
        end
        if frame.pages.spells.scroll.SetVerticalScroll then frame.pages.spells.scroll:SetVerticalScroll(0) end
    else
        if ns.Breakdown and ns.Breakdown.Unembed then ns.Breakdown.Unembed() end
    end
    Win.Draw()
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
function Win.Draw()
    if not frame or not view.source then return end
    local K = Kit()
    local s = view.source
    local name = Readable(s.name) and s.name or "?"
    frame:SetTitle(name)
    local where = view.sessionType == 0 and L["Current fight"] or L["Overall"]
    local class = Readable(s.classFilename) and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[s.classFilename] or nil
    frame.context:SetText((class and (class .. " · ") or "") .. where)
    frame.sessionCombo:GenerateMenu()
    if view.tab == "spells" then return end

    local m = Win.Numbers(s, view.sessionType)
    local cr, cg, cb = ns.ClassColor(Readable(s.classFilename) and s.classFilename or nil)
    local k = K.BarBrightness()
    cr, cg, cb = (cr or 1) * k, (cg or 1) * k, (cb or 1) * k

    local function Set(t, number, label, s1, s2, bad)
        t.number:SetText(number or "-")
        K.Colour(t.number, bad and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
        t.label:SetText(label)
        t.side1:SetText(s1 or "")
        t.side2:SetText(s2 or "")
    end
    local function Rank(x) return x and x.rank and format(L["%dº of the group"], x.rank) or "" end
    local function Total(x) return x and (K.Fmt(x.total) .. " " .. L["in total"]) or L["out of combat only"] end
    Set(frame.tiles[1], m and K.Fmt(m.damage.perSecond), L["Damage per second"], Total(m and m.damage), Rank(m and m.damage))
    Set(frame.tiles[2], m and m.healing and K.Fmt(m.healing.perSecond), L["Healing per second"], Total(m and m.healing), Rank(m and m.healing))
    local i, d = m and m.interrupts, m and m.dispels
    Set(frame.tiles[3], i and tostring(i.total), L["Interrupts"], Rank(i),
        d and d.total > 0 and format("%d %s", d.total, L["Dispels"]) or "")
    local deaths = m and #m.deaths or nil
    Set(frame.tiles[4], deaths and tostring(deaths), deaths == 1 and L["Death"] or L["Deaths"], "", "", deaths and deaths > 0)

    -- The damage taken, by spell.
    local b = frame.taken
    local total = m and m.taken and m.taken.total or 0
    local avoidable = m and m.avoidable and m.avoidable.total or 0
    b.title:SetText(total > 0 and format("%s — %s", L["Damage taken"], K.Fmt(total)) or L["Damage taken"])
    local list = m and m.takenSpells or {}
    local top = list[1] and list[1].amount or 1
    for n, row in ipairs(b.rows) do
        local sp = list[n]
        if not sp then row:Hide() else
            row:Show()
            row.icon:SetTexture(K.SpellIcon(sp.spellID))
            row.name:SetText(K.SpellNameOf(sp.spellID) .. (sp.creature and (" · " .. sp.creature) or ""))
            row.value:SetText(K.Fmt(sp.amount))
            row.bar:SetMinMaxValues(0, top)
            row.bar:SetValue(sp.amount)
            row.bar:SetStatusBarColor(cr, cg, cb)
            if sp.deadly then row.mark:SetAtlas("icons_16x16_deadly"); row.mark:Show()
            elseif sp.avoidable then row.mark:SetAtlas("damagemeters-avoidabledamage-icon"); row.mark:Show()
            else row.mark:Hide() end
        end
    end
    if not m then
        b.note:SetText(L["In combat the meter's numbers are hidden; they come back when it ends."])
    elseif #list == 0 then
        b.note:SetText(L["Nothing taken."])
    else
        b.note:SetText(total > 0 and format(L["%d%% avoidable"], math.floor(avoidable / total * 100 + 0.5)) or "")
    end

    -- The share of the group: how much of each of the group's totals is this player's.
    for n, spec in ipairs(SHARES) do
        local row = frame.share.rows[n]
        local x = m and m[spec.key]
        local pct = x and x.groupTotal and x.groupTotal > 0 and x.total / x.groupTotal * 100 or nil
        row.name:SetText(L[spec.label])
        row.value:SetText(pct and format("%d%%", math.floor(pct + 0.5)) or "-")
        row.bar:SetMinMaxValues(0, 100)
        row.bar:SetValue(pct or 0)
        row.bar:SetStatusBarColor(cr, cg, cb)
    end

    -- The deaths, each with the second the game's meter gives it.
    local dl = m and m.deaths or {}
    for n, row in ipairs(frame.deaths.rows) do
        local death = dl[n]
        if not death then row:Hide() else
            row:Show()
            row.text:SetText(death.t and format(L["at %s"], K.Clock(death.t)) or L["time not given by the game"])
        end
    end
    frame.deaths.empty:SetText(#dl == 0 and (m and L["No death."] or "") or "")
    frame.deaths.title:SetText(#dl > MAX_DEATHS and format("%s (%d)", L["Deaths"], #dl) or L["Deaths"])
end

---Opens the screen of a player (a source of the meter).
function Win.Show(source, sessionType)
    if not (source and Kit()) then return false end
    CreatePanel()
    view.source = source
    view.sessionType = sessionType == 0 and 0 or 1
    if not frame:IsShown() then
        frame:ClearAllPoints()
        local saved = ns.db and ns.db.playerPos
        if type(saved) == "table" and type(saved.point) == "string" then
            frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
        else
            frame:SetPoint("CENTER")
        end
    end
    frame:Show()
    frame:Raise()
    Win.SetTab(view.tab or "summary")
    return true
end

function Win.Hide()
    if not frame then return end
    if ns.Breakdown and ns.Breakdown.Unembed then ns.Breakdown.Unembed() end
    frame:Hide()
end
function Win.IsShown() return frame ~= nil and frame:IsShown() end
function Win.Refresh()
    if not Win.IsShown() then return end
    if view.tab == "spells" then
        if ns.Breakdown and ns.Breakdown.Refresh then ns.Breakdown.Refresh() end
    else
        Win.Draw()
    end
end

-- For the harness.
function Win.__frame() return frame end
function Win.__view() return view end
