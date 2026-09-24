//
//  PKCanvasWrapper.swift
//  Instant Notes
//
// PencilKit ink layer drawn over a note's content.

#if os(iOS)
import SwiftUI
import UIKit
import PencilKit

/// Transparent PencilKit layer for one note. Fills whatever frame SwiftUI gives it.
struct NoteInkLayer: UIViewRepresentable {
    let note: Note
    /// true: captures strokes, shows the PKToolPicker, becomes first responder.
    /// false: inert (isUserInteractionEnabled = false) and the tool picker is hidden. Existing strokes stay visible.
    let isDrawing: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The editor's ScrollView scrolls the layer with the text, so the canvas itself never scrolls.
        canvas.isScrollEnabled = false
        canvas.contentInset = .zero
        canvas.contentInsetAdjustmentBehavior = .never
        // Follows the system setting: Pencil-only on an iPad paired with a Pencil (a finger scrolls),
        // finger, mouse and simulator input everywhere else.
        canvas.drawingPolicy = .default
        canvas.isUserInteractionEnabled = false
        canvas.delegate = context.coordinator

        let pen = PKInkingTool(.pen, color: .black)
        canvas.tool = pen
        context.coordinator.toolPicker.selectedTool = pen
        context.coordinator.toolPicker.addObserver(canvas)

        context.coordinator.load(note, into: canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.load(note, into: canvas)
        context.coordinator.setDrawing(isDrawing)
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.setDrawing(false)
        coordinator.flush()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        private weak var canvas: PKCanvasView?
        private var note: Note?
        private var isDrawing = false
        private var isLoading = false
        private var pendingSave: Task<Void, Never>?

        /// Shows `note`'s strokes, first saving any pending strokes to the note shown before.
        func load(_ note: Note, into canvas: PKCanvasView) {
            guard note !== self.note else { return }
            flush()
            self.note = note
            self.canvas = canvas
            // Setting `drawing` calls the delegate; that change isn't the user's, so don't save it.
            isLoading = true
            canvas.drawing = note.drawingData.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
            isLoading = false
        }

        func setDrawing(_ isDrawing: Bool) {
            guard let canvas, isDrawing != self.isDrawing else { return }
            self.isDrawing = isDrawing
            canvas.isUserInteractionEnabled = isDrawing
            toolPicker.setVisible(isDrawing, forFirstResponder: canvas)
            if isDrawing {
                // Deferred a tick: on the first update the canvas isn't in a window yet.
                Task { if self.isDrawing { canvas.becomeFirstResponder() } }
            } else {
                canvas.resignFirstResponder()
                flush()
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isLoading else { return }
            pendingSave?.cancel()
            pendingSave = Task {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                self.flush()
            }
        }

        /// Writes unsaved strokes to the note now.
        func flush() {
            guard pendingSave != nil, let canvas, let note else { return }
            pendingSave?.cancel()
            pendingSave = nil
            let data = canvas.drawing.dataRepresentation()
            // Written a tick later because this can run inside a SwiftUI view update.
            Task {
                guard note.modelContext != nil else { return } // deleted meanwhile
                note.drawingData = data
                note.touch()
                // Saved now, not at the next autosave (~10 s later), so quitting right after drawing keeps the ink.
                try? note.modelContext?.save()
            }
        }
    }
}

#endif
