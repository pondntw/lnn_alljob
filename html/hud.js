/* HUD ฟาร์ม + เมนูเลือกไอเทม — Lua ส่งเฉพาะตอนสถานะเปลี่ยน (ดู client/jobs.lua)
 *
 *   ui:theme   { primary, secondary, accent }                         สีจาก Config.UI → CSS variable
 *   hud:show   { job, items: [{ label, perTick, tickMs, score, limit, img }], bonus: [ชื่อ], need: [ชื่อ], text }
 *   hud:select { index }                                              เปิดเมนูเลือก (วงหลายไอเทม · ยึดโฟกัส)
 *   hud:start  { item, count, limit, rank, perTick, tickMs, vip }     เริ่มฟาร์ม (perTick/tickMs คิด VIP แล้ว · limit = จำนวนที่ถือได้จริง)
 *   hud:tick   { count, rank, bonus?: [ชื่อ] }                        ได้ของ 1 รอบ (วงแหวนเริ่มรอบใหม่)
 *   hud:stop   { text, ok }   hud:fail { text }   hud:hide
 * NUI → Lua: pick { idx } · cancelPick
 *
 * วงแหวนวิ่งเองด้วย CSS transition ตาม tickMs — Lua ไม่ต้องส่งความคืบหน้าทุกเฟรม
 */
