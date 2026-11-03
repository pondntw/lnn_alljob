/* lnn_alljob — Ranking HUD
 *
 * Lua → NUI (action):
 *   open    { boards: [{ idx, label }], idx }   เปิดแผง
 *   loading idx                                  กำลังขอกระดาน
 *   board   { idx, rows, count, rank, score }    ข้อมูลกระดาน (rows = [[ชื่อ, แต้ม], ...] เรียงอันดับ 1 → N)
 *   me      { idx, rank, score }                 อันดับของเราเปลี่ยน
 *   close                                        ปิดแผง
 * NUI → Lua: select { idx } · close
 *
 * เปิดไฟล์นี้ในเบราว์เซอร์ธรรมดา (ไม่มี GetParentResourceName) = โหมดพรีวิวพร้อมข้อมูลจำลอง
 */
(() => {
    const IN_GAME = typeof GetParentResourceName === 'function';
    const RES = IN_GAME ? GetParentResourceName() : 'lnn_alljob';
    const SWITCH_MS = 300;                       // ต้องมากกว่า Config.Ranking.OpenCooldownMs ของ server

    const $ = (id) => document.getElementById(id);
    const app = $('app'), tabs = $('tabs'), podium = $('podium'), list = $('list');

    const state = { boards: [], idx: 0, rows: [], count: 0, rank: 0, score: 0, open: false };
    let prevRanks = new Map();                   // ชื่อ → อันดับรอบก่อน (ไว้โชว์ ▲) · ล้างเมื่อเปลี่ยนกระดาน
    let lastSwitch = 0, clockTimer = null, shownScore = 0;

    const post = (name, data = {}) => {
        if (!IN_GAME) return Promise.resolve();
        return fetch(`https://${RES}/${name}`, { method: 'POST', body: JSON.stringify(data) }).catch(() => {});
    };
    const fmt = (n) => Number(n || 0).toLocaleString('en-US');
    const el = (tag, cls, text) => {
        const e = document.createElement(tag);
        if (cls) e.className = cls;
        if (text !== undefined) e.textContent = text;      // ชื่อผู้เล่นเข้า DOM ด้วย textContent เท่านั้น
        return e;
    };

    // ---------------- ส่วนแสดงผล ----------------

    function renderTabs() {
        tabs.replaceChildren(...state.boards.map((b, i) => {
            const t = el('div', 'tab' + (b.idx === state.idx ? ' active' : ''));
            t.append(el('span', 'no', String(i).padStart(2, '0')), el('span', 'name', b.label));
            t.onclick = () => select(b.idx);
            return t;
        }));
        const cur = state.boards.find((b) => b.idx === state.idx);
        $('boardTitle').textContent = cur ? cur.label : '—';
    }

    function renderBoard() {
        const rows = state.rows, top = rows.length ? rows[0][1] : 0;
        const ranks = new Map();

        // โพเดียม: ลำดับวาง 2 · 1 · 3
        podium.replaceChildren(...[2, 1, 3].map((r) => {
            const row = rows[r - 1];
            const p = el('div', `pod r${r}` + (row ? '' : ' vacant') + (state.rank === r ? ' mine' : ''));
            p.append(el('div', 'medal', String(r).padStart(2, '0')),
                     el('div', 'who', row ? row[0] : '— ว่าง —'),
                     el('div', 'pts', row ? `${fmt(row[1])} PTS` : '0 PTS'));
            if (row) ranks.set(row[0], r);
            return p;
        }));

        list.replaceChildren(...rows.slice(3).map((row, i) => {
            const r = i + 4;
            const li = el('li', 'row' + (state.rank === r ? ' mine' : ''));
            const before = prevRanks.get(row[0]);
            if (before && before > r) li.classList.add('up');
            li.style.animationDelay = `${i * 30}ms`;

            const bar = el('div', 'bar'), fill = el('i');
            fill.style.width = top > 0 ? `${Math.max(4, (row[1] / top) * 100)}%` : '0%';
            bar.append(fill);
            li.append(el('span', 'rk', `#${r}`), el('span', 'nm', row[0]), bar, el('span', 'sc', fmt(row[1])));
            ranks.set(row[0], r);
            return li;
        }));

        prevRanks = ranks;
        $('count').textContent = fmt(state.count);
        $('empty').style.display = rows.length ? 'none' : 'flex';
        renderMe();
    }

    function renderMe() {
        const rank = $('meRank');
        const text = state.rank > 0 ? `#${fmt(state.rank)}` : '—';
        if (rank.textContent !== text) { rank.textContent = text; bump(rank); }

        countTo(state.score);

        // แถบ = สัดส่วนคนที่อยู่ "ใต้หรือเท่า" เรา (อันดับ 1 = เต็มแถบ)
        const ranked = state.rank > 0 && state.count > 0;
        const above = ranked ? (state.count - state.rank + 1) / state.count : 0;
        $('meBar').style.width = ranked ? `${Math.max(2, above * 100)}%` : '0%';
        $('mePct').textContent = ranked ? `TOP ${Math.max(1, Math.ceil((state.rank / state.count) * 100))}%` : '—';
    }

    function countTo(target) {
        const node = $('meScore'), from = shownScore, start = performance.now();
        shownScore = target;
        if (from === target) { node.textContent = fmt(target); return; }
        bump(node);
        const tick = (t) => {
            // timestamp ของ rAF = เวลาเริ่มเฟรม อาจมาก่อน start → ต้องกันไม่ให้ติดลบ (เคยขึ้นแต้มติดลบ)
            const k = Math.min(1, Math.max(0, (t - start) / 600));
            node.textContent = fmt(Math.round(from + (target - from) * (1 - Math.pow(1 - k, 3))));
            if (k < 1 && shownScore === target) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
    }

    function bump(node) {
        node.classList.remove('bump');
        void node.offsetWidth;                    // รีสตาร์ท animation
        node.classList.add('bump');
    }

    function flashSync() {
        const s = $('sync');
        s.classList.add('flash');
        setTimeout(() => s.classList.remove('flash'), 350);
    }

    function setLoading(on) {
        $('loading').style.display = on ? 'flex' : 'none';
        if (on) { podium.replaceChildren(); list.replaceChildren(); $('empty').style.display = 'none'; }
    }

    function startClock() {
        const draw = () => { $('clock').textContent = new Date().toLocaleTimeString('en-GB'); };
        draw();
        clockTimer = setInterval(draw, 1000);
    }

    // ---------------- การกระทำ ----------------

    function select(idx) {
        const now = Date.now();
        if (idx === state.idx || now - lastSwitch < SWITCH_MS) return;
        lastSwitch = now;
        state.idx = idx;
        prevRanks = new Map();
        renderTabs();
        post('select', { idx });
        if (!IN_GAME) preview.load(idx);
    }

    function step(dir) {
        const i = state.boards.findIndex((b) => b.idx === state.idx);
        const next = state.boards[(i + dir + state.boards.length) % state.boards.length];
        if (next) select(next.idx);
    }

    function show(data) {
        state.boards = data.boards || [];
        state.idx = data.idx || 0;
        state.open = true;
        prevRanks = new Map();
        renderTabs();
        app.style.display = '';
        app.classList.add('show');
        if (!clockTimer) startClock();
    }

    function hide() {
        state.open = false;
        app.classList.remove('show');
        app.style.display = 'none';
        clearInterval(clockTimer);
        clockTimer = null;
    }

    function requestClose() {
        if (!state.open) return;
        hide();
        post('close');
    }

    const handlers = {
        open: show,
        close: hide,
        loading: (idx) => { if (idx === state.idx) setLoading(true); },
        board: (d) => {
            if (d.idx !== state.idx) return;      // ตอบช้าของกระดานที่เลื่อนผ่านไปแล้ว
            setLoading(false);
            Object.assign(state, { rows: d.rows || [], count: d.count, rank: d.rank, score: d.score });
            renderBoard();
            flashSync();
        },
        me: (d) => {
            if (d.idx !== state.idx) return;
            state.rank = d.rank; state.score = d.score;
            renderBoard();                        // วาดใหม่ทั้งกระดาน — ไฮไลต์แถว "YOU" ย้ายตามอันดับ
        },
    };

    window.addEventListener('message', (e) => {
        const msg = e.data;
        if (msg && handlers[msg.action]) handlers[msg.action](msg.data);
    });

    window.addEventListener('keydown', (e) => {
        if (!state.open) return;
        if (e.key === 'Escape' || e.key === 'Backspace') requestClose();
        else if (e.key === 'ArrowUp' || e.key === 'w' || e.key === 'W') step(-1);
        else if (e.key === 'ArrowDown' || e.key === 's' || e.key === 'S') step(1);
    });
    $('close').onclick = requestClose;

    // ---------------- พรีวิวนอกเกม ----------------
    const preview = {
        names: ['Neo Arashi', 'Kaito Vex', 'Mira Holt', 'Zed Okafor', 'Lumen Ray', 'Iris Novak', 'Rex Kade', 'Sora Lin', 'Juno Pike', 'Dax Moreno', 'Echo Vale', 'Nyx Corran'],
        data: {},
        load(idx) {
            handlers.loading(idx);
            setTimeout(() => {
                if (!this.data[idx]) this.data[idx] = this.names.map((n) => [n, Math.floor(Math.random() * 900) + 20]);
                this.push(idx);
            }, 250);
        },
        push(idx) {
            const rows = this.data[idx].slice().sort((a, b) => b[1] - a[1]).slice(0, 10);
            const me = this.data[idx].slice().sort((a, b) => b[1] - a[1]).findIndex((r) => r[0] === 'Neo Arashi') + 1;
            handlers.board({ idx, rows, count: 1284, rank: me, score: this.data[idx].find((r) => r[0] === 'Neo Arashi')[1] });
        },
    };
    // ?view=hud = พรีวิว HUD ฟาร์มอย่างเดียว · ?view=rank = กระดานอย่างเดียว · ไม่ใส่ = ทั้งคู่
    if (!IN_GAME) document.body.style.background = 'radial-gradient(circle at 30% 20%, #3a5872, #0b1520 70%)';
    if (!IN_GAME && new URLSearchParams(location.search).get('view') !== 'hud') {
        show({ boards: [{ idx: 0, label: 'รวมทุกงาน' }, { idx: 1, label: 'ตัดไม้' }, { idx: 2, label: 'ขุดแร่' }, { idx: 3, label: 'เก็บส้ม' }], idx: 0 });
        preview.load(0);
        setInterval(() => {                       // จำลองมีคนทำงานแล้วอันดับขยับ
            const rows = preview.data[state.idx];
            if (!rows) return;
            rows[Math.floor(Math.random() * rows.length)][1] += Math.floor(Math.random() * 60);
            preview.push(state.idx);
        }, 1500);
    }
})();
