//
//  NoteStorageTests.swift
//  Instant Notes
//
// Notes saved by earlier builds must keep opening, and a second recording in a note must carry
// on its meeting transcript.

import Foundation
import SwiftData
import Testing
import MeetingMindKit
@testable import InstantNotes

@MainActor
@Suite("Note storage")
struct NoteStorageTests {
    let container: ModelContainer

    init() throws {
        let schema = Schema([Note.self, Recording.self, MeetingArtifact.self, TranscriptSegment.self,
                             MeetingChatMessage.self, NoteImage.self, Tag.self,
                             TableEntity.self, ColumnEntity.self, RowEntity.self])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test("Blocks saved before audio marks and ink floors still decode")
    func oldBlocksDecode() throws {
        // As build 1.0 (2) wrote it: no audioMark or minY keys.
        let json = """
        {"order":["6F1C2A10-0000-4000-8000-000000000001","6F1C2A10-0000-4000-8000-000000000002"],
         "blocksByID":{
          "6F1C2A10-0000-4000-8000-000000000001":{"id":"6F1C2A10-0000-4000-8000-000000000001","kind":"heading","headingLevel":2,
            "runs":[{"text":"Agenda","isBold":false,"isItalic":false,"isCode":false}],"indent":0,"isExpanded":true,"isChecked":false},
          "6F1C2A10-0000-4000-8000-000000000002":{"id":"6F1C2A10-0000-4000-8000-000000000002","kind":"todo",
            "runs":[{"text":"Send the notes","isBold":true,"isItalic":false,"isCode":false}],"indent":1,"isExpanded":true,"isChecked":true}
         }}
        """
        let note = Note(title: "Old", blocksJSON: json)
        let blocks = note.blockDocument.blocks
        #expect(blocks.map(\.plainText) == ["Agenda", "Send the notes"])
        #expect(blocks[0].type == .heading(level: 2))
        #expect(blocks[1].type == .todo && blocks[1].isChecked && blocks[1].indent == 1)
        #expect(blocks.allSatisfy { $0.audioMark == nil && $0.minY == nil })
    }

    @Test("Audio marks and ink floors round-trip through the note")
    func newFieldsRoundTrip() {
        let mark = AudioMark(recordingID: UUID(), time: 42)
        let note = Note(title: "New")
        note.blockDocument = BlockDocument(blocks: [Block(type: .paragraph, runs: [.plain("Hi")], audioMark: mark, minY: 300)])
        let block = note.blockDocument.blocks[0]
        #expect(block.audioMark == mark)
        #expect(block.minY == 300)
    }

    @Test("A second recording carries on the note's transcript after the first")
    func secondRecordingAppends() throws {
        let context = container.mainContext
        let note = Note(title: "Standup")
        context.insert(note)
        let first = Recording(name: "Standup", filePath: "a.m4a", duration: 60)
        note.recordings.append(first)
        let artifact = MeetingArtifact(recordingId: first.id, status: 0, summary: "First.", fullTranscript: "Hello there.")
        artifact.segments = [TranscriptSegment(artifactId: artifact.id, startTime: 0, endTime: 4, text: "Hello there.")]
        note.meetingArtifact = artifact

        let second = Recording(name: "Standup", filePath: "b.m4a", duration: 30)
        MeetingSession.append(second, pieces: [TranscriptPiece(start: 2, end: 6, text: "Follow-up.")],
                              transcript: "Follow-up.", summary: "Second.", to: artifact, after: note.recordings)
        note.recordings.append(second)
        try context.save()

        // After the first recording's 60 s, not its last word at 4 s.
        #expect(second.transcriptOffset == 60)
        let segments = artifact.segments.sorted { $0.startTime < $1.startTime }
        #expect(segments.map(\.text) == ["Hello there.", "Follow-up."])
        #expect(segments[1].startTime == 62 && segments[1].endTime == 66)
        #expect(artifact.fullTranscript == "Hello there.\n\nFollow-up.")
        #expect(artifact.summary == "First.\n\nSecond.")

        // A jump to the new words plays the second recording, 2 s in.
        let recordings = note.recordings.sorted { $0.createdAt < $1.createdAt }
        let index = try #require(AudioClock.source(at: 62, starts: recordings.map(\.transcriptOffset)))
        #expect(recordings[index] === second)
        #expect(62 - recordings[index].transcriptOffset == 2)
    }
}
