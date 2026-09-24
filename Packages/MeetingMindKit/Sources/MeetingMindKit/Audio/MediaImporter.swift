//
//  MediaImporter.swift
//  MeetingMindKit
//
// Brings an audio or video file from outside the app (Files, Photos, a Mac folder) into the
// recordings folder, so it can be transcribed and kept like a meeting recorded in the app.

import Foundation
import AVFoundation

public enum MediaImporter {
    public enum Failure: Error, LocalizedError, Equatable {
        case noAudio
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .noAudio: "That file has no sound to transcribe."
            case .unreadable: "That file couldn't be opened as audio or video."
            }
        }
    }

    /// Copies audio the transcriber can read as it is; anything else (video, or audio in another
    /// container) has its sound track written out as an .m4a. The original file is left alone.
    public static func importMedia(
        from source: URL,
        into directory: URL = AudioRecorderService.defaultRecordingsDirectory()
    ) async throws -> AudioRecordingResult {
        // Files picked outside the sandbox are only readable while this is held.
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: source)
        let hasVideo = !((try? await asset.loadTracks(withMediaType: .video)) ?? []).isEmpty
        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
        let stem = source.deletingPathExtension().lastPathComponent
        let unique = "\(stem)_\(UUID().uuidString.prefix(8))"

        let destination: URL
        if !hasVideo, (try? AVAudioFile(forReading: source)) != nil {
            destination = directory.appending(path: "\(unique).\(source.pathExtension)")
            try FileManager.default.copyItem(at: source, to: destination)
        } else {
            guard !audioTracks.isEmpty else {
                throw (try? await asset.load(.isReadable)) == true ? Failure.noAudio : Failure.unreadable
            }
            destination = directory.appending(path: "\(unique).m4a")
            try await exportAudio(of: asset, to: destination)
        }

        let duration = try await AVURLAsset(url: destination).load(.duration).seconds
        return AudioRecordingResult(url: destination, duration: duration.isFinite ? duration : 0, startTime: .now)
    }

    private static func exportAudio(of asset: AVURLAsset, to destination: URL) async throws {
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw Failure.unreadable
        }
        if #available(iOS 18, macOS 15, *) {
            try await session.export(to: destination, as: .m4a)
        } else {
            session.outputURL = destination
            session.outputFileType = .m4a
            await session.export()
            if let error = session.error { throw error }
            guard session.status == .completed else { throw Failure.unreadable }
        }
    }
}
