//
//  BlockEditorView.swift
//  Instant Notes
//
// The note editor: an editable title, the note's blocks laid out on ruled paper, and a
// bar of block actions that follows the caret.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PencilKit
import MeetingMindKit

/// Where focus and the caret should land after an edit.
struct CaretTarget: Equatable {
    var id: UUID
    /// UTF-16 offset into the block's text; nil puts the caret at the end.
    var offset: Int?
}

// MARK: - Editor

struct CanvasNoteEditorView: View {
    @Binding var note: Note
    /// Where a search result opened the note: the block or photo to scroll to, or the moment of
    /// the recording to play from.
    var jump: SearchPassage.Source? = nil
    @StateObject private var state = CanvasEditorState()
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var recorder: NoteRecorder

    @State private var focusedBlockID: UUID?
    @FocusState private var titleFocused: Bool
    @State private var caret: CaretTarget?
    @State private var caretGeneration = 0
    @State private var scrollTarget: UUID?
    @State private var contentHeight: CGFloat = 0
    @State private var showQuiz = false
    @State private var showFlashcards = false
    @State private var isSuggestingTags = false
    @State private var tagError: String?
    @State private var isDrawing = false
    /// Bottom of the lowest stroke, so the page stays long enough to show it.
    @State private var inkBottom: CGFloat = 0
    @State private var showMeetingChat = false
    @State private var scrollHandle = EditorScrollHandle()
    @State private var exportError: String?
    @State private var photoSource: PhotoSource?
    @State private var postImages: [UIImage]?
    /// Held in @State rather than observed, so playback ticking doesn't redraw the whole page;
    /// the bar observes it, and the page follows `playingBlockID`.
    @State private var player = PlaybackController()
    @State private var loadedRecordingID: UUID?
    @State private var playingBlockID: UUID?
    /// Taps on the page play the ink under them instead of editing.
    @State private var isReplaying = false

