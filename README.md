# lnn_alljob — All Job + Ranking All Job

โซนฟาร์มอัตโนมัติหลายงานตั้งด้วย config (เดินเข้าวง → กด E → ได้ของเองทุกรอบ)
+ กระดานอันดับทุกงานและรวมทุกงาน ผู้เล่นทุกคนเปิดดูได้ตลอด อันดับขยับสดระหว่างเปิดดู

**ต้องมี:** ESX Legacy (1.10+) · oxmysql · ox_lib — ไม่พึ่ง resource อื่น

## ติดตั้ง
1. วางโฟลเดอร์ `lnn_alljob` ใน `resources/` แล้วเติม `ensure lnn_alljob` ใน `server.cfg` (หลัง es_extended / oxmysql / ox_lib)
2. รัน `sql/lnn_alljob.sql` เพื่อเพิ่มไอเทมตัวอย่าง (ตารางแต้มสร้างเองตอน start)
3. แก้พิกัดใน `config/jobs.lua` — ชุดที่มากับไฟล์เป็นค่าตัวอย่าง
4. ในเกม: เดินเข้าวงบนแมพ (blip "ฟาร์ม · …") → **E** เริ่ม (หลายไอเทม = เลือกก่อน) · **X** หยุด · `/lnn_rank` เปิดกระดาน

## ตั้งค่า (`config/`)
| ไฟล์ | ตั้งอะไร |
|---|---|
| `general.lua` | ปุ่ม · ระยะวาดวง · tick เร็วสุดที่ยอม · สีธีมของ UI · URL รูปไอเทม |
| `defaults.lua` | ค่าตั้งต้นของ **ทุกงาน** — รัศมี · tickMs · perTick · แต้ม · บัตร VIP · ท่า · prop ในมือ · particle · วง · blip |
| `jobs.lua` | งานแต่ละงาน — ใส่เฉพาะค่าที่ต่างจาก `defaults.lua` |
| `ranking.lua` | กระดานอันดับ — คำสั่ง · ปุ่มลัด · กี่อันดับ · รอบเซฟ |
| `locale.lua` | ข้อความทุกตัวที่ผู้เล่นเห็น |
| `functions_server.lua` / `functions_client.lua` | hook ต่อระบบอื่นโดยไม่ต้องแก้ core (`CanStart` · `OnTick` · `OnStart` · `OnStop`) |

**กติกา override** (ต่องานใน `jobs.lua`): ไม่ใส่ = ใช้ค่าใน `defaults.lua` · `false` = ปิดเฉพาะงานนั้น ·
table ของ `vip` `blip` `marker` `carryProp` `effect` `popProp` = ทับเฉพาะ key ที่ใส่ · ค่าอื่นทับทั้งก้อน
ค่าต่อไอเทม (`perTick` `tickMs` `score` `limit` `popProp`) ทับค่าของงานได้อีกชั้น

```lua
Config.Jobs['mining'] = {
    label = 'ขุดแร่', order = 2,
    coords = vec3(2955.0, 2790.0, 41.0), radius = 25.0,
    items = {                                                    -- หลายตัว = เมนูเลือก
        { name = 'lnn_stone', label = 'ก้อนแร่', perTick = 2 },
        { name = 'lnn_gold',  label = 'แร่ทอง', tickMs = 8000, score = 3, limit = 50 },
    },
    requires = { { name = 'lnn_pickaxe', label = 'อีเต้อ', consume = false } },   -- false · 'start' · 'tick'
    bonus    = { { name = 'lnn_gem', label = 'อัญมณี', chance = 2 } },
    vip      = { itemMult = 3 },                                 -- ทับแค่ตัวคูณ · false = ปิด VIP งานนี้
    jobs     = { type = 'blacklist', list = { 'police', 'ambulance' } },
    carryProp = false,
    popProp  = { model = 'prop_rock_1_a', style = 'rise' },
}
```

