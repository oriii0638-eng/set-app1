'use strict';
// סרטוני תרגילים של מאמנים: העלאה בזרם לדיסק, והורדה עם תמיכה ב-Range (נדרש ל-iOS).
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const MAX_FILE = 80 * 1024 * 1024, MAX_PER_COACH = 400 * 1024 * 1024;
const TYPES = { 'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm', 'video/x-m4v': 'mp4', 'video/3gpp': '3gp' };
const MIME = { mp4: 'video/mp4', mov: 'video/quicktime', webm: 'video/webm', '3gp': 'video/3gpp' };

module.exports = function (db, save, send, userFor, dataFile) {
  const DIR = path.join(path.dirname(dataFile), 'videos');
  fs.mkdirSync(DIR, { recursive: true });
  db.videos = db.videos || {};
  const fileOf = v => path.join(DIR, v.id + '.' + v.ext);
  const used = owner => Object.values(db.videos).filter(v => v.owner === owner).reduce((s, v) => s + v.size, 0);
  function remove(id) { const v = db.videos[id]; if (!v) return; try { fs.unlinkSync(fileOf(v)); } catch (e) {} delete db.videos[id]; }

  return async function handle(req, res, url) {
    if (!url.pathname.startsWith('/api/video')) return false;
    const me = userFor(req); if (!me) { send(res, 401, { error: 'login' }); return true; }

    if (req.method === 'POST' && url.pathname === '/api/video') {
      if (me.role !== 'coach') { send(res, 403, { error: 'forbidden' }); return true; }
      const name = String(url.searchParams.get('name') || '').slice(0, 60);
      const ext = TYPES[String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase()];
      const len = Number(req.headers['content-length'] || 0);
      if (!name || !ext) { send(res, 400, { error: 'סוג קובץ לא נתמך. השתמש בסרטון MP4 או MOV' }); return true; }
      if (len > MAX_FILE) { send(res, 413, { error: 'הסרטון גדול מדי (עד 80MB). קצר אותו או הקטן את האיכות' }); return true; }
      const old = Object.values(db.videos).filter(v => v.owner === me.id && v.name === name);
      const oldSize = old.reduce((s, v) => s + v.size, 0);
      if (used(me.id) - oldSize + len > MAX_PER_COACH) { send(res, 413, { error: 'אין מקום לעוד סרטונים. מחק סרטונים ישנים' }); return true; }
      const id = crypto.randomBytes(12).toString('hex'), v = { id, owner: me.id, name, ext, size: 0, t: Date.now() };
      const out = fs.createWriteStream(fileOf(v));
      let n = 0, dead = false;
      await new Promise(resolve => {
        const fail = () => { if (dead) return; dead = true; try { out.destroy(); fs.unlinkSync(fileOf(v)); } catch (e) {} resolve(); };
        req.on('data', c => { n += c.length; if (n > MAX_FILE) { fail(); req.destroy(); } });
        req.on('error', fail); req.on('aborted', fail);
        out.on('error', fail);
        out.on('finish', () => { if (!dead) resolve(); });
        req.pipe(out);
      });
      if (dead || n === 0) { send(res, 400, { error: 'ההעלאה נכשלה' }); return true; }
      v.size = n; db.videos[id] = v; old.forEach(o => remove(o.id)); save();
      send(res, 200, { id }); return true;
    }

    if (req.method === 'DELETE' && url.pathname === '/api/video') {
      const v = db.videos[url.searchParams.get('id')];
      if (!v || v.owner !== me.id) { send(res, 404, { error: 'nf' }); return true; }
      remove(v.id); save(); send(res, 200, { ok: true }); return true;
    }

    const m = /^\/api\/video\/([a-f0-9]{24})$/.exec(url.pathname);
    if (req.method === 'GET' && m) {
      const v = db.videos[m[1]]; if (!v) { send(res, 404, { error: 'nf' }); return true; }
      let st; try { st = fs.statSync(fileOf(v)); } catch (e) { send(res, 404, { error: 'nf' }); return true; }
      const h = { 'Content-Type': MIME[v.ext] || 'video/mp4', 'Accept-Ranges': 'bytes', 'Cache-Control': 'private, max-age=86400', 'X-Content-Type-Options': 'nosniff' };
      const r = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range || ''));
      let a = 0, b = st.size - 1, code = 200;
      if (r && (r[1] || r[2])) {
        if (r[1] === '') { a = Math.max(0, st.size - Number(r[2])); } else { a = Number(r[1]); if (r[2]) b = Math.min(b, Number(r[2])); }
        if (a > b || a >= st.size) { res.writeHead(416, { 'Content-Range': 'bytes */' + st.size }); res.end(); return true; }
        code = 206; h['Content-Range'] = 'bytes ' + a + '-' + b + '/' + st.size;
      }
      h['Content-Length'] = b - a + 1;
      res.writeHead(code, h);
      if (req.method === 'HEAD') { res.end(); return true; }
      fs.createReadStream(fileOf(v), { start: a, end: b }).pipe(res);
      return true;
    }
    send(res, 404, { error: 'nf' }); return true;
  };
};
