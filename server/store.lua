--- ชั้นฐานข้อมูล — สร้างตาราง · โหลดกระดาน · เซฟแต้ม
---
--- หลัก:
---   · hot path ไม่แตะ DB — ranking ปักธง Store.markDirty() แล้วเซฟเป็นรอบ
---   · เขียน "แต้มเต็ม" ไม่ใช่ส่วนต่าง → เขียนซ้ำ/เขียนช้าก็ไม่เพี้ยน
---   · เซฟเฉพาะ (คน, งาน) ที่เปลี่ยน ก้อนละ SaveBatchSize แถว พักเฟรมระหว่างก้อน · พลาด = คืนธงให้รอบหน้า
---   · หยุด resource / ปิดเซิร์ฟ = ส่งทุกแถวโดยไม่รอผล (coroutine ใน onResourceStop จะไม่ถูก resume อีก)

Store = {}

local RES <const> = GetCurrentResourceName()
local BATCH <const> = math.max(1, math.floor(Config.Ranking.SaveBatchSize or 100))
local PAGE <const> = 500
local SAVE_STUCK_MS <const> = 240000    -- oxmysql ขอ connection ไม่ได้ = await ไม่กลับ → ถือว่ารอบนั้นค้าง ให้รอบใหม่เริ่มได้
local SCORE_CEIL <const> = 4294967296   -- มากกว่าเพดาน INT UNSIGNED → หน้าแรกของ keyset ผ่านเงื่อนไขเสมอ

-- ⚠️ ต้องขึ้นต้นด้วย "INSERT" ตรงๆ ห้ามมีช่องว่าง/ขึ้นบรรทัดนำหน้า —
--    oxmysql ดูชนิดคำสั่งจากคำแรก ได้คำว่าง = ชนิดผิด
-- GREATEST: แต้มขึ้นอย่างเดียว → ก้อนเก่าที่เขียนถึง DB ช้ากว่าก้อนใหม่ (รอบเซฟชนกับเซฟตอนออกเกม) ทับค่าใหม่ไม่ได้
local UPSERT_SQL <const> = 'INSERT INTO lnn_alljob_scores (identifier, job, score) VALUES (?, ?, ?) '
    .. 'ON DUPLICATE KEY UPDATE score = GREATEST(score, VALUES(score))'

-- keyset paging เดินบน idx_job_score ย้อนหลัง — score และ identifier ต้อง DESC ทั้งคู่ (ผสมทิศ = filesort ทุกหน้า)
local PAGE_SQL <const> = 'SELECT identifier, score FROM lnn_alljob_scores WHERE job = ? '
    .. 'AND (score < ? OR (score = ? AND identifier < ?)) ORDER BY score DESC, identifier DESC LIMIT ?'

local Dirty = {}   -- Dirty[identifier][job] = true → รอเขียน