    private var metrics: EditorMetrics { EditorMetrics(dynamicTypeSize) }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        InkFloorStack(pitch: metrics.pitch) {
                            header
                            ForEach(state.visibleBlocks) { block in
                                if block.minY != nil {
                                    PaperRuling(style: note.paper, pitch: metrics.pitch)
                                        .layoutValue(key: InkGap.self, value: true)
                                }
                                row(for: block).id(block.id)
                                    .layoutValue(key: InkFloor.self, value: block.minY.map { CGFloat($0) })
                            }
                        }
                        .background(
                            GeometryReader { inner in
                                Color.clear.preference(key: ContentHeightKey.self, value: inner.size.height)
                            }
                        )
                        trailingSpace(viewport: geometry.size.height)
                    }
                    // Over the whole page, inside the scroll view, so strokes scroll with the text.
                    .overlay {
                        NoteInkLayer(note: note, isDrawing: isDrawing)
                            .allowsHitTesting(isDrawing)
                    }
                    .overlay {
                        if isReplaying, !isDrawing {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(SpatialTapGesture().onEnded { playInk(at: $0.location) })
                        }
                    }
                    .background(EnclosingScrollViewFinder(handle: scrollHandle))
                }
                .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
                    scrollTarget = nil
                }
            }
        }
        .background(Color(paperTint: note.paperTint).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        // While drawing, the tool picker covers the bottom of the screen, so Stop moves up here.
        .safeAreaInset(edge: .top) {
            if isDrawing, recorder.isRecording(into: note), let session = recorder.session {
                NoteRecordingBanner(session: session).padding(.top, 8)
            }
        }
        .toolbar { toolbarContent }
        .fullScreenCover(isPresented: $showQuiz) {
            QuizView(noteTitle: note.title, notesText: state.document.plainText)
        }
        .fullScreenCover(isPresented: $showFlashcards) {
            FlashcardsView(noteTitle: note.title, notesText: state.document.plainText)
        }
        .modifier(PhotoInput(source: $photoSource, onPick: insertPhotos))
        .sheet(item: Binding(get: { postImages.map(PostImages.init) }, set: { postImages = $0?.images })) { post in
            SharePostView(title: note.title, document: state.document, tags: note.tags, images: post.images)
        }
        .sheet(isPresented: $showMeetingChat) {
            if let artifact = note.meetingArtifact {
                MeetingChatView(artifact: artifact, notesText: state.document.plainText)
            }
        }
        .alert(
            "Couldn't export PDF",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert(
            "Couldn't suggest tags",
            isPresented: Binding(get: { tagError != nil }, set: { if !$0 { tagError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(tagError ?? "")
        }
        .environmentObject(state)
        .onAppear {
            state.load(from: note)
            installClock()
            // A brand-new note opens ready to type.
            if state.document.isEmpty { focus(state.insertBlock(.paragraph, after: nil)) }
            updateInkBottom()
            switch jump {
            case let .block(id): scrollTarget = id
            case let .photo(imageID): scrollTarget = state.document.blocks.first { $0.type == .image(id: imageID) }?.id
            // A second early, so the words searched for aren't clipped.
            case let .transcript(start):
                // The transcript runs the note's recordings end to end; find the one this moment is in.
                let all = recordings
                if let index = AudioClock.source(at: start, starts: all.map(\.transcriptOffset)) {
                    play(all[index], from: start - all[index].transcriptOffset - 1)
                }
            default: break
            }
        }
        .onDisappear { player.stop() }
        .onReceive(player.$currentTime) { time in
            let id = loadedRecordingID.flatMap { recording in
                player.isPlaying || time > 0 ? AudioClock.currentBlock(in: state.document.blocks, recordingID: recording, at: time) : nil
            }
            if id != playingBlockID { playingBlockID = id }
        }
        .onChange(of: note.drawingData) { _, _ in updateInkBottom() }
        .onChange(of: isDrawing) { _, drawing in
            // The keyboard and the tool picker would fight over the bottom of the screen.
            if drawing {
                focusedBlockID = nil
                titleFocused = false
            }
        }
        .onChange(of: note.id) { _, _ in
            state.load(from: note)
            installClock()
            focusedBlockID = nil
            player.stop()
            loadedRecordingID = nil
            isReplaying = false
        }
        .onChange(of: state.document) { _, document in
            if document != note.blockDocument { state.save(to: note) }
        }
        .onChange(of: note.blocksJSON) { _, _ in
            // Another window edited this note; take its version rather than overwrite it.
            let stored = note.blockDocument
            if stored != state.document { state.document = stored }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Vertical so long titles wrap rather than truncate; Return is caught in the binding.
            TextField("Untitled", text: titleBinding, axis: .vertical)
                .lineLimit(1...3)
                .font(metrics.titleFont)
                .foregroundStyle(Color("InkColor"))
                .textFieldStyle(.plain)
                .submitLabel(.next)
                .onSubmit { focusFirstBlock() }
                .focused($titleFocused)
                .frame(minHeight: metrics.pitch * 2, alignment: .bottom)
                .padding(.trailing, 16)

            if !note.tags.isEmpty || isSuggestingTags {
                tagRow.frame(height: metrics.pitch)
            }
        }
        .padding(.leading, EditorLayout.contentX)
        .padding(.top, metrics.pitch)
        .background(PaperRuling(style: note.paper, pitch: metrics.pitch))
    }

    /// The stored title is never blank, but the field should be — so the placeholder shows.
    private var titleBinding: Binding<String> {
        Binding(
            get: { note.title == "Untitled" ? "" : note.title },
            set: { typed in
                // A multi-line field inserts Return as a newline; treat it as "next" instead.
                // The field is mid-edit here, so let it go first and move on the next turn.
                if typed.contains("\n") {
                    titleFocused = false
                    DispatchQueue.main.async { focusFirstBlock() }
                }
                let typed = typed.replacingOccurrences(of: "\n", with: "")
                note.title = typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : typed
                note.touch()
            }
        )
    }

    private var tagRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(note.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text("#\(tag)")
                        Button { note.tags.removeAll { $0 == tag } } label: {
                            Image(systemName: "xmark").font(.caption2.bold())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove tag \(tag)")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                }
                if isSuggestingTags {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.trailing, 16)
        }
    }

    // MARK: Rows

    private func row(for block: Block) -> some View {
        BlockRowView(
            block: block,
            number: state.listCounters[block.id],
            metrics: metrics,
            paper: note.paper,
            isFocused: focusedBlockID == block.id,
            wantsCaret: caret?.id == block.id,
            caretOffset: caret?.id == block.id ? caret?.offset : nil,
            caretGeneration: caretGeneration,
            focus: focus,
            setFocused: { gained in blockFocusChanged(block.id, gained: gained) },
            audioTime: block.audioMark.flatMap { mark in recording(mark.recordingID).map { _ in mark.time } },
            isPlayingHere: playingBlockID == block.id,
            onAudioTap: {
                if let mark = block.audioMark, let recording = recording(mark.recordingID) {
                    play(recording, from: mark.time - 1)
                }
            }
        )
    }

    /// The paper carries on past the last block, and tapping any of it writes there — not
    /// just a strip below the text.
    private func trailingSpace(viewport: CGFloat) -> some View {
        let minimum = metrics.pitch * 4
        let wanted = max(minimum, viewport - contentHeight, inkBottom + metrics.pitch - contentHeight)
        let height = (wanted / metrics.pitch).rounded(.up) * metrics.pitch
        return PaperRuling(style: note.paper, pitch: metrics.pitch)
            .frame(height: height)
            .contentShape(Rectangle())
            .onTapGesture { focusTrailingBlock() }
            .accessibilityLabel("Write below the last block")
    }

    // MARK: Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            if !isDrawing, recorder.isRecording(into: note), let session = recorder.session {
                NoteRecordingBanner(session: session)
            }
            blockBarOrPlayer
        }
    }

    @ViewBuilder
    private var blockBarOrPlayer: some View {
        if let id = focusedBlockID {
            HStack(spacing: 2) {
                if !turnIntoTypes(for: id).isEmpty {
                    Menu {
                        ForEach(turnIntoTypes(for: id), id: \.displayName) { type in
                            Button { state.turn(id, into: type) } label: {
                                Label(type.displayName, systemImage: type.iconName)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .frame(width: 40, height: 34)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Turn into")
                }

                barButton("decrease.indent", "Outdent") { state.indent(id, by: -1) }
                barButton("increase.indent", "Indent") { state.indent(id, by: 1) }
                barButton("arrow.up", "Move up") { state.move(id, by: -1) }
                barButton("arrow.down", "Move down") { state.move(id, by: 1) }
                barButton("trash", "Delete block") { focus(state.remove(id)) }

                Spacer()
                Button("Done") { focusedBlockID = nil }
                    .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        } else if !isDrawing, !recorder.isRecording(into: note), let recording = shownRecording {
            RecordingPlayerBar(player: player, isReplaying: hasTimedInk ? $isReplaying : nil)
                .onAppear { load(recording) }
        }
    }

    // MARK: Recording & playback

    /// Oldest first, so the first is the meeting the note was made from.
    private var recordings: [Recording] {
        note.recordings.sorted { $0.createdAt < $1.createdAt }
    }

    private func recording(_ id: UUID) -> Recording? {
        note.recordings.first { $0.id == id }
    }

    /// The one in the player: the last one played, or the note's first.
    private var shownRecording: Recording? {
        loadedRecordingID.flatMap(recording) ?? recordings.first
    }

    /// Whether any recording was made in this note, so its ink can be replayed.
    private var hasTimedInk: Bool {
        note.drawingData != nil && note.recordings.contains { $0.clockSpansJSON != nil }
    }

    /// New and first-edited blocks are stamped with the moment of this note's recording.
    private func installClock() {
        let note = note
        state.clock = { [weak recorder] in recorder?.mark(for: note) }
    }

    private func load(_ recording: Recording) {
        guard loadedRecordingID != recording.id else { return }
        RecordingPlayerBar.load(recording, into: player)
        loadedRecordingID = recording.id
    }

    private func play(_ recording: Recording, from time: TimeInterval) {
        load(recording)
        guard player.error == nil else { return }
        player.seek(to: max(0, time))
        RecordingPlayerBar.play(player)
    }

    /// Replay: plays from when the stroke under `point` was drawn.
    private func playInk(at point: CGPoint) {
        guard let drawing = note.drawingData.flatMap({ try? PKDrawing(data: $0) }) else { return }
        // Topmost first: the stroke drawn last is the one on top.
        for stroke in drawing.strokes.reversed() where stroke.renderBounds.insetBy(dx: -8, dy: -8).contains(point) {
            let drawn = stroke.path.creationDate
            for recording in recordings.reversed() {
                if let time = AudioClock.fileTime(at: drawn, spans: recording.clockSpans, duration: recording.duration) {
                    play(recording, from: time - 1)
                    return
                }
            }
        }
    }

    private func barButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 40, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Turning written text into a rule would hide it with no way back, so Divider is only
    /// offered on an empty block.
    private func turnIntoTypes(for id: UUID) -> [BlockType] {
        // A photo has no text to turn into anything else.
        if case .image = state.document[id]?.type { return [] }
        let isEmpty = state.document[id]?.plainText.isEmpty ?? true
        return AddBlockPicker.blockTypes.filter { $0 != .divider || isEmpty }
    }

    // MARK: Toolbar

    /// Menus draw SF Symbols as monochrome templates, so a tinted symbol comes out black.
    /// A pre-rendered image keeps its colours; the outline keeps pale tints visible on the menu.
    private static func swatch(_ color: Color) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 18, height: 18))
            UIColor(color).setFill()
            circle.fill()
            UIColor.black.withAlphaComponent(0.25).setStroke()
            circle.lineWidth = 1
            circle.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if note.meetingArtifact?.fullTranscript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMeetingChat = true } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                .accessibilityLabel("Ask this meeting")
            }
        }
        if !recorder.isRecording(into: note) {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    player.pause()
                    isReplaying = false
                    recorder.start(for: note)
                } label: {
                    Image(systemName: "mic")
                }
                // One recording at a time, app-wide.
                .disabled(recorder.session != nil)
                .accessibilityLabel("Record")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { isDrawing.toggle() } label: {
                Image(systemName: isDrawing ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle")
            }
            .accessibilityLabel(isDrawing ? "Stop drawing" : "Draw")
        }
        // In the bar rather than floating over the page, where it hid text as the page scrolled.
        ToolbarItem(placement: .topBarTrailing) {
            AddBlockPicker(onInsert: insert, onPhoto: { photoSource = $0 })
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ShareLink(
                    item: markdownFile,
                    preview: SharePreview(markdownFile.name, image: Image(systemName: "doc.text"))
                ) {
                    Label("Share as Markdown", systemImage: "square.and.arrow.up")
                }
                Button { exportPDF() } label: {
                    Label("Share as PDF", systemImage: "doc.richtext")
                }
                Button { postImages = imagesInNote() } label: {
                    Label("Share as post…", systemImage: "paperplane")
                }
                Button { suggestTags() } label: {
                    Label("Suggest tags", systemImage: "tag")
                }
                .disabled(
                    isSuggestingTags
                        || state.document.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                Picker(selection: Binding(get: { note.paper }, set: { note.paper = $0 })) {
                    ForEach(PaperStyle.allCases, id: \.self) { style in
                        Text(style.rawValue.capitalized).tag(style)
                    }
                } label: {
                    Label("Paper", systemImage: "doc.plaintext")
                }
                .pickerStyle(.menu)
                Picker(selection: Binding(get: { note.paperTint }, set: { note.paperTint = $0 })) {
                    ForEach(PaperTint.allCases, id: \.self) { tint in
                        Label {
                            Text(tint.displayName)
                        } icon: {
                            Image(uiImage: Self.swatch(Color(paperTint: tint)))
                        }
                        .tag(tint)
                    }
                } label: {
                    Label("Page color", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showQuiz = true } label: { Label("Quiz me", systemImage: "brain.head.profile") }
                Button { showFlashcards = true } label: { Label("Flashcards", systemImage: "rectangle.on.rectangle.angled") }
            } label: {
                Label("Study", systemImage: "brain.head.profile")
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.pink)
        }
    }

    private var markdownFile: MarkdownFile {
        MarkdownFile(name: exportFileName, text: NoteMarkdownExporter.markdown(title: note.title, document: state.document))
    }

    private var exportFileName: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "Note" : trimmed
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    // MARK: Ink & PDF

    private func updateInkBottom() {
        let drawing = note.drawingData.flatMap { try? PKDrawing(data: $0) }
        // An empty drawing's bounds are CGRect.null, whose maxY is infinite.
        inkBottom = drawing.map { $0.strokes.isEmpty ? 0 : $0.bounds.maxY } ?? 0
    }

    private func exportPDF() {
        focusedBlockID = nil
        titleFocused = false
        isDrawing = false
        Task {
            // Let the keyboard and tool picker leave so they don't change the page mid-export.
            try? await Task.sleep(for: .milliseconds(400))
            guard let scrollView = scrollHandle.scrollView else { return }
            let data = NotePDFExporter.pdf(
                of: scrollView,
                height: max(contentHeight, inkBottom) + metrics.pitch,
                background: UIColor(Color(paperTint: note.paperTint)),
                title: note.title
            )
            do {
                try NotePDFExporter.share(data, name: exportFileName, from: scrollView)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    // MARK: Focus

    private func focus(_ target: CaretTarget?) {
        guard let target else { return }
        caret = target
        caretGeneration += 1
        focusedBlockID = target.id
    }

    private func blockFocusChanged(_ id: UUID, gained: Bool) {
        if gained {
            if focusedBlockID != id { focusedBlockID = id }
        } else if focusedBlockID == id {
            // Give a block taking over a turn to claim focus before the bar disappears.
            DispatchQueue.main.async {
                if focusedBlockID == id { focusedBlockID = nil }
            }
        }
    }

    private func insert(_ type: BlockType) {
        let target = state.insertBlock(type, after: focusedBlockID)
        focus(target)
        scrollTarget = target.id
    }

    // MARK: Photos

    /// Stores each photo and puts it on the page below the caret, in the order picked. An
    /// empty line the caret was sitting on gives way to the first photo.
    private func insertPhotos(_ images: [UIImage]) {
        var after = focusedBlockID
        let replaced = after.flatMap { state.document[$0] }.flatMap { $0.plainText.isEmpty && $0.type.holdsText ? $0.id : nil }
        var lastID: UUID?
        for image in images {
            guard let data = NoteImage.jpeg(from: image) else { continue }
            let stored = NoteImage(data: data)
            modelContext.insert(stored)
            stored.note = note
            let target = state.insertBlock(.image(id: stored.id), after: after)
            after = target.id
            lastID = target.id
        }
        guard let lastID else { return }
        if let replaced { state.remove(replaced) }
        focusedBlockID = nil
        titleFocused = false
        scrollTarget = lastID
        // Save the blocks with the photos now; onChange would only copy them after this save.
        state.save(to: note)
        try? modelContext.save()
        Task { await PhotoTextRecognition.recognizePending(in: modelContext) }
    }

    /// The note's photos in page order, for the post composer.
    private func imagesInNote() -> [UIImage] {
        state.document.blocks.compactMap { block in
            guard case let .image(id) = block.type else { return nil }
            return NoteImageCache.image(for: id, in: modelContext)
        }
    }

    private func focusFirstBlock() {
        if let first = state.document.blocks.first, first.type.holdsText {
            focus(CaretTarget(id: first.id, offset: 0))
        } else {
            focus(state.insertBlock(.paragraph, after: nil))
        }
    }

    private func focusTrailingBlock() {
        if let last = state.document.blocks.last, last.plainText.isEmpty, last.type.holdsText {
            focus(CaretTarget(id: last.id, offset: 0))
        } else {
            focus(state.insertBlock(.paragraph, after: state.document.order.last))
        }
    }

    // MARK: Tags

    private func suggestTags() {
        guard AppleIntelligence.unavailableReason == nil, #available(iOS 26, *) else {
            tagError = AppleIntelligence.unavailableReason
            return
        }
        let existing = Set(((try? modelContext.fetch(FetchDescriptor<Note>())) ?? []).flatMap(\.tags)).sorted()
        isSuggestingTags = true
        Task {
            defer { isSuggestingTags = false }
            do {
                let suggested = try await OnDeviceTagSuggester().tags(
                    title: note.title, notes: state.document.plainText, existingTags: existing
                )
                note.tags += suggested.filter { !note.tags.contains($0) }
                note.touch()
            } catch {
                tagError = error.localizedDescription
            }
        }
    }
}

/// The photos handed to the post composer; a sheet needs something Identifiable.
private struct PostImages: Identifiable {
    let images: [UIImage]
    var id: Int { images.count }
}

/// A row's `Block.minY`: it starts no higher than this.
private struct InkFloor: LayoutValueKey {
    static let defaultValue: CGFloat? = nil
}

/// Marks the ruled filler placed just before a row with an `InkFloor`.
private struct InkGap: LayoutValueKey {
    static let defaultValue = false
}

/// Stacks rows top to bottom like a VStack, except that a row with an `InkFloor` is pushed down
/// to the first ruled line at or below it, so text added under a drawing doesn't land on the ink.
/// The `InkGap` filler before that row takes up the space it skips.
private struct InkFloorStack: Layout {
    let pitch: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(for: subviews, width: proposal.width)
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(for: subviews, width: bounds.width)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat?) -> [CGRect] {
        var y: CGFloat = 0
        var frames: [CGRect] = []
        for index in subviews.indices {
            let height: CGFloat
            var frameWidth = width ?? 0
            if subviews[index][InkGap.self] {
                let floor = index + 1 < subviews.endIndex ? subviews[index + 1][InkFloor.self] : nil
                height = floor.map { max(0, ($0 / pitch).rounded(.up) * pitch - y) } ?? 0
            } else {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                height = size.height
                frameWidth = size.width
            }
            frames.append(CGRect(x: 0, y: y, width: frameWidth, height: height))
            y += height
        }
        return frames
    }
}

