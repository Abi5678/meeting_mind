// Original soundtrack for the Quolio films, synthesized from scratch (no samples,
// no licensed music): a music-box theme in F major plus paper/pencil/train sound
// effects cued to each scene. Writes out/<film>.wav, then muxes it into
// out/quolio-<film>.mp4 when that video exists.
//   node audio.mjs <film|all>
import { writeFileSync, existsSync, renameSync, unlinkSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";
import ffmpegPath from "ffmpeg-static";

const here = path.dirname(fileURLToPath(import.meta.url));
const out = path.join(here, "out");
const SR = 44100;

// Scene layout per film — mirrors FILMS in films/film.js: [scene, start, end, offset]
const FILMS = {
  hero: { duration: 50, segs: [["town", 0, 7], ["scribblers", 7, 14], ["meeting", 14, 30], ["note", 30, 38], ["train", 38, 45], ["end", 45, 50]] },
  listen: { duration: 22, segs: [["meeting", 0, 9.5, 6.5], ["note", 9.5, 17], ["end", 17, 22]] },
  notebook: { duration: 24, segs: [["scraps", 0, 4.5], ["notebook", 4.5, 15], ["import", 15, 19], ["end", 19, 24]] },
  speed: { duration: 15, segs: [["speed", 0, 10], ["end", 10, 15]] },
};

// ---------- helpers ----------
function rng(seed) {
  let a = seed >>> 0;
  return () => { a = (a + 0x6d2b79f5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const mtof = (m) => 440 * Math.pow(2, (m - 69) / 12);

function makeBus(n) { return { L: new Float32Array(n), R: new Float32Array(n) }; }
function put(bus, i, v, pan) {
  if (i < 0 || i >= bus.L.length) return;
  const a = (pan + 1) * Math.PI / 4;
  bus.L[i] += v * Math.cos(a); bus.R[i] += v * Math.sin(a);
}

// ---------- instruments ----------
// Music box: bright inharmonic partials with fast-decaying overtones.
function musicBox(bus, t, freq, vol, pan = 0, decay = 1.1) {
  const parts = [[1, 1, 1], [2, 0.32, 2.2], [3.01, 0.1, 3.5], [4.2, 0.06, 5]];
  const n = Math.floor(decay * 4 * SR), s0 = Math.floor(t * SR);
  for (let k = 0; k < n; k++) {
    const x = k / SR, att = Math.min(1, x / 0.003);
    let v = 0;
    for (const [m, a, d] of parts) v += a * Math.sin(2 * Math.PI * freq * m * x) * Math.exp(-x * d / decay);
    put(bus, s0 + k, v * vol * att, pan);
  }
}
// Soft pad: detuned harmonic stack with slow swell.
function pad(bus, t, freqs, dur, vol) {
  const n = Math.floor((dur + 1.2) * SR), s0 = Math.floor(t * SR);
  for (let k = 0; k < n; k++) {
    const x = k / SR;
    const env = Math.min(1, x / 0.6) * (x > dur ? Math.exp(-(x - dur) * 3) : 1);
    let v = 0;
    freqs.forEach((f, j) => {
      for (let h = 1; h <= 4; h++) {
        v += Math.sin(2 * Math.PI * f * h * x * 1.0015) / (h * h) + Math.sin(2 * Math.PI * f * h * x * 0.9985) / (h * h);
      }
    });
    put(bus, s0 + k, v * env * vol / freqs.length, Math.sin(x * 0.7) * 0.3);
  }
}
function bass(bus, t, freq, vol) {
  const n = Math.floor(2 * SR), s0 = Math.floor(t * SR);
  for (let k = 0; k < n; k++) {
    const x = k / SR;
    const v = (Math.sin(2 * Math.PI * freq * x) + 0.25 * Math.sin(4 * Math.PI * freq * x)) * Math.exp(-x * 1.6) * Math.min(1, x / 0.01);
    put(bus, s0 + k, v * vol, 0);
  }
}

// ---------- sound effects ----------
const noiseR = rng(99);
// Band-passed noise whose centre sweeps — paper through air.
function whoosh(bus, t, dur, vol, pan = 0, f0 = 400, f1 = 2400) {
  const n = Math.floor(dur * SR), s0 = Math.floor(t * SR);
  let lp = 0, bp = 0;
  for (let k = 0; k < n; k++) {
    const p = k / n, fc = f0 + (f1 - f0) * p, g = 2 * Math.PI * fc / SR;
    const w = noiseR() * 2 - 1;
    lp += g * (w - lp); bp += g * (lp - bp);
    const env = Math.sin(Math.PI * p) ** 2;
    put(bus, s0 + k, (lp - bp) * env * vol * 3, pan + (p - 0.5) * 0.6);
  }
}
// Pencil on paper: bright noise in quick, uneven strokes.
function scribble(bus, t, dur, vol, pan, seed) {
  const r = rng(seed), n = Math.floor(dur * SR), s0 = Math.floor(t * SR);
  let hp = 0, prev = 0, stroke = 0, rate = 7;
  for (let k = 0; k < n; k++) {
    if (k % 2205 === 0) rate = 6 + r() * 6;
    const x = k / SR;
    const w = r() * 2 - 1;
    hp = 0.92 * (hp + w - prev); prev = w;
    stroke = Math.pow(Math.abs(Math.sin(Math.PI * rate * x)), 3);
    const edge = Math.min(1, x / 0.1, (dur - x) / 0.2);
    put(bus, s0 + k, hp * stroke * edge * vol, pan);
  }
}
// Short percussive click with a low thump (taps, set-downs, clacks).
function click(bus, t, vol, pan = 0, thumpHz = 140, bright = 0.5) {
  const n = Math.floor(0.12 * SR), s0 = Math.floor(t * SR);
  for (let k = 0; k < n; k++) {
    const x = k / SR;
    const v = (noiseR() * 2 - 1) * Math.exp(-x * 400) * bright + Math.sin(2 * Math.PI * thumpHz * x * (1 - x * 2)) * Math.exp(-x * 45);
    put(bus, s0 + k, v * vol, pan);
  }
}
// Crumpled paper: a burst of tiny crackles.
function crumple(bus, t, vol, pan, seed) {
  const r = rng(seed);
  for (let i = 0; i < 14; i++) click(bus, t + r() * 0.35, vol * (0.3 + r() * 0.7), pan, 2000 + r() * 2000, 1.4);
}
function tick(bus, t, vol, pan) {
  const n = Math.floor(0.03 * SR), s0 = Math.floor(t * SR);
  for (let k = 0; k < n; k++) { const x = k / SR; put(bus, s0 + k, Math.sin(2 * Math.PI * 2600 * x) * Math.exp(-x * 220) * vol, pan); }
}
const chime = (bus, t, vol, pan = 0) => { [0, 7, 12, 16].forEach((st, i) => musicBox(bus, t + i * 0.07, mtof(77 + st), vol * (1 - i * 0.12), pan, 1.8)); };

// ---------- per-scene cues (local seconds) ----------
const CUES = {
  town(sfx) {
    for (let i = 0; i < 7; i++) whoosh(sfx, 0.6 + i * 0.55, 1.4, 0.05, -0.6 + i * 0.2, 600, 1800);
  },
  scribblers(sfx) {
    scribble(sfx, 0.4, 6.4, 0.07, -0.55, 11);
    scribble(sfx, 0.7, 6.1, 0.06, 0, 12);
    scribble(sfx, 1.0, 5.8, 0.06, 0.55, 13);
    for (let i = 0; i < 3; i++) for (let k = 0; k < 5; k++) { const bt = 1.4 + k * 1.1 + i * 0.3; if (bt < 7) crumple(sfx, bt, 0.05, -0.55 + i * 0.55, 40 + i * 9 + k); }
  },
  meeting(sfx) {
    click(sfx, 1.75, 0.35, 0.25, 110, 0.3);                     // phone set on the table
    click(sfx, 2.35, 0.2, 0.25, 900, 0.2);                      // tap
    musicBox(sfx, 2.5, mtof(84), 0.12, 0.25, 0.6);              // record: two-note blip up
    musicBox(sfx, 2.62, mtof(91), 0.12, 0.25, 0.8);
    click(sfx, 8.95, 0.3, 0.45, 180, 0.6);                      // pencil set down
    [8.4, 9.7, 11.0, 12.3, 13.6].forEach((t, i) => {
      whoosh(sfx, t, 1.5, 0.09, -0.4 + i * 0.1, 500, 2600);
      musicBox(sfx, t + 1.45, mtof(96 + [0, 2, 4, 7, 9][i]), 0.05, 0.25, 0.5); // strip lands in the phone
    });
  },
  note(sfx) {
    whoosh(sfx, 0, 0.8, 0.06, 0.2, 800, 3000);
    [3.4, 3.8].forEach((t) => whoosh(sfx, t, 0.45, 0.05, 0.3, 2500, 5000)); // highlighter
    [6.2, 6.6, 7.0].forEach((t, i) => { tick(sfx, t, 0.08, 0.3); musicBox(sfx, t + 0.05, mtof(88 + i * 3), 0.08, 0.3, 0.7); });
  },
  train(sfx) {
    for (let t = 0.2; t < 7.2; t += 0.46) {
      const v = Math.min(1, t / 2) * 0.22;
      click(sfx, t, v, -0.1, 70, 0.25); click(sfx, t + 0.12, v * 0.8, 0.1, 80, 0.25);
    }
    musicBox(sfx, 2.2, mtof(81), 0.08, -0.3, 0.6); musicBox(sfx, 2.36, mtof(76), 0.08, -0.3, 0.8); // no signal
    whoosh(sfx, 3.55, 0.6, 0.07, 0.5, 400, 2000);                  // inset opens
    chime(sfx, 4.6, 0.07, 0.5);                                      // note opens anyway
  },
  end(sfx) {
    whoosh(sfx, 0.05, 0.6, 0.05, 0, 500, 2000);
    chime(sfx, 0.25, 0.1, 0);
    whoosh(sfx, 1.6, 0.6, 0.04, 0.2, 2500, 5000);
  },
  scraps(sfx) {
    for (let i = 0; i < 5; i++) whoosh(sfx, 0.1 + i * 0.18, 0.9, 0.06, -0.6 + i * 0.3, 700, 2200);
  },
  notebook(sfx) {
    for (let i = 0; i < 5; i++) whoosh(sfx, i * 0.08, 0.7, 0.04, 0, 1500, 600);
    scribble(sfx, 0.8, 3.2, 0.08, -0.25, 21);                       // pencil drawing the diagram
    click(sfx, 4.4, 0.2, -0.3, 900, 0.2);                           // tap the audio chip
    musicBox(sfx, 4.5, mtof(84), 0.1, -0.3, 0.6); musicBox(sfx, 4.62, mtof(88), 0.1, -0.3, 0.8);
    [7.75, 8.1, 8.45].forEach((t) => whoosh(sfx, t, 0.3, 0.03, 0.4, 2000, 4000)); // table rows
    [8.2, 8.6, 9.0].forEach((t, i) => { tick(sfx, t, 0.08, 0.4); musicBox(sfx, t + 0.05, mtof(88 + i * 3), 0.08, 0.4, 0.7); });
  },
  import(sfx) {
    whoosh(sfx, 0.0, 0.8, 0.07, -0.5, 400, 1600);
    for (let i = 0; i < 5; i++) whoosh(sfx, 1.1 + i * 0.22, 0.8, 0.05, -0.2 + i * 0.15, 900, 3000);
    chime(sfx, 2.95, 0.08, 0.4);
  },
  speed(sfx) {
    for (let s = 1; s <= 9; s++) tick(sfx, s, 0.09, -0.6);
    click(sfx, 1.15, 0.2, 0.55, 900, 0.2);
    chime(sfx, 1.3, 0.09, 0.55);
  },
};

// Music intensity per scene (0 sparse · 1 arpeggio · 2 full), in local seconds.
const LEVELS = {
  town: [[0, 0]], scraps: [[0, 1]], notebook: [[0, 1], [4.4, 2]], import: [[0, 2]], scribblers: [[0, 1]], meeting: [[0, 1], [8.8, 2]], note: [[0, 2]], train: [[0, 1]], speed: [[0, 1]], end: [[0, 3]],
};

// ---------- compose ----------
function compose(id) {
  const film = FILMS[id];
  const n = Math.floor((film.duration + 0.2) * SR);
  const music = makeBus(n + 4 * SR), sfx = makeBus(n + 4 * SR);

  for (const s of film.segs) {
    const [name, a, b, off = 0] = s;
    const scoped = makeBus(n + 4 * SR);
    CUES[name](scoped);
    // shift the scene's cues to film time and keep only those inside the segment
    const shift = Math.round((a - off) * SR), from = Math.floor(a * SR), to = Math.floor((b + 0.6) * SR);
    for (let k = 0; k < scoped.L.length; k++) {
      const g = k + shift;
      if (g < from - 0.3 * SR || g >= to || g >= sfx.L.length) continue;
      sfx.L[g] += scoped.L[k]; sfx.R[g] += scoped.R[k];
    }
  }
  const levelAt = (t) => {
    for (const s of film.segs) {
      const [name, a, b, off = 0] = s;
      if (t >= a && t < b) { let l = 0; for (const [lt, v] of LEVELS[name]) if (t - a + off >= lt) l = v; return l; }
    }
    return 3;
  };

  // F major: I – vi – IV – V, 84 bpm
  const beat = 60 / 84, bar = beat * 4;
  const chords = [[53, 57, 60], [50, 53, 57], [46, 50, 53], [48, 52, 55]];
  const scale = [65, 67, 69, 72, 74, 77, 79, 81];
  const r = rng(2026);
  const endStart = film.segs.find((s) => s[0] === "end")?.[1] ?? film.duration;
  let mel = 3;
  for (let b = 0; b * bar < endStart - 0.2; b++) {
    const t0 = b * bar, ch = chords[b % 4];
    const lvl = levelAt(t0 + 0.01);
    if (lvl >= 2) { pad(music, t0, ch.map((m) => mtof(m)), bar, 0.035); bass(music, t0, mtof(ch[0] - 12), 0.16); bass(music, t0 + beat * 2, mtof(ch[0] - 12), 0.1); }
    for (let i = 0; i < 8; i++) {
      const t = t0 + i * beat / 2;
      if (t >= endStart - 0.1) break;
      const l = levelAt(t);
      const arp = [ch[0] + 12, ch[1] + 12, ch[2] + 12, ch[1] + 24][i % 4];
      if (l === 0 && i % 2 === 0) musicBox(music, t, mtof(arp + 12), 0.09, (i % 4) / 2 - 0.75, 1.4);
      if (l >= 1) musicBox(music, t, mtof(arp + (i % 2 ? 12 : 0)), l === 1 ? 0.075 : 0.065, ((i % 4) - 1.5) * 0.3, 0.9);
      if (l >= 2 && i % 2 === 0 && r() < 0.75) {
        mel = Math.max(0, Math.min(scale.length - 1, mel + Math.round((r() - 0.5) * 3)));
        musicBox(music, t, mtof(scale[mel] + 12), 0.1, 0.1, 1.3);
      }
    }
  }
  // closing chord on the end card: rolled F major with a low root
  [41, 53, 57, 60, 65, 69, 72].forEach((m, i) => musicBox(music, endStart + 0.2 + i * 0.06, mtof(m + 12), 0.1, (i - 3) * 0.15, 2.2));
  bass(music, endStart + 0.2, mtof(41), 0.18);

  // reverb (Schroeder: 4 combs + 2 allpasses per side)
  const reverb = (bus, wet) => {
    const res = makeBus(bus.L.length);
    [[bus.L, res.L, 0], [bus.R, res.R, 23]].forEach(([src, dst, sp]) => {
      const combs = [1557, 1617, 1491, 1422].map((d) => ({ buf: new Float32Array(d + sp), i: 0, f: 0 }));
      for (let k = 0; k < src.length; k++) {
        let acc = 0;
        for (const c of combs) { const y = c.buf[c.i]; c.f = y * 0.8 + c.f * 0.2; c.buf[c.i] = src[k] + c.f * 0.82; c.i = (c.i + 1) % c.buf.length; acc += y; }
        dst[k] = acc / 4;
      }
      for (const d of [556 + sp, 441 + sp]) {
        const buf = new Float32Array(d); let i = 0;
        for (let k = 0; k < dst.length; k++) { const b = buf[i], x = dst[k]; const y = -x + b; buf[i] = x + b * 0.5; i = (i + 1) % d; dst[k] = y; }
      }
    });
    for (let k = 0; k < bus.L.length; k++) { bus.L[k] += res.L[k] * wet; bus.R[k] += res.R[k] * wet; }
  };
  reverb(music, 0.45); reverb(sfx, 0.18);

  // mix, fade, normalize
  const L = new Float32Array(n), R = new Float32Array(n);
  let peak = 0;
  for (let k = 0; k < n; k++) {
    const t = k / SR;
    const fade = Math.min(1, t / 0.4, (film.duration - t) / 1.4);
    L[k] = (music.L[k] + sfx.L[k]) * Math.max(0, fade);
    R[k] = (music.R[k] + sfx.R[k]) * Math.max(0, fade);
    peak = Math.max(peak, Math.abs(L[k]), Math.abs(R[k]));
  }
  const g = 0.89 / peak;
  const pcm = Buffer.alloc(44 + n * 4);
  pcm.write("RIFF", 0); pcm.writeUInt32LE(36 + n * 4, 4); pcm.write("WAVEfmt ", 8);
  pcm.writeUInt32LE(16, 16); pcm.writeUInt16LE(1, 20); pcm.writeUInt16LE(2, 22); pcm.writeUInt32LE(SR, 24);
  pcm.writeUInt32LE(SR * 4, 28); pcm.writeUInt16LE(4, 32); pcm.writeUInt16LE(16, 34); pcm.write("data", 36); pcm.writeUInt32LE(n * 4, 40);
  for (let k = 0; k < n; k++) {
    pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, L[k] * g)) * 32767), 44 + k * 4);
    pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, R[k] * g)) * 32767), 46 + k * 4);
  }
  const wav = path.join(out, `quolio-${id}.wav`);
  writeFileSync(wav, pcm);
  console.log("wrote", wav);

  for (const mp4 of [`quolio-${id}.mp4`, `quolio-${id}-vertical.mp4`].map((f) => path.join(out, f))) {
    if (!existsSync(mp4)) continue;
    const tmp = mp4.replace(/\.mp4$/, ".tmp.mp4");
    const res = spawnSync(ffmpegPath, ["-y", "-v", "error", "-i", mp4, "-i", wav, "-map", "0:v", "-map", "1:a",
      "-c:v", "copy", "-af", "loudnorm=I=-16:TP=-1.5:LRA=11", "-ar", "44100", "-c:a", "aac", "-b:a", "192k", "-shortest", "-movflags", "+faststart", tmp], { stdio: "inherit" });
    if (res.status === 0) { renameSync(tmp, mp4); console.log("muxed", mp4); }
    else if (existsSync(tmp)) unlinkSync(tmp);
  }
}

const arg = process.argv[2] || "all";
for (const id of arg === "all" ? Object.keys(FILMS) : [arg]) compose(id);
