--- อ่าน config/jobs.lua + config/defaults.lua → Config.Jobs แบบ array ที่ทุกช่องมีค่าครบ (ครั้งเดียวตอนโหลด)
---
--- รันทั้ง client และ server ด้วยกติกาเดียวกัน → ลำดับงาน/ไอเทมตรงกันทั้งสองฝั่ง
--- client จึงส่งแค่ "เลขลำดับ" (jobIdx, itemIdx) ไม่ต้องส่งชื่อ
--- config ผิด = ตัดก้อนนั้นทิ้ง + เตือนใน console ฝั่ง server (resource ไม่ล่ม)
---
--- กติกา override (อธิบายให้ผู้ตั้งค่าไว้ที่หัว config/defaults.lua):
---   nil = ค่า default · false = ปิด · table ของ MERGE = ทับเฉพาะ key ที่ใส่ · อื่นๆ = ทับทั้งก้อน

local IS_SERVER <const> = IsDuplicityVersion()
local D <const> = Config.Default
local MIN_TICK <const> = Config.MinTickMs
local MERGE <const> = { vip = true, blip = true, marker = true, carryProp = true, effect = true, popProp = true }
local CONSUME <const> = { start = true, tick = true }

local function warn(fmt, ...)
    if IS_SERVER then print(('^3[lnn_alljob] ' .. fmt .. '^7'):format(...)) end
end

local function isPosInt(n) return math.type(n) == 'integer' and n > 0 end
local function isText(s) return type(s) == 'string' and s ~= '' end

local function merged(base, over)
    local out = {}
    for k, v in pairs(base) do out[k] = v end
    for k, v in pairs(over) do out[k] = v end
    return out
end

--- ค่าของช่องนี้หลังใช้กติกา override · base = ค่าชั้นบน (default ของงาน หรือค่าของงานสำหรับไอเทม)
local function pick(v, base, key)
    if v == false then return nil end
    if v == nil then return base end
    if MERGE[key] and type(v) == 'table' and type(base) == 'table' then return merged(base, v) end
    return v
end

-- ---------------- ตรวจ (คืน nil = ใช้ได้ · string = เหตุผล) ----------------

local function checkItem(it, i)
    if not isText(it.name) then return ('items[%d] ไม่มี name'):format(i) end
    if not isPosInt(it.perTick) then return ('items[%d] perTick ต้องเป็นจำนวนเต็มบวก'):format(i) end
    if not isPosInt(it.tickMs) or it.tickMs < MIN_TICK then return ('items[%d] tickMs ต้องเป็นจำนวนเต็ม %d ขึ้นไป'):format(i, MIN_TICK) end
    if math.type(it.score) ~= 'integer' or it.score < 0 then return ('items[%d] score ต้องเป็นจำนวนเต็ม 0 ขึ้นไป'):format(i) end
    if it.limit ~= nil and not isPosInt(it.limit) then return ('items[%d] limit ต้องเป็นจำนวนเต็มบวก'):format(i) end
    if it.popProp and not isText(it.popProp.model) then return ('items[%d] popProp ไม่มี model'):format(i) end
end

local function checkJob(job)
    if type(job.coords) ~= 'vector3' then return 'coords ต้องเป็น vec3' end
    if type(job.radius) ~= 'number' or job.radius <= 0 then return 'radius ต้องเป็นเลขบวก' end
    if #job.items == 0 then return 'ไม่มี items' end

    for i, r in ipairs(job.requires) do
        if not isText(r.name) or not isPosInt(r.count) then return ('requires[%d] ต้องมี name และ count เป็นจำนวนเต็มบวก'):format(i) end
        if r.consume and not CONSUME[r.consume] then return ('requires[%d] consume ต้องเป็น false · \'start\' · \'tick\''):format(i) end
    end
    for i, b in ipairs(job.bonus) do
        if not isText(b.name) or type(b.chance) ~= 'number' or b.chance <= 0 or b.chance > 100 then
            return ('bonus[%d] ต้องมี name และ chance มากกว่า 0 ไม่เกิน 100'):format(i)
        end
    end

    local rule = job.jobs
    if rule and ((rule.type ~= 'whitelist' and rule.type ~= 'blacklist') or type(rule.list) ~= 'table') then
        return 'jobs ต้องเป็น { type = \'whitelist\' | \'blacklist\', list = { ... } }'
    end
    local vip = job.vip
    if vip and (not isText(vip.item) or type(vip.itemMult) ~= 'number' or vip.itemMult < 1
        or type(vip.speedBonus) ~= 'number' or vip.speedBonus < 0) then
        return 'vip ต้องมี item · itemMult >= 1 · speedBonus >= 0'
    end
    if job.anim and (not isText(job.anim.dict) or not isText(job.anim.clip)) then return 'anim ต้องมี dict และ clip' end
    if job.carryProp and not isText(job.carryProp.model) then return 'carryProp ไม่มี model' end
    if job.centerProp and not isText(job.centerProp.model) then return 'centerProp ไม่มี model' end
    if job.effect and (not isText(job.effect.asset) or not isText(job.effect.fx)) then return 'effect ต้องมี asset และ fx' end

    for i, it in ipairs(job.items) do
        local why = checkItem(it, i)
        if why then return why end
    end
