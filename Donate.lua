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