private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    // max, not the last value: the ink overlay and scroll finder report the default 0 after the content.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The note as a real `.md` file, so sharing it lands a document rather than a wall of text.
struct MarkdownFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .noteMarkdown) { file in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(file.name)
                .appendingPathExtension("md")
            try? FileManager.default.removeItem(at: url)
            try file.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
        .suggestedFileName { "\($0.name).md" }
    }
}

extension UTType {
    /// Markdown has no system-declared type on every OS the app runs on; plain text is the
    /// honest fallback, and the .md extension survives either way.
    static let noteMarkdown = UTType(filenameExtension: "md") ?? .plainText
}

// MARK: - State

@MainActor
final class CanvasEditorState: ObservableObject {
    @Published var document = BlockDocument() { didSet { updateListCounters() } }
    @Published private(set) var listCounters: [UUID: Int] = [:]
    /// The moment of the recording running in this note, if one is, for stamping what's written.
    var clock: (() -> AudioMark?)?

    // MARK: Persistence

    func load(from note: Note) {
        document = note.blockDocument
    }

    func save(to note: Note) {
        note.blockDocument = document
        note.touch()
        // A photo whose block is gone would otherwise sit in the store for good; there's no undo to bring it back.
        let shown = Set(document.blocks.compactMap { block -> UUID? in
            if case let .image(id) = block.type { return id } else { return nil }
        })
        for image in note.images ?? [] where !shown.contains(image.id) {
            note.modelContext?.delete(image)
        }
    }

