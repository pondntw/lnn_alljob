--- วัดความเร็ว server/board.lua นอกเกม:  lua tests/board_bench.lua [จำนวนคน]
---
--- ตัวเลขขึ้นกับเครื่อง ใช้ดูสัดส่วนมากกว่าค่าตายตัว · ใน FiveM (Lua 5.4 ของ CitizenFX) จะต่างไปบ้าง

local dir = (arg and arg[0] or ''):match('^(.*)[/\\]') or '.'
dofile(dir .. '/../server/board.lua')

local N = tonumber(arg and arg[1]) or 50000
local OPS = 200000

local function us(seconds, count) return seconds / count * 1e6 end

math.randomseed(42)

-- กระดาน N คน แต้มสุ่ม (โหลดแบบเรียงมาแล้วเหมือนตอนบูต)
local function randomBoard()
    local scores = {}
    for i = 1, N do scores[i] = math.random(0, 100000) end
    table.sort(scores, function(x, y) return x > y end)
    local b = Board.new()
    for i = 1, N do Board.push(b, i, scores[i]) end
    return b
end

-- 1) บวกแต้มทั่วไป: คนสุ่ม +1..10
local b = randomBoard()
local ids = {}
for i = 1, OPS do ids[i] = math.random(1, N) end
local t = os.clock()
for i = 1, OPS do Board.add(b, ids[i], math.random(1, 10)) end
local addUs = us(os.clock() - t, OPS)

-- 2) หาอันดับ
t = os.clock()
for i = 1, OPS do Board.rank(b, ids[i]) end
local rankUs = us(os.clock() - t, OPS)

-- 3) กรณีแย่สุด: ทุกคนแต้มเท่ากัน คนท้ายสุดได้ +1 → แซงทั้งกระดาน (table.move ขยับ ~N ช่อง)
local tied = Board.new()
for i = 1, N do Board.push(tied, i, 100) end
local WORST = 200
t = os.clock()
for i = 1, WORST do Board.add(tied, N - i + 1, 1) end
local worstUs = us(os.clock() - t, WORST)

print(('Board %d คน (%s)'):format(N, _VERSION))
print(('  บวกแต้ม (คนสุ่ม +1..10)   %8.2f µs/ครั้ง'):format(addUs))
print(('  หาอันดับ                  %8.2f µs/ครั้ง'):format(rankUs))
print(('  แย่สุด (แซงคนแต้มเท่ากัน %d คน) %8.2f µs/ครั้ง'):format(N, worstUs))
