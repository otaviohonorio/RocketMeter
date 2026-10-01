-- RocketMeter | MyRunWindow.lua
-- The screen "Minha corrida": what the player did, what cost, the cooldowns, the damage taken,
-- the timeline and the history. Opens in place of the spell panel on the player's own row.
--
-- The preview it was built from: prints-analisados/PREVIA Minha corrida (…).png (30/09).
-- The data is MyRun.lua; this file only draws. Same skin as the spell panel (Breakdown.lua):
-- the header art of the game's meter, the game's fonts, the class colour on the bars.
local ADDON, ns = ...
local L = ns.L

local Win = {}
ns.MyRunWindow = Win

local WIDTH = 880
local SIDE = 12
local HEADER_HEIGHT = 25
local TAB_ROW = 24
local TILE_HEIGHT = 46
local TITLE = 16
local ITEM_HEIGHT = 30
local BAR_HEIGHT = 22
local ROW_HEIGHT = 16
local GAP = 8
local LEFT_WIDTH = 520
local RIGHT_WIDTH = WIDTH - SIDE * 3 - LEFT_WIDTH
local MAX_PROBLEMS = 6
local MAX_COOLDOWNS = 6
local MAX_TAKEN = 5
local MAX_HISTORY = 8
local TIMELINE_HEIGHT = 76
local MAX_DEATH_ROWS = 10
local DEATH_ROW = 34
local MAX_EVENT_ROWS = 10
local EVENT_ROW = 30
local DEATH_LIST_WIDTH = 380

local frame
local view = { scope = "all", run = nil, cooldown = nil, tab = "summary" }   -- run = nil: the one in memory

local function Skin() return ns.Skin end
local function Fmt(v) return ns.Data.FormatAmount(v) or "-" end
local function Clock(s) return ns.MyRun.Clock(s) end

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

---A tile with a big number, its label and two lines at the right.
local function Tile(parent)
    local t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    t:SetBackdropColor(0, 0, 0, 0.35)
    t:SetBackdropBorderColor(0.16, 0.16, 0.19, 1)
    t.number = Text(t, "GameFontHighlightLarge")
    t.number:SetPoint("TOPLEFT", 10, -6)
    t.label = Text(t, "GameFontNormalSmall")
    t.label:SetPoint("BOTTOMLEFT", 10, 6)
    t.side1 = Text(t, "GameFontDisableSmall", "RIGHT")
    t.side1:SetPoint("TOPRIGHT", -10, -8)
    t.side2 = Text(t, "GameFontDisableSmall", "RIGHT")
    t.side2:SetPoint("TOPRIGHT", -10, -22)
    return t
end

---One line of "what cost": icon, title, detail, number at the right, a coloured edge by severity.
local function ProblemRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ITEM_HEIGHT)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.3)
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetPoint("TOPLEFT")
    r.edge:SetPoint("BOTTOMLEFT")
    r.edge:SetWidth(3)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(22, 22)
    r.icon:SetPoint("LEFT", 8, 0)
    r.title = Text(r, "GameFontHighlightSmall")
    r.title:SetPoint("TOPLEFT", 36, -3)
    r.detail = Text(r, "GameFontDisableSmall")
    r.detail:SetPoint("BOTTOMLEFT", 36, 3)
    r.number = Text(r, "GameFontHighlightSmall", "RIGHT")
    r.number:SetPoint("RIGHT", -8, 0)
    r.title:SetPoint("RIGHT", r.number, "LEFT", -8, 0)
    r.detail:SetPoint("RIGHT", r.number, "LEFT", -8, 0)
    return r
end