end

-- ---------------- ประกอบ ----------------

local function build(name, src)
    local job = {
        name       = name,
        label      = src.label or name,
        order      = src.order,
        coords     = src.coords,
        radius     = pick(src.radius, D.radius, 'radius'),
        vip        = pick(src.vip, D.vip, 'vip'),
        anim       = pick(src.anim, D.anim, 'anim'),
        carryProp  = pick(src.carryProp, D.carryProp, 'carryProp'),
        centerProp = pick(src.centerProp, D.centerProp, 'centerProp'),
        popProp    = pick(src.popProp, D.popProp, 'popProp'),
        effect     = pick(src.effect, D.effect, 'effect'),
        marker     = pick(src.marker, D.marker, 'marker'),
        blip       = pick(src.blip, D.blip, 'blip'),
        jobs       = pick(src.jobs, D.jobs, 'jobs'),
        requires   = pick(src.requires, D.requires, 'requires') or {},
        bonus      = pick(src.bonus, D.bonus, 'bonus') or {},
        items      = {},
    }

    local tickMs  = pick(src.tickMs, D.tickMs, 'tickMs')
    local perTick = pick(src.perTick, D.perTick, 'perTick')
    local score   = pick(src.score, D.score, 'score')
    local limit   = pick(src.limit, D.limit, 'limit')

    for i, it in ipairs(src.items or {}) do
        job.items[i] = {
            name    = it.name,
            label   = it.label or it.name,
            perTick = pick(it.perTick, perTick, 'perTick'),
            tickMs  = pick(it.tickMs, tickMs, 'tickMs'),
            score   = pick(it.score, score, 'score'),
            limit   = pick(it.limit, limit, 'limit'),
            popProp = pick(it.popProp, job.popProp, 'popProp'),
        }
    end
    for i, r in ipairs(job.requires) do
        job.requires[i] = { name = r.name, label = r.label or r.name, count = r.count or 1, consume = r.consume or false }
    end
    for i, b in ipairs(job.bonus) do
        job.bonus[i] = { name = b.name, label = b.label or b.name, chance = b.chance, limit = b.limit }
    end

    -- อาชีพ: เก็บเป็น set ไว้เช็ค O(1) ตอนกดเริ่ม
    if job.jobs then
        local set = {}
        for _, j in ipairs(job.jobs.list or {}) do set[j] = true end
        job.jobRule = { whitelist = job.jobs.type == 'whitelist', set = set }
    end
    -- requires แบบหักทุก tick แยกไว้ — tick ไม่ต้องไล่ทั้งลิสต์
    job.tickConsume = {}
    for _, r in ipairs(job.requires) do
        if r.consume == 'tick' then job.tickConsume[#job.tickConsume + 1] = r end
    end
    return job
end

-- ---------------- เรียง + ตรวจทุกงาน ----------------

local names = {}
for name in pairs(Config.Jobs) do names[#names + 1] = name end
table.sort(names, function(a, b)
    local oa, ob = Config.Jobs[a].order or math.huge, Config.Jobs[b].order or math.huge
    if oa ~= ob then return oa < ob end
    return a < b
end)

local list = {}
for _, name in ipairs(names) do
    local why
    if type(name) ~= 'string' or not name:match('^[%w_]+$') or #name > 32 then
        why = 'ชื่องานต้องเป็น a-z 0-9 _ ไม่เกิน 32 ตัว'
    elseif name == Config.TotalBoard then
        why = 'ชื่องานซ้ำกับชื่อสงวนของกระดานรวม'
    end

    local job = not why and build(name, Config.Jobs[name])
    why = why or checkJob(job)
    if why then
        warn('Config.Jobs[\'%s\']: %s — ข้ามงานนี้', tostring(name), why)
    else
        list[#list + 1] = job
    end
end
Config.Jobs = list
