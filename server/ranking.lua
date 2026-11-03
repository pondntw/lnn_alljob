--- Ranking — กระดานทุกงาน + กระดานรวม อยู่ใน RAM ทั้งหมด
---
--- โหลดจาก DB ครั้งเดียวตอนบูต แล้วกระดานใน RAM คือของจริงตลอด (แต้มเปลี่ยนผ่าน resource นี้ทางเดียว)
--- → บวกแต้ม = O(log n) ไม่มี SQL · เข้าเกมไม่ต้อง SELECT · ไม่มีรอบ rebuild
---
--- realtime: ส่งเฉพาะคนที่เปิดกระดานนั้นอยู่ (Viewers) ไม่มี -1 · ticker ตัวเดียวรวมการเปลี่ยนทั้งรอบเป็น 1 push/กระดาน
---   top = Top-N เปลี่ยน → pack ครั้งเดียว ส่งผู้ชมทุกคนของกระดานนั้น
---   me  = อันดับ/แต้มของผู้ชมคนนั้นเปลี่ยน (รวมถึงถูกคนอื่นแซง) → ส่งเฉพาะคนนั้น
---
--- เลขกระดาน: 0 = รวมทุกงาน · 1..#Config.Jobs = งานลำดับนั้น

Ranking = {}

local TOP <const> = Config.Ranking.Top
local TOTAL <const> = 0
local LAST <const> = #Config.Jobs
local PUSH_MS <const> = Config.Ranking.PushIntervalMs
local OPEN_CD <const> = Config.Ranking.OpenCooldownMs
local UNKNOWN <const> = 'ไม่ทราบชื่อ'

local EV_TOP <const> = 'lnn_alljob:rank:top'
local EV_ME <const> = 'lnn_alljob:rank:me'

local Boards = {}     -- [idx] = Board
local KeyOf = {}      -- [idx] = ชื่อกระดานใน DB
local IdxOf = {}      -- [ชื่อใน DB] = idx
local Rev = {}        -- [idx] = รุ่นของ Top-N (ขึ้นทุกครั้งที่ Top-N เปลี่ยน) — client แคชตามเลขนี้
local TopCache = {}   -- [idx] = { rev, rows }
local TopDirty = {}   -- [idx] = true → Top-N เปลี่ยนตั้งแต่ push ล่าสุด
local Changed = {}    -- [idx] = true → มีคนได้แต้มในกระดานนี้ตั้งแต่ push ล่าสุด (อันดับของผู้ชมอาจขยับ)
local Names = {}      -- [identifier] = ชื่อตัวละคร
local Ready = false

local Viewers = {}    -- [idx] = { [src] = true }
local Watching = {}   -- [src] = idx (คนละ 1 กระดาน)
local SentRank = {}   -- [src] = อันดับที่ส่งให้ล่าสุด
local SentScore = {}  -- [src] = แต้มที่ส่งให้ล่าสุด
local OpenAt = {}     -- [src] = GetGameTimer() ที่เปิดล่าสุด

for idx = TOTAL, LAST do
    local key = idx == TOTAL and Config.TotalBoard or Config.Jobs[idx].name
    Boards[idx], KeyOf[idx], IdxOf[key], Rev[idx], Viewers[idx] = Board.new(), key, idx, 0, {}
end

-- ============================================================
-- อ่าน
-- ============================================================

function Ranking.IsReady() return Ready end

--- แต้มเต็มของคนนี้ในกระดาน (ชื่อใน DB) — Store เรียกตอนเซฟ
function Ranking.ScoreOf(ident, key)
    local idx = IdxOf[key]
    return idx and Board.score(Boards[idx], ident)
end

--- อันดับของคนนี้ในงาน jobIdx (nil = ยังไม่ติดกระดาน)
function Ranking.RankOf(ident, jobIdx)
    return (Board.rank(Boards[jobIdx], ident))
end

