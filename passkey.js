'use strict';
// כניסה עם Face ID / טביעת אצבע (Passkeys, תקן WebAuthn). בלי תלויות חיצוניות.
const crypto = require('crypto');
const b64u = b => Buffer.from(b).toString('base64url');
const unb64u = s => Buffer.from(String(s || ''), 'base64url');

function cbor(buf, o) {                       // מפענח CBOR מינימלי: מספרים, בייטים, טקסט, מערכים ומפות
  const b = buf; let p = o || 0;
  function item() {
    const ib = b[p++], mt = ib >> 5; let ai = ib & 31, n;
    if (ai < 24) n = ai; else if (ai === 24) n = b[p++]; else if (ai === 25) { n = b.readUInt16BE(p); p += 2; }
    else if (ai === 26) { n = b.readUInt32BE(p); p += 4; } else throw new Error('cbor');
    if (mt === 0) return n; if (mt === 1) return -1 - n;
    if (mt === 2) { const r = b.subarray(p, p + n); p += n; return r; }
    if (mt === 3) { const r = b.toString('utf8', p, p + n); p += n; return r; }
    if (mt === 4) { const a = []; for (let i = 0; i < n; i++) a.push(item()); return a; }
    if (mt === 5) { const m = new Map(); for (let i = 0; i < n; i++) { const k = item(); m.set(k, item()); } return m; }
    throw new Error('cbor');
  }
  return item();
}

module.exports = function (db, save, send, readBody, userFor, startSession) {
  db.passkeys = db.passkeys || {};
  const chal = new Map();
  const mk = uid => { const c = crypto.randomBytes(32).toString('base64url'); chal.set(c, { uid, t: Date.now() }); for (const [k, v] of chal) if (Date.now() - v.t > 300000) chal.delete(k); return c; };
  const take = c => { const v = chal.get(c); chal.delete(c); return v && Date.now() - v.t < 300000 ? v : null; };
  const rpOf = req => String(req.headers.host || '').replace(/:\d+$/, '');
  function checkClient(req, cdj, type) {
    const cd = JSON.parse(cdj.toString('utf8'));
    if (cd.type !== type) throw new Error('type');
    const host = rpOf(req), oh = new URL(cd.origin).hostname;
    if (oh !== host) throw new Error('origin');
    const v = take(cd.challenge); if (!v) throw new Error('challenge');
    return v;
  }
  const rpHash = req => crypto.createHash('sha256').update(rpOf(req)).digest();

  return async function handle(req, res, url) {
    if (!url.pathname.startsWith('/api/pk/')) return false;
    try {
      const p = url.pathname;
      if (req.method !== 'POST') { send(res, 405, { error: 'x' }); return true; }
      const b = await readBody(req);
      if (p === '/api/pk/login-options') { send(res, 200, { challenge: mk(null), rpId: rpOf(req) }); return true; }
      if (p === '/api/pk/login-finish') {
        const cred = db.passkeys[b.id]; if (!cred) throw new Error('nocred');
        const cdj = unb64u(b.clientDataJSON), ad = unb64u(b.authenticatorData), sig = unb64u(b.signature);
        checkClient(req, cdj, 'webauthn.get');
        if (!ad.subarray(0, 32).equals(rpHash(req)) || !(ad[32] & 1)) throw new Error('rp');
        const data = Buffer.concat([ad, crypto.createHash('sha256').update(cdj).digest()]);
        const ok = crypto.verify('sha256', data, { key: crypto.createPublicKey({ key: cred.jwk, format: 'jwk' }), dsaEncoding: 'der' }, sig);
        if (!ok) throw new Error('sig');
        const user = db.users[cred.user]; if (!user) throw new Error('user');
        cred.last = Date.now(); save();
        send(res, 200, { ok: true }, { 'Set-Cookie': startSession(req, res, user) }); return true;
      }
      const me = userFor(req); if (!me) { send(res, 401, { error: 'login' }); return true; }
      if (p === '/api/pk/reg-options') {
        send(res, 200, { challenge: mk(me.id), rp: { id: rpOf(req), name: 'סט' }, user: { id: b64u(me.id), name: me.name, displayName: me.name },
          exclude: Object.keys(db.passkeys).filter(k => db.passkeys[k].user === me.name) }); return true;
      }
      if (p === '/api/pk/reg-finish') {
        const cdj = unb64u(b.clientDataJSON);
        const v = checkClient(req, cdj, 'webauthn.create');
        if (v.uid !== me.id) throw new Error('who');
        const att = cbor(unb64u(b.attestationObject)), ad = att.get('authData');
        if (!ad.subarray(0, 32).equals(rpHash(req)) || !(ad[32] & 1) || !(ad[32] & 0x40)) throw new Error('rp');
        const idLen = ad.readUInt16BE(53), credId = ad.subarray(55, 55 + idLen), key = cbor(ad, 55 + idLen);
        if (key.get(3) !== -7 || key.get(1) !== 2) throw new Error('alg');
        db.passkeys[b64u(credId)] = { user: me.name, jwk: { kty: 'EC', crv: 'P-256', x: b64u(key.get(-2)), y: b64u(key.get(-3)) }, created: Date.now() };
        save(); send(res, 200, { ok: true }); return true;
      }
      if (p === '/api/pk/remove') {
        Object.keys(db.passkeys).forEach(k => { if (db.passkeys[k].user === me.name) delete db.passkeys[k]; });
        save(); send(res, 200, { ok: true }); return true;
      }
      send(res, 404, { error: 'x' }); return true;
    } catch (e) { if (process.env.PK_DEBUG) console.log('pk', e.message); send(res, 400, { error: 'האימות נכשל. נסה שוב או היכנס עם סיסמה' }); return true; }
  };
};
