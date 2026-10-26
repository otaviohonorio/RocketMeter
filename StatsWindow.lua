-- RocketMeter | StatsWindow.lua
-- (26/10) The Statistics window: this week and the season, side by side in two tabs (the data is Stats.lua). Opened by
-- the trophy in the meter's header. The same pieces as "My run" (the game's skin, the rule of 27/09):
--
--   frame     `ButtonFrameTemplate` without the portrait, the dark body (ns.DarkBody, "escuro em tudo")
--   body      its `Inset`, one page that scrolls (Report.Page)
--   tabs      `PanelTabButtonTemplate` under the frame: the game's "This Week" and our "Season"
--   boxes     Report.Band (`InsetFrameTemplate3`) over each table, Report.Table, Report.Note
local ADDON, ns = ...
local L = ns.L

local Win = {}
ns.StatsWindow = Win

local WIDTH = 760
local PAD = 12
local TOP_BAND = 30
local BODY_HEIGHT = 520
local GAP = 10
local INNER = WIDTH - 16 - PAD * 2
local TABS = { "week", "season" }
local TAB_LABEL = { week = L["This Week"], season = L["Season"] }
-- (26/10) the columns' widths: the longest header of the eleven languages, measured with the game's font at 10
-- (frFR "Plus haute dans les temps" 129 px, "Emplacements débloqués" 127, ptBR "Tentativas fracassadas" 115) plus
-- the cell's padding
local VAULT_LABEL = { [1] = L["Dungeons"], [3] = L["Raids"], [6] = L["World"] }

local frame
local view = { tab = "week" }

local function Kit() return ns.MyRunWindow.Kit end

---A number with one decimal, in the game's decimal mark (a comma in Portuguese).
local function Dec(v)
    if not v then return nil end
    local text = format("%.1f", v)
    local mark = type(DECIMAL_SEPERATOR) == "string" and DECIMAL_SEPERATOR or "."
    return (text:gsub("%.", mark))
end

local function Whole(v)
    if not v then return nil end
    local n = math.floor(v + 0.5)
    if BreakUpLargeNumbers then
        local ok, text = pcall(BreakUpLargeNumbers, n)
        if ok and type(text) == "string" then return text end
    end
    return tostring(n)
end

local function Duration(sec)
    if not sec or sec <= 0 then return nil end
    if SecondsToTime then
        local ok, text = pcall(SecondsToTime, sec, true)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return Kit().Clock(sec)
end

local function Share(n, of)
    if not of or of <= 0 then return tostring(n or 0) end
    return format("%d (%d%%)", n or 0, math.floor(100 * (n or 0) / of + 0.5))
end

