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
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}

/// The note list with the launch mark over it. The mark plays once per launch and then
/// removes itself, so the list is already loaded behind it by the time it clears.
private struct RootView: View {
    /// Per process, not per scene, so a new iPad or Mac window opens straight to the list.
    @MainActor private static var didShowLaunchMark = false
    @State private var showLaunchMark = !RootView.didShowLaunchMark

    var body: some View {
        NoteListView() // Entry point — replaces hello-world placeholder
            .navigationViewStyle(.stack)
            .overlay {
                if showLaunchMark {
                    // The splash fades itself out at the end of its own sequence, so this
                    // just removes it afterwards rather than animating a second time.
                    LaunchSplashView { showLaunchMark = false }
                        .onAppear { Self.didShowLaunchMark = true }
                }
            }
    }
}
