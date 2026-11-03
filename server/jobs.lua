--- ฟาร์มอัตโนมัติ — server ตัดสินทุกอย่าง client ส่งแค่เลขลำดับ (jobIdx, itemIdx)
---
---   start → ตรวจ (พร้อม · ในวง · อาชีพ · ของที่ต้องมี · ที่ว่าง · hook) → คิด VIP → เปิด session
---   tick  → ทุก tickMs: ยังอยู่ไหม · ยังไม่ตาย · ยังในวง · อุปกรณ์ยังพอ · ยังไม่ถึง limit → ให้ของ + โบนัส + แต้ม Ranking
---   stop  → กด X / ออกวง / ตาย / ถึง limit / อุปกรณ์หมด / หลุด
---
--- เพดาน = limit ของไอเทมในกระเป๋า (จำนวนที่ถือได้ ไม่ใช่น้ำหนัก · ไม่เรียก canCarryItem) — ดู capOf
---
--- timer แยกต่อ session (SetTimeout) แทน thread กลางที่ตื่นมาสแกนทุกคน:
---   ไม่มีคนฟาร์ม = ไม่มี timer · มีคนฟาร์ม = ตื่นตรงรอบของแต่ละคนพอดี
---   ตัว table ของ session คือ "รุ่น" — หยุด/เริ่มใหม่ = table ใหม่ → timer ของรอบเก่าจบเอง ไม่ต้องยกเลิก
--- ไอเทม / จำนวน / แต้ม มาจาก config ฝั่ง server ทั้งหมด → client ปลอมค่าไม่ได้

Jobs = {}

local PAD <const> = Config.ZonePad
local MIN_TICK <const> = Config.MinTickMs
local T <const> = Config.Text
local HOOK <const> = Config.Hooks.Server
local STATE <const> = 'lnnFarm'           -- Player state: { jobIdx, itemIdx } ระหว่างฟาร์ม → คนรอบตัววาด prop ในมือ
local EV_TICK <const> = 'lnn_alljob:tick'
local EV_STOPPED <const> = 'lnn_alljob:stopped'

local Sessions = {}   -- [src] = { job, jobIdx, item, itemIdx, ident, player, count, gained, perTick, tickMs, state }

--- เรียก hook แบบไม่ให้ hook พังลากระบบพังตาม
local function callHook(name, ...)
    local fn = HOOK[name]
    if not fn then return true end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        print(('^1[lnn_alljob] hook %s error: %s^7'):format(name, tostring(a)))
        return false, nil, true
    end
    return a, b
end

local function setFarmState(src, value)
    pcall(function() Player(src).state:set(STATE, value, true) end)   -- ผู้เล่นหลุดไปแล้ว = ไม่มี bag ให้ตั้ง
end

local function stop(src, reason)
    local s = Sessions[src]
    if not s then return end
    Sessions[src] = nil
    setFarmState(src, nil)
    TriggerClientEvent(EV_STOPPED, src, reason, s.gained)
    callHook('OnStop', src, s.job.name, s.item.name, reason, s.gained)
end

--- หลุดเกม — ทิ้ง session (ของที่ได้เข้ากระเป๋าไปทีละ tick แล้ว ไม่มีอะไรค้างจ่าย)
function Jobs.forget(src)
    local s = Sessions[src]
    if not s then return end
    Sessions[src] = nil
    callHook('OnStop', src, s.job.name, s.item.name, 'dropped', s.gained)
end

local function inZone(ped, job)
    return #(GetEntityCoords(ped) - job.coords) <= job.radius + PAD
end

