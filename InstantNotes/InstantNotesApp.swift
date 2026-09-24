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
        let types: [any PersistentModel.Type] = [
            // Phase 3 models (core)
            Note.self,
            Recording.self,
            MeetingArtifact.self,
            TranscriptSegment.self,
            MeetingChatMessage.self,
            NoteImage.self,

            // Tagging and organization
            Tag.self,

            // Phase 5 — planned
            TableEntity.self,
            ColumnEntity.self,
            RowEntity.self,
        ]
        let schema = Schema(types)
        #if DEBUG
        CloudSync.initializeSchema(for: types)
        #endif
        // Synced with the user's private iCloud database; without an iCloud account it simply
        // stays on the device.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .private(CloudSync.containerID)
        )
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            CloudSync.prepare(container.mainContext)
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// One for the app, so a recording keeps going across notes and windows.
    @StateObject private var noteRecorder = NoteRecorder()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(noteRecorder)
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
