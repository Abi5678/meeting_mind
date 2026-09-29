// Export a film to MP4: node render.mjs <film> [fps] [--vertical] [--stills=t1,t2,...]
// Social stills:        node render.mjs --posters
// Drives the canvas frame by frame in headless Chrome, pipes PNGs into ffmpeg.
import puppeteer from "puppeteer-core";
import ffmpegPath from "ffmpeg-static";
import { spawn } from "node:child_process";
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const [film = "hero", fpsArg] = process.argv.slice(2).filter((a) => !a.startsWith("--"));
const stillsArg = process.argv.find((a) => a.startsWith("--stills="));
const vertical = process.argv.includes("--vertical");
const [VW, VH] = vertical ? [1080, 1920] : [1920, 1080];
const tag = vertical ? `${film}-vertical` : film;
const fps = Number(fpsArg) || 30;
const out = path.join(here, "out"); mkdirSync(out, { recursive: true });

const browser = await puppeteer.launch({
  executablePath: "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  args: ["--allow-file-access-from-files"],
});
const page = await browser.newPage();
await page.setViewport({ width: VW, height: VH });
await page.goto("file://" + path.join(here, "films/player.html") + `?film=${film}&export=1${vertical ? "&v=1" : ""}`, { waitUntil: "networkidle0" });
const duration = await page.evaluate(() => window.filmReady);
const canvas = await page.$("canvas");

if (process.argv.includes("--posters")) {
  const dir = path.join(out, "social"); mkdirSync(dir, { recursive: true });
  const ids = await page.evaluate(() => QUOLIO_POSTERS.map((p) => p.id));
  for (const id of ids) {
    const data = await page.evaluate((id) => {
      const p = QUOLIO_POSTERS.find((x) => x.id === id), c = document.createElement("canvas");
      [c.width, c.height] = p.size;
      QuolioFilms.poster(c.getContext("2d"), c.width, c.height, p);
      return c.toDataURL("image/png");
    }, id);
    writeFileSync(path.join(dir, id + ".png"), Buffer.from(data.split(",")[1], "base64"));
    console.log("poster", id);
  }
  await browser.close();
  process.exit(0);
}

if (stillsArg) {
  for (const t of stillsArg.split("=")[1].split(",").map(Number)) {
    await page.evaluate((t) => renderFrame(t), t);
    await canvas.screenshot({ path: path.join(out, `${tag}-${t}.png`) });
  }
} else {
  const file = path.join(out, `quolio-${tag}.mp4`);
  const ff = spawn(ffmpegPath, ["-y", "-f", "image2pipe", "-framerate", String(fps), "-i", "-",
    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", "-preset", "medium", "-movflags", "+faststart", file], { stdio: ["pipe", "ignore", "inherit"] });
  const n = Math.round(duration * fps);
  for (let i = 0; i < n; i++) {
    await page.evaluate((t) => renderFrame(t), i / fps);
    const buf = await canvas.screenshot({ type: "png" });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    if (i % (fps * 5) === 0) console.log(`${tag}: ${Math.round((i / n) * 100)}%`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
  console.log("wrote", file);
}
await browser.close();