function Store.ensureTable()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `lnn_alljob_scores` (
            `identifier` VARCHAR(64) NOT NULL,
            `job`        VARCHAR(32) NOT NULL,
            `score`      INT UNSIGNED NOT NULL DEFAULT 0,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            PRIMARY KEY (`identifier`, `job`),
            KEY `idx_job_score` (`job`, `score`, `identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

--- โหลดทั้งกระดานของงานนี้ เรียงมาก → น้อยจาก SQL (ไม่ต้อง sort ใน Lua) ทีละ PAGE แถว
function Store.loadBoard(job, onRow)
    local lastScore, lastId, total = SCORE_CEIL, '', 0
    while true do
        local page = MySQL.query.await(PAGE_SQL, { job, lastScore, lastScore, lastId, PAGE }) or {}
        for i = 1, #page do
            local r = page[i]
            onRow(r.identifier, tonumber(r.score) or 0)
        end
        total = total + #page
        if #page < PAGE then return total end

        local last = page[#page]
        lastScore, lastId = tonumber(last.score) or 0, last.identifier
        Wait(0)
    end
end

--- ชื่อตัวละครของคนออฟไลน์ (ใช้แค่ Top-N ตอนบูต) · ไม่มีคอลัมน์ firstname/lastname = คืนว่าง
function Store.loadNames(idents)
    local names = {}
    for first = 1, #idents, PAGE do
        local part = table.move(idents, first, math.min(first + PAGE - 1, #idents), 1, {})
        local ok, rows = pcall(MySQL.query.await,
            'SELECT identifier, firstname, lastname FROM users WHERE identifier IN (?)', { part })
        if not ok then
            print(('^3[%s] อ่านชื่อจากตาราง users ไม่ได้ (%s) — ชื่อจะขึ้นเมื่อคนนั้นเข้าเกม^7'):format(RES, tostring(rows)))
            return names
        end
        for i = 1, #(rows or {}) do
            local r = rows[i]
            local name = ('%s %s'):format(r.firstname or '', r.lastname or ''):match('^%s*(.-)%s*$')
            if name ~= '' then names[r.identifier] = name end
        end
    end
    return names
end

function Store.markDirty(ident, job)
    local jobs = Dirty[ident]
    if not jobs then jobs = {}; Dirty[ident] = jobs end
    jobs[job] = true
end

--- ดึงงานที่รอเขียนของคนนี้ออกเป็นแถว { identifier, job, score } แล้วล้างธง
local function takeDirty(ident, rows)
    local jobs = Dirty[ident]
    if not jobs then return end
    Dirty[ident] = nil
    for job in pairs(jobs) do
        local score = Ranking.ScoreOf(ident, job)
        if score then rows[#rows + 1] = { ident, job, score } end
    end
end

--- เขียนเป็นก้อน พักเฟรมระหว่างก้อน · ก้อนที่พลาดคืนธง (รอบหน้าเขียนค่าล่าสุดแทน)
--- สำเร็จ/พลาดดูจาก pcall อย่างเดียว — ค่าที่ prepare คืนต่างกันตามจำนวนแถว
local function writeRows(rows)
    for first = 1, #rows, BATCH do
        local last = math.min(first + BATCH - 1, #rows)
        local part = table.move(rows, first, last, 1, {})
        local ok, err = pcall(MySQL.prepare.await, UPSERT_SQL, part)
        if not ok then
            for i = 1, #part do Store.markDirty(part[i][1], part[i][2]) end
            print(('^1[%s] เซฟพลาด %d แถว: %s^7'):format(RES, #part, tostring(err)))
        end
        if last < #rows then Wait(0) end
    end
end

--- ออกเกม — เขียนเฉพาะคนนั้น
function Store.saveOne(ident)
    local rows = {}
    takeDirty(ident, rows)
    if #rows > 0 then writeRows(rows) end
end

local saving, savingSince, savePass = false, 0, 0

--- รอบเซฟปกติ (ต้องอยู่ใน thread ที่ yield ได้) · รอบก่อนยังไม่จบ = ข้ามรอบนี้
function Store.saveAll()
    if saving and (GetGameTimer() - savingSince) < SAVE_STUCK_MS then return end
    savePass = savePass + 1
    local myPass = savePass
    saving, savingSince = true, GetGameTimer()

    local ok, err = pcall(function()
        -- ล้างค่าใน pairs() ระหว่างไล่ได้ (ไม่ได้เพิ่ม key) และช่วงนี้ไม่มี yield
        local rows = {}
        for ident in pairs(Dirty) do takeDirty(ident, rows) end
        if #rows > 0 then writeRows(rows) end
    end)

    -- รอบที่ค้างแล้วกลับมาทีหลัง ห้ามปลดธงของรอบใหม่
    if savePass == myPass then saving = false end
    if not ok then print(('^1[%s] รอบเซฟล้ม: %s^7'):format(RES, tostring(err))) end
end

--- หยุด resource / ปิดเซิร์ฟ — yield ไม่ได้ ส่งทุกแถวใน prepare เดียวแล้วไม่รอผล
function Store.saveAllNoYield()
    local rows = {}
    for ident in pairs(Dirty) do takeDirty(ident, rows) end
    if #rows > 0 then MySQL.prepare(UPSERT_SQL, rows) end
end
