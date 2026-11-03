--- เทส server/board.lua นอกเกม — รันด้วย Lua 5.4 ธรรมดา:  lua tests/board_test.lua
---
--- 1) เคสเฉพาะ: แต้มเท่ากัน · คนใหม่ · id ซ้ำตอนโหลด · ไม่มีในกระดาน
--- 2) สุ่มเทียบกับ "ตัวอ้างอิงแบบโง่" (sort ใหม่ทุกครั้ง) หลายพันรอบ → ทุกอันดับต้องตรงกัน

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
dofile(dir .. '/../server/board.lua')

local passed, failed = 0, 0
local function check(name, cond, msg)
    if cond then
        passed = passed + 1
    else
        failed = failed + 1
        print(('FAIL  %s  %s'):format(name, msg or ''))
    end
end

local function order(b)
    local out = {}
    for i, e in ipairs(b.list) do out[i] = e.id end
    return table.concat(out, ',')
end

-- ── เคสเฉพาะ ──────────────────────────────────────────────

do -- คนใหม่ได้แต้มแรก
    local b = Board.new()
    local old, new = Board.add(b, 'a', 5)
    check('new entry old rank', old == 1, ('old=%s'):format(old))
    check('new entry new rank', new == 1, ('new=%s'):format(new))
    local r, s = Board.rank(b, 'a')
    check('new entry rank/score', r == 1 and s == 5)
end

do -- แต้มเท่ากัน: คนที่ถึงแต้มนี้ก่อนอยู่บน
    local b = Board.new()
    Board.add(b, 'a', 10)
    Board.add(b, 'b', 10)
    Board.add(b, 'c', 10)
    check('tie keeps arrival order', order(b) == 'a,b,c', order(b))
    Board.add(b, 'c', 1)
    check('overtake moves to top', order(b) == 'c,a,b', order(b))
    Board.add(b, 'b', 1)                 -- b = 11 เท่ากับ c แต่มาทีหลัง → อยู่ใต้ c
    check('tie after overtake', order(b) == 'c,b,a', order(b))
end

do -- อันดับเดิม / ใหม่ ที่ Board.add คืน
    local b = Board.new()
    for i = 1, 5 do Board.add(b, 'p' .. i, 100 - i) end   -- p1..p5 เรียงอยู่แล้ว
    local old, new = Board.add(b, 'p5', 10)              -- 95 + 10 = 105 → ขึ้นที่ 1
    check('returned old rank', old == 5, ('old=%s'):format(old))
    check('returned new rank', new == 1, ('new=%s'):format(new))
    local o2, n2 = Board.add(b, 'p4', 1)                 -- 96 + 1 = 97 → ยังอยู่ใต้ p3 (97 มาก่อน)
    check('no move when tie not beaten', o2 == 5 and n2 == 5, ('old=%s new=%s'):format(o2, n2))
end

do -- push ตอนโหลด: id ซ้ำ = ข้าม
    local b = Board.new()
    Board.push(b, 'a', 50)
    Board.push(b, 'b', 40)
    Board.push(b, 'a', 999)
    check('push skips duplicate', Board.size(b) == 2 and Board.score(b, 'a') == 50)
end

do -- ไม่มีในกระดาน
    local b = Board.new()
    check('rank of missing = nil', Board.rank(b, 'x') == nil)
    check('rank of nil id = nil', Board.rank(b, nil) == nil)
    check('score of missing = nil', Board.score(b, 'x') == nil)
end

-- ── สุ่มเทียบตัวอ้างอิง ────────────────────────────────────

local function reference(players)
    local arr = {}
    for id, p in pairs(players) do arr[#arr + 1] = { id = id, score = p.score, seq = p.seq } end
    table.sort(arr, function(x, y)
        if x.score ~= y.score then return x.score > y.score end
        return x.seq < y.seq
    end)
    return arr
end

math.randomseed(12345)
for round = 1, 20 do
    local b, players, seq = Board.new(), {}, 0

    -- โหลดตั้งต้นแบบที่ SQL ส่งมา (เรียงมาก → น้อยแล้ว)
    local initial = math.random(0, 200)
    local scores = {}
    for i = 1, initial do scores[i] = math.random(0, 50) end
    table.sort(scores, function(x, y) return x > y end)
    for i = 1, initial do
        local id = 'init' .. i
        Board.push(b, id, scores[i])
        seq = seq + 1
        players[id] = { score = scores[i], seq = seq }
    end

    for _ = 1, 500 do
        local id = 'p' .. math.random(1, 300)     -- ปนคนเก่ากับคนใหม่
        if math.random() < 0.3 and initial > 0 then id = 'init' .. math.random(1, initial) end
        local delta = math.random(1, 5)
        Board.add(b, id, delta)
        seq = seq + 1
        local p = players[id] or { score = 0 }
        p.score, p.seq = p.score + delta, seq
        players[id] = p
    end

    local ref = reference(players)
    local ok = #ref == Board.size(b)
    for i = 1, #ref do
        local r, s = Board.rank(b, ref[i].id)
        if r ~= i or s ~= ref[i].score or b.list[i].id ~= ref[i].id then ok = false; break end
    end
    check(('random round %d'):format(round), ok)
end

print(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
