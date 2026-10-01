-- RocketMeter | MyRunWindow.lua
-- The screen "My run" ("Meu combate"): what the player did, what cost, the cooldowns, the damage
-- taken, the timeline, the casts, the deaths and the history. Opens in place of the spell panel
-- on the player's own row. The data is MyRun.lua; this file only draws.
--
-- (!) THE GAME'S SKIN (01/10). The first version was painted by hand like the meter's spell
-- panel, and the user called it: *"os addons que estou criando seguem o padrão de skin blizzard,
-- tem que revisar"*. This is a screen to READ, like Rocket Mount's window, not a combat
-- overlay, so every piece is the game's (12.1.0, Blizzard_SharedXML and Blizzard_UIPanelTemplates):
--
--   frame     `ButtonFrameTemplate` without the portrait: title, close button, Esc
--   body      its `Inset`
--   tabs      `PanelTabButtonTemplate` under the frame, `PanelTemplates_SetNumTabs` / `_SetTab`
--   tiles     `InsetFrameTemplate3`
--   combos    `WowStyle1DropdownTemplate`
--   bars      the game's status bar texture, in the class colour (the colour of "me")
--   text      the game's font objects, and the colour OBJECTS: gold for titles, white for
--             values, grey for detail, red for what is not met (`RED_FONT_COLOR`)
--   marks     the game's own glyphs: tombstone, avoidable, deadly, boss
--
-- NO COLOUR CARRIES A MEANING OF OURS: the first version had a red/yellow/grey edge for how bad
-- a problem was, a red bar for "avoidable", a blue one for rhythm. The order of the list says
-- how bad, and the game's glyph says avoidable.
--
-- WHAT CAME FROM WARCRAFT LOGS (01/10, the user's two reports, read tab by tab), as far as the
-- game lets an addon rebuild it for the local player: the chart by fight (their per-second
-- curve has no source here: one point per fight), one line per cooldown with every use (their
-- casts timeline), the band of time casting with its holes, the casts tab with count, share and
-- casts per minute, and in the deaths "in N s" / "one shot", the last three blows and the
-- damage of the window.
local ADDON, ns = ...
local L = ns.L

local Win = {}
ns.MyRunWindow = Win

local WIDTH = 900
local PAD = 12                   -- inside the inset
local TOP_BAND = 60              -- title bar + the row of the combos
local TILE_HEIGHT = 46
local TITLE = 16
local ITEM_HEIGHT = 30
local BAR_HEIGHT = 20
local ROW_HEIGHT = 18
local GAP = 10
local LEFT_WIDTH = 520
local INNER = WIDTH - 16 - PAD * 2          -- the inset is 8 from each side of the frame
local RIGHT_WIDTH = INNER - LEFT_WIDTH - GAP
local MAX_PROBLEMS = 6
local MAX_COOLDOWNS = 6
local MAX_TAKEN = 5
local MAX_HISTORY = 8
local MAX_CD_LINES = 5
local CD_LINE = 16
local CHART_HEIGHT = 40
local GUTTER = 20                -- left of the timeline: the icon of each cooldown line
local MAX_CAST_ROWS = 16         -- per column, two columns
local MAX_DEATH_ROWS = 8
local DEATH_ROW = 46
local MAX_EVENT_ROWS = 10
local EVENT_ROW = 30
local DEATH_LIST_WIDTH = 400
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local TABS = { "summary", "casts", "deaths", "spells", "history" }
local TAB_LABEL = { summary = "Summary", casts = "Casts", deaths = "Deaths", spells = "Spells", history = "History" }

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

local function SpellNameOf(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellName) then return "" end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    return ok and type(name) == "string" and name or ("#" .. tostring(spellID))
end

---The run on screen: the one in memory, or a saved one chosen in the combo.
local function RunShown()
    return view.run or ns.MyRun.Current()
end

local function ClassRGB(r)
    return ns.ClassColor(r and r.class or nil)
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------
local function Text(parent, template, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
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
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", left, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetStatusBarTexture(BAR_TEXTURE)
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
-- The frame
--------------------------------------------------------------------------------
local function BuildSummary(page)
    local y = 0
    frame.tiles = {}
    local tileWidth = (INNER - 6 * 3) / 4
    for i = 1, 4 do
        local t = Tile(page)
        t:SetSize(tileWidth, TILE_HEIGHT)
        t:SetPoint("TOPLEFT", (i - 1) * (tileWidth + 6), -y)
        frame.tiles[i] = t
    end
    y = y + TILE_HEIGHT + GAP

    -- Left: what cost, and the timeline.
    local left = y
    local p = Block(page, L["What cost"])
    p:SetPoint("TOPLEFT", 0, -left)
    p:SetSize(LEFT_WIDTH, TITLE + MAX_PROBLEMS * (ITEM_HEIGHT + 2) + 14)
    p.rows = {}
    for i = 1, MAX_PROBLEMS do
        local r = ProblemRow(p)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (ITEM_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        r:EnableMouse(true)
        r:SetScript("OnMouseUp", function(self)
            local problem = self.problem
            if problem and problem.kind == "death" then view.death = problem.index; Win.SetTab("deaths") end
        end)
        p.rows[i] = r
    end
    p.empty = Text(p, "GameFontDisableSmall")
    p.empty:SetPoint("TOPLEFT", 4, -TITLE)
    p.checked = Text(p, "GameFontDisableSmall")
    p.checked:SetPoint("BOTTOMLEFT", 4, 0)
    p.checked:SetPoint("RIGHT")
    frame.problems = p
    left = left + p:GetHeight() + GAP

    -- The timeline: the chart by fight, the band of time casting, bosses / deaths / potions, and
    -- one line per cooldown. Everything shares the same time axis, GUTTER from the left.
    local tl = Block(page, L["Timeline"])
    local height = TITLE + CHART_HEIGHT + 4 + 8 + 2 + 18 + MAX_CD_LINES * CD_LINE + 14
    tl:SetPoint("TOPLEFT", 0, -left)
    tl:SetSize(LEFT_WIDTH, height)
    tl.width = LEFT_WIDTH - GUTTER
    tl.chartTop = TITLE
    tl.bandTop = TITLE + CHART_HEIGHT + 4
    tl.marksTop = tl.bandTop + 8 + 2
    tl.linesTop = tl.marksTop + 18
    tl.bars = Pool(tl, "ARTWORK")
    tl.segments = Pool(tl, "ARTWORK")
    tl.holes = Pool(tl, "OVERLAY")
    tl.marks = Pool(tl, "OVERLAY")
    tl.uses = Pool(tl, "OVERLAY")
    tl.lineIcons = {}
    for i = 1, MAX_CD_LINES do
        local icon = tl:CreateTexture(nil, "ARTWORK")
        icon:SetSize(CD_LINE - 2, CD_LINE - 2)
        icon:SetPoint("TOPLEFT", 0, -(tl.linesTop + (i - 1) * CD_LINE))
        tl.lineIcons[i] = icon
    end
    tl.start = Text(tl, "GameFontDisableSmall")
    tl.start:SetPoint("BOTTOMLEFT", GUTTER, 0)
    tl.finish = Text(tl, "GameFontDisableSmall", "RIGHT")
    tl.finish:SetPoint("BOTTOMRIGHT", 0, 0)
    tl.note = Text(tl, "GameFontDisableSmall", "RIGHT")
    tl.note:SetPoint("TOPRIGHT", 0, -1)
    frame.timeline = tl
    left = left + height

    -- Right: cooldowns, damage taken, rhythm.
    local right = y
    local rx = LEFT_WIDTH + GAP
    local cd = Block(page, L["Cooldowns — used / fitted"])
    cd:SetPoint("TOPLEFT", rx, -right)
    cd:SetSize(RIGHT_WIDTH, TITLE + MAX_COOLDOWNS * (BAR_HEIGHT + 2) + 14)
    cd.rows = {}
    for i = 1, MAX_COOLDOWNS do
        local r = BarRow(cd)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        cd.rows[i] = r
    end
    cd.note = Text(cd, "GameFontDisableSmall")
    cd.note:SetPoint("BOTTOMLEFT", 4, 0)
    cd.note:SetPoint("RIGHT")
    frame.cooldowns = cd
    right = right + cd:GetHeight() + GAP

    local tk = Block(page, L["Damage taken"])
    tk:SetPoint("TOPLEFT", rx, -right)
    tk:SetSize(RIGHT_WIDTH, TITLE + MAX_TAKEN * (BAR_HEIGHT + 2) + 14)
    tk.rows = {}
    for i = 1, MAX_TAKEN do
        local r = BarRow(tk)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        tk.rows[i] = r
    end
    tk.note = Text(tk, "GameFontDisableSmall")
    tk.note:SetPoint("BOTTOMLEFT", 4, 0)
    tk.note:SetPoint("RIGHT")
    frame.taken = tk
    right = right + tk:GetHeight() + GAP

    local rh = Block(page, L["Rhythm"])
    rh:SetPoint("TOPLEFT", rx, -right)
    rh:SetSize(RIGHT_WIDTH, TITLE + 3 * (BAR_HEIGHT + 2))
    rh.rows = {}
    for i = 1, 3 do
        local r = BarRow(rh, false)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        rh.rows[i] = r
    end
    frame.rhythm = rh
    right = right + rh:GetHeight()

    return math.max(left, right)
end

local function BuildCasts(page)
    page.title = Text(page, "GameFontNormalSmall")
    page.title:SetPoint("TOPLEFT", 2, -1)
    page.rows = {}
    local colWidth = (INNER - GAP) / 2
    for i = 1, MAX_CAST_ROWS * 2 do
        local col = i > MAX_CAST_ROWS and 1 or 0
        local line = (i - 1) % MAX_CAST_ROWS
        local r = BarRow(page)
        r:SetPoint("TOPLEFT", col * (colWidth + GAP), -(TITLE + line * (BAR_HEIGHT + 2)))
        r:SetWidth(colWidth)
        page.rows[i] = r
    end
    page.empty = Text(page, "GameFontDisableSmall")
    page.empty:SetPoint("TOPLEFT", 4, -TITLE)
    frame.casts = page
end

local function BuildDeaths(page)
    page.listTitle = Text(page, "GameFontNormalSmall")
    page.listTitle:SetPoint("TOPLEFT", 2, -1)
    page.rows = {}
    for i = 1, MAX_DEATH_ROWS do
        local r = CreateFrame("Button", nil, page)
        r:SetSize(DEATH_LIST_WIDTH, DEATH_ROW)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (DEATH_ROW + 2)))
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        r.selected = r:CreateTexture(nil, "BACKGROUND")
        r.selected:SetAllPoints()
        r.selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        r.selected:SetBlendMode("ADD")
        r.selected:Hide()
        r.when = Text(r, "GameFontDisableSmall", "RIGHT")
        r.when:SetPoint("TOPLEFT", 2, -4)
        r.when:SetWidth(36)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("TOPLEFT", 44, -4)
        r.killer = Text(r, "GameFontHighlightSmall")
        r.killer:SetPoint("TOPLEFT", 74, -3)
        r.killer:SetPoint("RIGHT", -24, 0)
        r.hardest = Text(r, "GameFontHighlightSmall")
        r.hardest:SetPoint("TOPLEFT", 74, -17)
        r.hardest:SetPoint("RIGHT", -24, 0)
        r.window = Text(r, "GameFontDisableSmall")
        r.window:SetPoint("TOPLEFT", 74, -31)
        r.window:SetPoint("RIGHT", -24, 0)
        r.mark = r:CreateTexture(nil, "OVERLAY")
        r.mark:SetSize(14, 14)
        r.mark:SetPoint("TOPRIGHT", -4, -4)
        r:SetScript("OnClick", function(self) view.death = self.index; Win.Draw() end)
        page.rows[i] = r
    end
    page.empty = Text(page, "GameFontDisableSmall")
    page.empty:SetPoint("TOPLEFT", 4, -TITLE)

    local detail = CreateFrame("Frame", nil, page)
    detail:SetPoint("TOPLEFT", DEATH_LIST_WIDTH + GAP, 0)
    detail:SetPoint("BOTTOMRIGHT")
    page.detail = detail
    detail.title = Text(detail, "GameFontNormalSmall")
    detail.title:SetPoint("TOPLEFT", 2, -1)
    detail.sub = Text(detail, "GameFontDisableSmall")
    detail.sub:SetPoint("TOPLEFT", 2, -TITLE)
    detail.rows = {}
    for i = 1, MAX_EVENT_ROWS do
        local r = CreateFrame("Frame", nil, detail)
        r:SetHeight(EVENT_ROW)
        r:SetPoint("TOPLEFT", 0, -(TITLE + 14 + (i - 1) * (EVENT_ROW + 1)))
        r:SetPoint("RIGHT")
        r.before = Text(r, "GameFontDisableSmall", "RIGHT")
        r.before:SetPoint("LEFT", 0, 0)
        r.before:SetWidth(44)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("LEFT", 50, 0)
        r.spell = Text(r, "GameFontNormalSmall")
        r.spell:SetPoint("TOPLEFT", 80, -3)
        r.spell:SetWidth(170)
        r.source = Text(r, "GameFontDisableSmall")
        r.source:SetPoint("BOTTOMLEFT", 80, 3)
        r.source:SetWidth(170)
        r.amount = Text(r, "GameFontHighlightSmall", "RIGHT")
        r.amount:SetPoint("LEFT", 252, 0)
        r.amount:SetWidth(70)
        r.life = CreateFrame("StatusBar", nil, r)
        r.life:SetSize(80, 10)
        r.life:SetPoint("LEFT", 330, 0)
        r.life:SetStatusBarTexture(BAR_TEXTURE)
        r.life:SetMinMaxValues(0, 1)
        -- The green of every health bar of the game.
        r.life:SetStatusBarColor(0, 1, 0)
        r.pct = Text(r, "GameFontDisableSmall", "RIGHT")
        r.pct:SetPoint("LEFT", r.life, "RIGHT", 4, 0)
        r.pct:SetWidth(32)
        r.mark = r:CreateTexture(nil, "OVERLAY")
        r.mark:SetSize(12, 12)
        r.mark:SetPoint("LEFT", r.pct, "RIGHT", 2, 0)
        detail.rows[i] = r
    end
    detail.empty = Text(detail, "GameFontDisableSmall")
    detail.empty:SetPoint("TOPLEFT", 4, -TITLE)
    frame.deaths = page
end

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

    -- The band above the inset: who and what at the left, the two combos at the right.
    frame.context = Text(frame, "GameFontHighlightSmall")
    frame.context:SetPoint("TOPLEFT", 14, -36)
    frame.fightCombo = Dropdown(frame, 170)
    frame.fightCombo:SetPoint("TOPRIGHT", -12, -30)
    frame.runCombo = Dropdown(frame, 270)
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

    -- The body: the game's inset, and one page per tab inside it.
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
    local bodyHeight = BuildSummary(frame.pages.summary)
    BuildCasts(frame.pages.casts)
    BuildDeaths(frame.pages.deaths)
    BuildHistory(frame.pages.history)

    frame:SetHeight(TOP_BAND + PAD + bodyHeight + PAD + ns.DONATE_ROW + 6)
    ns.DonateFooter(frame)

    -- The tabs, under the frame, as in the game's own windows.
    frame.tabs = {}
    for i, key in ipairs(TABS) do
        local tab = CreateFrame("Button", frame:GetName() .. "Tab" .. i, frame, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(L[TAB_LABEL[key]])
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

---Which tab is on. The spell panel is drawn inside the body, in the same place and size.
function Win.SetTab(tab)
    if not frame then return end
    view.tab = tab
    for i, key in ipairs(TABS) do
        frame.pages[key]:SetShown(key == tab)
        if key == tab then PanelTemplates_SetTab(frame, i) end
    end
    local scoped = tab ~= "spells" and tab ~= "history"
    frame.fightCombo:SetShown(scoped)
    frame.runCombo:SetShown(scoped)
    if tab == "spells" then
        if ns.Breakdown and ns.Breakdown.ShowOwn then ns.Breakdown.ShowOwn(nil, frame.pages.spells) end
    else
        if ns.Breakdown and ns.Breakdown.Unembed then ns.Breakdown.Unembed() end
        Win.Draw()
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
local function DrawTiles(r, own, m)
    local tiles = frame.tiles
    local role = r and r.role or "DAMAGER"
    local function Set(t, number, label, s1, s2, bad)
        t.number:SetText(number or "-")
        Colour(t.number, bad and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
        t.label:SetText(label)
        t.side1:SetText(s1 or "")
        t.side2:SetText(s2 or "")
    end
    local function Rank(x) return x and x.rank and format(L["%dº of the group"], x.rank) or "" end
    local function Total(x) return x and (Fmt(x.total) .. " " .. L["in total"]) or L["out of combat only"] end
    if role == "HEALER" then
        Set(tiles[1], m and m.healing and Fmt(m.healing.perSecond), L["Healing per second"], Total(m and m.healing), Rank(m and m.healing))
        Set(tiles[2], m and m.damage and Fmt(m.damage.perSecond), L["Damage per second"], m and Total(m.damage) or "", Rank(m and m.damage))
    elseif role == "TANK" then
        Set(tiles[1], m and m.taken and Fmt(m.taken.perSecond), L["Damage taken per second"], Total(m and m.taken), Rank(m and m.taken))
        Set(tiles[2], m and m.damage and Fmt(m.damage.perSecond), L["Damage per second"], m and Total(m.damage) or "", Rank(m and m.damage))
    else
        Set(tiles[1], m and m.damage and Fmt(m.damage.perSecond), L["Damage per second"], Total(m and m.damage), Rank(m and m.damage))
        local a = m and m.avoidable
        local share = a and m.taken and m.taken.total > 0 and math.floor(a.total / m.taken.total * 100 + 0.5) or nil
        Set(tiles[2], a and Fmt(a.total), L["Avoidable damage taken"], share and format(L["%d%% of what you took"], share) or "", Rank(a), share and share >= 5)
    end
    local i = m and m.interrupts
    local cast = 0
    if ns.InterruptSpells then for id, n in pairs(own.bySpell) do if ns.InterruptSpells[id] then cast = cast + n end end end
    local missed = i and math.max(0, cast - i.total) or nil
    Set(tiles[3], i and tostring(i.total), L["Interrupts"], Rank(i), missed and missed > 0 and format(L["%d cast cut nothing"], missed) or "")
    local deaths = #own.deaths
    local last = own.deaths[deaths]
    Set(tiles[4], tostring(deaths), deaths == 1 and L["Death"] or L["Deaths"],
        last and format(L["at %s"], Clock(last.t)) or "", last and (last.killer or "") or "", deaths > 0)
end

local function DrawProblems(r, scope)
    local list, checked = ns.MyRun.Problems(scope, r and r.role or nil, r)
    local b = frame.problems
    b.title:SetText(format("%s (%s)", L["What cost"], L[r and r.role or "DAMAGER"]))
    for i, row in ipairs(b.rows) do
        local p = list[i]
        row.problem = p
        if not p then row:Hide() else
            row:Show()
            if p.atlas then
                row.icon:SetAtlas(p.atlas)
            elseif p.item then
                row.icon:SetTexture(134400)
            else
                row.icon:SetTexture(SpellIcon(p.spellID))
            end
            row.title:SetText(p.title)
            row.detail:SetText(p.detail or "")
            row.number:SetText(p.number or "")
        end
    end
    b.empty:SetShown(#list == 0)
    b.empty:SetText(L["Nothing found: no death, no avoidable damage worth the name, cooldowns on time."])
    b.checked:SetText(format(L["Looked at: %s."], table.concat(checked, ", ")))
end

local function DrawCooldowns(r, own)
    local b = frame.cooldowns
    local cr, cg, cb = ClassRGB(r)
    for i, row in ipairs(b.rows) do
        local cd = own.cooldowns[i]
        if not cd then row:Hide() else
            row:Show()
            row.icon:SetTexture(SpellIcon(cd.spellID))
            row.name:SetText(cd.name .. (cd.category == "utility" and (" " .. L["(defensive)"]) or ""))
            row.value:SetText(format("%d / %d", cd.used, cd.fitted))
            row.bar:SetMinMaxValues(0, math.max(1, cd.fitted))
            row.bar:SetValue(cd.used)
            row.bar:SetStatusBarColor(cr, cg, cb)
            -- Used less than half of what fitted: the number in the game's red.
            Colour(row.value, (cd.fitted > 0 and cd.used / cd.fitted < 0.5) and RED_FONT_COLOR or HIGHLIGHT_FONT_COLOR)
        end
    end
    b.note:SetText(#own.cooldowns == 0 and L["The game's Cooldown Manager lists no cooldown for this spec."]
        or L["The game's Cooldown Manager list, with the cooldown of each."])
end

local function DrawTaken(r, m, scope)
    local b = frame.taken
    local cr, cg, cb = ClassRGB(r)
    local total = m and m.taken and m.taken.total or 0
    local avoidable = m and m.avoidable and m.avoidable.total or 0
    b.title:SetText(total > 0 and format("%s — %s", L["Damage taken"], Fmt(total)) or L["Damage taken"])
    local list = m and m.takenSpells or {}
    local top = list[1] and list[1].amount or 1
    for i, row in ipairs(b.rows) do
        local sp = list[i]
        if not sp then row:Hide() else
            row:Show()
            row.icon:SetTexture(SpellIcon(sp.spellID))
            row.name:SetText(SpellNameOf(sp.spellID) .. (sp.creature and (" · " .. sp.creature) or ""))
            row.value:SetText(Fmt(sp.amount))
            row.bar:SetMinMaxValues(0, top)
            row.bar:SetValue(sp.amount)
            row.bar:SetStatusBarColor(cr, cg, cb)
            -- Avoidable and deadly are said by the game's own glyphs, not by a colour.
            if sp.deadly then row.mark:SetAtlas("icons_16x16_deadly"); row.mark:Show()
            elseif sp.avoidable then row.mark:SetAtlas("damagemeters-avoidabledamage-icon"); row.mark:Show()
            else row.mark:Hide() end
        end
    end
    if not m then
        b.note:SetText(type(scope) == "number" and L["This fight's numbers were not kept."]
            or L["In combat the meter's numbers are hidden; they come back when it ends."])
    elseif #list == 0 then
        b.note:SetText(L["Nothing taken."])
    else
        b.note:SetText(total > 0 and format(L["%d%% avoidable"], math.floor(avoidable / total * 100 + 0.5)) or "")
    end
end

local function DrawTimeline(r)
    local tl = frame.timeline
    tl.bars.Reset(); tl.segments.Reset(); tl.holes.Reset(); tl.marks.Reset(); tl.uses.Reset()
    for _, icon in ipairs(tl.lineIcons) do icon:Hide() end
    tl.note:SetText("")
    if not r then tl.start:SetText(""); tl.finish:SetText(""); return end

    local fights = {}
    for _, f in ipairs(r.fights) do fights[#fights + 1] = f end
    if r.open then fights[#fights + 1] = r.open end
    local now = r == ns.MyRun.Current() and not r.finished and (GetTime() - r.startedAt) or nil
    local total = r.elapsed or now or (fights[#fights] and (fights[#fights].e or fights[#fights].s)) or 0
    if total <= 0 then total = 1 end
    local width = tl.width
    local function X(t) return GUTTER + math.max(0, math.min(width, t / total * width)) end
    local cr, cg, cb = ClassRGB(r)

    -- 1. The chart by fight: one bar per fight over its own time, as tall as the role's rate.
    local rates, top, key = ns.MyRun.FightRates(r, r.role)
    for _, f in ipairs(rates) do
        if f.rate and top > 0 and f.e then
            local bar = tl.bars.Get()
            bar:SetTexture(BAR_TEXTURE)
            bar:SetVertexColor(cr, cg, cb)
            bar:SetPoint("BOTTOMLEFT", tl, "TOPLEFT", X(f.s), -(tl.chartTop + CHART_HEIGHT))
            bar:SetSize(math.max(2, X(f.e) - X(f.s) - 1), math.max(1, f.rate / top * CHART_HEIGHT))
        end
    end
    local what = key == "healing" and L["Healing per second"] or (key == "taken" and L["Damage taken per second"] or L["Damage per second"])
    tl.note:SetText(top > 0 and format(L["by fight: %s, up to %s"], what, Fmt(top)) or L["by fight: the numbers come at the end of each fight"])

    -- 2. The band of time casting: the fights filled, the gaps without casting as holes.
    for _, f in ipairs(fights) do
        local seg = tl.segments.Get()
        seg:SetTexture(BAR_TEXTURE)
        seg:SetVertexColor(cr, cg, cb)
        seg:SetPoint("TOPLEFT", tl, "TOPLEFT", X(f.s), -tl.bandTop)
        seg:SetSize(math.max(1, X(f.e or total) - X(f.s)), 8)
    end
    for _, g in ipairs(r.gaps or {}) do
        local hole = tl.holes.Get()
        hole:SetColorTexture(0, 0, 0, 0.85)
        hole:SetPoint("TOPLEFT", tl, "TOPLEFT", X(g[1] - g[2]), -tl.bandTop)
        hole:SetSize(math.max(1, X(g[1]) - X(g[1] - g[2])), 8)
    end

    -- 3. Bosses, my deaths, my potions: the game's glyphs on one line.
    local function Mark(t, size, atlas, texture)
        local mk = tl.marks.Get()
        mk:SetSize(size, size)
        mk:SetPoint("CENTER", tl, "TOPLEFT", X(t), -(tl.marksTop + 9))
        if atlas then mk:SetAtlas(atlas) else mk:SetTexture(texture) end
    end
    for _, f in ipairs(fights) do
        if f.boss and f.e then Mark(f.e, 16, "worldquest-icon-boss") end
    end
    for _, d in ipairs(r.deaths or {}) do Mark(d.t, 16, "deathrecap-icon-tombstone") end
    for _, it in ipairs(r.items or {}) do
        if it[2] == "potion" then Mark(it[1], 12, nil, 134400) end
    end

    -- 4. One line per cooldown: its icon at the left, and an icon at every use.
    local uses = ns.MyRun.CooldownUses(r)
    local all = ns.MyRun.Own("all", r).cooldowns
    for i = 1, MAX_CD_LINES do
        local cd = all[i]
        if cd then
            local tex = SpellIcon(cd.spellID)
            tl.lineIcons[i]:SetTexture(tex)
            tl.lineIcons[i]:Show()
            for _, t in ipairs(uses[cd.spellID] or {}) do
                local u = tl.uses.Get()
                u:SetSize(CD_LINE - 4, CD_LINE - 4)
                u:SetTexture(tex)
                u:SetPoint("CENTER", tl, "TOPLEFT", X(t), -(tl.linesTop + (i - 1) * CD_LINE + CD_LINE / 2))
            end
        end
    end
    tl.start:SetText("0:00")
    tl.finish:SetText(Clock(total))
end

local function DrawRhythm(r, own)
    local rows = frame.rhythm.rows
    local cr, cg, cb = ClassRGB(r)
    local seconds = own.combatSeconds
    local active = seconds > 0 and math.max(0, (seconds - own.gaps.total) / seconds) or 0
    local function Set(row, name, value, ratio)
        row:Show()
        row.name:SetText(name)
        row.value:SetText(value)
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(ratio)
        row.bar:SetStatusBarColor(cr, cg, cb)
    end
    Set(rows[1], L["Time casting in combat"], seconds > 0 and format(L["%d%% · %s idle of %s"], math.floor(active * 100 + 0.5), Clock(own.gaps.total), Clock(seconds)) or "-", active)
    Set(rows[2], L["Casts per minute"], own.perMinute and format(L["%d · %d casts"], math.floor(own.perMinute + 0.5), own.casts) or "-", own.perMinute and math.min(1, own.perMinute / 60) or 0)
    Set(rows[3], L["Potion / healthstone"], format("%d / %d", own.potions, own.healthstones), math.min(1, own.potions / math.max(1, own.bossCount)))
end

local function DrawCasts(r, own)
    local page = frame.casts
    local cr, cg, cb = ClassRGB(r)
    local list = ns.MyRun.CastList(own)
    page.title:SetText(format(L["Casts — %d in %s of combat"], own.casts, Clock(own.combatSeconds)))
    local top = list[1] and list[1].count or 1
    for i, row in ipairs(page.rows) do
        local c = list[i]
        if not c then row:Hide() else
            row:Show()
            row.icon:SetTexture(SpellIcon(c.spellID))
            row.name:SetText(SpellNameOf(c.spellID))
            row.value:SetText(c.perMinute and format(L["%d · %d%% · %.1f/min"], c.count, math.floor(c.share + 0.5), c.perMinute)
                or format("%d · %d%%", c.count, math.floor(c.share + 0.5)))
            row.bar:SetMinMaxValues(0, top)
            row.bar:SetValue(c.count)
            row.bar:SetStatusBarColor(cr, cg, cb)
        end
    end
    page.empty:SetShown(#list == 0)
    page.empty:SetText(L["No cast in this scope."])
end

local function DrawDeaths(r, own)
    local d = frame.deaths
    local list = own.deaths
    d.listTitle:SetText(format("%s (%d)", L["My deaths"], #list))
    if not view.death or not list[view.death] then view.death = list[1] and 1 or nil end
    for i, row in ipairs(d.rows) do
        local death = list[i]
        if not death then row:Hide() else
            row:Show()
            row.index = i
            row.when:SetText(Clock(death.t))
            if not death.killerSpell then row.icon:SetAtlas("deathrecap-icon-tombstone")
            else row.icon:SetTexture(SpellIcon(death.killerSpell)) end
            local killer = (death.killer or L["cause unknown"]) .. (death.killerSource and (" · " .. death.killerSource) or "")
            if death.hardest then
                row.killer:SetText(format("%s: %s", L["Killed"], killer))
                row.hardest:SetText(format("%s: %s", L["Hardest"], death.hardest .. (death.hardestSource and (" · " .. death.hardestSource) or "")))
            else
                row.killer:SetText(format("%s: %s", L["Killed and hardest"], killer))
                row.hardest:SetText(ns.MyRun.BossAt(death.t, r) or "")
            end
            -- In how long, with what, and how much: the "Over", "Last Three Hits" and "Damage
            -- Taken" of the deaths table of Warcraft Logs, from the game's recap.
            local sum = ns.MyRun.DeathSummary(death)
            if sum.blows == 0 then
                row.window:SetText("")
            elseif sum.oneShot then
                row.window:SetText(format(L["one shot · %s"], Fmt(sum.total)))
            else
                row.window:SetText(format(L["%s in %.1f s · %s"], Fmt(sum.total), sum.seconds or 0, table.concat(sum.last, ", ")))
            end
            if death.avoidable then row.mark:SetAtlas("damagemeters-avoidabledamage-icon"); row.mark:Show()
            else row.mark:Hide() end
            row.selected:SetShown(view.death == i)
        end
    end
    d.empty:SetShown(#list == 0)
    d.empty:SetText(L["No death in this scope."])

    local det = d.detail
    local death = view.death and list[view.death]
    for _, row in ipairs(det.rows) do row:Hide() end
    if not death then
        det.title:SetText(L["Blow by blow"])
        det.sub:SetText("")
        det.empty:SetShown(#list > 0)
        det.empty:SetText(L["Click a death."])
        return
    end
    det.empty:Hide()
    det.title:SetText(format("%s — %s", L["Blow by blow"], Clock(death.t)))
    local events = death.events or {}
    local covers = events[#events] and events[#events].before
    det.sub:SetText(#events > 0 and format(L["%d blows, the last %s s before the death · %s of life"], #events,
        covers and format("%.1f", covers) or "?", death.maxHealth and Fmt(death.maxHealth) or "?") or L["The game kept no blow of this death."])
    local maxHealth = death.maxHealth
    for i, row in ipairs(det.rows) do
        local ev = events[i]
        if ev then
            row:Show()
            row.before:SetText(ev.before and format("-%.1fs", ev.before) or "")
            row.icon:SetTexture(SpellIcon(ev.spellId))
            row.spell:SetText(ev.spell or L["cause unknown"])
            -- The blow that killed, in the game's red; the others in the gold of a spell's name.
            Colour(row.spell, i == 1 and RED_FONT_COLOR or NORMAL_FONT_COLOR)
            row.source:SetText(ev.source or "")
            local amount = ev.amount and Fmt(ev.amount) or "-"
            if ev.absorbed and ev.absorbed > 0 then amount = amount .. format(" (%s %s)", Fmt(ev.absorbed), L["absorbed"]) end
            row.amount:SetText(amount)
            local share = maxHealth and maxHealth > 0 and ev.hp and math.max(0, math.min(1, ev.hp / maxHealth)) or nil
            row.life:SetValue(share or 0)
            row.pct:SetText(share and format("%d%%", math.floor(share * 100 + 0.5)) or "")
            if ev.deadly then row.mark:SetAtlas("icons_16x16_deadly"); row.mark:Show()
            elseif ev.avoidable then row.mark:SetAtlas("damagemeters-avoidabledamage-icon"); row.mark:Show()
            else row.mark:Hide() end
        end
    end
end

local function DrawHistory()
    local b = frame.history
    local list = ns.MyRun.History()
    b.title:SetText(format(L["History — the last %d"], MAX_HISTORY))
    local labels = { L["Run"], L["Role"], L["Per second"], L["Avoidable"], L["Interr."], L["Deaths"], L["Cooldowns"], L["Casts/min"] }
    for c, cell in ipairs(b.rows[0].cells) do cell:SetText(labels[c]) end
    for i = 1, MAX_HISTORY do
        local row = b.rows[i]
        local saved = list[i]
        row.run = saved
        if not saved then row:Hide() else
            row:Show()
            local m = saved.metrics
            local own = ns.MyRun.Own("all", saved)
            local key = saved.role == "HEALER" and "healing" or (saved.role == "TANK" and "taken" or "damage")
            local share = m and m.taken and m.avoidable and m.taken.total > 0 and math.floor(m.avoidable.total / m.taken.total * 100 + 0.5) or nil
            local used, fitted = 0, 0
            for _, cd in ipairs(own.cooldowns) do used, fitted = used + cd.used, fitted + cd.fitted end
            local cells = row.cells
            cells[1]:SetText((saved.date or "") .. " · " .. (saved.name or "?") .. (saved.level and (" +" .. saved.level) or ""))
            cells[2]:SetText(L[saved.role or "DAMAGER"])
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

function Win.Draw()
    if not frame or view.tab == "spells" then return end
    local r = RunShown()
    local valid = false
    for _, s in ipairs(ns.MyRun.Scopes(r)) do if s.key == view.scope then valid = true end end
    if not valid then view.scope = "all" end
    local scope = view.scope

    if r then
        local parts = {}
        if r.player then parts[#parts + 1] = r.player end
        if r.spec then parts[#parts + 1] = r.spec end
        local where = (r.name or "") .. (r.level and (" +" .. r.level) or "")
        if where ~= "" then parts[#parts + 1] = where end
        if r.elapsed then parts[#parts + 1] = Clock(r.elapsed) end
        frame.context:SetText(table.concat(parts, " · "))
    else
        frame.context:SetText(L["No run recorded yet: start a key or a raid."])
    end
    frame.fightCombo:GenerateMenu()
    frame.runCombo:GenerateMenu()

    if view.tab == "history" then DrawHistory(); return end
    local own = ns.MyRun.Own(scope, r)
    if view.tab == "deaths" then DrawDeaths(r, own); return end
    if view.tab == "casts" then DrawCasts(r, own); return end

    local m = ns.MyRun.Metrics(scope, r)
    DrawTiles(r, own, m)
    DrawProblems(r, scope)
    DrawCooldowns(r, own)
    DrawTaken(r, m, scope)
    DrawTimeline(r)
    DrawRhythm(r, own)
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
    Win.SetTab(view.tab or "summary")
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
function Win.Toggle() if Win.IsShown() then Win.Hide() else Win.Show() end end

-- For the harness.
function Win.__frame() return frame end
function Win.__view() return view end
function Win.__setView(scope, r) view.scope = scope; view.run = r end
