'use strict';
// התראות לטלפון (Web Push) בלי תלויות חיצוניות: הצפנה לפי RFC 8291 וזיהוי VAPID.
const crypto = require('crypto'), https = require('https'), http2 = require('http2');
const TZ = 'Asia/Jerusalem';
const b64u = b => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const unb64u = s => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');

module.exports = function (db, save, send, readBody, userFor) {
  db.push = db.push || {};
  if (!db.vapid) {
    const kp = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
    db.vapid = { priv: kp.privateKey.export({ format: 'jwk' }), pub: kp.publicKey.export({ format: 'jwk' }) };
    save();
  }
  const privKey = crypto.createPrivateKey({ key: db.vapid.priv, format: 'jwk' });
  const pubRaw = Buffer.concat([Buffer.from([4]), unb64u(db.vapid.pub.x), unb64u(db.vapid.pub.y)]);

  function vapidHeader(endpoint) {
    const aud = new URL(endpoint).origin;
    const head = b64u(JSON.stringify({ typ: 'JWT', alg: 'ES256' }));
    const body = b64u(JSON.stringify({ aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: 'mailto:set-app@example.com' }));
    const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key: privKey, dsaEncoding: 'ieee-p1363' });
    return 'vapid t=' + head + '.' + body + '.' + b64u(sig) + ', k=' + b64u(pubRaw);
  }
  function encrypt(sub, payload) {
    const ua = unb64u(sub.keys.p256dh), auth = unb64u(sub.keys.auth);
    const ecdh = crypto.createECDH('prime256v1'); ecdh.generateKeys();
    const asPub = ecdh.getPublicKey(), secret = ecdh.computeSecret(ua);
    const hk = (salt, ikm, info, len) => Buffer.from(crypto.hkdfSync('sha256', ikm, salt, info, len));
    const prk = hk(auth, secret, Buffer.concat([Buffer.from('WebPush: info\0'), ua, asPub]), 32);
    const salt = crypto.randomBytes(16);
    const cek = hk(salt, prk, Buffer.from('Content-Encoding: aes128gcm\0'), 16);
    const nonce = hk(salt, prk, Buffer.from('Content-Encoding: nonce\0'), 12);
    const c = crypto.createCipheriv('aes-128-gcm', cek, nonce);
    const enc = Buffer.concat([c.update(Buffer.concat([Buffer.from(payload), Buffer.from([2])])), c.final(), c.getAuthTag()]);
    const rs = Buffer.alloc(4); rs.writeUInt32BE(4096);
    return Buffer.concat([salt, rs, Buffer.from([asPub.length]), asPub, enc]);
  }
  /* ---------- התראות לאפליקציית האייפון דרך Apple (APNs) ----------
     משתני סביבה: APNS_KEY (תוכן קובץ ה-p8), APNS_KEY_ID, APNS_TEAM_ID, APNS_TOPIC */
  const APNS = {
    key: String(process.env.APNS_KEY || '').replace(/\\n/g, '\n').trim(),
    kid: process.env.APNS_KEY_ID || '', team: process.env.APNS_TEAM_ID || '7FJYSD96DH', topic: process.env.APNS_TOPIC || 'com.setapp.workout'
  };
  APNS.on = !!(APNS.key && APNS.kid);
  let apnsJwt = null, apnsJwtT = 0;
  function apnsToken() {
    if (apnsJwt && Date.now() - apnsJwtT < 40 * 60e3) return apnsJwt;
    const head = b64u(JSON.stringify({ alg: 'ES256', kid: APNS.kid })), body = b64u(JSON.stringify({ iss: APNS.team, iat: Math.floor(Date.now() / 1000) }));
    const sig = crypto.sign('sha256', Buffer.from(head + '.' + body), { key: crypto.createPrivateKey(APNS.key), dsaEncoding: 'ieee-p1363' });
    apnsJwt = head + '.' + body + '.' + b64u(sig); apnsJwtT = Date.now(); return apnsJwt;
  }
  function apnsSend(host, token, payload) {
    return new Promise(resolve => {
      let c; try { c = http2.connect('https://' + host); } catch (e) { return resolve({ code: 0 }); }
      c.on('error', () => resolve({ code: 0 }));
      const body = JSON.stringify({ aps: { alert: { title: payload.title, body: payload.body }, sound: 'default', 'thread-id': payload.thread || 'set' }, url: payload.url || '/', tab: payload.tab || '' });
      let req; try {
        req = c.request({ ':method': 'POST', ':path': '/3/device/' + token, authorization: 'bearer ' + apnsToken(), 'apns-topic': APNS.topic, 'apns-push-type': 'alert', 'apns-priority': '10', 'content-type': 'application/json' });
      } catch (e) { c.close(); return resolve({ code: 0 }); }
      let code = 0, data = '';
      req.setTimeout(15000, () => { req.close(); });
      req.on('response', h => { code = h[':status']; });
      req.on('data', d => { data += d; });
      req.on('end', () => { c.close(); let reason = ''; try { reason = JSON.parse(data).reason || ''; } catch (e) {} resolve({ code, reason }); });
      req.on('error', () => { c.close(); resolve({ code: 0 }); });
      req.end(body);
    });
  }
  async function sendApns(sub, payload) {
    if (!APNS.on) return 0;
    let r = await apnsSend(sub.dev ? 'api.sandbox.push.apple.com' : 'api.push.apple.com', sub.apns, payload);
    if (r.code === 400 && r.reason === 'BadDeviceToken') { sub.dev = !sub.dev; r = await apnsSend(sub.dev ? 'api.sandbox.push.apple.com' : 'api.push.apple.com', sub.apns, payload); }
    if (r.code === 410 || (r.code === 400 && r.reason === 'BadDeviceToken')) return 410;
    return r.code;
  }
  function sendPush(sub, payload) {
    if (sub && sub.apns) return sendApns(sub, payload);
    return new Promise(resolve => {
      let body;
      try { body = encrypt(sub, JSON.stringify(payload)); } catch (e) { return resolve(0); }
      const u = new URL(sub.endpoint);
      const r = https.request({ method: 'POST', hostname: u.hostname, port: u.port || 443, path: u.pathname + u.search, timeout: 15000,
        headers: { 'Content-Encoding': 'aes128gcm', 'Content-Type': 'application/octet-stream', 'Content-Length': body.length, TTL: '43200', Urgency: 'normal', Authorization: vapidHeader(sub.endpoint) } },
        res => { res.resume(); resolve(res.statusCode); });
      r.on('error', () => resolve(0)); r.on('timeout', () => { r.destroy(); resolve(0); });
      r.end(body);
    });
  }
  function nowIL() {
    const p = {};
    new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', hourCycle: 'h23' })
      .formatToParts(new Date()).forEach(x => p[x.type] = x.value);
    const d = Math.round((Date.UTC(+p.year, +p.month - 1, +p.day) - Date.UTC(2020, 0, 1)) / 86400000);
    return { d, h: +p.hour, dow: new Date(Date.UTC(2020, 0, 1) + d * 86400000).getUTCDay() };
  }
  function dayOf(ms) {
    const p = {};
    new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(ms)).forEach(x => p[x.type] = x.value);
    return Math.round((Date.UTC(+p.year, +p.month - 1, +p.day) - Date.UTC(2020, 0, 1)) / 86400000);
  }
  function weekStats(uid, n) {
    const tr = parse('trainees/' + uid); if (!tr || !Array.isArray(tr.sessions)) return null;
    const ws = n.d - n.dow; let cnt = 0, vol = 0;
    tr.sessions.forEach(s => {
      const dd = dayOf(s.date); if (dd < ws || dd > n.d) return; cnt++;
      (s.exercises || []).forEach(e => (e.sets || []).forEach(x => { vol += (x.kg || 0) * (x.reps || 0); }));
    });
    return cnt ? { cnt, vol: Math.round(vol / 100) / 10, goal: Number(tr.profile && tr.profile.days) || 3 } : null;
  }
  function parse(k) { try { return JSON.parse(db.docs[k].json); } catch (e) { return null; } }
  function todays(uid, d) {
    const co = parse('coach/' + uid), tr = parse('trainees/' + uid);
    let sched = null;
    if (co && !co.rejected && Array.isArray(co.sched)) sched = co.sched;
    else if (tr && tr.ai && Array.isArray(tr.sched)) sched = tr.sched;   // אימונים אוטומטיים בלי מאמן
    if (!sched) return null;
    const en = sched.filter(e => e.d === d)[0]; if (!en) return null;
    if (tr && (tr.sessions || []).some(s => s.sk === d)) return null;
    return { name: en.prog && en.prog.name ? en.prog.name : '' };
  }
  async function tick() {
    const n = nowIL();
    for (const uid in db.push) {
      const rec = db.push[uid];
      if (rec && rec.subs && rec.subs.length && n.dow === 5 && n.h >= 11 && rec.wlast !== n.d) {
        rec.wlast = n.d; save();
        const w = weekStats(uid, n);
        if (w) {
          const msg = { title: 'סט · הסיכום השבועי שלך', body: w.cnt + ' מתוך ' + w.goal + ' אימונים השבוע' + (w.vol ? ' · ' + w.vol + ' טון נפח' : '') + (w.cnt >= w.goal ? '. שבוע מושלם! 🔥' : '. כל הכבוד על ההתמדה!'), url: '/' };
          const keep = [];
          for (const sb of rec.subs) { const code = await sendPush(sb, msg); if (code !== 404 && code !== 410) keep.push(sb); }
          rec.subs = keep; save();
        }
      }
      if (!rec || !rec.subs || !rec.subs.length || rec.last === n.d || n.h < (rec.hour == null ? 17 : rec.hour)) continue;
      const t = todays(uid, n.d); if (!t) continue;
      rec.last = n.d; save();
      const msg = { title: 'סט · יש לך אימון היום', body: (t.name ? t.name + '. ' : '') + 'בוא נעשה את זה! הכול מחכה לך באפליקציה.', url: '/' };
      const keep = [];
      for (const s of rec.subs) { const code = await sendPush(s, msg); if (code !== 404 && code !== 410) keep.push(s); }
      rec.subs = keep; save();
    }
  }
  /* התראה על אירוע (בקשת חברות, הזמנה לתחרות, הודעה מהמאמן). לכל היותר אחת ל-20 שניות מאותו סוג */
  async function notify(uid, msg) {
    const rec = db.push[uid]; if (!rec || !rec.subs || !rec.subs.length) return 0;
    rec.nt = rec.nt || {}; const k = msg.kind || 'x';
    if (rec.nt[k] && Date.now() - rec.nt[k] < 20000) return 0; rec.nt[k] = Date.now();
    const keep = []; let ok = 0;
    for (const s of rec.subs) { const code = await sendPush(s, msg); if (code >= 200 && code < 300) ok++; if (code !== 404 && code !== 410) keep.push(s); }
    rec.subs = keep; save(); return ok;
  }
  setInterval(() => { tick().catch(() => {}); }, 5 * 60 * 1000);
  setTimeout(() => { tick().catch(() => {}); }, 20000);

  async function handle(req, res, url) {
    if (!url.pathname.startsWith('/api/push')) return false;
    const me = userFor(req); if (!me) { send(res, 401, { error: 'login' }); return true; }
    if (req.method === 'GET' && url.pathname === '/api/push/state') {
      const r = db.push[me.id];
      send(res, 200, { key: b64u(pubRaw), on: !!(r && r.subs && r.subs.length), native: !!(r && r.subs && r.subs.some(x => x.apns)), apns: APNS.on, hour: r && r.hour != null ? r.hour : 17 }); return true;
    }
    if (req.method === 'POST' && url.pathname === '/api/push/apns') {
      const b = await readBody(req), t = String(b.token || '').replace(/[^0-9a-fA-F]/g, '');
      if (t.length < 32 || t.length > 200) { send(res, 400, { error: 'bad' }); return true; }
      for (const id in db.push) if (id !== me.id && db.push[id].subs) db.push[id].subs = db.push[id].subs.filter(x => x.apns !== t); // מכשיר שעבר משתמש
      const r = db.push[me.id] = db.push[me.id] || { subs: [], hour: 17 };
      r.subs = r.subs.filter(x => x.apns !== t).concat([{ apns: t, dev: !!b.dev }]).slice(-5);
      if (b.hour != null && b.hour >= 6 && b.hour <= 22 && !(b.auto && r.custom)) r.hour = Math.floor(b.hour);
      save(); send(res, 200, { ok: true, apns: APNS.on }); return true;
    }
    if (req.method === 'POST' && url.pathname === '/api/push/sub') {
      const b = await readBody(req), s = b.subscription;
      if (!s || typeof s.endpoint !== 'string' || !/^https:\/\//.test(s.endpoint) || !s.keys || !s.keys.p256dh || !s.keys.auth) { send(res, 400, { error: 'bad' }); return true; }
      const r = db.push[me.id] = db.push[me.id] || { subs: [], hour: 17 };
      r.subs = r.subs.filter(x => x.endpoint !== s.endpoint).concat([{ endpoint: s.endpoint, keys: { p256dh: String(s.keys.p256dh), auth: String(s.keys.auth) } }]).slice(-5);
      if (b.hour != null && b.hour >= 6 && b.hour <= 22 && !(b.auto && r.custom)) { r.hour = Math.floor(b.hour); if (!b.auto) r.custom = true; }
      save(); send(res, 200, { ok: true }); return true;
    }
    if (req.method === 'POST' && url.pathname === '/api/push/hour') {
      const b = await readBody(req), r = db.push[me.id];
      if (r && b.hour >= 6 && b.hour <= 22 && !(b.auto && r.custom)) { r.hour = Math.floor(b.hour); if (!b.auto) r.custom = true; save(); }
      send(res, 200, { ok: true, hour: r && r.hour != null ? r.hour : null }); return true;
    }
    if (req.method === 'POST' && url.pathname === '/api/push/off') { delete db.push[me.id]; save(); send(res, 200, { ok: true }); return true; }
    if (req.method === 'POST' && url.pathname === '/api/push/test') {
      const r = db.push[me.id]; let ok = 0;
      if (r) for (const s of r.subs) { const c = await sendPush(s, { title: 'סט', body: 'ההתראות עובדות. נתראה באימון!', url: '/' }); if (c >= 200 && c < 300) ok++; }
      send(res, 200, { sent: ok }); return true;
    }
    send(res, 404, { error: 'nf' }); return true;
  }
  handle.notify = notify;
  return handle;
};
module.exports.encrypt = null;