    /// Blocks hidden under a collapsed toggle are dropped here, not in the view.
    var visibleBlocks: [Block] {
        var result: [Block] = []
        var hiddenBelow: Int?
        for block in document.blocks {
            if let level = hiddenBelow {
                if block.indent > level { continue }
                hiddenBelow = nil
            }
            result.append(block)
            if block.type == .toggle, !block.isExpanded { hiddenBelow = block.indent }
        }
        return result
    }

    // MARK: Editing

    @discardableResult
    func insertBlock(_ type: BlockType, after id: UUID?) -> CaretTarget {
        var doc = document
        let block = Block(type: type, indent: id.flatMap { doc[$0]?.indent } ?? 0, audioMark: clock?())
        if let id, doc[id] != nil {
            doc.insert(block, after: id)
        } else {
            doc.append(block)
        }
        document = doc
        return CaretTarget(id: block.id, offset: 0)
    }

    func updateText(_ id: UUID, _ text: String) {
        guard let block = document[id], block.plainText != text else { return }
        let mark = block.audioMark ?? clock?()
        document.update(id) {
            $0.runs = text.isEmpty ? [] : [.plain(text)]
            $0.audioMark = mark
        }
    }

    func updateBlock(_ id: UUID, transform: (inout Block) -> Void) {
        document.update(id, transform: transform)
    }

