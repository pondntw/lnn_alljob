--- บูต + วงจรชีวิต (เข้า/ออก · เซฟเป็นรอบ · หยุด/ปิดเซิร์ฟ)

local RES <const> = GetCurrentResourceName()

-- oxmysql พร้อมแล้วค่อยเริ่ม (cb รันใน thread ที่ await ได้)
MySQL.ready(function()
    Store.ensureTable()
    Ranking.Load()
    Players.Scan()        -- restart กลางคัน: ผูกคนที่ออนไลน์อยู่ (เข้าเกมใหม่ไม่ต้อง — esx:playerLoaded ผูกให้)
    Ranking.SetReady()    -- ก่อนนี้ begin ปฏิเสธหมด → ไม่มีแต้มเกิดก่อนกระดานโหลดเสร็จ

    while true do
        Wait(Config.Ranking.SaveIntervalMs)
        Store.saveAll()
    end
end)

--- ล้างทุกอย่างของ src · save = เซฟแต้มของคนนั้นด้วย
local function leave(src, save)
    local ident = Players.forget(src)
    Jobs.forget(src)
    Ranking.Forget(src)
    if save and ident then Store.saveOne(ident) end
end

-- esx:playerDropped ยิงทั้งตอนหลุดและตอน logout (multichar) · playerDropped ของเกมเก็บคนที่ยังไม่เคยโหลดตัวละคร
AddEventHandler('esx:playerDropped', function(playerId) leave(tonumber(playerId), true) end)
AddEventHandler('playerDropped', function() leave(source, false) end)

AddEventHandler('onResourceStop', function(res)
    if res == RES then Store.saveAllNoYield() end
end)

-- txAdmin ฆ่า process ตอนรีสตาร์ท → onResourceStop ไม่การันตี: เซฟก่อนรีสตาร์ท 30 วิ + ตอน shutdown
AddEventHandler('txAdmin:events:scheduledRestart', function(e)
    if e.secondsRemaining == 60 then SetTimeout(30000, Store.saveAllNoYield) end
end)
AddEventHandler('txAdmin:events:serverShuttingDown', Store.saveAllNoYield)
