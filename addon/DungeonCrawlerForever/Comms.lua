-- Sharing finished runs between players (D-063, D-066). Hidden addon messages only; nothing is shown to other players' chat. Nothing is sent before the
-- player has answered the sharing question (DungeonMapDB.shareAsked), and "Guild and friends only" (shareScope = "guild") never asks the group for runs.
--
-- Messages (tab separated, at most 255 bytes, first field is the kind and its version):
--   prefix DCFRun:  R1 inst wing route rv started total bracket(i|o) level size deaths wipes kills members by hop
--       kills = "i:time,..." (i = the boss's place in the route's boss keys sorted A-Z, times in base 36 seconds on the clock),
--       members = "name:classChar,..." (names escaped), the record's own player first
--   prefix DCFCtl:  D1 / D2 <boards>  a DIGEST: per board "inst.wing.bossSetVersion.i|o:runs held:best time (base 36)", up to DIGEST_BOARDS boards, split over
--                       messages. D1 is sent to a group / the guild / friends and is answered with the sender's own digest as D2 (never answered).
--                   Q1 <board:hashes,...>  "for these boards I hold runs with these short hashes: send me the others". The receiver of a digest sends
--                       a Q1 for the boards where the other side holds more runs, a better best time or a board we lack; the answer is the runs the
--                       asker lacks (best first, Q_PER_BOARD per board, Q_TOTAL in all) as ordinary R1 whispers. This replaces asking by date: it
--                       fills the gaps from both sides with a few small messages, and repeated meetings complete the picture.
--   prefix DCFCtl:  S1 <since>  (still answered, for 0.2.0 clients; nothing sends it any more)  "send me your best runs that finished after <since> (base 36)". The answer is by whisper and RELAYS what we hold, not only
--       our own runs, with these limits against bloat: only on request (nothing is pushed), only runs newer than the requester's newest minus 7 days, the
--       best PER_REPLY per board and REPLY_MAX in all, never the requester's own runs back, a run is passed on at most MAX_HOP times from its owner (hop),
--       one answer per sender per 10 minutes and ANSWER_BUDGET whispers per 10 minutes in all. Kept locally: the PER_BOARD best per board, nothing older
--       than 60 days, BOARD_MAX in all.
--                   H1 / H2  hello and answer between friends: a friend who answers has the addon and gets runs too
-- Where it goes: the group (PARTY / RAID / INSTANCE_CHAT) and the guild when a run is finished; a request for runs goes to the guild at login, from the
-- Highscore tab's button, and (scope "everyone" only) to a new group. Every channel has a gate like LayerSwap's: the first refusal of a kind (4 or 7)
-- closes it for the session. Friends: every online friend (character or Battle.net, same faction) gets an H1 once per 30 minutes; one who answers is
-- remembered for the session and gets finished runs and requests like the guild does. Received runs are checked against our own official routes and kept in DungeonMapDB.board
-- (capped); they are honour-system records (D-063), marked verified when a member of the run sent the same run as ours.
-- Every send result and receive is logged in DungeonMapDB.commsLog (60 entries) so OQ-025 can be answered from the saved variables.
local _, ns = ...

local PREFIX_REC, PREFIX_CTL = "DCFRun", "DCFCtl"
local MAX_MSG = 255
local SEND_GAP = 0.4        -- seconds between messages (the game holds back a burst per prefix)
local REPLY_MAX = 12        -- records in one answer to a request
local PER_REPLY = 3         -- of them, at most this many per board
local MAX_HOP = 2           -- a run is passed on at most this many times from its owner
local ANSWER_BUDGET = 60    -- answer whispers per 10 minutes, all requesters together
local PER_BOARD = 25        -- runs kept per board
local DIGEST_BOARDS = 24    -- boards in a digest
local QUERY_BOARDS = 6      -- boards one digest can make us ask about
local QUERY_HASHES = 12     -- run hashes sent per board in a query
local Q_PER_BOARD = 6       -- runs sent back per board for a query
local Q_TOTAL = 18          -- runs sent back for one query message
local REPLY_BUDGET = 30     -- digest replies (D2) per 10 minutes, all senders together
local MAX_AGE = 60 * 86400  -- runs older than this are dropped
local OVERLAP = 7 * 86400   -- a request looks this far back before the newest run it has
local REPLY_EVERY = 600     -- seconds before the same player gets another answer
local BOARD_MAX = 500       -- received records kept
local RECV_MAX, RECV_WINDOW = 40, 600 -- records accepted from one sender per window
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID", "DEATHKNIGHT", "MONK", "DEMONHUNTER", "EVOKER" }
local CLASS_AT = {}
for i, c in ipairs(CLASSES) do CLASS_AT[c] = i end

local gate, queue, batch = {}, {}, nil
local lastReply, recvCount = {}, {}
local budget = { n = 0, since = 0 }
local lastGuildAsk, lastGroupAsk = -1e9, -1e9
local syncReport = nil -- the answer to the Sync with guild button: { heard = {key=true}, runs = n, from = {key=true} } until the report is printed
local unknownNoted = false -- the "update the addon" hint has been shown this session
local peersSeen = {}   -- players with the addon who sent us a digest or runs this session (they have sharing on)
local askedUntil = 0 -- whispered runs from non-friends are taken only until this time (the answer to our own request)
local friendsNow, knownFriends, greeted = {}, {}, {} -- online friends by key; those who answered a hello; when each was greeted

local function norm(n) return ns.NormName(n) end
local function readable(v) return not (issecretvalue and issecretvalue(v)) end
local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a = pcall(fn, ...)
    if ok and readable(a) then return a end
    return nil
end

local function log(what, ...)
    if not DungeonMapDB then return end
    local l = DungeonMapDB.commsLog
    if not l then l = {}; DungeonMapDB.commsLog = l end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    l[#l + 1] = { t = time(), what = what, info = table.concat(parts, " ") }
    while #l > 60 do table.remove(l, 1) end
end

-- base 36 numbers keep the message short
local DIG = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    n = math.floor(tonumber(n) or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIG:sub(d + 1, d + 1) .. s
        n = (n - d) / 36
    end
    return s
end
local function fromB36(s) return tonumber(s, 36) end

local function esc(s) return (tostring(s):gsub("[%%,:\t\r\n|]", function(c) return string.format("%%%02X", c:byte()) end)) end
local function unesc(s) return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)) end

