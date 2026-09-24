//
//  CloudSync.swift
//  Instant Notes
//
// Notes sync through the user's private iCloud database. Stores from before sync need their
// audio copied into the database and their new relationship sides filled in.

import Foundation
import SwiftData
import MeetingMindKit

enum CloudSync {
    static let containerID = "iCloud.com.homezero1.instantnotes"
    private static let audioCopiedKey = "CloudSync.audioCopied"

    /// Brings rows saved before sync up to date. Cheap after the first launch: the audio copy
    /// runs once, and the relationship check only writes what's missing.
    @MainActor
    static func prepare(_ context: ModelContext) {
        let artifacts = (try? context.fetch(FetchDescriptor<MeetingArtifact>())) ?? []
        let notes = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        // Before sync only one side of these was stored; CloudKit needs both.
        for note in notes {
            if let artifact = note.meetingArtifact, artifact.note !== note { artifact.note = note }
        }
        for artifact in artifacts {
            if let recording = artifact.recording, recording.artifact !== artifact { recording.artifact = artifact }
        }

        if !UserDefaults.standard.bool(forKey: audioCopiedKey) {
            let folder = AudioRecorderService.defaultRecordingsDirectory()
            for recording in (try? context.fetch(FetchDescriptor<Recording>())) ?? [] where recording.audioData == nil {
                recording.audioData = try? Data(contentsOf: folder.appending(path: recording.filePath), options: .mappedIfSafe)
            }
            UserDefaults.standard.set(true, forKey: audioCopiedKey)
        }
        if context.hasChanges { try? context.save() }
    }

    /// The local file for `recording`, written from its synced audio when this device doesn't
    /// have it yet.
    static func audioURL(for recording: Recording) -> URL {
        let folder = AudioRecorderService.defaultRecordingsDirectory()
        let url = folder.appending(path: recording.filePath)
        if !FileManager.default.fileExists(atPath: url.path), let data = recording.audioData {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: url)
        }
        return url
    }
}
