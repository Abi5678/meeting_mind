# Instant Notes

A native iOS notes app combining **Notability** (ink canvas + audio sync) with **Notion** (block editor + databases), powered by AI meeting capture. Built from the merged codebase of [NotabilityClone](https://github.com/Home-01/NotabilityClone) and [meeting_mind](https://github.com/Home-01/meeting_mind).

## Architecture

```
InstantNotes/          ← iOS app (SwiftUI, SwiftData)
├── Models/            ← SwiftData entities (Phase 3)
├── Editor/            ← Block editor views (Phase 4)
├── Views/             ← Canvas, NoteList, MeetingCapture, Import, AI (Phases 5-8)
└── Assets.xcassets/

MeetingMindKit/        ← Shared Swift package (already built & tested)
├── Blocks/            ← Block model + BlockDocument ✅
├── OnDevice/          ← Apple Foundation Models: summary, quiz, tags, meeting chat, Ask ✅
├── NotionImport/      ← MarkdownBlockParser + CSVTableParser ✅
├── Audio/             ← SyncEngine + AudioRecorderService + PlaybackController (new)
├── Transcription/     ← WhisperContext protocol layer (new)
└── ChunkPlanner.swift ← Audio chunk planning ✅

NoteStyle Studio/      ← Visual design reference only (React/Vite, never ships)
```

## Phases

| Phase | Title | Status |
|-------|-------|--------|
| 1 | Project scaffold (XcodeGen + hello world) | ✅ Complete |
| 2 | Merge SyncEngine/audio into MeetingMindKit | ✅ Complete |
| 3 | SwiftData models (Note, Recording, MeetingArtifact, etc.) | ✅ Complete |
| 4 | Block editor views (BlockRowView, CanvasNoteEditorView) | ✅ Complete (scaffold — TextKit 2 spike pending) |
| 5 | Canvas + Notes core (PKCanvasView wrapper, NoteListView) | ✅ Complete (scaffold — PencilKit integration pending) |
| 6 | Meeting capture (WaveformBanner, MeetingCaptureView, ViewModel) | ✅ Complete (stub — whisper.cpp pending) |
| 7 | Notion import views (ImportCoordinator, ImportView) | ✅ Complete |
| 8 | AI on device (summary, quiz, tags, meeting chat, Ask your notes) | ✅ Complete |
| 9 | Polish + paid account | ⏳ Gated on $99 Apple Developer account |

## Getting Started (macOS)

### Prerequisites
1. **Xcode 16+** with iOS 17 SDK
2. **Swift 6** toolchain
3. **xcodegen**: `brew install xcodegen`
4. **Apple Developer ID** (for device signing — free personal team works for development)

### Setup
```bash
# Generate Xcode project
cd meeting_mind
xcodegen generate

# Open in Xcode
open build/InstantNotes.xcodeproj
```

### Run on Simulator
In Xcode: select "iPhone 16" simulator → Cmd+R

### Run on Device
1. Connect iPhone via USB
2. In Xcode, select your iPhone as destination
3. Sign in with Apple ID (Settings → Accounts → Add Apple ID)
4. Build and run — Phase 1 gate: app launches on device

### Whisper.cpp (Phase 6)
```bash
./Scripts/fetch-whisper.sh  # Downloads model xcframework
# Model files go to Vendor/whisper.xcframework/
```

## Design Identity

Based on **NoteStyle Studio** visual reference — "a calm notebook identity that positions against Notion's gray sprawl":

- **Paper background**: warm cream `oklch(0.975 0.012 85)` / hex `#FAF6F0`
- **Ink color**: deep blue-black `oklch(0.22 0.02 260)` 
- **Ruled lines**: light blue at low opacity, 32pt spacing
- **Red margin accent**: legal pad convention at x=72pt
- **Highlighter colors**: yellow `#FFF59D`, pink `#F48FB1`, mint `#A5D6A7`

## Key Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Block editor | TextKit 2 single UITextView + custom NSTextLayoutFragment | Native text stack; fallback: markdown (Bear model) if spike fails |
| Persistence | SwiftData, CloudKit-shaped from day one | Sync becomes config flip later |
| AI provider | Apple Foundation Models, on device (iOS 26+, Apple Intelligence) | No key, no network, notes never leave the device; `@Generable` for constrained output |
| Speech-to-text | whisper.cpp xcframework (MPS-backed on Apple Silicon) | Offline, low latency |
| Meeting capture | AVAudioRecorder → ChunkPlanner windows → whisper.cpp per chunk → on-device analyze | Flat memory, no 90-min file in RAM |
