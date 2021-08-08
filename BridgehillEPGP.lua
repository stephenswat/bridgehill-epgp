local _, data = ...

local Priorities = {
    HIGH = 3,
    MEDIUM = 2,
    LOW = 1
}

local roll_state = {}

local function reset_roll_state()
    roll_state.rolling_item = nil
    roll_state.member_rolls = {}
    roll_state.candidates = {}
    roll_state.ticker = nil
end

reset_roll_state()

local function clean_name(name)
    local dash = name:find('-')

    if dash then
        return name:sub(1, dash - 1)
    else
        return name
    end
end

local function get_announce_target(warn)
    if warn and (UnitIsGroupLeader('player') or UnitIsGroupAssistant('player')) then
        return 'RAID_WARNING'
    else
        return 'RAID'
    end
end

local function send_whisper(msg, target)
    local fmsg = 'BH EPHP: ' .. msg

    if target == UnitName('player') then
        print(fmsg)
    else
        SendChatMessage(fmsg, "WHISPER", nil, target)
    end
end

local function send_message(msg, warn)
    SendChatMessage('BH EPGP: ' .. msg, get_announce_target(warn), nil, nil)
end

local function do_finish_roll()
    local rolls = {}

    for name, prio in pairs(roll_state.member_rolls) do
        if not rolls[prio] then
            rolls[prio] = {}
        end

        table.insert(rolls[prio], name)
    end

    local highest = nil

    if rolls[Priorities.HIGH] then
        highest = rolls[Priorities.HIGH]
        send_message('Bidding ended on HIGH priority!', false)
    elseif rolls[Priorities.MEDIUM] then
        highest = rolls[Priorities.MEDIUM]
        send_message('Bidding ended on MEDIUM priority!', false)
    elseif rolls[Priorities.LOW] then
        highest = rolls[Priorities.LOW]
        send_message('Bidding ended on LOW priority!', false)
    end

    if highest then
        local candidates = ""

        for _, name in ipairs(highest) do
            candidates = candidates .. ' ' .. clean_name(name)
        end

        send_message('Bidders in this category:' .. candidates, false)
    else
        send_message('Nobody has bid on this item.', false)
    end

    reset_roll_state()
end

local function handle_tick()
    if not roll_state.ticker then
        -- roll was cancelled, shouldn't be reachable but just in case
        return
    end

    local iter = roll_state.ticker._remainingIterations - 1

    if iter == 0 then
        do_finish_roll()
    elseif iter <= 3 then
        send_message('{rt1} ' .. tostring(iter) .. ' {rt1}', false)
    end
end

local function do_start_roll(item_link, duration)
    roll_state.rolling_item = item_link

    for n = 1, GetNumGroupMembers() do
        local name = GetRaidRosterInfo(n)
        roll_state.candidates[name] = true
    end

    local s, e = string.find(item_link, '|H([^|]*)|h')
    local _, itemId = strsplit(":", string.sub(item_link, s+2, e-2))

    local priceData = data.items[tonumber(itemId)]

    local extraStr = ""

    if priceData ~= nil then
        extraStr = extraStr .. 'GP value ' .. tostring(priceData.price)

        if priceData.prio ~= nil then
            extraStr = extraStr .. ", prio " .. priceData.prio
        end
    end

    if extraStr ~= "" then
        extraStr = extraStr .. ", "
    end

    extraStr = extraStr .. "bid time " .. tostring(duration) .. ' seconds'

    send_message('Bid for ' .. item_link .. ' (' .. extraStr .. ')', true)

    roll_state.ticker = C_Timer.NewTicker(1, handle_tick, duration)
end

local function handle_msg(msg, player)
    player = clean_name(player)

    if roll_state.rolling_item == nil then
        return
    end

    if not roll_state.candidates[clean_name(player)] then
        return
    end

    if msg == "+" then
        roll_state.member_rolls[player] = Priorities.HIGH
        send_whisper("Your bid has been recorded as HIGH priority!", player)
    elseif msg == "=" then
        roll_state.member_rolls[player] = Priorities.MEDIUM
        send_whisper("Your bid has been recorded as MEDIUM priority!", player)
    elseif msg == "-" then
        roll_state.member_rolls[player] = Priorities.LOW
        send_whisper("Your bid has been recorded as LOW priority!", player)
    else
        send_whisper("Your bid was not recognised!", player)
    end
end

local function do_cancel_roll()
    if roll_state.ticker then
        roll_state.ticker:Cancel()
    end

    send_message('{rt7} Cancelled bidding for ' .. roll_state.rolling_item .. '!', false)
    reset_roll_state()
end

local function event_handler(self, event, ...)
    if event == 'CHAT_MSG_WHISPER' then
        handle_msg(...)
    end
end

local frame = CreateFrame('frame', 'BridgehillEPGPFrame')
frame:RegisterEvent('CHAT_MSG_WHISPER')
frame:SetScript('OnEvent', event_handler)

SLASH_BHEPGP1 = "/bh"
function SlashCmdList.BHEPGP(arg)
    if not IsInRaid() then
        print('You are not in a raid!')
        return
    end

    local cmd = nil
    local rest = nil

    local space = arg:find(' ')
    if space then
        cmd = arg:sub(1, space - 1)
        rest = arg:sub(space + 1)
    else
        cmd = arg
    end

    if cmd == 'start' and rest then
        if roll_state.rolling_item == nil then
            do_start_roll(rest, 20)
        else
            print('There is an ongoing bid for ' .. roll_state.rolling_item)
        end
    elseif cmd == 'cancel' then
        if roll_state.rolling_item then
            do_cancel_roll()
        else
            print('There is no ongoing bid')
            reset_roll_state()
        end
    else
        print('Usage: /bh start [item] | /bh cancel')
    end
end
