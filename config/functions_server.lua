-- ════════════════════════════════════════════════════════════
--  lnn_alljob — hook ฝั่ง server (ต่อระบบอื่นได้โดยไม่ต้องแก้ core)
--  ทุก hook ถูกเรียกใน pcall: hook พัง = เตือนใน console · CanStart พัง = ไม่ให้เริ่ม (ปลอดภัยไว้ก่อน)
--
--  ⚠️ player ในทุก hook = ESX.Player(src) (proxy) → เรียกได้เฉพาะ method
--     ใช้ player.getIdentifier() / player.getJob() แทน player.identifier / player.job
--  ⚠️ OnTick ถูกเรียกทุก tick ของทุกคนที่ฟาร์ม — อย่าทำงานหนัก (SQL / HTTP) ในนั้น
-- ════════════════════════════════════════════════════════════

Config = Config or {}
Config.Hooks = Config.Hooks or {}

Config.Hooks.Server = {
    --- ก่อนเริ่มฟาร์ม (หลังผ่านด่านของระบบแล้ว) → true = ให้เริ่ม · false, 'เหตุผล' = ไม่ให้
    ---@param src number · player proxy · jobName string · itemName string
    CanStart = function(src, player, jobName, itemName)
        -- ตัวอย่าง: ห้ามฟาร์มทองถ้าอยู่ในแก๊ง
        -- if itemName == 'lnn_gold' and exports['my_gang']:IsInGang(src) then return false, 'สมาชิกแก๊งขุดทองไม่ได้' end
        return true
    end,

    --- ได้ของ 1 tick · bonus = { 'ชื่อไอเทม', ... } หรือ nil
    OnTick = function(src, player, jobName, itemName, amount, bonus)
    end,

    --- หยุดฟาร์ม · reason = manual · left_zone · died · full (ถึง limit) · no_tool · error · dropped
    OnStop = function(src, jobName, itemName, reason, gained)
        -- ตัวอย่าง log:
        -- print(('[lnn_alljob] %d หยุด %s (%s) ได้ %s %d ชิ้น'):format(src, jobName, reason, itemName, gained))
    end,
}
