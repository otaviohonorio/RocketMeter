-- RocketMeter | Donate.lua
-- (04/11/2026) NO DONATION REQUEST IN THE GAME. The user: "como eu quero receber pelo curseforge e tem várias regras
-- (...) temos que tirar das telas do addon o apoiar projeto, deixar somente o reportar problema". Researched the same
-- day: Blizzard's UI Add-On Development Policy says add-ons "may not solicit donations" in the game (rule 5); the
-- CurseForge rewards program pays by the project's popularity, and the project PAGE may carry the donation button
-- (CurseForge's description guidelines). So the footer is only "Report a problem", centred, on the same line (the
-- windows keep their height: DONATE_ROW stays), and the `## X-Donate` line left every .toc.
-- The support line at the bottom of every window, the same in every Rocket addon: the "Donate"
-- link and, beside it, "Report a problem".
--
-- The user (26/09) asked for a donation link with PayPal in a corner of the window, then
-- *"vamos fazer sim"* -- knowing Blizzard's add-on policy (rule 5)
-- asks for donation requests to stay off the game; it is his call.
--
-- An addon cannot open a browser. So the link goes in a box, already selected: Ctrl+C copies it,
-- and the dialog closes by itself after the copy. (18/11/2026) The box is the family's (`Style.Ask` in Style.lua), never
-- the game's `StaticPopup`: a game dialog opened by an addon joins the game's one list of dialogs, and the game then
-- blamed the addon for its own protected calls (measured in the Rocket Swap, RocketSwap/Dialog.lua).
--
-- Currency: BRL when the game is in Portuguese (Brazil), USD everywhere else (user's rule).
local ADDON, ns = ...
local L = ns.L

local REPORT_POPUP = "ROCKETMETER_REPORT"


---The box with a link in it, already selected, ready for Ctrl+C (the family's box, `Style.Ask`). Without the box,
---the link goes to the chat.
---@param key string what the box is (Style.AskHide(key) closes only it)
---@param text string what the box says
---@param url string the link
local function CopyBox(key, text, url)
    if ns.Style and ns.Style.Ask(key, { text = text, url = url, copied = L["Link copied — paste it in your browser."] }) then
        return true
    end
    ns.Print(url)
    return false
end


--------------------------------------------------------------------------------
-- "Report a problem"
--------------------------------------------------------------------------------
-- (!) WHERE A PROBLEM IS REPORTED (asked on 27/09, asked again on 28/09). The user: *"nos addons
-- precisamos ter um lugar onde o usuário posso reportar um bug, que jogue para o cursefoge ou
-- github, o usuário escolhe, pode ficar junto com o apoiar projeto"*.
--
-- The places, in the order of the menu. GitHub takes it in the repository's issues. CurseForge
-- has no tracker of its own (looked at on 28/09: the project page has Description, Comments,
-- Files, Gallery and Relations, and its "Report" button reports the PROJECT to moderation): there
-- a problem is told in the comments.
--
ns.REPORT = {
    { name = "GitHub", url = "https://github.com/otaviohonorio/RocketMeter/issues" },
    { name = "CurseForge", url = "https://www.curseforge.com/wow/addons/rocketmeter/comments" },
}

---The addon's version, which is the first thing a report needs.
function ns.ReportVersion()
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    return type(v) == "string" and v ~= "" and v or "?"
end

---The box with the link of one place, ready to copy.
function ns.ShowReport(site)
    if not site then return end
    CopyBox(REPORT_POPUP, L["Rocket Meter %s — report a problem on %s.|n|nPress Ctrl+C to copy the link, then paste it in your browser. Say what you were doing and what happened."]:format(ns.ReportVersion(), site.name), site.url or "")
end

---The player chooses where: the game's menu with the places. With one place only, or on a
---client without the menu, the box opens at once.
function ns.ReportMenu(owner)
    if #ns.REPORT < 2 or not (MenuUtil and MenuUtil.CreateContextMenu) then
        return ns.ShowReport(ns.REPORT[1])
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Report a problem on"])
        for _, site in ipairs(ns.REPORT) do
            root:CreateButton(site.name, function() ns.ShowReport(site) end)
        end
    end)
end

--------------------------------------------------------------------------------
-- The links
--------------------------------------------------------------------------------
---THE DISCREET LINK (27/09). The user: *"os comandos não precisa (...) tem que ser na janela do addon
---mesmo, em algum canto ou menu (...) um pouco mais discreto sem chamar atenção"*. A small word in
---the game's disabled grey (`GameFontDisableSmall`) -- "Support the project", not
---"Donate" (the user, 27/09: *"doar é feio"*) -- that lights up on hover, with a tooltip saying
---what it does -- no button art, nothing competing with the addon's own controls.
---The PayPal monogram (27/09, the user: *"poderia ter um logo do paypal"*). A PNG in the addon's
---own `Textures/` -- the retail client loads PNG.
---The glyph is simple-icons' `paypal`
---(CC0) in PayPal's two blues, rendered at 64x64.
-- The game's own alert glyph (20x20 in the art, seen with `tools/ver_atlas.py`).
ns.REPORT_ICON = "gmchat-icon-alert"
local ICON = 14

---THE SUPPORT LINE (27/09), the standard for every Rocket window, current and future. The user:
---*"esse item tem que ser padrão em todos os addons atuais e futuros, deixa ele numa linha sozinho no
---final da janela"*. A line of its own at the very bottom, centred, below everything else: the
---window grows by `DONATE_ROW` and whatever lived at the bottom moves up by the same amount.
ns.DONATE_ROW = 22            -- 5 below + the 14 of the link + 3 above
local DONATE_Y = 5
-- Between the two links of the line: more than the 3 between a glyph and its word, so each
-- glyph reads as belonging to the word at its right.
local LINK_GAP = 18
ns.LINK_GAP = LINK_GAP

---A link of the support line: a glyph, a word in the game's grey, and a tooltip.
local function Link(parent, word, tip, icon, click)
    local b = CreateFrame("Button", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT")
    icon(b.icon)
    b.icon:SetAlpha(0.8)                                 -- discreet until the mouse comes
    -- (14/10) The game's light grey until the mouse comes (the rule of 13/10: never the disabled
    -- grey on the art).
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetTextColor(LIGHTGRAY_FONT_COLOR:GetRGB())
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
    b.text:SetText(word)
    local w = b.text.GetStringWidth and b.text:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then w = 30 end     -- by TYPE: the harness answers a table
    b.linkWidth = ICON + 3 + w + 4
    b:SetSize(b.linkWidth, ICON)
    b:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        self.text:SetTextColor(HIGHLIGHT_FONT_COLOR:GetRGB())
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- (14/10) The workspace standard: the title, and one green line per action, its verb
        -- in the infinitive.
        GameTooltip_SetTitle(GameTooltip, word)
        GameTooltip_AddInstructionLine(GameTooltip, tip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.8)
        self.text:SetTextColor(LIGHTGRAY_FONT_COLOR:GetRGB())
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", click)
    return b
end


function ns.ReportLink(parent)
    return Link(parent, L["Report a problem"], L["Click: choose where to report a problem"],
        function(icon) icon:SetAtlas(ns.REPORT_ICON) end,
        function(self) ns.ReportMenu(self) end)
end

---The support line at the bottom of `window` (see `DONATE_ROW`): the two links side by side,
---the PAIR centred. Every window uses this; `DonateLink` alone is for a place that is not a
---window (none today).
---@return table donate the support link; the report link is its `report`
function ns.DonateFooter(window)
    local r = ns.ReportLink(window)
    r:SetPoint("BOTTOM", window, "BOTTOM", 0, DONATE_Y)
    r.report = r   -- the callers knew the report link as the footer's `report`
    return r
end