**ฟาร์มหยุดเองเมื่อ:** กด X · ออกนอกวง · ตาย · ถือครบ **limit** · อุปกรณ์ที่หักทุก tick หมด
**limit = จำนวนไอเทมที่ถือได้ในกระเป๋า** (ไม่ใช่น้ำหนัก · ไม่เรียก `canCarryItem`):
เพดานจริงคือ `limit` ของไอเทมในกระเป๋าที่ `getInventoryItem` คืนมา (ไม่มี = `ESX.Items[name].limit` · `-1` = ไม่จำกัด) ·
`limit` ใน config ใช้ "ลด" เพดานของการฟาร์มได้อย่างเดียว ตั้งเกิน limit จริงก็ได้แค่เท่า limit จริง
(ต้องคุมเองเพราะ `addInventoryItem` ของ ESX ไม่เช็ค limit · โบนัสก็เคารพ limit ของตัวเอง — ถึงแล้วแค่ไม่ได้ตัวนั้น ฟาร์มต่อ)
config ผิด = งานนั้นถูกข้าม + เตือนใน console (บอกว่าช่องไหนผิด) ไม่ทำให้ resource ล่ม · โมเดล prop ที่โหลดไม่ได้ = ข้ามเฉยๆ
⚠️ ชื่องาน (`Config.Jobs['ชื่อ']`) คือคีย์ในฐานข้อมูล — เปลี่ยนหลังเปิดใช้ = แต้มเดิมของงานนั้นหาย

## ให้สคริปต์อื่นนับแต้มเข้า (server)
```lua
exports.lnn_alljob:AddScore(src, 'lumber', 1)              -- คืน true = นับแล้ว
TriggerEvent('lnn_alljob:addScore', src, 'lumber', 1)      -- แบบไม่ error ถ้า lnn_alljob ไม่ได้ start
exports.lnn_alljob:GetTop('lumber', 10)                    -- nil / 'total' = กระดานรวม
exports.lnn_alljob:GetRank(identifier, 'lumber')           -- อันดับ, แต้ม
```
ตัวรับเป็น `AddEventHandler` (server-local) ห้ามเปลี่ยนเป็น `RegisterNetEvent` — client จะปั๊มแต้มตัวเองได้

## โครงไฟล์โค้ด
| ไฟล์ | หน้าที่ |
|---|---|
| `shared/jobs.lua` | รวม default + ตรวจ + เรียงงาน (รันทั้งสองฝั่ง ลำดับจึงตรงกัน client ส่งแค่เลขลำดับ) |
| `server/jobs.lua` | session ฟาร์ม + tick (server ตัดสินทุกอย่าง) |
| `server/board.lua` | กระดานเรียงลำดับ 1 กระดาน — pure Lua ไม่มี native |
| `server/ranking.lua` | กระดานทุกงาน · ชื่อ · ส่งสดให้คนที่เปิดดู · exports |
| `server/store.lua` | DB: สร้างตาราง · โหลด · เซฟ |
| `server/players.lua` | แคช src → identifier |
| `server/main.lua` | บูต · เข้า/ออก · เซฟเป็นรอบ · ปิดเซิร์ฟ |
| `client/jobs.lua` | วง (ox_lib points) · เมนูเลือก · ท่า · เอฟเฟกต์ · ส่งสถานะให้ HUD |
| `client/props.lua` | prop ในมือ · กลางวง · เด้งตอนได้ของ (local ทั้งหมด) |
| `client/ranking.lua` | เปิด/ปิดแผง Ranking · รับอันดับสด |
| `html/` | NUI: `index.html` + `style.css` / `app.js` (Ranking) · `hud.css` / `hud.js` (HUD ฟาร์ม + เมนูเลือก) |

## การออกแบบด้าน performance

**ฟาร์ม: timer แยกต่อ session** (`server/jobs.lua`) — `SetTimeout(tickMs)` ของแต่ละคน แทน thread กลางที่ตื่นมาสแกนทุกคน
ไม่มีคนฟาร์ม = ไม่มี timer · ตัว table ของ session คือ "รุ่น": หยุด/เริ่มใหม่ = table ใหม่ → timer เก่าจบเองโดยไม่ต้องยกเลิก
- เก็บ proxy `ESX.Player(src)` ไว้ใน session → 1 tick = 2 export (`getInventoryItem` + `addInventoryItem`) ไม่ต้องถาม ESX หาผู้เล่นซ้ำ
  · limit / VIP คิดครั้งเดียวตอนเริ่ม · โบนัสอ่านกระเป๋าเฉพาะรอบที่สุ่มออก
