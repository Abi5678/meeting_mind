//
//  InstantNotesApp.swift
//  Instant Notes
//
// iOS notes app with block editor, ink canvas, meeting capture, and AI organization.
// Phase 1 scaffold — full SwiftData model list for all phases.

import SwiftUI
import SwiftData
import MeetingMindKit

@main
struct InstantNotesApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // Phase 3 models (core)
            Note.self,
            Recording.self,
            MeetingArtifact.self,
            TranscriptSegment.self,
            MeetingChatMessage.self,

            // Tagging and organization
            Tag.self,

            // Phase 5 — planned
            TableEntity.self,
            ColumnEntity.self,
            RowEntity.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            NoteListView() // Entry point — replaces hello-world placeholder
                .navigationViewStyle(.stack)
        }
        .modelContainer(sharedModelContainer)
    }
}