    func turn(_ id: UUID, into type: BlockType) {
        document.update(id) { block in
            block.type = type
            if type == .divider { block.runs = [] }
            if type != .todo { block.isChecked = false }
            if type == .toggle { block.isExpanded = true }
        }
    }

    /// Return, or a multi-line paste. Returns where focus and the caret should land.
    func split(_ id: UUID, lines: [String], caret: Int) -> CaretTarget? {
        guard let block = document[id], lines.count > 1 else { return nil }
        let first = lines[0]
        let rest = Array(lines.dropFirst())
        var doc = document

        // Return on an empty list item leaves the list instead of making another one.
        if lines.count == 2, first.isEmpty, rest[0].isEmpty,
           block.plainText.isEmpty, block.type.continuesOnReturn {
            if block.indent > 0 {
                doc.update(id) { $0.indent -= 1 }
            } else {
                doc.update(id) { $0.type = .paragraph; $0.isChecked = false }
            }
            document = doc
            return CaretTarget(id: id, offset: 0)
        }

        // Return at the very start pushes a blank line above and leaves you where you were,
        // so a heading or a to-do never gets downgraded by making room above it.
        if lines.count == 2, first.isEmpty, !block.plainText.isEmpty, rest[0] == block.plainText {
            let above = Block(type: block.type.continuation, indent: block.indent, audioMark: clock?())
            let index = doc.order.firstIndex(of: id) ?? 0
            doc.insert(above, after: index > 0 ? doc.order[index - 1] : nil)
            document = doc
            return CaretTarget(id: id, offset: 0)
        }

        doc.update(id) { $0.runs = first.isEmpty ? [] : [.plain(first)] }

        // A toggle's Return writes its first child, tucked under it.
        let isToggle = block.type == .toggle
        if isToggle { doc.update(id) { $0.isExpanded = true } }
        let newType: BlockType = isToggle ? .paragraph : block.type.continuation
        let newIndent = isToggle ? block.indent + 1 : block.indent

        var previous = id
        for line in rest {
            let next = Block(type: newType, runs: line.isEmpty ? [] : [.plain(line)], indent: newIndent, audioMark: clock?())
            doc.insert(next, after: previous)
            previous = next.id
        }
        document = doc
        return CaretTarget(id: previous, offset: caret)
    }