- ตรวจระยะ/ตาย/หลุดด้วย native ฝั่ง server ใน tick เดียวกัน ไม่มีลูปเฝ้าแยก · tick / hook พัง = หยุดแค่ session นั้น (pcall)
- ส่ง client 1 event ต่อ tick: จำนวน + อันดับ + เลขลำดับโบนัส (ชื่อ/ค่าคงที่ client มีใน config อยู่แล้ว)

**prop ในมือให้คนรอบตัวเห็นโดยไม่มี network entity** — server ตั้ง Player state `lnnFarm` ตอนเริ่ม/หยุด (2 ครั้งต่อ session)
OneSync ส่งเฉพาะเครื่องที่อยู่ในระยะ · ทุกเครื่องสร้าง prop local ติดมือเอง · client เขียน state เอง = server ทับกลับ
prop กลางวง / prop เด้ง เป็น local ล้วน

**กระดานอยู่ใน RAM ทั้งหมด แล้ว RAM คือของจริง** — โหลดจาก DB ครั้งเดียวตอนบูต (keyset paging ทีละ 500 แถว SQL เรียงมาให้แล้ว ไม่ต้อง sort)
แต้มเปลี่ยนผ่าน resource นี้ทางเดียว จึงไม่มีรอบ rebuild · เข้าเกมไม่ต้อง SELECT · ออกเกมไม่ต้องโหลด/ทิ้ง cache

**บวกแต้ม = O(log n)** (`server/board.lua`) — entry เรียงด้วย key (แต้ม, ลำดับที่ถึงแต้มนี้) ซึ่งไม่ซ้ำกันเลย
→ หาตำแหน่งด้วย binary search แล้วขยับเฉพาะช่วงที่ถูกแซงด้วย `table.move` (วนใน C)
ไม่เก็บ map "id → อันดับ" เพราะแต้มขยับครั้งเดียว อันดับของทุกคนที่ถูกแซงเปลี่ยนตาม (คนแต้มเท่ากันเป็นหมื่น = ไล่แก้เป็นหมื่นรอบใน Lua)
วัดบน Lua 5.4 ธรรมดา ที่ 50,000 คน: บวกแต้ม ≈ 2.2 µs · หาอันดับ ≈ 1.2 µs · กรณีแย่สุด (คนท้ายแซงคนแต้มเท่ากัน 50,000 คน) ≈ 165 µs

**hot path ไม่แตะ DB** — tick = อัปเดตกระดาน + ปักธง dirty
- เซฟทุก `SaveIntervalMs` เฉพาะ (คน, งาน) ที่เปลี่ยน ก้อนละ 100 แถว (`MySQL.prepare` แบบหลายแถว) พักเฟรมระหว่างก้อน · พลาด = คืนธงให้รอบหน้า
- เขียน "แต้มเต็ม" ด้วย `GREATEST(score, VALUES(score))` → เขียนซ้ำไม่เพี้ยน และก้อนเก่าที่ถึง DB ช้ากว่าทับค่าใหม่ไม่ได้
- ออกเกม = เซฟเฉพาะคนนั้น · หยุด resource / txAdmin ปิดหรือรีสตาร์ท = ส่งทุกแถวโดยไม่ await (coroutine ใน `onResourceStop` จะไม่ถูก resume)
- รอบเซฟที่ค้าง (oxmysql ขอ connection ไม่ได้ = await ไม่กลับ) ไม่ล็อกการเซฟถาวร — เกิน 4 นาทีรอบใหม่เริ่มได้