---A bar with an icon, a name and a value: the cooldowns and the damage taken.
local function BarRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(BAR_HEIGHT)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(0, 0, 0, 0.3)
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(BAR_HEIGHT, BAR_HEIGHT)
    r.icon:SetPoint("LEFT")
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetPoint("TOPLEFT", BAR_HEIGHT + 2, 0)
    r.bar:SetPoint("BOTTOMRIGHT")
    r.bar:SetStatusBarTexture(Skin().barTexture)
    r.bar:SetMinMaxValues(0, 1)
    r.text = CreateFrame("Frame", nil, r)
    r.text:SetAllPoints()
    r.text:SetFrameLevel(r.bar:GetFrameLevel() + 2)
    r.name = Text(r.text, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", BAR_HEIGHT + 8, 0)
    r.value = Text(r.text, "GameFontHighlightSmall", "RIGHT")
    r.value:SetPoint("RIGHT", -6, 0)
    r.name:SetPoint("RIGHT", r.value, "LEFT", -6, 0)
    r.mark = r.text:CreateTexture(nil, "OVERLAY")
    r.mark:SetSize(12, 12)
    r.mark:SetPoint("RIGHT", r.value, "LEFT", -4, 0)
    r.mark:Hide()
    return r
end

local function PlainRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(ROW_HEIGHT)
    r.cells = {}
    return r
end

--------------------------------------------------------------------------------
-- The panel
--------------------------------------------------------------------------------
local function Dropdown(parent, width)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetSize(width, 22)
    return dd
end

local function CreatePanel()
    if frame then return frame end
    local skin = Skin()

    frame = CreateFrame("Frame", ADDON .. "MyRun", UIParent, "BackdropTemplate")
    frame:SetWidth(WIDTH)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    -- (!) THE SCREEN STAYS WHERE IT WAS PUT (01/10): the user, *"falta muita usabilidade"*. The
    -- position is saved on drop and used on every open; Esc closes it, as the game's own.
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if ns.db and type(point) == "string" then ns.db.myRunPos = { point = point, relPoint = relPoint, x = x, y = y } end
    end)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    frame:SetBackdropColor(0.03, 0.03, 0.04, skin.panelAlpha)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()
    if UISpecialFrames and tinsert then tinsert(UISpecialFrames, frame:GetName()) end

    -- Header: the same art as the meter's.
    local header = CreateFrame("Frame", nil, frame)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(HEADER_HEIGHT)
    header.bg = header:CreateTexture(nil, "BACKGROUND")
    header.bg:SetAllPoints()
    ns.ApplyHeaderArt(header.bg)
    frame.title = Text(header, "GameFontNormal")
    frame.title:SetPoint("LEFT", 10, 0)
    frame.title:SetText(L["My run"])
    frame.context = Text(header, "GameFontHighlightSmall", "RIGHT")
    frame.context:SetPoint("RIGHT", -26, 0)
    frame.close = CreateFrame("Button", nil, header)
    frame.close:SetSize(14, 14)
    frame.close:SetPoint("RIGHT", -5, 0)
    frame.close:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    local closeTexture = frame.close:GetNormalTexture()
    if closeTexture then
        if closeTexture.SetAtlas then closeTexture:SetAtlas("common-icon-redx", false) end
        if closeTexture.SetDesaturated then closeTexture:SetDesaturated(true) end
        closeTexture:SetVertexColor(0.78, 0.73, 0.58)
    end
    frame.close:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    frame.close:SetScript("OnClick", function() frame:Hide() end)

    -- Tabs: this summary, or the spell panel of the same row.
    local y = HEADER_HEIGHT + 6
    frame.tabSummary = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.tabSummary:SetSize(80, 22)
    frame.tabSummary:SetPoint("TOPLEFT", SIDE, -y)
    frame.tabSummary:SetText(L["Summary"])
    frame.tabSummary:SetScript("OnClick", function() Win.SetTab("summary") end)
    frame.tabDeaths = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.tabDeaths:SetSize(80, 22)
    frame.tabDeaths:SetPoint("LEFT", frame.tabSummary, "RIGHT", 4, 0)
    frame.tabDeaths:SetText(L["Deaths"])
    frame.tabDeaths:SetScript("OnClick", function() Win.SetTab("deaths") end)
    frame.tabSpells = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.tabSpells:SetSize(80, 22)
    frame.tabSpells:SetPoint("LEFT", frame.tabDeaths, "RIGHT", 4, 0)
    frame.tabSpells:SetText(L["Spells"])
    frame.tabSpells:SetScript("OnClick", function() Win.SetTab("spells") end)

    -- The combos: which run, which fight.
    frame.fightCombo = Dropdown(frame, 170)
    frame.fightCombo:SetPoint("TOPRIGHT", -SIDE, -y)
    frame.runCombo = Dropdown(frame, 260)
    frame.runCombo:SetPoint("RIGHT", frame.fightCombo, "LEFT", -6, 0)
    frame.runCombo:SetupMenu(function(_, root)
        root:CreateRadio(L["This run"], function() return view.run == nil end, function() view.run = nil; view.scope = "all"; Win.Draw() end, nil)
        for i, saved in ipairs(ns.MyRun.History()) do
            local label = (saved.date or "") .. " · " .. (saved.name or "?") .. (saved.level and (" +" .. saved.level) or "")
            root:CreateRadio(label, function() return view.run == saved end, function() view.run = saved; view.scope = "all"; Win.Draw() end, i)
        end
    end)
    frame.fightCombo:SetupMenu(function(_, root)
        for _, s in ipairs(ns.MyRun.Scopes(RunShown())) do
            root:CreateRadio(s.label, function() return view.scope == s.key end, function() view.scope = s.key; Win.Draw() end, s.key)
        end
    end)

    -- Tiles.
    y = y + TAB_ROW + GAP
    frame.tiles = {}
    local tileWidth = (WIDTH - SIDE * 2 - 6 * 3) / 4
    for i = 1, 4 do
        local t = Tile(frame)
        t:SetSize(tileWidth, TILE_HEIGHT)
        t:SetPoint("TOPLEFT", SIDE + (i - 1) * (tileWidth + 6), -y)
        frame.tiles[i] = t
    end
    y = y + TILE_HEIGHT + GAP

    -- Left column: what cost, the timeline, the rhythm.
    local left = y
    frame.problems = Block(frame, L["What cost"])
    frame.problems:SetPoint("TOPLEFT", SIDE, -left)
    frame.problems:SetSize(LEFT_WIDTH, TITLE + MAX_PROBLEMS * (ITEM_HEIGHT + 2) + 14)
    frame.problems.rows = {}
    for i = 1, MAX_PROBLEMS do
        local r = ProblemRow(frame.problems)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (ITEM_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        r:EnableMouse(true)
        r:SetScript("OnMouseUp", function(self)
            local p = self.problem
            if p and p.kind == "death" then view.death = p.index; Win.SetTab("deaths") end
        end)
        frame.problems.rows[i] = r
    end
    frame.problems.empty = Text(frame.problems, "GameFontDisableSmall")
    frame.problems.empty:SetPoint("TOPLEFT", 4, -TITLE)
    frame.problems.checked = Text(frame.problems, "GameFontDisableSmall")
    frame.problems.checked:SetPoint("BOTTOMLEFT", 4, 0)
    left = left + frame.problems:GetHeight() + GAP

    frame.timeline = Block(frame, L["Timeline — my cooldowns, potions and deaths over the run"])
    frame.timeline:SetPoint("TOPLEFT", SIDE, -left)
    frame.timeline:SetSize(LEFT_WIDTH, TITLE + TIMELINE_HEIGHT)
    local tl = frame.timeline
    tl.rail = tl:CreateTexture(nil, "BACKGROUND")
    tl.rail:SetPoint("TOPLEFT", 0, -(TITLE + 34))
    tl.rail:SetSize(LEFT_WIDTH, 6)
    tl.rail:SetColorTexture(0.1, 0.1, 0.12, 1)
    tl.segments, tl.marks = {}, {}
    tl.start = Text(tl, "GameFontDisableSmall")
    tl.start:SetPoint("TOPLEFT", 0, -(TITLE + 52))
    tl.finish = Text(tl, "GameFontDisableSmall", "RIGHT")
    tl.finish:SetPoint("TOPRIGHT", 0, -(TITLE + 52))
    tl.legend = Text(tl, "GameFontDisableSmall")
    tl.legend:SetPoint("TOPLEFT", 0, -(TITLE + 2))
    left = left + tl:GetHeight() + GAP

    frame.rhythm = Block(frame, L["Rhythm"])
    frame.rhythm:SetPoint("TOPLEFT", SIDE, -left)
    frame.rhythm:SetSize(LEFT_WIDTH, TITLE + 3 * (BAR_HEIGHT + 2))
    frame.rhythm.rows = {}
    for i = 1, 3 do
        local r = BarRow(frame.rhythm)
        r.icon:Hide()
        r.bar:SetPoint("TOPLEFT", 0, 0)
        r.name:SetPoint("LEFT", 8, 0)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        frame.rhythm.rows[i] = r
    end
    left = left + frame.rhythm:GetHeight() + GAP

    -- Right column: cooldowns, damage taken, history.
    local right = y
    local rx = SIDE * 2 + LEFT_WIDTH
    frame.cooldowns = Block(frame, L["Cooldowns — used / fitted"])
    frame.cooldowns:SetPoint("TOPLEFT", rx, -right)
    frame.cooldowns:SetSize(RIGHT_WIDTH, TITLE + MAX_COOLDOWNS * (BAR_HEIGHT + 2) + 14)
    frame.cooldowns.rows = {}
    for i = 1, MAX_COOLDOWNS do
        local r = BarRow(frame.cooldowns)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        r:EnableMouse(true)
        r:SetScript("OnMouseUp", function(self) if self.spellID then view.cooldown = self.spellID; Win.Draw() end end)
        frame.cooldowns.rows[i] = r
    end
    frame.cooldowns.note = Text(frame.cooldowns, "GameFontDisableSmall")
    frame.cooldowns.note:SetPoint("BOTTOMLEFT", 4, 0)
    right = right + frame.cooldowns:GetHeight() + GAP

    frame.taken = Block(frame, L["Damage taken"])
    frame.taken:SetPoint("TOPLEFT", rx, -right)
    frame.taken:SetSize(RIGHT_WIDTH, TITLE + MAX_TAKEN * (BAR_HEIGHT + 2) + 14)
    frame.taken.rows = {}
    for i = 1, MAX_TAKEN do
        local r = BarRow(frame.taken)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (BAR_HEIGHT + 2)))
        r:SetPoint("RIGHT")
        frame.taken.rows[i] = r
    end
    frame.taken.note = Text(frame.taken, "GameFontDisableSmall")
    frame.taken.note:SetPoint("BOTTOMLEFT", 4, 0)
    right = right + frame.taken:GetHeight() + GAP

    frame.history = Block(frame, L["History"])
    frame.history:SetPoint("TOPLEFT", rx, -right)
    frame.history:SetSize(RIGHT_WIDTH, TITLE + (MAX_HISTORY + 1) * ROW_HEIGHT)
    frame.history.rows = {}
    local cols = { 96, 50, 56, 44, 44 }
    for i = 0, MAX_HISTORY do
        local r = PlainRow(frame.history)
        r:SetPoint("TOPLEFT", 0, -(TITLE + i * ROW_HEIGHT))
        r:SetPoint("RIGHT")
        local x = 4
        for c = 1, #cols do
            local cell = Text(r, i == 0 and "GameFontDisableSmall" or "GameFontHighlightSmall", c == 1 and "LEFT" or "RIGHT")
            cell:SetPoint("LEFT", x, 0)
            cell:SetWidth(cols[c] - 4)
            r.cells[c] = cell
            x = x + cols[c]
        end
        frame.history.rows[i] = r
    end
    right = right + frame.history:GetHeight() + GAP

    frame:SetHeight(math.max(left, right) + ns.DONATE_ROW + 4)
    ns.DonateFooter(frame)

    -- The body: everything between the tabs and the footer. The "Spells" tab fills it with the
    -- spell panel, in the same place and size; the summary's blocks hide meanwhile.
    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("TOPLEFT", SIDE, -y)
    frame.body:SetPoint("BOTTOMRIGHT", -SIDE, ns.DONATE_ROW + 4)
    frame.blocks = { frame.problems, frame.timeline, frame.rhythm, frame.cooldowns, frame.taken, frame.history }

    -- (!) THE DEATHS TAB (01/10). The user: *"um quadro onde eu pudesse ver todas as minhas mortes,
    -- para quem, qual skill deu mais dano em mim e qual skill matou (pode ser a mesma ou
    -- diferente)"*. Left, one row per death: when, what killed and from whom, the hardest blow
    -- when it is another, the game's marks. Right, the chosen death blow by blow, with the life
    -- left after each one. Same shape as the preview of 30/09 (PREVIA tela de mortes).
    local deaths = CreateFrame("Frame", nil, frame.body)
    deaths:SetAllPoints()
    deaths:Hide()
    frame.deaths = deaths
    deaths.listTitle = Text(deaths, "GameFontNormalSmall")
    deaths.listTitle:SetPoint("TOPLEFT", 2, -1)
    deaths.rows = {}
    for i = 1, MAX_DEATH_ROWS do
        local r = CreateFrame("Button", nil, deaths)
        r:SetSize(DEATH_LIST_WIDTH, DEATH_ROW)
        r:SetPoint("TOPLEFT", 0, -(TITLE + (i - 1) * (DEATH_ROW + 2)))
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(0, 0, 0, 0.3)
        r:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        r.when = Text(r, "GameFontDisableSmall", "RIGHT")
        r.when:SetPoint("TOPLEFT", 4, -4)
        r.when:SetWidth(36)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(22, 22)
        r.icon:SetPoint("LEFT", 46, 0)
        r.killer = Text(r, "GameFontHighlightSmall")
        r.killer:SetPoint("TOPLEFT", 74, -3)
        r.killer:SetPoint("RIGHT", -30, 0)
        r.hardest = Text(r, "GameFontDisableSmall")
        r.hardest:SetPoint("BOTTOMLEFT", 74, 3)
        r.hardest:SetPoint("RIGHT", -30, 0)
        r.mark = r:CreateTexture(nil, "OVERLAY")
        r.mark:SetSize(14, 14)
        r.mark:SetPoint("RIGHT", -8, 0)
        r:SetScript("OnClick", function(self) view.death = self.index; Win.Draw() end)
        deaths.rows[i] = r
    end
    deaths.empty = Text(deaths, "GameFontDisableSmall")
    deaths.empty:SetPoint("TOPLEFT", 4, -TITLE)

    local detail = CreateFrame("Frame", nil, deaths)
    detail:SetPoint("TOPLEFT", DEATH_LIST_WIDTH + GAP, 0)
    detail:SetPoint("BOTTOMRIGHT")
    deaths.detail = detail
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
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(0, 0, 0, 0.3)
        r.before = Text(r, "GameFontDisableSmall", "RIGHT")
        r.before:SetPoint("LEFT", 4, 0)
        r.before:SetWidth(44)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(24, 24)
        r.icon:SetPoint("LEFT", 54, 0)
        r.spell = Text(r, "GameFontNormalSmall")
        r.spell:SetPoint("TOPLEFT", 84, -3)
        r.spell:SetWidth(190)
        r.source = Text(r, "GameFontDisableSmall")
        r.source:SetPoint("BOTTOMLEFT", 84, 3)
        r.source:SetWidth(190)
        r.amount = Text(r, "GameFontHighlightSmall", "RIGHT")
        r.amount:SetPoint("LEFT", 276, 0)
        r.amount:SetWidth(60)
        r.life = CreateFrame("StatusBar", nil, r)
        r.life:SetSize(90, 10)
        r.life:SetPoint("LEFT", 346, 0)
        r.life:SetStatusBarTexture(Skin().barTexture)
        r.life:SetMinMaxValues(0, 1)
        r.lifeBg = r.life:CreateTexture(nil, "BACKGROUND")
        r.lifeBg:SetAllPoints()
        r.lifeBg:SetColorTexture(0.1, 0.1, 0.12, 1)
        r.pct = Text(r, "GameFontDisableSmall", "RIGHT")
        r.pct:SetPoint("LEFT", r.life, "RIGHT", 4, 0)
        r.pct:SetWidth(34)
        r.mark = r:CreateTexture(nil, "OVERLAY")
        r.mark:SetSize(12, 12)
        r.mark:SetPoint("LEFT", r.pct, "RIGHT", 4, 0)
        detail.rows[i] = r
    end
    detail.empty = Text(detail, "GameFontDisableSmall")
    detail.empty:SetPoint("TOPLEFT", 4, -TITLE)
    return frame
