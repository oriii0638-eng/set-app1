'use strict';
// מטבעות 🪙, משימות, חנות פריטים לאווטר, ושמירת הדמות.
// הכול נשמר בשרת (ולא בטלפון), כדי שאי אפשר יהיה "לייצר" מטבעות.
const DAY = 86400000;
// היום והשבוע לפי שעון ישראל (בערך: UTC+2)
const dayNum = (t = Date.now()) => Math.floor((t + 2 * 3600e3) / DAY);
const weekNum = (t = Date.now()) => Math.floor((dayNum(t) + 4) / 7); // שבוע שמתחיל ביום ראשון

const EARN = {
  daily: { add: 5, perDay: 1 },
  workout: { add: 20, perDay: 2 },
  meal: { add: 5, perDay: 1 },
  story: { add: 10, perDay: 1 },
  pr: { add: 10, perDay: 3 },
  week: { add: 50, perWeek: 1 },
};
const STREAK_BONUS = 30;          // כל 7 ימים ברצף של כניסה
const INVITE_COINS = 150;         // למזמין, כשהחבר מסיים אימון ראשון
const WELCOME_COINS = 50;         // לחבר שהוזמן, באימון הראשון

// מחירון החנות. פריטים שלא מופיעים כאן חינמיים
const SHOP = {
  'hat:1': 60, 'hat:2': 60, 'hat:3': 40, 'hat:4': 120, 'hat:5': 400, 'hat:6': 80,
  'gl:1': 50, 'gl:2': 80, 'gl:3': 50,
  'acc:1': 150, 'acc:2': 100, 'acc:3': 200, 'acc:4': 40,
  'sh:2': 80, 'sh:3': 100, 'sh:4': 150, 'sh:5': 60,
  'bg:7': 70, 'bg:8': 90, 'bg:9': 250, 'bg:10': 120,
  'so:3': 180, 'so:1': 60, 'pn:3': 50,
};
// טווחי ערכים מותרים לכל חלק בדמות
const RANGE = { bt: 5, sk: 6, hs: 9, hc: 8, ey: 4, br: 3, mo: 4, fh: 4, sh: 6, sc: 8, pn: 4, pc: 8, so: 4, soc: 6, hat: 7, gl: 4, acc: 5, bg: 11 };

module.exports = function (db, save, send, readBody, userFor) {
  function cl(u) { u.cl = u.cl || {}; return u.cl; }
  function add(u, n, why) {
    u.coins = Math.max(0, (u.coins || 0) + n);
    (u.clog = u.clog || []).push([Date.now(), n, why]); if (u.clog.length > 60) u.clog = u.clog.slice(-60);
  }
  function countToday(u, kind) { const c = cl(u)[kind]; return c && c.d === dayNum() ? c.n : 0; }
  function bump(u, kind) { const c = cl(u), d = dayNum(); if (!c[kind] || c[kind].d !== d) c[kind] = { d, n: 0 }; c[kind].n++; }

  /* פרס הזמנה: החבר סיים אימון ראשון. המזמין מקבל מטבעות (גם משתמש רגיל, לא רק שגריר) */
  function inviteReward(u) {
    if (!u.refBy || u.refCoined) return 0;
    const r = Object.values(db.users).find(x => x.id === u.refBy);
    u.refCoined = Date.now();
    add(u, WELCOME_COINS, 'welcome');
    if (r) { add(r, INVITE_COINS, 'invite'); r.refCoins = (r.refCoins || 0) + INVITE_COINS; }
    return WELCOME_COINS;
  }

  function status(u) {
    const d = dayNum();
    return {
      coins: u.coins || 0, inv: u.inv || [], av: u.av || null,
      today: Object.fromEntries(Object.keys(EARN).filter(k => EARN[k].perDay).map(k => [k, countToday(u, k)])),
      weekDone: !!(cl(u).week && cl(u).week.w === weekNum()),
      streak: cl(u).streak && cl(u).streak.last >= d - 1 ? cl(u).streak.n : 0,
      earn: Object.fromEntries(Object.keys(EARN).map(k => [k, EARN[k].add])),
      shop: SHOP, invite: { coins: INVITE_COINS, welcome: WELCOME_COINS, earned: u.refCoins || 0 },
    };
  }

  function clean(av, u) {
    if (!av || typeof av !== 'object') return null;
    const out = {}, inv = u.inv || [];
    for (const k of Object.keys(RANGE)) {
      let v = Math.round(Number(av[k]) || 0);
      if (!(v >= 0 && v < RANGE[k])) v = 0;
      if (SHOP[k + ':' + v] && !inv.includes(k + ':' + v)) v = 0; // פריט בתשלום שלא נקנה
      out[k] = v;
    }
    return out;
  }

  return async function handle(req, res, url) {
    if (!url.pathname.startsWith('/api/coins') && url.pathname !== '/api/avatar' && url.pathname !== '/api/shop/buy') return false;
    const u = userFor(req); if (!u) { send(res, 401, { error: 'auth' }); return true; }
    if (req.method === 'GET' && url.pathname === '/api/coins') { send(res, 200, status(u)); return true; }
    if (req.method === 'POST' && url.pathname === '/api/coins/claim') {
      const b = await readBody(req), kind = String(b.kind || ''), e = EARN[kind];
      if (!e) { send(res, 400, { error: 'x' }); return true; }
      let got = 0, bonus = 0, welcome = 0;
      if (e.perWeek) {
        const c = cl(u);
        if (!(c.week && c.week.w === weekNum())) { c.week = { w: weekNum() }; got = e.add; add(u, got, kind); }
      } else if (countToday(u, kind) < e.perDay) {
        bump(u, kind); got = e.add; add(u, got, kind);
        if (kind === 'daily') {
          const c = cl(u), d = dayNum(), s = c.streak || { last: 0, n: 0 };
          s.n = s.last === d - 1 ? s.n + 1 : 1; s.last = d; c.streak = s;
          if (s.n % 7 === 0) { bonus = STREAK_BONUS; add(u, bonus, 'streak'); }
        }
        if (kind === 'workout') welcome = inviteReward(u);
      }
      if (got || bonus || welcome) save();
      send(res, 200, Object.assign(status(u), { add: got, bonus, welcome })); return true;
    }
    if (req.method === 'POST' && url.pathname === '/api/shop/buy') {
      const b = await readBody(req), id = String(b.id || ''), price = SHOP[id];
      if (!price) { send(res, 400, { error: 'הפריט לא נמצא' }); return true; }
      u.inv = u.inv || [];
      if (u.inv.includes(id)) { send(res, 200, status(u)); return true; }
      if ((u.coins || 0) < price) { send(res, 400, { error: 'אין מספיק מטבעות', need: price - (u.coins || 0) }); return true; }
      add(u, -price, 'buy ' + id); u.inv.push(id); save();
      send(res, 200, status(u)); return true;
    }
    if (req.method === 'POST' && url.pathname === '/api/avatar') {
      const b = await readBody(req), av = clean(b.av, u);
      if (!av) { send(res, 400, { error: 'x' }); return true; }
      u.av = av; save(); send(res, 200, status(u)); return true;
    }
    send(res, 404, { error: 'x' }); return true;
  };
};
module.exports.SHOP = SHOP;