    /// Backspace with the caret at offset zero: shed the block's type, then its indent, then
    /// merge it into the block above.
    func backspaceAtStart(_ id: UUID) -> CaretTarget? {
        guard let block = document[id] else { return nil }
        // Code keeps its text; only an empty code block gives way.
        if block.type.isCode, !block.plainText.isEmpty { return nil }
        var doc = document

        if block.type != .paragraph, !block.type.isCode {
            doc.update(id) { $0.type = .paragraph; $0.isChecked = false; $0.isExpanded = true }
            document = doc
            return CaretTarget(id: id, offset: 0)
        }
        if block.indent > 0 {
            doc.update(id) { $0.indent -= 1 }
            document = doc
            return CaretTarget(id: id, offset: 0)
        }

        guard let index = doc.order.firstIndex(of: id), index > 0 else { return nil }
        let previousID = doc.order[index - 1]
        guard let previous = doc[previousID] else { return nil }

        // A rule above simply goes.
        if previous.type == .divider {
            doc.remove(previousID)
            document = doc
            return CaretTarget(id: id, offset: 0)
        }
        // A photo above is selected rather than deleted, so one Backspace too many can't lose it.
        if case .image = previous.type {
            return CaretTarget(id: previousID, offset: nil)
        }

        let offset = previous.plainText.utf16.count
        if block.plainText.isEmpty {
            doc.remove(id)
            document = doc
            return CaretTarget(id: previousID, offset: offset)
        }
        guard !previous.type.isCode else { return nil }
        doc.mergeWithPrevious(id)
        document = doc
        return CaretTarget(id: previousID, offset: offset)
    }

