'use strict';
// גבייה דרך Google Play: אימות מנוי מול Google Play Developer API (subscriptionsv2) עם חשבון שירות.
// הגדרות בשרת:
//   GOOGLE_PLAY_SA       תוכן קובץ ה-JSON של חשבון השירות (אפשר גם ב-base64)
//   GOOGLE_PLAY_PACKAGE  שם החבילה של האפליקציה (ברירת מחדל com.setapp.workout)
const crypto = require('crypto'), https = require('https');
const PKG = process.env.GOOGLE_PLAY_PACKAGE || 'com.setapp.workout';

function loadSa() {
  const raw = process.env.GOOGLE_PLAY_SA || '';
  if (!raw) return null;
  try { return JSON.parse(raw.trim().startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8')); }
  catch (e) { console.log('[gplay] GOOGLE_PLAY_SA is not valid JSON'); return null; }
}
const SA = loadSa();
if (SA) console.log('[gplay] service account ' + SA.client_email);

function req(method, url, headers, body) {
  return new Promise((resolve, reject) => {
    const r = https.request(url, { method, headers }, resp => {
      const ch = []; resp.on('data', c => ch.push(c));
      resp.on('end', () => { const t = Buffer.concat(ch).toString('utf8'); let j = null; try { j = JSON.parse(t); } catch (e) {} resolve({ status: resp.statusCode, json: j, text: t }); });
    });
    r.on('error', reject); r.setTimeout(20000, () => r.destroy(new Error('timeout')));
    if (body) r.write(body); r.end();
  });
}
const b64u = b => Buffer.from(b).toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_');
let tok = { v: '', exp: 0 };
async function accessToken() {
  if (!SA) throw new Error('Google Play לא הוגדר בשרת');
  if (tok.v && tok.exp > Date.now() + 60000) return tok.v;
  const now = Math.floor(Date.now() / 1000), aud = SA.token_uri || 'https://oauth2.googleapis.com/token';
  const unsigned = b64u(JSON.stringify({ alg: 'RS256', typ: 'JWT' })) + '.' + b64u(JSON.stringify({ iss: SA.client_email, scope: 'https://www.googleapis.com/auth/androidpublisher', aud, iat: now, exp: now + 3600 }));
  const sig = crypto.createSign('RSA-SHA256').update(unsigned).sign(SA.private_key);
  const body = 'grant_type=' + encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer') + '&assertion=' + unsigned + '.' + b64u(sig);
  const r = await req('POST', aud, { 'content-type': 'application/x-www-form-urlencoded', 'content-length': Buffer.byteLength(body) }, body);
  if (r.status !== 200 || !r.json || !r.json.access_token) throw new Error('google auth ' + r.status);
  tok = { v: r.json.access_token, exp: Date.now() + (r.json.expires_in || 3600) * 1000 };
  return tok.v;
}
// מחזיר עסקה בפורמט שדומה לזה של Apple, כדי ששאר הקוד יעבוד אותו דבר
async function verifySub(purchaseToken) {
  const t = String(purchaseToken || '');
  if (!/^[A-Za-z0-9._:-]{20,600}$/.test(t)) throw new Error('bad token');
  const at = await accessToken();
  const r = await req('GET', 'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/' + encodeURIComponent(PKG) + '/purchases/subscriptionsv2/tokens/' + encodeURIComponent(t), { authorization: 'Bearer ' + at });
  if (r.status !== 200 || !r.json) throw new Error('google ' + r.status + (r.json && r.json.error ? ' ' + r.json.error.message : ''));
  const s = r.json, items = Array.isArray(s.lineItems) ? s.lineItems : [];
  if (!items.length) throw new Error('no items');
  const item = items.reduce((a, b) => (Date.parse(b.expiryTime || 0) > Date.parse(a.expiryTime || 0) ? b : a));
  const live = ['SUBSCRIPTION_STATE_ACTIVE', 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD', 'SUBSCRIPTION_STATE_CANCELED'].indexOf(s.subscriptionState) >= 0;
  const ext = s.externalAccountIdentifiers || {};
  return {
    store: 'google',
    bundleId: PKG,
    productId: item.productId,
    originalTransactionId: 'gp:' + crypto.createHash('sha256').update(s.linkedPurchaseToken || t).digest('hex').slice(0, 32),
    purchaseToken: t,
    expiresDate: live ? Date.parse(item.expiryTime) || 0 : 0,
    appAccountToken: ext.obfuscatedExternalAccountId || '',
    environment: s.testPurchase ? 'Sandbox' : 'Production',
    state: s.subscriptionState,
  };
}
// הודעות בזמן אמת מ-Google Play (Pub/Sub push). מחזיר את ה-purchaseToken שצריך לבדוק מחדש
function rtdnToken(body) {
  try {
    const d = JSON.parse(Buffer.from(body.message.data, 'base64').toString('utf8'));
    if (d.packageName !== PKG) return null;
    return d.subscriptionNotification && d.subscriptionNotification.purchaseToken || null;
  } catch (e) { return null; }
}
module.exports = { verifySub, rtdnToken, configured: () => !!SA, PKG };
