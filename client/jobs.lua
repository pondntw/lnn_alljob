--- ฟาร์มอัตโนมัติ — client (วาดวง · เมนูเลือกไอเทม · HUD · ท่า) · ของ/แต้มทั้งหมด server เป็นคนให้
---
--- โซนเป็น lib.points ของ ox_lib (สแกนแบบ grid ทุก 300 ms) · nearby ทุกเฟรมเฉพาะตอนอยู่ใกล้วง
--- → ไกลทุกวง = ไม่มีลูปทุกเฟรมเลย · ระหว่างฟาร์มมีลูปอ่านปุ่ม X ซึ่งจบเองถ้า tick จาก server ขาด
---
--- HUD / เมนู (html/hud.js) — ส่ง NUI เฉพาะตอนสถานะเปลี่ยน:
---   hud:show  เข้าวง          hud:start เริ่มฟาร์ม   hud:tick ได้ของ 1 รอบ   hud:stop หยุด
---   hud:fail  เริ่มไม่ได้      hud:hide  ออกจากวง     hud:select เมนูเลือกไอเทม (ยึดโฟกัส)

local KEYS <const> = Config.Keys
local DRAW <const> = Config.DrawDistance
local T <const> = Config.Text
local HOOK <const> = Config.Hooks.Client

local zone = nil         -- point ของวงที่ยืนอยู่ (HUD โชว์อยู่)
local farming = nil      -- { point, item, tickMs, lastTick } ระหว่างที่ server มี session
local busy = false       -- รอคำตอบ start / เมนูเลือกเปิดอยู่
local lastItem = {}      -- [jobIdx] = itemIdx ที่เลือกล่าสุด (เมนูเปิดมาที่ตัวนั้น)
local hudCache = {}
local themeSent = false

local function send(action, data)
    if not themeSent then
        themeSent = true
        SendNUIMessage({ action = 'ui:theme', data = Config.UI })
    end
    SendNUIMessage({ action = action, data = data })
end

local function callHook(name, ...)
    local fn = HOOK[name]
    if not fn then return true end
    local ok, a, b = pcall(fn, ...)
    if not ok then
        print(('^1[lnn_alljob] hook %s error: %s^7'):format(name, tostring(a)))
        return false
    end
    return a, b
end

local function itemView(it)
    return {
        label = it.label, perTick = it.perTick, tickMs = it.tickMs, score = it.score, limit = it.limit,
        img = Config.ItemImage ~= '' and Config.ItemImage:format(it.name) or nil,
    }
end

--- ข้อมูลคงที่ของงานสำหรับ HUD (สร้างครั้งแรกที่ใช้ แล้วแคช)
local function hudPayload(job)
    local p = hudCache[job]
    if p then return p end

    local items, bonus, need = {}, {}, {}
    for i, it in ipairs(job.items) do items[i] = itemView(it) end
    for i, b in ipairs(job.bonus) do bonus[i] = b.label end
    for _, r in ipairs(job.requires) do need[#need + 1] = r.count > 1 and ('%s x%d'):format(r.label, r.count) or r.label end

    p = { job = job.label, items = items, bonus = bonus, need = need, text = T.hud }
    hudCache[job] = p
    return p
end

-- ---------------- ท่า + เอฟเฟกต์ ----------------

-- ⚠️ lib.request* โยน error เมื่อโหลดไม่ทัน → ครอบ pcall เสมอ ไม่งั้น thread ฟาร์มตายทั้งที่ farming ยังค้าง
local function playAnim(ped, anim)
    if anim and pcall(lib.requestAnimDict, anim.dict, 3000) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, -3.0, -1, 49, 0, false, false, false)   -- 49 = วน + ท่อนบน (เดินได้)
    end
end

local function stopAnim(ped, anim)
    if not anim then return end
    StopAnimTask(ped, anim.dict, anim.clip, 2.0)
    RemoveAnimDict(anim.dict)
end

--- asset โหลดครั้งเดียวตอนเริ่มฟาร์ม (ไม่ใช่ทุก tick) แล้วคืนตอนหยุด
local function playEffect(ped, fx)
    if not fx or not HasNamedPtfxAssetLoaded(fx.asset) then return end
    UseParticleFxAsset(fx.asset)
    StartParticleFxNonLoopedOnEntity(fx.fx, ped, 0.0, 0.0, 0.2, 0.0, 0.0, 0.0, fx.scale or 1.0, false, false, false)
end

-- ---------------- ฟาร์ม ----------------

local function endFarm(reason, gained)
    local f = farming
    if not f then return end
    farming = nil
    local job = f.point.job
    stopAnim(cache.ped, job.anim)
    if job.effect then RemoveNamedPtfxAsset(job.effect.asset) end
    callHook('OnStop', job.name, f.item.name, reason, gained or 0)

    if not zone then return send('hud:hide') end
    local text = T.stop[reason] or T.stop.manual
    if (gained or 0) > 0 then text = T.hud.gained:format(text, f.item.label, gained) end
    send('hud:stop', { text = text, ok = reason == 'manual' or reason == 'full' })
end

