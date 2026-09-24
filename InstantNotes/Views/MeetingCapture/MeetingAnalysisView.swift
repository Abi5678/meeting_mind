//
//  MeetingAnalysisView.swift
//  Instant Notes
//
// Displays the meeting summary as blocks using the paper design identity.

import SwiftUI
import MeetingMindKit

struct MeetingAnalysisView: View {
    let analysis: MeetingAnalysis

    var body: some View {
        VStack(spacing: 20) {
            // Summary section
            if !analysis.summary.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Summary", systemImage: "text.alignleft")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    Text(analysis.summary)
                        .font(.body)
                        .lineSpacing(2)
                }
                .padding(16)
                .background(Color("PaperBackground").opacity(0.9).cornerRadius(8))
            }

            // Key decisions
            if !analysis.keyDecisions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Key Decisions", systemImage: "checkmark.seal")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    ForEach(analysis.keyDecisions, id: \.self) { decision in
                        // Render each decision as a block
                        Text("• \(decision)")
                            .font(.body)
                            .lineSpacing(2)
                    }
                }
                .padding(16)
                .background(Color("PaperBackground").opacity(0.9).cornerRadius(8))
            }

            // Action items
            if !analysis.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Action Items", systemImage: "list.bullet.checkbox")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    ForEach(analysis.actionItems.indices, id: \.self) { i in
                        let item = analysis.actionItems[i]
                        HStack(spacing: 8) {
                            Image(systemName: "circle")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(item.task)
                                .font(.body)
                            Spacer()
                            if let owner = item.owner, !owner.isEmpty {
                                Text(owner)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color("PaperBackground").opacity(0.9).cornerRadius(8))
            }

            // Follow-up email draft
            let email = analysis.followUpEmail
            if !email.subject.isEmpty || !email.body.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Follow-up Draft", systemImage: "envelope")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    if !email.subject.isEmpty {
                        Text("Subject: \(email.subject)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !email.body.isEmpty {
                        Text(email.body)
                            .font(.body)
                            .lineSpacing(2)
                    }
                }
                .padding(16)
                .background(Color("PaperBackground").opacity(0.9).cornerRadius(8))
            }
        }
    }
}
