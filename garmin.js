'use strict';
// חיבור ל-Garmin Connect (Health API): OAuth2 PKCE, קליטת נתונים שגרמין דוחפת (Push), וניתוק.
// משתני סביבה: GARMIN_CLIENT_ID, GARMIN_CLIENT_SECRET, PUBLIC_URL (ברירת מחדל: הכתובת ב-Render)
const crypto = require('crypto'), https = require('https');

module.exports = function (db, save, send, userFor) {
  db.garmin = db.garmin || {};      // uid -> { gid, at, rt, exp, rexp, perms, t }
  db.gdata = db.gdata || {};        // uid -> { 'YYYY-MM-DD': { ...נתונים מצומצמים } }
  db.gpk = db.gpk || {};            // state -> { uid, ver, exp }
  const CID = String(process.env.GARMIN_CLIENT_ID || '').trim(), CSEC = String(process.env.GARMIN_CLIENT_SECRET || '').trim();
  const BASE = (process.env.PUBLIC_URL || 'https://set-app-e0r6.onrender.com').replace(/\/$/, '');
  const REDIRECT = BASE + '/api/garmin/callback';
  const on = () => !!(CID && CSEC);
  console.log(on() ? '[garmin] configured (id ' + CID.length + ' chars, secret ' + CSEC.length + ' chars)' : '[garmin] not configured');
  const b64u = b => Buffer.from(b).toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const uidOfG = gid => Object.keys(db.garmin).find(u => db.garmin[u].gid === gid);

  function req(method, url, { body, headers } = {}) {
    return new Promise(resolve => {
      const u = new URL(url);
      const r = https.request({ method, hostname: u.hostname, path: u.pathname + u.search, timeout: 20000, headers: Object.assign({ Accept: 'application/json' }, headers || {}, body ? { 'Content-Length': Buffer.byteLength(body) } : {}) }, res => {
        let d = ''; res.on('data', c => d += c); res.on('end', () => { let j = null; try { j = JSON.parse(d); } catch (e) {} resolve({ code: res.statusCode, j, raw: d }); });
      });
      r.on('error', () => resolve({ code: 0 })); r.on('timeout', () => { r.destroy(); resolve({ code: 0 }); });
      if (body) r.write(body); r.end();
    });
  }
  const form = o => Object.keys(o).map(k => encodeURIComponent(k) + '=' + encodeURIComponent(o[k])).join('&');
  async function tokenReq(fields) {
    const r = await req('POST', 'https://diauth.garmin.com/di-oauth2-service/oauth/token', { body: form(Object.assign({ client_id: CID, client_secret: CSEC }, fields)), headers: { 'Content-Type': 'application/x-www-form-urlencoded', Authorization: 'Basic ' + Buffer.from(CID + ':' + CSEC).toString('base64') } });
    if (!(r.code === 200 && r.j && r.j.access_token)) console.log('[garmin] token ' + fields.grant_type + ' failed: ' + r.code + ' ' + String(r.raw || '').slice(0, 200).replace(/[A-Za-z0-9_-]{30,}/g, '…'));
    return r.code === 200 && r.j && r.j.access_token ? r.j : null;
  }
  async function accessFor(uid) {
    const g = db.garmin[uid]; if (!g) return null;
    if (g.at && g.exp > Date.now() + 10 * 60e3) return g.at;
    const t = await tokenReq({ grant_type: 'refresh_token', refresh_token: g.rt }); if (!t) return null;
    g.at = t.access_token; g.rt = t.refresh_token || g.rt; g.exp = Date.now() + (t.expires_in || 86400) * 1000; g.rexp = Date.now() + (t.refresh_token_expires_in || 7776000) * 1000; save();
    return g.at;
  }
  function readBig(r) {
    return new Promise(resolve => {
      let n = 0; const ch = [];
      r.on('data', c => { n += c.length; if (n <= 20e6) ch.push(c); });
      r.on('end', () => { try { resolve(JSON.parse(Buffer.concat(ch).toString('utf8'))); } catch (e) { resolve(null); } });
      r.on('error', () => resolve(null));
    });
  }
  function page(res, title, msg, ok) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end('<!doctype html><html lang="he" dir="rtl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>סט · Garmin</title></head>' +
      '<body style="margin:0;background:#0A0A0A;color:#fff;font:17px -apple-system,Arial;display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center;padding:24px;box-sizing:border-box">' +
      '<div><div style="font-size:56px">' + (ok ? '✅' : '⚠️') + '</div><h1 style="font-size:24px">' + title + '</h1><p style="color:#bbb;line-height:1.6">' + msg + '</p>' +
      '<a href="/?garmin=' + (ok ? 'ok' : 'err') + '#health" style="display:inline-block;margin-top:12px;background:#E8794A;color:#000;padding:12px 22px;border-radius:14px;text-decoration:none;font-weight:700">חזרה לסט</a></div></body></html>');
  }

  // שומר מכל סיכום רק מספרים (רמה אחת, וגם {value} מקונן), לפי תאריך
  const KEEP = 40;
  function store(type, list) {
    let n = 0;
    (Array.isArray(list) ? list : []).forEach(s => {
      const uid = uidOfG(s.userId); if (!uid) return;
      const day = s.calendarDate || (s.startTimeInSeconds ? new Date((s.startTimeInSeconds + (s.startTimeOffsetInSeconds || 0)) * 1000).toISOString().slice(0, 10) : null);
      if (!day) return;
      const box = db.gdata[uid] = db.gdata[uid] || {}, rec = box[day] = box[day] || {};
      if (type === 'acts') {   // אימונים שנרשמו בשעון (ריצה, הליכה, אופניים, כוח...)
        const a = { id: s.summaryId || s.activityId, n: s.activityName || s.activityType || '', type: s.activityType || '', dur: s.durationInSeconds || 0, kcal: s.activeKilocalories || 0, hr: s.averageHeartRateInBeatsPerMinute || 0, dist: s.distanceInMeters || 0, t: s.startTimeInSeconds || 0 };
        rec.acts = (rec.acts || []).filter(x => x.id !== a.id).concat([a]).slice(-12);
      } else Object.keys(s).forEach(k => {
        const v = s[k];
        if (typeof v === 'number') rec[type + '.' + k] = v;
        else if (v && typeof v === 'object' && typeof v.value === 'number') rec[type + '.' + k] = v.value;
        else if (v && typeof v === 'object' && !Array.isArray(v)) {   // מפה של ערכים לאורך היום (חמצן, נשימה...) → ממוצע
          const vals = Object.keys(v).map(x => v[x]).filter(x => typeof x === 'number');
          if (vals.length > 2) rec[type + '.' + k + '.avg'] = Math.round(vals.reduce((a, b) => a + b, 0) / vals.length * 10) / 10;
        }
      });
      if (type === 'stress' && s.timeOffsetBodyBatteryValues) {
        const vals = Object.keys(s.timeOffsetBodyBatteryValues).sort((a, b) => a - b).map(k => s.timeOffsetBodyBatteryValues[k]).filter(x => typeof x === 'number');
        if (vals.length) { rec['bb.max'] = Math.max.apply(null, vals); rec['bb.min'] = Math.min.apply(null, vals); rec['bb.last'] = vals[vals.length - 1]; }
      }
      rec.t = Date.now(); n++;
      const days = Object.keys(box).sort(); while (days.length > KEEP) delete box[days.shift()];
    });
    if (n) save();
    return n;
  }
  const PUSH_TYPES = { dailies: 'daily', sleeps: 'sleep', hrv: 'hrv', stressDetails: 'stress', userMetrics: 'metrics', bodyComps: 'body', pulseox: 'spo2', pulseOx: 'spo2', respiration: 'resp', allDayRespiration: 'resp', healthSnapshot: 'snap', skinTemp: 'skin', bloodPressures: 'bp', activities: 'acts', manuallyUpdatedActivities: 'acts' };

  return async function handle(req0, res, url) {
    const p = url.pathname;
    if (!p.startsWith('/api/garmin')) return false;

    // ---- Webhooks מגרמין (בלי עוגייה): מחזירים 200 מהר ----
    if (req0.method === 'POST' && p.startsWith('/api/garmin/push/')) {
      const b = await readBig(req0); send(res, 200, { ok: true });
      if (!b || typeof b !== 'object') return true;
      Object.keys(b).forEach(k => {
        if (PUSH_TYPES[k]) store(PUSH_TYPES[k], b[k]);
        else if (Array.isArray(b[k]) && b[k][0] && b[k][0].userId && !/deregistrations|userPermissionsChange/.test(k)) store(k.slice(0, 12), b[k]);   // סוג חדש: שומרים גם אותו
        else if (k === 'deregistrations') (b[k] || []).forEach(x => { const uid = uidOfG(x.userId); if (uid) { delete db.garmin[uid]; delete db.gdata[uid]; save(); } });
        else if (k === 'userPermissionsChange') (b[k] || []).forEach(x => { const uid = uidOfG(x.userId); if (uid) { db.garmin[uid].perms = x.permissions || []; save(); } });
      });
      return true;
    }

    // ---- חזרה מגרמין אחרי אישור ----
    if (req0.method === 'GET' && p === '/api/garmin/callback') {
      const st = String(url.searchParams.get('state') || ''), code = String(url.searchParams.get('code') || ''), x = db.gpk[st];
      if (!x || x.exp < Date.now() || !code) { page(res, 'החיבור לא הושלם', 'הקישור פג או בוטל. חזור לאפליקציה ונסה שוב.', false); return true; }
      delete db.gpk[st];
      const t = await tokenReq({ grant_type: 'authorization_code', code, code_verifier: x.ver, redirect_uri: REDIRECT });
      if (!t) { page(res, 'החיבור לא הושלם', 'גרמין לא אישרה את החיבור. נסה שוב בעוד רגע.', false); return true; }
      const idr = await req('GET', 'https://apis.garmin.com/wellness-api/rest/user/id', { headers: { Authorization: 'Bearer ' + t.access_token } });
      const gid = idr.j && idr.j.userId; if (!gid) console.log('[garmin] user id failed: ' + idr.code + ' ' + String(idr.raw || '').slice(0, 200)); if (!gid) { page(res, 'החיבור לא הושלם', 'לא הצלחנו לזהות את חשבון הגרמין.', false); return true; }
      const pr = await req('GET', 'https://apis.garmin.com/wellness-api/rest/user/permissions', { headers: { Authorization: 'Bearer ' + t.access_token } });
      Object.keys(db.garmin).forEach(u => { if (db.garmin[u].gid === gid && u !== x.uid) delete db.garmin[u]; });   // אותו גרמין עבר משתמש
      db.garmin[x.uid] = { gid, at: t.access_token, rt: t.refresh_token, exp: Date.now() + (t.expires_in || 86400) * 1000, rexp: Date.now() + (t.refresh_token_expires_in || 7776000) * 1000, perms: Array.isArray(pr.j) ? pr.j : [], t: Date.now() };
      save();
      page(res, 'Garmin מחובר ✓', 'הנתונים מהשעון (שינה, HRV, Body Battery, דופק מנוחה ועוד) יתחילו להגיע אחרי הסנכרון הבא של השעון עם Garmin Connect. אפשר לחזור לאפליקציה.', true);
      return true;
    }

    const me = userFor(req0); if (!me) { send(res, 401, { error: 'auth' }); return true; }

    if (req0.method === 'GET' && p === '/api/garmin/connect') {
      if (!on()) { send(res, 503, { error: 'החיבור לגרמין עוד לא הופעל בשרת' }); return true; }
      Object.keys(db.gpk).forEach(k => { if (db.gpk[k].exp < Date.now()) delete db.gpk[k]; });
      const ver = b64u(crypto.randomBytes(48)), state = b64u(crypto.randomBytes(16));
      db.gpk[state] = { uid: me.id, ver, exp: Date.now() + 15 * 60e3 }; save();
      const ch = b64u(crypto.createHash('sha256').update(ver).digest());
      const to = 'https://connect.garmin.com/oauth2Confirm?' + form({ response_type: 'code', client_id: CID, code_challenge: ch, code_challenge_method: 'S256', redirect_uri: REDIRECT, state });
      if (url.searchParams.get('json')) { send(res, 200, { url: to }); return true; }
      res.writeHead(302, { Location: to }); res.end(); return true;
    }
    if (req0.method === 'GET' && p === '/api/garmin/state') {
      const g = db.garmin[me.id];
      send(res, 200, { available: on(), connected: !!g, since: g ? g.t : 0, perms: g ? g.perms : [], days: g ? (db.gdata[me.id] || {}) : {} });
      return true;
    }
    if (req0.method === 'POST' && p === '/api/garmin/disconnect') {
      const at = await accessFor(me.id);
      if (at) await req('DELETE', 'https://apis.garmin.com/wellness-api/rest/user/registration', { headers: { Authorization: 'Bearer ' + at } });
      delete db.garmin[me.id]; delete db.gdata[me.id]; save();
      send(res, 200, { ok: true }); return true;
    }
    send(res, 404, { error: 'nf' }); return true;
  };
};