-- the two-column table of a box: a label and its value
local PAIRS = { { key = "name", label = "" }, { key = "value", label = "", width = 150 } }
local function Pairs(rows)
    local out = {}
    for _, r in ipairs(rows) do out[#out + 1] = { name = r[1], value = r[2] or "-" } end
    return out
end

---A band and a table under it, at `x` and `width`, without moving the page's cursor; returns the height taken.
local function Box(page, x, width, title, right, spec)
    local y0 = page.y
    ns.Report.Band(page, title, x, width, right, true)
    page.y = y0 + ns.Report.Geometry.BAND
    spec.x, spec.width = x, width
    local h = ns.Report.Table(page, spec, true)
    page.y = y0
    return ns.Report.Geometry.BAND + h
end

local function SideBySide(page, left, right)
    local half = (page.width - GAP) / 2
    local h1 = Box(page, 0, half, left[1], left[2], left[3])
    local h2 = right and Box(page, half + GAP, half, right[1], right[2], right[3]) or 0
    page.y = page.y + math.max(h1, h2) + GAP
end

local function Full(page, title, right, spec)
    page.y = page.y + Box(page, 0, page.width, title, right, spec) + GAP
end

---What the two tabs draw.
function Win.Draw()
    if not frame or not frame:IsShown() then return end
    local Stats = ns.Stats
    local snap = Stats.Capture()
    local s = Stats.Compute(snap, view.tab)
    local week = view.tab == "week"
    local page = frame.page
    ns.Report.Begin(page)

    local m = s.mplus
    local mplusRows = {
        { L["Keys"], tostring(m.keys or 0) },
        { L["In time"], Share(m.inTime, m.keys) },
        { L["Over time"], tostring(m.overTime or 0) },
        { L["Not finished"], tostring(m.notDone or 0) },
        -- the level alone: with the dungeon's name it did not fit ("+15 · Arena da Chaga do Caos" is 153 px in a cell of
        -- 144, the user's print of 26/10), and the dungeon is in the Dungeons table below, on the row with that level
        { L["Highest in time"], m.highest and ("+" .. m.highest.level) },
        { L["Average level"], m.avgLevel and ("+" .. Dec(m.avgLevel)) },
        { L["Time in keys"], Duration(m.seconds) },
    }
    local ratingRight = week and (m.gained and (L["Gained this week"] .. ": " .. (m.gained >= 0 and "+" or "") .. Whole(m.gained)))
        or (m.rating and (L["Mythic+ Rating"] .. ": " .. Whole(m.rating)))
    local p = s.perf
    local perfRows = {
        { L["Keys recorded"], tostring(p.keys or 0) },
        { L["Damage per second, on average"], p.dps and Kit().Fmt(p.dps) },
        { L["Rank in the group, on average"], Dec(p.rank) },
        { L["Deaths per key"], Dec(p.deaths) },
        { L["Interrupts per key"], Dec(p.interrupts) },
        { L["Raids recorded"], tostring(p.raids or 0) },
        { L["Damage per second on bosses"], p.bossDps and Kit().Fmt(p.bossDps) },
    }
    local mplusBox = { L["Mythic+"], ratingRight, { columns = PAIRS, rows = Pairs(mplusRows), noHead = true } }
    local perfBox = { L["Your performance"], nil, { columns = PAIRS, rows = Pairs(perfRows), noHead = true } }

    if week then
        local vaultRows = {}
        for _, v in ipairs(s.vault or {}) do
            vaultRows[#vaultRows + 1] = { name = VAULT_LABEL[v.type] or tostring(v.type),
                                          done = format("%d/%d", v.progress or 0, v.threshold or 0),
                                          open = format("%d/%d", v.unlocked or 0, v.slots or 0) }
        end
        SideBySide(page, mplusBox, { L["Great Vault"], nil, { columns = {
            { key = "name", label = "" }, { key = "done", label = L["Done"], width = 70 },
            { key = "open", label = L["Unlocked"], width = 134 } }, rows = vaultRows } })
    else
        SideBySide(page, mplusBox, perfBox)
    end

    -- each dungeon of the season
    local dRows = {}
    for _, d in ipairs(s.dungeons or {}) do
        local info = ((snap.maps or {})[d.cm]) or {}
        dRows[#dRows + 1] = { name = d.name or ("#" .. tostring(d.cm)), icon = info.icon, keys = tostring(d.keys or 0),
                              inTime = tostring(d.inTime or 0), best = d.bestLevel and ("+" .. d.bestLevel),
                              time = d.bestSec and Kit().Clock(d.bestSec), rating = d.rating and Whole(d.rating) }
    end
    local dCols = { { key = "name", label = L["Dungeon"] }, { key = "keys", label = L["Keys"], width = 84 },
                    { key = "inTime", label = L["In time"], width = 84 }, { key = "best", label = L["Highest in time"], width = 136 },
                    { key = "time", label = L["Best time"], width = 90 } }
    if not week then dCols[#dCols + 1] = { key = "rating", label = L["Rating"], width = 70 } end
    for _, c in ipairs(dCols) do c.fmt = function(v) return v end end
    Full(page, L["Dungeons"], nil, { columns = dCols, rows = dRows })

    -- the raids: this week's lockouts (the game), the season's from the runs recorded
    local rRows = {}
    if week then
        for _, r in ipairs(s.raids or {}) do
            rRows[#rRows + 1] = { name = r.name .. (r.difficultyName and (" · " .. r.difficultyName) or ""),
                                  bosses = format("%d/%d", r.done or 0, r.total or 0) }
        end
        -- none: one line that says so, not a header over nothing (the user's print of 26/10)
        if #rRows == 0 then rRows[1] = { name = L["No raid lockout this week."], bosses = "" } end
        local raidBox = { L["Raids"], nil, { columns = { { key = "name", label = "" },
            { key = "bosses", label = L["Bosses"], width = 80 } }, rows = rRows } }
        SideBySide(page, raidBox, perfBox)
    else
        for _, r in ipairs(s.raids or {}) do
            rRows[#rRows + 1] = { name = tostring(r.name) .. (r.detail and (" · " .. r.detail) or ""),
                                  kills = tostring(r.kills or 0), wipes = tostring(r.wipes or 0) }
        end
        if #rRows == 0 then rRows[1] = { name = L["No raid recorded this season."], kills = "", wipes = "" } end
        Full(page, L["Raids"], nil, { columns = { { key = "name", label = "" },
            { key = "kills", label = L["Bosses defeated"], width = 130 }, { key = "wipes", label = L["Wipes"], width = 122 } }, rows = rRows })
    end

    if not next(snap.maps or {}) and #(snap.runs or {}) == 0 then
        ns.Report.Note(page, L["The game has not sent the keys yet: they show here in a few seconds."])
    end
    local all = week and Stats.Compute(snap, "season").perf or p
    ns.Report.Note(page, format(L["The keys, the rating, the Great Vault and the raids come from the game. Your performance comes from the runs RocketMeter recorded: %d keys and %d raids this season."],
        all.keys or 0, all.raids or 0))
    ns.Report.Finish(page)
end

local function CreatePanel()
    if frame then return frame end
    frame = CreateFrame("Frame", ADDON .. "Stats", UIParent, "ButtonFrameTemplate")
    frame:SetWidth(WIDTH)
    ns.DarkBody(frame, 1, frame.Bg)
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
        if ns.db and type(point) == "string" then ns.db.statsPos = { point = point, relPoint = relPoint, x = x, y = y } end
    end)
    frame:Hide()
    ButtonFrameTemplate_HidePortrait(frame)
    frame:SetTitle(L["Statistics"])
    tinsert(UISpecialFrames, frame:GetName())

    local inset = frame.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", 8, -TOP_BAND)
    inset:SetPoint("BOTTOMRIGHT", -8, ns.DONATE_ROW + 6)
    frame.body = CreateFrame("Frame", nil, inset)
    frame.body:SetPoint("TOPLEFT", PAD, -PAD)
    frame.body:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    frame.page = CreateFrame("Frame", nil, frame.body)
    frame.page:SetAllPoints()
    ns.Report.Page(frame.page, INNER)

    frame:SetHeight(TOP_BAND + PAD + BODY_HEIGHT + PAD + ns.DONATE_ROW + 6)
    ns.DonateFooter(frame)

    frame.tabs = {}
    for i, key in ipairs(TABS) do
        local tab = CreateFrame("Button", frame:GetName() .. "Tab" .. i, frame, "PanelTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(TAB_LABEL[key])
        tab:SetScript("OnClick", function() Win.SetTab(key) end)
        if i == 1 then tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
        else tab:SetPoint("LEFT", frame.tabs[i - 1], "RIGHT", 3, 0) end
        PanelTemplates_TabResize(tab, 0)
        frame.tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(frame, #TABS)
    return frame
end

function Win.SetTab(tab)
    if not frame then return end
    view.tab = tab
    for i, key in ipairs(TABS) do if key == tab then PanelTemplates_SetTab(frame, i) end end
    if frame.page.scroll and frame.page.scroll.SetVerticalScroll then frame.page.scroll:SetVerticalScroll(0) end
    Win.Draw()
end

function Win.Show()
    if not ns.Stats then return end
    CreatePanel()
    ns.Stats.Request()
    frame:ClearAllPoints()
    local saved = ns.db and ns.db.statsPos
    if type(saved) == "table" and type(saved.point) == "string" then
        frame:SetPoint(saved.point, UIParent, saved.relPoint or saved.point, saved.x or 0, saved.y or 0)
    else
        frame:SetPoint("CENTER")
    end
    frame:Show()
    frame:Raise()
    Win.SetTab(view.tab or "week")
end

function Win.Hide() if frame then frame:Hide() end end
function Win.IsShown() return frame ~= nil and frame:IsShown() end
function Win.Refresh() if Win.IsShown() then Win.Draw() end end
function Win.Toggle() if Win.IsShown() then Win.Hide() else Win.Show() end end

-- For the harness.
function Win.__frame() return frame end
function Win.__view() return view end
