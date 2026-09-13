# Instant Notes — Native iOS "Notion but fast + offline" (Core MVP)

## Context

Evolve `/Users/abishek/meeting_mind` into **Instant Notes**: a native iOS notes app whose wedge is speed (< 2 s cold launch vs Notion's reported 8–12 s), full offline operation, Notion migration, AI auto-organize, and simple databases — plus the differentiator no competitor ships: **meetings that become notes automatically**. Meeting Mind is not abandoned; its record → whisper.cpp transcribe → Gemini analyze pipeline is absorbed as this app's flagship feature. Single user, no backend, no sync in v1.

**User's confirmed choices (2026-07-09):** One app (Meeting Mind absorbed) · local-only v1, sync is a v1.1 decision · **Notion-style block editor** · native iOS · on-device whisper.cpp · Gemini free key (`gemini-3-flash-preview`).

**Current state (verified):**
- `Packages/MeetingMindKit` built and green (51 tests): `GeminiClient` (REST + `responseSchema` + 429/5xx retry, **live-verified on the free tier**), `PromptBuilder`, `ChunkPlanner`, `MarkdownExporter`.
- `NoteStyle Studio/` is a React design reference only (warm cream paper, ruled lines, red margin accent — a calm notebook identity that positions well against Notion's gray sprawl). None of its code ships.
- Signing still blocked: 0 codesigning identities (Apple ID sign-in in Xcode pending), no simulator runtimes installed, iPhone 12 Pro paired but offline.
- A free personal team — once it exists — **cannot** use CloudKit, push, IAP, or TestFlight. Those phases gate on the $99/yr Apple Developer account; installs also expire weekly until then.

## Headline decisions

| Area | Choice | Why |
|---|---|---|
| Product | One app: notes core + meeting capture | Differentiator vs Craft/Obsidian/Capacities; MeetingMindKit carries over unchanged |
| Editor | **Notion-style blocks on TextKit 2**: ONE `UITextView`, block = paragraph + custom attributes, custom `NSTextLayoutFragment` for block chrome (drag handle, toggle arrow, checkbox), attachment view providers for images | A single first responder keeps native selection, undo, keyboard, and scroll behavior. Per-block-UITextView collection views are where block editors go to die. **Fallback if the 2-week spike fails: markdown + rich attachments (Bear model)** |
| Block model | `Block` (id, type, indent, inline runs) owned by `Note`; the editor is a projection of the model. MVP block set: paragraph, h1–h3, bulleted, numbered, todo, toggle, quote, callout, code, divider, image | Small enough to ship, big enough to cover what Notion exports actually contain |
| Data | SwiftData, **CloudKit-shaped from day one** (all attributes optional or defaulted, no `.unique`, optional relationships with inverses) even though v1 is local-only | Sync becomes a configuration flip, not a data migration, when the paid account lands |
| Search | Derived `plainText` per note, updated on save; `#Predicate` + `localizedStandardContains`; FTS5 deferred | Searching rich block content directly is painful; denormalize instead |
| Databases | `Table` / `Column` (text, number, date, checkbox, select) / `Row` (JSON-encoded values keyed by column id) / saved views (filter + sort). Table UI only in MVP | "Simple databases" is the promise — EAV-via-JSON avoids dynamic SwiftData schemas |
| Notion import | **Export-ZIP import** (Markdown + CSV), parser lives in Kit, host-testable. NOT the OAuth API in v1 | API OAuth needs a token-exchange server (client secret can't ship in the app) and rate-limited crawls; the export ZIP is offline, complete, and maps cleanly to blocks. API-based "one-click" import = the Import Pro upsell later |
| AI | Gemini flash (existing client) for summarize / auto-tag, **on demand, queued and throttled**; `NLEmbedding` (on-device, works on iPhone 12 Pro) for related-notes suggestions | Free tier ≈ 10–15 req/min, a few hundred/day — a 2,000-page import must never fire 2,000 calls. Apple Foundation Models framework needs iPhone 15 Pro+, untestable on this device — post-MVP |
| Meetings | Meeting Mind phases absorbed intact: AVAudioRecorder → mono AAC m4a, whisper.cpp v1.9.1 xcframework behind an actor, ChunkPlanner windows, Gemini analyze → output is a **note** (summary paragraphs, decision blocks, todo blocks with owner, transcript inside a toggle) | The pipeline is already de-risked at the Kit layer; meeting output as blocks makes it editable like any other note |
| Monetization | StoreKit 2, gated on the paid account: Free (unlimited notes, 3 databases, basic AI) / Pro $4.99/mo or $39.99/yr / "Notion Import Pro" one-time | Limit enforcement is local, no server. Nothing before the $99 account exists |
| Speed gates | Cold launch < 2 s and 1,000-block editing at 60 fps **measured on the iPhone 12 Pro** | The wedge is a number, so it's a test — on the slowest device we own |
| Project gen | XcodeGen `project.yml`, app target `InstantNotes`, repo stays `~/meeting_mind` | Renaming the directory is cosmetic; do it at App Store submission. Same Info.plist keys as meeting_note.md plus mic/background-audio for meetings |
| Concurrency / testing | Swift 6, default-MainActor isolation, whisper behind an actor; all pure logic in `MeetingMindKit`, `swift test` on the Mac | Same discipline that already caught real bugs (ChunkPlanner runt-tail) |

## Repository layout (delta from today)

```
meeting_mind/
├── project.yml, .gitignore, Scripts/            # per meeting_note.md (fetch-whisper, build, install-device)
├── Vendor/whisper.xcframework/                  # gitignored, fetched
├── Packages/MeetingMindKit/                     # EXISTS — grows:
│   └── Sources/MeetingMindKit/
│       ├── Gemini/…                             # done, live-verified
│       ├── ChunkPlanner.swift                   # done
│       ├── MarkdownExporter.swift               # done; gains a blocks→markdown path
│       ├── Blocks/{Block,InlineRun,BlockDocument}.swift        # pure model + plainText projection
│       └── NotionImport/{ExportArchive,MarkdownBlockParser,CSVTableParser}.swift
├── InstantNotes/
│   ├── App/InstantNotesApp.swift
│   ├── Models/{Note,Tag,Table,Column,Row,MeetingRecord}.swift  # SwiftData, CloudKit-shaped
│   ├── Editor/{BlockTextView,BlockLayoutFragments,BlockCommands,DragReorder}.swift   # the big one
│   ├── Audio/{RecorderService,AudioDecoder}.swift              # from meeting_note.md Phase 3
│   ├── Transcription/{WhisperContext,TranscriptionService,ModelManager}.swift        # Phase 4
│   ├── Analysis/AnalysisService.swift
│   ├── Import/NotionImportCoordinator.swift
│   ├── Support/KeychainHelper.swift
│   └── Views/{NoteListView,EditorView,TableView,RecordView,ImportView,SettingsView}.swift
└── NoteStyle Studio/                            # design reference only, never built
```

## Phases

### Phase 0 — Manual prerequisites (user)
- Sign into Apple ID in Xcode (Settings → Accounts) — CLI cannot create the personal team; **this is what unblocks every UI phase.**
- iPhone: Developer Mode on, cable, trust the Mac.
- Decide paid-account timing: not needed until Phase 9, but TestFlight/IAP/CloudKit are impossible without it.

### Phase 1 — Scaffold + prove signing/device install (unchanged gate)
Identical to meeting_note.md Phase 1: `project.yml` (target `InstantNotes`), hello-world build, `devicectl` install + launch.
**Verify:** app launches on the iPhone. **Fallback:** `xcodebuild -downloadPlatform iOS` (~8 GB) and develop against the simulator.

### Phase 2 — Kit: block model + Notion parsers (**unblocked today — start regardless of Phase 0/1**)
- `Block`, `InlineRun`, `BlockDocument` (ordering, indent/nesting rules, plainText projection for search).
- `MarkdownBlockParser`: CommonMark subset + Notion quirks (`[ ]` todos, toggles as nested lists, callout emoji prefixes) → `[Block]`.
- `ExportArchive`: walk a Notion export ZIP (nested pages → note hierarchy, page-link rewriting); `CSVTableParser` → `Table`/`Row` values.
- `MarkdownExporter` gains blocks→markdown (round-trip with the parser where lossless).

**Verify:** `swift test` with a real Notion export fixture checked into `Tests/Fixtures/`; parser round-trips its own output.

### Phase 3 — Editor spike (**THE risk gate — time-boxed: 2 weeks of effort, then decide**)
TextKit 2 single-textview editor bound to `BlockDocument`: typing, enter/backspace block semantics, markdown-shortcut conversion (`# `, `- `, `[] `), checkbox taps, toggle collapse, drag-handle reorder, undo/redo.
**Verify (device or simulator):** 1,000-block note — typing latency imperceptible, 60 fps scroll, reorder and undo correct, no lost keystrokes.
**Fallback:** markdown + rich attachments (Bear model). The decision is recorded and final — no sunk-cost extensions. Nothing after this phase depends on which editor won.

### Phase 4 — Notes core
SwiftData models (CloudKit-shaped), note list with `.searchable` over title/plainText/tags, tag chips, image blocks (photo picker + camera), swipe-to-delete, share-sheet text capture (`.onOpenURL` / share extension deferred if entitlement friction).
**Verify (device):** create/edit/search/delete; persistence across relaunch; cold launch < 2 s measured with a stopwatch and `os_signpost`.

### Phase 5 — Simple databases
Table UI (columns typed, rows editable in place), saved views (filter + sort), CSV import via `.fileImporter`.
**Verify:** 500-row table scrolls at 60 fps on device; view filters persist.

### Phase 6 — Notion import end-to-end
`ImportView`: pick export ZIP → progress → import report ("214 pages, 3 databases; 12 unsupported blocks skipped — see list"). Unsupported content degrades to visible placeholder blocks, never silent drops.
**Verify:** import a real workspace export; spot-check 10 pages against Notion side-by-side; search finds imported content.

### Phase 7 — Meeting capture (meeting_note.md Phases 3–4, retargeted)
RecorderService (interruptions, metering, background audio), whisper.cpp fetch + ModelManager first-launch download (base.en-q5_1 default, small.en selectable), AudioDecoder → ChunkPlanner → WhisperContext actor, then Gemini analyze → generated meeting note.
**Verify:** the original gates stand — 60-min locked-screen recording; JFK sample; 10-min real recording with memory < ~500 MB; kill mid-transcription and Retry recovers.

### Phase 8 — AI organize
On-demand per-note summarize + tag suggestions (Gemini, serial queue, throttled, Keychain key from Settings); related-notes via `NLEmbedding` sentence embeddings computed at save time.
**Verify:** airplane mode degrades gracefully — every non-AI feature fully functional offline; `swift test` for queue/throttle logic.

### Phase 9 — Polish + paid-account wave
Edge states (mic denied, no API key, storage stats), markdown export/ShareLink, app icon, then — once the $99 account exists — StoreKit 2 Free/Pro limits and TestFlight beta. CloudKit sync remains a **separate v1.1 decision**, deliberately not in this plan.

## Risk register (ranked)

1. **Block editor on the iOS text stack** — the chosen path is the expensive one. Mitigations: single-textview architecture, 2-week time-box, named fallback, and a phase order where the fallback loses nothing downstream.
2. **Free-team provisioning** — still unproven (0 identities today); same Phase 1 gate and simulator fallback as before.
3. **Notion import fidelity long tail** — relations, rollups, synced blocks, comments don't map. Mitigation: documented supported subset + import report; placeholders, never silent loss. "Perfect formatting" is not promised anywhere.
4. **Solo-dev scope (9 phases)** — the app is *usable* after Phase 4 (fast offline notes) and *marketable* after Phase 6 (import). Each phase ends shippable.
5. **Gemini free-tier limits** — on-demand + throttled only; model name stays a Settings-editable constant.
6. **whisper.cpp vs Xcode 26 / 90-min memory** — unchanged from meeting_note.md (pin v1.7.5 or source-build; incremental decode).
7. **Paid-account gating** — TestFlight, IAP, CloudKit all blocked until purchase; weekly reinstalls until then.

## Verification (end-to-end)

- Per-phase gates above; all Kit work checkable anytime via `cd Packages/MeetingMindKit && swift test`.
- MVP acceptance, on the iPhone 12 Pro, mostly in airplane mode: cold launch < 2 s → write a 30-block note fluidly → import a real Notion export ZIP and find an imported page by content search → build a 3-column table with a filtered view → (online) record a 5-min standup and watch it become a note with summary, decisions, and owned todos → export a note as markdown to Notes.
- The unvalidated assumptions in the pitch (market sizes, review percentages, competitor pricing) are treated as hypotheses, not inputs — nothing in this plan breaks if they're off.
