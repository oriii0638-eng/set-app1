/* דמות תלת-ממד בגוף מלא לפרופיל.
   גוף, פנים ושיער: Universal Base Characters של Quaternius (רישיון CC0, נחלת הכלל).
   בגדי ספורט נצבעים על הגוף בשיידר לפי השלד, וכובעים/משקפיים/תכשיטים נבנים בקוד ומוצמדים לראש.
   mount(el, cfg, opt) → {set(cfg), focus('body'|'head'|'mid'), emote(), snap(), dispose()} */
import * as THREE from '/vendor/three.module.min.js';
import { GLTFLoader } from '/vendor/GLTFLoader.js';
import { MeshoptDecoder } from '/vendor/meshopt_decoder.module.js';
import { clone as skClone } from '/vendor/SkeletonUtils.js';

const PAL = {
  sk: ['#FFDBC4', '#F3C9A5', '#E0AC69', '#C68642', '#8D5524', '#5C3A21'],
  hc: ['#1B1B1B', '#4A2E1F', '#7A4A2A', '#B87333', '#D9B26F', '#E9E4DA', '#C0392B', '#3A6FD8'],
  sc: ['#E8794A', '#232323', '#F2F2F2', '#2F6BDB', '#2E9E5B', '#C0392B', '#7B4FD1', '#F2C94C'],
  pc: ['#232323', '#3B4B6B', '#6B6B6B', '#F2F2F2', '#5A4632', '#2F6BDB', '#C0392B', '#2E9E5B'],
  so: ['#F2F2F2', '#1E1E1E', '#E8794A', '#2F6BDB', '#C0392B', '#F2C94C']
};
const DEF = { bt: 0, sk: 1, hs: 2, hc: 1, ey: 0, br: 0, mo: 0, fh: 0, sh: 0, sc: 0, pn: 0, pc: 0, so: 0, soc: 0, hat: 0, gl: 0, acc: 0, bg: 0 };
export function cfgOf(c) { const o = {}; for (const k in DEF) o[k] = c && c[k] != null ? c[k] : DEF[k]; return o; }
/* תסרוקות לפי הסדר בעורך */
export const HAIR = [null, 'Hair_Buzzed', 'Hair_SimpleParted', 'Hair_Long', 'Hair_Buns', 'Hair_BuzzedFemale'];
const isF = c => c.bt === 1 || c.bt >= 3;

/* ---------- טעינת מודלים (פעם אחת לכל הדף) ---------- */
const loader = new GLTFLoader(); loader.setMeshoptDecoder(MeshoptDecoder);
const CACHE = {};
function load(name) { return CACHE[name] || (CACHE[name] = loader.loadAsync('/av/' + name + '.glb').catch(e => { delete CACHE[name]; throw e; })); }
export function preload(c) { c = cfgOf(c); const L = [load(isF(c) ? 'body_Female' : 'body_Male')]; const h = HAIR[c.hs % HAIR.length]; if (h) L.push(load(h)); if (c.fh && !isF(c)) L.push(load('Hair_Beard')); return Promise.all(L); }

const lin = hex => new THREE.Color(hex);
const SKIN_BASE = new THREE.Color().setRGB(167 / 255, 116 / 255, 81 / 255, THREE.SRGBColorSpace);

