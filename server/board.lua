--- กระดานอันดับ 1 กระดาน — pure Lua ไม่มี native (เทสนอกเกมได้)
---
--- โครงสร้าง:
---   list[i]  = entry อันดับ i (เรียงมาก → น้อย)
---   byId[id] = entry           entry = { id, score, seq }
---
--- ลำดับ: score มากอยู่บน · score เท่ากัน = seq น้อยอยู่บน (ถึงแต้มนี้ก่อน)
--- → key (score, seq) ไม่ซ้ำกันเลย หาตำแหน่งของ entry ไหนก็ได้ด้วย binary search ตัวเดียว
---
--- ทำไมไม่เก็บ map "id → อันดับ":
---   แต้มขยับ 1 ครั้ง อันดับของทุกคนที่ถูกแซงเปลี่ยนตาม → ต้องไล่อัปเดตใน Lua
---   (คนแต้มเท่ากันเป็นหมื่น = หมื่นรอบ) แบบนี้ใช้ binary search O(log n)
---   แล้วขยับช่วงด้วย table.move ซึ่งวนใน C

Board = {}

--- a อยู่เหนือ b ไหม
local function above(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.seq < b.seq
end

--- ตำแหน่งแรกใน [lo, hi) ที่ไม่อยู่เหนือ e (= ตำแหน่งของ e ถ้ามันอยู่ในช่วงนี้)
local function seek(list, e, lo, hi)
    while lo < hi do
        local mid = (lo + hi) // 2
        if above(list[mid], e) then lo = mid + 1 else hi = mid end
    end
    return lo
end

function Board.new()
    return { list = {}, byId = {}, seq = 0 }
end

--- ต่อท้ายตอนโหลด — แถวต้องมาเรียงมาก → น้อยแล้ว (SQL เรียงให้) · id ซ้ำ = ข้าม
function Board.push(b, id, score)
    if b.byId[id] then return end
    b.seq = b.seq + 1
    local e = { id = id, score = score, seq = b.seq }
    b.byId[id] = e
    b.list[#b.list + 1] = e
end

--- บวกแต้ม (delta > 0) → คืน อันดับเดิม, อันดับใหม่ (คนใหม่ อันดับเดิม = ท้ายกระดาน + 1)
function Board.add(b, id, delta)
    local list, e = b.list, b.byId[id]
    local old
    if e then
        old = seek(list, e, 1, #list + 1)        -- หาด้วย key เดิมก่อนแก้แต้ม
    else
        e = { id = id, score = 0, seq = 0 }
        b.byId[id] = e
        old = #list + 1
    end

    b.seq = b.seq + 1
    e.score = e.score + delta
    e.seq = b.seq

    -- แต้มขึ้นอย่างเดียว → ตำแหน่งใหม่อยู่ในช่วงเหนือตำแหน่งเดิมเท่านั้น
    -- ทุกคนที่อยู่ใต้ตำแหน่งเดิมก็ยังอยู่ใต้ e เหมือนเดิม
    local new = seek(list, e, 1, old)
    if new < old then
        table.move(list, new, old - 1, new + 1)  -- ดันช่วงที่ถูกแซงลง 1 ช่อง (ช่วงทับกันได้ — Lua จัดการให้)
    end
    list[new] = e
    return old, new
end

--- อันดับ + แต้ม (nil = ยังไม่ติดกระดาน)
function Board.rank(b, id)
    local e = id and b.byId[id]
    if not e then return nil end
    return seek(b.list, e, 1, #b.list + 1), e.score
end

function Board.score(b, id)
    local e = b.byId[id]
    return e and e.score
end

function Board.size(b)
    return #b.list
end

return Board
