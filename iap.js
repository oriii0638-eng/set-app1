'use strict';
// גבייה דרך Apple (StoreKit 2): אימות רכישות בשרת וקבלת עדכוני חידוש.
// הרכישה נחתמת ע"י Apple כ-JWS. כאן מוודאים את שרשרת האישורים מול Apple Root CA - G3 (נעוץ לפי טביעת אצבע), ואת החתימה.
const crypto = require('crypto');
const gplay = require('./gplay.js');
const BUNDLE = process.env.IAP_BUNDLE_ID || 'com.setapp.workout';
const PRODUCTS = { 'com.setapp.workout.monthly': 'sub', 'com.setapp.workout.yearly': 'sub', 'com.setapp.workout.coach': 'coach' };
// Apple Root CA - G3, SHA-256 (מתוך רשימת אישורי השורש של Apple)
const APPLE_ROOT_FP = '63:34:3A:BF:B8:9A:6A:03:EB:B5:7E:9B:3F:5F:A7:BE:7C:4F:5C:75:6F:30:17:B3:A8:C4:88:C3:65:3E:91:79';
const b64u = s => Buffer.from(String(s).replace(/-/g, '+').replace(/_/g, '/'), 'base64');

function verifyJws(jws, rootFp) {
  const p = String(jws || '').split('.');
  if (p.length !== 3) throw new Error('bad jws');
  const head = JSON.parse(b64u(p[0]).toString('utf8'));
  if (head.alg !== 'ES256' || !Array.isArray(head.x5c) || head.x5c.length < 2) throw new Error('bad header');
  const certs = head.x5c.map(c => new crypto.X509Certificate(Buffer.from(c, 'base64')));
  const root = certs[certs.length - 1];
  if (root.fingerprint256 !== (rootFp || APPLE_ROOT_FP)) throw new Error('untrusted root');
  for (let i = 0; i < certs.length - 1; i++) {
    if (!certs[i].checkIssued(certs[i + 1]) || !certs[i].verify(certs[i + 1].publicKey)) throw new Error('bad chain');
  }
  if (!root.verify(root.publicKey)) throw new Error('bad root');
  const ok = crypto.verify('sha256', Buffer.from(p[0] + '.' + p[1]), { key: certs[0].publicKey, dsaEncoding: 'ieee-p1363' }, b64u(p[2]));
  if (!ok) throw new Error('bad signature');
  return JSON.parse(b64u(p[1]).toString('utf8'));
}
// UUID קבוע לכל משתמש. נשלח ל-Apple כ-appAccountToken כדי לקשור רכישה לחשבון
function tokenOf(uid) {
  const h = crypto.createHash('sha256').update('set-iap:' + uid).digest();
  h[6] = (h[6] & 0x0f) | 0x50; h[8] = (h[8] & 0x3f) | 0x80;
  const x = h.subarray(0, 16).toString('hex');
  return `${x.slice(0, 8)}-${x.slice(8, 12)}-${x.slice(12, 16)}-${x.slice(16, 20)}-${x.slice(20, 32)}`.toUpperCase();
}
function check(tx) {
  if (tx.bundleId !== BUNDLE) throw new Error('bundle');
  if (!PRODUCTS[tx.productId]) throw new Error('product');
  return PRODUCTS[tx.productId];
}
function apply(db, u, kind, tx) {
  const exp = tx.revocationDate ? 0 : Number(tx.expiresDate || 0);
  if (kind === 'sub') u.subUntil = exp;
  else { u.coachUntil = exp; u.coachOk = exp > Date.now(); }
  u.iap = u.iap || {}; u.iap[kind] = { otid: tx.originalTransactionId, exp, env: tx.environment };
  if (tx.store === 'google') { u.iap[kind].store = 'google'; u.iap[kind].gp = tx.purchaseToken; }
}
module.exports = function (db, save, send, userFor, readBody, rootFp, onPaid) {
  db.iap = db.iap || {};
  /* מנוי בתשלום (לא תקופת ניסיון: יותר מ-20 יום קדימה) מזכה את מי שהזמין את המשתמש בחודש חינם */
  const paidHook = (u, kind, tx) => { try { if (onPaid && kind === 'sub' && u.refBy && !u.refRewarded && Number(tx.expiresDate || 0) - Date.now() > 20 * 86400e3 && !tx.revocationDate) onPaid(u); } catch (e) {} };
  async function gpRefresh(token) {
    const tx = await gplay.verifySub(token), kind = check(tx), rec = db.iap[tx.originalTransactionId];
    const u = rec && Object.values(db.users).find(x => x.id === rec.uid);
    if (u) { apply(db, u, kind, tx); paidHook(u, kind, tx); save(); }
  }
  /* בלי הודעות מ-Google עדיין מתעדכנים: כל 3 שעות בודקים מנויי Google שעומדים להיגמר או נגמרו ביממה האחרונה */
  if (gplay.configured()) setInterval(async () => {
    const now = Date.now();
    for (const u of Object.values(db.users)) for (const k of Object.keys(u.iap || {})) {
      const r = u.iap[k];
      if (r && r.store === 'google' && r.gp && r.exp < now + 12 * 3600e3 && r.exp > now - 7 * 86400e3) { try { await gpRefresh(r.gp); } catch (e) { console.log('[gplay] refresh ' + u.id + ': ' + e.message); } }
    }
  }, 3 * 3600e3).unref();
  return async function handle(req, res, url) {
    if (url.pathname === '/api/iap/verify' && req.method === 'POST') {
      const me = userFor(req); if (!me) { send(res, 401, { error: 'login' }); return true; }
      let tx, kind, b = {};
      try {
        b = await readBody(req);
        tx = b.gp ? await gplay.verifySub(b.gp) : verifyJws(b.jws, rootFp); kind = check(tx);
      } catch (e) { console.log('[iap] verify failed for ' + me.id + ': ' + e.message); send(res, 400, { error: (b.gp ? 'Google Play' : 'Apple') + ' לא אישרה את הרכישה (' + e.message + ')' }); return true; }
      let owner = db.iap[tx.originalTransactionId];
      /* הרכישה נעשתה במקור מחשבון אחר באפליקציה (appAccountToken של חשבון אחר) */
      if (!owner && tx.appAccountToken && String(tx.appAccountToken).toUpperCase() !== tokenOf(me.id)) {
        const t = String(tx.appAccountToken).toUpperCase(), u0 = Object.values(db.users).find(x => tokenOf(x.id) === t);
        owner = { uid: u0 ? u0.id : '?', kind };
      }
      if (owner && owner.uid !== me.id) {
        const prev = Object.values(db.users).find(x => x.id === owner.uid);
        /* אותו Apple ID כבר משלם על מנוי שמחובר לחשבון אחר. אפשר להעביר אותו לחשבון הנוכחי, באישור המשתמש */
        if (!b.transfer) {
          const em = prev && prev.email ? String(prev.email).replace(/^(.).*?(@.*)$/, '$1***$2') : (prev ? prev.name : '');
          console.log('[iap] owned by other account ' + owner.uid + ' (asked by ' + me.id + ')');
          send(res, 409, { error: 'המנוי של ' + (tx.store === 'google' ? 'חשבון Google Play' : 'ה-Apple ID') + ' הזה כבר מחובר לחשבון אחר', other: em, canTransfer: true, store: tx.store || 'apple' }); return true;
        }
        if (prev) { if ((owner.kind || kind) === 'sub') prev.subUntil = 0; else { prev.coachUntil = 0; prev.coachOk = false; } if (prev.iap) delete prev.iap[owner.kind || kind]; }
        console.log('[iap] transferred ' + tx.originalTransactionId + ' from ' + owner.uid + ' to ' + me.id);
      }
      db.iap[tx.originalTransactionId] = { uid: me.id, kind, productId: tx.productId };
      apply(db, me, kind, tx); paidHook(me, kind, tx); save();
      send(res, 200, { ok: true, kind, until: kind === 'sub' ? me.subUntil : me.coachUntil }); return true;
    }
    if (url.pathname === '/api/iap/google-notify' && req.method === 'POST') {
      // עדכוני חידוש/ביטול מ-Google Play (Real-time developer notifications דרך Pub/Sub push).
      // לא סומכים על תוכן ההודעה: רק לוקחים ממנה את ה-token ובודקים אותו מחדש מול Google
      try { const b = await readBody(req), t = gplay.rtdnToken(b); if (t) await gpRefresh(t); } catch (e) { console.log('[gplay] notify: ' + e.message); }
      send(res, 200, { ok: true }); return true;
    }
    if (url.pathname === '/api/iap/notify' && req.method === 'POST') {
      // עדכוני חידוש/ביטול מ-Apple (App Store Server Notifications V2)
      try {
        const b = await readBody(req), n = verifyJws(b.signedPayload, rootFp), inf = n.data && n.data.signedTransactionInfo;
        if (inf) {
          const tx = verifyJws(inf, rootFp), kind = check(tx), rec = db.iap[tx.originalTransactionId], u = rec && Object.values(db.users).find(x => x.id === rec.uid);
          if (u) { apply(db, u, kind, tx); paidHook(u, kind, tx); save(); }
        }
      } catch (e) { /* מחזירים 200 כדי ש-Apple לא תנסה שוב ושוב */ }
      send(res, 200, { ok: true }); return true;
    }
    return false;
  };
};
module.exports.verifyJws = verifyJws; module.exports.tokenOf = tokenOf; module.exports.APPLE_ROOT_FP = APPLE_ROOT_FP;
