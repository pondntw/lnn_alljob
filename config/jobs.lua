-- ════════════════════════════════════════════════════════════
--  lnn_alljob — งานฟาร์ม (โซนฟาร์มอัตโนมัติ)
--  เดินเข้าวง → กด E (หลายไอเทม = เลือกก่อน) → ได้ของเองทุก tick จนกว่า:
--  กด X · ออกนอกวง · ตาย · ถึงจำนวนที่ถือได้ (limit) · อุปกรณ์ที่หักทุก tick หมด
--
--  Config.Jobs['ชื่องาน'] = { ... }
--    ชื่องาน = คีย์ในฐานข้อมูลของ Ranking (a-z 0-9 _ · ไม่เกิน 32 ตัว)
--    ⚠️ เปลี่ยนชื่องานหลังเปิดใช้ = แต้มเดิมของงานนั้นหาย
--
--  ช่องของงาน (ไม่ใส่ = ใช้ค่าใน defaults.lua):
--    label      ชื่อที่โชว์                      order    ลำดับบนกระดาน/เมนู (ไม่ใส่ = เรียงตามชื่องาน)
--    coords     กลางวง (vec3)                   radius   รัศมีวง
--    items      ไอเทมที่ฟาร์มได้ — 1 ตัว = กด E เริ่มเลย · หลายตัว = เปิดเมนูเลือก
--               { name, label, perTick, tickMs, score, limit, popProp }   (ช่องที่ไม่ใส่ = ใช้ของงาน)
--    tickMs · perTick · score · limit · vip · jobs · requires · bonus
--    anim · carryProp · centerProp · popProp · effect · marker · blip
--
--  ⚠️ พิกัดและชื่อโมเดล prop ในไฟล์นี้เป็นค่าตัวอย่าง · โมเดลที่โหลดไม่ได้ = ข้ามเฉยๆ ไม่ error
--  ⚠️ ไอเทมทุกตัวต้องมีใน ESX ก่อน (ดู sql/lnn_alljob.sql)
-- ════════════════════════════════════════════════════════════

Config = Config or {}
Config.Jobs = {}

-- ─── ตัดไม้ — ต้องมีขวาน (ไม่หัก) ───────────────────────────────────────────────
Config.Jobs['lumber'] = {
    label  = 'ตัดไม้',
    order  = 1,
    coords = vec3(-570.0, 5370.0, 70.0),
    items  = {
        { name = 'lnn_wood', label = 'ไม้ท่อน' },
    },
    requires = {
        { name = 'lnn_axe', label = 'ขวาน', count = 1, consume = false },
    },
    bonus = {
        { name = 'lnn_resin', label = 'ยางไม้', chance = 3 },
    },
    centerProp = { model = 'prop_log_01', zOffset = -1.0, heading = 0.0 },
    popProp    = { model = 'prop_log_01', style = 'float' },
    blip       = { sprite = 77, color = 25 },
}

-- ─── ขุดแร่ — หลายไอเทม (เมนูเลือก) · แร่ทองช้ากว่าแต่แต้มเยอะ ──────────────────
Config.Jobs['mining'] = {
    label  = 'ขุดแร่',
    order  = 2,
    coords = vec3(2955.0, 2790.0, 41.0),
    radius = 25.0,
    items  = {
        { name = 'lnn_stone', label = 'ก้อนแร่', perTick = 2 },
        { name = 'lnn_gold',  label = 'แร่ทอง', perTick = 1, tickMs = 8000, score = 3, limit = 50 },
    },
    requires = {
        { name = 'lnn_pickaxe', label = 'อีเต้อ', count = 1, consume = false },
    },
    bonus = {
        { name = 'lnn_gem', label = 'อัญมณี', chance = 2 },
    },
    vip       = { itemMult = 3 },                             -- ทับเฉพาะ itemMult (บัตร/ความเร็วตาม defaults)
    jobs      = { type = 'blacklist', list = { 'police', 'ambulance' } },
    anim      = { dict = 'amb@world_human_hammering@male@base', clip = 'base' },
    carryProp = false,                                        -- ท่าตอกไม่ต้องถือคลิปบอร์ด
    popProp   = { model = 'prop_rock_1_a', style = 'rise' },
    blip      = { sprite = 618, color = 5 },
}

-- ─── เก็บส้ม — ได้ทีละ 2 ถือได้ 100 · ไม่มี VIP ─────────────────────────────
Config.Jobs['orange'] = {
    label  = 'เก็บส้ม',
    order  = 3,
    coords = vec3(2350.0, 4760.0, 35.0),
    items  = {
        { name = 'lnn_orange', label = 'ส้ม', perTick = 2, limit = 100 },
    },
    vip     = false,
    popProp = { model = 'ng_proc_food_ornge1a', style = 'float' },
    blip    = { sprite = 285, color = 47 },
}

-- ─── ตกปลา — ใช้เหยื่อ 1 ชิ้นทุก tick (หมด = หยุด) ─────────────────────────────
Config.Jobs['fishing'] = {
    label  = 'ตกปลา',
    order  = 4,
    coords = vec3(-1850.0, -1250.0, 8.6),
    radius = 15.0,
    tickMs = 6000,
    items  = {
        { name = 'lnn_fish', label = 'ปลา', score = 2 },
    },
    requires = {
        { name = 'lnn_bait', label = 'เหยื่อ', count = 1, consume = 'tick' },
    },
    carryProp = {                                             -- ทับแค่โมเดล + ตำแหน่ง (bone ตาม defaults)
        model = 'prop_fishing_rod_01',
        pos   = vec3(0.1, 0.0, 0.0),
        rot   = vec3(0.0, 0.0, 0.0),
    },
    blip = { sprite = 68, color = 3 },
}