--- ระหว่างฟาร์ม: อ่านปุ่ม X ทุกเฟรม · ย้ำท่าทุก 1 วิ (กระโดด/ล้มแล้วท่าหลุด)
--- deadline = tick จาก server ต้องมาภายใน 3 รอบ ไม่งั้นถือว่าขาด (กันลูปค้างทั้งเซสชัน)
local function farmLoop(f)
    local anim = f.point.job.anim
    local grace = f.tickMs * 3 + 2000
    local nextAnim = 0
    while farming == f do
        Wait(0)
        local now = GetGameTimer()
        if IsControlJustPressed(0, KEYS.stop) then
            TriggerServerEvent('lnn_alljob:stop')
        elseif now - f.lastTick > grace then
            TriggerServerEvent('lnn_alljob:stop')
            endFarm('timeout')
        elseif anim and now >= nextAnim then
            nextAnim = now + 1000
            local ped = cache.ped
            if not IsEntityPlayingAnim(ped, anim.dict, anim.clip, 3) then playAnim(ped, anim) end
        end
    end
end

local function start(point, itemIdx)
    local job, item = point.job, point.job.items[itemIdx]
    local allowed, reason = callHook('CanStart', job.name, item.name)
    if allowed ~= true then
        busy = false
        return send('hud:fail', { text = reason or T.cannot_start })
    end

    lastItem[point.jobIdx] = itemIdx
    local ok, res = lib.callback.await('lnn_alljob:start', false, point.jobIdx, itemIdx)
    busy = false
    if not ok then return send('hud:fail', { text = res or T.cannot_start }) end

    local f = { point = point, item = item, tickMs = res.tickMs, lastTick = GetGameTimer() }
    farming = f
    playAnim(cache.ped, job.anim)
    if job.effect then pcall(lib.requestNamedPtfxAsset, job.effect.asset, 2000) end
    send('hud:start', { item = itemIdx, count = res.count, rank = res.rank, perTick = res.perTick, tickMs = res.tickMs, limit = res.limit, vip = res.vip })
    callHook('OnStart', job.name, item.name, res.vip == true)
    farmLoop(f)
end

RegisterNetEvent('lnn_alljob:tick', function(count, rank, bonus)
    local f = farming
    if not f then return end
    f.lastTick = GetGameTimer()

    local labels
    if bonus then
        labels = {}
        local list = f.point.job.bonus
        for i = 1, #bonus do labels[i] = list[bonus[i]] and list[bonus[i]].label end
    end
    send('hud:tick', { count = count, rank = rank, bonus = labels })
    playEffect(cache.ped, f.point.job.effect)
    Props.Pop(f.item.popProp)
end)

RegisterNetEvent('lnn_alljob:stopped', function(reason, gained)
    endFarm(reason, gained)
end)

-- ---------------- เมนูเลือกไอเทม (วงที่มีหลายไอเทม) ----------------

local selecting = nil    -- point ที่เปิดเมนูอยู่

local function closeSelect()
    if not selecting then return end
    selecting = nil
    SetNuiFocus(false, false)
end

local function openSelect(point)
    selecting = point
    SetNuiFocus(true, true)
    send('hud:select', { index = lastItem[point.jobIdx] or 1 })
end

RegisterNUICallback('pick', function(data, cb)
    cb(1)
    local point = selecting
    closeSelect()
    local idx = math.tointeger(tonumber(data and data.idx))
    if not point or not idx or not point.job.items[idx] or zone ~= point then busy = false return end
    CreateThread(function() start(point, idx) end)
end)

RegisterNUICallback('cancelPick', function(_, cb)
    cb(1)
    closeSelect()
    busy = false
end)

-- ---------------- วง ----------------

local function canStart()
    local ped = cache.ped
    return not IsEntityDead(ped) and not IsPedInAnyVehicle(ped, false)
end

local function pressStart(point)
    busy = true
    if #point.job.items > 1 then return openSelect(point) end
    CreateThread(function() start(point, 1) end)
end

local function nearby(self)
    local job, c, m = self.job, self.coords, self.job.marker
    if m then
        DrawMarker(m.type or 1, c.x, c.y, c.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, job.radius * 2.0, job.radius * 2.0, m.height or 0.6,
            m.color[1], m.color[2], m.color[3], m.color[4], false, false, 2, false, nil, nil, false)
    end

    local inside = self.currentDistance <= job.radius
    if inside and zone ~= self then
        zone = self
        if not farming then send('hud:show', hudPayload(job)) end
    elseif not inside and zone == self then
        zone = nil
        if selecting == self then closeSelect(); busy = false end
        if not farming then send('hud:hide') end         -- กำลังฟาร์ม = รอ server หยุดให้ (left_zone) แล้วค่อยซ่อน
    end

    if inside and not farming and not busy and IsControlJustReleased(0, KEYS.start) and canStart() then
        pressStart(self)
    end
end

local function onEnter(self) Props.Center(self.job, true) end

local function onExit(self)
    Props.Center(self.job, false)
    if zone ~= self then return end
    zone = nil
    if not farming then send('hud:hide') end
end

for jobIdx, job in ipairs(Config.Jobs) do
    lib.points.new({
        coords = job.coords,
        distance = job.radius + DRAW,
        nearby = nearby,
        onEnter = onEnter,
        onExit = onExit,
        jobIdx = jobIdx, job = job,
    })

    local blip = job.blip
    if blip then
        local c = job.coords
        local b = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(b, blip.sprite or 1)
        SetBlipColour(b, blip.color or 0)
        SetBlipScale(b, blip.scale or 0.9)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(T.blip:format(job.label))
        EndTextCommandSetBlipName(b)

        if blip.radius then
            local r = AddBlipForRadius(c.x, c.y, c.z, job.radius)
            SetBlipColour(r, blip.radiusColor or blip.color or 0)
            SetBlipAlpha(r, blip.radiusAlpha or 80)
        end
    end
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if farming then stopAnim(cache.ped, farming.point.job.anim) end
    if selecting then SetNuiFocus(false, false) end
end)
