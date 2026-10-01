import fs from 'node:fs';
import path from 'node:path';
const dir=path.dirname(new URL(import.meta.url).pathname);
const assets=fs.readFileSync(path.join(dir,'assets.json'),'utf8');
const js=fs.readFileSync(path.join(dir,'animation.js'),'utf8');
const html=`<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="#F6F3EC">
<title>Quolio — Opening animation</title>
<style>
:root{color-scheme:light;--quolio-background:#F6F3EC}
*{box-sizing:border-box}html,body{margin:0;width:100%;height:100%;overflow:hidden}
body{background:var(--quolio-background);font:14px system-ui,sans-serif;color:#3C3835}
main{width:100%;height:100%;display:grid;place-items:center}
canvas{display:block;width:100%;height:100%;max-width:1100px;max-height:1100px;object-fit:contain}
button{position:fixed;right:24px;bottom:24px;padding:10px 17px;border:1px solid #cfc8ba;border-radius:100px;background:#faf8f3;color:#575045;font:inherit;cursor:pointer}
button:hover{background:#eee9de}button:focus-visible{outline:3px solid #86BBE0;outline-offset:4px}
[hidden]{display:none!important}.render button{display:none!important}
</style>
</head>
<body>
<main aria-label="Quolio opening animation"><canvas id="quolio-canvas" role="img" aria-label="An open notebook turns its pages, closes with a wink and a happy smile, and reveals the Quolio logo."></canvas></main>
<button id="replay" type="button" hidden>Replay</button>
<script id="quolio-assets" type="application/json">${assets.replaceAll('</','<\\/')}</script>
<script>${js}</script>
</body></html>`;
fs.writeFileSync(path.join(dir,'../../InstantNotes/Views/Launch/QuolioSplash.html'),html);
console.log('Built InstantNotes/Views/Launch/QuolioSplash.html');
