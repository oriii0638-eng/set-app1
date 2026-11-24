'use strict';
// התראות לטלפון (Web Push) בלי תלויות חיצוניות: הצפנה לפי RFC 8291 וזיהוי VAPID.
const crypto = require('crypto'), https = require('https');
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
  function sendPush(sub, payload) {
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
    return { d: Math.round((Date.UTC(+p.year, +p.month - 1, +p.day) - Date.UTC(2020, 0, 1)) / 86400000), h: +p.hour };
  }
  function parse(k) { try { return JSON.parse(db.docs[k].json); } catch (e) { return null; } }
  function todays(uid, d) {
    const co = parse('coach/' + uid); if (!co || co.rejected || !Array.isArray(co.sched)) return null;
    const en = co.sched.filter(e => e.d === d)[0]; if (!en) return null;
    const tr = parse('trainees/' + uid);
    if (tr && (tr.sessions || []).some(s => s.sk === d)) return null;
    return { name: en.prog && en.prog.name ? en.prog.name : '' };
  }
  async function tick() {
    const n = nowIL();
    for (const uid in db.push) {
      const rec = db.push[uid];
      if (!rec || !rec.subs || !rec.subs.length || rec.last === n.d || n.h < (rec.hour == null ? 17 : rec.hour)) continue;
      const t = todays(uid, n.d); if (!t) continue;
      rec.last = n.d; save();
      const msg = { title: 'סט · יש לך אימון היום', body: (t.name ? t.name + '. ' : '') + 'בוא נעשה את זה! הכול מחכה לך באפליקציה.', url: '/' };
      const keep = [];
      for (const s of rec.subs) { const code = await sendPush(s, msg); if (code !== 404 && code !== 410) keep.push(s); }
      rec.subs = keep; save();
    }
  }
  setInterval(() => { tick().catch(() => {}); }, 5 * 60 * 1000);
  setTimeout(() => { tick().catch(() => {}); }, 20000);

  return async function handle(req, res, url) {
    if (!url.pathname.startsWith('/api/push')) return false;
    const me = userFor(req); if (!me) { send(res, 401, { error: 'login' }); return true; }
    if (req.method === 'GET' && url.pathname === '/api/push/state') {
      const r = db.push[me.id];
      send(res, 200, { key: b64u(pubRaw), on: !!(r && r.subs && r.subs.length), hour: r && r.hour != null ? r.hour : 17 }); return true;
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
  };
};
module.exports.encrypt = null;
