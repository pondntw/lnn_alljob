--- Ranking — client (แผง NUI ใน html/)
---
--- /lnn_rank → เปิดแผง → เลือกกระดาน = server ลงชื่อเราเป็นผู้ชม แล้ว push มาเองเมื่อมีอะไรเปลี่ยน
---   rank:top = Top-N ใหม่ (ผู้ชมทุกคนของกระดาน) · rank:me = อันดับของเราเปลี่ยน (เฉพาะเรา)
--- ปิดแผง = แจ้ง server เลิกส่ง · แคชแถวตามเลข rev → เปิดกระดานเดิมซ้ำ server ไม่ต้องส่งแถวซ้ำ
--- NUI ส่งเฉพาะตอนข้อมูลเปลี่ยน (ไม่มีลูป)

local CMD <const> = Config.Ranking.Command
local LAST <const> = #Config.Jobs

local Cache = {}       -- [idx] = { rev, rows = { { ชื่อ, แต้ม } }, count, rank, score }
local Watching = nil   -- กระดานที่ server กำลังส่งให้เรา
local isOpen = false
local lastIdx = 0      -- เปิดครั้งหน้ากลับมาที่กระดานเดิม

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function boards()
    local list = { { idx = 0, label = Config.Ranking.TotalLabel } }
    for idx = 1, LAST do list[#list + 1] = { idx = idx, label = Config.Jobs[idx].label } end
    return list
end

local function stopWatching()
    if not Watching then return end
    Watching = nil
    TriggerServerEvent('lnn_alljob:rank:close')
end

local function sendBoard(idx)
    local c = Cache[idx]
    send('board', { idx = idx, rows = c.rows, count = c.count, rank = c.rank, score = c.score })
end

local function openBoard(idx)
    send('loading', idx)
    local c = Cache[idx]
    local res = lib.callback.await('lnn_alljob:rank:open', false, idx, c and c.rev)

    -- ปิดแผงระหว่างรอ server → server ลงชื่อเราไปแล้ว ต้องบอกเลิก
    if not isOpen then
        if res then TriggerServerEvent('lnn_alljob:rank:close') end
        return
    end
    if not res then
        lib.notify({ type = 'error', description = 'เปิดกระดานไม่ได้ ลองใหม่อีกครั้ง' })
        return
    end

    c = c or { rows = {} }
    Cache[idx] = c
    c.rev, c.count, c.rank, c.score = res.rev, res.count, res.rank, res.score
    if res.rows then c.rows = res.rows end

    Watching, lastIdx = idx, idx
    sendBoard(idx)
end

local function close()
    if not isOpen then return end
    isOpen = false
    SetNuiFocus(false, false)
    send('close')
    stopWatching()
end

local function open()
    if isOpen then return end
    isOpen = true
    SetNuiFocus(true, true)
    send('ui:theme', Config.UI)
    send('open', { boards = boards(), idx = lastIdx })
    CreateThread(function() openBoard(lastIdx) end)
end

RegisterNUICallback('select', function(data, cb)
    cb(1)
    local idx = math.tointeger(tonumber(data and data.idx))
    if isOpen and idx and idx >= 0 and idx <= LAST then
        CreateThread(function() openBoard(idx) end)
    end
end)

RegisterNUICallback('close', function(_, cb)
    cb(1)
    close()
end)

--- push ของกระดานที่ไม่ได้เปิดอยู่แล้ว (แผงปิด / เปลี่ยนกระดาน) = บอก server เลิกส่ง
local function accept(idx)
    if isOpen and Watching == idx and Cache[idx] then return Cache[idx] end
    stopWatching()
end

RegisterNetEvent('lnn_alljob:rank:top', function(idx, rev, rows, count)
    local c = accept(idx)
    if not c then return end
    c.rev, c.rows, c.count = rev, rows, count
    sendBoard(idx)
end)

RegisterNetEvent('lnn_alljob:rank:me', function(idx, rank, score)
    local c = accept(idx)
    if not c then return end
    c.rank, c.score = rank, score
    send('me', { idx = idx, rank = rank, score = score })
end)

RegisterCommand(CMD, open, false)
RegisterKeyMapping(CMD, 'เปิด Ranking All Job', 'keyboard', Config.Ranking.Key or '')
