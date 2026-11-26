/* מאגר המזון הלאומי של משרד הבריאות (data.gov.il, רישיון פתוח).
   השרת מוריד את הקבצים פעם בחודש, שומר עותק מקומי, ומגיש לאפליקציה גרסה מקוצרת:
   [שם, קלוריות, חלבון, פחמימה, שומן, [[יחידה, גרמים], ...]] ל-100 גרם. */
const fs = require('fs'), path = require('path'), zlib = require('zlib'), https = require('https');
const BASE = 'https://data.gov.il/dataset/d4f9c425-d657-4852-bd58-0cceb96a5f6d/resource/';
const SRC = {
  foods: BASE + 'c3cb0630-0650-46c1-a068-82d575c094b2/download/moh_mitzrachim.csv',
  units: BASE + '98fb46fe-e8de-4067-94d2-b0a8ea4269da/download/moh_yehidot_mida.csv',
  unitMap: BASE + '755d28c0-75f7-40e1-9c8c-ecdd106f9b2d/download/moh_yehidot_mida_lemitzrachim.csv'
};
const MONTH = 30 * 86400000;

function get(url, n) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15', Accept: 'text/csv,*/*' }, timeout: 60000 }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && (n || 0) < 4) { res.resume(); return resolve(get(new URL(res.headers.location, url).href, (n || 0) + 1)); }
      if (res.statusCode !== 200) { res.resume(); return reject(new Error('HTTP ' + res.statusCode)); }
      const ch = []; res.on('data', c => ch.push(c)); res.on('end', () => resolve(Buffer.concat(ch).toString('utf8')));
    }).on('error', reject).on('timeout', function () { this.destroy(new Error('timeout')); });
  });
}
function parseCSV(t) {
  const rows = []; let row = [], f = '', q = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i];
    if (q) { if (c === '"') { if (t[i + 1] === '"') { f += '"'; i++; } else q = false; } else f += c; }
    else if (c === '"') q = true;
    else if (c === ',') { row.push(f); f = ''; }
    else if (c === '\n') { row.push(f.replace(/\r$/, '')); rows.push(row); row = []; f = ''; }
    else f += c;
  }
  if (f || row.length) { row.push(f); rows.push(row); }
  return rows;
}
function build(foodsCsv, unitsCsv, mapCsv) {
  const R = parseCSV(foodsCsv), H = R[0], ix = n => H.indexOf(n);
  if (ix('shmmitzrach') < 0 || ix('food_energy') < 0) throw new Error('unexpected columns');
  const UN = {}; parseCSV(unitsCsv).slice(1).forEach(r => { if (r[0]) UN[r[0]] = String(r[1] || '').replace(/\s+/g, ' ').trim(); });
  const units = {};
  parseCSV(mapCsv).slice(1).forEach(r => {
    if (!r[0] || r[1] === '700' || r[1] === '2000') return;
    const g = parseFloat(r[2]); if (!(g > 0 && g < 3000)) return;
    (units[r[0]] = units[r[0]] || []).push([UN[r[1]] || r[1], Math.round(g)]);
  });
  const num = v => { const x = parseFloat(v); return isFinite(x) ? Math.round(x * 10) / 10 : 0; };
  const out = [], seen = new Set();
  for (const r of R.slice(1)) {
    if (r.length < 11) continue;
    const nm = String(r[ix('shmmitzrach')] || '').replace(/\s+/g, ' ').trim();
    if (!nm || seen.has(nm) || /חלב אם|תמ"ל|תרכובת מזון לתינוקות/.test(nm)) continue;
    seen.add(nm);
    out.push([nm, num(r[ix('food_energy')]), num(r[ix('protein')]), num(r[ix('carbohydrates')]), num(r[ix('total_fat')]), (units[r[ix('Code')]] || []).slice(0, 4)]);
  }
  return out;
}

module.exports = function (dataDir, send) {
  const FILE = path.join(dataDir, 'fooddb.json');
  let cache = null; // { t, items, json, gz }
  function setCache(t, items) {
    const json = JSON.stringify({ v: t, src: 'מאגר התזונה הלאומי, משרד הבריאות (data.gov.il)', items });
    cache = { t, items, json, gz: zlib.gzipSync(json) };
  }
  try { const d = JSON.parse(fs.readFileSync(FILE, 'utf8')); if (Array.isArray(d.items) && d.items.length) setCache(d.t, d.items); } catch (e) {}
  let busy = false;
  async function refresh(force) {
    if (busy || (!force && cache && Date.now() - cache.t < MONTH)) return;
    busy = true;
    try {
      const [a, b, c] = await Promise.all([get(SRC.foods), get(SRC.units), get(SRC.unitMap)]);
      const items = build(a, b, c);
      if (items.length < 500) throw new Error('too few items: ' + items.length);
      const t = Date.now();
      fs.writeFileSync(FILE, JSON.stringify({ t, items }));
      setCache(t, items);
      console.log('[fooddb] loaded ' + items.length + ' foods');
    } catch (e) { console.log('[fooddb] refresh failed: ' + e.message + (cache ? ' (keeping ' + cache.items.length + ' cached)' : '')); }
    busy = false;
  }
  setTimeout(() => refresh(false), 8000);
  setInterval(() => refresh(false), 24 * 3600000).unref();

  function handle(req, res, url) {
    if (url.pathname !== '/api/fooddb') return false;
    if (!cache) { send(res, 503, { error: 'המאגר נטען, נסה שוב בעוד דקה' }); refresh(false); return true; }
    const etag = '"f' + cache.t + '"';
    if (req.headers['if-none-match'] === etag) { res.writeHead(304, { ETag: etag }); res.end(); return true; }
    const gz = /\bgzip\b/.test(req.headers['accept-encoding'] || '');
    res.writeHead(200, Object.assign({ 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'private, max-age=86400', ETag: etag, Vary: 'Accept-Encoding' }, gz ? { 'Content-Encoding': 'gzip' } : {}));
    res.end(gz ? cache.gz : cache.json);
    return true;
  }
  handle.refresh = refresh;
  handle.build = build;
  return handle;
};
module.exports.build = build;