/* שיידר הבגדים: לפי מיקום הנקודה בתנוחת המנוחה (T) ולפי נקודות השלד */
function clothe(mat, U) {
  mat.onBeforeCompile = sh => {
    Object.assign(sh.uniforms, U);
    sh.vertexShader = sh.vertexShader.replace('#include <common>', '#include <common>\nvarying vec3 vRest;\nuniform mat4 uRestM;').replace('#include <begin_vertex>', '#include <begin_vertex>\nvRest = (uRestM * vec4(position, 1.0)).xyz;');
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', `#include <common>
varying vec3 vRest;
uniform vec3 uSkin, uTopC, uPantC, uShoeC; uniform float uTop, uPant, uShoe, uFem;
uniform vec4 uY; uniform vec4 uX; uniform float uAnk;
float lum(vec3 c){return dot(c,vec3(.299,.587,.114));}`)
      .replace('#include <map_fragment>', `#include <map_fragment>
{
  vec3 p = vRest; float ax = abs(p.x);
  float pel = uY.x, chest = uY.y, neck = uY.z, knee = uY.w, shX = uX.x, wrX = uX.z;
  float L = lum(diffuseColor.rgb);
  float shade = clamp(L / 0.27, 0.55, 1.25);
  vec3 col = diffuseColor.rgb * uSkin;
  if (L < 0.09) col = vec3(0.62, 0.33, 0.2) * uSkin * 0.8;
  float edge = 1.0;
  bool arm = ax > shX - 0.01 && p.y > chest + 0.02;
  float pb = uPant < 0.5 ? knee + 0.17 : uPant < 1.5 ? knee + 0.0 : uAnk + 0.05;
  float ptop = pel + (uFem > 0.5 ? 0.11 : 0.075);
  bool pant = !arm && p.y < ptop && p.y > pb;
  if (pant) { col = uPantC * mix(1.0, shade, 0.55); if (p.y < pb + 0.012 || p.y > ptop - 0.012) edge = 0.78; if (uPant > 2.5 && abs(ax - 0.11) < 0.004 && p.y < pel) edge = 0.85; }
  float hem = pel + 0.035;
  bool torso = !arm && p.y > hem && p.y < neck + (ax > 0.075 ? 0.03 : -0.02);
  float scoop = (uTop > 4.5) ? 0.0 : 0.035;
  if (torso && p.z > 0.0 && ax < 0.06) torso = p.y < neck - 0.03 - scoop * (1.0 - ax / 0.06);
  if (uTop > 0.5 && uTop < 1.5 && torso) { vec2 d = vec2((ax - shX + 0.02) / 0.075, (p.y - chest - 0.16) / 0.15); if (dot(d, d) < 1.0) torso = false; }
  if (uTop > 3.5 && uTop < 4.5) torso = torso && p.y > chest - (uFem > 0.5 ? 0.07 : 0.02);
  float sl = uTop < 0.5 || (uTop > 2.5 && uTop < 3.5) ? shX + 0.13 : (uTop > 1.5 && uTop < 2.5) || uTop > 4.5 ? wrX - 0.025 : -1.0;
  bool sleeve = arm && ax < sl;
  float cs = mix(1.0, shade, 0.5);
  if (torso || sleeve) { col = uTopC * cs; if ((torso && p.y < hem + 0.012) || (sleeve && ax > sl - 0.012)) edge = 0.8; if (uTop > 2.5 && uTop < 3.5 && (sleeve && ax > sl - 0.03)) col = mix(col, vec3(1.0), 0.8); }
  if (p.y < uAnk + 0.035) { col = uShoeC * (0.75 + 0.35 * shade); if (p.y < 0.022) col = uShoe > 2.5 ? vec3(0.95, 0.75, 0.2) : uShoe > 1.5 ? vec3(0.95, 0.4, 0.2) : uShoe > 0.5 ? vec3(0.04) : vec3(0.93); else if (p.y > uAnk + 0.022) edge = 0.82; }
  diffuseColor.rgb = col * edge;
}`)
      .replace('#include <roughnessmap_fragment>', '#include <roughnessmap_fragment>\n{ vec3 p=vRest; if (p.y > uY.x + 0.035 && p.y < uY.z) roughnessFactor = max(roughnessFactor, 0.7); }');
  };
  mat.customProgramCacheKey = () => 'set-clothes';
}
/* צבע שיער: גוון הטקסטורה המקורית (אפור) → הצבע שנבחר */
function tint(mat, U) {
  mat.onBeforeCompile = sh => { sh.uniforms.uHair = U; sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform vec3 uHair;').replace('#include <map_fragment>', '#include <map_fragment>\n diffuseColor.rgb = uHair * (dot(diffuseColor.rgb, vec3(.333)) / 0.26);'); };
  mat.customProgramCacheKey = () => 'set-hair';
}

const M = (c, r = .65, extra) => new THREE.MeshStandardMaterial(Object.assign({ color: c, roughness: r, metalness: 0 }, extra || {}));
const shade = (hex, f) => new THREE.Color(hex).multiplyScalar(f);
const sph = (r, mat, w = 20, h = 14) => new THREE.Mesh(new THREE.SphereGeometry(r, w, h), mat);

/* פריטים מהחנות. הקואורדינטות יחסיות למרכז הראש (y = גובה העיניים) */
function addHead(head, c, R) {
  const SX = .92, SY = 1.1, SZ = 1.02;
  const surf = (x, y) => { const zx = x / (R * SX), zy = y / (R * SY); return R * SZ * Math.sqrt(Math.max(0.02, 1 - zx * zx - zy * zy)); };
  const gold = M('#E8C14A', .3, { metalness: .8 }), hatC = PAL.sc[c.sc];
  if (c.hat === 1) { const m = M(hatC, .7); const cr = new THREE.Mesh(new THREE.SphereGeometry(R * 1.24, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2), m); cr.scale.set(SX, SY * .95, SZ); cr.position.y = .035; cr.rotation.x = -.15; head.add(cr); const br = new THREE.Mesh(new THREE.CylinderGeometry(R * .78, R * .78, .007, 24, 1, false, -Math.PI / 2, Math.PI), M(shade(hatC, .78), .7)); br.position.set(0, .045, R * .98); br.rotation.x = .12; head.add(br); }
  if (c.hat === 2) { const cr = new THREE.Mesh(new THREE.SphereGeometry(R * 1.24, 32, 16, 0, Math.PI * 2, 0, Math.PI / 1.85), M('#2F6BDB', .9)); cr.scale.set(SX, SY * 1.05, SZ); cr.position.y = .02; head.add(cr); const cu = new THREE.Mesh(new THREE.TorusGeometry(R * 1.14, .016, 10, 32), M('#2558B8', .9)); cu.rotation.x = Math.PI / 2; cu.scale.set(SX, SZ, 1); cu.position.y = .04; head.add(cu); const p = sph(.028, M('#F2F2F2', .95)); p.position.y = R * 1.4; head.add(p); }
  if (c.hat === 3) { const t = new THREE.Mesh(new THREE.TorusGeometry(R * 1.06, .013, 8, 32), M('#C0392B', .8)); t.rotation.x = Math.PI / 2 - .12; t.scale.set(SX, SZ, 1); t.position.y = .06; head.add(t); }
  if (c.hat === 4) { const br = new THREE.Mesh(new THREE.CylinderGeometry(R * 1.9, R * 1.9, .01, 32), M('#8B5A2B', .8)); br.position.y = R * .8; br.scale.z = .85; head.add(br); const cr = new THREE.Mesh(new THREE.CylinderGeometry(R * .75, R * 1.0, R * 1.0, 24), M('#A0693A', .8)); cr.position.y = R * 1.3; head.add(cr); const bd = new THREE.Mesh(new THREE.CylinderGeometry(R * 1.01, R * 1.02, .018, 24), M('#5C3A1E', .8)); bd.position.y = R * .92; head.add(bd); }
  if (c.hat === 5) { const g = M('#F2C94C', .3, { metalness: .85 }); const ring = new THREE.Mesh(new THREE.CylinderGeometry(R * .75, R * .75, .035, 24, 1, true), g); ring.material.side = THREE.DoubleSide; ring.position.y = R * 1.25; head.add(ring); for (let i = 0; i < 6; i++) { const a = i / 6 * Math.PI * 2, s = new THREE.Mesh(new THREE.ConeGeometry(.014, .045, 6), g); s.position.set(Math.sin(a) * R * .75, R * 1.25 + .035, Math.cos(a) * R * .75); head.add(s); const j = sph(.008, M(['#C0392B', '#2F6BDB', '#2E9E5B'][i % 3], .2)); j.position.set(Math.sin(a) * R * .77, R * 1.25, Math.cos(a) * R * .77); head.add(j); } }
  if (c.hat === 6) { const cr = new THREE.Mesh(new THREE.SphereGeometry(R * 1.24, 32, 16, 0, Math.PI * 2, 0, Math.PI / 2.2), M('#C0392B', .85)); cr.scale.set(SX, SY * .95, SZ); cr.position.y = .03; cr.rotation.x = -.2; head.add(cr); const k = new THREE.Mesh(new THREE.ConeGeometry(.022, .06, 8), M('#C0392B', .85)); k.position.set(.02, .05, -R * 1.05); k.rotation.x = -2.2; head.add(k); }
  if (c.gl) {
    const fr = c.gl === 2 ? M('#111', .3) : M('#222', .4), gy = 0;
    [-1, 1].forEach(s => {
      const x = s * R * .36, z = surf(x, gy) + .006;
      if (c.gl === 1) { const r = new THREE.Mesh(new THREE.TorusGeometry(R * .2, .003, 8, 20), fr); r.position.set(x, gy, z); head.add(r); }
      if (c.gl === 2) { const l = new THREE.Mesh(new THREE.CircleGeometry(R * .23, 20), M('#0b0b0b', .15, { metalness: .4 })); l.scale.y = .75; l.position.set(x, gy, z); head.add(l); }
      if (c.gl === 3) { const l = new THREE.Mesh(new THREE.TorusGeometry(R * .21, .0035, 4, 4), fr); l.rotation.z = Math.PI / 4; l.scale.y = .8; l.position.set(x, gy, z); head.add(l); }
      const arm = new THREE.Mesh(new THREE.BoxGeometry(.003, .003, R * .7), fr); arm.position.set(s * R * SX * .9, gy + .003, z - R * .42); head.add(arm);
    });
    const brg = new THREE.Mesh(new THREE.BoxGeometry(R * .18, .003, .003), fr); brg.position.set(0, gy + .004, surf(0, gy) + .009); head.add(brg);
  }
  if (c.acc === 2) { const band = new THREE.Mesh(new THREE.TorusGeometry(R * 1.12, .01, 8, 32, Math.PI), M('#1E1E1E', .5)); band.scale.set(SX * 1.04, SY * 1.05, 1); band.position.y = .01; head.add(band); [-1, 1].forEach(s => { const cup = new THREE.Mesh(new THREE.CylinderGeometry(R * .32, R * .32, .026, 20), M('#E8794A', .5)); cup.rotation.z = Math.PI / 2; cup.position.set(s * R * SX * 1.06, -.01, -.01); head.add(cup); }); }
  if (c.acc === 4) { const e = sph(.006, gold); e.position.set(-R * SX * .98, -R * .35, -.01); head.add(e); }
}
function addChest(chest, c, B) {
  const gold = M('#E8C14A', .3, { metalness: .8 });
  if (c.acc === 1) { const ch = new THREE.Mesh(new THREE.TorusGeometry(B.nr, .005, 8, 32), gold); ch.rotation.x = Math.PI / 2 - .55; ch.position.set(0, B.ny, B.nz); chest.add(ch); const p = sph(.012, gold); p.position.set(0, B.ny - B.nr * .9, B.nz + B.nr * .75); chest.add(p); }
  if (c.acc === 3) { const rb = new THREE.Mesh(new THREE.TorusGeometry(B.nr * 1.05, .009, 6, 24, Math.PI * .9), M('#2F6BDB', .6)); rb.rotation.set(Math.PI / 2 - .25, 0, Math.PI * 1.05); rb.position.set(0, B.ny, B.nz); chest.add(rb); const md = new THREE.Mesh(new THREE.CylinderGeometry(.026, .026, .007, 24), M('#F2C94C', .25, { metalness: .9 })); md.rotation.x = Math.PI / 2; md.position.set(0, B.ny - B.nr * 1.6, B.nz + B.nr * 1.3); chest.add(md); }
}

/* מחבר שיער/זקן (שנבנו לאותו שלד) לשלד של הגוף */
function rebind(mesh, bones) {
  const sk = mesh.skeleton; const nb = sk.bones.map(b => bones[b.name] || b);
  mesh.bind(new THREE.Skeleton(nb, sk.boneInverses), mesh.bindMatrix);
}
const shapeKey = c => [isF(c), c.hs % HAIR.length, !!(c.fh && !isF(c)), c.hat, c.gl, c.acc, c.sc].join();

/* בונה את הדמות. מחזיר עצמות לאנימציה ופונקציה לעדכון צבעים בלי לבנות מחדש */
async function build(c) {
  const F = isF(c);
  const [g] = await Promise.all([load(F ? 'body_Female' : 'body_Male'), preload(c)]);
  const root = skClone(g.scene);
  const bones = {}; root.traverse(o => { if (o.isBone) bones[o.name] = o; });
  root.updateMatrixWorld(true);
  const wp = n => { const v = new THREE.Vector3(); bones[n].getWorldPosition(v); return v; };
  const U = {
    uSkin: { value: new THREE.Vector3() }, uTopC: { value: new THREE.Color() }, uPantC: { value: new THREE.Color() }, uShoeC: { value: new THREE.Color() },
    uTop: { value: 0 }, uPant: { value: 0 }, uShoe: { value: 0 }, uFem: { value: F ? 1 : 0 },
    uY: { value: new THREE.Vector4(wp('pelvis').y, wp('spine_03').y, wp('neck_01').y, wp('calf_l').y) },
    uX: { value: new THREE.Vector4(wp('upperarm_l').x, wp('lowerarm_l').x, wp('hand_l').x, 0) },
    uAnk: { value: wp('foot_l').y }
  };
  const HU = { value: new THREE.Color() };
  let eyes = null;
  root.traverse(o => {
    if (!o.isMesh) return; o.frustumCulled = false;
    o.material = o.material.clone();
    if (/Superhero|SuperHero/.test(o.name)) { U.uRestM = { value: o.matrixWorld.clone().multiply(o.bindMatrix ? new THREE.Matrix4() : new THREE.Matrix4()) }; clothe(o.material, U); }
    else if (/Eyebrows/.test(o.name)) tint(o.material, HU);
    else if (/Eyes|Face\.001/.test(o.name)) eyes = o;
  });
  /* מרכז הראש לפי העיניים */
  const eb = eyes ? new THREE.Box3().setFromObject(eyes, true) : null;
  const ec = eb ? eb.getCenter(new THREE.Vector3()) : wp('Head').add(new THREE.Vector3(0, .1, .07));
  const R = F ? .093 : .1;
  const hc = new THREE.Vector3(0, ec.y, ec.z - R * .78);
  const attach = (boneName, worldPos) => { const b = bones[boneName], grp = new THREE.Group(); b.add(grp); grp.position.copy(b.worldToLocal(worldPos.clone())); const q = new THREE.Quaternion(); b.getWorldQuaternion(q); grp.quaternion.copy(q.invert()); return grp; };
  const add = async n => { const h = await load(n); const s = skClone(h.scene); const meshes = []; s.traverse(o => { if (o.isSkinnedMesh) meshes.push(o); }); meshes.forEach(m => { m.material = m.material.clone(); tint(m.material, HU); m.frustumCulled = false; rebind(m, bones); root.add(m); }); };
  const hn = HAIR[c.hs % HAIR.length]; if (hn) await add(hn);
  if (c.fh && !F) await add('Hair_Beard');
  const head = attach('Head', hc); addHead(head, c, R);
  const chest = attach('spine_03', new THREE.Vector3(0, 0, 0));
  addChest(chest, c, { ny: wp('neck_01').y - .035, nz: .01, nr: F ? .065 : .075 });
  function colors(c2) {
    const s = lin(PAL.sk[c2.sk] || PAL.sk[1]); U.uSkin.value.set(s.r / SKIN_BASE.r, s.g / SKIN_BASE.g, s.b / SKIN_BASE.b);
    U.uTopC.value.copy(lin(PAL.sc[c2.sc] || PAL.sc[0])); U.uPantC.value.copy(lin(PAL.pc[c2.pc] || PAL.pc[0])); U.uShoeC.value.copy(lin(PAL.so[c2.soc] || PAL.so[0]));
    U.uTop.value = c2.sh; U.uPant.value = c2.pn; U.uShoe.value = c2.so; HU.value.copy(lin(PAL.hc[c2.hc] || PAL.hc[1]));
  }
  colors(c);
  const rest = {}; for (const k in bones) rest[k] = bones[k].quaternion.clone();
  return { root, bones, rest, colors, F, key: shapeKey(c) };
}

/* סיבוב עצם סביב ציר בעולם */
const _q = new THREE.Quaternion(), _p = new THREE.Quaternion();
function rotW(b, axis, a) { if (!b || !a) return; b.parent.getWorldQuaternion(_p); _q.setFromAxisAngle(axis, a); const l = _p.clone().invert().multiply(_q).multiply(_p); b.quaternion.premultiply(l); b.updateMatrixWorld(true); }
const AX = new THREE.Vector3(1, 0, 0), AY = new THREE.Vector3(0, 1, 0), AZ = new THREE.Vector3(0, 0, 1);

const VIEW = { body: { y: .92, d: 4.6 }, head: { y: 1.62, d: 1.5 }, mid: { y: 1.3, d: 2.4 } };

export function mount(el, cfg, opt) {
  opt = opt || {};
  let renderer;
  try { renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true, preserveDrawingBuffer: !!opt.snap }); } catch (e) { return null; }
  renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
  renderer.outputColorSpace = THREE.SRGBColorSpace; renderer.toneMapping = THREE.ACESFilmicToneMapping; renderer.toneMappingExposure = 1.0;
  el.appendChild(renderer.domElement); renderer.domElement.style.cssText = 'width:100%;height:100%;display:block;touch-action:pan-y';
  const scene = new THREE.Scene();
  scene.add(new THREE.HemisphereLight(0xffffff, 0x4a3a30, 1.3));
  const key = new THREE.DirectionalLight(0xffffff, 2.4); key.position.set(1.6, 3, 2.4); scene.add(key);
  const rim = new THREE.DirectionalLight(0xffb48a, 1.4); rim.position.set(-2, 2, -2.5); scene.add(rim);
  const fill = new THREE.DirectionalLight(0x9ab8ff, .5); fill.position.set(-2, 1, 2); scene.add(fill);
  { const cv = document.createElement('canvas'); cv.width = cv.height = 128; const g = cv.getContext('2d'); const gr = g.createRadialGradient(64, 64, 4, 64, 64, 64); gr.addColorStop(0, 'rgba(0,0,0,.5)'); gr.addColorStop(1, 'rgba(0,0,0,0)'); g.fillStyle = gr; g.fillRect(0, 0, 128, 128); const m = new THREE.Mesh(new THREE.PlaneGeometry(1.1, .7), new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(cv), transparent: true, depthWrite: false })); m.rotation.x = -Math.PI / 2; m.position.y = .003; scene.add(m); }
  const cam = new THREE.PerspectiveCamera(30, 1, .05, 50);
  let view = VIEW[opt.view || 'body'], cy = view.y, cd = view.d;
  const holder = new THREE.Group(); scene.add(holder);
  let A = null, C = cfgOf(cfg), alive = true, seq = 0;
  function dispose3(o) { o.traverse(x => { if (x.material && !x.isSkinnedMesh) x.material.dispose?.(); if (x.geometry && !x.isSkinnedMesh) x.geometry.dispose(); }); }
  async function rebuild() {
    const my = ++seq; const nb = await build(C); if (!alive || my !== seq) return;
    if (A) { holder.remove(A.root); dispose3(A.root); }
    A = nb; nb.colors(C); holder.add(A.root); if (opt.onReady) opt.onReady();
  }
  const ready = rebuild();

  let rot = opt.rot != null ? opt.rot : -.35, vel = 0, drag = null, lastTouch = 0;
  const cv = renderer.domElement;
  const pd = e => { drag = { x: e.clientX, r: rot, t: Date.now(), moved: false }; };
  const pm = e => { if (!drag) return; const dx = e.clientX - drag.x; if (Math.abs(dx) > 6) drag.moved = true; if (drag.moved) { const nr = drag.r + dx * .012; vel = nr - rot; rot = nr; lastTouch = Date.now(); } };
  const pu = () => { if (drag && !drag.moved && Date.now() - drag.t < 350) emote(); drag = null; };
  cv.addEventListener('pointerdown', pd); window.addEventListener('pointermove', pm); window.addEventListener('pointerup', pu);

  let em = null;
  function emote(k) { em = { k: k || ['flex', 'wave', 'jump', 'squat'][Math.floor(Math.random() * 4)], t: 0 }; }
  const clock = new THREE.Clock(); let t = 0, raf = 0, visible = true;
  function size() { const w = el.clientWidth || 1, h = el.clientHeight || 1; renderer.setSize(w, h, false); cam.aspect = w / h; cam.updateProjectionMatrix(); }
  const ro = window.ResizeObserver ? new ResizeObserver(size) : null; if (ro) ro.observe(el); size();
  const io = window.IntersectionObserver ? new IntersectionObserver(es => { visible = es[0].isIntersecting; if (visible && !raf) loop(); }) : null; if (io) io.observe(el);

  function pose(dt) {
    const B = A.bones; for (const k in A.rest) B[k].quaternion.copy(A.rest[k]);
    A.root.position.y = 0; A.root.updateMatrixWorld(true);
    const br = Math.sin(t * 2.0);
    let armL = -1.22, armR = 1.22, fwd = .08, th = 0, kn = 0, sp = 0, hy = Math.sin(t * .45) * .14, wave = 0, flex = 0;
    if (em) {
      em.t += dt; const p = em.t, e = Math.sin(Math.min(1, p / 1.6) * Math.PI);
      if (em.k === 'flex') flex = e;
      if (em.k === 'wave') wave = e;
      if (em.k === 'jump') { const j = p < 1 ? Math.max(0, Math.sin(p * Math.PI)) : 0; A.root.position.y = j * .3; th = -j * .5; kn = j * .9; armL = -1.22 + j * 2.6; armR = 1.22 - j * 2.6; }
      if (em.k === 'squat') { A.root.position.y = -e * .32; th = -e * 1.3; kn = e * 2.0; sp = e * .35; fwd = .08 + e * 1.3; }
      if (p > 1.6) em = null;
    }
    A.root.updateMatrixWorld(true);
    rotW(B.spine_01, AX, sp); rotW(B.spine_03, AX, br * .012);
    rotW(B.Head, AY, hy);
    rotW(B.upperarm_l, AZ, armL * (1 - flex)); rotW(B.upperarm_r, AZ, armR * (1 - flex) - wave * 2.9);
    rotW(B.upperarm_l, AX, -fwd * (1 - flex)); rotW(B.upperarm_r, AX, -fwd * (1 - flex) * (1 - wave));
    if (flex) { rotW(B.lowerarm_l, AZ, flex * 1.9); rotW(B.lowerarm_r, AZ, -flex * 1.9); }
    else { rotW(B.lowerarm_l, AX, -.22); if (!wave) rotW(B.lowerarm_r, AX, -.22); }
    if (wave) rotW(B.lowerarm_r, AZ, wave * (Math.sin(t * 12) * .45 - .3));
    rotW(B.thigh_l, AX, th); rotW(B.thigh_r, AX, th); rotW(B.calf_l, AX, kn); rotW(B.calf_r, AX, kn);
    if (kn) { rotW(B.foot_l, AX, -kn * .45); rotW(B.foot_r, AX, -kn * .45); }
  }
  function loop() {
    raf = 0; if (!alive) return;
    const dt = Math.min(.05, clock.getDelta()); t += dt;
    if (!drag) { rot += vel; vel *= .92; if (Date.now() - lastTouch > 2500 && !opt.still) rot += (Math.sin(t * .25) * .5 - .35 - rot) * .01; }
    holder.rotation.y = rot;
    cy += (view.y - cy) * .12; cd += (view.d - cd) * .12;
    cam.position.set(0, cy + .05, cd); cam.lookAt(0, cy, 0);
    if (A) pose(dt);
    renderer.render(scene, cam);
    if (visible && !document.hidden) raf = requestAnimationFrame(loop);
  }
  const vis = () => { if (!document.hidden && visible && !raf && alive) { clock.getDelta(); loop(); } };
  document.addEventListener('visibilitychange', vis);
  loop();
  return {
    ready,
    set(c) { C = cfgOf(c); if (A && shapeKey(C) === A.key) A.colors(C); else rebuild(); },
    focus(v) { view = VIEW[v] || VIEW.body; },
    emote,
    snap() { renderer.render(scene, cam); return renderer.domElement.toDataURL('image/png'); },
    dispose() { alive = false; if (raf) cancelAnimationFrame(raf); if (ro) ro.disconnect(); if (io) io.disconnect(); window.removeEventListener('pointermove', pm); window.removeEventListener('pointerup', pu); document.removeEventListener('visibilitychange', vis); if (A) dispose3(A.root); renderer.dispose(); renderer.domElement.remove(); }
  };
}
