-- RocketMeter | Donate.lua
-- The support line at the bottom of every window, the same in every Rocket addon: the "Donate"
-- link and, beside it, "Report a problem".
--
-- The user (26/09) asked for a donation link with PayPal in a corner of the window, then
-- *"vamos fazer sim"* -- knowing Blizzard's add-on policy (rule 5)
-- asks for donation requests to stay off the game; it is his call.
--
-- An addon cannot open a browser. So the link goes in a box, already selected: Ctrl+C copies it,
-- and the dialog closes by itself after the copy. The box is the game's own popup (`StaticPopup`
-- with an edit box, reached through `GetEditBox()` in 12.x).
--
-- Currency: BRL when the game is in Portuguese (Brazil), USD everywhere else (user's rule).
local ADDON, ns = ...
local L = ns.L

local BASE = "https://www.paypal.com/donate/?business=HH4PHH48DPG9J&no_recurring=0&currency_code="
local POPUP = "ROCKETMETER_DONATE"
local REPORT_POPUP = "ROCKETMETER_REPORT"

function ns.DonateURL()
    local brl = GetLocale and GetLocale() == "ptBR"
    return BASE .. (brl and "BRL" or "USD")
end

local function EditBoxOf(dialog)
    if dialog.GetEditBox then return dialog:GetEditBox() end
    return dialog.editBox or (dialog.GetName and _G[dialog:GetName() .. "EditBox"])
end

---The game's popup with a link in its box, already selected.
---@param text string what the dialog says
---@param url function the link, asked for when the dialog opens
local function CopyBox(text, url)
    return {
        text = text,
        button2 = CLOSE,
        hasEditBox = true,
        editBoxWidth = 350,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
        OnShow = function(self)
            local box = EditBoxOf(self)
            if not box then return end
            box:SetText(url())
            box:HighlightText()
            box:SetFocus()
            -- The popup's box is SHARED with every other popup of the game. (14/10) Its own
            -- OnTextChanged is the game's (it feeds "DELETE" to destroy an item, and the name
            -- autocomplete): never replaced, the dialog's EditBoxOnTextChanged below is the hook.
            -- It has no OnKeyDown of its own; ours goes on here and the original comes back in
            -- OnHide.
            -- Shown again while open (another place chosen): the original was already kept.
            if not self.rocketHooked then
                self.rocketKeyDown, self.rocketHooked = box:GetScript("OnKeyDown"), true
            end
            box:SetScript("OnKeyDown", function(_, key)
                if key == "C" and IsControlKeyDown and IsControlKeyDown() then
                    C_Timer.After(0.1, function()
                        self:Hide()
                        ns.Print(L["Link copied — paste it in your browser."])
                    end)
                end
            end)
        end,
        -- Typing over it would lose the link: whatever is typed, the link comes back.
        EditBoxOnTextChanged = function(box)
            if box:GetText() ~= url() then
                box:SetText(url())
                box:HighlightText()
            end
        end,
        OnHide = function(self)
            local box = EditBoxOf(self)
            if box then
                box:SetScript("OnKeyDown", self.rocketKeyDown)
                self.rocketKeyDown, self.rocketHooked = nil, nil
            end
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
    }
end

function ns.ShowDonate()
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    if not StaticPopupDialogs[POPUP] then
        StaticPopupDialogs[POPUP] = CopyBox(
            L["Thank you for supporting Rocket Meter! Press Ctrl+C to copy the link, then paste it in your browser."],
            ns.DonateURL)
    end
    StaticPopup_Show(POPUP)
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

-- The place chosen, for the dialog that is open.
local reporting

---The addon's version, which is the first thing a report needs.
function ns.ReportVersion()
    local v = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")
    return type(v) == "string" and v ~= "" and v or "?"
end

---The box with the link of one place, ready to copy.
function ns.ShowReport(site)
    if not (site and StaticPopupDialogs and StaticPopup_Show) then return end
    reporting = site
    if not StaticPopupDialogs[REPORT_POPUP] then
        StaticPopupDialogs[REPORT_POPUP] = CopyBox(
            L["Rocket Meter %s — report a problem on %s.|n|nPress Ctrl+C to copy the link, then paste it in your browser. Say what you were doing and what happened."],
            function() return reporting and reporting.url or "" end)
    end
    StaticPopup_Show(REPORT_POPUP, ns.ReportVersion(), site.name)
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
ns.PAYPAL_ICON = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\PayPal.png"
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

function ns.DonateLink(parent)
    return Link(parent, L["Support the project"], L["Click: open the donation link, ready to copy"],
        function(icon) icon:SetTexture(ns.PAYPAL_ICON) end,
        function() ns.ShowDonate() end)
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
    local b = ns.DonateLink(window)
    local r = ns.ReportLink(window)
    -- The middle of the pair on the middle of the window: the first link sits half of what is
    -- at its right to the left of it.
    b:SetPoint("BOTTOM", window, "BOTTOM", -(LINK_GAP + r.linkWidth) / 2, DONATE_Y)
    r:SetPoint("LEFT", b, "RIGHT", LINK_GAP, 0)
    b.report = r
    return b
end
