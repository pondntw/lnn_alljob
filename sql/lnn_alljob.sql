-- lnn_alljob — ตารางแต้ม (resource สร้างเองตอน start อยู่แล้ว ไฟล์นี้ไว้รันมือ/ดูสคีมา)
-- ⚠️ ต้องตรงกับ Store.ensureTable() ใน server/store.lua
CREATE TABLE IF NOT EXISTS `lnn_alljob_scores` (
    `identifier` VARCHAR(64) NOT NULL,
    `job`        VARCHAR(32) NOT NULL,          -- ชื่องานใน config/jobs.lua · '__total' = กระดานรวม
    `score`      INT UNSIGNED NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `job`),
    KEY `idx_job_score` (`job`, `score`, `identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ไอเทมของงานตัวอย่างใน config/jobs.lua
-- ระบบใช้ "limit ต่อไอเทม" (ไม่ใช่น้ำหนัก): ตั้งที่ limit ใน config ได้ หรืออ่านจากคอลัมน์ limit ของตาราง items
-- ESX ที่ตาราง items ไม่มีคอลัมน์ limit (รุ่นน้ำหนัก) → ลบ `limit` ออกจากคำสั่งด้านล่าง แล้วตั้ง limit ใน config แทน
INSERT IGNORE INTO `items` (`name`, `label`, `weight`, `limit`) VALUES
    ('lnn_wood',    'ไม้ท่อน',  1, 200),
    ('lnn_resin',   'ยางไม้',   1, 50),
    ('lnn_axe',     'ขวาน',     1, 1),
    ('lnn_stone',   'ก้อนแร่',  1, 200),
    ('lnn_gold',    'แร่ทอง',   1, 50),
    ('lnn_gem',     'อัญมณี',   1, 20),
    ('lnn_pickaxe', 'อีเต้อ',   1, 1),
    ('lnn_orange',  'ส้ม',      1, 200),
    ('lnn_fish',    'ปลา',      1, 100),
    ('lnn_bait',    'เหยื่อ',   1, 100),
    ('vip_card',    'บัตร VIP', 1, 1);
