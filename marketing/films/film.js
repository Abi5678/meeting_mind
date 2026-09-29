// Quolio — launch films.
// Every frame is drawn procedurally on a 1920×1080 canvas in a torn-paper,
// stop-motion style. render(ctx, filmId, t, W, H) is deterministic, so the
// same code drives the live player and the frame-by-frame MP4 export.
(function () {
  "use strict";

  const VW = 1920, VH = 1080;

  // Brand palette (NoteStyle Studio tokens, converted to hex)
  const C = {
    navy: "#1d2748", navy2: "#26325a", navy3: "#33416f", navyDeep: "#141a33",
    cream: "#faf6f0", paper2: "#f2e9da", manila: "#dcc79d", manilaDark: "#c4ad80",
    ink: "#1e2433", inkSoft: "#5b6275", red: "#dd5a44", rule: "#bcd0e6",
    yellow: "#fff27a", pink: "#f4a0b8", mint: "#a8dcae", star: "#ffe08a",
    window: "#ffd780", sky: "#bfd9ec", mustard: "#e3b23c", blue: "#4f6fb0",
    plum: "#6b4e7a", green: "#6ea77a", brand: "#4a64dc", brandDeep: "#2f45a8",
  };
  const SKIN = ["#f0c6a2", "#c98e68", "#8d5a3f", "#e7b28c"];

  // ---------- math ----------
  function rng(seed) {
    let a = (seed * 2654435761) >>> 0;
    return function () {
      a = (a + 0x6d2b79f5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  const clamp = (v, a = 0, b = 1) => Math.max(a, Math.min(b, v));
  const lerp = (a, b, p) => a + (b - a) * p;
  const seg = (t, a, b) => clamp((t - a) / (b - a));
  const easeOut = (p) => 1 - Math.pow(1 - p, 3);
  const easeInOut = (p) => (p < 0.5 ? 4 * p * p * p : 1 - Math.pow(-2 * p + 2, 3) / 2);
  const backOut = (p) => { const c = 1.9; return 1 + (c + 1) * Math.pow(p - 1, 3) + c * Math.pow(p - 1, 2); };
  function bez(p0, p1, p2, p) {
    const q = 1 - p;
    return [q * q * p0[0] + 2 * q * p * p1[0] + p * p * p2[0], q * q * p0[1] + 2 * q * p * p1[1] + p * p * p2[1]];
  }

  // Stop-motion "boil": torn edges re-cut 6× a second, cycling 3 variants.
  let BOIL = 0;
  // Vertical (9:16) mode: scenes are framed by a moving camera; captions are
  // collected during the scene draw and set afterwards in screen space.
  let VERT = false, CAPS = null;

  // ---------- paper primitives ----------
  let grain = null;
  function grainPattern(ctx) {
    if (grain) return grain;
    const g = document.createElement("canvas");
    g.width = g.height = 220;
    const x = g.getContext("2d");
    const r = rng(7);
    for (let i = 0; i < 5200; i++) {
      const v = r() < 0.5 ? 0 : 255;
      x.fillStyle = `rgba(${v},${v},${v},${0.03 + r() * 0.07})`;
      x.fillRect(r() * 220, r() * 220, 1 + r() * 1.6, 1 + r() * 1.6);
    }
    x.strokeStyle = "rgba(120,100,70,0.06)";
    for (let i = 0; i < 60; i++) {
      const a = r() * 220, b = r() * 220, l = 6 + r() * 18, ang = r() * Math.PI;
      x.beginPath(); x.moveTo(a, b); x.lineTo(a + Math.cos(ang) * l, b + Math.sin(ang) * l); x.stroke();
    }
    grain = ctx.createPattern(g, "repeat");
    return grain;
  }

  function roundRectPts(x, y, w, h, r) {
    const pts = [];
    const corner = (cx, cy, a0) => { for (let i = 0; i <= 4; i++) { const a = a0 + (i / 4) * Math.PI / 2; pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); } };
    corner(x + w - r, y + r, -Math.PI / 2);
    corner(x + w - r, y + h - r, 0);
    corner(x + r, y + h - r, Math.PI / 2);
    corner(x + r, y + r, Math.PI);
    return pts;
  }
  function circlePts(cx, cy, r, n = 40, ry = r) {
    const pts = [];
    for (let i = 0; i < n; i++) { const a = (i / n) * Math.PI * 2; pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * ry]); }
    return pts;
  }

  // Jagged, hand-torn outline for a closed polygon.
  function tornPath(ctx, pts, seed, rough = 3, step = 14) {
    const r = rng(seed * 31 + BOIL * 977 + 1);
    ctx.beginPath();
    for (let i = 0; i < pts.length; i++) {
      const a = pts[i], b = pts[(i + 1) % pts.length];
      const dx = b[0] - a[0], dy = b[1] - a[1];
      const len = Math.hypot(dx, dy) || 1;
      const nx = -dy / len, ny = dx / len;
      const n = Math.max(1, Math.ceil(len / step));
      for (let k = 0; k < n; k++) {
        const p = k / n;
        let off = (r() - 0.5) * 2 * rough;
        if (r() < 0.06) off *= 2.4;
        const px = a[0] + dx * p + nx * off, py = a[1] + dy * p + ny * off;
        if (i === 0 && k === 0) ctx.moveTo(px, py); else ctx.lineTo(px, py);
      }
    }
    ctx.closePath();
  }

  // A torn piece of paper: soft shadow, pale fibrous edge, flat colour, grain.
  function paper(ctx, pts, color, seed, o = {}) {
    const rough = o.rough ?? 3, shadow = o.shadow ?? true;
    tornPath(ctx, pts, seed, rough, o.step ?? 14);
    if (shadow) {
      ctx.save();
      ctx.shadowColor = o.shadowColor || "rgba(10,14,30,0.28)";
      ctx.shadowBlur = o.blur ?? 10;
      ctx.shadowOffsetY = o.dy ?? 4;
      ctx.fillStyle = color; ctx.fill();
      ctx.restore();
    }
    if (o.edge !== false) {
      ctx.lineWidth = o.edgeW ?? 3.5;
      ctx.strokeStyle = o.edgeColor || "rgba(255,251,242,0.7)";
      ctx.stroke();
    }
    ctx.fillStyle = color; ctx.fill();
    if (o.grain !== false) {
      ctx.save(); ctx.clip();
      ctx.globalAlpha = 0.9; ctx.fillStyle = grainPattern(ctx);
      ctx.fillRect(-4000, -4000, 8000, 8000);
      ctx.restore();
    }
  }
  const rect = (ctx, x, y, w, h, color, seed, o) => paper(ctx, [[x, y], [x + w, y], [x + w, y + h], [x, y + h]], color, seed, o);
  const rrect = (ctx, x, y, w, h, r, color, seed, o) => paper(ctx, roundRectPts(x, y, w, h, r), color, seed, o);
  const circ = (ctx, x, y, r, color, seed, o) => paper(ctx, circlePts(x, y, r, Math.max(18, Math.round(r / 3))), color, seed, Object.assign({ step: 10, rough: 2.2 }, o));

  function fullBg(ctx, color) {
    ctx.fillStyle = color; ctx.fillRect(-1200, -1200, VW + 2400, VH + 2400);
    ctx.save(); ctx.fillStyle = grainPattern(ctx); ctx.fillRect(-1200, -1200, VW + 2400, VH + 2400); ctx.restore();
  }

  // ---------- type ----------
  const F = {
    hand: (s, w = 600) => `${w} ${s}px Caveat, "Comic Sans MS", cursive`,
    serif: (s, it) => `${it ? "italic " : ""}400 ${s}px "Instrument Serif", Georgia, serif`,
    sans: (s, w = 500) => `${w} ${s}px Inter, "Helvetica Neue", Arial, sans-serif`,
  };
  function text(ctx, str, x, y, font, color, o = {}) {
    ctx.save();
    ctx.font = font; ctx.fillStyle = color;
    ctx.textAlign = o.align || "left"; ctx.textBaseline = o.base || "alphabetic";
    if (o.spacing) ctx.letterSpacing = o.spacing + "px";
    const reveal = o.reveal ?? 1;
    if (reveal < 1) {
      const w = ctx.measureText(str).width;
      const x0 = o.align === "center" ? x - w / 2 : o.align === "right" ? x - w : x;
      ctx.beginPath(); ctx.rect(x0 - 10, y - 400, (w + 20) * reveal, 800); ctx.clip();
    }
    if (o.alpha != null) ctx.globalAlpha = o.alpha;
    ctx.fillText(str, x, y);
    ctx.restore();
  }
  function wrap(ctx, str, font, maxW) {
    ctx.save(); ctx.font = font;
    const words = str.split(" "), lines = []; let cur = "";
    for (const w of words) {
      const test = cur ? cur + " " + w : w;
      if (ctx.measureText(test).width > maxW && cur) { lines.push(cur); cur = w; } else cur = test;
    }
    if (cur) lines.push(cur);
    ctx.restore();
    return lines;
  }

  // Torn-paper caption strip that slides up, writes itself on, then leaves.
  function caption(ctx, str, lt, start, dur, o = {}) {
    if (CAPS) { CAPS.push([str, lt, start, dur, o]); return; }
    const p = lt - start;
    if (p < 0 || p > dur) return;
    const inP = easeOut(seg(p, 0, 0.55)), outP = seg(p, dur - 0.45, dur);
    ctx.save();
    ctx.font = F.hand(o.size || 58);
    const w = ctx.measureText(str).width + 90, h = (o.size || 58) * 1.55;
    const cx = o.x ?? VW / 2, cy = (o.y ?? 968) + (1 - inP) * 180 + outP * 40;
    ctx.globalAlpha = 1 - outP;
    ctx.translate(cx, cy); ctx.rotate((o.rot ?? -0.8) * Math.PI / 180);
    rect(ctx, -w / 2, -h / 2, w, h, o.bg || C.cream, 900 + Math.round(start * 10), { rough: 4, step: 12 });
    text(ctx, str, 0, h * 0.18, F.hand(o.size || 58), o.color || C.ink, { align: "center", reveal: easeInOut(seg(p, 0.25, 0.25 + Math.min(1.3, str.length * 0.03))) });
    ctx.restore();
  }

  // Vertical captions: wrapped, larger, stacked inside the Reels/TikTok safe zone.
  function captionsV(ctx, caps) {
    const size = 70, lineH = size * 1.5;
    let y = null;
    for (const [str, lt, start, dur, o] of caps) {
      const p = lt - start;
      if (p < 0 || p > dur) continue;
      if (y == null) y = o.vy ?? 1470;
      const inP = easeOut(seg(p, 0, 0.55)), outP = seg(p, dur - 0.45, dur);
      const lines = wrap(ctx, str, F.hand(size), 860);
      lines.forEach((ln, i) => {
        ctx.save();
        ctx.font = F.hand(size);
        const w = ctx.measureText(ln).width + 80;
        ctx.globalAlpha = 1 - outP;
        ctx.translate(540 + (i % 2 ? 14 : -10), y + (1 - inP) * 160 + outP * 30);
        ctx.rotate(((o.rot ?? -0.8) + (i % 2 ? 1.2 : 0)) * Math.PI / 180);
        rect(ctx, -w / 2, -lineH / 2, w, lineH, o.bg || C.cream, 900 + Math.round(start * 10) + i, { rough: 4, step: 12 });
        const per = Math.min(1.3, str.length * 0.03) / lines.length;
        text(ctx, ln, 0, lineH * 0.2, F.hand(size), o.color || C.ink, { align: "center", reveal: easeInOut(seg(p, 0.25 + i * per, 0.25 + (i + 1) * per)) });
        ctx.restore();
        y += lineH + 6;
      });
      y += 14;
    }
  }

  // ---------- characters ----------
  function hairShape(ctx, style, color, seed) {
    if (style === "bun") {
      circ(ctx, 4, -74, 32, color, seed + 1, { shadow: false });
    }
    if (style === "curly") {
      for (let i = 0; i < 9; i++) {
        const a = Math.PI + (i / 8) * Math.PI;
        circ(ctx, Math.cos(a) * 60, -10 + Math.sin(a) * 60, 26, color, seed + 10 + i, { shadow: false, edge: false });
      }
    }
    if (style === "long") {
      paper(ctx, [[-70, -20], [-66, 70], [-40, 86], [40, 86], [66, 70], [70, -20]], color, seed + 2, { shadow: false });
    }
  }
  function hairFront(ctx, style, color, seed) {
    const pts = [];
    const r = style === "curly" ? 66 : 65;
    for (let i = 0; i <= 14; i++) { const a = Math.PI + (i / 14) * Math.PI; pts.push([Math.cos(a) * r, Math.sin(a) * r - 2]); }
    if (style === "short") pts.push([60, -14], [30, -26], [-10, -20], [-40, -30], [-62, -8]);
    else if (style === "bun" || style === "long") pts.push([58, -6], [34, -30], [0, -34], [-30, -26], [-60, 4]);
    else pts.push([62, -20], [20, -34], [-20, -34], [-62, -20]);
    paper(ctx, pts, color, seed + 3, { shadow: false, rough: 2 });
  }

  // p: {x,y,s,skin,shirt,hair,hairStyle,look,mouth,talk,blink,seed,tilt,arms:[{sh,hand,pencil,mug}],scarf}
  function person(ctx, p) {
    const s = p.s || 1;
    ctx.save();
    ctx.translate(p.x, p.y); ctx.scale(s, s);
    // torso
    paper(ctx, [[-62, -168], [62, -168], [92, -130], [104, 0], [-104, 0], [-92, -130]], p.shirt, p.seed, { rough: 3 });
    if (p.scarf) paper(ctx, [[-44, -172], [44, -172], [36, -142], [10, -130], [18, -80], [-4, -80], [-8, -132], [-40, -142]], p.scarf, p.seed + 40, { shadow: false });
    // head
    ctx.save();
    ctx.translate(0, -232); ctx.rotate((p.tilt || 0) * Math.PI / 180);
    hairShape(ctx, p.hairStyle, p.hair, p.seed + 5);
    circ(ctx, 0, 0, 62, p.skin, p.seed + 6, { rough: 1.8 });
    hairFront(ctx, p.hairStyle, p.hair, p.seed + 7);
    const [lx, ly] = p.look || [0, 0];
    ctx.fillStyle = C.ink;
    if (p.blink) {
      ctx.lineWidth = 4; ctx.strokeStyle = C.ink; ctx.lineCap = "round";
      ctx.beginPath(); ctx.moveTo(-30 + lx, 4 + ly); ctx.lineTo(-16 + lx, 4 + ly); ctx.moveTo(16 + lx, 4 + ly); ctx.lineTo(30 + lx, 4 + ly); ctx.stroke();
    } else {
      ctx.beginPath(); ctx.ellipse(-23 + lx, 4 + ly, 6, 7.5, 0, 0, Math.PI * 2); ctx.ellipse(23 + lx, 4 + ly, 6, 7.5, 0, 0, Math.PI * 2); ctx.fill();
    }
    ctx.fillStyle = "rgba(240,120,130,0.35)";
    ctx.beginPath(); ctx.ellipse(-38, 24, 11, 7, 0, 0, Math.PI * 2); ctx.ellipse(38, 24, 11, 7, 0, 0, Math.PI * 2); ctx.fill();
    ctx.strokeStyle = C.ink; ctx.lineWidth = 4; ctx.lineCap = "round";
    const mx = lx * 0.5, my = 30 + ly * 0.4;
    if (p.mouth === "talk") {
      ctx.fillStyle = "#6b2f35"; ctx.beginPath(); ctx.ellipse(mx, my, 9, 3 + 9 * (p.talk || 0), 0, 0, Math.PI * 2); ctx.fill();
    } else if (p.mouth === "flat") {
      ctx.beginPath(); ctx.moveTo(mx - 10, my); ctx.lineTo(mx + 10, my); ctx.stroke();
    } else if (p.mouth === "frown") {
      ctx.beginPath(); ctx.arc(mx, my + 12, 12, 1.2 * Math.PI, 1.8 * Math.PI); ctx.stroke();
    } else {
      ctx.beginPath(); ctx.arc(mx, my - 6, 13, 0.18 * Math.PI, 0.82 * Math.PI); ctx.stroke();
    }
    if (p.sweat) { circ(ctx, 58, -40, 9, "#bfe3f5", p.seed + 90, { shadow: false }); }
    ctx.restore();
    // arms
    for (const a of p.arms || []) {
      ctx.lineCap = "round"; ctx.strokeStyle = p.shirt; ctx.lineWidth = 32;
      ctx.beginPath(); ctx.moveTo(a.sh[0], a.sh[1]);
      const mid = a.elbow || [(a.sh[0] + a.hand[0]) / 2 + (a.hand[0] > a.sh[0] ? 10 : -10), (a.sh[1] + a.hand[1]) / 2 + 30];
      ctx.quadraticCurveTo(mid[0], mid[1], a.hand[0], a.hand[1]); ctx.stroke();
      if (a.pencil) pencil(ctx, a.hand[0], a.hand[1], a.pencilAng ?? -0.9, 1);
      if (a.mug) mug(ctx, a.hand[0], a.hand[1] - 20, p.seed + 70);
      circ(ctx, a.hand[0], a.hand[1], 16, p.skin, p.seed + 60 + a.hand[0] | 0, { shadow: false, rough: 1.4 });
    }
    ctx.restore();
  }
  function pencil(ctx, x, y, ang, s) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(ang); ctx.scale(s, s);
    paper(ctx, [[-8, -70], [8, -70], [8, 20], [-8, 20]], C.mustard, 311, { shadow: false, rough: 1.2, step: 8 });
    paper(ctx, [[-8, 20], [8, 20], [0, 42]], "#e9c9a0", 312, { shadow: false, rough: 1, step: 6 });
    ctx.fillStyle = C.ink; ctx.beginPath(); ctx.moveTo(-3, 34); ctx.lineTo(3, 34); ctx.lineTo(0, 42); ctx.fill();
    paper(ctx, [[-8, -84], [8, -84], [8, -70], [-8, -70]], C.pink, 313, { shadow: false, rough: 1, step: 6 });
    ctx.restore();
  }
  function mug(ctx, x, y, seed) {
    paper(ctx, [[x - 26, y - 34], [x + 26, y - 34], [x + 22, y + 26], [x - 22, y + 26]], C.red, seed, { rough: 1.6 });
    ctx.strokeStyle = C.red; ctx.lineWidth = 8; ctx.beginPath(); ctx.arc(x + 30, y - 4, 14, -1.3, 1.3); ctx.stroke();
  }

  // Speech-bubble outline with the Quolio tail sweeping down-right.
  function bubblePts(x, y, w, h, r, tip, back) {
    const pts = [];
    const arc = (cx, cy, a0, a1, n = 6) => { for (let i = 0; i <= n; i++) { const a = a0 + (i / n) * (a1 - a0); pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]); } };
    arc(x + w - r, y + r, -Math.PI / 2, 0);
    arc(x + w - r, y + h - r, 0, Math.PI * 0.36, 3);
    pts.push(tip, back);
    arc(x + r, y + h - r, Math.PI / 2, Math.PI);
    arc(x + r, y + r, Math.PI, Math.PI * 1.5);
    return pts;
  }

  // The Quolio mascot: the app icon's cream speech bubble, with a face.
  function mascot(ctx, x, y, s, o = {}) {
    ctx.save(); ctx.translate(x, y); ctx.scale(s, s); ctx.rotate((o.rot || 0) * Math.PI / 180);
    ctx.strokeStyle = C.ink; ctx.lineCap = "round";
    if (o.wave != null) {
      ctx.lineWidth = 7;
      const a = -0.6 + Math.sin(o.wave) * 0.45;
      ctx.beginPath(); ctx.moveTo(70, -10); ctx.lineTo(98 + Math.cos(a) * 10, -46 + Math.sin(a) * 18); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(-70, 0); ctx.lineTo(-96, 24); ctx.stroke();
    }
    paper(ctx, bubblePts(-78, -62, 156, 114, 44, [64, 84], [14, 52]), C.cream, 501, { rough: 2, step: 10 });
    ctx.lineWidth = 3.5; ctx.strokeStyle = "rgba(74,100,220,0.85)"; ctx.stroke();
    ctx.fillStyle = C.ink; ctx.strokeStyle = C.ink; ctx.lineWidth = 4.5;
    const ey = -12;
    if (o.sleep) {
      ctx.beginPath(); ctx.arc(-22, ey, 8, 0.1 * Math.PI, 0.9 * Math.PI); ctx.stroke();
      ctx.beginPath(); ctx.arc(22, ey, 8, 0.1 * Math.PI, 0.9 * Math.PI); ctx.stroke();
    } else {
      if (o.blink) { ctx.beginPath(); ctx.moveTo(-30, ey); ctx.lineTo(-14, ey); ctx.stroke(); }
      else { ctx.beginPath(); ctx.ellipse(-22, ey, 6.5, 8, 0, 0, Math.PI * 2); ctx.fill(); }
      if (o.wink || o.blink) { ctx.beginPath(); ctx.arc(22, ey + 4, 8, 1.1 * Math.PI, 1.9 * Math.PI); ctx.stroke(); }
      else { ctx.beginPath(); ctx.ellipse(22, ey, 6.5, 8, 0, 0, Math.PI * 2); ctx.fill(); }
    }
    ctx.fillStyle = "rgba(74,100,220,0.35)";
    ctx.beginPath(); ctx.ellipse(-40, 8, 10, 6, 0, 0, Math.PI * 2); ctx.ellipse(40, 8, 10, 6, 0, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(0, 8, o.bigSmile ? 14 : 10, 0.15 * Math.PI, 0.85 * Math.PI); ctx.stroke();
    ctx.restore();
  }

  // The Quolio app icon, cut from paper.
  function logo(ctx, cx, cy, S) {
    ctx.save(); ctx.translate(cx - S / 2, cy - S / 2); ctx.scale(S / 1024, S / 1024);
    const g = ctx.createLinearGradient(0, 0, 0, 1024);
    g.addColorStop(0, "#5273e4"); g.addColorStop(1, C.brandDeep);
    paper(ctx, roundRectPts(0, 0, 1024, 1024, 230), g, 950, { rough: 5, step: 28, blur: 40, dy: 18, edgeW: 7 });
    paper(ctx, bubblePts(170, 190, 683, 520, 160, [828, 842], [603, 710]), C.cream, 951, { rough: 5, step: 24, blur: 30, dy: 14, edgeW: 6 });
    [[790, 352], [708, 452], [586, 552]].forEach(([x2, y], i) => {
      circ(ctx, 272, y, 30, C.brand, 952 + i, { shadow: false, rough: 2, edge: false });
      ctx.fillStyle = "#1c1c1e"; ctx.beginPath(); ctx.roundRect(340, y - 27, x2 - 340, 54, 27); ctx.fill();
    });
    ctx.restore();
  }

  // Phone frame; draws `screen(ctx, x, y, w, h)` clipped inside the display.
  function phone(ctx, x, y, w, h, seed, screen) {
    rrect(ctx, x, y, w, h, w * 0.14, C.ink, seed, { rough: 2, blur: 18, dy: 8 });
    const m = w * 0.055;
    ctx.save();
    const sx = x + m, sy = y + m, sw = w - 2 * m, sh = h - 2 * m;
    ctx.beginPath(); ctx.roundRect(sx, sy, sw, sh, w * 0.1); ctx.clip();
    ctx.fillStyle = C.cream; ctx.fillRect(sx, sy, sw, sh);
    ctx.fillStyle = grainPattern(ctx); ctx.fillRect(sx, sy, sw, sh);
    if (screen) screen(ctx, sx, sy, sw, sh);
    ctx.restore();
    ctx.fillStyle = C.ink; ctx.beginPath(); ctx.roundRect(x + w / 2 - w * 0.14, y + m + 6, w * 0.28, w * 0.07, w * 0.035); ctx.fill();
  }

  // ---------- shared set pieces ----------
  function nightSky(ctx, t, seed = 1) {
    const g = ctx.createLinearGradient(0, 0, 0, VH);
    g.addColorStop(0, C.navyDeep); g.addColorStop(0.7, C.navy); g.addColorStop(1, C.navy2);
    ctx.fillStyle = g; ctx.fillRect(-1200, -1200, VW + 2400, VH + 2400);
    ctx.fillStyle = grainPattern(ctx); ctx.fillRect(-1200, -1200, VW + 2400, VH + 2400);
    if (VERT) {
      const r2 = rng(seed + 500);
      ctx.fillStyle = C.star;
      for (let i = 0; i < 40; i++) {
        const x = -200 + r2() * (VW + 400), y = -600 + r2() * 600, ph = r2() * 6;
        ctx.globalAlpha = 0.45 + 0.55 * Math.abs(Math.sin(t * 1.6 + ph));
        ctx.beginPath(); ctx.arc(x, y, 1.6 + r2() * 1.8, 0, Math.PI * 2); ctx.fill();
      }
      ctx.globalAlpha = 1;
    }
    const r = rng(seed);
    for (let i = 0; i < 80; i++) {
      const x = r() * VW, y = r() * VH * 0.62, big = r() < 0.18, ph = r() * 6;
      const a = 0.45 + 0.55 * Math.abs(Math.sin(t * 1.6 + ph));
      ctx.globalAlpha = a; ctx.fillStyle = C.star;
      if (big) {
        const s = 7 + r() * 5;
        ctx.beginPath();
        for (let k = 0; k < 8; k++) { const rr = k % 2 ? s * 0.28 : s; const ang = k * Math.PI / 4; ctx.lineTo(x + Math.cos(ang) * rr, y + Math.sin(ang) * rr); }
        ctx.fill();
      } else { ctx.beginPath(); ctx.arc(x, y, 1.6 + r() * 1.8, 0, Math.PI * 2); ctx.fill(); }
    }
    ctx.globalAlpha = 1;
  }
  function moon(ctx, x, y, r) {
    const pts = [];
    for (let i = 0; i <= 20; i++) { const a = -Math.PI / 2 + (i / 20) * Math.PI; pts.push([x + Math.cos(a) * r, y + Math.sin(a) * r]); }
    for (let i = 20; i >= 0; i--) { const a = -Math.PI / 2 + (i / 20) * Math.PI; pts.push([x + Math.cos(a) * r * 0.32, y + Math.sin(a) * r * 0.96]); }
    ctx.save(); ctx.translate(x, y); ctx.rotate(0.35); ctx.translate(-x, -y);
    paper(ctx, pts, C.cream, 77, { shadowColor: "rgba(255,230,160,0.35)", blur: 30, dy: 0, rough: 2 });
    ctx.restore();
  }
  function hills(ctx, t, seed, colors, drift = 0) {
    colors.forEach((col, i) => {
      const r = rng(seed + i * 13);
      const base = VH - 250 + i * 80, pts = [[-40, VH + 900]];
      for (let x = -40; x <= VW + 900; x += 120) pts.push([x + drift * (i + 1), base - r() * 70 - Math.sin(x / 300 + i) * 30]);
      pts.push([VW + 900 + drift * (i + 1), VH + 900]);
      paper(ctx, pts, col, seed + i, { rough: 5, step: 18, shadowColor: "rgba(0,0,0,0.35)", dy: -2 });
    });
  }
  function paperPlane(ctx, x, y, ang, s, seed) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(ang); ctx.scale(s, s);
    paper(ctx, [[30, 0], [-26, -18], [-14, 0]], C.cream, seed, { rough: 1, step: 6, blur: 4 });
    paper(ctx, [[30, 0], [-14, 0], [-22, 16]], C.paper2, seed + 1, { rough: 1, step: 6, shadow: false });
    ctx.restore();
  }

  // ================= SCENES =================
  // Each scene draws itself at local time `lt` (seconds).

  // 1 · A night town where every window is someone taking notes.
  function sceneTown(ctx, lt) {
    const push = 1 + 0.05 * easeInOut(seg(lt, 0, 7));
    ctx.save(); ctx.translate(VW / 2, VH / 2); ctx.scale(push, push); ctx.translate(-VW / 2, -VH / 2);
    nightSky(ctx, lt, 3);
    moon(ctx, 300, 220, 88);
    const r = rng(42);
    const cols = [C.navy3, "#3b4a80", "#2f3a66", "#46538a", "#4a4174", "#394a6e", "#3f4f7e"];
    const bs = [];
    let x = 90;
    for (let i = 0; i < 8; i++) {
      const w = 170 + r() * 90, h = 300 + r() * 240;
      bs.push({ x, w, h, col: cols[i % cols.length], roof: r() < 0.5, seed: 100 + i });
      x += w + 14 + r() * 30;
    }
    const ground = VH - 150;
    const planes = [];
    bs.forEach((b, i) => {
      const top = ground - b.h;
      const pts = [[b.x, ground + 60], [b.x, top], ...(b.roof ? [[b.x + b.w / 2, top - 70]] : []), [b.x + b.w, top], [b.x + b.w, ground + 60]];
      paper(ctx, pts, b.col, b.seed, { rough: 3 });
      const cN = b.w > 220 ? 3 : 2, rN = Math.floor((b.h - 60) / 95);
      const ww = 46, wh = 58, gap = (b.w - cN * ww) / (cN + 1);
      const wr = rng(b.seed);
      for (let cy = 0; cy < rN; cy++) for (let cx = 0; cx < cN; cx++) {
        const wx = b.x + gap + cx * (ww + gap), wy = top + 40 + cy * 95;
        const lit = wr() < 0.72;
        rect(ctx, wx, wy, ww, wh, lit ? C.window : "#232c52", b.seed * 10 + cy * 5 + cx, { rough: 1.6, step: 9, shadow: false });
        if (lit && wr() < 0.7) {
          // silhouette hunched over a desk, scribbling
          const bob = Math.sin(lt * 15 + cx + cy * 3 + i) * 2;
          ctx.fillStyle = "rgba(30,36,51,0.78)";
          ctx.beginPath(); ctx.arc(wx + ww / 2, wy + wh - 22 + bob, 9, 0, Math.PI * 2); ctx.fill();
          ctx.beginPath(); ctx.ellipse(wx + ww / 2, wy + wh, 17, 13, 0, Math.PI, 0); ctx.fill();
          if (wr() < 0.35) planes.push([wx + ww / 2, wy + 10, wr()]);
        }
      }
    });
    hills(ctx, lt, 600, ["#18203d", C.navyDeep], 0);
    // pages torn out and flown away, unread
    planes.slice(0, 9).forEach(([sx, sy, k], i) => {
      const start = 0.6 + i * 0.55, p = seg(lt, start, start + 5.5);
      if (p <= 0) return;
      const pt = (q) => [sx + q * (500 + k * 500), sy - q * (520 + k * 200) + Math.sin(q * 6 + i) * 40];
      ctx.save(); ctx.setLineDash([6, 12]); ctx.strokeStyle = "rgba(250,246,240,0.45)"; ctx.lineWidth = 2.5;
      ctx.beginPath(); for (let q = Math.max(0, p - 0.35); q <= p; q += 0.02) { const [a, b] = pt(q); ctx.lineTo(a, b); } ctx.stroke(); ctx.restore();
      const [px, py] = pt(p), [qx, qy] = pt(p + 0.01);
      paperPlane(ctx, px, py, Math.atan2(qy - py, qx - px), 1.1, 700 + i);
    });
    ctx.restore();
    caption(ctx, "In a town that never stopped taking notes…", lt, 1.0, 5.6);
  }

  // 2 · Three windows up close: frantic scribbling, missing the point.
  function sceneScribblers(ctx, lt) {
    nightSky(ctx, lt, 9);
    const panels = [
      { x: 110, wall: "#f3e6cf", skin: SKIN[1], shirt: C.blue, hair: "#2b2230", hs: "short", said: "…so the real issue is—" },
      { x: 680, wall: "#f4dcd3", skin: SKIN[0], shirt: C.green, hair: "#8a4b2a", hs: "long", said: "…wait, who owns this?" },
      { x: 1250, wall: "#dcebdc", skin: SKIN[2], shirt: C.plum, hair: "#1d1a22", hs: "curly", said: "…did anyone catch that?" },
    ];
    panels.forEach((P, i) => {
      const drop = easeOut(seg(lt, i * 0.25, i * 0.25 + 0.7));
      const y = 150 + (1 - drop) * -700;
      ctx.save(); ctx.translate(P.x, y); ctx.rotate(((i - 1) * 1.2) * Math.PI / 180);
      rect(ctx, 0, 0, 560, 640, P.wall, 200 + i * 7, { rough: 4, blur: 22, dy: 10 });
      ctx.save(); ctx.beginPath(); ctx.rect(8, 8, 544, 624); ctx.clip();
      const t = lt + i * 0.37;
      const scrib = [Math.sin(t * 22) * 22 + Math.sin(t * 7) * 18, Math.cos(t * 19) * 8];
      person(ctx, {
        x: 280, y: 560, s: 1.05, seed: 300 + i * 20, skin: P.skin, shirt: P.shirt, hair: P.hair, hairStyle: P.hs,
        look: [0, 12], mouth: i === 1 ? "frown" : "flat", tilt: Math.sin(t * 9) * 2, sweat: seg(lt, 3, 3.2) > 0 && i !== 1,
        arms: [{ sh: [60, -140], hand: [70 + scrib[0], -10 + scrib[1]], pencil: true, pencilAng: -0.5 }, { sh: [-60, -140], hand: [-70, -10] }],
      });
      // desk + a page filling with scribble
      rect(ctx, 20, 540, 520, 120, C.manila, 240 + i, { rough: 3 });
      ctx.save(); ctx.translate(250, 520); ctx.rotate(-0.08);
      rect(ctx, -110, -30, 200, 60, C.cream, 250 + i, { rough: 2, shadow: false });
      ctx.strokeStyle = C.ink; ctx.lineWidth = 2; ctx.beginPath();
      const n = Math.floor(clamp(lt / 7) * 90); const sr = rng(260 + i);
      for (let k = 0; k < n; k++) { const row = Math.floor(k / 30), col = k % 30; ctx.lineTo(-96 + col * 6, -16 + row * 14 + (sr() - 0.5) * 10); }
      ctx.stroke(); ctx.restore();
      // crumpled pages pile up
      for (let k = 0; k < 5; k++) {
        const bt = 1.4 + k * 1.1 + i * 0.3; if (lt < bt) continue;
        const fp = easeOut(seg(lt, bt, bt + 0.5));
        circ(ctx, 60 + k * 70 + i * 13, lerp(470, 600, fp), 22, C.cream, 270 + k + i * 9, { rough: 5, step: 6 });
      }
      ctx.restore();
      ctx.restore();
    });
    // what was actually said, drifting past unnoticed
    panels.forEach((P, i) => {
      const sp = seg(lt, 1.2 + i * 0.9, 5.6 + i * 0.5);
      if (sp <= 0 || sp >= 1) return;
      ctx.save(); ctx.globalAlpha = Math.sin(sp * Math.PI);
      ctx.translate(P.x + lerp(600, -60, sp), 230);
      ctx.font = F.hand(34); const w = ctx.measureText(P.said).width + 40;
      rect(ctx, 0, -30, w, 56, C.cream, 280 + i, { rough: 2.5, blur: 6 });
      text(ctx, P.said, 20, 10, F.hand(34), C.inkSoft);
      ctx.restore();
    });
    caption(ctx, "Everyone wrote everything down — and missed what was actually said.", lt, 1.4, 5.4, { size: 52 });
  }

  // 3 · Mia's meeting. She sets the phone down, then puts the pencil down.
  const MEET = { phone: [1080, 540, 110, 196] };
  function meetingRoom(ctx, lt) {
    fullBg(ctx, "#f1e5cf");
    rect(ctx, 0, 0, VW, 90, "#e6d6b8", 401, { rough: 4, shadow: false });
    rect(ctx, 1240, 120, 520, 360, C.sky, 402, { rough: 4, blur: 14 });
    circ(ctx, 1640, 210, 52, C.yellow, 403, { shadowColor: "rgba(255,220,120,0.6)", blur: 20, dy: 0 });
    [[1360, 220, 0.9], [1520, 330, 1.1]].forEach(([cx, cy, sc], i) => {
      const dx = (lt * 12 * sc) % 400;
      ctx.save(); ctx.beginPath(); ctx.rect(1250, 130, 500, 340); ctx.clip();
      [[-40, 0, 34], [0, -14, 44], [44, 0, 32]].forEach(([ox, oy, rr], k) => circ(ctx, cx + dx + ox - 120, cy + oy, rr * sc, C.cream, 404 + i * 5 + k, { shadow: false }));
      ctx.restore();
    });
    rect(ctx, 1230, 470, 540, 26, C.manilaDark, 409, { rough: 2 });
    // plant
    rect(ctx, 150, 470, 90, 100, C.red, 410, { rough: 2 });
    for (let k = 0; k < 6; k++) {
      const a = -Math.PI / 2 + (k - 2.5) * 0.35 + Math.sin(lt * 1.5 + k) * 0.03;
      ctx.save(); ctx.translate(195, 470); ctx.rotate(a + Math.PI / 2);
      paper(ctx, [[0, 0], [-18, -70], [0, -130], [18, -70]], k % 2 ? C.green : "#5a9468", 411 + k, { shadow: false, rough: 2 });
      ctx.restore();
    }
    // wall notes: the "old way"
    rect(ctx, 420, 150, 220, 170, C.cream, 420, { rough: 3 });
    text(ctx, "Agenda", 450, 205, F.hand(44), C.ink);
    ctx.strokeStyle = C.inkSoft; ctx.lineWidth = 3;
    for (let k = 0; k < 3; k++) { ctx.beginPath(); ctx.moveTo(450, 240 + k * 26); ctx.lineTo(600 - k * 30, 240 + k * 26); ctx.stroke(); }
  }
  function screenRecording(ctx, x, y, w, h, lt, on, level) {
    const cx = x + w / 2;
    if (!on) { ctx.fillStyle = "rgba(30,36,51,0.08)"; ctx.fillRect(x, y, w, h); }
    mascot(ctx, cx, y + h * 0.36, w / 210, { sleep: !on, blink: on && lt % 2.8 < 0.12 });
    if (on) {
      ctx.fillStyle = C.red; ctx.globalAlpha = 0.6 + 0.4 * Math.sin(lt * 5);
      ctx.beginPath(); ctx.arc(x + 16, y + 20, 5, 0, Math.PI * 2); ctx.fill(); ctx.globalAlpha = 1;
      const n = 11;
      for (let k = 0; k < n; k++) {
        const hh = 4 + level * 26 * Math.abs(Math.sin(lt * 9 + k * 1.3)) * (0.5 + 0.5 * Math.sin(k));
        ctx.fillStyle = C.ink; ctx.fillRect(x + w * 0.14 + k * (w * 0.72 / n), y + h * 0.78 - hh / 2, 4, hh);
      }
    }
  }
  const STRIPS = [
    { who: 0, t: 8.4, s: "Ship v1 on Oct 14", c: C.yellow },
    { who: 0, t: 9.7, s: "Priya owns pricing", c: C.mint },
    { who: 1, t: 11.0, s: "Beta: 200 people first", c: C.pink },
    { who: 1, t: 12.3, s: "Sam sends invites", c: C.cream },
    { who: 0, t: 13.6, s: "Mia writes the launch post", c: C.yellow },
  ];
  function talkAt(who, lt) {
    const turns = [[0.3, 3.8, 0], [4.2, 7.6, 1], [8.0, 10.2, 0], [10.3, 12.2, 1], [12.4, 14.8, 0], [14.9, 16, 1]];
    for (const [a, b, w] of turns) if (w === who && lt > a && lt < b) return Math.abs(Math.sin(lt * 13 + who)) * 0.8 + 0.2;
    return 0;
  }
  function sceneMeeting(ctx, lt) {
    meetingRoom(ctx, lt);
    const speakers = [
      { x: 470, skin: SKIN[3], shirt: C.blue, hair: "#3a2a24", hs: "short", seed: 520 },
      { x: 790, skin: SKIN[2], shirt: C.red, hair: "#1d1a22", hs: "curly", seed: 540 },
    ];
    speakers.forEach((P, i) => {
      const talk = talkAt(i, lt);
      person(ctx, {
        x: P.x, y: 760, s: 1.08, seed: P.seed, skin: P.skin, shirt: P.shirt, hair: P.hair, hairStyle: P.hs,
        look: [i === 0 ? 10 : -8, 0], mouth: talk > 0 ? "talk" : "smile", talk, blink: (lt + i) % 3.4 < 0.12,
        tilt: talk > 0 ? Math.sin(lt * 3) * 3 : 0,
        arms: [{ sh: [60, -140], hand: [80 + (talk > 0 ? Math.sin(lt * 4) * 30 : 0), -30 - (talk > 0 ? 40 + Math.sin(lt * 5) * 30 : 0)] }, { sh: [-60, -140], hand: [-70, -20] }],
      });
    });
    // Mia
    const [px, py, pw, ph] = MEET.phone;
    const place = easeInOut(seg(lt, 0.6, 1.8));
    const tap = seg(lt, 2.2, 2.6);
    const on = lt > 2.5;
    const penDown = easeInOut(seg(lt, 8.0, 9.0));
    const lean = easeInOut(seg(lt, 9.2, 10.2));
    const miaX = 1420, miaY = 760, ms = 1.08;
    const toLocal = (gx, gy) => [(gx - miaX) / ms, (gy - miaY) / ms];
    const phoneHand = on ? lerp(1, 0, seg(lt, 2.6, 3.2)) : 1;
    let rightHand = toLocal(lerp(1330, px + pw / 2, place), lerp(560, py + ph - 20, place));
    if (tap > 0) rightHand = toLocal(px + pw / 2 + 10, py + ph * 0.5 + Math.sin(tap * Math.PI) * 20);
    if (on) rightHand = [lerp(rightHand[0], -80, 1 - phoneHand), lerp(rightHand[1], -10, 1 - phoneHand)];
    if (lean > 0) rightHand = [lerp(rightHand[0], -30, lean), lerp(rightHand[1], -205, lean)];
    const pencilHand = [lerp(90, 120, penDown), lerp(-90, -8, penDown)];
    const lookSpeakers = on ? easeInOut(seg(lt, 3.0, 3.8)) : 0;
    person(ctx, {
      x: miaX, y: miaY, s: ms, seed: 560, skin: SKIN[0], shirt: C.mustard, hair: "#6b3a22", hairStyle: "bun", scarf: C.red,
      look: [lerp(-12, -20, lookSpeakers), lerp(14, 0, lookSpeakers)], mouth: "smile",
      blink: lt % 3.1 < 0.12, tilt: lean * -8,
      arms: [
        { sh: [-60, -140], hand: rightHand },
        penDown < 1 ? { sh: [60, -140], hand: pencilHand, pencil: true, pencilAng: lerp(-0.6, -1.5, penDown) } : { sh: [60, -140], hand: [140, -8] },
      ],
    });
    // table
    rect(ctx, 150, 740, 1620, 60, C.manila, 590, { rough: 3, blur: 16 });
    rect(ctx, 190, 796, 1540, 900, C.manilaDark, 591, { rough: 4 });
    // pencil resting on the table
    if (penDown >= 1) pencil(ctx, miaX + 150 * ms, 738, -1.52, 1);
    // phone, lifted from Mia's hand onto the table
    const phX = lerp(1300, px, place), phY = lerp(470, py, place);
    ctx.save(); ctx.translate(phX + pw / 2, phY + ph); ctx.rotate(lerp(-0.25, 0, place)); ctx.translate(-(phX + pw / 2), -(phY + ph));
    const level = Math.max(talkAt(0, lt), talkAt(1, lt));
    phone(ctx, phX, phY, pw, ph, 595, (c, x, y, w, h) => screenRecording(c, x, y, w, h, lt, on, level));
    ctx.restore();
    if (tap > 0 && tap < 1) {
      ctx.strokeStyle = C.red; ctx.lineWidth = 4; ctx.globalAlpha = 1 - tap;
      ctx.beginPath(); ctx.arc(px + pw / 2, py + ph / 2, 20 + tap * 70, 0, Math.PI * 2); ctx.stroke(); ctx.globalAlpha = 1;
    }
    // sound arcs travel to the phone while it listens
    if (on) for (let i = 0; i < 2; i++) {
      const talk = talkAt(i, lt); if (!talk) continue;
      const mx = speakers[i].x + 14, my = 760 - 232 * 1.08 + 34;
      for (let k = 0; k < 3; k++) {
        const q = ((lt * 0.9 + k / 3) % 1);
        const [ax, ay] = bez([mx + 50, my], [(mx + px) / 2, my - 120], [px + pw / 2, py + 40], q);
        ctx.strokeStyle = C.inkSoft; ctx.globalAlpha = 0.5 * Math.sin(q * Math.PI); ctx.lineWidth = 3;
        ctx.beginPath(); ctx.arc(ax, ay, 14, -0.8, 0.8); ctx.stroke();
      }
      ctx.globalAlpha = 1;
    }
    // what was said becomes paper strips the phone gathers up
    STRIPS.forEach((S, i) => {
      const q = seg(lt, S.t, S.t + 1.5); if (q <= 0 || q >= 1) return;
      const mx = speakers[S.who].x, my = 300;
      const e = easeInOut(q);
      const [x, y] = bez([mx + 40, my], [(mx + px) / 2 + 60, 160 - i * 16], [px + pw / 2, py + 70], e);
      const sc = lerp(1, 0.15, Math.pow(e, 2.4));
      ctx.save(); ctx.translate(x, y); ctx.rotate(Math.sin(q * 6 + i) * 0.12); ctx.scale(sc, sc);
      ctx.font = F.hand(40); const w = ctx.measureText(S.s).width + 44;
      rect(ctx, -w / 2, -32, w, 64, S.c, 610 + i, { rough: 3, blur: 8 });
      text(ctx, S.s, 0, 12, F.hand(40), C.ink, { align: "center" });
      ctx.restore();
    });
    caption(ctx, "One morning, Mia tried something different.", lt, 0.4, 6.8);
    caption(ctx, "She put her pencil down — and listened.", lt, 8.2, 7.6);
  }

  // 4 · The finished note, built line by line.
  function ruledPaperBg(ctx) {
    fullBg(ctx, C.cream);
    ctx.strokeStyle = "rgba(150,185,220,0.45)"; ctx.lineWidth = 2;
    for (let y = 60 - 54 * 14; y < VH + 760; y += 54) { ctx.beginPath(); ctx.moveTo(-1200, y); ctx.lineTo(VW + 1200, y); ctx.stroke(); }
    ctx.strokeStyle = "rgba(221,90,68,0.55)"; ctx.beginPath(); ctx.moveTo(150, 0); ctx.lineTo(150, VH); ctx.stroke();
  }
  function noteScreen(ctx, x, y, w, h, lt) {
    const L = x + 30, R = x + w - 30;
    let yy = y + 90;
    const on = (a) => seg(lt, a, a + 0.6);
    text(ctx, "Launch sync", L, yy, F.serif(46), C.ink, { reveal: on(0.6) }); yy += 34;
    text(ctx, "Tue · 32 min · from recording", L, yy, F.sans(17, 500), C.inkSoft, { reveal: on(0.9), alpha: on(0.9) }); yy += 52;
    const head = (s, a) => { text(ctx, s, L, yy, F.sans(15, 600), C.red, { spacing: 2, alpha: on(a) }); yy += 30; };
    head("SUMMARY", 1.3);
    const lines = wrap(ctx, "The team agreed to ship v1 on Oct 14, starting with a 200-person beta.", F.sans(21, 400), w - 60);
    lines.forEach((ln, i) => { text(ctx, ln, L, yy, F.sans(21, 400), C.ink, { reveal: seg(lt, 1.5 + i * 0.35, 1.95 + i * 0.35) }); yy += 30; });
    yy += 22;
    head("DECISIONS", 2.6);
    [["Ship date: Oct 14", C.yellow, 3.0], ["Pricing: $4.99 a month", C.mint, 3.4]].forEach(([s, col, a]) => {
      ctx.font = F.sans(21, 500);
      const tw = ctx.measureText(s).width;
      const hp = easeOut(seg(lt, a + 0.4, a + 0.9));
      if (hp > 0) { ctx.fillStyle = col; ctx.globalAlpha = 0.9; ctx.beginPath(); ctx.roundRect(L + 20, yy - 22, (tw + 16) * hp, 30, 4); ctx.fill(); ctx.globalAlpha = 1; }
      text(ctx, "•  " + s, L, yy, F.sans(21, 500), C.ink, { reveal: on(a) }); yy += 38;
    });
    yy += 16;
    head("TO-DOS", 4.0);
    [["Pricing page", "Priya", 4.2, 6.2], ["Beta invites", "Sam", 4.5, 6.6], ["Launch post", "Mia", 4.8, 7.0]].forEach(([s, who, a, done]) => {
      const al = on(a);
      ctx.globalAlpha = al; ctx.strokeStyle = C.ink; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.roundRect(L, yy - 20, 24, 24, 5); ctx.stroke();
      const cp = seg(lt, done, done + 0.3);
      if (cp > 0) { ctx.strokeStyle = C.red; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(L + 4, yy - 8); ctx.lineTo(L + 10, yy - 1); if (cp > 0.4) ctx.lineTo(L + 10 + 14 * (cp - 0.4) / 0.6, yy - 1 - 22 * (cp - 0.4) / 0.6); ctx.stroke(); }
      ctx.globalAlpha = 1;
      text(ctx, s, L + 40, yy, F.sans(21, 500), C.ink, { reveal: al });
      text(ctx, "@" + who, R, yy, F.sans(17, 600), C.inkSoft, { align: "right", alpha: al });
      yy += 44;
    });
    yy += 12;
    text(ctx, "▸  Transcript · 32 min", L, yy, F.sans(18, 500), C.inkSoft, { alpha: on(5.2) });
  }
  function sceneNote(ctx, lt) {
    ruledPaperBg(ctx);
    const pw = 440, ph = 880, px = 1110, py = 70;
    const rise = easeOut(seg(lt, 0, 0.8));
    // strips from the meeting finish landing
    STRIPS.forEach((S, i) => {
      const q = seg(lt, i * 0.12, 0.7 + i * 0.12); if (q >= 1) return;
      const [x, y] = bez([200 + i * 300, 180 + (i % 2) * 520], [700, 200], [px + pw / 2, py + 300], easeInOut(q));
      ctx.save(); ctx.translate(x, y); ctx.scale(1 - q * 0.8, 1 - q * 0.8);
      ctx.font = F.hand(40); const w = ctx.measureText(S.s).width + 44;
      rect(ctx, -w / 2, -32, w, 64, S.c, 610 + i, { rough: 3 });
      text(ctx, S.s, 0, 12, F.hand(40), C.ink, { align: "center" });
      ctx.restore();
    });
    ctx.save(); ctx.translate(0, (1 - rise) * 500);
    phone(ctx, px, py, pw, ph, 700, (c, x, y, w, h) => noteScreen(c, x, y, w, h, lt));
    ctx.restore();
    // Mia, relaxed, coffee in hand
    const mp = easeOut(seg(lt, 0.3, 1.1));
    person(ctx, {
      x: lerp(-200, 520, mp), y: 1080 + 60, s: 1.45, seed: 560, skin: SKIN[0], shirt: C.mustard, hair: "#6b3a22", hairStyle: "bun", scarf: C.red,
      look: [16, 2], mouth: "smile", blink: lt % 3 < 0.12,
      arms: [{ sh: [60, -140], hand: [110, -170], mug: true }, { sh: [-60, -140], hand: [-80, -20] }],
    });
    mascot(ctx, px + pw + 20, py + ph - 120, 0.95, { rot: 10, wink: lt > 6.6 && lt < 7.4, bigSmile: true, wave: lt * 6 });
    caption(ctx, "Quolio wrote the rest:", lt, 1.4, 6.2, { y: 190, x: 560, size: 56 });
    caption(ctx, "summary, decisions, to-dos.", lt, 2.0, 5.6, { y: 300, x: 600, size: 56, rot: 1.2, bg: C.yellow });
  }

  // 5 · Night train, no signal — the note still opens instantly.
  function sceneTrain(ctx, lt) {
    nightSky(ctx, lt, 21);
    moon(ctx, 1080, 150, 64);
    hills(ctx, lt, 800, [C.navy3, "#28335e"], -lt * 25);
    const trackY = 880;
    rect(ctx, -20, trackY, VW + 40, 22, "#141a33", 801, { rough: 2 });
    const tx = lerp(-1300, 700, easeOut(seg(lt, 0, 3.2))) + seg(lt, 3.2, 7) * 120;
    const cars = [[0, C.red], [390, C.manila], [780, C.manila], [1170, C.manila]];
    cars.forEach(([ox, col], i) => {
      const x = tx - ox, y = trackY - 190 + Math.sin(lt * 18 + i) * 1.5;
      rrect(ctx, x, y, 370, 180, 18, col, 810 + i, { rough: 3 });
      for (let k = 0; k < 4; k++) {
        const wx = x + 26 + k * 86, wy = y + 30;
        rect(ctx, wx, wy, 64, 70, C.window, 820 + i * 5 + k, { rough: 1.5, shadow: false });
        if (i === 1 && k === 1) {
          // Mia in the window, lit by her phone
          ctx.save(); ctx.beginPath(); ctx.rect(wx, wy, 64, 70); ctx.clip();
          ctx.fillStyle = "#6b3a22"; ctx.beginPath(); ctx.arc(wx + 32, wy + 34, 20, 0, Math.PI * 2); ctx.fill();
          ctx.beginPath(); ctx.arc(wx + 34, wy + 12, 8, 0, Math.PI * 2); ctx.fill();
          ctx.fillStyle = SKIN[0]; ctx.beginPath(); ctx.arc(wx + 32, wy + 40, 16, 0, Math.PI * 2); ctx.fill();
          ctx.fillStyle = C.mustard; ctx.beginPath(); ctx.ellipse(wx + 32, wy + 72, 26, 16, 0, Math.PI, 0); ctx.fill();
          ctx.fillStyle = "rgba(255,255,255,0.8)"; ctx.fillRect(wx + 38, wy + 50, 10, 14);
          ctx.restore();
        }
      }
      [[x + 70, 0], [x + 300, 1]].forEach(([wx], k) => {
        circ(ctx, wx, trackY + 4, 26, C.ink, 840 + i * 3 + k, { shadow: false });
        ctx.save(); ctx.translate(wx, trackY + 4); ctx.rotate(lt * 8); ctx.strokeStyle = "#8a90a8"; ctx.lineWidth = 3;
        ctx.beginPath(); ctx.moveTo(-18, 0); ctx.lineTo(18, 0); ctx.moveTo(0, -18); ctx.lineTo(0, 18); ctx.stroke(); ctx.restore();
      });
    });
    // "no signal" badge
    const b = backOut(seg(lt, 2.2, 2.8));
    if (b > 0) {
      ctx.save(); ctx.translate(tx - 390 + 150, trackY - 330); ctx.scale(b, b); ctx.rotate(-0.05);
      rrect(ctx, -120, -44, 240, 88, 20, C.cream, 850, { rough: 2.5 });
      ctx.fillStyle = C.inkSoft;
      for (let k = 0; k < 4; k++) ctx.fillRect(-92 + k * 14, 10 - k * 9, 9, 10 + k * 9);
      ctx.strokeStyle = C.red; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(-98, 18); ctx.lineTo(-38, -30); ctx.stroke();
      text(ctx, "No signal", -20, 14, F.hand(40), C.ink);
      ctx.restore();
    }
    // inset: the note opens anyway
    const ip = backOut(seg(lt, 3.6, 4.3));
    if (ip > 0) {
      ctx.save(); ctx.translate(1520, 470); ctx.scale(ip, ip);
      circ(ctx, 0, 0, 270, C.paper2, 860, { blur: 30, dy: 10, rough: 3 });
      ctx.save(); ctx.rotate(-0.06);
      phone(ctx, -110, -200, 220, 400, 861, (c, x, y, w, h) => {
        const op = easeOut(seg(lt, 4.6, 4.9));
        if (op < 1) { c.fillStyle = C.ink; c.globalAlpha = 1 - op; c.fillRect(x, y, w, h); c.globalAlpha = 1; }
        c.globalAlpha = op;
        text(c, "Launch sync", x + 16, y + 60, F.serif(28), C.ink);
        text(c, "DECISIONS", x + 16, y + 100, F.sans(10, 600), C.red, { spacing: 1.5 });
        c.fillStyle = C.yellow; c.fillRect(x + 16, y + 110, 150, 20);
        text(c, "Ship date: Oct 14", x + 20, y + 125, F.sans(13, 500), C.ink);
        c.fillStyle = C.mint; c.fillRect(x + 16, y + 138, 160, 20);
        text(c, "Pricing: $4.99/mo", x + 20, y + 153, F.sans(13, 500), C.ink);
        text(c, "TO-DOS", x + 16, y + 196, F.sans(10, 600), C.red, { spacing: 1.5 });
        ["Pricing page", "Beta invites", "Launch post"].forEach((s, k) => {
          c.strokeStyle = C.ink; c.lineWidth = 1.5; c.strokeRect(x + 16, y + 210 + k * 30, 14, 14);
          text(c, s, x + 40, y + 222 + k * 30, F.sans(13, 500), C.ink);
        });
        c.globalAlpha = 1;
      });
      ctx.restore();
      const tp = seg(lt, 4.6, 5.0);
      if (tp > 0) {
        ctx.save(); ctx.rotate(0.08);
        rrect(ctx, 40, 150, 230, 70, 14, C.yellow, 870, { rough: 2 });
        text(ctx, "opens offline", 155, 197, F.hand(40), C.ink, { align: "center", reveal: tp });
        ctx.restore();
      }
      ctx.restore();
    }
    caption(ctx, "No signal? Her notes live right on her phone.", lt, 1.0, 5.8, { x: 760 });
  }

  // 6 · End card.
  function sceneEnd(ctx, lt, o = {}) {
    ruledPaperBg(ctx);
    const a = easeOut(seg(lt, 0.1, 0.9));
    logo(ctx, VW / 2, 250 - (1 - a) * 60, 230 * (0.85 + 0.15 * backOut(seg(lt, 0.1, 0.8))));
    mascot(ctx, VW / 2 + 520, 420, 1.1, { wave: lt * 6, bigSmile: true, blink: lt % 2.6 < 0.12, rot: 6 });
    ctx.globalAlpha = a;
    text(ctx, "Quolio", VW / 2, 570, F.serif(170), C.ink, { align: "center" });
    ctx.globalAlpha = 1;
    const line = o.tagline || "Be in the room. We'll take the notes.";
    ctx.font = F.hand(70);
    const lw = ctx.measureText(line).width;
    const hp = easeOut(seg(lt, 1.6, 2.3));
    ctx.fillStyle = C.yellow; ctx.globalAlpha = 0.85;
    ctx.beginPath(); ctx.roundRect(VW / 2 - lw / 2 - 12, 620, (lw + 24) * hp, 64, 6); ctx.fill(); ctx.globalAlpha = 1;
    text(ctx, line, VW / 2, 670, F.hand(70), C.ink, { align: "center", reveal: easeInOut(seg(lt, 0.8, 2.0)) });
    text(ctx, o.sub || "Meeting notes that write themselves  ·  iPhone, iPad & Mac  ·  coming soon", VW / 2, 790, F.sans(28, 500), C.inkSoft, { align: "center", alpha: seg(lt, 2.2, 2.8) });
  }

  // Spot · "Two seconds": ideas don't wait for loading screens.
  function speedLeft(ctx, lt) {
    const clock = Math.min(9, Math.floor(lt));
    rect(ctx, 0, 0, 900, 820, "#cfd3dd", 900, { rough: 4, blur: 20 });
    text(ctx, "The usual way", 450, 90, F.hand(60), C.inkSoft, { align: "center" });
    person(ctx, {
      x: 300, y: 820, s: 1.1, seed: 910, skin: SKIN[1], shirt: "#8a8fa3", hair: "#2b2230", hairStyle: "short",
      look: [16, 14], mouth: lt > 4 ? "frown" : "flat", blink: lt % 2.2 < 0.15, sweat: lt > 6,
      arms: [{ sh: [60, -140], hand: [150, -150] }, { sh: [-60, -140], hand: [-60, -10 + (Math.sin(lt * 10) > 0 ? -12 : 0)] }],
    });
    phone(ctx, 440, 420, 150, 270, 915, (c, x, y, w, h) => {
      c.fillStyle = "#e6e8ee"; c.fillRect(x, y, w, h);
      c.save(); c.translate(x + w / 2, y + h / 2); c.rotate(lt * 5); c.strokeStyle = C.inkSoft; c.lineWidth = 6; c.lineCap = "round";
      c.beginPath(); c.arc(0, 0, 26, 0, Math.PI * 1.5); c.stroke(); c.restore();
      text(c, "Loading…", x + w / 2, y + h / 2 + 70, F.sans(16, 500), C.inkSoft, { align: "center" });
    });
    rrect(ctx, 640, 150, 210, 110, 20, C.cream, 918, { rough: 2 });
    text(ctx, clock + "s", 745, 232, F.serif(84), C.red, { align: "center" });
    if (lt > 6.5) {
      ctx.strokeStyle = "rgba(60,64,80,0.5)"; ctx.lineWidth = 2; ctx.globalAlpha = seg(lt, 6.5, 7.5);
      for (let k = 0; k < 6; k++) { ctx.beginPath(); ctx.moveTo(900, 0); ctx.lineTo(900 - 170 * Math.cos(k * 0.3), 170 * Math.sin(k * 0.3 + 0.1)); ctx.stroke(); }
      for (let r = 40; r < 170; r += 36) { ctx.beginPath(); ctx.arc(900, 0, r, Math.PI / 2, Math.PI); ctx.stroke(); }
      ctx.globalAlpha = 1;
    }
  }
  function speedRight(ctx, lt) {
    rect(ctx, 0, 0, 900, 820, C.cream, 930, { rough: 4, blur: 20 });
    text(ctx, "Quolio", 450, 90, F.hand(60), C.ink, { align: "center" });
    const ready = lt > 1.2;
    person(ctx, {
      x: 300, y: 820, s: 1.1, seed: 560, skin: SKIN[0], shirt: C.mustard, hair: "#6b3a22", hairStyle: "bun", scarf: C.red,
      look: ready ? [14, 12] : [14, 8], mouth: "smile", blink: lt % 3 < 0.12,
      arms: [{ sh: [60, -140], hand: [150, -150] }, { sh: [-60, -140], hand: ready ? [-80, -250 + Math.sin(lt * 8) * 20] : [-60, -10] }],
    });
    phone(ctx, 440, 420, 150, 270, 935, (c, x, y, w, h) => {
      if (!ready) { c.fillStyle = C.ink; c.fillRect(x, y, w, h); return; }
      const op = easeOut(seg(lt, 1.2, 1.45));
      c.globalAlpha = op;
      text(c, "New idea", x + 12, y + 50, F.serif(24), C.ink);
      const lines = ["Pricing: try an", "annual plan", "→ ask Priya"];
      lines.forEach((s, k) => text(c, s, x + 12, y + 90 + k * 26, F.hand(24), C.ink, { reveal: seg(lt, 1.6 + k * 0.6, 2.2 + k * 0.6) }));
      c.globalAlpha = 1;
    });
    const tp = backOut(seg(lt, 1.3, 1.8));
    if (tp > 0) {
      ctx.save(); ctx.translate(745, 205); ctx.scale(tp, tp);
      rrect(ctx, -105, -55, 210, 110, 20, C.yellow, 938, { rough: 2 });
      text(ctx, "ready", 0, 24, F.serif(72), C.ink, { align: "center" });
      ctx.restore();
    }
    if (lt > 3) mascot(ctx, 760, 620, 0.9, { wave: lt * 6, bigSmile: true, rot: 8 });
  }
  function sceneSpeed(ctx, lt) {
    fullBg(ctx, C.navy);
    ctx.save(); ctx.translate(40, 60); ctx.rotate(-0.012); speedLeft(ctx, lt); ctx.restore();
    ctx.save(); ctx.translate(980, 60); ctx.rotate(0.012); speedRight(ctx, lt); ctx.restore();
    caption(ctx, "Ideas don't wait for loading screens.", lt, 2.4, 7.4, { y: 990, vy: 110 });
  }
  sceneSpeed.vertical = (ctx, lt) => {
    ctx.fillStyle = C.navy; ctx.fillRect(0, 0, 1080, 1920);
    ctx.fillStyle = grainPattern(ctx); ctx.fillRect(0, 0, 1080, 1920);
    ctx.save(); ctx.translate(112, 300); ctx.scale(0.95, 0.95); ctx.rotate(-0.012); speedLeft(ctx, lt); ctx.restore();
    ctx.save(); ctx.translate(112, 1105); ctx.scale(0.95, 0.95); ctx.rotate(0.012); speedRight(ctx, lt); ctx.restore();
    caption(ctx, "Ideas don't wait for loading screens.", lt, 2.4, 7.4, { vy: 95 });
  };

  // Vertical end card, laid out for a 1080×1920 screen.
  function sceneEndV(ctx, lt, o = {}) {
    ctx.fillStyle = C.cream; ctx.fillRect(0, 0, 1080, 1920);
    ctx.fillStyle = grainPattern(ctx); ctx.fillRect(0, 0, 1080, 1920);
    ctx.strokeStyle = "rgba(150,185,220,0.45)"; ctx.lineWidth = 2;
    for (let y = 60; y < 1920; y += 54) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(1080, y); ctx.stroke(); }
    ctx.strokeStyle = "rgba(221,90,68,0.55)"; ctx.beginPath(); ctx.moveTo(90, 0); ctx.lineTo(90, 1920); ctx.stroke();
    const a = easeOut(seg(lt, 0.1, 0.9));
    logo(ctx, 540, 480 - (1 - a) * 60, 300 * (0.85 + 0.15 * backOut(seg(lt, 0.1, 0.8))));
    mascot(ctx, 860, 1520, 1.2, { wave: lt * 6, bigSmile: true, blink: lt % 2.6 < 0.12, rot: 6 });
    ctx.globalAlpha = a;
    text(ctx, "Quolio", 540, 890, F.serif(220), C.ink, { align: "center" });
    ctx.globalAlpha = 1;
    // one sentence per line, but keep short sentences together while they fit
    const lines = [];
    for (const sent of (o.tagline || "Be in the room. We'll take the notes.").split(/(?<=\.)\s+/)) {
      const joined = lines.length ? lines[lines.length - 1] + " " + sent : sent;
      ctx.font = F.hand(88);
      if (lines.length && ctx.measureText(joined).width <= 900) lines[lines.length - 1] = joined; else lines.push(sent);
    }
    lines.forEach((ln, i) => {
      const y = 1030 + i * 110;
      ctx.font = F.hand(88);
      const lw = ctx.measureText(ln).width;
      const hp = easeOut(seg(lt, 1.6 + i * 0.25, 2.3 + i * 0.25));
      ctx.fillStyle = C.yellow; ctx.globalAlpha = 0.85;
      ctx.beginPath(); ctx.roundRect(540 - lw / 2 - 14, y - 64, (lw + 28) * hp, 80, 6); ctx.fill(); ctx.globalAlpha = 1;
      text(ctx, ln, 540, y, F.hand(88), C.ink, { align: "center", reveal: easeInOut(seg(lt, 0.8 + i * 0.5, 1.4 + i * 0.5)) });
    });
    const sub = wrap(ctx, o.sub || "Meeting notes that write themselves  ·  iPhone, iPad & Mac  ·  coming soon", F.sans(36, 500), 820);
    sub.forEach((ln, i) => text(ctx, ln.replace(/^·\s*/, ""), 540, 1300 + i * 54, F.sans(36, 500), C.inkSoft, { align: "center", alpha: seg(lt, 2.2, 2.8) }));
  }
  sceneEnd.vertical = (ctx, lt) => sceneEndV(ctx, lt);
  const SPEED_END = { tagline: "Open. Write. Done.", sub: "Opens in under 2 seconds — even offline  ·  coming soon" };
  function speedEnd(ctx, lt) { sceneEnd(ctx, lt, SPEED_END); }
  speedEnd.vertical = (ctx, lt) => sceneEndV(ctx, lt, SPEED_END);

  // Camera moves for the 9:16 cut: keyframes of [t, centreX, centreY, visibleWidth].
  function camPath(keys) {
    return (t) => {
      if (t <= keys[0][0]) return keys[0].slice(1);
      for (let i = 1; i < keys.length; i++) {
        if (t <= keys[i][0]) {
          const p = easeInOut((t - keys[i - 1][0]) / (keys[i][0] - keys[i - 1][0]));
          return [1, 2, 3].map((k) => lerp(keys[i - 1][k], keys[i][k], p));
        }
      }
      return keys[keys.length - 1].slice(1);
    };
  }
  sceneTown.vcam = camPath([[0, 360, 540, 720], [2.5, 620, 540, 720], [7, 1250, 560, 760]]);
  sceneScribblers.vcam = camPath([[0, 390, 470, 640], [2.0, 390, 470, 640], [2.8, 960, 470, 640], [4.2, 960, 470, 640], [5.0, 1530, 470, 640], [7, 1530, 470, 640]]);
  sceneMeeting.vcam = camPath([[0, 1330, 520, 660], [2.0, 1210, 540, 640], [3.4, 640, 520, 720], [7.4, 640, 520, 720], [8.3, 1450, 540, 660], [9.6, 1450, 540, 660], [10.8, 900, 470, 1000], [16, 940, 470, 1000]]);
  sceneNote.vcam = camPath([[0, 900, 540, 1000], [1.2, 1340, 520, 800], [8, 1340, 520, 800]]);
  sceneTrain.vcam = camPath([[0, 500, 620, 760], [3.2, 620, 620, 760], [4.0, 1420, 540, 760], [7, 1460, 540, 760]]);

  // ================= NOTEBOOK AD =================
  // Hand-drawn ink: strokes are point lists, revealed by total path length.
  function wobbleRect(x, y, w, h, seed) {
    const r = rng(seed), pts = [], j = () => (r() - 0.5) * 5;
    const edge = (ax, ay, bx, by) => { for (let i = 0; i <= 6; i++) pts.push([lerp(ax, bx, i / 6) + j(), lerp(ay, by, i / 6) + j()]); };
    edge(x, y, x + w, y); edge(x + w, y, x + w, y + h); edge(x + w, y + h, x, y + h); edge(x, y + h, x + 4, y - 3);
    return pts;
  }
  const INK = [
    wobbleRect(420, 300, 190, 110, 1),
    [[622, 355], [660, 352], [700, 356], [728, 355]], [[708, 338], [730, 355], [706, 372]],
    wobbleRect(740, 300, 200, 110, 2),
    [[430, 520], [470, 512], [520, 524], [570, 510], [620, 522], [680, 512]],
    (() => { const p = []; for (let i = 0; i <= 24; i++) { const a = -Math.PI / 2 + (i / 24) * Math.PI * 2.1; p.push([905 + Math.cos(a) * 42, 488 + Math.sin(a) * 34]); } return p; })(),
  ];
  const INK_LABELS = [["Free", 515, 368, 0.22], ["Pro · $4.99", 840, 368, 0.62], ["annual = 2 months free", 430, 495, 0.8], ["?", 905, 503, 0.97]];
  function strokeLen(st) { let L = 0; for (let i = 1; i < st.length; i++) L += Math.hypot(st[i][0] - st[i - 1][0], st[i][1] - st[i - 1][1]); return L; }
  const INK_TOTAL = INK.reduce((a, st) => a + strokeLen(st), 0);
  // Draw ink up to fraction p; strokes before `tint` (fraction) are recoloured, as when audio replays.
  function drawInk(ctx, p, tint) {
    let budget = p * INK_TOTAL, tip = null, done = 0;
    ctx.lineCap = "round"; ctx.lineJoin = "round"; ctx.lineWidth = 4.5;
    for (const st of INK) {
      if (budget <= 0) break;
      const L = strokeLen(st);
      ctx.strokeStyle = (done + L / 2) / INK_TOTAL < tint ? C.brand : C.ink;
      ctx.beginPath(); ctx.moveTo(st[0][0], st[0][1]);
      let left = budget;
      for (let i = 1; i < st.length && left > 0; i++) {
        const a = st[i - 1], b = st[i], d = Math.hypot(b[0] - a[0], b[1] - a[1]);
        const f = Math.min(1, left / d);
        tip = [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f];
        ctx.lineTo(tip[0], tip[1]); left -= d;
      }
      ctx.stroke(); budget -= L; done += L;
    }
    INK_LABELS.forEach(([str, x, y, at]) => {
      const r = seg(p, at, at + 0.14);
      if (r > 0) text(ctx, str, x, y, F.hand(40), tint > at + 0.1 ? C.brand : C.ink, { align: str.length < 12 ? "center" : "left", reveal: r });
    });
    return p < 1 ? tip : null;
  }

  function tablet(ctx, x, y, w, h, seed, screen) {
    rrect(ctx, x, y, w, h, 46, C.ink, seed, { rough: 2, blur: 26, dy: 12 });
    ctx.save();
    const m = 26, sx = x + m, sy = y + m, sw = w - 2 * m, sh = h - 2 * m;
    ctx.beginPath(); ctx.roundRect(sx, sy, sw, sh, 24); ctx.clip();
    ctx.fillStyle = C.cream; ctx.fillRect(sx, sy, sw, sh);
    ctx.fillStyle = grainPattern(ctx); ctx.fillRect(sx, sy, sw, sh);
    if (screen) screen(ctx, sx, sy, sw, sh);
    ctx.restore();
  }

  // Loose scraps: the "before" of the notebook ad.
  const SCRAPS = [
    { x: 330, y: 250, w: 260, h: 220, c: C.yellow, rot: -8, kind: "note", s: "call Sam re: beta" },
    { x: 700, y: 170, w: 340, h: 250, c: C.cream, rot: 5, kind: "sketch" },
    { x: 1150, y: 230, w: 330, h: 240, c: "#e9ecf3", rot: -4, kind: "table" },
    { x: 1500, y: 470, w: 280, h: 230, c: C.cream, rot: 7, kind: "todo" },
    { x: 180, y: 560, w: 280, h: 170, c: C.pink, rot: 6, kind: "note", s: "idea: annual plan?" },
  ];
  function scrap(ctx, S, i) {
    rect(ctx, 0, 0, S.w, S.h, S.c, 1200 + i, { rough: 3, blur: 12 });
    ctx.strokeStyle = C.ink; ctx.lineWidth = 3; ctx.lineCap = "round";
    if (S.kind === "note") text(ctx, S.s, 22, S.h / 2 + 12, F.hand(40), C.ink);
    if (S.kind === "sketch") {
      ctx.strokeRect(34, 60, 100, 70); ctx.strokeRect(200, 60, 100, 70);
      ctx.beginPath(); ctx.moveTo(140, 95); ctx.lineTo(192, 95); ctx.moveTo(180, 84); ctx.lineTo(194, 95); ctx.lineTo(180, 106); ctx.stroke();
      text(ctx, "pricing??", 40, 200, F.hand(40), C.inkSoft);
    }
    if (S.kind === "table") {
      ctx.strokeStyle = C.inkSoft; ctx.lineWidth = 2;
      for (let r = 0; r <= 4; r++) { ctx.beginPath(); ctx.moveTo(24, 40 + r * 42); ctx.lineTo(S.w - 24, 40 + r * 42); ctx.stroke(); }
      for (let c = 0; c <= 3; c++) { ctx.beginPath(); ctx.moveTo(24 + c * ((S.w - 48) / 3), 40); ctx.lineTo(24 + c * ((S.w - 48) / 3), 208); ctx.stroke(); }
      text(ctx, "Plans.xlsx", 24, 28, F.sans(18, 600), C.inkSoft);
    }
    if (S.kind === "todo") {
      ["draft page", "ask Priya", "share"].forEach((t, k) => { ctx.strokeRect(26, 44 + k * 56, 24, 24); text(ctx, t, 66, 66 + k * 56, F.hand(38), C.ink); });
    }
  }
  function sceneScraps(ctx, lt) {
    fullBg(ctx, "#e7d7b6");
    SCRAPS.forEach((S, i) => {
      const inP = easeOut(seg(lt, 0.1 + i * 0.18, 0.9 + i * 0.18));
      const fx = S.x + Math.sin(lt * 1.3 + i) * 10, fy = S.y + Math.cos(lt * 1.1 + i * 2) * 8 - (1 - inP) * 900;
      ctx.save(); ctx.translate(fx, fy); ctx.rotate((S.rot + Math.sin(lt * 1.7 + i) * 2) * Math.PI / 180);
      scrap(ctx, S, i); ctx.restore();
    });
    const look = Math.sin(lt * 2.4) * 16;
    person(ctx, {
      x: 960, y: 1150, s: 1.35, seed: 560, skin: SKIN[0], shirt: C.mustard, hair: "#6b3a22", hairStyle: "bun", scarf: C.red,
      look: [look, -6], mouth: "frown", blink: lt % 2.7 < 0.12, sweat: lt > 2,
      arms: [{ sh: [60, -140], hand: [120, -250] }, { sh: [-60, -140], hand: [-120, -250] }],
    });
    caption(ctx, "Sketches here. Lists there. Tables… somewhere.", lt, 0.9, 3.8, { vy: 1500 });
  }

  const NB = { x: 340, y: 110, w: 1240, h: 820 };
  function notebookScreen(ctx, x, y, w, h, lt) {
    const on = (a) => seg(lt, a, a + 0.5);
    // sidebar strip
    ctx.fillStyle = "rgba(30,36,51,0.05)"; ctx.fillRect(x, y, 26, h);
    text(ctx, "Pricing workshop", 400, 196, F.serif(46), C.ink, { reveal: on(0.3) });
    text(ctx, "Thu · 38 min · handwriting + audio", 402, 232, F.sans(17, 500), C.inkSoft, { alpha: on(0.6) });
    const inkP = easeInOut(seg(lt, 0.8, 4.0));
    const tint = seg(lt, 4.7, 7.0);
    const tip = drawInk(ctx, inkP, tint);
    if (tip) pencil(ctx, tip[0] + 18, tip[1] - 30, 0.5, 0.9);
    // audio chip that replays the ink
    const chipA = on(3.8);
    if (chipA > 0) {
      ctx.globalAlpha = chipA;
      const pressed = lt > 4.4 && lt < 4.6;
      rrect(ctx, 420, 560, 250, 58, 29, pressed ? C.brandDeep : C.brand, 1300, { rough: 1.5, blur: 8 });
      ctx.fillStyle = "#fff"; ctx.beginPath(); ctx.moveTo(446, 574); ctx.lineTo(466, 589); ctx.lineTo(446, 604); ctx.fill();
      for (let k = 0; k < 14; k++) {
        const hh = 6 + 18 * Math.abs(Math.sin(k * 1.7 + (tint > 0 && tint < 1 ? lt * 8 : 0)));
        ctx.fillStyle = k / 14 < tint ? "#fff" : "rgba(255,255,255,0.5)"; ctx.fillRect(484 + k * 9, 589 - hh / 2, 5, hh);
      }
      text(ctx, "0:42", 650, 597, F.sans(18, 600), "#fff", { align: "right" });
      ctx.globalAlpha = 1;
    }
    if (lt > 4.35 && lt < 4.9) {
      const q = seg(lt, 4.35, 4.9);
      ctx.strokeStyle = C.brand; ctx.globalAlpha = 1 - q; ctx.lineWidth = 4;
      ctx.beginPath(); ctx.arc(456, 589, 20 + q * 50, 0, Math.PI * 2); ctx.stroke(); ctx.globalAlpha = 1;
    }
    // divider
    ctx.strokeStyle = "rgba(30,36,51,0.12)"; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.moveTo(985, 260); ctx.lineTo(985, 860); ctx.stroke();
    // to-dos
    text(ctx, "TO-DO", 1015, 280, F.sans(15, 600), C.red, { spacing: 2, alpha: on(1.4) });
    [["Draft pricing page", 1.6, 8.2], ["Ask Priya about annual", 1.9, 8.6], ["Share with the team", 2.2, 9.0]].forEach(([t, a, done], k) => {
      const yy = 322 + k * 46, al = on(a);
      ctx.globalAlpha = al; ctx.strokeStyle = C.ink; ctx.lineWidth = 2.5;
      ctx.beginPath(); ctx.roundRect(1015, yy - 21, 24, 24, 5); ctx.stroke();
      const cp = seg(lt, done, done + 0.3);
      if (cp > 0) { ctx.strokeStyle = C.red; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(1019, yy - 9); ctx.lineTo(1025, yy - 2); if (cp > 0.4) ctx.lineTo(1025 + 14 * (cp - 0.4) / 0.6, yy - 2 - 22 * (cp - 0.4) / 0.6); ctx.stroke(); }
      ctx.globalAlpha = 1;
      text(ctx, t, 1055, yy, F.sans(21, 500), C.ink, { reveal: al });
    });
    // table
    text(ctx, "PLANS", 1015, 500, F.sans(15, 600), C.red, { spacing: 2, alpha: on(2.5) });
    const cols = [1015, 1175, 1305, 1440], rows = [["Plan", "Price", "Users"], ["Free", "$0", "1,200"], ["Pro", "$4.99", "180"], ["Annual", "$39.99", "—"]];
    rows.forEach((row, r) => {
      const al = r === 0 ? on(2.6) : on(7.4 + r * 0.35);
      const yy = 520 + r * 52;
      if (r === 0) { ctx.globalAlpha = al; ctx.fillStyle = C.paper2; ctx.fillRect(1015, yy, 460, 52); ctx.globalAlpha = 1; }
      ctx.strokeStyle = "rgba(30,36,51,0.18)"; ctx.lineWidth = 1.5; ctx.globalAlpha = Math.max(on(2.6), 0);
      ctx.strokeRect(1015, yy, 460, 52); ctx.globalAlpha = 1;
      row.forEach((cell, c) => text(ctx, cell, cols[c] + 14, yy + 34, F.sans(20, r === 0 ? 600 : 400), r === 0 ? C.inkSoft : C.ink, { alpha: al }));
    });
  }
  function sceneNotebook(ctx, lt) {
    ruledPaperBg(ctx);
    // scraps arrive and become blocks
    SCRAPS.forEach((S, i) => {
      const q = seg(lt, i * 0.08, 0.7 + i * 0.08); if (q >= 1) return;
      const e = easeInOut(q);
      ctx.save(); ctx.translate(lerp(S.x, 960, e), lerp(S.y, 520, e)); ctx.scale(1 - e * 0.85, 1 - e * 0.85); ctx.rotate(S.rot * Math.PI / 180);
      scrap(ctx, S, i); ctx.restore();
    });
    const rise = easeOut(seg(lt, 0, 0.7));
    ctx.save(); ctx.translate(0, (1 - rise) * 600);
    tablet(ctx, NB.x, NB.y, NB.w, NB.h, 1400, (c, x, y, w, h) => notebookScreen(c, x, y, w, h, lt));
    ctx.restore();
    mascot(ctx, NB.x + NB.w + 10, NB.y + NB.h - 110, 0.9, { rot: 10, bigSmile: true, wink: lt > 9 && lt < 9.6, wave: lt * 6 });
    caption(ctx, "Handwriting, text, to-dos and tables — one page.", lt, 0.5, 3.8, { y: 1010 });
    caption(ctx, "Tap your ink to hear what was said.", lt, 4.4, 3.0, { y: 1010 });
    caption(ctx, "Your plans sit right beside your thinking.", lt, 7.6, 2.8, { y: 1010 });
  }

  // Notion export → pages in Quolio.
  function sceneImport(ctx, lt) {
    ruledPaperBg(ctx);
    const fp = easeOut(seg(lt, 0, 0.8));
    ctx.save(); ctx.translate(lerp(-500, 520, fp), 560); ctx.rotate(-0.06 + seg(lt, 0.9, 1.3) * -0.12);
    paper(ctx, [[-230, -170], [-80, -170], [-50, -200], [230, -200], [230, 170], [-230, 170]], C.manila, 1500, { rough: 3, blur: 16 });
    text(ctx, "Notion export.zip", 0, 30, F.hand(52), C.ink, { align: "center" });
    ctx.restore();
    const titles = ["Roadmap", "Meeting notes", "Reading list", "Hiring plan", "Launch checklist"];
    titles.forEach((t, i) => {
      const q = easeInOut(seg(lt, 1.1 + i * 0.22, 1.9 + i * 0.22)); if (q <= 0) return;
      const [x, y] = bez([540, 480], [900, 150 + i * 30], [1260, 250 + i * 118], q);
      ctx.save(); ctx.translate(x, y); ctx.rotate((1 - q) * (i % 2 ? 0.3 : -0.3));
      rect(ctx, -260, -46, 520, 92, C.cream, 1510 + i, { rough: 2.5, blur: 8 });
      ctx.fillStyle = C.brand; ctx.fillRect(-236, -10, 20, 20);
      text(ctx, t, -200, 12, F.sans(28, 500), C.ink);
      text(ctx, "imported", 236, 10, F.sans(18, 500), C.inkSoft, { align: "right" });
      ctx.restore();
    });
    const b = backOut(seg(lt, 2.9, 3.4));
    if (b > 0) {
      ctx.save(); ctx.translate(1260, 870); ctx.scale(b, b); ctx.rotate(-0.04);
      rrect(ctx, -200, -44, 400, 88, 20, C.yellow, 1520, { rough: 2 });
      text(ctx, "214 pages · offline", 0, 14, F.hand(46), C.ink, { align: "center" });
      ctx.restore();
    }
    caption(ctx, "Coming from Notion? Bring every page with you.", lt, 0.4, 3.6, { y: 1010, x: 700 });
  }
  const NB_END = { tagline: "Ink, blocks and tables. One notebook.", sub: "Handwriting, audio, to-dos & tables  ·  iPhone, iPad & Mac  ·  coming soon" };
  function notebookEnd(ctx, lt) { sceneEnd(ctx, lt, NB_END); }
  notebookEnd.vertical = (ctx, lt) => sceneEndV(ctx, lt, NB_END);
  sceneScraps.vcam = camPath([[0, 960, 520, 980], [4.5, 960, 540, 980]]);
  sceneNotebook.vcam = camPath([[0, 960, 520, 1300], [1.0, 690, 440, 700], [7.2, 690, 440, 700], [7.9, 1250, 540, 700], [10.5, 1250, 540, 700]]);
  sceneImport.vcam = camPath([[0, 620, 560, 820], [1.2, 900, 520, 1000], [4, 1200, 560, 900]]);

  // ================= FILMS =================
  const FILMS = {
    hero: {
      title: "What Mia heard", duration: 50,
      segs: [
        [sceneTown, 0, 7], [sceneScribblers, 7, 14], [sceneMeeting, 14, 30],
        [sceneNote, 30, 38], [sceneTrain, 38, 45], [sceneEnd, 45, 50],
      ],
    },
    listen: {
      title: "Pencil down", duration: 22,
      segs: [[sceneMeeting, 0, 9.5, 6.5], [sceneNote, 9.5, 17], [sceneEnd, 17, 22]],
    },
    notebook: {
      title: "One notebook", duration: 24,
      segs: [[sceneScraps, 0, 4.5], [sceneNotebook, 4.5, 15], [sceneImport, 15, 19], [notebookEnd, 19, 24]],
    },
    speed: {
      title: "Two seconds", duration: 15,
      segs: [[sceneSpeed, 0, 10], [speedEnd, 10, 15]],
    },
  };
  const XFADE = 0.6;

  let bufA = null;
  function buffer(w, h) {
    if (!bufA || bufA.width !== w || bufA.height !== h) { bufA = document.createElement("canvas"); bufA.width = w; bufA.height = h; }
    return bufA;
  }
  function drawSeg(ctx, s, t, W, H) {
    const [fn, a, , offset = 0] = s;
    const lt = t - a + offset;
    ctx.save();
    if (!VERT) { ctx.setTransform(W / VW, 0, 0, H / VH, 0, 0); fn(ctx, lt); ctx.restore(); return; }
    ctx.setTransform(W / 1080, 0, 0, H / 1920, 0, 0);
    CAPS = [];
    if (fn.vertical) fn.vertical(ctx, lt);
    else {
      const [cx, cy, w] = fn.vcam(lt), k = 1080 / w;
      ctx.save(); ctx.translate(540, 840); ctx.scale(k, k); ctx.translate(-cx, -cy); fn(ctx, lt); ctx.restore();
    }
    const caps = CAPS; CAPS = null;
    captionsV(ctx, caps);
    ctx.restore();
  }
  function render(ctx, filmId, t, W, H) {
    const film = FILMS[filmId];
    BOIL = Math.floor(t * 6) % 3;
    VERT = H > W;
    t = clamp(t, 0, film.duration - 1e-3);
    const i = film.segs.findIndex(([, a, b]) => t >= a && t < b);
    const s = film.segs[i];
    drawSeg(ctx, s, t, W, H);
    const into = t - s[1];
    if (i > 0 && into < XFADE) {
      const b = buffer(W, H), bc = b.getContext("2d");
      bc.clearRect(0, 0, W, H);
      drawSeg(bc, film.segs[i - 1], t, W, H);
      ctx.save(); ctx.globalAlpha = 1 - easeInOut(into / XFADE); ctx.drawImage(b, 0, 0); ctx.restore();
    }
    // open from and close to ink
    const edge = Math.min(seg(t, 0, 0.6), 1 - seg(t, film.duration - 0.6, film.duration));
    if (edge < 1) { ctx.save(); ctx.globalAlpha = 1 - edge; ctx.fillStyle = C.navyDeep; ctx.fillRect(0, 0, W, H); ctx.restore(); }
  }

  // ================= POSTERS =================
  // Stills for social: a scene frame framed by a camera, with a headline card and logo tag.
  const SCENES = { town: sceneTown, scribblers: sceneScribblers, meeting: sceneMeeting, note: sceneNote, train: sceneTrain,
    speed: sceneSpeed, scraps: sceneScraps, notebook: sceneNotebook, import: sceneImport, end: sceneEnd };
  function paperScreen(ctx, W, H, U) {
    ctx.fillStyle = C.cream; ctx.fillRect(0, 0, W, H);
    ctx.fillStyle = grainPattern(ctx); ctx.fillRect(0, 0, W, H);
    ctx.strokeStyle = "rgba(150,185,220,0.45)"; ctx.lineWidth = 2 * U;
    for (let y = 60 * U; y < H; y += 54 * U) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(W, y); ctx.stroke(); }
    ctx.strokeStyle = "rgba(221,90,68,0.55)"; ctx.beginPath(); ctx.moveTo(90 * U, 0); ctx.lineTo(90 * U, H); ctx.stroke();
  }
  function posterPanel(ctx, W, H, U, p) {
    const left = p.pos === "left";
    const pw = left ? W * 0.42 : W * 0.88, pad = 44 * U;
    const ts = (left ? 66 : 78) * U * (p.scale || 1), ks = 40 * U, ss = 27 * U;
    const tl = wrap(ctx, p.title, F.serif(ts), pw - 2 * pad);
    const sl = p.sub ? wrap(ctx, p.sub, F.sans(ss, 500), pw - 2 * pad) : [];
    const h = pad * 2 + (p.kicker ? ks * 1.3 : 0) + tl.length * ts * 1.04 + (sl.length ? 16 * U + sl.length * ss * 1.45 : 0);
    const x = left ? W * 0.05 : (W - pw) / 2;
    const y = left ? (H - h) / 2 : p.pos === "bottom" ? H - h - H * 0.045 : H * 0.045;
    ctx.save(); ctx.translate(x + pw / 2, y + h / 2); ctx.rotate((p.rot ?? -0.6) * Math.PI / 180); ctx.translate(-pw / 2, -h / 2);
    rect(ctx, 0, 0, pw, h, C.cream, 1700 + Math.round(ts), { rough: 4 * U, step: 14 * U, blur: 18 * U, dy: 6 * U });
    let yy = pad;
    if (p.kicker) { text(ctx, p.kicker, pad, yy + ks * 0.85, F.hand(ks), C.brand); yy += ks * 1.3; }
    tl.forEach((ln) => { yy += ts * 1.04; text(ctx, ln, pad, yy - ts * 0.2, F.serif(ts), C.ink); });
    if (sl.length) { yy += 16 * U; sl.forEach((ln) => { yy += ss * 1.45; text(ctx, ln, pad, yy - ss * 0.35, F.sans(ss, 500), C.inkSoft); }); }
    ctx.restore();
  }
  function posterLogo(ctx, W, H, U, pos) {
    const s = 58 * U, tw = 190 * U, th = s + 30 * U;
    const x = pos.includes("l") ? W * 0.04 : W - W * 0.04 - tw, y = pos.includes("t") ? H * 0.04 : H - H * 0.04 - th;
    rrect(ctx, x, y, tw, th, 14 * U, C.cream, 1790, { rough: 2 * U, blur: 12 * U, dy: 4 * U });
    logo(ctx, x + 15 * U + s / 2, y + th / 2, s);
    text(ctx, "Quolio", x + 30 * U + s, y + th / 2 + 14 * U, F.serif(42 * U), C.ink);
  }
  function posterCTA(ctx, W, H, U, c) {
    logo(ctx, W / 2, H * 0.29, Math.min(W, H) * 0.3);
    text(ctx, "Quolio", W / 2, H * 0.29 + Math.min(W, H) * 0.15 + 150 * U, F.serif(150 * U), C.ink, { align: "center" });
    const lines = wrap(ctx, c.tagline, F.hand(62 * U), W * 0.8);
    let y = H * 0.29 + Math.min(W, H) * 0.15 + 250 * U;
    lines.forEach((ln) => {
      ctx.font = F.hand(62 * U); const lw = ctx.measureText(ln).width;
      ctx.fillStyle = C.yellow; ctx.globalAlpha = 0.85; ctx.beginPath(); ctx.roundRect(W / 2 - lw / 2 - 12 * U, y - 50 * U, lw + 24 * U, 64 * U, 6 * U); ctx.fill(); ctx.globalAlpha = 1;
      text(ctx, ln, W / 2, y, F.hand(62 * U), C.ink, { align: "center" }); y += 80 * U;
    });
    if (c.button) {
      ctx.font = F.sans(32 * U, 600); const bw = ctx.measureText(c.button).width + 80 * U;
      rrect(ctx, W / 2 - bw / 2, y + 30 * U, bw, 80 * U, 40 * U, C.brand, 1795, { rough: 1.5 * U, blur: 14 * U });
      text(ctx, c.button, W / 2, y + 81 * U, F.sans(32 * U, 600), "#fff", { align: "center" });
    }
  }
  function poster(ctx, W, H, spec) {
    const U = Math.min(W, H) / 1000;
    BOIL = spec.boil ?? 1; VERT = true; CAPS = [];
    ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0);
    const fn = spec.scene && SCENES[spec.scene];
    if (fn && spec.vertical && fn.vertical) { ctx.save(); ctx.scale(W / 1080, H / 1920); fn.vertical(ctx, spec.lt); ctx.restore(); }
    else if (fn) {
      const [cx, cy, w] = spec.cam, k = W / w;
      ctx.save(); ctx.translate(W / 2, H * (spec.anchor ?? 0.5)); ctx.scale(k, k); ctx.translate(-cx, -cy); fn(ctx, spec.lt); ctx.restore();
    } else paperScreen(ctx, W, H, U);
    CAPS = null; VERT = false;
    if (spec.panel) posterPanel(ctx, W, H, U, spec.panel);
    if (spec.cta) posterCTA(ctx, W, H, U, spec.cta);
    if (spec.logo !== false) posterLogo(ctx, W, H, U, spec.logoPos || (spec.panel?.pos === "bottom" ? "tr" : "br"));
    ctx.restore();
  }

  const ready = Promise.all([
    "600 40px Caveat", "700 40px Caveat", "400 40px 'Instrument Serif'", "500 20px Inter", "600 20px Inter", "400 20px Inter",
  ].map((f) => document.fonts.load(f))).then(() => document.fonts.ready);

  window.QuolioFilms = { FILMS, render, poster, ready, VW, VH };
})();