    /// Tab and Shift-Tab. A block can only ever sit one level deeper than the one above it.
    func indent(_ id: UUID, by delta: Int) {
        guard let index = document.order.firstIndex(of: id),
              let block = document[id], block.type.holdsText else { return }
        let ceiling = index > 0 ? (document[document.order[index - 1]]?.indent ?? 0) + 1 : 0
        let target = min(max(block.indent + delta, 0), ceiling)
        guard target != block.indent else { return }
        document.update(id) { $0.indent = target }
    }

    /// `BlockDocument.move` takes its destination in the pre-move ordering, so one row down
    /// is index + 2.
    func move(_ id: UUID, by delta: Int) {
        guard let index = document.order.firstIndex(of: id) else { return }
        let destination = delta < 0 ? index - 1 : index + 2
        guard destination >= 0, destination <= document.order.count else { return }
        document.move(fromIndex: index, toIndex: destination)
    }

    @discardableResult
    func remove(_ id: UUID) -> CaretTarget? {
        guard let index = document.order.firstIndex(of: id) else { return nil }
        var doc = document
        doc.remove(id)
        document = doc
        if index > 0 {
            let previousID = doc.order[index - 1]
            return CaretTarget(id: previousID, offset: doc[previousID]?.plainText.utf16.count)
        }
        return doc.order.first.map { CaretTarget(id: $0, offset: 0) }
    }