**realtime แต่ไม่ broadcast** — ไม่มี `TriggerClientEvent(-1)` เลย
- ส่งเฉพาะคนที่เปิดกระดานนั้นอยู่ · ticker ตัวเดียวทุก 1 วิ รวมการเปลี่ยนทั้งรอบเป็น push เดียวต่อกระดาน
- Top-N ที่ส่งให้ทุกคนเหมือนกัน → `msgpack.pack_args` ครั้งเดียว แล้ว `TriggerClientEventInternal` ทีละคน
- อันดับของผู้ชมแต่ละคน: ส่งเฉพาะเมื่อเปลี่ยน (รวมถึงถูกคนอื่นแซง) · กระดานที่ไม่มีใครได้แต้มรอบนั้น = ข้ามการค้นทั้งหมด
- แถวเป็น array `{ ชื่อ, แต้ม }` · client แคชตามเลข `rev` เปิดซ้ำแล้วไม่มีอะไรเปลี่ยน = ไม่ส่งแถวซ้ำ
- ชื่อดึงจาก DB เฉพาะ Top-N ตอนบูต · คนออนไลน์ได้ชื่อจาก `xPlayer.getName()` ตอนเข้าเกม

**ESX** — `@es_extended/imports.lua` ใส่เฉพาะฝั่ง server · ใช้ `ESX.Player(src)` (proxy เรียก method ทีละตัว ไม่ก๊อป xPlayer ทั้งก้อนข้าม resource)
ESX รุ่นที่ยังไม่มีจะตกไปใช้ `ESX.GetPlayerFromId` · client ไม่โหลด ESX เลย

**client** — วงเป็น `lib.points` (ox_lib สแกนแบบ grid ทุก 300 ms) ไกลทุกวง = ไม่มีลูปทุกเฟรม
ระหว่างฟาร์มมีลูปอ่านปุ่ม X ซึ่งจบเองถ้า tick จาก server ไม่มา 3 รอบ · prop ในมือ reconcile ทุก 1 วิเฉพาะตอนมีคนฟาร์มอยู่ในระยะ ·
NUI ส่งเฉพาะตอนสถานะเปลี่ยน · วงแหวนบน HUD วิ่งเองด้วย CSS transition ตาม `tickMs`

## กันโกง
client ส่งแค่เลขลำดับงาน + ไอเทม — ไอเทม จำนวน แต้ม limit มาจาก config ฝั่ง server ทั้งหมด
- `start`: ระยะจากตำแหน่งที่ server เห็น · อาชีพ · ของที่ต้องมี · limit · hook · ฟาร์มซ้อนไม่ได้
- ทุก tick ตรวจซ้ำ: ยังอยู่ในวง · ยังไม่ตาย · อุปกรณ์ยังพอ · ยังไม่ถึง limit — ไม่ผ่าน = หยุดก่อนให้ของรอบนั้น
- อัตราได้ของถูกคุมด้วย timer ของ server เอง client เร่งไม่ได้ · VIP เช็คบัตรที่ server
- ค่าแปลกจาก client (NaN · ทศนิยม · string · เลขงาน/ไอเทม/กระดานที่ไม่มี) ถูกปฏิเสธที่ `math.tointeger`

## UI
แนวไซไฟ พื้นใส กรอบเรืองแสง · สีตั้งที่ `Config.UI`
- **HUD ฟาร์ม** (กลางล่าง ไม่ยึดเมาส์): วงแหวนนับรอบ · จำนวนที่มี | limit · อันดับสดในงานนั้น · ป้าย VIP · ของที่ต้องมี · ของที่ได้ลอยขึ้น · ปุ่ม E/X
- **เมนูเลือกไอเทม** (วงที่มีหลายไอเทม): การ์ดต่อไอเทม (รูปจาก `Config.ItemImage`) · `↑` `↓` `Enter` `ESC` หรือคลิก
- **Ranking** (`/lnn_rank`): โพเดียม 3 อันดับแรก · รายการถึง Top-N · แถบ "YOU" + เปอร์เซ็นไทล์ · `↑` `↓` เปลี่ยนกระดาน · `ESC` ปิด
- เปิด `html/index.html` ในเบราว์เซอร์ = พรีวิวพร้อมข้อมูลจำลอง (`?view=hud` / `?view=rank` = ดูทีละอย่าง)
- ค่าเริ่มต้นของหน้าเป็น "ซ่อน" ทั้งใน CSS และ inline (ui_page ถูกวาดทับจอตลอดเวลาที่ resource รัน)
