-- ════════════════════════════════════════════════════════════
--  lnn_alljob — hook ฝั่ง client (ต่อระบบอื่นได้โดยไม่ต้องแก้ core)
--  ทุก hook ถูกเรียกใน pcall · ด่านจริงอยู่ที่ server เสมอ ตรงนี้แค่ไม่ยิงคำขอที่รู้ว่าไม่ผ่าน
-- ════════════════════════════════════════════════════════════

Config = Config or {}
Config.Hooks = Config.Hooks or {}

Config.Hooks.Client = {
    --- ก่อนขอเริ่มฟาร์ม → true = ขอได้ · false, 'เหตุผล' = ไม่ขอ (ขึ้นเหตุผลบน HUD)
    CanStart = function(jobName, itemName)
        -- ตัวอย่าง: ถูกใส่กุญแจมืออยู่ห้ามฟาร์ม
        -- if LocalPlayer.state.handcuffed then return false, 'ถูกใส่กุญแจมืออยู่' end
        return true
    end,

    --- เริ่มฟาร์มสำเร็จ · vip = true ถ้าได้บัฟบัตร VIP
    OnStart = function(jobName, itemName, vip)
    end,

    --- หยุดฟาร์ม · reason ดู Config.Text.stop
    OnStop = function(jobName, itemName, reason, gained)
    end,
}
