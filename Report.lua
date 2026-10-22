-- RocketMeter | Report.lua
-- The pieces of "My run" drawn the way Warcraft Logs draws a report: a chart over the time of the run, a table with a
-- header line, the amount as "percent · bar · total" in its own column and a Total line, a box with a title band.
--
-- (!) THE USER, 20/10: *"essa janela ela precisa ser igual ao warcraftlogs e entendo se não tiver algumas informações
-- por não ter como mesmo, mas pesquisa tudo, analisa todos os detalhes e faça"*. What came from their report (the
-- user's, `2LMPXTqKQ4xBRGvF`, read tab by tab on 20/10): every table is Name, then Amount (the share in percent, a bar
-- and the total), then the columns of the tab, then the rate; a Total line at the foot; every chart has the time of
-- the fight along the bottom and the amount per second at the left. The skin stays the game's (the rule of 27/09):
-- the game's fonts and colour objects, the window's dark inset, the bars of the meter.
--
-- A page scrolls (the game's ScrollFrameTemplate) and is drawn top to bottom: `Begin`, then boxes, tables, charts and
-- notes, each one placed under the one before (or beside it, with `x` and `width`), then `Finish`.
local ADDON, ns = ...
local L = ns.L

local Report = {}
ns.Report = Report

local SCROLL_BAR = 24
local BAND = 20                 -- the title band of a box
local HEAD = 18                 -- the header line of a table
local ROW = 20                  -- a line of a table
local GAP = 10
local CELL_PAD = 6
local AXIS_LEFT = 44            -- the amounts at the left of a chart
local AXIS_BOTTOM = 16          -- the times under a chart
local PCT_WIDTH = 46            -- inside the Amount column: the percent, the bar, the total
local TOTAL_WIDTH = 56
Report.Geometry = { BAND = BAND, HEAD = HEAD, ROW = ROW, GAP = GAP, SCROLL_BAR = SCROLL_BAR }

local function Kit() return ns.MyRunWindow.Kit end

local function RGB(colour, r, g, b)
    if colour and colour.GetRGB then return colour:GetRGB() end
    return r or 1, g or 1, b or 1
end

--------------------------------------------------------------------------------
-- The page and its pools
--------------------------------------------------------------------------------
---Builds a scrolling page inside `page`, `width` wide.
function Report.Page(page, width)
    page.scroll = CreateFrame("ScrollFrame", nil, page, "ScrollFrameTemplate")
    page.scroll:SetPoint("TOPLEFT")
    page.scroll:SetPoint("BOTTOMRIGHT", -SCROLL_BAR, 0)
    page.child = CreateFrame("Frame", nil, page.scroll)
    page.width = width - SCROLL_BAR
    page.child:SetSize(page.width, 10)
    page.scroll:SetScrollChild(page.child)
    page.pools = {}
    return page
end

---A pool of one kind of piece of a page, reused at every redraw.
local function Take(page, kind, make)
    local pool = page.pools[kind]
    if not pool then pool = { used = 0, list = {} }; page.pools[kind] = pool end
    pool.used = pool.used + 1
    local piece = pool.list[pool.used]
    if not piece then
        piece = make()
        pool.list[pool.used] = piece
    end
    if piece.ClearAllPoints then piece:ClearAllPoints() end
    piece:Show()
    return piece
end

function Report.Begin(page)
    page.y = 0
    page.items = {}
    for _, pool in pairs(page.pools) do pool.used = 0 end
end

function Report.Finish(page)
    for _, pool in pairs(page.pools) do
        for i = pool.used + 1, #pool.list do pool.list[i]:Hide() end
    end
    page.child:SetHeight(page.y + 20)
end

--------------------------------------------------------------------------------
-- Text pieces
--------------------------------------------------------------------------------
local function FontString(page, template, justify)
    return Take(page, "text:" .. (template or "") .. (justify or ""), function()
        local fs = Kit().Text(page.child, template, justify)
        return fs
    end)
end

---A paragraph in the game's light grey, wrapped to the width. Returns its height.
function Report.Note(page, text, x, width, noAdvance)
    local fs = FontString(page, "GameFontDisableSmall", "LEFT")
    fs:SetWordWrap(true)
    fs:SetJustifyV("TOP")
    fs:SetPoint("TOPLEFT", (x or 0) + 4, -page.y)
    fs:SetWidth((width or page.width) - 8)
    fs:SetText(text or "")
    local h = math.max(14, (fs.GetStringHeight and fs:GetStringHeight() or 14) + 4)
    page.items[#page.items + 1] = { kind = "note", text = text, string = fs }
    if not noAdvance then page.y = page.y + h + 4 end
    return h + 4
end

---The title band of a box, as Warcraft Logs heads each table ("Damage Done By Ability"). Returns its height.
function Report.Band(page, title, x, width, right, noAdvance)
    local band = Take(page, "band", function()
        local b = CreateFrame("Frame", nil, page.child, "InsetFrameTemplate3")
        b.title = Kit().Text(b, "GameFontNormalSmall")
        b.title:SetPoint("LEFT", 6, 0)
        b.right = Kit().Text(b, "GameFontHighlightSmall", "RIGHT")
        b.right:SetPoint("RIGHT", -6, 0)
        return b
    end)
    band:SetPoint("TOPLEFT", x or 0, -page.y)
    band:SetSize(width or page.width, BAND)
    band.title:SetText(title or "")
    band.right:SetText(right or "")
    page.items[#page.items + 1] = { kind = "band", title = title, right = right, frame = band }
    if not noAdvance then page.y = page.y + BAND end
    return BAND
end

--------------------------------------------------------------------------------
-- The table
--------------------------------------------------------------------------------
-- A column: { key, label, width, grey = true (the game's light grey: rates and averages), fmt = function(v, row) }.
-- The column "amount" is special: the share in percent, a bar as long as the row's `bar` against the table's `top`,
-- and the total. The first column is always the name, with the icon, and takes the width the others leave.
local function Cell(parent, justify, template)
    local fs = Kit().Text(parent, template or "GameFontHighlightSmall", justify or "RIGHT")
    return fs
end

local function MakeRow(page)
    local K = Kit()
    local r = CreateFrame("Button", nil, page.child)
    r:SetHeight(ROW)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(ROW - 4, ROW - 4)
    r.icon:SetPoint("LEFT", 4, 0)
    r.name = Cell(r, "LEFT")
    r.name:SetPoint("LEFT", ROW + 4, 0)
    r.cells = {}
    -- the Amount column's three pieces
    r.pct = Cell(r, "RIGHT")
    r.barBg = r:CreateTexture(nil, "BORDER")
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetStatusBarTexture(K.BarTexture())
    r.bar:SetMinMaxValues(0, 1)
    r.total = Cell(r, "RIGHT")
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r:SetScript("OnEnter", function(self)
        if not self.spellID and not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok
        if self.link then ok = pcall(GameTooltip.SetHyperlink, GameTooltip, self.link)
        else ok = pcall(GameTooltip.SetSpellByID, GameTooltip, self.spellID) end
        if not ok then GameTooltip:Hide() return end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) if self.onClick then self.onClick(self.data) end end)
    return r
end

local function MakeHead(page)
    local h = CreateFrame("Frame", nil, page.child)
    h:SetHeight(HEAD)
    h.bg = h:CreateTexture(nil, "BACKGROUND")
    h.bg:SetAllPoints()
    h.bg:SetColorTexture(0, 0, 0, 0.45)
    h.name = Kit().Text(h, "GameFontNormalSmall", "LEFT")
    h.name:SetPoint("LEFT", 6, 0)
    h.cells = {}
    return h
end

---Lays out `n` cells of `holder` from the right edge in, by the widths of `columns` (the first, the name, excluded).
local function PlaceCells(holder, columns, make)
    local x = -CELL_PAD
    for i = #columns, 2, -1 do
        local c = columns[i]
        local cell = holder.cells[i]
        if not cell then cell = make(); holder.cells[i] = cell end
        cell:ClearAllPoints()
        cell:SetPoint("RIGHT", holder, "RIGHT", x, 0)
        cell:SetWidth(c.width - CELL_PAD)
        cell:Show()
        c.right = x
        x = x - c.width
    end
    for i = #columns + 1, #holder.cells do if holder.cells[i] then holder.cells[i]:Hide() end end
    if holder.cells[1] then holder.cells[1]:Hide() end
    return x
end

---A table. `spec`: { columns, rows, total (a row, or nil), top (the bar's full length), x, width, maxRows,
---colour = { r, g, b } (the bars), onClick = function(row), selected = row }; a column may have `colour(v, row)` for
---its cells. Each row: { spellID or icon, name,
---[column key] = value, bar, share }. Returns its height; `noAdvance` keeps the cursor where it was (a table beside
---another).
function Report.Table(page, spec, noAdvance)
    local K = Kit()
    local x, width = spec.x or 0, spec.width or page.width
    local columns = spec.columns
    local y0 = page.y
    local y = y0
    local cr, cg, cb = unpack(spec.colour or { 0.6, 0.6, 0.6 })

    local head = Take(page, "head", function() return MakeHead(page) end)
    head:SetPoint("TOPLEFT", x, -y)
    head:SetWidth(width)
    head.name:SetText(columns[1].label or "")
    local left = PlaceCells(head, columns, function() return Cell(head, "RIGHT", "GameFontNormalSmall") end)
    for i = 2, #columns do
        local c = columns[i]
        head.cells[i]:SetText(c.label or "")
        head.cells[i]:SetJustifyH(c.key == "amount" and "CENTER" or (c.justify or "RIGHT"))
    end
    head.name:SetPoint("RIGHT", head, "RIGHT", left, 0)
    y = y + HEAD

    local shown = {}
    for i, row in ipairs(spec.rows or {}) do
        if spec.maxRows and i > spec.maxRows then break end
        shown[#shown + 1] = row
    end
    if spec.total then shown[#shown + 1] = spec.total end
    local frames = {}
    local bg = (ns.Skin and ns.Skin.panelRowBackground) or { 0, 0, 0, 0.25 }
    for i, data in ipairs(shown) do
        local r = Take(page, "row", function() return MakeRow(page) end)
        frames[i] = r
        r:SetPoint("TOPLEFT", x, -y)
        r:SetWidth(width)
        local isTotal = data == spec.total
        -- the lines in turn a little darker, as the site does; the Total line darkest
        local a = isTotal and 0.55 or (i % 2 == 0 and bg[4] + 0.12 or bg[4])
        r.bg:SetColorTexture(bg[1], bg[2], bg[3], a)
        r.spellID, r.link, r.data, r.onClick = data.spellID, data.link, data, spec.onClick
        if data.atlas then r.icon:SetAtlas(data.atlas); r.icon:Show()
        elseif data.icon or data.spellID then r.icon:SetTexture(data.icon or K.SpellIcon(data.spellID)); r.icon:Show()
        else r.icon:Hide() end
        r.name:ClearAllPoints()
        r.name:SetPoint("LEFT", (r.icon:IsShown() and ROW or 0) + 6, 0)
        r.name:SetText(data.name or (data.spellID and K.SpellNameOf(data.spellID)) or "")
        K.Colour(r.name, isTotal and NORMAL_FONT_COLOR or (data.nameColour or HIGHLIGHT_FONT_COLOR))
        local leftEdge = PlaceCells(r, columns, function() return Cell(r, "RIGHT") end)
        r.name:SetPoint("RIGHT", r, "RIGHT", leftEdge, 0)
        r.pct:Hide(); r.bar:Hide(); r.barBg:Hide(); r.total:Hide()
        for ci = 2, #columns do
            local c = columns[ci]
            local cell = r.cells[ci]
            if c.key == "amount" then
                cell:SetText("")
                -- the share, the bar, the total, inside the column
                local colLeft = c.right - c.width + CELL_PAD
                r.pct:ClearAllPoints()
                r.pct:SetPoint("LEFT", r, "RIGHT", colLeft, 0)
                r.pct:SetWidth(PCT_WIDTH)
                r.pct:SetText(data.share and format("%.2f%%", data.share) or (isTotal and "100%" or ""))
                r.pct:Show()
                r.total:ClearAllPoints()
                r.total:SetPoint("RIGHT", r, "RIGHT", c.right, 0)
                r.total:SetWidth(TOTAL_WIDTH)
                local v = data.amount
                r.total:SetText(c.fmt and c.fmt(v, data) or (v and K.Fmt(v)) or "")
                r.total:Show()
                if not isTotal and data.bar then
                    local barLeft = colLeft + PCT_WIDTH + 4
                    local barWidth = math.max(4, c.width - CELL_PAD - PCT_WIDTH - TOTAL_WIDTH - 8)
                    r.barBg:SetPoint("LEFT", r, "RIGHT", barLeft, 0)
                    r.barBg:SetSize(barWidth, ROW - 8)
                    r.barBg:SetColorTexture(0, 0, 0, 0.35)
                    r.barBg:Show()
                    r.bar:SetPoint("LEFT", r, "RIGHT", barLeft, 0)
                    r.bar:SetSize(barWidth, ROW - 8)
                    r.bar:SetMinMaxValues(0, math.max(1, spec.top or 1))
                    r.bar:SetValue(data.bar)
                    r.bar:SetStatusBarColor(cr, cg, cb)
                    r.bar:Show()
                end
            else
                local v = data[c.key]
                local text
                if c.fmt then text = c.fmt(v, data) elseif type(v) == "number" then text = K.Fmt(v) else text = v end
                cell:SetJustifyH(c.justify or "RIGHT")
                cell:SetText(text or (isTotal and "" or "-"))
                -- (21/10) a column may colour its own cells (`colour(v, row)` -> a colour object of the game, or nil)
                K.Colour(cell, (c.colour and not isTotal and c.colour(v, data)) or (c.grey and LIGHTGRAY_FONT_COLOR or HIGHLIGHT_FONT_COLOR))
            end
        end
        if spec.selected ~= nil and spec.selected == data then
            r:LockHighlight()
        elseif r.UnlockHighlight then
            r:UnlockHighlight()
        end
        y = y + ROW
    end
    local item = { kind = "table", spec = spec, frames = frames, head = head, rows = shown }
    page.items[#page.items + 1] = item
    local h = y - y0
    if not noAdvance then page.y = y end
    spec.frames, spec.head = frames, head
    return h
end

--------------------------------------------------------------------------------
-- The chart
--------------------------------------------------------------------------------
---A chart over time. `spec`: { height, from, to (seconds of the run), x, width, series = { { label, colour = { r, g, b },
---points = { { s, e, v } }, fill = true|nil, bars = true|nil } }, marks = { { t, atlas | texture } } }.
---A series is drawn as the site draws a line: flat over each span at its value, down to the floor between spans
---that do not touch; `fill` paints under it (the site's stacked areas, one colour). Returns its height.
function Report.Chart(page, spec, noAdvance)
    local K = Kit()
    local x, width = spec.x or 0, spec.width or page.width
    local height = spec.height or 110
    local from, to = spec.from or 0, spec.to or 1
    if to <= from then to = from + 1 end
    local frame = Take(page, "chart", function()
        local c = CreateFrame("Frame", nil, page.child)
        c.bg = c:CreateTexture(nil, "BACKGROUND")
        c.bg:SetColorTexture(0, 0, 0, 0.35)
        c.textures = {}
        c.labels = {}
        c.legend = {}
        return c
    end)
    frame:SetPoint("TOPLEFT", x, -page.y)
    frame:SetSize(width, height)
    local plotW = width - AXIS_LEFT - 8
    local plotH = height - AXIS_BOTTOM - 18          -- 18 at the top for the legend
    local top0 = 18
    frame.bg:ClearAllPoints()
    frame.bg:SetPoint("TOPLEFT", AXIS_LEFT, -top0)
    frame.bg:SetSize(plotW, plotH)
    for _, t in ipairs(frame.textures) do t:Hide() end
    for _, l in ipairs(frame.labels) do l:Hide() end
    for _, l in ipairs(frame.legend) do l:Hide() end
    local used, usedLabels = 0, 0
    local function Tex(layer)
        used = used + 1
        local t = frame.textures[used]
        if not t then t = frame:CreateTexture(nil, layer or "ARTWORK"); frame.textures[used] = t end
        t:ClearAllPoints()
        t:SetDrawLayer(layer or "ARTWORK")
        t:SetVertexColor(1, 1, 1, 1)
        t:SetAlpha(1)
        t:Show()
        return t
    end
    local function Label(template, justify)
        usedLabels = usedLabels + 1
        local l = frame.labels[usedLabels]
        if not l then l = K.Text(frame, template or "GameFontDisableSmall", justify); frame.labels[usedLabels] = l end
        l:ClearAllPoints()
        l:SetJustifyH(justify or "LEFT")
        l:Show()
        return l
    end

    local top = 0
    for _, s in ipairs(spec.series or {}) do
        for _, p in ipairs(s.points or {}) do if p[3] and p[3] > top then top = p[3] end end
    end
    if spec.top then top = spec.top end
    local function X(t) return AXIS_LEFT + math.max(0, math.min(plotW, (t - from) / (to - from) * plotW)) end
    local function Y(v) return top0 + plotH - (top > 0 and math.max(0, math.min(1, v / top)) * plotH or 0) end

    -- the grid: three lines across, the amounts at the left
    for i = 0, 2 do
        local v = top * i / 2
        local g = Tex("BORDER")
        g:SetColorTexture(1, 1, 1, i == 0 and 0.25 or 0.08)
        g:SetPoint("TOPLEFT", frame, "TOPLEFT", AXIS_LEFT, -Y(v))
        g:SetSize(plotW, 1)
        local l = Label("GameFontDisableSmall", "RIGHT")
        l:SetPoint("RIGHT", frame, "TOPLEFT", AXIS_LEFT - 4, -Y(v))
        l:SetText(top > 0 and K.Fmt(v) or "")
    end
    -- the time along the bottom: five marks
    for i = 0, 4 do
        local t = from + (to - from) * i / 4
        local l = Label("GameFontDisableSmall", i == 0 and "LEFT" or (i == 4 and "RIGHT" or "CENTER"))
        local px = X(t)
        if i == 0 then l:SetPoint("TOPLEFT", frame, "TOPLEFT", px, -(top0 + plotH + 2))
        elseif i == 4 then l:SetPoint("TOPRIGHT", frame, "TOPLEFT", px, -(top0 + plotH + 2))
        else l:SetPoint("TOP", frame, "TOPLEFT", px, -(top0 + plotH + 2)) end
        l:SetText(K.Clock(t))
    end
    -- the series
    local THICK = 2
    for _, s in ipairs(spec.series or {}) do
        local r, g, b = unpack(s.colour or { 1, 1, 1 })
        local prevE, prevY
        for _, p in ipairs(s.points or {}) do
            local ps, pe, v = p[1], p[2], p[3] or 0
            if pe > from and ps < to then
                local x1, x2, y = X(ps), X(pe), Y(v)
                local floor = Y(0)
                if s.bars then
                    local f = Tex("ARTWORK")
                    f:SetColorTexture(r, g, b, 0.85)
                    f:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, -y)
                    f:SetSize(math.max(1, x2 - x1 - 1), math.max(1, floor - y))
                elseif s.fill then
                    local f = Tex("ARTWORK")
                    f:SetColorTexture(r, g, b, 0.35)
                    f:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, -y)
                    f:SetSize(math.max(1, x2 - x1), math.max(1, floor - y))
                end
                local h = not s.bars and Tex("OVERLAY") or nil
                if h then
                    h:SetColorTexture(r, g, b, 1)
                    h:SetPoint("TOPLEFT", frame, "TOPLEFT", x1, -(y - THICK / 2))
                    h:SetSize(math.max(1, x2 - x1), THICK)
                end
                -- up from the floor (or from the span before, when they touch) at the start
                local fromY = (prevE and math.abs(prevE - ps) < 1.5) and prevY or floor
                if h and math.abs(fromY - y) >= 1 then
                    local v1 = Tex("OVERLAY")
                    v1:SetColorTexture(r, g, b, 1)
                    v1:SetPoint("TOPLEFT", frame, "TOPLEFT", x1 - THICK / 2, -math.min(fromY, y))
                    v1:SetSize(THICK, math.abs(fromY - y))
                end
                -- down to the floor at the end, unless the next span starts here
                prevE, prevY = pe, y
            end
        end
        -- the closing drops: every span not followed by one that touches it goes back to the floor
        local pts = s.points or {}
        for i, p in ipairs(s.bars and {} or pts) do
            local nxt = pts[i + 1]
            if p[2] > from and p[1] < to and not (nxt and math.abs(nxt[1] - p[2]) < 1.5) then
                local y, floor = Y(p[3] or 0), Y(0)
                if floor - y >= 1 then
                    local v2 = Tex("OVERLAY")
                    v2:SetColorTexture(r, g, b, 1)
                    v2:SetPoint("TOPLEFT", frame, "TOPLEFT", X(p[2]) - THICK / 2, -y)
                    v2:SetSize(THICK, floor - y)
                end
            end
        end
    end
    -- the marks (deaths) on the floor
    for _, m in ipairs(spec.marks or {}) do
        if m[1] >= from and m[1] <= to then
            local t = Tex("OVERLAY")
            t:SetSize(14, 14)
            t:SetPoint("CENTER", frame, "TOPLEFT", X(m[1]), -(top0 + plotH - 7))
            if m.atlas then t:SetAtlas(m.atlas) else t:SetTexture(m.texture) end
        end
    end
    -- the legend at the top, in the colour of each series
    local lx = AXIS_LEFT
    for i, s in ipairs(spec.series or {}) do
        if s.label then
            local l = frame.legend[i]
            if not l then l = K.Text(frame, "GameFontHighlightSmall"); frame.legend[i] = l end
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", frame, "TOPLEFT", lx, -2)
            l:SetText("— " .. s.label)
            l:SetTextColor(unpack(s.colour or { 1, 1, 1 }))
            l:Show()
            lx = lx + (l.GetStringWidth and tonumber(l:GetStringWidth()) or 0) + 18
            if lx < AXIS_LEFT + i * 10 then lx = AXIS_LEFT + i * 150 end    -- the harness has no widths
        end
    end
    if spec.note then
        local l = Label("GameFontDisableSmall", "RIGHT")
        l:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -2)
        l:SetText(spec.note)
    end
    page.items[#page.items + 1] = { kind = "chart", spec = spec, frame = frame, top = top }
    spec.frame, spec.max = frame, top
    if not noAdvance then page.y = page.y + height + GAP end
    return height + GAP
end

---Leaves a gap.
function Report.Space(page, h) page.y = page.y + (h or GAP) end
