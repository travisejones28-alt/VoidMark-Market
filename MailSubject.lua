-- Mail subject autofill: attach items (or add gold) and an empty subject is
-- filled for you ("Linen Cloth", "Linen Cloth and 4 more", "Gold"), so Send
-- works without typing. Anything you type yourself is never changed.
local _, M = ...
M = M or {}
local S = {}
M.MailSubject = S
local lastAuto   -- the subject we filled in; replaced as attachments change

local function Readable(v)
    if type(issecretvalue) == 'function' then
        local ok, secret = pcall(issecretvalue, v)
        if not ok or secret then return nil end
    end
    return v
end

-- Subject for what is attached right now, or nil if nothing is.
function S.Subject()
    local names, seen = {}, {}
    local max = tonumber(ATTACHMENTS_MAX_SEND) or 12
    if type(GetSendMailItem) == 'function' then
        for i = 1, max do
            local ok, name = pcall(GetSendMailItem, i)
            name = ok and Readable(name)
            if type(name) == 'string' and name ~= '' and not seen[name] then
                seen[name] = true; names[#names + 1] = name
            end
        end
    end
    if #names == 1 then return names[1] end
    if #names > 1 then return names[1] .. ' and ' .. (#names - 1) .. ' more' end
    local ok, money = pcall(GetSendMailMoney or function() return 0 end)
    if ok and (tonumber(Readable(money)) or 0) > 0 then return 'Gold' end
end

function S.Fill()
    local box = _G.SendMailSubjectEditBox
    if not box or not box.GetText then return end
    local current = Readable(box:GetText()) or ''
    if current ~= '' and current ~= lastAuto then return end  -- you typed it: leave it
    local subject = S.Subject()
    if subject == current then return end
    if not subject then
        if current ~= '' and current == lastAuto then box:SetText('') end
        lastAuto = nil
    else
        box:SetText(subject); lastAuto = subject
    end
    -- Let the Send button notice the new subject.
    if type(SendMailFrame_CanSend) == 'function' then pcall(SendMailFrame_CanSend) end
end

local f = CreateFrame('Frame')
for _, e in ipairs({ 'MAIL_SEND_INFO_UPDATE', 'MAIL_SHOW', 'MAIL_SEND_SUCCESS' }) do pcall(f.RegisterEvent, f, e) end
f:SetScript('OnEvent', function(_, event)
    if event == 'MAIL_SEND_SUCCESS' then lastAuto = nil else S.Fill() end
end)
-- Money typed into the gold boxes doesn't fire an event; the game's update does.
if hooksecurefunc then
    if type(SendMailFrame_Update) == 'function' then hooksecurefunc('SendMailFrame_Update', function() pcall(S.Fill) end) end
    if type(SendMailFrame_CanSend) == 'function' then
        hooksecurefunc('SendMailFrame_CanSend', function() if not S.busy then S.busy = true; pcall(S.Fill); S.busy = false end end)
    end
end