--- จำนวนที่ถือไอเทมนี้ได้สูงสุดในกระเป๋า (ระบบ limit ของ ESX ไม่ใช่น้ำหนัก · nil = ไม่จำกัด)
---   limit จริง: ไอเทมในกระเป๋า (getInventoryItem คืน limit มาด้วย) → ไม่มี = แคตตาล็อก ESX.Items · -1 = ไม่จำกัด
---   limit ใน config = เพดานของการฟาร์มที่ "ต่ำกว่า" ได้ แต่ไม่เกิน limit จริง
---   (addInventoryItem ของ ESX ไม่เช็ค limit เอง — เกินเมื่อไหร่ ของล้นกระเป๋า)
local function capOf(cfgLimit, invItem, name)
    local lim = invItem and tonumber(invItem.limit)
    if lim == nil then
        local def = ESX.Items and ESX.Items[name]
        lim = def and tonumber(def.limit)
    end
    if lim and lim < 0 then lim = nil end
    if cfgLimit and (not lim or cfgLimit < lim) then return cfgLimit end
    return lim
end

local function jobAllowed(job, player)
    local rule = job.jobRule
    if not rule then return true end
    local inList = rule.set[player.getJob().name] == true
    return inList == rule.whitelist
end

local function tick(src, s)
    local job, item, player = s.job, s.item, s.player
    local ped = GetPlayerPed(src)
    if ped == 0 then return stop(src, 'dropped') end
    if GetEntityHealth(ped) <= 0 then return stop(src, 'died') end   -- IsEntityDead เป็น native ฝั่ง client
    if not inZone(ped, job) then return stop(src, 'left_zone') end

    -- อุปกรณ์ที่หักทุก tick ต้องพอก่อน (ยังไม่หัก — หักหลังให้ของสำเร็จ)
    local tc = job.tickConsume
    for i = 1, #tc do
        local have = player.getInventoryItem(tc[i].name)
        if not have or have.count < tc[i].count then return stop(src, 'no_tool') end
    end

    -- จำนวนจริงในกระเป๋าทุก tick (export เดียว) — ผู้เล่นมอบ/ใช้ของระหว่างฟาร์มก็นับถูก
    local have = player.getInventoryItem(item.name)
    if not have then return stop(src, 'dropped') end
    local count = have.count or 0

    local add = s.perTick
    if s.cap then add = math.min(add, s.cap - count) end   -- ไม่ให้เกิน limit
    if add <= 0 then return stop(src, 'full') end

    player.addInventoryItem(item.name, add)
    for i = 1, #tc do player.removeInventoryItem(tc[i].name, tc[i].count) end
    count = count + add
    s.gained = s.gained + add

    -- โบนัสสุ่มแยกกันทุกตัว เฉพาะรอบที่ได้ของปกติ · ถึง limit ของโบนัสตัวนั้น = ข้าม (ไม่หยุดฟาร์ม)
    -- อ่านกระเป๋าเฉพาะตอนสุ่มออก (ส่วนใหญ่ไม่ออก = ไม่มี export เพิ่ม)
    local got
    for i = 1, #job.bonus do
        local b = job.bonus[i]
        if math.random() * 100 < b.chance then
            local bItem = player.getInventoryItem(b.name)
            local bCap = capOf(b.limit, bItem, b.name)
            if bItem and (not bCap or (bItem.count or 0) < bCap) then
                player.addInventoryItem(b.name, 1)
                got = got or {}
                got[#got + 1] = i                              -- ส่งเลขลำดับโบนัส client หา label จาก config เอง
            end
        end
    end

    local rank = item.score > 0 and Ranking.Add(s.ident, s.jobIdx, item.score) or nil
    -- ส่งแค่จำนวน + อันดับ + โบนัสรอบนี้ (ไม่มี = nil ไม่กินไบต์) · ค่าคงที่ของงาน client มีใน config อยู่แล้ว
    TriggerClientEvent(EV_TICK, src, count, rank, got)
    callHook('OnTick', src, player, job.name, item.name, add, got)

    if s.cap and count >= s.cap then stop(src, 'full') end
end

local function schedule(src, s)
    SetTimeout(s.tickMs, function()
        if Sessions[src] ~= s then return end              -- ถูกหยุด/เริ่มใหม่ไปแล้ว
        local ok, err = pcall(tick, src, s)
        if not ok then
            print(('^1[lnn_alljob] tick error src=%s: %s^7'):format(src, tostring(err)))
            return stop(src, 'error')                      -- พังแค่ session นี้ ไม่ลามไปคนอื่น
        end
        if Sessions[src] == s then schedule(src, s) end
    end)
end

lib.callback.register('lnn_alljob:start', function(src, jobIdx, itemIdx)
    if not Ranking.IsReady() then return false, T.not_ready end
    if Sessions[src] then return false, T.already end

    local ident = Players.ident(src)
    jobIdx, itemIdx = math.tointeger(jobIdx), math.tointeger(itemIdx)
    local job = jobIdx and Config.Jobs[jobIdx]
    local item = job and itemIdx and job.items[itemIdx]
    if not ident or not item then return false, T.cannot_start end

    local ped = GetPlayerPed(src)
    if ped == 0 or not inZone(ped, job) then return false, T.out_of_zone end

    local player = Players.get(src)
    if not player then return false, T.not_loaded end
    if not jobAllowed(job, player) then return false, T.wrong_job end

    -- อ่านกระเป๋าครั้งเดียว (map ชื่อ → จำนวน) ใช้ทั้งของที่ต้องมี · บัตร VIP · จำนวนตั้งต้น
    local inv = player.getInventory(true)
    for _, r in ipairs(job.requires) do
        if (inv[r.name] or 0) < r.count then return false, T.need_item:format(r.label, r.count) end
    end

    -- limit ของไอเทมคงที่ทั้ง session → อ่านครั้งเดียวตอนเริ่ม
    local invItem = player.getInventoryItem(item.name)
    local have = invItem and invItem.count or 0
    local cap = capOf(item.limit, invItem, item.name)
    if cap and have >= cap then return false, T.bag_full end

    local allowed, reason, broken = callHook('CanStart', src, player, job.name, item.name)
    if allowed ~= true then return false, (not broken and reason) or T.cannot_start end

    -- VIP: มีบัตร = ได้ของ x itemMult และ tick เร็วขึ้น (คิดครั้งเดียวทั้ง session)
    local vip = job.vip and (inv[job.vip.item] or 0) > 0
    local perTick, tickMs = item.perTick, item.tickMs
    if vip then
        perTick = math.floor(perTick * job.vip.itemMult)
        tickMs = math.max(MIN_TICK, math.floor(tickMs / (1 + job.vip.speedBonus)))
    end

    for _, r in ipairs(job.requires) do
        if r.consume == 'start' then player.removeInventoryItem(r.name, r.count) end
    end

    -- เก็บ proxy ไว้ใน session → tick ไม่ต้องถาม ESX หาผู้เล่นซ้ำ (tick = getInventoryItem + addInventoryItem)
    local s = {
        job = job, jobIdx = jobIdx, item = item, itemIdx = itemIdx, ident = ident, player = player,
        cap = cap, gained = 0, perTick = perTick, tickMs = tickMs, state = { jobIdx, itemIdx },
    }
    Sessions[src] = s
    setFarmState(src, s.state)
    schedule(src, s)

    return true, { count = have, limit = cap, rank = Ranking.RankOf(ident, jobIdx), perTick = perTick, tickMs = tickMs, vip = vip or nil }
end)

RegisterNetEvent('lnn_alljob:stop', function()
    stop(source, 'manual')
end)

-- client เขียน state ของตัวเองได้ (strict mode ปิดอยู่เป็นค่าเริ่มต้น) → เขียนค่าของ server ทับกลับ
-- การเขียนของ server เองไม่ใช่ replicated จึงไม่วนกลับมาที่นี่
AddStateBagChangeHandler(STATE, '', function(bagName, _, _, _, replicated)
    if not replicated then return end
    local src = GetPlayerFromStateBagName(bagName)
    if src == 0 then return end
    local s = Sessions[src]
    setFarmState(src, s and s.state or nil)
end)