--- แถว Top-N แบบ array { ชื่อ, แต้ม } — ไม่ส่งชื่อ key ไปกับทุกแถว · แคชตาม Rev (สร้างครั้งเดียวต่อรุ่น)
local function topRows(idx)
    local cached = TopCache[idx]
    if cached and cached.rev == Rev[idx] then return cached.rows end

    local list, rows = Boards[idx].list, {}
    for i = 1, math.min(TOP, #list) do
        local e = list[i]
        rows[i] = { Names[e.id] or UNKNOWN, e.score }
    end
    TopCache[idx] = { rev = Rev[idx], rows = rows }
    return rows
end

local function topChanged(idx)
    Rev[idx] = Rev[idx] + 1
    TopDirty[idx] = true
end

-- ============================================================
-- เขียน (hot path — RAM ล้วน)
-- ============================================================

local function bump(idx, ident, amount)
    local _, rank = Board.add(Boards[idx], ident, amount)
    Store.markDirty(ident, KeyOf[idx])
    Changed[idx] = true
    if rank <= TOP then topChanged(idx) end   -- อันดับใหม่ ≤ อันดับเดิมเสมอ → เช็คแค่อันดับใหม่พอ
    return rank
end

--- บวกแต้มงาน jobIdx + กระดานรวม → คืนอันดับใหม่ในงานนั้น
function Ranking.Add(ident, jobIdx, amount)
    if not Ready or not ident or amount <= 0 then return nil end
    local rank = bump(jobIdx, ident, amount)
    bump(TOTAL, ident, amount)
    return rank
end

--- ชื่อเปลี่ยน (เข้าเกม) → ถ้าคนนี้อยู่ใน Top-N ของกระดานไหน ต้องส่งชื่อใหม่
function Ranking.SetName(ident, name)
    if type(name) ~= 'string' or name == '' or Names[ident] == name then return end
    Names[ident] = name
    for idx = TOTAL, LAST do
        local rank = Board.rank(Boards[idx], ident)
        if rank and rank <= TOP then topChanged(idx) end
    end
end

-- ============================================================
-- บูต
-- ============================================================

function Ranking.Load()
    local started, rows = GetGameTimer(), 0
    for idx = TOTAL, LAST do
        local board = Boards[idx]
        rows = rows + Store.loadBoard(KeyOf[idx], function(ident, score) Board.push(board, ident, score) end)
    end

    -- ชื่อเฉพาะ Top-N (คนนอก Top-N ไม่มีใครเห็นชื่อ) · คนที่เข้าเกมระหว่างโหลดได้ชื่อไปแล้ว
    -- คนออฟไลน์เข้า Top-N ใหม่ไม่ได้ (แต้มขึ้นเฉพาะตอนออนไลน์) จึงไม่ต้องดึงชื่อเพิ่มทีหลัง
    local idents, seen = {}, {}
    for idx = TOTAL, LAST do
        local list = Boards[idx].list
        for i = 1, math.min(TOP, #list) do
            local id = list[i].id
            if not seen[id] and not Names[id] then seen[id] = true; idents[#idents + 1] = id end
        end
    end
    for id, name in pairs(Store.loadNames(idents)) do
        if not Names[id] then Names[id] = name end
    end
    for idx = TOTAL, LAST do topChanged(idx) end

    print(('[lnn_alljob] โหลด Ranking %d แถว %d กระดาน ใน %d ms'):format(rows, LAST + 1, GetGameTimer() - started))
end

function Ranking.SetReady() Ready = true end

-- ============================================================
-- ผู้ชม realtime
-- ============================================================

function Ranking.Unwatch(src)
    local idx = Watching[src]
    if idx then Viewers[idx][src] = nil end
    Watching[src], SentRank[src], SentScore[src] = nil, nil, nil
end

--- หลุดเกม — ล้างทุกอย่างของ src นี้
function Ranking.Forget(src)
    Ranking.Unwatch(src)
    OpenAt[src] = nil
end

--- เปิดกระดาน: ลงชื่อเป็นผู้ชม + คืนสถานะปัจจุบัน · rev ตรงกับที่ client แคชไว้ = ไม่ส่งแถวซ้ำ
lib.callback.register('lnn_alljob:rank:open', function(src, idx, rev)
    if not Ready then return false end
    idx = math.tointeger(idx)
    local board = idx and Boards[idx]
    if not board then return false end

    local now = GetGameTimer()
    if OpenAt[src] and now - OpenAt[src] < OPEN_CD then return false end
    OpenAt[src] = now

    Ranking.Unwatch(src)
    Viewers[idx][src], Watching[src] = true, idx

    local rank, score = Board.rank(board, Players.ident(src))
    rank, score = rank or 0, score or 0
    SentRank[src], SentScore[src] = rank, score

    return {
        rev = Rev[idx],
        rows = rev ~= Rev[idx] and topRows(idx) or nil,
        count = Board.size(board),
        rank = rank,
        score = score,
    }
end)

RegisterNetEvent('lnn_alljob:rank:close', function()
    Ranking.Unwatch(source)
end)

--- ส่งอันดับของผู้ชมคนนี้ถ้าเปลี่ยนจากที่ส่งไปล่าสุด
local function pushMe(src, idx)
    local rank, score = Board.rank(Boards[idx], Players.ident(src))
    rank, score = rank or 0, score or 0
    if SentRank[src] == rank and SentScore[src] == score then return end
    SentRank[src], SentScore[src] = rank, score
    TriggerClientEvent(EV_ME, src, idx, rank, score)
end

local function pushTick()
    for idx = TOTAL, LAST do
        local viewers = Viewers[idx]
        if next(viewers) then
            if TopDirty[idx] then
                -- payload เดียวกันทุกคน → pack ครั้งเดียว แทนให้ TriggerClientEvent pack ใหม่ทุกคน
                local payload = msgpack.pack_args(idx, Rev[idx], topRows(idx), Board.size(Boards[idx]))
                local len = #payload
                for src in pairs(viewers) do TriggerClientEventInternal(EV_TOP, src, payload, len) end
            end
            -- ไม่มีใครได้แต้มในกระดานนี้ = อันดับของผู้ชมไม่มีทางขยับ ข้ามการค้นทั้งหมด
            if Changed[idx] then
                for src in pairs(viewers) do pushMe(src, idx) end
            end
        end
        -- ไม่มีผู้ชม = ทิ้งธงได้เลย คนที่เปิดทีหลังได้ค่าสดจาก callback open
        TopDirty[idx], Changed[idx] = nil, nil
    end
end

CreateThread(function()
    while true do
        Wait(PUSH_MS)
        if Ready then pushTick() end
    end
end)

-- ============================================================
-- ให้ resource อื่นใช้ (server เท่านั้น)
-- ============================================================

local MAX_EXTERNAL <const> = 1000000

--- นับแต้มจากสคริปต์อื่นเข้างานที่มีใน config · คืน true = นับแล้ว
local function addExternal(src, jobName, amount)
    local idx = IdxOf[jobName]
    amount = math.tointeger(amount)
    if not idx or idx == TOTAL or not amount or amount <= 0 or amount > MAX_EXTERNAL then return false end
    return Ranking.Add(Players.ident(tonumber(src)), idx, amount) ~= nil
end

exports('AddScore', addExternal)
-- ⚠️ AddEventHandler เท่านั้น ห้ามเปลี่ยนเป็น RegisterNetEvent (client จะปั๊มแต้มตัวเองได้)
AddEventHandler('lnn_alljob:addScore', addExternal)

--- Top-N ของกระดาน (ชื่องาน หรือ nil/'total' = รวม) → { { rank, identifier, name, score }, ... }
exports('GetTop', function(board, n)
    local idx = (board == nil or board == 'total') and TOTAL or IdxOf[board]
    if not idx then return {} end
    local list, out = Boards[idx].list, {}
    for i = 1, math.min(math.tointeger(n) or TOP, 100, #list) do
        local e = list[i]
        out[i] = { rank = i, identifier = e.id, name = Names[e.id] or UNKNOWN, score = e.score }
    end
    return out
end)

--- อันดับ + แต้มของ identifier (nil = ไม่ติดกระดาน)
exports('GetRank', function(identifier, board)
    local idx = (board == nil or board == 'total') and TOTAL or IdxOf[board]
    if not idx then return nil end
    return Board.rank(Boards[idx], identifier)
end)
