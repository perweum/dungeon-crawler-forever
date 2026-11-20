-- "Copy / paste runs" (D-070): your runs as text in a small window with the text already selected (Ctrl+C), and the same box takes pasted text
-- (Ctrl+V, then Import). This moves highscore runs between your own machines, to a friend, or into a post, without any server. Opened from the
-- Highscore tab and with /dm runs or /dm runs import. The format and the checks are in Comms.lua (ns.RunsExport / ns.RunsImport).
local _, ns = ...

local function plural(n, word) return format("%d %s%s", n, word, n == 1 and "" or "s") end

function ns.ShowRunsIO(startEmpty)
    local text, n = ns.RunsExport()
    local f = DungeonMapRunsFrame
    if not f then
        f = ns.NewWindow("DungeonMapRunsFrame")
        f:SetSize(520, 320)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        if f.SetTitle then f:SetTitle("Copy / paste runs") end
        f.info = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.info:SetPoint("TOPLEFT", 16, -34)
        f.info:SetPoint("TOPRIGHT", -16, -34)
        f.info:SetJustifyH("LEFT")
        f.info:SetWordWrap(true)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -96)
        sf:SetPoint("BOTTOMRIGHT", -34, 76)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(460)
        eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.edit = eb
        f.result = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.result:SetPoint("BOTTOMLEFT", 16, 46)
        f.result:SetPoint("BOTTOMRIGHT", -16, 46)
        f.result:SetJustifyH("LEFT")
        f.copy = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.copy:SetSize(130, 24)
        f.copy:SetPoint("BOTTOMLEFT", 16, 12)
        f.copy:SetText("Select all to copy")
        f.copy:SetScript("OnClick", function() f.edit:SetFocus(); f.edit:HighlightText() end)
        f.import = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.import:SetSize(110, 24)
        f.import:SetPoint("LEFT", f.copy, "RIGHT", 8, 0)
        f.import:SetText("Import")
        f.import:SetScript("OnClick", function()
            local mine, others, held, bad = ns.RunsImport(f.edit:GetText())
            if mine + others + held + bad == 0 then
                f.result:SetText("Nothing to import: paste the text from the other machine into the box first.")
            else
                local parts = {}
                if mine > 0 then parts[#parts + 1] = plural(mine, "run of yours") end
                if others > 0 then parts[#parts + 1] = plural(others, "run") .. " by others" end
                local msg = #parts > 0 and ("Imported " .. table.concat(parts, " and ") .. ".") or "Nothing new."
                if held > 0 then msg = msg .. " " .. plural(held, "run") .. " already here." end
                if bad > 0 then msg = msg .. " " .. plural(bad, "line") .. " skipped (not valid for this version)." end
                f.result:SetText(msg)
                if ns.RefreshMap then pcall(ns.RefreshMap) end
            end
        end)
        f.close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.close:SetSize(90, 24)
        f.close:SetPoint("BOTTOMRIGHT", -16, 12)
        f.close:SetText("Close")
        f.close:SetScript("OnClick", function() f:Hide() end)
    end
    f.result:SetText("")
    if startEmpty or n == 0 then
        f.info:SetText("To bring runs from another machine: on that machine open this window (Highscore tab, Copy / paste runs, or /dm runs), press Ctrl+C, paste the text into a note or message to yourself, then paste it into the box here and press Import. Runs you already have are skipped.")
        f.edit:SetText("")
        f.edit:SetFocus()
    else
        f.info:SetText(format("%s ready. Press Ctrl+C to copy the text below and paste it on your other machine (or to a friend). To bring runs in here, replace the text with what you copied there and press Import.", plural(n, "run")))
        f.edit:SetText(text)
        f.edit:SetFocus()
        f.edit:HighlightText()
    end
    f:Show()
end