local function split(text)
    local out = {}
    for field in (text .. "\t"):gmatch("(.-)\t") do out[#out + 1] = field end
    return out
end

local function sortedKeys(route)
    local keys = {}
    for k in pairs(route.keys) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

-- the official route a record is on, from our own data (nil when the sender runs other route data)
-- The route a record is on: what counts is the SET OF BOSSES (the version is a hash of it), not the route's name. A route with the same id is taken
-- first; otherwise any route of ours with the same boss set (the sender may have a named route where we have "all regular bosses").
local function routeOf(inst, wing, routeId, rv)
    local found
    for _, r in ipairs(ns.OfficialRoutes(inst, wing ~= 0 and wing or nil)) do
        if r.version == rv then
            if r.id == routeId then return r end
            found = found or r
        end
    end
    if found then return found end
    return ns.RouteAlias(inst, wing, rv) -- (route, alias row): an old version that still counts
end

-- Encoding / decoding ---------------------------------------------------------------------------------------------------------------
function ns.CommsEncode(rec, hop)
    local route, alias = routeOf(rec.inst, rec.wing or 0, rec.route, rec.rv)
    if not route or alias then return nil end
    local keys = sortedKeys(route)
    local idx = {}
    for i, k in ipairs(keys) do idx[k] = i - 1 end
    local kills = {}
    for k, t in pairs(rec.kills or {}) do if idx[k] then kills[#kills + 1] = { idx[k], t } end end
    table.sort(kills, function(a, b) return a[1] < b[1] end)
    local kp = {}
    for _, e in ipairs(kills) do kp[#kp + 1] = b36(e[1]) .. ":" .. b36(e[2]) end
    local members = {}
    for _, m in ipairs(rec.members or {}) do
        members[#members + 1] = esc(m.name) .. ":" .. (m.class and CLASS_AT[m.class] and b36(CLASS_AT[m.class]) or "-")
    end
    if #members == 0 then members[1] = esc(rec.by or "?") .. ":-" end
    local function build()
        return "R1\t" .. table.concat({ rec.inst, rec.wing or 0, rec.route, rec.rv, b36(rec.started), b36(rec.total), rec.bracket == "over" and "o" or "i",
            rec.level or 0, rec.size or 1, rec.deaths or 0, rec.wipes or 0, table.concat(kp, ","), table.concat(members, ","), esc(rec.by or "?"), hop or rec.hop or 0 }, "\t")
    end
    local text = build()
    while #text > MAX_MSG and #members > 1 do
        table.remove(members)
        text = build()
    end
    if #text > MAX_MSG then return nil end
    return text
end

-- Returns a record, or nil and the reason. Everything is checked: this is text from another player.
function ns.CommsDecode(text, sender)
    if type(text) ~= "string" or #text > MAX_MSG or text:sub(1, 3) ~= "R1\t" then return nil, "kind" end
    local f = split(text:sub(4))
    if #f ~= 15 then return nil, "fields" end
    local hop = tonumber(f[15])
    if not hop or hop < 0 or hop > 3 or hop ~= math.floor(hop) then return nil, "hop" end
    local inst, wing = tonumber(f[1]), tonumber(f[2])
    if not (inst and wing and ns.Dungeons[inst] and wing >= 0 and wing <= 20 and wing == math.floor(wing)) then return nil, "dungeon" end
    local route, alias = routeOf(inst, wing, f[3], f[4])
    if not route then return nil, "route" end
    local started, total = fromB36(f[5]), fromB36(f[6])
    local level, size, deaths, wipes = tonumber(f[8]), tonumber(f[9]), tonumber(f[10]), tonumber(f[11])
    if not (started and total and level and size and deaths and wipes) then return nil, "numbers" end
    if started < 1.6e9 or started > time() + 3600 then return nil, "date" end
    if total < 30 or total > 21600 then return nil, "total" end
    if level < 1 or level > 80 or size < 1 or size > 40 or deaths < 0 or deaths > 999 or wipes < 0 or wipes > 999 then return nil, "ranges" end
    local bracket = f[7] == "o" and "over" or (f[7] == "i" and "in" or nil)
    if not bracket then return nil, "bracket" end
    local keys, oldNames
    if alias then keys, oldNames = ns.AliasKeys(alias) else keys = sortedKeys(route) end
    local kills, names, n, maxT = {}, {}, 0, 0
    for part in f[12]:gmatch("[^,]+") do
        local i, t = part:match("^(%w+):(%w+)$")
        i, t = i and fromB36(i), t and fromB36(t)
        local key = i and keys[i + 1]
        if not (key and t and t >= 1 and t <= total) or kills[key] then return nil, "kills" end
        kills[key], names[key] = t, (oldNames or route.keys)[key]
        n = n + 1
        if t > maxT then maxT = t end
    end
    if n ~= #keys or maxT ~= total then return nil, "incomplete" end
    if alias then -- an old route version: keep the kills of the bosses the current route has; all of them must be there
        local k2, n2 = {}, {}
        for key, name in pairs(route.keys) do
            if not kills[key] then return nil, "incomplete" end
            k2[key], n2[key] = kills[key], name
        end
        kills, names = k2, n2
        -- the run now ends at the last boss of the CURRENT route (the old route's last boss may be one it no longer has)
        local last = 0
        for _, t in pairs(kills) do if t > last then last = t end end
        total = last
    end
    local members = {}
    for part in f[13]:gmatch("[^,]+") do
        local name, c = part:match("^(.-):([%w%-])$")
        if not name or #members >= 40 then return nil, "members" end
        name = unesc(name)
        if #name < 1 or #name > 40 then return nil, "members" end
        local ci = c ~= "-" and fromB36(c) or nil
        members[#members + 1] = { name = name, class = ci and CLASSES[ci] or nil }
    end
    if #members == 0 then return nil, "members" end
    local by = unesc(f[14])
    if #by < 1 or #by > 40 then return nil, "by" end
    return { id = format("%d.%d.%s.%s", inst, started, norm(by), route.id), inst = inst, wing = wing, route = route.id, rv = route.version, rname = route.name,
        started = started, finished = started + total, total = total, kills = kills, names = names, pulls = {}, deaths = deaths, wipes = wipes, size = size,
        level = level, bracket = bracket, members = members, ranked = true, by = by, from = sender or "?", got = time(), hop = hop + 1 }
end

-- The board of received runs ------------------------------------------------------------------------------------------------------------
local function boardKey(r) return r.inst .. "." .. (r.wing or 0) .. "." .. r.route .. "." .. r.rv .. "." .. (r.bracket or "in") end

local function pruneBoard()
    local b = DungeonMapDB.board
    local now = time()
    local groups, out = {}, {}
    for _, r in ipairs(b) do
        if now - (r.finished or 0) <= MAX_AGE then
            local k = boardKey(r)
            groups[k] = groups[k] or {}
            table.insert(groups[k], r)
        end
    end
    for _, g in pairs(groups) do
        table.sort(g, function(x, y) if x.total ~= y.total then return x.total < y.total end return (x.got or 0) < (y.got or 0) end)
        for i = 1, math.min(PER_BOARD, #g) do out[#out + 1] = g[i] end
    end
    if #out > BOARD_MAX then
        table.sort(out, function(x, y) return (x.got or 0) > (y.got or 0) end)
        for i = #out, BOARD_MAX + 1, -1 do out[i] = nil end
    end
    DungeonMapDB.board = out
end

-- the same run, whatever the route id the sender called it: same dungeon, start time and owner
local function sameRun(a, b) return a.inst == b.inst and a.started == b.started and norm(a.by or "") == norm(b.by or "") end
local function haveRun(rec)
    for _, r in ipairs(DungeonMapDB.runs or {}) do if r.id == rec.id or sameRun(r, rec) then return r end end
    for _, r in ipairs(DungeonMapDB.board or {}) do if r.id == rec.id or sameRun(r, rec) then return r end end
end

local function senderKey(s) return norm((tostring(s):match("^([^%-]+)")) or s) end

-- One of the people in our run sent the same run: both are verified (they were there).
local function cosign(rec, sender)
    local sk = senderKey(sender)
    for _, mine in ipairs(DungeonMapDB.runs or {}) do
        if mine.ranked and mine.inst == rec.inst and (mine.wing or 0) == rec.wing and mine.route == rec.route and mine.rv == rec.rv
            and math.abs(mine.started - rec.started) <= 180 and math.abs(mine.total - rec.total) <= 5 then
            for _, m in ipairs(mine.members or {}) do
                if norm(m.name) == sk then mine.verified = true; rec.verified = true return true end
            end
        end
    end
end

function ns.CommsAddRun(rec, sender)
    DungeonMapDB.board = DungeonMapDB.board or {}
    if haveRun(rec) then return false end
    cosign(rec, sender)
    DungeonMapDB.board[#DungeonMapDB.board + 1] = rec
    pruneBoard()
    return true
end

-- Export / import by copy and paste (D-070) ---------------------------------------------------------------------------------------------
-- Addons cannot read files or reach the network, so runs move between a player's machines (or to a friend, or a site) as text: one line per run,
-- the same record as the addon message, with "~" in place of the tab (chat programs and notes apps eat tabs). Works with sharing switched off:
-- nothing leaves the game by itself, the player copies the text.
local EXPORT_HEAD = "DCFRUNS1"

-- The text for the Ctrl+C box: own ranked runs first, then received ones. Returns the text and the number of runs in it.
function ns.RunsExport()
    local lines, seen = {}, {}
    local function add(r, hop)
        if r.ranked and not seen[r.id] then
            local t = ns.CommsEncode(r, hop)
            if t then seen[r.id] = true; lines[#lines + 1] = (t:gsub("\t", "~")) end
        end
    end
    for _, r in ipairs(DungeonMapDB and DungeonMapDB.runs or {}) do add(r, 0) end
    for _, r in ipairs(DungeonMapDB and DungeonMapDB.board or {}) do add(r, r.hop or 1) end
    if #lines == 0 then return "", 0 end
    return EXPORT_HEAD .. "\n" .. table.concat(lines, "\n"), #lines
end

-- Merge pasted text. Every line is checked like a message from another player (same dungeon, route and numbers rules); a run already held is skipped.
-- A run by this character name goes into your own runs (it counts as yours: your best, your rank), the rest onto the board.
-- Returns: added (own), added (others), already held, rejected lines.
function ns.RunsImport(text)
    local mine, others, held, bad = 0, 0, 0, 0
    if not (DungeonMapDB and type(text) == "string") then return 0, 0, 0, 0 end
    DungeonMapDB.runs = DungeonMapDB.runs or {}
    local me = ns.MyRunName and ns.MyRunName()
    for raw in (text .. "\n"):gmatch("(.-)\r?\n") do
        local line = raw:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line ~= EXPORT_HEAD then
            local rec = ns.CommsDecode((line:gsub("~", "\t")), "import")
            if not rec then
                bad = bad + 1
            elseif haveRun(rec) then
                held = held + 1
            else
                rec.hop = math.max(0, (rec.hop or 1) - 1) -- carried by hand, not relayed
                rec.from = nil
                if me and norm(rec.by or "") == norm(me) then
                    table.insert(DungeonMapDB.runs, rec)
                    mine = mine + 1
                else
                    rec.from = "import"
                    DungeonMapDB.board = DungeonMapDB.board or {}
                    DungeonMapDB.board[#DungeonMapDB.board + 1] = rec
                    others = others + 1
                end
            end
        end
    end
    if mine > 0 then table.sort(DungeonMapDB.runs, function(a, b) return (a.started or 0) < (b.started or 0) end) end
    if others > 0 then pruneBoard() end
    if mine + others > 0 and ns.OnBoardChanged then pcall(ns.OnBoardChanged) end
    return mine, others, held, bad
end

-- Sending -------------------------------------------------------------------------------------------------------------------------------
local pumpFrame
local function enqueue(prefix, text, chat, target, kind, bn, share)
    if gate[kind] == "closed" then return false end
    queue[#queue + 1] = { prefix = prefix, text = text, chat = chat, target = target, kind = kind, bn = bn, share = share }
    if pumpFrame then pumpFrame:Show() end
    return true
end

-- One message out; returns false when the queue is empty or a throttle says wait.
function ns.CommsPump()
    local m = table.remove(queue, 1)
    if not m then
        if batch and batch.count > 0 then
            local where = {}
            for _, k in ipairs({ "GROUP", "GUILD", "FRIENDS" }) do
                if batch.kinds[k] then where[#where + 1] = (k == "GROUP" and "your group") or (k == "GUILD" and "your guild") or "your friends" end
            end
            if #where > 0 then ns.Print("Shared your run with " .. table.concat(where, " and ") .. ".") end
        end
        batch = nil
        return false
    end
    if gate[m.kind] == "closed" or not (m.bn or (C_ChatInfo and C_ChatInfo.SendAddonMessage)) then return true end
    -- the game can lock addon messages inside an instance or during an encounter: wait, nothing is lost
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and call(C_ChatInfo.InChatMessagingLockdown) == true then
        table.insert(queue, 1, m)
        if not gate.lockLogged then gate.lockLogged = true; log("lockdown", "waiting") end
        return false
    end
    local ok, res
    if m.bn then
        if not BNSendGameData then return true end
        ok, res = pcall(BNSendGameData, m.bn, m.prefix, m.text)
        res = nil
    else
        ok, res = pcall(C_ChatInfo.SendAddonMessage, m.prefix, m.text, m.chat, m.target)
    end
    if not ok then log("error", m.kind, res) return true end
    if not readable(res) then log("secret", m.kind) return true end
    if res == 3 then -- throttled: try again in a moment
        table.insert(queue, 1, m)
        log("throttled", m.kind)
        return false
    end
    if res == nil or res == true or res == 0 then
        if batch then batch.count = batch.count + 1; if m.prefix == PREFIX_REC and m.share then batch.kinds[m.share] = true end end
        if not gate["ok" .. m.kind] then gate["ok" .. m.kind] = true; log("ok", m.kind, m.chat) end
    else
        if res == 4 or res == 7 then
            gate[m.kind] = "closed"
            log("closed", m.kind, m.chat, res)
        else
            log("refused", m.kind, m.chat, res)
            ns.CommsDefer(m) -- an unknown refusal (inside the instance, in an encounter ...): tried again later, a few times
        end
    end
    return true
end

-- Messages the game refused for a reason that may pass: tried again every 30 seconds up to 6 times, and at once when you leave the instance.
local late = {}
local function retryLate()
    local list = late
    late = {}
    for _, m in ipairs(list) do
        if m.tries <= 6 then enqueue(m.prefix, m.text, m.chat, m.target, m.kind, m.bn, m.share) ; queue[#queue].tries = m.tries end
    end
end
function ns.CommsDefer(m)
    m.tries = (m.tries or 0) + 1
    if m.tries > 6 then log("dropped", m.kind, m.tries) return end
    late[#late + 1] = m
    if #late == 1 and C_Timer then C_Timer.After(30, retryLate) end
end
function ns.CommsRetryNow() if #late > 0 then retryLate() end end

local function groupChannel()
    if call(IsInRaid) then return "RAID" end
    local lePI = _G.LE_PARTY_CATEGORY_INSTANCE
    if lePI and call(IsInGroup, lePI) then return "INSTANCE_CHAT" end
    if call(IsInGroup) then return "PARTY" end
end

-- sharing is on: the question was answered and the answer was not "Don't share" (scope "none"). Receiving what others send needs no consent.
local function consented() return DungeonMapDB and DungeonMapDB.shareAsked == true and DungeonMapDB.shareScope ~= "none" end
-- "Don't share", and not having answered the question yet, keep your own runs to yourself, but you still pass on the runs other people
-- shared with you, to your guild and friends, so the best times reach everyone. The question keeps coming (UI/RunDone.lua) until it is answered.
local function relaying() return DungeonMapDB ~= nil end

-- A finished run (Runs.lua): to the group and the guild.
function ns.CommsShareRun(rec, backlog)
    if not (DungeonMapDB and rec and rec.ranked and consented()) then return end
    local text = ns.CommsEncode(rec)
    if not text then log("notEncoded", rec.id) return end
    rec.pushed = true -- sent once; a run recorded while private goes out later (ns.CommsShareBacklog)
    batch = batch or { kinds = {}, count = 0 }
    local g = groupChannel()
    if not backlog and g and #(rec.members or {}) > 1 then enqueue(PREFIX_REC, text, g, nil, "GROUP", nil, "GROUP") end
    if call(IsInGuild) then enqueue(PREFIX_REC, text, "GUILD", nil, "GUILD", nil, "GUILD") end
    -- friends who answered a hello and were not in the run (the group has it already)
    local inRun = {}
    for _, m in ipairs(rec.members or {}) do inRun[norm(m.name)] = true end
    for key, f in pairs(knownFriends) do
        if friendsNow[key] and not inRun[key] then
            if f.bn then enqueue(PREFIX_REC, text, nil, nil, "BN", f.bn, "FRIENDS") else enqueue(PREFIX_REC, text, "WHISPER", f.whisper, "WHISPER", nil, "FRIENDS") end
        end
    end
end

-- Runs recorded while sharing was off (or the question unanswered) are not lost: when sharing is turned on they go to the guild and friends too,
-- the best of each board first (at most REPLY_MAX in all; the rest is still handed out when someone asks). Not to the group: that run is long over.
function ns.CommsShareBacklog()
    if not (DungeonMapDB and consented()) then return 0 end
    local perBoard, list = {}, {}
    local runs = {}
    for _, r in ipairs(DungeonMapDB.runs or {}) do if r.ranked and not r.pushed and r.total then runs[#runs + 1] = r end end
    table.sort(runs, function(a, b) if a.total ~= b.total then return a.total < b.total end return (a.finished or 0) > (b.finished or 0) end)
    for _, r in ipairs(runs) do
        local k = boardKey(r)
        perBoard[k] = (perBoard[k] or 0) + 1
        if perBoard[k] <= PER_REPLY and #list < REPLY_MAX then list[#list + 1] = r end
    end
    for _, r in ipairs(list) do ns.CommsShareRun(r, true) end
    for _, r in ipairs(runs) do r.pushed = true end -- the rest is not pushed: others get it by asking
    return #list
end

-- Friends -------------------------------------------------------------------------------------------------------------------------------
-- Online friends who play this game on our faction: key -> { whisper = name } or { bn = gameAccountID, whisper = characterName }
local function scanFriends()
    local t = {}
    local fl = C_FriendList
    if fl and fl.GetNumFriends and fl.GetFriendInfoByIndex then
        for i = 1, tonumber(call(fl.GetNumFriends)) or 0 do
            local ok, f = pcall(fl.GetFriendInfoByIndex, i)
            if ok and type(f) == "table" and readable(f) and f.connected and type(f.name) == "string" and readable(f.name) then
                t[senderKey(f.name)] = { whisper = f.name }
            end
        end
    end
    if BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendAccountInfo then
        local mine = call(UnitFactionGroup, "player")
        for i = 1, tonumber(call(BNGetNumFriends)) or 0 do
            local ok, a = pcall(C_BattleNet.GetFriendAccountInfo, i)
            local g = ok and type(a) == "table" and a.gameAccountInfo
            if type(g) == "table" and g.isOnline and g.clientProgram == (BNET_CLIENT_WOW or "WoW") and (not WOW_PROJECT_ID or g.wowProjectID == WOW_PROJECT_ID)
                and mine and g.factionName == mine and type(g.characterName) == "string" and readable(g.characterName) and g.gameAccountID then
                t[senderKey(g.characterName)] = { bn = g.gameAccountID, whisper = g.characterName }
            end
        end
    end
    friendsNow = t
    for key in pairs(knownFriends) do if not t[key] then knownFriends[key] = nil end end -- gone offline: greeted again when back
    return t
end

local function toFriend(f, text)
    if f.bn then enqueue(PREFIX_CTL, text, nil, nil, "BN", f.bn) else enqueue(PREFIX_CTL, text, "WHISPER", f.whisper, "WHISPER") end
end

-- hello to every online friend not greeted in the last 30 minutes; the ones who have the addon answer
function ns.CommsFriends()
    if not (DungeonMapDB and relaying()) then return end
    local now = time()
    local n = 0
    for key, f in pairs(scanFriends()) do
        if (not greeted[key] or now - greeted[key] > 1800) and n < 40 then
            greeted[key] = now
            toFriend(f, "H1")
            n = n + 1
        end
    end
    if n > 0 then log("hello", n) end
end

local friendTimer
local function friendsChanged()
    if friendTimer or not (DungeonMapDB and relaying()) then return end
    friendTimer = true
    C_Timer.After(3, function() friendTimer = nil; ns.CommsFriends() end)
end
ns.CommsFriendsChanged = friendsChanged

-- "S1 <since>": the newest run we hold from others (or ours), minus a week of overlap, so answers skip what we already have
function ns.CommsRequestText()
    local newest = 0
    for _, r in ipairs(DungeonMapDB.board or {}) do if (r.finished or 0) > newest then newest = r.finished end end
    for _, r in ipairs(DungeonMapDB.runs or {}) do if (r.finished or 0) > newest then newest = r.finished end end
    return "S1\t" .. b36(math.max(0, newest - OVERLAP))
end

-- Digests -------------------------------------------------------------------------------------------------------------------------------
local guildAdvUntil, groupAdvUntil = 0, 0 -- until when we have advertised to the guild / the group (their whispered answers are welcome)
local replyOk, digestSeen, qSeen, digestReplied = {}, {}, {}, {}
local replyBudget = { n = 0, since = 0 }

local function bkOf(r) return r.inst .. "." .. (r.wing or 0) .. "." .. r.rv .. "." .. (r.bracket == "over" and "o" or "i") end

-- a short stable id of a run (4 characters), the same on every client
local function runHash(r)
    local h = 5381
    local s = r.inst .. "." .. (r.started or 0) .. "." .. norm(r.by or "")
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 1048576 end
    local t = b36(h)
    return string.rep("0", 4 - #t) .. t
end
ns.CommsRunHash = runHash

-- what we hold, per board: { [key] = { key, n, best, runs } } and the same as a list (ranked runs only, own and received)
local function boardStats(forPeer)
    local stats, list = {}, {}
    local function add(r)
        if not r.ranked then return end
        local k = bkOf(r)
        local s = stats[k]
        if not s then s = { key = k, n = 0, best = r.total, runs = {} }; stats[k] = s; list[#list + 1] = s end
        s.n = s.n + 1
        s.runs[#s.runs + 1] = r
        if r.total < s.best then s.best = r.total end
    end
    if not (forPeer and not consented()) then for _, r in ipairs(DungeonMapDB.runs or {}) do add(r) end end -- what we tell or send others leaves out our own runs when we do not share them
    for _, r in ipairs(DungeonMapDB.board or {}) do add(r) end
    return stats, list
end

-- the digest as one or more messages of the given kind ("D1" or "D2"); an empty digest is one empty message (it still makes others answer)
function ns.CommsDigestTexts(kind)
    local _, list = boardStats(true)
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.key < b.key end)
    local msgs, cur = {}, {}
    local function flush() msgs[#msgs + 1] = kind .. "\t" .. table.concat(cur, ","); cur = {} end
    for i = 1, math.min(DIGEST_BOARDS, #list) do
        local s = list[i]
        local e = s.key .. ":" .. s.n .. ":" .. b36(s.best)
        if #cur > 0 and #(kind .. "\t" .. table.concat(cur, ",") .. "," .. e) > MAX_MSG then flush() end
        cur[#cur + 1] = e
    end
    if #cur > 0 or #msgs == 0 then flush() end
    return msgs
end

local function sendTo(target, prefix, text)
    if target.bn then enqueue(prefix, text, nil, nil, "BN", target.bn) else enqueue(prefix, text, "WHISPER", target.whisper, "WHISPER") end
end

-- A peer's digest: ask (Q1) for the boards where they hold more than we do, then (for a D1) answer with our own digest.
local function handleDigest(kind, body, sender, chat, friend)
    local now = time()
    local d = digestSeen[sender]
    if not d or now - d.since > REPLY_EVERY then d = { n = 0, since = now }; digestSeen[sender] = d end
    d.n = d.n + 1
    if d.n > 6 then return end
    local stats = boardStats()
    local wants, n, unknown = {}, 0, 0
    for entry in body:gmatch("[^,]+") do
        n = n + 1
        if n > 30 then break end
        local bk, cnt, best = entry:match("^([%w%.]+):(%d+):(%w+)$")
        local inst, wing, rv = (bk or ""):match("^(%d+)%.(%d+)%.(%w+)%.[io]$")
        cnt, best = tonumber(cnt), best and fromB36(best)
        inst, wing = tonumber(inst), tonumber(wing)
        if bk and cnt and best and inst and wing and ns.Dungeons[inst] then
            local route = routeOf(inst, wing, "", rv)
            if not route then
                unknown = unknown + 1 -- a route version our data does not have: the sender runs other route data (an older addon)
            else
                -- the sender's key is what the query must say; our own board has the current version of that route
                local canon = route.version == rv and bk or (inst .. "." .. wing .. "." .. route.version .. bk:match("%.[io]$"))
                local mine = stats[canon]
                local prio = (not mine and 3) or (best < mine.best and 2) or (cnt > mine.n and 1) or 0
                if prio > 0 then wants[#wants + 1] = { key = bk, prio = prio, mine = mine } end
            end
        end
    end
    if unknown > 0 then
        log("unknownroutes", sender, unknown)
        if syncReport then syncReport.unknown = (syncReport.unknown or 0) + unknown
        elseif not unknownNoted then
            unknownNoted = true -- once per session; the Sync button's report says it again with numbers
            ns.Print("Another player's highscore boards use route data this addon version does not have, so their runs are skipped. Updating the addon (you or they) fixes it.")
        end
    end
    table.sort(wants, function(a, b) if a.prio ~= b.prio then return a.prio > b.prio end return a.key < b.key end)
    local target = friend or { whisper = sender }
    local parts = {}
    for i = 1, math.min(QUERY_BOARDS, #wants) do
        local w = wants[i]
        local hs = {}
        if w.mine then
            local runs = {}
            for _, r in ipairs(w.mine.runs) do runs[#runs + 1] = r end
            table.sort(runs, function(x, y) return x.total < y.total end)
            for k = 1, math.min(QUERY_HASHES, #runs) do hs[#hs + 1] = runHash(runs[k]) end
        end
        parts[#parts + 1] = w.key .. ":" .. table.concat(hs)
    end
    if #parts > 0 then
        askedUntil = now + 180 -- their answers come as whispers
        local cur = {}
        local function flush() if #cur > 0 then sendTo(target, PREFIX_CTL, "Q1\t" .. table.concat(cur, ",")); cur = {} end end
        for _, e in ipairs(parts) do
            if #cur > 0 and #("Q1\t" .. table.concat(cur, ",") .. "," .. e) > MAX_MSG then flush() end
            cur[#cur + 1] = e
        end
        flush()
        log("query", sender, #parts)
    end
    if kind == "D1" and now - (digestReplied[sender] or -1e9) >= REPLY_EVERY then
        if now - replyBudget.since > REPLY_EVERY then replyBudget = { n = 0, since = now } end
        if replyBudget.n < REPLY_BUDGET then
            replyBudget.n = replyBudget.n + 1
            digestReplied[sender] = now
            replyOk[senderKey(sender)] = now + 180
            for _, t in ipairs(ns.CommsDigestTexts("D2")) do sendTo(target, PREFIX_CTL, t) end
        end
    end
end

-- A peer's query: send the runs they lack on the boards they name (best first), within the caps and the answer budget.
local function handleQuery(body, sender, friend)
    local now = time()
    local q = qSeen[sender]
    if not q or now - q.since > REPLY_EVERY then q = { n = 0, since = now }; qSeen[sender] = q end
    q.n = q.n + 1
    if q.n > 4 then return end
    if now - budget.since > REPLY_EVERY then budget = { n = 0, since = now } end
    local stats = boardStats(true)
    local rk = senderKey(sender)
    local target = friend or { whisper = sender }
    local sent, n = 0, 0
    for entry in body:gmatch("[^,]+") do
        n = n + 1
        if n > 12 then break end
        local bk, hashes = entry:match("^([%w%.]+):(%w*)$")
        local s = bk and stats[bk]
        if s then
            local have = {}
            for h in hashes:gmatch("%w%w%w%w") do have[h] = true end
            local cands = {}
            for _, r in ipairs(s.runs) do
                if (r.hop or 0) < MAX_HOP and norm(r.by or "") ~= rk and not have[runHash(r)] then cands[#cands + 1] = r end
            end
            table.sort(cands, function(x, y) if x.total ~= y.total then return x.total < y.total end return x.finished > y.finished end)
            for i = 1, math.min(Q_PER_BOARD, #cands) do
                if sent >= Q_TOTAL then break end
                if budget.n >= ANSWER_BUDGET then log("budget", sender) return end
                local text = ns.CommsEncode(cands[i], cands[i].hop or 0)
                if text then
                    sendTo(target, PREFIX_REC, text)
                    sent = sent + 1
                    budget.n = budget.n + 1
                end
            end
        end
    end
    log("answeredQuery", sender, sent)
end

-- who may talk to us: a friend; the guild; whispers right after we advertised or replied; the group only when we share with everyone
local function allowed(chat, friend, sender)
    if not relaying() then return false end
    local now = time()
    if friend or chat == "GUILD" then return true end
    if chat == "WHISPER" then
        return (replyOk[senderKey(sender)] or 0) > now or guildAdvUntil > now or (groupAdvUntil > now and DungeonMapDB.shareScope == "everyone")
    end
    return DungeonMapDB.shareScope == "everyone"
end

-- Asking for runs ---------------------------------------------------------------------------------------------------------------------
-- What the Sync button got, said once after the answers have had time to arrive (they come as quiet addon messages; nothing else shows them).
local REPORT_AFTER = 45
local PERIODIC = 900 -- seconds between the guild / friends / group asks while the game is open
local function countKeys(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
local function printSyncReport(r)
    if syncReport ~= r then return end
    syncReport = nil
    local heard, runs, unknown = countKeys(r.heard), r.runs, r.unknown or 0
    if unknown > 0 then
        ns.Print(format("Guild sync: %d of the boards the others hold use route data your addon version does not have (or theirs lacks yours), so they were skipped. Update the addon (they may need to as well) and sync again.", unknown))
        if r.runs == 0 then return end -- "nothing new" would read as "they have nothing for you"
    end
    if runs > 0 then
        ns.Print(format("Guild sync done: %d new run%s from %d player%s with the addon.", runs, runs == 1 and "" or "s", heard, heard == 1 and "" or "s"))
    elseif heard > 0 then
        ns.Print(format("Guild sync done: %d player%s with the addon answered. They have no runs you lack, so nothing new came in.", heard, heard == 1 and "" or "s"))
    elseif gate.GUILD == "closed" then
        ns.Print("Guild sync failed: the game refused the message to the guild (addon messages are restricted right now). Try again later.")
    elseif countKeys(peersSeen) > 0 then
        ns.Print(format("Guild sync done: nothing new. %d player%s with the addon answered earlier this session and have nothing more for you.", countKeys(peersSeen), countKeys(peersSeen) == 1 and "" or "s"))
    else
        ns.Print("Guild sync done: no answer. Nobody in your guild who has the addon and sharing switched on has answered. They may be offline, or no one has runs you lack.")
    end
end

function ns.CommsSyncGuild(manual)
    if not (DungeonMapDB and relaying()) then
        if manual then ns.Print("Not available yet.") end
        return false
    end
    if not call(IsInGuild) then
        if manual then ns.Print("You are not in a guild.") end
        return false
    end
    local now = time()
    if now - lastGuildAsk < (manual and 60 or 300) then
        if manual then ns.Print("You asked a moment ago. Try again in a minute.") end
        return false
    end
    lastGuildAsk = now
    guildAdvUntil = now + 180
    for _, t in ipairs(ns.CommsDigestTexts("D1")) do
        enqueue(PREFIX_CTL, t, "GUILD", nil, "GUILD")
        for key, f in pairs(knownFriends) do if friendsNow[key] then toFriend(f, t) end end
    end
    if manual then
        ns.Print("Sent a summary of your highscore runs to your guild and friends. I will tell you what came back in under a minute.")
        local r = { heard = {}, runs = 0 }
        syncReport = r
        if C_Timer and C_Timer.After then C_Timer.After(REPORT_AFTER, function() printSyncReport(r) end) end
    end
    return true
end

-- login: a while after entering the world (every loading screen: the game ones, so a zone change or a dungeon exit asks again once the 5 minute gap
-- is over), and then every 15 minutes for as long as the game is open, so a guildmate who logged in after us is asked too (D-070)
local periodic = false
local function periodicAsk()
    if DungeonMapDB and relaying() then
        ns.CommsFriends()
        ns.CommsSyncGuild(false)
        ns.CommsRoster()
    end
    if C_Timer and C_Timer.After then C_Timer.After(PERIODIC, periodicAsk) end
end
function ns.CommsLogin()
    if DungeonMapDB and consented() then ns.CommsShareBacklog() end
    if DungeonMapDB and relaying() then
        ns.CommsFriends()
        ns.CommsSyncGuild(false)
        if not periodic and C_Timer and C_Timer.After then periodic = true; C_Timer.After(PERIODIC, periodicAsk) end
    end
end

-- the group changed (scope "everyone" only): ask the new group, at most every two minutes, never in combat
function ns.CommsRoster()
    if not (DungeonMapDB and consented() and DungeonMapDB.shareScope == "everyone") then return end
    local g = groupChannel()
    if not g or (InCombatLockdown and InCombatLockdown()) then return end
    local now = time()
    if now - lastGroupAsk < 120 then return end
    lastGroupAsk = now
    groupAdvUntil = now + 180
    for _, t in ipairs(ns.CommsDigestTexts("D1")) do enqueue(PREFIX_CTL, t, g, nil, "GROUP") end
end

-- What to answer a request with (relaying): own and received runs, finished after `since`, not the requester's own, passed on fewer than MAX_HOP
-- times; the best PER_REPLY of each board, taken round-robin across boards (every board's best first) up to REPLY_MAX.
function ns.CommsRelayList(since, requesterKey)
    local groups, order = {}, {}
    local function consider(r)
        if r.ranked and (r.finished or 0) > since and (r.hop or 0) < MAX_HOP and norm(r.by or "") ~= requesterKey then
            local k = boardKey(r)
            if not groups[k] then groups[k] = {}; order[#order + 1] = k end
            table.insert(groups[k], r)
        end
    end
    if consented() then for _, r in ipairs(DungeonMapDB.runs or {}) do consider(r) end end -- your own runs only when you share them
    for _, r in ipairs(DungeonMapDB.board or {}) do consider(r) end
    table.sort(order)
    for _, g in pairs(groups) do table.sort(g, function(x, y) if x.total ~= y.total then return x.total < y.total end return x.finished > y.finished end) end
    local list, seen = {}, {}
    for round = 1, PER_REPLY do
        for _, k in ipairs(order) do
            local r = groups[k][round]
            if r and not seen[r.id] and #list < REPLY_MAX then seen[r.id] = true; list[#list + 1] = r end
        end
    end
    return list
end

local function answer(sender, chat, friend, since)
    if not relaying() then return end
    if chat ~= "GUILD" and not friend and DungeonMapDB.shareScope ~= "everyone" then return end
    local now = time()
    if lastReply[sender] and now - lastReply[sender] < REPLY_EVERY then return end
    if now - budget.since > REPLY_EVERY then budget = { n = 0, since = now } end
    lastReply[sender] = now
    local n = 0
    for _, r in ipairs(ns.CommsRelayList(since or 0, senderKey(sender))) do
        if budget.n >= ANSWER_BUDGET then log("budget", sender) break end
        local text = ns.CommsEncode(r, r.hop or 0)
        if text then
            if friend and friend.bn then enqueue(PREFIX_REC, text, nil, nil, "BN", friend.bn) else enqueue(PREFIX_REC, text, "WHISPER", sender, "WHISPER") end
            n = n + 1
            budget.n = budget.n + 1
        end
    end
    log("answered", sender, chat, n)
end

-- Receiving -----------------------------------------------------------------------------------------------------------------------------
-- somebody with the addon (and sharing on) sent a digest or a query; counts for the report after the Sync button
local function heardFrom(sender)
    local k = senderKey(sender)
    peersSeen[k] = true
    if syncReport then syncReport.heard[k] = true end
end

local function isMe(sender)
    local me = ns.MyRunName and ns.MyRunName()
    return me and norm(senderKey(sender)) == norm(me)
end

function ns.CommsReceive(prefix, text, chat, sender, bnAccount)
    if prefix ~= PREFIX_REC and prefix ~= PREFIX_CTL then return end
    if not (DungeonMapDB and readable(text) and readable(sender) and readable(chat)) then return end
    if type(text) ~= "string" or type(sender) ~= "string" or sender == "" or #text > MAX_MSG then return end
    if isMe(sender) then return end
    local friend = friendsNow[senderKey(sender)]
    if bnAccount and not friend then friend = { bn = bnAccount, whisper = sender } end -- Battle.net messages only come from friends
    if prefix == PREFIX_CTL then
        if text == "H1" or text == "H2" then
            if friend and relaying() then
                knownFriends[senderKey(sender)] = bnAccount and { bn = bnAccount, whisper = sender } or friend
                friendsNow[senderKey(sender)] = friendsNow[senderKey(sender)] or friend
                log("friend", sender, text)
                if text == "H1" then toFriend(knownFriends[senderKey(sender)], "H2") end
            end
        elseif text:sub(1, 3) == "D1\t" or text:sub(1, 3) == "D2\t" then
            if allowed(chat, (chat == "WHISPER" or bnAccount) and friend or nil, sender) then
                log("digest", sender, chat, text:sub(1, 2))
                heardFrom(sender)
                handleDigest(text:sub(1, 2), text:sub(4), sender, chat, (chat == "WHISPER" or bnAccount) and friend or nil)
            end
        elseif text:sub(1, 3) == "Q1\t" then
            if allowed(chat, (chat == "WHISPER" or bnAccount) and friend or nil, sender) then
                heardFrom(sender)
                handleQuery(text:sub(4), sender, (chat == "WHISPER" or bnAccount) and friend or nil)
            end
        elseif text:sub(1, 2) == "S1" then
            local since = fromB36(text:match("^S1\t(%w+)$") or "0") or 0
            log("request", sender, chat)
            answer(sender, chat, (chat == "WHISPER" or bnAccount) and friend or nil, since)
        end
        return
    end
    if chat == "WHISPER" and not friend and time() > askedUntil then return end -- a run by whisper: from a friend, or the answer to our own request
    local now = time()
    local c = recvCount[sender]
    if not c or now - c.since > RECV_WINDOW then c = { n = 0, since = now }; recvCount[sender] = c end
    c.n = c.n + 1
    if c.n > RECV_MAX then return end
    local rec, why = ns.CommsDecode(text, sender)
    if not rec then
        log("rejected", sender, why)
        if why == "route" and syncReport then syncReport.unknown = (syncReport.unknown or 0) + 1 end
        return
    end
    if ns.CommsAddRun(rec, sender) then
        log("received", sender, chat, rec.inst, rec.total)
        peersSeen[senderKey(sender)] = true
        if syncReport then syncReport.heard[senderKey(sender)] = true; syncReport.runs = syncReport.runs + 1 end
        if ns.OnBoardChanged then pcall(ns.OnBoardChanged) end
    end
end

-- /dm comms: what sharing is doing, for testing with a friend (the same facts are in DungeonMapDB.commsLog)
function ns.CommsStatus()
    local out = {}
    local restricted = call(C_ChatInfo and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted)
    out[#out + 1] = format("Sharing: %s, scope %s. Addon chat restricted by the realm: %s.", consented() and "on" or (DungeonMapDB.shareAsked and "own runs kept private (others' runs are still passed on to guild and friends)" or "NOT answered (own runs kept private until you choose, others' runs are passed on to guild and friends)"), tostring(DungeonMapDB.shareScope), tostring(restricted))
    local gates = {}
    for _, k in ipairs({ "GROUP", "GUILD", "WHISPER", "BN" }) do gates[#gates + 1] = k .. "=" .. (gate[k] == "closed" and "CLOSED" or (gate["ok" .. k] and "working" or "untried")) end
    out[#out + 1] = "Channels: " .. table.concat(gates, ", ")
    local nf, nk = 0, 0
    for _ in pairs(friendsNow) do nf = nf + 1 end
    for _ in pairs(knownFriends) do nk = nk + 1 end
    out[#out + 1] = format("Friends online: %d, with the addon: %d. Runs received and kept: %d. Waiting to send: %d.", nf, nk, #(DungeonMapDB.board or {}), #queue)
    local l = DungeonMapDB.commsLog or {}
    for i = math.max(1, #l - 5), #l do out[#out + 1] = format("  %s %s %s", date("%H:%M:%S", l[i].t), l[i].what, l[i].info) end
    return out
end

-- events: the addon-message event has its own frame; the pump runs only while there is something to send
if ns.isForever and CreateFrame then
    pcall(function()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_REC)
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX_CTL)
        end
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("CHAT_MSG_ADDON")
        pcall(ev.RegisterEvent, ev, "BN_CHAT_MSG_ADDON")
        for _, e in ipairs({ "FRIENDLIST_UPDATE", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_INFO_CHANGED" }) do pcall(ev.RegisterEvent, ev, e) end
        ev:SetScript("OnEvent", function(_, event, prefix, text, chat, sender)
            if event == "CHAT_MSG_ADDON" then pcall(ns.CommsReceive, prefix, text, chat, sender)
            elseif event == "BN_CHAT_MSG_ADDON" then
                -- prefix, text, channel, gameAccountID: the sender's character name comes from the account info
                local g = readable(sender) and C_BattleNet and C_BattleNet.GetGameAccountInfoByID and call(C_BattleNet.GetGameAccountInfoByID, sender)
                if type(g) == "table" and type(g.characterName) == "string" and readable(g.characterName) then pcall(ns.CommsReceive, prefix, text, "BN", g.characterName, sender) end
            else friendsChanged() end
        end)
        pumpFrame = CreateFrame("Frame")
        local wait = 0
        pumpFrame:SetScript("OnUpdate", function(self, elapsed)
            wait = wait - elapsed
            if wait > 0 then return end
            wait = SEND_GAP
            if not ns.CommsPump() and #queue == 0 then self:Hide() end
        end)
        pumpFrame:Hide()
    end)
end
