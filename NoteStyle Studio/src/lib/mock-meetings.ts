export type Meeting = {
  id: string;
  title: string;
  date: string; // ISO
  duration: string;
  participants: string[];
  tag: "product" | "design" | "sales" | "1:1" | "sync";
  transcript: { t: string; speaker: string; text: string }[];
  summary: string[];
  decisions: string[];
  actions: { who: string; what: string; due?: string; done?: boolean }[];
  email: { to: string; subject: string; body: string };
};

export const meetings: Meeting[] = [
  {
    id: "m-01",
    title: "Q3 Roadmap — Meeting Mind kickoff",
    date: "2026-07-08T10:00:00Z",
    duration: "48m",
    participants: ["Abishek", "Priya", "Sam", "Lena"],
    tag: "product",
    transcript: [
      { t: "00:00", speaker: "Abishek", text: "Alright, thanks for jumping on. Goal today is to lock the MVP scope for Meeting Mind and figure out what ships in three weeks." },
      { t: "00:22", speaker: "Priya", text: "I think the core loop is: record, transcribe on-device, and get a summary with action items. Everything else is nice-to-have." },
      { t: "01:05", speaker: "Sam", text: "Agreed. I'd cut Notion sync entirely for v1. It's a rabbit hole and nobody has asked for it yet." },
      { t: "02:18", speaker: "Lena", text: "From a design side — the calmer we make this, the better. It should feel like a notebook, not a dashboard." },
      { t: "03:40", speaker: "Abishek", text: "Good. Let's commit: whisper.cpp locally, Gemini flash for the summary, SwiftData for storage. No backend." },
      { t: "05:12", speaker: "Priya", text: "One risk — the first-launch model download is 60 megs. We should show progress and let people pick base vs small." },
    ],
    summary: [
      "MVP scope confirmed: local recording, on-device transcription via whisper.cpp, Gemini for summary + actions.",
      "No backend, no Notion sync, no payments in v1.",
      "Design direction: notebook feel — calm, paper, minimal chrome.",
      "First-launch model download flow needs a progress UI and a base/small selector.",
    ],
    decisions: [
      "Ship without Notion integration; revisit in v1.1.",
      "Default Whisper model: base.en-q5_1 (60 MB).",
      "Store meetings locally with SwiftData; audio in Documents/Recordings/.",
      "Use Gemini 3 Flash via direct REST with a JSON schema response.",
    ],
    actions: [
      { who: "Priya", what: "Wireframe the first-launch model download flow", due: "Fri", done: true },
      { who: "Sam", what: "Prototype whisper.cpp xcframework integration", due: "Wed" },
      { who: "Lena", what: "Explore paper/ruled-line UI directions in Figma", due: "Thu" },
      { who: "Abishek", what: "Draft Gemini response schema for summary + actions", due: "Tue" },
    ],
    email: {
      to: "team@meetingmind.app",
      subject: "Recap — Q3 Roadmap kickoff",
      body:
        "Hi all,\n\nQuick recap from this morning's kickoff:\n\n• MVP scope is locked: local recording, on-device Whisper transcription, Gemini for summary + actions. No backend, no Notion, no payments in v1.\n• Default Whisper model will be base.en-q5_1 with an in-app selector for small.en.\n• Design direction is a calm notebook feel — Lena is exploring in Figma.\n\nOwners and due dates in the action items below. Shout if anything looks off.\n\n— Abishek",
    },
  },
  {
    id: "m-02",
    title: "Design review — paper canvas",
    date: "2026-07-07T15:30:00Z",
    duration: "31m",
    participants: ["Lena", "Abishek"],
    tag: "design",
    transcript: [
      { t: "00:00", speaker: "Lena", text: "I've been pulling references from Notability, Field Notes and Muji notebooks. The through-line is: warm paper, thin ruled lines, one accent color." },
      { t: "01:14", speaker: "Abishek", text: "Love it. Let's keep the accent red — matches the margin rule on legal pads." },
    ],
    summary: [
      "Reference set: Notability, Field Notes, Muji.",
      "Direction: warm cream paper, thin ruled lines, single red accent.",
    ],
    decisions: ["Accent color = margin red.", "Use ruled paper only in the transcript view."],
    actions: [
      { who: "Lena", what: "Finalize paper texture and ruled-line spacing", due: "Mon" },
    ],
    email: {
      to: "lena@meetingmind.app",
      subject: "Design review notes",
      body: "Lena — sign-off on the notebook direction. Ruled paper for transcript view only, red accent throughout. Ship it.",
    },
  },
  {
    id: "m-03",
    title: "1:1 — Sam",
    date: "2026-07-06T09:00:00Z",
    duration: "22m",
    participants: ["Abishek", "Sam"],
    tag: "1:1",
    transcript: [
      { t: "00:00", speaker: "Abishek", text: "How's the whisper.cpp integration going? Any surprises?" },
      { t: "00:08", speaker: "Sam", text: "Prebuilt xcframework is clean. Metal is on by default. Real-time factor is around 0.4x on my iPhone 15." },
    ],
    summary: ["Whisper integration is on track.", "Realtime factor ~0.4x on iPhone 15 with Metal."],
    decisions: ["Stick with prebuilt xcframework — no source build."],
    actions: [{ who: "Sam", what: "Benchmark small.en on older devices", due: "Fri" }],
    email: {
      to: "sam@meetingmind.app",
      subject: "1:1 notes",
      body: "Sam — nice progress on Whisper. Benchmark small.en on an iPhone 12 before Friday and share numbers.",
    },
  },
  {
    id: "m-04",
    title: "Sales sync — pilot outreach",
    date: "2026-07-03T14:00:00Z",
    duration: "27m",
    participants: ["Abishek", "Priya", "Jordan"],
    tag: "sales",
    transcript: [
      { t: "00:00", speaker: "Jordan", text: "I've got twelve design studios interested in a private beta." },
    ],
    summary: ["12 studios interested in private beta.", "Jordan to send NDA + onboarding doc."],
    decisions: ["Cap private beta at 15 teams."],
    actions: [{ who: "Jordan", what: "Send NDA + onboarding to interested studios", due: "Next Mon" }],
    email: {
      to: "jordan@meetingmind.app",
      subject: "Private beta — next steps",
      body: "Jordan — cap the beta at 15 teams. Send NDA + onboarding to the twelve studios by Monday.",
    },
  },
  {
    id: "m-05",
    title: "Weekly product sync",
    date: "2026-06-30T11:00:00Z",
    duration: "44m",
    participants: ["Abishek", "Priya", "Sam", "Lena", "Jordan"],
    tag: "sync",
    transcript: [
      { t: "00:00", speaker: "Priya", text: "Standing agenda: shipped, shipping, stuck." },
    ],
    summary: ["Standard weekly cadence.", "Two items stuck on model download UX."],
    decisions: ["Move model picker into onboarding, not Settings."],
    actions: [
      { who: "Priya", what: "Move model picker into onboarding flow", due: "Wed" },
      { who: "Lena", what: "Design onboarding steps 1–3", due: "Thu" },
    ],
    email: {
      to: "team@meetingmind.app",
      subject: "Weekly sync recap",
      body: "Team — moving the model picker into onboarding. Priya + Lena own it this week.",
    },
  },
];

export function formatDate(iso: string) {
  const d = new Date(iso);
  return d.toLocaleString(undefined, {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

export function relativeDay(iso: string) {
  const d = new Date(iso);
  const now = new Date();
  const days = Math.floor((now.getTime() - d.getTime()) / 86400000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  if (days < 7) return `${days} days ago`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}