    /// Numbers each level's run of items from 1, so a nested list restarts and its parent
    /// carries on where it left off.
    private func updateListCounters() {
        var counters: [UUID: Int] = [:]
        var levels: [Int] = []
        for block in document.blocks {
            if block.type == .numberedList {
                let level = block.indent
                if levels.count > level + 1 { levels.removeSubrange((level + 1)...) }
                while levels.count <= level { levels.append(0) }
                levels[level] += 1
                counters[block.id] = levels[level]
            } else if block.indent == 0 {
                levels.removeAll()
            } else if levels.count > block.indent {
                levels.removeSubrange(block.indent...)
            }
        }
        if counters != listCounters { listCounters = counters }
    }
}

// MARK: - Paper

extension Color {
    init(paperTint tint: PaperTint) {
        self.init(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? tint.darkComponents : tint.components
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
    }
}

/// A whole sheet of paper at a fixed pitch — for previews and template thumbnails. The
/// editor itself draws its ruling per row so it scrolls with the text.
struct PaperCanvasBackground: View {
    var style: PaperStyle = .lined
    var tint: PaperTint = .cream
    var pitch: CGFloat = 30

    var body: some View {
        Color(paperTint: tint)
            .overlay(PaperRuling(style: style, pitch: pitch))
    }
}

// MARK: - Add block

struct AddBlockPicker: View {
    let onInsert: (BlockType) -> Void
    let onPhoto: (PhotoSource) -> Void

    var body: some View {
        Menu {
            Section {
                if PhotoSource.isCameraAvailable {
                    Button { onPhoto(.camera) } label: { Label("Take Photo", systemImage: "camera") }
                }
                Button { onPhoto(.library) } label: { Label("Photo Library", systemImage: "photo.on.rectangle") }
                Button { onPhoto(.files) } label: { Label("Image from Files", systemImage: "folder") }
            }
            ForEach(Self.blockTypes, id: \.displayName) { type in
                Button {
                    onInsert(type)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: type.iconName)
                            .font(.caption)
                            .frame(width: 24)
                        Text(type.displayName)
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add block")
    }

    static var blockTypes: [BlockType] {
        [
            .paragraph,
            .heading(level: 1), .heading(level: 2), .heading(level: 3),
            .bulletedList, .numberedList, .todo, .toggle,
            .quote, .callout(emoji: "💡"), .code(language: nil), .divider
        ]
    }
}
