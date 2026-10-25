-- RocketMeter | MyRunWindow.lua
-- The screen "My run" ("Meu combate"): the player's own report of a key, a raid, a delve or a session in the world,
-- tab by tab as Warcraft Logs shows a report. Opens in place of the spell panel on the player's own row. The data is
-- MyRun.lua; the tables and charts are Report.lua; this file chooses what goes in each tab.
--
-- (!) THE GAME'S SKIN (01/10). The first version was painted by hand, and the user called it: *"os addons que estou
-- criando seguem o padrão de skin blizzard, tem que revisar"*. Every piece is the game's (12.1.0):
--
--   frame     `ButtonFrameTemplate` without the portrait: title, close button, Esc
--   body      its `Inset`, each tab a page that scrolls (`ScrollFrameTemplate`)
--   tabs      `PanelTabButtonTemplate` under the frame, `PanelTemplates_SetNumTabs` / `_SetTab`
--   boxes     `InsetFrameTemplate3` for the title band of each table
--   combos    `WowStyle1DropdownTemplate`
--   text      the game's font objects and colour objects; the game's glyphs (tombstone, avoidable, deadly)
--
-- (!) WARCRAFT LOGS, TAB BY TAB (20/10). The user: *"eu falei para deixar igual ao warcraft logs, mas tu manteve
-- algumas abas e ficou informação meio duplicada e não tá igual ao warcraftlogs, nenhum pouco igual, essa janela ela
-- precisa ser igual ao warcraftlogs e entendo se não tiver algumas informações por não ter como mesmo, mas pesquisa
-- tudo, analisa todos os detalhes e faça"*, and *"vai ter que aumentar a janela para caber as abas"*. Their report
-- (`2LMPXTqKQ4xBRGvF`, fight 16) was read tab by tab on 20/10, and these are its twelve tabs in its order, with the
-- History of this addon at the end:
--
--   Summary       the chart per second (damage done, damage taken, healing done), the stats, the gear, and four
--                 boxes: damage done, healing done and damage taken by ability, and the deaths
--   Damage Done   Name, Amount, Casts, Avg Cast, Hits, Avg Hit, Crit %, Uptime %, DPS, and a Total line
--   Damage Taken  Name, Amount, Hits, Avg Hit, DTPS (who cast it and the game's avoidable and deadly glyphs)
--   Healing       the heals and the shields in one list: Name, Amount, Casts, Avg Cast, Hits, Avg Hit, Crit %,
--                 Overheal, HPS
--   Deaths        Time, Killing Blow, the window, the last three hits, the damage taken; a click opens the blows
--   Interrupts    the total, what was stopped and the interrupts cast
--   Dispels       the total and what was dispelled
--   Casts         the casts over time; Name, Amount, CPM
--
-- (!) THREAT, BUFFS, DEBUFFS AND RESOURCES ARE NOT HERE (20/10): MEASURED EMPTY. For a few hours they were, fed by a
-- sample a second in combat of the player's health, power, the enemies tanked and each aura, kept only when readable.
-- The user's raid of 20/10 17:58 (Abismo Peçonhento, Death Knight, 6 fights, 347 samples): health 0 readable of 347,
-- power 0 of 347, threat 0 of 347, auras readable only in the very first sample of each fight (the instant the fight
-- begins) and 27,440 refused -- "Auras cannot be accessed when secret while tainted". Those first readings even drew
-- false one-second spans. The user: *"documenta as que não mostrou nada, se tiver aba vazia pode remover"*. Hits,
-- crits, overheal, uptime and the per-second curve exist only in the game's combat log file, which no addon can read,
-- and the tabs say so.
--
-- (!) DEVELOPMENT SHOWS WHAT THE PACKAGE SHOWS (20/10). For a few hours the development copy drew those columns from
-- the combat log (tools/meter_timeline.py -> Timeline.lua). The user: *"deixa igual ao pacote publicado, se não vai me
-- gerar confusão"*. The tool stays, out of the addon, to check the numbers against Warcraft Logs.
--
-- What was here before and is not on the site went away (20/10): the four tiles, "What cost", the cooldowns "used /
-- fitted", the rhythm and the Character tab (the stats and the gear are in the Summary, as on the site).
local ADDON, ns = ...
local L = ns.L

local Win = {}
ns.MyRunWindow = Win

-- (20/10) 900 -> 1000. Thirteen tabs were measured at 958 px with the game's font, and in game they ran past the window
-- (the user's print, 18:17): a tab is never narrower than its two side pieces, about 70 px ("Cura" is 70, not 43).
-- Measured on the print, the nine that stay take about 760 px.
local WIDTH = 1000
local PAD = 12                   -- inside the inset
local TOP_BAND = 60              -- title bar + the row of the combos
local BODY_HEIGHT = 560
local TITLE = 16
local ITEM_HEIGHT = 30
local BAR_HEIGHT = 20
local ROW_HEIGHT = 18
local GAP = 10
local INNER = WIDTH - 16 - PAD * 2          -- the inset is 8 from each side of the frame
local MAX_HISTORY = 8
local CHART_HEIGHT = 130
local BOX_ROWS = 10              -- the Summary's four boxes
-- (!) THE BARS ARE THE METER'S OWN, FLAT (01/10). The user: *"a skin do gráfico das outras abas poderia ser igual ao
-- da aba magias, sem degradê"*. Every bar takes the texture, the brightness and the row background from `ns.Skin`.
local FLAT = "Interface\\Buttons\\WHITE8X8"
local function BarTexture()
    return (ns.Skin and ns.Skin.barTexture) or FLAT
end
local function BarBrightness()
    return (ns.Skin and tonumber(ns.Skin.barBrightness)) or 0.7
end

local TABS = { "summary", "damage", "taken", "healing", "deaths", "interrupts", "dispels", "casts", "history" }
-- Labels looked up here, by name, so the locale test sees them used.
local TAB_LABEL = { summary = L["Summary"], damage = L["Damage done"], taken = L["Damage taken"], healing = L["Healing"],
                    deaths = L["Deaths"], interrupts = L["Interrupts"], dispels = L["Dispels"], casts = L["Casts"],
                    history = L["History"] }

-- The colours of the Summary's three lines, as the site draws them (blue, red, green); the legend names each.
local LINE = { damage = { 0.38, 0.62, 1.0 }, taken = { 0.95, 0.3, 0.3 }, healing = { 0.35, 0.85, 0.45 } }

local frame
local view = { scope = "all", run = nil, tab = "summary", death = nil }

local function Fmt(v) return ns.Data.FormatAmount(v) or "-" end
local function Clock(s) return ns.MyRun.Clock(s) end

local function Colour(fs, colour)
    if colour and colour.GetRGB then fs:SetTextColor(colour:GetRGB()) end
end

local function SpellIcon(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellTexture) then return 134400 end
    local ok, tex = pcall(C_Spell.GetSpellTexture, spellID)
    return ok and tex or 134400
end

---The icon of an item, from the game; the question mark only when the item is not known.
local function ItemIcon(itemID)
    if itemID and C_Item and C_Item.GetItemIconByID then
        local ok, tex = pcall(C_Item.GetItemIconByID, itemID)
        if ok and tex then return tex end
    end
    return 134400
end

local function SpellNameOf(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellName) then return "" end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    return ok and type(name) == "string" and name or ("#" .. tostring(spellID))
end

---The run on screen: the one in memory, or a saved one chosen in the combo.
local function RunShown()
    return view.run or ns.MyRun.Current()
end

---The colour of a bar: the class colour at the skin's brightness, as the spell panel paints it.
local function ClassRGB(r)
    local cr, cg, cb = ns.ClassColor(r and r.class or nil)
    local k = BarBrightness()
    return (cr or 1) * k, (cg or 1) * k, (cb or 1) * k
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------
local function Text(parent, template, justify)
    -- (14/10) Secondary text: the white font in the game's light grey (LIGHTGRAY_FONT_COLOR, 0.6),
    -- never the disabled grey (0.5) on the stone and the art (the rule of 13/10: ~3.7:1 against
    -- ~5.1:1). Asked for "GameFontDisableSmall", this gives that.
    local grey = template == "GameFontDisableSmall"
    local fs = parent:CreateFontString(nil, "OVERLAY", grey and "GameFontHighlightSmall" or template or "GameFontHighlightSmall")
    if grey then Colour(fs, LIGHTGRAY_FONT_COLOR) end
    fs:SetJustifyH(justify or "LEFT")
    fs:SetWordWrap(false)
    return fs
end

local function Block(parent, title)
    local b = CreateFrame("Frame", nil, parent)
    b.title = Text(b, "GameFontNormalSmall")
    b.title:SetPoint("TOPLEFT", 2, -1)
    b.title:SetText(title)
    return b
end

---A box of the game with a big number, its label and two lines at the right.
local function Tile(parent)
    local t = CreateFrame("Frame", nil, parent, "InsetFrameTemplate3")
    t.number = Text(t, "GameFontHighlightLarge")
    t.number:SetPoint("TOPLEFT", 10, -7)
    t.label = Text(t, "GameFontNormalSmall")
    t.label:SetPoint("BOTTOMLEFT", 10, 7)
    t.side1 = Text(t, "GameFontDisableSmall", "RIGHT")
    t.side1:SetPoint("TOPRIGHT", -10, -9)
    t.side2 = Text(t, "GameFontDisableSmall", "RIGHT")
    t.side2:SetPoint("TOPRIGHT", -10, -23)
    return t
end

---One line of "what cost": the glyph or the spell's icon, the title, the detail, a number.
local function ProblemRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ITEM_HEIGHT)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 2, 0)
    r.title = Text(r, "GameFontHighlightSmall")
    r.title:SetPoint("TOPLEFT", 30, -3)
    r.detail = Text(r, "GameFontDisableSmall")
    r.detail:SetPoint("BOTTOMLEFT", 30, 3)
    r.number = Text(r, "GameFontHighlightSmall", "RIGHT")
    r.number:SetPoint("RIGHT", -4, 0)
    r.title:SetPoint("RIGHT", r.number, "LEFT", -8, 0)
    r.detail:SetPoint("RIGHT", r.number, "LEFT", -8, 0)
    return r
