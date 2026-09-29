// Social stills: size, which film scene/moment to frame, and the copy on top.
// Rendered with `node render.mjs --posters` into out/social/.
window.QUOLIO_POSTERS = [
  // X / Twitter — 1600×900
  { id: "x-1-be-in-the-room", size: [1600, 900], scene: "meeting", lt: 15.4, cam: [960, 470, 1640], anchor: 0.64,
    panel: { pos: "top", kicker: "Meeting notes that write themselves", title: "Be in the room. We'll take the notes.", scale: 0.85 } },
  { id: "x-2-written-up", size: [1600, 900], scene: "note", lt: 7.8, cam: [1180, 480, 1500], anchor: 0.53,
    panel: { pos: "left", kicker: "One tap of record", title: "Your meeting, already written up.", sub: "Summary, decisions and to-dos with owners." }, logoPos: "tr" },
  { id: "x-3-two-seconds", size: [1600, 900], scene: "speed", lt: 6, cam: [960, 470, 1920], anchor: 0.42,
    panel: { pos: "bottom", title: "Opens in under 2 seconds. Even offline.", scale: 0.8 }, logoPos: "tr" },
  { id: "x-4-one-notebook", size: [1600, 900], scene: "notebook", lt: 10, cam: [960, 520, 1560], anchor: 0.44,
    panel: { pos: "bottom", title: "Ink, blocks and tables. One notebook.", scale: 0.8 }, logoPos: "tr" },

  // LinkedIn — 1200×1200
  { id: "li-1-stop-choosing", size: [1200, 1200], scene: "meeting", lt: 15.4, cam: [960, 500, 1300], anchor: 0.66,
    panel: { pos: "top", kicker: "For people who live in meetings", title: "Stop choosing between listening and taking notes." } },
  { id: "li-2-decisions-owners", size: [1200, 1200], scene: "note", lt: 7.8, cam: [1330, 520, 1100], anchor: 0.74,
    panel: { pos: "top", kicker: "After every meeting", title: "A note with the decisions — and who owns what.", scale: 0.9 } },
  { id: "li-3-one-page", size: [1200, 1200], scene: "notebook", lt: 10, cam: [960, 520, 1300], anchor: 0.68,
    panel: { pos: "top", kicker: "The notebook part", title: "Your handwriting, to-dos and tables on one page.", scale: 0.9 } },

  // Instagram carousel (also the LinkedIn document carousel) — 1080×1350
  { id: "ig-carousel-1", size: [1080, 1350], scene: "town", lt: 4.2, cam: [760, 520, 1000], anchor: 0.42,
    panel: { pos: "bottom", kicker: "A short story about meetings  →", title: "In a town that never stopped taking notes…" } },
  { id: "ig-carousel-2", size: [1080, 1350], scene: "scribblers", lt: 5.2, cam: [960, 470, 1840], anchor: 0.36,
    panel: { pos: "bottom", title: "…everyone wrote everything down, and missed what was said." } },
  { id: "ig-carousel-3", size: [1080, 1350], scene: "meeting", lt: 15.4, cam: [940, 500, 1200], anchor: 0.4,
    panel: { pos: "bottom", title: "Mia hit record, put her pencil down, and listened." } },
  { id: "ig-carousel-4", size: [1080, 1350], scene: "note", lt: 7.8, cam: [1330, 560, 820], anchor: 0.44,
    panel: { pos: "bottom", title: "Quolio wrote the rest.", sub: "Summary, decisions, to-dos, owners." } },
  { id: "ig-carousel-5", size: [1080, 1350], scene: null, logo: false,
    cta: { tagline: "Be in the room. We'll take the notes.", button: "Join the waitlist · link in bio" } },

  // Instagram feed single + stories
  { id: "ig-feed-notebook", size: [1080, 1350], scene: "notebook", lt: 10, cam: [960, 520, 1320], anchor: 0.62,
    panel: { pos: "top", kicker: "Handwriting + audio + blocks", title: "One notebook for ink, to-dos and tables." } },
  { id: "ig-story-1", size: [1080, 1920], scene: "meeting", lt: 15.4, cam: [1180, 520, 760], anchor: 0.42,
    panel: { pos: "bottom", kicker: "New app · coming soon", title: "Be in the room. We'll take the notes." }, logoPos: "tr" },
  { id: "ig-story-2", size: [1080, 1920], scene: "speed", lt: 6, vertical: true, logoPos: "bl",
    panel: { pos: "top", title: "Ideas don't wait for loading screens.", scale: 0.6 } },
];