(() => {
    const IN_GAME = typeof GetParentResourceName === 'function';
    const RES = IN_GAME ? GetParentResourceName() : 'lnn_alljob';
    const $ = (id) => document.getElementById(id);
    const hud = $('hud'), fill = $('hudFill'), chips = $('hudChips'), picker = $('picker');

    let job = null;          // payload ของ hud:show
    let item = null;         // ไอเทมที่โชว์อยู่ (ค่าจริงของ session ทับตอน start)
    let farming = false, rank = null, vip = false;
    let countdown = null, resultTimer = null, pickIdx = 0;

    const post = (name, data = {}) => {
        if (!IN_GAME) return;
        fetch(`https://${RES}/${name}`, { method: 'POST', body: JSON.stringify(data) }).catch(() => {});
    };
    const el = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;   // ข้อความจาก config เข้า DOM ด้วย textContent เท่านั้น
        return e;
    };
    const chip = (cls, bold, text) => {
        const c = el('span', 'chip ' + cls);
        c.append(el('b', null, bold), document.createTextNode(text));
        return c;
    };
    const secs = (ms) => (ms / 1000).toFixed(1);

    // ---------------- ส่วนแสดงผล ----------------

    function renderChips() {
        const t = job.text, list = [];
        if (vip) list.push(chip('vip', '★', ` ${t.vip}`));
        if (rank) list.push(chip('rank', `#${rank}`, t.in_job));
        list.push(chip('get', `+${item.perTick}`, t.per_tick.replace('%s', secs(item.tickMs))));
        if (item.score > 0) list.push(chip('pts', `+${item.score}`, t.pts));
        if (!farming) job.need.forEach((n) => list.push(chip('need', t.need, ` ${n}`)));
        job.bonus.forEach((b) => list.push(chip('bonus', '★', ` ${b}`)));
        chips.replaceChildren(...list);
    }

    function setCount(n) {
        const node = $('hudCount');
        const text = n === null ? '—' : Number(n).toLocaleString('en-US');
        if (n !== null && node.textContent !== text) { node.classList.remove('bump'); void node.offsetWidth; node.classList.add('bump'); }
        node.textContent = text;
        $('hudMax').textContent = item.limit ? `| ${item.limit}` : '';
    }

    function setIdle() {
        farming = false; vip = false;
        const multi = job.items.length > 1;
        $('hudKeyCap').textContent = 'E';
        $('hudKeyText').textContent = multi ? job.text.choose : job.text.start;
        hud.classList.remove('working');
        stopRing();
        renderChips();
    }

    /* วงแหวน 1 รอบ = tickMs (เริ่มจากว่างทุกครั้ง) */
    function runRing() {
        fill.style.transition = 'none';
        fill.style.strokeDashoffset = '100';
        void fill.getBoundingClientRect();
        fill.style.transition = `stroke-dashoffset ${item.tickMs}ms linear`;
        fill.style.strokeDashoffset = '0';

        clearInterval(countdown);
        const end = Date.now() + item.tickMs;
        const draw = () => { $('hudTime').textContent = `${secs(Math.max(0, end - Date.now()))}s`; };
        draw();
        countdown = setInterval(draw, 100);
    }

    function stopRing() {
        clearInterval(countdown);
        countdown = null;
        fill.style.transition = 'stroke-dashoffset .3s';
        fill.style.strokeDashoffset = '100';
    }

    function flash(text, ok) {
        const r = $('hudResult');
        r.textContent = text;
        r.className = 'hud-result on ' + (ok ? 'ok' : 'fail');
        hud.classList.remove('flash-ok', 'flash-fail');
        void hud.offsetWidth;
        hud.classList.add(ok ? 'flash-ok' : 'flash-fail');
        clearTimeout(resultTimer);
        resultTimer = setTimeout(() => { r.className = 'hud-result'; }, 2600);
    }

    function pop(text, gold) {
        const p = el('div', 'pop' + (gold ? ' gold' : ''), text);
        p.style.marginLeft = `${(Math.random() - 0.5) * 3}vh`;
        $('hudPops').append(p);
        setTimeout(() => p.remove(), 1500);
    }

    function setRank(r) {
        const up = rank && r && r < rank;
        rank = r || null;
        renderChips();
        if (up) chips.querySelector('.rank')?.classList.add('up');
    }

    // ---------------- เมนูเลือกไอเทม ----------------

    function renderPicker() {
        const t = job.text;
        $('pickJob').textContent = job.job;
        $('pickTitle').textContent = t.select;
        $('pickHint').textContent = t.select_hint;
        $('pickList').replaceChildren(...job.items.map((it, i) => {
            const card = el('div', 'pick' + (i === pickIdx ? ' active' : ''));
            const icon = el('div', 'pick-icon');
            if (it.img) {
                const img = el('img');
                img.src = it.img;                         // URL มาจาก Config.ItemImage ของเซิร์ฟเอง
                img.onerror = () => { img.remove(); icon.classList.remove('has-img'); };
                icon.classList.add('has-img');
                icon.append(img);
            }
            const info = el('div', 'pick-info');
            info.append(el('div', 'pick-name', it.label));
            const meta = el('div', 'pick-meta');
            meta.append(chip('get', `+${it.perTick}`, t.per_tick.replace('%s', secs(it.tickMs))));
            if (it.score > 0) meta.append(chip('pts', `+${it.score}`, t.pts));
            if (it.limit) meta.append(chip('max', t.limit.replace('%d', it.limit), ''));
            info.append(meta);
            card.append(icon, info);
            card.onclick = () => { pickIdx = i; choose(); };
            card.onmouseenter = () => { if (pickIdx !== i) { pickIdx = i; renderPicker(); } };
            return card;
        }));
    }

    function openPicker(index) {
        pickIdx = Math.min(Math.max((index || 1) - 1, 0), job.items.length - 1);
        renderPicker();
        picker.style.display = '';
        picker.classList.add('show');
    }

    function closePicker() {
        picker.classList.remove('show');
        picker.style.display = 'none';
    }

    function choose() {
        if (picker.style.display === 'none') return;
        closePicker();
        item = job.items[pickIdx];
        setCount(null);
        $('hudItem').textContent = item.label;
        renderChips();
        post('pick', { idx: pickIdx + 1 });
        if (!IN_GAME) preview.afterPick(pickIdx + 1);
    }

    function cancelPick() {
        if (picker.style.display === 'none') return;
        closePicker();
        post('cancelPick');
    }

    window.addEventListener('keydown', (e) => {
        if (picker.style.display === 'none' || !job) return;
        const n = job.items.length;
        if (e.key === 'ArrowUp' || e.key === 'w' || e.key === 'W') { pickIdx = (pickIdx - 1 + n) % n; renderPicker(); }
        else if (e.key === 'ArrowDown' || e.key === 's' || e.key === 'S') { pickIdx = (pickIdx + 1) % n; renderPicker(); }
        else if (e.key === 'Enter' || e.key === ' ') choose();
        else if (e.key === 'Escape' || e.key === 'Backspace') cancelPick();
    });

    // ---------------- ข้อความจาก Lua ----------------

    const handlers = {
        'ui:theme': (c) => {
            const root = document.documentElement.style;
            if (c.primary) root.setProperty('--c1', c.primary);
            if (c.secondary) root.setProperty('--c2', c.secondary);
            if (c.accent) root.setProperty('--c3', c.accent);
            document.querySelectorAll('#hudGrad .g1').forEach((s) => c.primary && s.setAttribute('stop-color', c.primary));
            document.querySelectorAll('#hudGrad .g2').forEach((s) => c.secondary && s.setAttribute('stop-color', c.secondary));
            document.querySelectorAll('#hudGrad .g3').forEach((s) => c.accent && s.setAttribute('stop-color', c.accent));
        },
        'hud:show': (d) => {
            job = d; item = d.items[0]; rank = null;
            $('hudJob').textContent = d.job;
            $('hudTag').textContent = d.text.tag;
            $('hudItem').textContent = d.items.length > 1 ? d.text.choose : item.label;
            setCount(null);
            setIdle();
            hud.style.display = '';
            hud.classList.add('show');
        },
        'hud:select': (d) => { if (job) openPicker(d.index); },
        'hud:start': (d) => {
            if (!job) return;
            // ค่าจริงของ session (VIP เปลี่ยน perTick / tickMs) ทับค่าใน config
            item = Object.assign({}, job.items[(d.item || 1) - 1], { perTick: d.perTick, tickMs: d.tickMs, limit: d.limit });
            farming = true; vip = d.vip === true;
            $('hudItem').textContent = item.label;
            $('hudKeyCap').textContent = 'X';
            $('hudKeyText').textContent = job.text.stop;
            hud.classList.add('working');
            setCount(d.count);
            setRank(d.rank);
            runRing();
        },
        'hud:tick': (d) => {
            if (!job || !farming) return;
            pop(`+${item.perTick} ${item.label}`);
            (d.bonus || []).forEach((b, i) => setTimeout(() => pop(`★ ${b}`, true), 250 * (i + 1)));
            setCount(d.count);
            setRank(d.rank);
            runRing();
        },
        'hud:stop': (d) => {
            if (!job) return;
            setIdle();
            flash(d.text, d.ok);
        },
        'hud:fail': (d) => { if (job) flash(d.text, false); },
        'hud:hide': () => {
            job = null; farming = false;
            closePicker();
            stopRing();
            hud.classList.remove('show', 'working');
            hud.style.display = 'none';
        },
    };

    window.addEventListener('message', (e) => {
        const msg = e.data;
        if (msg && handlers[msg.action]) handlers[msg.action](msg.data);
    });

    // ---------------- พรีวิวนอกเกม: วนรอ → เลือกไอเทม → ฟาร์ม → หยุด ----------------
    const text = {
        tag: 'AUTO FARM', start: 'เริ่มฟาร์ม', choose: 'เลือกไอเทม', stop: 'หยุดฟาร์ม', in_job: ' ในงานนี้',
        per_tick: ' / %s วิ', pts: ' PTS', need: 'ต้องมี', vip: 'VIP', select: 'เลือกสิ่งที่จะฟาร์ม',
        select_hint: '↑ ↓ เลือก · Enter เริ่ม · ESC ยกเลิก', limit: 'ถือได้ %d',
    };
    const demo = {
        job: 'ขุดแร่', text, bonus: ['อัญมณี'], need: ['อีเต้อ'],
        items: [
            { label: 'ก้อนแร่', perTick: 2, tickMs: 2500, score: 1 },
            { label: 'แร่ทอง', perTick: 1, tickMs: 4000, score: 3, limit: 50 },
        ],
    };
    const preview = {
        timer: null, count: 12, r: 9, ticks: 0,
        afterPick(idx) {
            const it = demo.items[idx - 1];
            const vipOn = idx === 1;
            const tickMs = vipOn ? Math.floor(it.tickMs / 1.5) : it.tickMs;
            handlers['hud:start']({ item: idx, count: this.count, limit: it.limit || 30, rank: this.r, perTick: it.perTick * (vipOn ? 2 : 1), tickMs, vip: vipOn });
            this.ticks = 0;
            this.timer = setInterval(() => {
                this.count += 1; this.ticks += 1;
                if (this.ticks % 2 === 0 && this.r > 1) this.r -= 1;
                handlers['hud:tick']({ count: this.count, rank: this.r, bonus: this.ticks % 3 === 0 ? ['อัญมณี'] : null });
                if (this.ticks % 5 === 0) {
                    clearInterval(this.timer);
                    handlers['hud:stop']({ text: `หยุดฟาร์มแล้ว · ได้ ${it.label} 5 ชิ้น`, ok: true });
                    setTimeout(() => this.cycle(), 2500);
                }
            }, tickMs);
        },
        cycle() {
            handlers['hud:show'](demo);
            setTimeout(() => handlers['hud:select']({ index: 1 }), 1200);
            setTimeout(() => choose(), 3200);           // เลือกเองอัตโนมัติ (หรือกดในเบราว์เซอร์ก็ได้)
        },
    };
    if (!IN_GAME && new URLSearchParams(location.search).get('view') !== 'rank') preview.cycle();
})();
