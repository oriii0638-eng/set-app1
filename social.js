'use strict';
// חברים ותחרויות: דירוג כללי (אופציונלי), דירוג חברים, בקשות חברות, חסימה ודיווח.
module.exports = function (db, save, send, readBody, userFor, normName) {
  db.social = db.social || {}; db.edges = db.edges || {}; db.blocks = db.blocks || {}; db.reports = db.reports || [];
  const byId = id => Object.values(db.users).find(u => u.id === id);
  const key = (a, b) => [a, b].sort().join(':');
  const int = (v, mx) => Math.max(0, Math.min(mx || 9999, Math.round(Number(v) || 0)));
  function il() {
    const p = {}; new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Jerusalem', year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'short' }).formatToParts(new Date()).forEach(x => { p[x.type] = x.value; });
    const dow = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(p.weekday);
    const dn = Math.round((Date.UTC(+p.year, +p.month - 1, +p.day) - Date.UTC(2020, 0, 1)) / 86400000);
    return { ws: dn - dow, mo: p.year + '-' + p.month };
  }
  function valueOf(kind, s) {
    if (!s || !s.stats) return 0;
    const st = s.stats, c = il();
    if (kind === 'streak') return Date.now() - st.t > 72 * 3600e3 ? 0 : st.streak;
    if (kind === 'week') return st.ws === c.ws ? st.wk : 0;
    return st.mo === c.mo ? st.moN : 0;
  }
  const nick = u => (db.social[u.id] && db.social[u.id].nick) || u.name;
  function rank(rows, meId) {
    rows.sort((a, b) => b.value - a.value || a.name.localeCompare(b.name));
    let r = 0, prev = null;
    rows.forEach((x, i) => { if (x.value !== prev) { r = i + 1; prev = x.value; } x.rank = r; });
    return rows;
  }
  const friendsOf = id => Object.values(db.edges).filter(e => e.st === 'ok' && (e.a === id || e.b === id)).map(e => e.a === id ? e.b : e.a);

  return async function handle(req, res, url) {
    const p = url.pathname;
    if (!(p.startsWith('/api/social') || p.startsWith('/api/friends') || p === '/api/report')) return false;
    const me = userFor(req); if (!me) { send(res, 401, { error: 'login' }); return true; }
    try {
      if (req.method === 'GET' && p === '/api/social/board') {
        const kind = ['streak', 'week', 'month'].includes(url.searchParams.get('kind')) ? url.searchParams.get('kind') : 'streak';
        const scope = url.searchParams.get('scope') === 'friends' ? 'friends' : 'all';
        let rows;
        if (scope === 'all') rows = Object.keys(db.social).filter(id => db.social[id].join && byId(id)).map(id => ({ id, name: nick(byId(id)), value: valueOf(kind, db.social[id]) }));
        else rows = [me.id].concat(friendsOf(me.id)).filter(id => byId(id)).map(id => ({ id, name: id === me.id ? nick(me) : byId(id).name, value: valueOf(kind, db.social[id]) }));
        rank(rows);
        const mine = rows.find(x => x.id === me.id);
        send(res, 200, { rows: rows.slice(0, 100).map(x => ({ rank: x.rank, name: x.name, value: x.value, me: x.id === me.id })), me: mine ? { rank: mine.rank, value: mine.value } : null, total: rows.length }); return true;
      }
      if (req.method === 'GET' && p === '/api/friends') {
        const out = { friends: [], incoming: [], outgoing: [], me: { name: me.name, join: !!(db.social[me.id] && db.social[me.id].join), nick: nick(me), stats: (db.social[me.id] || {}).stats || null } };
        Object.keys(db.edges).forEach(k => {
          const e = db.edges[k]; if (e.a !== me.id && e.b !== me.id) return;
          const oid = e.a === me.id ? e.b : e.a, o = byId(oid); if (!o) return;
          const st = (db.social[oid] || {}).stats;
          if (e.st === 'ok') out.friends.push({ id: k, name: o.name, streak: valueOf('streak', db.social[oid]), week: valueOf('week', db.social[oid]), month: valueOf('month', db.social[oid]), has: !!st });
          else if (e.a === me.id) out.outgoing.push({ id: k, name: o.name }); else out.incoming.push({ id: k, name: o.name });
        });
        send(res, 200, out); return true;
      }
      if (req.method !== 'POST') { send(res, 405, { error: 'x' }); return true; }
      const b = await readBody(req);
      if (p === '/api/social/me') {
        const s = db.social[me.id] = db.social[me.id] || {};
        if (b.join && !s.join && b.consent !== true) { send(res, 400, { error: 'נדרש אישור השתתפות והצגת שם' }); return true; }
        if (b.join && !s.join) s.consentAt = Date.now();
        s.join = !!b.join;
        let n = String(b.nick == null ? (s.nick || '') : b.nick).replace(/[<>\u0000-\u001f]/g, '').replace(/\s+/g, ' ').trim().slice(0, 20);
        s.nick = n.length >= 2 ? n : '';
        save(); send(res, 200, { ok: true, nick: nick(me) }); return true;
      }
      if (p === '/api/social/stats') {
        const s = db.social[me.id] = db.social[me.id] || {};
        s.stats = { streak: int(b.streak), best: int(b.best), wk: int(b.wk, 50), ws: int(b.ws, 99999), mo: String(b.mo || '').slice(0, 7), moN: int(b.moN, 400), t: Date.now() };
        save(); send(res, 200, { ok: true }); return true;
      }
      if (p === '/api/friends/request') {
        const o = db.users[normName(b.username)];
        if (!o || o.id === me.id) { send(res, 404, { error: 'לא נמצא משתמש בשם הזה' }); return true; }
        if ((db.blocks[o.id] || []).includes(me.id) || (db.blocks[me.id] || []).includes(o.id)) { send(res, 404, { error: 'לא נמצא משתמש בשם הזה' }); return true; }
        const k = key(me.id, o.id), e = db.edges[k];
        if (e && e.st === 'ok') { send(res, 200, { ok: true, msg: 'כבר חברים' }); return true; }
        if (e && e.a === o.id) { e.st = 'ok'; save(); send(res, 200, { ok: true, msg: 'אתם חברים עכשיו' }); return true; }
        if (!e) db.edges[k] = { a: me.id, b: o.id, st: 'p', t: Date.now() };
        save(); send(res, 200, { ok: true, msg: 'הבקשה נשלחה ל' + o.name }); return true;
      }
      if (p === '/api/friends/respond') {
        const e = db.edges[String(b.id || '')];
        if (!e || e.st !== 'p' || e.b !== me.id) { send(res, 404, { error: 'nf' }); return true; }
        if (b.accept) e.st = 'ok'; else delete db.edges[b.id];
        save(); send(res, 200, { ok: true }); return true;
      }
      if (p === '/api/friends/remove' || p === '/api/friends/block') {
        const k = String(b.id || ''), e = db.edges[k];
        if (!e || (e.a !== me.id && e.b !== me.id)) { send(res, 404, { error: 'nf' }); return true; }
        const oid = e.a === me.id ? e.b : e.a;
        delete db.edges[k];
        if (p.endsWith('block')) { db.blocks[me.id] = db.blocks[me.id] || []; if (!db.blocks[me.id].includes(oid)) db.blocks[me.id].push(oid); }
        save(); send(res, 200, { ok: true }); return true;
      }
      if (p === '/api/report') {
        db.reports.push({ by: me.name, about: String(b.name || '').slice(0, 40), reason: String(b.reason || '').slice(0, 300), t: Date.now() });
        if (db.reports.length > 500) db.reports.shift();
        save(); send(res, 200, { ok: true }); return true;
      }
      send(res, 404, { error: 'x' }); return true;
    } catch (e) { send(res, 400, { error: 'bad request' }); return true; }
  };
};
