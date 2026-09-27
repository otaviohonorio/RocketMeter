-- RocketMeter | Donate.lua
-- The "Donate" link, the same in every Rocket addon.
--
-- The user (26/09): *"tem vários addons que sempre tem algum menu nele em algum canto com link de
-- donate usando paypal"*, then *"vamos fazer sim"* -- knowing Blizzard's add-on policy (rule 5)
-- asks for donation requests to stay off the game; it is his call.
--
-- An addon cannot open a browser. So, as Baganator does (`Core/Dialogs.lua:40-70`), the link goes in
-- a box, already selected: Ctrl+C copies it, and the dialog closes by itself after the copy, as in
-- ArchonTooltip (`Utils.lua:225-260`). The box is the game's own popup (`StaticPopup` with an edit
-- box, reached through `GetEditBox()` in 12.x, as BugSack does).
--
-- Currency: BRL when the game is in Portuguese (Brazil), USD everywhere else (user's rule).
local ADDON, ns = ...
local L = ns.L

local BASE = "https://www.paypal.com/donate/?business=HH4PHH48DPG9J&no_recurring=0&currency_code="
local POPUP = "ROCKETMETER_DONATE"

function ns.DonateURL()
    local brl = GetLocale and GetLocale() == "ptBR"
    return BASE .. (brl and "BRL" or "USD")
end

local function EditBoxOf(dialog)
    if dialog.GetEditBox then return dialog:GetEditBox() end
    return dialog.editBox or (dialog.GetName and _G[dialog:GetName() .. "EditBox"])
end

function ns.ShowDonate()
    if not (StaticPopupDialogs and StaticPopup_Show) then return end
    if not StaticPopupDialogs[POPUP] then
        StaticPopupDialogs[POPUP] = {
            text = L["Thank you for supporting Rocket Meter! Press Ctrl+C to copy the link, then paste it in your browser."],
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
                box:SetText(ns.DonateURL())
                box:HighlightText()
                box:SetFocus()
                -- The popup's box is SHARED with every other popup of the game: the scripts go on
                -- here and come off in OnHide, or they would follow into someone else's dialog.
                box:SetScript("OnKeyDown", function(_, key)
                    if key == "C" and IsControlKeyDown and IsControlKeyDown() then
                        C_Timer.After(0.1, function()
                            self:Hide()
                            ns.Print(L["Link copied — paste it in your browser."])
                        end)
                    end
                end)
                -- Typing over it would lose the link: whatever is typed, the link comes back.
                box:SetScript("OnTextChanged", function(b, userInput)
                    if userInput then
                        b:SetText(ns.DonateURL())
                        b:HighlightText()
                    end
                end)
            end,
            OnHide = function(self)
                local box = EditBoxOf(self)
                if box then
                    box:SetScript("OnKeyDown", nil)
                    box:SetScript("OnTextChanged", nil)
                end
            end,
            EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        }
    end
    StaticPopup_Show(POPUP)
end

---THE DISCREET LINK (27/09). The user: *"os comandos não precisa (...) tem que ser na janela do addon
---mesmo, em algum canto ou menu (...) um pouco mais discreto sem chamar atenção"*. A small word in
---the game's disabled grey (`GameFontDisableSmall`) -- "Support the project", not
---"Donate" (the user, 27/09: *"doar é feio"*) -- that lights up on hover, with a tooltip saying
---what it does -- no button art, nothing competing with the addon's own controls.
---The PayPal monogram (27/09, the user: *"poderia ter um logo do paypal"*). A PNG in the addon's
---own `Textures/` -- the retail client loads PNG, as Details (`images/patreon_p_logo.png`) and
---KagrokLauncherCore (`Media/Social/patreon.png`) already ship. The glyph is simple-icons' `paypal`
---(CC0) in PayPal's two blues, rendered at 64x64.
ns.PAYPAL_ICON = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\PayPal.png"
local ICON = 14

---THE SUPPORT LINE (27/09), the standard for every Rocket window, current and future. The user:
---*"esse item tem que ser padrão em todos os addons atuais e futuros, deixa ele numa linha sozinho no
---final da janela"*. A line of its own at the very bottom, centred, below everything else: the
---window grows by `DONATE_ROW` and whatever lived at the bottom moves up by the same amount.
ns.DONATE_ROW = 22            -- 5 below + the 14 of the link + 3 above
local DONATE_Y = 5

function ns.DonateLink(parent)
    local b = CreateFrame("Button", nil, parent)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ICON, ICON)
    b.icon:SetPoint("LEFT")
    b.icon:SetTexture(ns.PAYPAL_ICON)
    b.icon:SetAlpha(0.8)                                 -- discreet until the mouse comes
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.text:SetPoint("LEFT", b.icon, "RIGHT", 3, 0)
    b.text:SetText(L["Support the project"])
    local w = b.text.GetStringWidth and b.text:GetStringWidth()
    if type(w) ~= "number" or w <= 0 then w = 30 end     -- by TYPE: the harness answers a table
    b:SetSize(ICON + 3 + w + 4, ICON)
    b:SetScript("OnEnter", function(self)
        self.icon:SetAlpha(1)
        self.text:SetFontObject("GameFontHighlightSmall")
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Support the project"], 1, 1, 1)
        GameTooltip:AddLine(L["Opens the donation link, ready to copy."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.icon:SetAlpha(0.8)
        self.text:SetFontObject("GameFontDisableSmall")
        GameTooltip:Hide()
    end)
    b:SetScript("OnClick", function() ns.ShowDonate() end)
    return b
end

---The link on its own line at the bottom of `window` (see `DONATE_ROW`). Every window uses this;
---`DonateLink` alone is for a place that is not a window (none today).
function ns.DonateFooter(window)
    local b = ns.DonateLink(window)
    b:SetPoint("BOTTOM", window, "BOTTOM", 0, DONATE_Y)
    return b
end
