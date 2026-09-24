//
//  WhisperContext.swift
//  MeetingMindKit
//
// whisper.cpp integration — protocol-first design with stub implementation.
// The xcframework will be integrated when available.

import Foundation

/// Protocol for whisper.cpp speech-to-text engine.
public protocol WhisperContextProtocol: Sendable {
    func load(modelPath: URL) throws
    func encode(audioBuffer: UnsafePointer<Float>, sampleRate: Int) throws -> WhisperEmbedding?
    func decode(embedding: WhisperEmbedding, tokens: [Int], outputRaw: Bool) throws -> String
    var progress: Progress { get }
}

/// Stub implementation that replaces xcframework until it's available.
public final class StubWhisperContext: WhisperContextProtocol, @unchecked Sendable {
    public func load(modelPath: URL) throws {
        // Stub — returns without doing anything when no framework
    }

    public func encode(audioBuffer: UnsafePointer<Float>, sampleRate: Int) throws -> WhisperEmbedding? {
        nil
    }

    public func decode(embedding: WhisperEmbedding, tokens: [Int], outputRaw: Bool) throws -> String {
        ""
    }

    public var progress: Progress { Progress() }
}

public struct WhisperEmbedding: @unchecked Sendable {
    public let buffer: UnsafePointer<Float>
    public let length: Int

    public func withUnsafeBufferedPointer<R>(_ body: (UnsafeBufferPointer<Float>) throws -> R) rethrows -> R {
        try body(UnsafeBufferPointer(start: buffer, count: length))
    }
}

/// Available whisper.cpp models for download.
public enum WhisperModel: String, CaseIterable {
    case tiny = "tiny"
    case base = "base"
    case small = "small"

    var fileName: String { "ggml-model-\(rawValue).bin" }
    var downloadSizeMB: Int {
        switch self {
        case .tiny: 150
        case .base: 500
        case .small: 1500
        }
    }

    var displayName: String {
        switch self {
        case .tiny: "Tiny (~150 MB)"
        case .base: "Base (~500 MB)"
        case .small: "Small (~1.5 GB)"
        }
    }
}

/// Manages whisper.cpp model download and caching.
public struct ModelManager: Sendable {
    public static let shared = ModelManager()

    private init() {}

    /// Check if a model is available locally.
    public func isModelAvailable(_ model: WhisperModel) -> Bool {
        // Stub — will scan AppSupport/WhisperModels when xcframework is available
        return false
    }

    /// Download a whisper.cpp model to local storage.
    public func downloadModel(_ model: WhisperModel, progress: Progress? = nil) async throws {
        // Stub — in production this would fetch from GitHub releases
        throw ModelError.downloadNotImplemented(model.rawValue)
    }

    /// Create a WhisperContextProtocol (real or stub) for the given model.
    public func createContext(for model: WhisperModel) throws -> WhisperContextProtocol {
        // Returns StubWhisperContext until xcframework is available
        StubWhisperContext()
    }

    public enum ModelError: LocalizedError {
        case downloadNotImplemented(String)
        case modelNotFound(String)
        case invalidModel

        public var errorDescription: String? {
            switch self {
            case .downloadNotImplemented(let name): "Download for \(name) not implemented yet."
            case .modelNotFound(let name): "Model \(name) not found on disk."
            case .invalidModel: "Invalid model file."
            }
        }
    }
}

// MARK: - TranscriptionService — stub orchestration layer

public struct TranscriptionService: Sendable {
    public static let shared = TranscriptionService()

    private init() {}

    /// Run the full meeting capture pipeline:
    /// AudioRecording → ChunkPlanner windows → WhisperContext per chunk → on-device analyze
    @available(*, deprecated, message: "Stub — will use real whisper.cpp when xcframework is integrated")
    public func analyzeMeeting(audioURL: URL) async throws -> MeetingAnalysis {
        // Stub implementation
        throw TranscriptionError.stubOnly
    }

    public enum TranscriptionError: LocalizedError {
        case stubOnly
        case audioLoadFailed(URL)
        case transcriptionFailed(Error)
        case analysisFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .stubOnly: "Transcription is not yet implemented — whisper.cpp xcframework needed."
            case .audioLoadFailed(let url): "Could not load audio from \(url.lastPathComponent)."
            case .transcriptionFailed(let error): "Transcription failed: \(error.localizedDescription)"
            case .analysisFailed(let error): "AI analysis failed: \(error.localizedDescription)"
            }
        }
    }
}
