--- แคช src → identifier — hot path ไม่ต้องถาม ESX
---
--- ผูกตอน esx:playerLoaded (handler ได้ xPlayer มาแล้ว อ่านชื่อได้ฟรี) · ปลดตอนหลุด/logout
--- restart กลางคัน = ไม่มีใครยิง esx:playerLoaded ให้ → Players.Scan() ไล่คนที่ออนไลน์อยู่

Players = {}

-- ESX Legacy รุ่นที่มี ESX.Player (proxy เบา เรียก method ทีละตัว) ใช้ตัวนั้น · รุ่นเก่าตกไป GetPlayerFromId
-- ทั้งสองแบบเรียก method ด้วย "." ได้เหมือนกัน
local getPlayer <const> = ESX.Player or ESX.GetPlayerFromId

local IdentOf = {}
local RestartDropped = nil   -- ระหว่าง Scan = {} · [src] = true คือคนที่ออกไประหว่างสแกน (ห้ามผูกกลับเป็นผี)

function Players.ident(src) return IdentOf[src] end
function Players.get(src) return getPlayer(src) end

local function bind(src, ident, name)
    IdentOf[src] = ident
    Ranking.SetName(ident, name)
end

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local src = tonumber(playerId)
    if src then bind(src, xPlayer.getIdentifier(), xPlayer.getName()) end
end)

--- หลุด / logout → คืน identifier เดิม (ไว้เซฟ)
function Players.forget(src)
    if RestartDropped then RestartDropped[src] = true end
    local ident = IdentOf[src]
    IdentOf[src] = nil
    return ident
end

--- restart กลางคัน — พักเฟรมทุก 64 คน (2 export ต่อคน)
function Players.Scan()
    RestartDropped = {}
    local list = GetPlayers()
    for i = 1, #list do
        if i % 64 == 0 then Wait(0) end
        local src = tonumber(list[i])
        if src and not RestartDropped[src] and not IdentOf[src] then
            local player = getPlayer(src)
            local ident = player and player.getIdentifier()
            if ident then bind(src, ident, player.getName()) end
        end
    end
    RestartDropped = nil
end