end

---Which tab is on: the summary, or the spell panel inside the same screen.
function Win.SetTab(tab)
    if not frame then return end
    view.tab = tab
    local summary = tab == "summary"
    frame.tabSummary:SetEnabled(not summary)
    frame.tabDeaths:SetEnabled(tab ~= "deaths")
    frame.tabSpells:SetEnabled(tab ~= "spells")
    for _, t in ipairs(frame.tiles) do t:SetShown(summary) end
    for _, b in ipairs(frame.blocks) do b:SetShown(summary) end
    frame.deaths:SetShown(tab == "deaths")
    frame.fightCombo:SetShown(tab ~= "spells")
    frame.runCombo:SetShown(tab ~= "spells")
    if tab == "spells" then
        if ns.Breakdown and ns.Breakdown.ShowOwn then ns.Breakdown.ShowOwn(nil, frame.body) end
    else
        if ns.Breakdown and ns.Breakdown.Unembed then ns.Breakdown.Unembed() end
        Win.Draw()
    end
end

--------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------
local SEVERITY_COLOUR = { [1] = { 0.6, 0.15, 0.15 }, [2] = { 0.55, 0.42, 0.1 }, [3] = { 0.23, 0.23, 0.26 } }

local function DrawTiles(r, own, m)
    local skin = Skin()
    local tiles = frame.tiles
    local role = r and r.role or "DAMAGER"
    local function Set(t, number, label, s1, s2, bad)
        t.number:SetText(number or "-")
        if bad then t.number:SetTextColor(1, 0.42, 0.35) else t.number:SetTextColor(1, 1, 1) end
        t.label:SetText(label)
        t.side1:SetText(s1 or "")
        t.side2:SetText(s2 or "")
    end
    local function Rank(x) return x and x.rank and format(L["%dº of the group"], x.rank) or "" end
    local deaths = #own.deaths
    if role == "HEALER" then
        local h = m and m.healing
        Set(tiles[1], h and Fmt(h.perSecond), L["Healing per second"], h and (Fmt(h.total) .. " " .. L["in total"]) or L["out of combat only"], Rank(h))
        local d = m and m.damage
        Set(tiles[2], d and Fmt(d.perSecond), L["Damage per second"], d and (Fmt(d.total) .. " " .. L["in total"]) or "", Rank(d))
    elseif role == "TANK" then
        local t = m and m.taken
        Set(tiles[1], t and Fmt(t.perSecond), L["Damage taken per second"], t and (Fmt(t.total) .. " " .. L["in total"]) or L["out of combat only"], Rank(t))
        local d = m and m.damage
        Set(tiles[2], d and Fmt(d.perSecond), L["Damage per second"], d and (Fmt(d.total) .. " " .. L["in total"]) or "", Rank(d))
    else
        local d = m and m.damage
        Set(tiles[1], d and Fmt(d.perSecond), L["Damage per second"], d and (Fmt(d.total) .. " " .. L["in total"]) or L["out of combat only"], Rank(d))
        local a = m and m.avoidable
        local share = a and m.taken and m.taken.total > 0 and math.floor(a.total / m.taken.total * 100 + 0.5) or nil
        Set(tiles[2], a and Fmt(a.total), L["Avoidable damage taken"], share and format(L["%d%% of what you took"], share) or "", Rank(a), share and share >= 5)
    end
    local i = m and m.interrupts
    local cast = 0
    if ns.InterruptSpells then for id, n in pairs(own.bySpell) do if ns.InterruptSpells[id] then cast = cast + n end end end
    local missed = i and math.max(0, cast - i.total) or nil
    Set(tiles[3], i and tostring(i.total), L["Interrupts"], Rank(i), missed and missed > 0 and format(L["%d cast cut nothing"], missed) or "")
    local last = own.deaths[#own.deaths]
    Set(tiles[4], tostring(deaths), deaths == 1 and L["Death"] or L["Deaths"],
        last and format(L["at %s"], Clock(last.t)) or "", last and (last.killer or "") or "", deaths > 0)
end

local function DrawProblems(r, scope)
    local list, checked = ns.MyRun.Problems(scope, r and r.role or nil, r)
    local b = frame.problems
    b.title:SetText(format("%s (%s)", L["What cost"], L[r and r.role or "DAMAGER"]))
    for i, row in ipairs(b.rows) do
        local p = list[i]
        if not p then row:Hide() else
            row:Show()
            local c = SEVERITY_COLOUR[p.severity] or SEVERITY_COLOUR[3]
            row.edge:SetColorTexture(c[1], c[2], c[3], 1)
            if p.atlas and row.icon.SetAtlas then
                row.icon:SetAtlas(p.atlas)
            elseif p.item then
                row.icon:SetTexture(134400)   -- the game has no generic potion glyph; the item's own icon when known
            else
                row.icon:SetTexture(SpellIcon(p.spellID))
            end
            row.title:SetText(p.title)
            row.detail:SetText(p.detail or "")
            row.number:SetText(p.number or "")
            row.problem = p
        end
    end
    b.empty:SetShown(#list == 0)
    b.empty:SetText(L["Nothing found: no death, no avoidable damage worth the name, cooldowns on time."])
    b.checked:SetText(format(L["Looked at: %s."], table.concat(checked, ", ")))
end

local function DrawCooldowns(r, own)
    local b = frame.cooldowns
    local classR, classG, classB = ns.ClassColor(r and r.class or nil)
    local k = Skin().barBrightness
    for i, row in ipairs(b.rows) do
        local cd = own.cooldowns[i]
        if not cd then row:Hide() else
            row:Show()
            row.spellID = cd.spellID
            row.icon:SetTexture(SpellIcon(cd.spellID))
            row.name:SetText(cd.name .. (cd.category == "utility" and (" " .. L["(defensive)"]) or ""))
            row.value:SetText(format("%d / %d", cd.used, cd.fitted))
            row.bar:SetMinMaxValues(0, math.max(1, cd.fitted))
            row.bar:SetValue(cd.used)
            local ratio = cd.fitted > 0 and cd.used / cd.fitted or 1
            if ratio < 0.5 then row.bar:SetStatusBarColor(0.69, 0.29, 0.23, 0.6)
            else row.bar:SetStatusBarColor(classR * k, classG * k, classB * k, 0.8) end
            if view.cooldown == cd.spellID then row.bg:SetColorTexture(1, 1, 1, 0.08) else row.bg:SetColorTexture(0, 0, 0, 0.3) end
        end
    end
    b.note:SetText(#own.cooldowns == 0 and L["The game's Cooldown Manager lists no cooldown for this spec."]
        or L["The game's Cooldown Manager list, with the cooldown of each. Click one to see it on the timeline."])
end

local function DrawTaken(m, scope)
    local b = frame.taken
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
            if sp.avoidable then row.bar:SetStatusBarColor(0.69, 0.29, 0.23, 0.6) else row.bar:SetStatusBarColor(0.47, 0.47, 0.51, 0.45) end
            if sp.deadly and row.mark.SetAtlas then row.mark:SetAtlas("icons_16x16_deadly"); row.mark:Show()
            elseif sp.avoidable and row.mark.SetAtlas then row.mark:SetAtlas("damagemeters-avoidabledamage-icon"); row.mark:Show()
            else row.mark:Hide() end
        end
    end
    if not m then
        b.note:SetText(type(scope) == "number" and L["A past fight: the meter no longer keeps it."] or L["In combat the meter's numbers are hidden; they come back when it ends."])
    elseif #list == 0 then
        b.note:SetText(type(scope) == "number" and L["By spell, the meter only answers for the whole run."] or L["Nothing taken."])
    else
        b.note:SetText(total > 0 and format(L["%d%% avoidable"], math.floor(avoidable / total * 100 + 0.5)) or "")
    end
end

local function DrawTimeline(r, own)
    local tl = frame.timeline
    for _, s in ipairs(tl.segments) do s:Hide() end
    for _, mk in ipairs(tl.marks) do mk:Hide() end
    if not r then return end
    local total = r.elapsed or (r.fights[#r.fights] and r.fights[#r.fights].e) or 0
    if r.open then total = math.max(total, r.open.e or (GetTime() - r.startedAt)) end
    if total <= 0 then total = 1 end
    local width = LEFT_WIDTH
    local function X(t) return math.max(0, math.min(width, t / total * width)) end
    local used = 0
    local function Segment(from, to)
        used = used + 1
        local seg = tl.segments[used]
        if not seg then seg = tl:CreateTexture(nil, "ARTWORK"); tl.segments[used] = seg end
        seg:ClearAllPoints()
        seg:SetPoint("LEFT", tl.rail, "LEFT", X(from), 0)
        seg:SetHeight(6)
        seg:SetWidth(math.max(1, X(to) - X(from)))
        seg:SetColorTexture(0.10, 0.70, 0.10, 0.85)
        seg:Show()
    end
    local fights = {}
    for _, f in ipairs(r.fights) do fights[#fights + 1] = f end
    if r.open then fights[#fights + 1] = r.open end
    for _, f in ipairs(fights) do Segment(f.s, f.e or total) end
    local marks = 0
    local function Mark(t, dy, size, atlas, texture)
        marks = marks + 1
        local mk = tl.marks[marks]
        if not mk then mk = tl:CreateTexture(nil, "OVERLAY"); tl.marks[marks] = mk end
        mk:ClearAllPoints()
        mk:SetSize(size, size)
        mk:SetPoint("CENTER", tl.rail, "LEFT", X(t), dy)
        if atlas and mk.SetAtlas then mk:SetAtlas(atlas) else mk:SetTexture(texture) end
        mk:Show()
    end
    for _, f in ipairs(fights) do
        if f.boss and f.e then Mark(f.e, 0, 18, "worldquest-icon-boss") end
    end
    for _, d in ipairs(own.deaths) do Mark(d.t, -14, 16, "deathrecap-icon-tombstone") end
    for _, it in ipairs(r.items or {}) do
        if it[2] == "potion" then Mark(it[1], -14, 12, nil, 134400) end
    end
    -- The chosen cooldown: one icon per use.
    local chosen = view.cooldown or (own.cooldowns[1] and own.cooldowns[1].spellID)
    local chosenName
    if chosen then
        local tex = SpellIcon(chosen)
        if r.casts then
            for _, c in ipairs(r.casts) do if c[2] == chosen then Mark(c[1], 16, 14, nil, tex) end end
        end
        chosenName = SpellNameOf(chosen)
    end
    tl.legend:SetText(chosenName and format(L["%s: each icon is a use"], chosenName) or L["Click a cooldown to see its uses here."])
    tl.start:SetText("0:00")
    tl.finish:SetText(Clock(total))
end

local function DrawRhythm(own)
    local rows = frame.rhythm.rows
    local seconds = own.combatSeconds
    local active = seconds > 0 and math.max(0, (seconds - own.gaps.total) / seconds) or 0
    local function Set(row, name, value, ratio)
        row:Show()
        row.name:SetText(name)
        row.value:SetText(value)
        row.bar:SetMinMaxValues(0, 1)
        row.bar:SetValue(ratio)
        row.bar:SetStatusBarColor(0.24, 0.47, 0.71, 0.45)
    end
    Set(rows[1], L["Time casting in combat"], seconds > 0 and format("%d%% · %s idle of %s", math.floor(active * 100 + 0.5), Clock(own.gaps.total), Clock(seconds)) or "-", active)
    Set(rows[2], L["Casts per minute"], own.perMinute and format("%d · %d in the scope", math.floor(own.perMinute + 0.5), own.casts) or "-", own.perMinute and math.min(1, own.perMinute / 60) or 0)
    Set(rows[3], L["Potion / healthstone"], format("%d / %d", own.potions, own.healthstones), math.min(1, own.potions / math.max(1, own.bossCount)))
end

local function DrawHistory(r)
    local b = frame.history
    local head = b.rows[0]
    local labels = { L["Run"], L["DPS"], L["Avoidable"], L["Interr."], L["Deaths"] }
    for c, cell in ipairs(head.cells) do cell:SetText(labels[c]) end
    local list = ns.MyRun.History()
    b.title:SetText(format("%s — %s", L["History"], r and r.name or ""))
    local shown = 0
    for i = 1, MAX_HISTORY do
        local row = b.rows[i]
        local saved = list[i]
        if not saved or (r and r.name and saved.name ~= r.name) then row:Hide() else
            shown = shown + 1
            row:Show()
            local m = saved.metrics
            local share = m and m.taken and m.avoidable and m.taken.total > 0 and math.floor(m.avoidable.total / m.taken.total * 100 + 0.5) or nil
            local deaths = #(saved.deaths or {})
            local cells = row.cells
            cells[1]:SetText((saved.date or ""):sub(6, 10) .. (saved.level and (" +" .. saved.level) or ""))
            cells[2]:SetText(m and m.damage and Fmt(m.damage.perSecond) or "-")
            cells[3]:SetText(share and (share .. "%") or "-")
            cells[4]:SetText(m and m.interrupts and tostring(m.interrupts.total) or "-")
            cells[5]:SetText(tostring(deaths))
            local mine = saved == r
            for _, cell in ipairs(cells) do
                if mine then cell:SetTextColor(1, 0.82, 0) else cell:SetTextColor(0.86, 0.87, 0.9) end
            end
        end
    end
    if shown == 0 then
        b.rows[1]:Show()
        b.rows[1].cells[1]:SetText(L["No run saved yet."])
        for c = 2, 5 do b.rows[1].cells[c]:SetText("") end
    end
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
            if row.icon.SetAtlas and not death.killerSpell then row.icon:SetAtlas("deathrecap-icon-tombstone")
            else row.icon:SetTexture(SpellIcon(death.killerSpell)) end
            local killer = (death.killer or L["cause unknown"]) .. (death.killerSource and (" · " .. death.killerSource) or "")
            if death.hardest then
                row.killer:SetText(format("%s: %s", L["Killed"], killer))
                row.hardest:SetText(format("%s: %s", L["Hardest"], death.hardest .. (death.hardestSource and (" · " .. death.hardestSource) or "")))
            else
                row.killer:SetText(format("%s: %s", L["Killed and hardest"], killer))
                row.hardest:SetText(ns.MyRun.BossAt and ns.MyRun.BossAt(death.t, r) or "")
            end
            if death.avoidable and row.mark.SetAtlas then row.mark:SetAtlas("damagemeters-avoidabledamage-icon"); row.mark:Show()
            else row.mark:Hide() end
            if view.death == i then row.bg:SetColorTexture(1, 1, 1, 0.08) else row.bg:SetColorTexture(0, 0, 0, 0.3) end
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
        if not ev then row:Hide() else
            row:Show()
            row.before:SetText(ev.before and format("-%.1fs", ev.before) or "")
            row.icon:SetTexture(SpellIcon(ev.spellId))
            row.spell:SetText(ev.spell or L["cause unknown"])
            if i == 1 then row.spell:SetTextColor(1, 0.3, 0.3) else row.spell:SetTextColor(1, 0.82, 0) end
            row.source:SetText(ev.source or "")
            local amount = ev.amount and Fmt(ev.amount) or "-"
            if ev.absorbed and ev.absorbed > 0 then amount = amount .. format(" (%s %s)", Fmt(ev.absorbed), L["absorbed"]) end
            row.amount:SetText(amount)
            row.amount:SetTextColor(1, 0.3, 0.3)
            local hp = ev.hp
            local share = maxHealth and maxHealth > 0 and hp and math.max(0, math.min(1, hp / maxHealth)) or nil
            row.life:SetValue(share or 0)
            if share and share < 0.2 then row.life:SetStatusBarColor(0.78, 0.23, 0.1)
            elseif share and share < 0.5 then row.life:SetStatusBarColor(0.78, 0.64, 0.1)
            else row.life:SetStatusBarColor(0.23, 0.66, 0.23) end
            row.pct:SetText(share and format("%d%%", math.floor(share * 100 + 0.5)) or "")
            if ev.deadly and row.mark.SetAtlas then row.mark:SetAtlas("icons_16x16_deadly"); row.mark:Show()
            elseif ev.avoidable and row.mark.SetAtlas then row.mark:SetAtlas("damagemeters-avoidabledamage-icon"); row.mark:Show()
            else row.mark:Hide() end
        end
    end
end

function Win.Draw()
    if not frame or view.tab == "spells" then return end
    local r = RunShown()
    local scope = view.scope
    local own = ns.MyRun.Own(scope, r)
    if view.tab == "deaths" then
        DrawDeaths(r, own)
        if frame.fightCombo.GenerateMenu then frame.fightCombo:GenerateMenu() end
        if frame.runCombo.GenerateMenu then frame.runCombo:GenerateMenu() end
        return
    end
    local m = ns.MyRun.Metrics(scope, r)

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
    if frame.fightCombo.GenerateMenu then frame.fightCombo:GenerateMenu() end
    if frame.runCombo.GenerateMenu then frame.runCombo:GenerateMenu() end

    DrawTiles(r, own, m)
    DrawProblems(r, scope)
    DrawCooldowns(r, own)
    DrawTaken(m, scope)
    DrawTimeline(r, own)
    DrawRhythm(own)
    DrawHistory(r)
end

---Opens the screen, beside `anchorTo` when it fits, else centred.
function Win.Show(anchorTo)
    CreatePanel()
    view.run = nil
    local scopes = ns.MyRun.Scopes(RunShown())
    local valid = false
    for _, s in ipairs(scopes) do if s.key == view.scope then valid = true end end
    if not valid then view.scope = "all" end
    frame:ClearAllPoints()
    local placed = false
    local saved = ns.db and ns.db.myRunPos
    if type(saved) == "table" and type(saved.point) == "string" then
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
        placed = true
    end
    if not placed and anchorTo and anchorTo.GetRight and UIParent and UIParent.GetWidth then
        local right, screen = anchorTo:GetRight(), UIParent:GetWidth()
        if type(right) == "number" and type(screen) == "number" then
            if right + WIDTH + 6 <= screen then frame:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", 6, 0)
            else frame:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", -6, 0) end
            placed = true
        end
    end
    if not placed then frame:SetPoint("CENTER") end
    frame.anchorTo = anchorTo
    frame:Show()
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
function Win.Toggle(anchorTo) if Win.IsShown() then Win.Hide() else Win.Show(anchorTo) end end

-- For the harness.
function Win.__frame() return frame end
function Win.__view() return view end
function Win.__setView(scope, r) view.scope = scope; view.run = r end
