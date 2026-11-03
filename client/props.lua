--- prop ทั้งหมดของระบบ — สร้างแบบ local บนเครื่องตัวเองเสมอ (ไม่สร้าง network entity เลย)
---
---   ในมือ (carryProp) — คนรอบตัวต้องเห็น: server ตั้ง Player state 'lnnFarm' = { jobIdx, itemIdx } ตอนเริ่ม/ล้างตอนหยุด
---                       OneSync ส่ง state ให้เฉพาะเครื่องที่อยู่ในระยะของคนนั้น (คนเดินเข้ามาทีหลังได้ค่าทันที)
---                       ทุกเครื่องสร้าง prop local ติดมือ ped ของคนนั้นเอง
---   กลางวง (centerProp) — สร้างตอนเข้าใกล้วง ลบตอนออก (client/jobs.lua เรียก)
---   เด้งตอนได้ของ (popProp) — ของตัวเองเท่านั้น อยู่ ~1 วิแล้วลบ
---
--- โมเดลที่โหลดไม่ได้ = ข้ามเฉยๆ (lib.requestModel โยน error ตอนโหลดไม่ทัน → ครอบ pcall ทุกจุด)

Props = {}

local STATE <const> = 'lnnFarm'

local function loadModel(model)
    local ok, hash = pcall(lib.requestModel, model, 3000)
    return ok and hash or nil
end

local function spawnLocal(model, coords)
    local hash = loadModel(model)
    if not hash then return nil end
    local obj = CreateObject(hash, coords.x, coords.y, coords.z, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(obj, false, false)
    return obj
end

local function remove(obj)
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
end

-- ============================================================
-- prop ในมือ — reconcile ทุก 1 วิ เฉพาะตอนมีคนฟาร์มอยู่ในระยะ
-- ============================================================
-- Want[serverId] = config ของ prop ที่คนนั้นควรถือ · Held[serverId] = { obj, ped }
-- loop เดียวจัดการทุกกรณีที่ event บอกไม่ได้: ped ยังไม่เกิดตอน state มาถึง · ออกนอก scope · เกิดใหม่/เปลี่ยนโมเดล
local Want, Held = {}, {}
local looping = false

local function drop(serverId)
    local held = Held[serverId]
    if held then remove(held.obj); Held[serverId] = nil end
end

local function attach(serverId, cfg)
    local player = GetPlayerFromServerId(serverId)
    if player == -1 then return drop(serverId) end        -- ⚠️ นอก scope = -1 และ GetPlayerPed(-1) คือ ped ของเราเอง
    local ped = GetPlayerPed(player)
    if ped == 0 or not DoesEntityExist(ped) then return drop(serverId) end   -- ped หาย = prop ไม่ค้างลอยกลางอากาศ

    local held = Held[serverId]
    if held and held.ped == ped and DoesEntityExist(held.obj) then return end
    if held then remove(held.obj) end

    local obj = spawnLocal(cfg.model, GetEntityCoords(ped))
    if not obj then Held[serverId] = nil return end
    local p, r = cfg.pos or vec3(0.0, 0.0, 0.0), cfg.rot or vec3(0.0, 0.0, 0.0)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, cfg.bone or 28422), p.x, p.y, p.z, r.x, r.y, r.z,
        true, true, false, false, 2, true)
    Held[serverId] = { obj = obj, ped = ped }
end

local function reconcile()
    if looping then return end
    looping = true
    CreateThread(function()
        while next(Want) or next(Held) do
            for id, cfg in pairs(Want) do attach(id, cfg) end
            for id in pairs(Held) do
                if not Want[id] then drop(id) end
            end
            Wait(1000)
        end
        looping = false
    end)
end

AddStateBagChangeHandler(STATE, '', function(bagName, _, value)
    local player = GetPlayerFromStateBagName(bagName)
    if player == 0 then return end
    local serverId = GetPlayerServerId(player)

    local job = type(value) == 'table' and Config.Jobs[math.tointeger(value[1]) or 0]
    Want[serverId] = job and job.carryProp or nil         -- ตรวจชนิดก่อนใช้: ค่าใน state มาจากเครื่องอื่น
    reconcile()
end)

AddEventHandler('onPlayerDropped', function(serverId)   -- ผู้เล่นออกจากเซิร์ฟ (OneSync) — ไม่ต้องรอ loop
    Want[serverId] = nil
end)

-- ============================================================
-- prop กลางวง
-- ============================================================
local Center = {}   -- [job] = obj

function Props.Center(job, show)
    local cfg = job.centerProp
    if not cfg then return end
    if not show then remove(Center[job]); Center[job] = nil return end
    if Center[job] then return end

    local c = job.coords
    local obj = spawnLocal(cfg.model, vec3(c.x, c.y, c.z + (cfg.zOffset or 0.0)))
    if not obj then return end
    SetEntityHeading(obj, cfg.heading or 0.0)
    FreezeEntityPosition(obj, true)
    Center[job] = obj
end

-- ============================================================
-- prop เด้งตอนได้ของ (ตัวเองเท่านั้น) — มี deadline เสมอ
-- ============================================================
local POP_MS <const> = 900

local function lerp(a, b, t) return a + (b - a) * t end

function Props.Pop(cfg)
    if not cfg then return end
    CreateThread(function()
        local ped = cache.ped
        local base = GetEntityCoords(ped)
        local angle = math.random() * math.pi * 2
        local from = cfg.style == 'rise'
            and vec3(base.x + math.cos(angle) * 0.8, base.y + math.sin(angle) * 0.8, base.z - 1.0)
            or vec3(base.x + math.cos(angle) * 3.0, base.y + math.sin(angle) * 3.0, base.z - 0.6)

        local obj = spawnLocal(cfg.model, from)
        if not obj then return end

        local started = GetGameTimer()
        while true do
            local t = (GetGameTimer() - started) / POP_MS
            if t >= 1.0 or not DoesEntityExist(obj) then break end
            local to = GetEntityCoords(ped)
            if cfg.style == 'rise' then
                SetEntityCoordsNoOffset(obj, from.x, from.y, lerp(from.z, from.z + 2.2, t), false, false, false)
            else
                SetEntityCoordsNoOffset(obj, lerp(from.x, to.x, t), lerp(from.y, to.y, t), lerp(from.z, to.z + 0.4, t), false, false, false)
            end
            SetEntityHeading(obj, t * 540.0)
            SetEntityAlpha(obj, math.floor(255 * (1.0 - t * t)), false)
            Wait(0)
        end
        remove(obj)
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, held in pairs(Held) do remove(held.obj) end
    for _, obj in pairs(Center) do remove(obj) end
end)
