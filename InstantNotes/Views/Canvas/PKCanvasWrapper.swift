//
//  PKCanvasWrapper.swift
//  Instant Notes
//
// PencilKit canvas wrapper for iOS ink input.

#if os(iOS)
import SwiftUI
import UIKit
import PencilKit

/// SwiftUI representable wrapping PKCanvasView for ink drawing on notes.
struct InkCanvasOverlay: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @EnvironmentObject private var state: CanvasEditorState

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .label, width: 2)
        canvas.delegate = context.coordinator
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Sync binding direction — user draws on PKCanvasView → updates drawing binding
        if let lastDrawing = context.coordinator.lastDrawing {
            drawing = lastDrawing
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let parent: InkCanvasOverlay
        var lastDrawing: PKDrawing?

        init(_ parent: InkCanvasOverlay) {
            self.parent = parent
        }

        func canvasDrawingChanged(_ canvas: PKCanvasView, drawing: PKDrawing) {
            // Debounced save to SwiftData — in production use a timer
            lastDrawing = drawing
        }
    }
}

// MARK: - Canvas toolbar for tool selection

struct CanvasToolbarView: View {
    @Binding var selectedTool: CanvasTool
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(CanvasTool.allCases, id: \.self) { tool in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTool = tool
                    }
                } label: {
                    Image(systemName: tool.iconName)
                        .font(.caption2)
                        .foregroundStyle(selectedTool == tool ? .white : .primary)
                        .padding(6)
                        .background(
                            Circle()
                                .fill(selectedTool == tool ? Color.accentColor : Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button { onExport() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .padding(6)
                    .background(Circle().fill(Color.secondary.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
    }
}

enum CanvasTool: String, CaseIterable, Identifiable {
    case pen, marker, highlighter, eraser

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .highlighter: return "circle.hexagongrid.fill"
        case .eraser: return "hand.draw"
        }
    }

    var pkTool: PKTool {
        switch self {
        case .pen:
            return PKInkingTool(.pen, color: .label, width: 2)
        case .marker:
            return PKInkingTool(.marker, color: .label.withAlphaComponent(0.8), width: 10)
        case .highlighter:
            return PKInkingTool(.marker, color: UIColor(white: 0.95, alpha: 0.6), width: 20)
        case .eraser:
            return PKEraserTool(.vector)
        }
    }
}

#endif