end

---A bar with an icon, a name and a value: cooldowns, damage taken, casts, rhythm.
local function BarRow(parent, withIcon)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(BAR_HEIGHT)
    local left = 0
    if withIcon ~= false then
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
        r.icon:SetPoint("LEFT")
        left = BAR_HEIGHT + 2
    end
    -- The row's own dark ground, as in the spell panel: the empty part of a bar is not a hole.
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetPoint("TOPLEFT", left, 0)
    r.bg:SetPoint("BOTTOMRIGHT")
    local bg = (ns.Skin and ns.Skin.panelRowBackground) or { 0, 0, 0, 0.25 }
    r.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", left, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetStatusBarTexture(BarTexture())
    r.bar:SetMinMaxValues(0, 1)
    r.text = CreateFrame("Frame", nil, r)
    r.text:SetAllPoints()
    r.text:SetFrameLevel(r.bar:GetFrameLevel() + 2)
    r.name = Text(r.text, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", left + 6, 0)
    r.value = Text(r.text, "GameFontHighlightSmall", "RIGHT")
    r.value:SetPoint("RIGHT", -6, 0)
    r.mark = r.text:CreateTexture(nil, "OVERLAY")
    r.mark:SetSize(12, 12)
    r.mark:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
    r.mark:Hide()
    r.name:SetPoint("RIGHT", r.mark, "LEFT", -4, 0)
    return r
end

local function Dropdown(parent, width)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetSize(width, 25)
    return dd
end

---Textures of a pool, reused: the timeline draws a different number of marks every time.
local function Pool(parent, layer)
    local pool = { used = 0, list = {} }
    function pool.Reset() for _, t in ipairs(pool.list) do t:Hide() end pool.used = 0 end
    function pool.Get()
        pool.used = pool.used + 1
        local t = pool.list[pool.used]
        if not t then
            t = parent:CreateTexture(nil, layer or "ARTWORK")
            pool.list[pool.used] = t
        end
        t:ClearAllPoints()
        t:SetVertexColor(1, 1, 1, 1)
        t:Show()
        return t
    end
    return pool
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------
local HISTORY_COLS = { 300, 70, 90, 80, 70, 70, 80, 80 }
local function BuildHistory(page)
    page.title = Text(page, "GameFontNormalSmall")
    page.title:SetPoint("TOPLEFT", 2, -1)
    page.rows = {}
    for i = 0, MAX_HISTORY do
        local r = CreateFrame("Button", nil, page)
        r:SetHeight(ROW_HEIGHT + 4)
        r:SetPoint("TOPLEFT", 0, -(TITLE + i * (ROW_HEIGHT + 6)))
        r:SetPoint("RIGHT")
        r.cells = {}
        local x = 4
        for c = 1, #HISTORY_COLS do
            local cell = Text(r, i == 0 and "GameFontDisableSmall" or "GameFontHighlightSmall", c == 1 and "LEFT" or "RIGHT")
            cell:SetPoint("LEFT", x, 0)
            cell:SetWidth(HISTORY_COLS[c] - 6)
            r.cells[c] = cell
            x = x + HISTORY_COLS[c]
        end
        if i > 0 then
            r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            r:SetScript("OnClick", function(self)
                if self.run then view.run = self.run; view.scope = "all"; view.death = nil; Win.SetTab("summary") end
            end)
        end
        page.rows[i] = r
    end
    page.note = Text(page, "GameFontDisableSmall")
    page.note:SetPoint("BOTTOMLEFT", 4, 0)
    frame.history = page
end

local function CreatePanel()
    if frame then return frame end

    frame = CreateFrame("Frame", ADDON .. "MyRun", UIParent, "ButtonFrameTemplate")
    frame:SetWidth(WIDTH)
    ns.DarkBody(frame, 1, frame.Bg)       -- (25/10) the dark body, as every Rocket window (Core.lua: "escuro em tudo")
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    -- The screen stays where it was put: saved on drop, used on every open. Esc closes it.
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db and type(point) == "string" then ns.db.myRunPos = { point = point, relPoint = relPoint, x = x, y = y } end
    end)
    frame:Hide()
    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetTitle(L["My run"])
    tinsert(UISpecialFrames, frame:GetName())
    frame:SetScript("OnHide", function()
        if ns.Breakdown and ns.Breakdown.Unembed then ns.Breakdown.Unembed() end
    end)

    -- The band above the inset: who and what at the left, the two combos at the right (the site's report and fight).
    frame.context = Text(frame, "GameFontHighlightSmall")
    frame.context:SetPoint("TOPLEFT", 14, -36)
    frame.fightCombo = Dropdown(frame, 190)
    frame.fightCombo:SetPoint("TOPRIGHT", -12, -30)
    frame.runCombo = Dropdown(frame, 290)
    frame.runCombo:SetPoint("RIGHT", frame.fightCombo, "LEFT", -6, 0)
    frame.context:SetPoint("RIGHT", frame.runCombo, "LEFT", -10, 0)
    frame.runCombo:SetupMenu(function(_, root)
        root:CreateRadio(L["This run"], function() return view.run == nil end,
            function() view.run = nil; view.scope = "all"; view.death = nil; Win.Draw() end, nil)
        for i, saved in ipairs(ns.MyRun.History()) do
            local label = (saved.date or "") .. " · " .. (saved.name or "?") .. (saved.level and (" +" .. saved.level) or "")
            root:CreateRadio(label, function() return view.run == saved end,
                function() view.run = saved; view.scope = "all"; view.death = nil; Win.Draw() end, i)
        end
    end)
    frame.fightCombo:SetupMenu(function(_, root)
        for _, s in ipairs(ns.MyRun.Scopes(RunShown())) do
            root:CreateRadio(s.label, function() return view.scope == s.key end,
                function() view.scope = s.key; view.death = nil; Win.Draw() end, s.key)
        end
    end)

    -- The body: the game's inset, and one page per tab inside it; every page but the History scrolls.
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
        if key ~= "history" then ns.Report.Page(page, INNER) end
    end
    BuildHistory(frame.pages.history)

    frame:SetHeight(TOP_BAND + PAD + BODY_HEIGHT + PAD + ns.DONATE_ROW + 6)
    ns.DonateFooter(frame)

    -- The tabs, under the frame, as in the game's own windows.
    frame.tabs = {}
    for i, key in ipairs(TABS) do
        local tab = CreateFrame("Button", frame:GetName() .. "Tab" .. i, frame, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(TAB_LABEL[key])
        tab:SetScript("OnClick", function() Win.SetTab(key) end)
        if i == 1 then tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2) end
        PanelTemplates_TabResize(tab, 0)
        frame.tabs[i] = tab
        frame["tab" .. key:sub(1, 1):upper() .. key:sub(2)] = tab
    end
    -- `parentArray="Tabs"` in the template fills `frame.Tabs` in the game; the functions below
    -- find the tabs there, or by the global name `<frame>Tab<i>` given above.
    PanelTemplates_SetNumTabs(frame, #TABS)
    return frame
end

---Which tab is on.
function Win.SetTab(tab)
    if not frame then return end
    view.tab = tab
    for i, key in ipairs(TABS) do
        frame.pages[key]:SetShown(key == tab)
        if key == tab then PanelTemplates_SetTab(frame, i) end
    end
    local scoped = tab ~= "history"
    frame.fightCombo:SetShown(scoped)
    frame.runCombo:SetShown(scoped)
    local page = frame.pages[tab]
    if page and page.scroll and page.scroll.SetVerticalScroll then page.scroll:SetVerticalScroll(0) end
    Win.Draw()
end

--------------------------------------------------------------------------------
-- What a scope covers
--------------------------------------------------------------------------------
---The fights of a scope (the run's own list), as MyRun counts them.
local function FightsOf(r, scope)
    local out = {}
    if not r then return out end
    local fights = r.fights or {}
    if type(scope) == "number" then
        if fights[scope] then out[1] = fights[scope] end
    elseif scope == "current" then
        out[1] = r.open or fights[#fights]
    else
        for _, f in ipairs(fights) do
            if scope ~= "trash" or not f.boss then out[#out + 1] = f end
        end
        if r.open and (scope ~= "trash" or not r.open.boss) then out[#out + 1] = r.open end
    end
    return out
end

local function Now(r)
    return r == ns.MyRun.Current() and r and not r.finished and r.startedAt and (GetTime() - r.startedAt) or nil
end

---The seconds of the run the charts span: the whole run, or the one fight of the scope.
local function Range(r, scope)
    if not r then return 0, 1 end
    if type(scope) == "number" or scope == "current" then
        local f = FightsOf(r, scope)[1]
        if f then return f.s, math.max(f.s + 1, f.e or Now(r) or (f.s + 1)) end
    end
    local fights = r.fights or {}
    local last = fights[#fights]
    return 0, math.max(1, r.elapsed or Now(r) or (last and (last.e or last.s)) or 1)
end

local function InFights(t, fights, grace)
    grace = grace or 0
    for _, f in ipairs(fights) do
        if t >= f.s - grace and t <= (f.e or math.huge) then return true end
    end
    return false
end

---One point per fight (MyRun.FightRates): the meter's rate of `key` over the span of each reading.
local function ByFight(r, key)
    local out = {}
    if not r then return out end
    local rates = ns.MyRun.FightRates(r, nil, key)
    for _, f in ipairs(rates) do
        if f.rate and f.e then out[#out + 1] = { f.s, f.e, f.rate } end
    end
    return out
end

local function DeathMarks(r)
    local out = {}
    for _, d in ipairs(r and r.deaths or {}) do out[#out + 1] = { d.t, atlas = "deathrecap-icon-tombstone" } end
    return out
end

--------------------------------------------------------------------------------
-- The rows of the tables
--------------------------------------------------------------------------------
local function SpellName(id)
    if not (C_Spell and C_Spell.GetSpellName) or type(id) ~= "number" then return nil end
    local ok, name = pcall(C_Spell.GetSpellName, id)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

---The casts behind a line of the meter: by id, or by NAME when the cast and what lands are two ids with one name.
local function CastMatcher(own)
    local byName = {}
    for id, n in pairs(own and own.bySpell or {}) do
        local name = SpellName(id)
        if name then byName[name] = (byName[name] or 0) + n end
    end
    return function(spellID)
        local name = SpellName(spellID)
        if name and byName[name] then return byName[name] end
        return own and own.bySpell and own.bySpell[spellID] or nil
    end
end

local function Pct(v) return v and format("%.1f%%", v) or nil end
local function Num0(v) return v and tostring(math.floor(v + 0.5)) or nil end

---The amounts of one kind (damage, healing) as rows: share, casts, per cast, per second.
local function AmountRows(list, own, seconds)
    local casts = CastMatcher(own)
    local rows, total = {}, 0
    for _, sp in ipairs(list or {}) do total = total + (sp.amount or 0) end
    for _, sp in ipairs(list or {}) do
        local n = casts(sp.spellID)
        local row = { spellID = sp.spellID, amount = sp.amount, bar = sp.amount, share = total > 0 and sp.amount / total * 100 or nil,
                      casts = n, perCast = n and n > 0 and sp.amount / n or nil,
                      rate = sp.perSecond or (seconds and seconds > 0 and sp.amount / seconds) or nil, name = sp.name,
                      atlas = sp.atlas }
        rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
    return rows, total
end

---The columns of a table of amounts.
local function AmountColumns(rateLabel, withCasts)
    local cols = { { key = "name", label = L["Name"] }, { key = "amount", label = L["Amount"], width = 250 } }
    if withCasts then
        cols[#cols + 1] = { key = "casts", label = L["Casts"], width = 72, fmt = function(v) return v and tostring(v) or "-" end }
        cols[#cols + 1] = { key = "perCast", label = L["Avg cast"], width = 84, grey = true }
    end
    cols[#cols + 1] = { key = "rate", label = rateLabel, width = 74 }
    return cols
end

---Why a table is empty, said once: in combat, a fight the meter did not keep, a run saved before the spells.
local function MissingNote(m, scope, hasList)
    if not m then
        if type(scope) == "number" then return L["This fight's numbers were not kept."] end
        return L["In combat the meter's numbers are hidden; they come back when it ends."]
    end
    if not hasList then return L["This run was saved before the spells were kept with it."] end
    return nil
end

local function ClassColour(r) return { ClassRGB(r) } end

--------------------------------------------------------------------------------
-- The tabs
--------------------------------------------------------------------------------
local function Ctx(r, scope)
    local own = ns.MyRun.Own(scope, r)
    local m = ns.MyRun.Metrics(scope, r)
    local from, to = Range(r, scope)
    return { r = r, scope = scope, own = own, m = m, from = from, to = to, seconds = own.combatSeconds or 0,
             fights = FightsOf(r, scope) }
end

---The chart of one kind: one point per fight (the game gives no curve).
local function KindChart(page, c, key, label)
    ns.Report.Chart(page, { height = CHART_HEIGHT, from = c.from, to = c.to, note = L["one point per fight: the game gives no curve"],
        marks = DeathMarks(c.r),
        series = { { label = label, colour = ClassColour(c.r), points = ByFight(c.r, key), fill = true } } })
end

local function DrawSummary(page, c)
    local Report = ns.Report
    Report.Begin(page)
    -- 1. The chart: damage done, damage taken, healing done.
    local series = {}
    for _, k in ipairs({ { "damage", L["Damage done"] }, { "taken", L["Damage taken"] }, { "healing", L["Healing"] } }) do
        series[#series + 1] = { label = k[2], colour = LINE[k[1]], points = ByFight(c.r, k[1]) }
    end
    Report.Chart(page, { height = CHART_HEIGHT, from = c.from, to = c.to, series = series, marks = DeathMarks(c.r),
        note = L["one point per fight: the game gives no curve"] })

    -- 2. The stats, one line, as the site writes them.
    local s = c.r and c.r.stats
    Report.Band(page, L["Attributes"])
    if s then
        local PRIMARY = { [1] = "SPELL_STAT1_NAME", [2] = "SPELL_STAT2_NAME", [4] = "SPELL_STAT4_NAME" }
        local parts = {}
        local function Add(global, value)
            if value then parts[#parts + 1] = format("%s: |cffffffff%s|r", _G[global] or global, BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value)) end
        end
        Add(PRIMARY[s.primaryStat or 4] or "SPELL_STAT4_NAME", s.primary)
        Add("SPELL_STAT3_NAME", s.stamina)
        Add("STAT_CRITICAL_STRIKE", s.crit)
        Add("STAT_HASTE", s.haste)
        Add("STAT_MASTERY", s.mastery)
        Add("STAT_VERSATILITY", s.versatility)
        if (s.avoidance or 0) > 0 then Add("STAT_AVOIDANCE", s.avoidance) end
        if (s.leech or 0) > 0 then Add("STAT_LIFESTEAL", s.leech) end
        if (s.speed or 0) > 0 then Add("STAT_SPEED", s.speed) end
        Report.Note(page, table.concat(parts, "    "))
    else
        Report.Note(page, L["This run was saved before the sheet and the gear were kept with it."])
    end

    -- 3. The gear: item level, slot, name, the gems and the enchant.
    local gear = c.r and c.r.gear
    if gear then
        Report.Band(page, L["Gear"], nil, nil, s and s.ilvl and format("%s: %.1f", _G.STAT_AVERAGE_ITEM_LEVEL or "Item Level", s.ilvl) or nil)
        local rows = {}
        for _, item in ipairs(gear) do
            local itemID = tonumber(item.link:match("item:(%d+)"))
            local colour, name = item.link:match("|c(%x+)"), item.link:match("%[(.-)%]")
            rows[#rows + 1] = { icon = ItemIcon(itemID), name = name and (colour and ("|c" .. colour .. name .. "|r") or name) or "",
                link = item.link, ilvl = item.ilvl, slot = _G[Win.SLOT_NAME[item.slot] or ""] or "", extras = Win.ItemExtras(item.link) }
        end
        Report.Table(page, { rows = rows, columns = {
            { key = "name", label = L["Name"] },
            { key = "slot", label = L["Slot"], width = 110, justify = "LEFT", grey = true },
            { key = "ilvl", label = L["Item level"], width = 78, fmt = function(v) return v and tostring(v) or "" end },
            { key = "extras", label = L["Gems and enchants"], width = 330, justify = "LEFT", grey = true },
        } })
        Report.Space(page)
    end

    -- 4. The four boxes, two by two: damage done, healing done; damage taken, deaths.
    local half = (page.width - GAP) / 2
    local m = c.m
    local function Box(x, title, rows, total, rateLabel, noAdvance)
        local y0 = page.y
        Report.Band(page, title, x, half, nil, true)
        page.y = page.y + Report.Geometry.BAND
        local h
        if #rows == 0 then
            h = Report.Note(page, MissingNote(m, c.scope, m and m.spells ~= nil) or L["Nothing in this scope."], x, half, true)
        else
            h = Report.Table(page, { x = x, width = half, rows = rows, maxRows = BOX_ROWS, top = rows[1].bar,
                colour = ClassColour(c.r), columns = {
                    { key = "name", label = L["Name"] }, { key = "amount", label = L["Amount"], width = 220 },
                    { key = "rate", label = rateLabel, width = 66 } } }, true)
        end
        local used = Report.Geometry.BAND + h
        page.y = y0
        return used
    end
    local dmg = AmountRows(m and m.spells and m.spells.damage, c.own, c.seconds)
    local heal = AmountRows(m and m.spells and Win.HealingList(m), c.own, c.seconds)
    local h1 = Box(0, L["Damage done by ability"], dmg, nil, L["DPS"])
    local h2 = Box(half + GAP, L["Healing done by ability"], heal, nil, L["HPS"])
    page.y = page.y + math.max(h1, h2) + GAP
    local taken = Win.TakenRows(c)
    local h3 = Box(0, L["Damage taken by ability"], taken, nil, L["DTPS"])
    -- the deaths' box: name, killing blow, time
    local y0 = page.y
    Report.Band(page, L["Deaths"], half + GAP, half, nil, true)
    page.y = page.y + Report.Geometry.BAND
    local deathRows = {}
    for _, d in ipairs(c.own.deaths) do
        deathRows[#deathRows + 1] = { name = c.r and c.r.player or "", atlas = "deathrecap-icon-tombstone",
            blow = (d.killer or L["cause unknown"]), time = Clock(d.t) }
    end
    local h4
    if #deathRows == 0 then
        h4 = Report.Note(page, L["No death in this scope."], half + GAP, half, true)
    else
        h4 = Report.Table(page, { x = half + GAP, width = half, rows = deathRows, maxRows = BOX_ROWS, columns = {
            { key = "name", label = L["Name"] }, { key = "blow", label = L["Killing blow"], width = 200, justify = "LEFT" },
            { key = "time", label = L["Time"], width = 60 } } }, true)
    end
    page.y = y0 + math.max(h3, Report.Geometry.BAND + h4) + GAP
    Report.Finish(page)
end

---The heals and the shields in one list, as the site lists them (a shield's line beside the heal of the same spell).
function Win.HealingList(m)
    local out = {}
    for _, sp in ipairs(m.spells.healing or {}) do out[#out + 1] = sp end
    for _, sp in ipairs(m.spells.absorbs or {}) do out[#out + 1] = sp end
    return out
end

---The damage taken by spell: who cast it, the game's glyphs, the amount and per second.
function Win.TakenRows(c)
    local list = c.m and c.m.takenSpells or {}
    local rows, total = {}, 0
    for _, sp in ipairs(list) do total = total + (sp.amount or 0) end
    for _, sp in ipairs(list) do
        local glyph = sp.deadly and CreateAtlasMarkup("icons_16x16_deadly", 12, 12)
            or sp.avoidable and CreateAtlasMarkup("damagemeters-avoidabledamage-icon", 12, 12) or nil
        local row = { spellID = sp.spellID, amount = sp.amount, bar = sp.amount, share = total > 0 and sp.amount / total * 100 or nil,
            rate = c.seconds > 0 and sp.amount / c.seconds or nil,
            name = SpellNameOf(sp.spellID) .. (sp.creature and (" · " .. sp.creature) or "") .. (glyph and (" " .. glyph) or "") }
        rows[#rows + 1] = row
    end
    return rows, total
end

local function TotalRow(total, seconds, extra)
    local row = { name = L["Total"], amount = total, rate = seconds > 0 and total / seconds or nil }
    for k, v in pairs(extra or {}) do row[k] = v end
    return row
end

local function DrawDamage(page, c)
    local Report = ns.Report
    Report.Begin(page)
    KindChart(page, c, "damage", L["Damage done"])
    local list = c.m and c.m.spells and c.m.spells.damage
    local rows, total = AmountRows(list, c.own, c.seconds)
    if #rows == 0 then
        Report.Note(page, MissingNote(c.m, c.scope, list ~= nil) or L["Nothing in this scope."])
    else
        Report.Table(page, { rows = rows, total = TotalRow(total, c.seconds), top = rows[1].bar, colour = ClassColour(c.r),
            columns = AmountColumns(L["DPS"], true) })
        Report.Space(page)
        Report.Note(page, L["Hits, critical hits and uptime exist only in the game's combat log file, which an addon cannot read."])
    end
    Report.Finish(page)
end

local function DrawTaken(page, c)
    local Report = ns.Report
    Report.Begin(page)
    KindChart(page, c, "taken", L["Damage taken"])
    local rows, total = Win.TakenRows(c)
    if #rows == 0 then
        Report.Note(page, MissingNote(c.m, c.scope, true) or L["Nothing taken."])
    else
        local avoidable = c.m and c.m.avoidable and c.m.avoidable.total or 0
        local whole = c.m and c.m.taken and c.m.taken.total or total
        Report.Band(page, L["Damage taken"], nil, nil, whole > 0 and format(L["%d%% avoidable"], math.floor(avoidable / whole * 100 + 0.5)) or nil)
        Report.Table(page, { rows = rows, total = TotalRow(total, c.seconds), top = rows[1].bar, colour = ClassColour(c.r),
            columns = AmountColumns(L["DTPS"], false) })
    end
    Report.Finish(page)
end

local function DrawHealing(page, c)
    local Report = ns.Report
    Report.Begin(page)
    KindChart(page, c, "healing", L["Healing"])
    local list = c.m and c.m.spells and Win.HealingList(c.m)
    local rows, total = AmountRows(list, c.own, c.seconds)
    if #rows == 0 then
        Report.Note(page, MissingNote(c.m, c.scope, list ~= nil) or L["Nothing in this scope."])
    else
        Report.Table(page, { rows = rows, total = TotalRow(total, c.seconds), top = rows[1].bar, colour = ClassColour(c.r),
            columns = AmountColumns(L["HPS"], true) })
        Report.Space(page)
        Report.Note(page, L["The heals and the shields in one list, as Warcraft Logs shows them; a shield is the game's \"Absorbs\"."])
    end
    Report.Finish(page)
end

---(21/10) The defensives ready at a death, as icons for the death's line: what Warcraft Logs does not say.
local READY_ICONS = 4
local function ReadyIcons(list)
    if not list then return "" end
    if #list == 0 then return L["none"] end
    local parts = {}
    for i, sp in ipairs(list) do
        if i > READY_ICONS then parts[#parts + 1] = "+" .. (#list - READY_ICONS); break end
        local icon = SpellIcon(sp.spellID)
        parts[#parts + 1] = icon and ("|T" .. icon .. ":16:16|t") or (sp.name or "?")
    end
    return table.concat(parts, " ")
end

local function DrawDeaths(page, c)
    local Report = ns.Report
    Report.Begin(page)
    local list = c.own.deaths
    if not view.death or not list[view.death] then view.death = list[1] and 1 or nil end
    local rows = {}
    for i, d in ipairs(list) do
        local sum = ns.MyRun.DeathSummary(d)
        local ready = ns.MyRun.ReadyAtDeath(d, c.r)
        rows[#rows + 1] = { index = i, name = Clock(d.t) .. "  " .. (c.r and c.r.player or ""),
            spellID = d.killerSpell, atlas = not d.killerSpell and "deathrecap-icon-tombstone" or nil,
            blow = (d.killer or L["cause unknown"]) .. (d.killerSource and (" · " .. d.killerSource) or ""),
            over = sum.blows > 0 and (sum.oneShot and L["one shot"] or format("%.1fs", sum.seconds or 0)) or "",
            last = table.concat(sum.last, ", "), taken = sum.total > 0 and sum.total or nil,
            ready = ReadyIcons(ready), readyCount = ready and #ready or nil }
    end
    if #rows == 0 then
        Report.Note(page, L["No death in this scope."])
        Report.Finish(page)
        return
    end
    Report.Table(page, { rows = rows, selected = rows[view.death], onClick = function(row) view.death = row.index; Win.Draw() end,
        columns = {
            { key = "name", label = L["Time"] .. " · " .. L["Name"] },
            { key = "blow", label = L["Killing blow"], width = 230, justify = "LEFT" },
            { key = "over", label = L["Window"], width = 70 },
            { key = "last", label = L["Last three hits"], width = 210, justify = "LEFT", grey = true },
            -- (21/10) beyond Warcraft Logs: what the player still had
            { key = "ready", label = L["Defensives ready"], width = 112, justify = "LEFT",
              colour = function(_, row) return row.readyCount and row.readyCount > 0 and NORMAL_FONT_COLOR or LIGHTGRAY_FONT_COLOR end },
            { key = "taken", label = L["Damage taken"], width = 90 } } })
    Report.Space(page)
    -- the blows of the death clicked, the killing one first
    local d = list[view.death]
    local events = d and d.events or {}
    Report.Band(page, format("%s — %s", L["Blow by blow"], Clock(d.t)), nil, nil,
        d.maxHealth and format(L["%s of life"], Fmt(d.maxHealth)) or nil)
    -- (21/10) the defensives that were ready, by name: the line says it in icons
    local ready = ns.MyRun.ReadyAtDeath(d, c.r)
    if ready then
        local names = {}
        for _, sp in ipairs(ready) do names[#names + 1] = sp.name end
        Report.Note(page, #names > 0 and format(L["Defensives ready and not pressed: %s."], table.concat(names, ", "))
            or L["No defensive was ready: all of them had been used."])
    end
    if #events == 0 then
        Report.Note(page, L["The game kept no blow of this death."])
    else
        local blows = {}
        for i, ev in ipairs(events) do
            local share = d.maxHealth and d.maxHealth > 0 and ev.hp and math.max(0, math.min(1, ev.hp / d.maxHealth)) or nil
            local glyph = ev.deadly and CreateAtlasMarkup("icons_16x16_deadly", 12, 12)
                or ev.avoidable and CreateAtlasMarkup("damagemeters-avoidabledamage-icon", 12, 12) or nil
            blows[#blows + 1] = { spellID = ev.spellId, name = (ev.spell or L["cause unknown"]) .. (glyph and (" " .. glyph) or ""),
                nameColour = i == 1 and RED_FONT_COLOR or NORMAL_FONT_COLOR,
                before = ev.before and format("-%.1fs", ev.before) or "", source = ev.source or "",
                amount = ev.amount, absorbed = ev.absorbed and ev.absorbed > 0 and ev.absorbed or nil,
                hp = share and format("%d%%", math.floor(share * 100 + 0.5)) or "" }
        end
        Report.Table(page, { rows = blows, columns = {
            { key = "name", label = L["Ability"] },
            { key = "source", label = L["Source"], width = 220, justify = "LEFT", grey = true },
            { key = "before", label = L["Before death"], width = 90, grey = true },
            { key = "amount", label = L["Amount"], width = 80, fmt = function(v) return v and Fmt(v) or "-" end },
            { key = "absorbed", label = L["absorbed"], width = 80, grey = true },
            { key = "hp", label = L["Health"], width = 70 } } })
    end
    Report.Finish(page)
end

---Counts by spell (the meter's interrupts or dispels) as rows.
local function CountRows(list)
    local rows, total = {}, 0
    for _, sp in ipairs(list or {}) do total = total + (sp.amount or 0) end
    for _, sp in ipairs(list or {}) do
        rows[#rows + 1] = { spellID = sp.spellID, count = sp.amount, share = total > 0 and sp.amount / total * 100 or nil, bar = sp.amount }
    end
    return rows, total
end

local function DrawInterrupts(page, c)
    local Report = ns.Report
    Report.Begin(page)
    local total = c.m and c.m.interrupts and c.m.interrupts.total
    Report.Band(page, L["Total interrupts"], nil, nil, total and tostring(total) or "-")
    local rows = CountRows(c.m and c.m.spells and c.m.spells.interrupts)
    if #rows > 0 then
        Report.Band(page, L["Interrupted (the game's count)"])
        Report.Table(page, { rows = rows, top = rows[1].bar, colour = ClassColour(c.r), columns = {
            { key = "name", label = L["Name"] },
            { key = "count", label = L["Count"], width = 70, fmt = tostring },
            { key = "share", label = L["%"], width = 60, fmt = Pct } } })
        Report.Space(page)
    end
    -- the interrupts cast (the player's own casts), against what the game credited
    local cast, castRows = 0, {}
    for id, n in pairs(c.own.bySpell or {}) do
        if type(ns.InterruptSpells) == "table" and ns.InterruptSpells[id] then
            cast = cast + n
            castRows[#castRows + 1] = { spellID = id, casts = n }
        end
    end
    if #castRows > 0 then
        Report.Band(page, L["Interrupts cast"], nil, nil, total and cast > total and format(L["%d cast cut nothing"], cast - total) or nil)
        Report.Table(page, { rows = castRows, columns = { { key = "name", label = L["Name"] },
            { key = "casts", label = L["Casts"], width = 76, fmt = tostring } } })
    end
    if not total and #castRows == 0 then Report.Note(page, MissingNote(c.m, c.scope, true) or L["No interrupt in this scope."]) end
    Report.Finish(page)
end

local function DrawDispels(page, c)
    local Report = ns.Report
    Report.Begin(page)
    local total = c.m and c.m.dispels and c.m.dispels.total
    Report.Band(page, L["Total dispels"], nil, nil, total and tostring(total) or "-")
    local rows = CountRows(c.m and c.m.spells and c.m.spells.dispels)
    if #rows > 0 then
        Report.Table(page, { rows = rows, top = rows[1].bar, colour = ClassColour(c.r), columns = {
            { key = "name", label = L["Name"] },
            { key = "count", label = L["Count"], width = 70, fmt = tostring },
            { key = "share", label = L["%"], width = 60, fmt = Pct } } })
    elseif not total or total == 0 then
        Report.Note(page, MissingNote(c.m, c.scope, true) or L["No dispel in this scope."])
    end
    Report.Finish(page)
end

local function DrawCasts(page, c)
    local Report = ns.Report
    Report.Begin(page)
    -- the chart: how many casts in each slice of the time, as the site's bars of time spent casting
    local times = ns.MyRun.CastTimes(c.r)
    local width = math.floor(page.width / 3)
    local step = math.max(1, (c.to - c.from) / width)
    local counts, order = {}, {}
    for _, t in ipairs(times) do
        if t[1] >= c.from and t[1] <= c.to and InFights(t[1], c.fights, 3) then
            local b = math.floor((t[1] - c.from) / step)
            if not counts[b] then counts[b] = 0; order[#order + 1] = b end
            counts[b] = counts[b] + 1
        end
    end
    local points = {}
    for _, b in ipairs(order) do points[#points + 1] = { c.from + b * step, c.from + (b + 1) * step, counts[b] / step * 60 } end
    if #points > 0 then
        Report.Chart(page, { height = CHART_HEIGHT, from = c.from, to = c.to, marks = DeathMarks(c.r),
            series = { { label = L["Casts per minute"], colour = ClassColour(c.r), points = points, fill = true, bars = true } } })
    end
    local rows, total = {}, c.own.casts or 0
    local minutes = c.seconds > 0 and c.seconds / 60 or nil
    -- (21/10) beyond Warcraft Logs: for a cooldown of 45 s or more, how many times it was ready in these fights
    -- ("Fitted") and the share of those it was pressed ("Usage") -- only for what is pressed as often as it comes
    -- back; in colour only a damage dealer's burst (MyRun.Judged); a defensive or what is pressed on demand, blank
    local cdOf = {}
    for _, cd in ipairs(c.own.cooldowns or {}) do
        cdOf[cd.spellID] = cd
        if cd.base then cdOf[cd.base] = cdOf[cd.base] or cd end
    end
    for id, n in pairs(c.own.bySpell or {}) do
        local cd = cdOf[id]
        local open = cd and not cd.situational and not cd.defensive and cd.fitted > 0
        rows[#rows + 1] = { spellID = id, amount = n, bar = n, share = total > 0 and n / total * 100 or nil,
                            perMinute = minutes and n / minutes or nil,
                            fitted = open and cd.fitted or nil,
                            usage = open and math.min(100, cd.used / cd.fitted * 100) or nil,
                            judged = cd and cd.judged or nil }
    end
    table.sort(rows, function(a, b) if a.amount == b.amount then return a.spellID < b.spellID end return a.amount > b.amount end)
    if #rows == 0 then
        Report.Note(page, L["No cast in this scope."])
    else
        Report.Table(page, { rows = rows, top = rows[1].bar, colour = ClassColour(c.r),
            total = { name = L["Total"], amount = total, perMinute = minutes and total / minutes or nil },
            columns = {
                { key = "name", label = L["Name"] },
                { key = "amount", label = L["Amount"], width = 200, fmt = function(v) return v and tostring(v) or "" end },
                { key = "perMinute", label = L["CPM"], width = 70, fmt = function(v) return v and format("%.1f", v) or "-" end },
                { key = "fitted", label = L["Fitted"], width = 56, fmt = function(v) return v and tostring(v) or "" end, grey = true },
                { key = "usage", label = L["Usage"], width = 92, fmt = function(v) return v and format("%d%%", math.floor(v + 0.5)) or "" end,
                  colour = function(v, row)
                      if not (v and row.judged) then return nil end
                      return v < 50 and RED_FONT_COLOR or v < 70 and NORMAL_FONT_COLOR or GREEN_FONT_COLOR end } } })
        Report.Note(page, L["Fitted: how many times a cooldown of 45 s or more was ready in these fights. Usage: the share of those it was pressed; in colour only a damage dealer's burst, defensives and what is pressed on demand are not judged."])
        -- what the game reported as a cast and the player did not press, apart, so nothing vanishes
        local other = {}
        for id, n in pairs(c.own.notPressed or {}) do other[#other + 1] = { spellID = id, casts = n } end
        if #other > 0 then
            table.sort(other, function(a, b) if a.casts == b.casts then return a.spellID < b.spellID end return a.casts > b.casts end)
            Report.Space(page)
            Report.Band(page, L["Not counted: automatic effects, the world and delves"])
            Report.Table(page, { rows = other, maxRows = 12, columns = { { key = "name", label = L["Name"] },
                { key = "casts", label = L["Casts"], width = 76, fmt = tostring } } })
        end
    end
    Report.Finish(page)
end

local function DrawHistory()
    local b = frame.history
    local list = ns.MyRun.History()
    b.title:SetText(format(L["History — the last %d"], MAX_HISTORY))
    local labels = { L["Run"], L["Role"], L["Per second"], L["Avoidable"], L["Interr."], L["Deaths"], L["Cooldowns"], L["Casts/min"] }
    for c, cell in ipairs(b.rows[0].cells) do cell:SetText(labels[c]) end
    local ROLE_LABEL = { DAMAGER = L["DAMAGER"], TANK = L["TANK"], HEALER = L["HEALER"] }
    for i = 1, MAX_HISTORY do
        local row = b.rows[i]
        local saved = list[i]
        row.run = saved
        if not saved then row:Hide() else
            row:Show()
            local m = ns.MyRun.Metrics("all", saved)
            local own = ns.MyRun.Own("all", saved)
            local key = saved.role == "HEALER" and "healing" or (saved.role == "TANK" and "taken" or "damage")
            local share = m and m.taken and m.avoidable and m.taken.total > 0 and math.floor(m.avoidable.total / m.taken.total * 100 + 0.5) or nil
            local used, fitted = 0, 0
            -- only the cooldowns that are judged (MyRun.Judged)
            for _, cd in ipairs(own.cooldowns) do
                if cd.judged then used, fitted = used + cd.used, fitted + cd.fitted end
            end
            local cells = row.cells
            local onde = ns.MyRun.Where(saved)
            cells[1]:SetText((saved.date or "") .. " · " .. (onde ~= "" and onde or "?"))
            cells[2]:SetText(ROLE_LABEL[saved.role] or ROLE_LABEL.DAMAGER)
            cells[3]:SetText(m and m[key] and Fmt(m[key].perSecond) or "-")
            cells[4]:SetText(share and (share .. "%") or "-")
            cells[5]:SetText(m and m.interrupts and tostring(m.interrupts.total) or "-")
            cells[6]:SetText(tostring(#(saved.deaths or {})))
            cells[7]:SetText(fitted > 0 and format("%d%%", math.floor(used / fitted * 100 + 0.5)) or "-")
            cells[8]:SetText(own.perMinute and format("%d", math.floor(own.perMinute + 0.5)) or "-")
        end
    end
    b.note:SetText(#list == 0 and L["No run saved yet."] or L["Click a line to open it."])
end

-- The slot names of the character sheet (the game's globals), by inventory slot.
Win.SLOT_NAME = { [1] = "HEADSLOT", [2] = "NECKSLOT", [3] = "SHOULDERSLOT", [15] = "BACKSLOT", [5] = "CHESTSLOT",
    [9] = "WRISTSLOT", [10] = "HANDSSLOT", [6] = "WAISTSLOT", [7] = "LEGSSLOT", [8] = "FEETSLOT", [11] = "FINGER0SLOT",
    [12] = "FINGER1SLOT", [13] = "TRINKET0SLOT", [14] = "TRINKET1SLOT", [16] = "MAINHANDSLOT", [17] = "SECONDARYHANDSLOT" }

---What the game's tooltip of an item says of its enchant, and the names of its gems: "Enchant · Gem, Gem".
function Win.ItemExtras(link)
    local parts = {}
    if C_TooltipInfo and C_TooltipInfo.GetHyperlink and Enum.TooltipDataLineType then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        for _, line in ipairs(ok and type(data) == "table" and data.lines or {}) do
            if line.type == Enum.TooltipDataLineType.ItemEnchantmentPermanent and type(line.leftText) == "string" then
                parts[#parts + 1] = line.leftText
            end
        end
    end
    local gems = {}
    for i = 1, (C_Item and C_Item.GetItemGem) and 3 or 0 do
        local ok, name = pcall(C_Item.GetItemGem, link, i)
        if ok and type(name) == "string" and name ~= "" then gems[#gems + 1] = name end
    end
    if #gems > 0 then parts[#parts + 1] = table.concat(gems, ", ") end
    return table.concat(parts, " · ")
end

local DRAW = {
    summary = DrawSummary, damage = DrawDamage, taken = DrawTaken, healing = DrawHealing,
    deaths = DrawDeaths, interrupts = DrawInterrupts, dispels = DrawDispels, casts = DrawCasts,
}

function Win.Draw()
    if not frame then return end
    local r = RunShown()
    local valid = false
    for _, s in ipairs(ns.MyRun.Scopes(r)) do if s.key == view.scope then valid = true end end
    if not valid then view.scope = "all" end
    local scope = view.scope

    if r then
        local parts = {}
        if r.player then parts[#parts + 1] = r.player end
        if r.spec then parts[#parts + 1] = r.spec end
        local where = ns.MyRun.Where(r)
        if where ~= "" then parts[#parts + 1] = where end
        if r.elapsed then parts[#parts + 1] = Clock(r.elapsed) end
        frame.context:SetText(table.concat(parts, " · "))
    else
        frame.context:SetText(L["Nothing recorded yet: it starts at your next fight."])
    end
    frame.fightCombo:GenerateMenu()
    frame.runCombo:GenerateMenu()

    if view.tab == "history" then DrawHistory(); return end
    local draw = DRAW[view.tab]
    if draw then draw(frame.pages[view.tab], Ctx(r, scope)) end
end

---Opens the screen where it was left; the first time, in the middle.
function Win.Show()
    CreatePanel()
    view.run = nil
    frame:ClearAllPoints()
    local saved = ns.db and ns.db.myRunPos
    if type(saved) == "table" and type(saved.point) == "string" then
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    frame:Raise()
    local known = false
    for _, key in ipairs(TABS) do if key == view.tab then known = true end end
    Win.SetTab(known and view.tab or "summary")
end

---Opens the screen on a SAVED run (a click on the player's row of the scoreboard of that key).
function Win.ShowRun(saved)
    Win.Show()
    if type(saved) ~= "table" then return end
    view.run, view.scope, view.death = saved, "all", nil
    Win.Draw()
end

function Win.Hide()
    if not frame then return end
    frame:Hide()
end
function Win.IsShown() return frame ~= nil and frame:IsShown() end
function Win.Refresh()
    if not Win.IsShown() then return end
    Win.Draw()
end
function Win.Toggle() if Win.IsShown() then Win.Hide() else Win.Show() end end

-- The pieces this window is made of, for the screen of the OTHER players (PlayerWindow.lua) and Report.lua: the
-- same boxes, bars, dropdown and colours, so the windows cannot drift apart.
Win.Kit = {
    Text = Text, Block = Block, Tile = Tile, BarRow = BarRow, Dropdown = Dropdown, Colour = Colour,
    SpellIcon = SpellIcon, SpellNameOf = SpellNameOf, Fmt = Fmt, Clock = Clock,
    BarTexture = BarTexture, BarBrightness = BarBrightness,
}

-- For the harness.
Win.TABS = TABS
function Win.__frame() return frame end
function Win.__view() return view end
function Win.__setView(scope, r) view.scope = scope; view.run = r end
