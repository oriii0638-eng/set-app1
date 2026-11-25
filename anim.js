'use strict';
// אנימציות תרגילים (Vital): הגשה למשתמשים מחוברים בלבד, עם Range (נדרש ל-iOS).
// מחפש קודם בדיסק הקבוע (<dir of DATA_FILE>/anim) ואז בתיקיית static/anim שבקוד.
const fs = require('fs'), path = require('path');
const MIME = { mp4: 'video/mp4', jpg: 'image/jpeg' };
module.exports = function (send, userFor, dataFile) {
  const DIRS = [path.join(path.dirname(dataFile), 'anim'), path.join(__dirname, 'static', 'anim')];
  const find = f => { for (const d of DIRS) { const p = path.join(d, f); try { if (fs.statSync(p).isFile()) return p; } catch (e) {} } return null; };
  return async function handle(req, res, url) {
    const m = /^\/api\/anim\/(\d{4})\.(mp4|jpg)$/.exec(url.pathname);
    if (!m) return false;
    if (req.method !== 'GET' && req.method !== 'HEAD') { send(res, 405, { error: 'method' }); return true; }
    if (!userFor(req)) { send(res, 401, { error: 'login' }); return true; }
    const p = find(m[1] + '.' + m[2]); if (!p) { send(res, 404, { error: 'nf' }); return true; }
    const st = fs.statSync(p);
    const h = { 'Content-Type': MIME[m[2]], 'Accept-Ranges': 'bytes', 'Cache-Control': 'private, max-age=604800', 'X-Content-Type-Options': 'nosniff' };
    const r = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range || ''));
    let a = 0, b = st.size - 1, code = 200;
    if (r && (r[1] || r[2])) {
      if (r[1] === '') a = Math.max(0, st.size - Number(r[2])); else { a = Number(r[1]); if (r[2]) b = Math.min(b, Number(r[2])); }
      if (a > b || a >= st.size) { res.writeHead(416, { 'Content-Range': 'bytes */' + st.size }); res.end(); return true; }
      code = 206; h['Content-Range'] = 'bytes ' + a + '-' + b + '/' + st.size;
    }
    h['Content-Length'] = b - a + 1;
    res.writeHead(code, h);
    if (req.method === 'HEAD') { res.end(); return true; }
    fs.createReadStream(p, { start: a, end: b }).pipe(res);
    return true;
  };
};
