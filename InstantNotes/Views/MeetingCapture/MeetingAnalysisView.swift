//
//  MeetingAnalysisView.swift
//  Instant Notes
//
// Displays Gemini analysis results as blocks using the paper design identity.

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

                    ForEach(analysis.keyDecisions.indices.map { String($0) }, id: \.self) { _ in
                        // Render each decision as a block
                        Text("• \(getDecision(at: Int(_)!).text)")
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

                    ForEach(analysis.actionItems.indices.map { String($0) }, id: \.self) { i in
                        let item = analysis.actionItems[Int(i)!]
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
            if let email = analysis.followUpEmail, !email.subject.isEmpty || !email.body.isEmpty {
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

            // Insert as note button
            Button { /* action: convert analysis to blocks and insert into current note */ } label: {
                HStack(spacing: 8) {
                    Image(systemName: "note.text.badge.plus")
                    Text("Insert into Note")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func getDecision(at index: Int) -> MeetingAnalysis.Decision {
        guard index >= 0, index < analysis.keyDecisions.count else {
            return MeetingAnalysis.Decision(text: "")
        }
        return analysis.keyDecisions[index]
    }
}

extension MeetingAnalysis {
    struct Decision: Codable {
        var text: String
    }

    struct ActionItem: Codable {
        var task: String
        var owner: String? = nil
        var due: String? = nil
    }

    struct FollowUpEmail: Codable {
        var subject: String = ""
        var body: String = ""
    }
}

struct MeetingAnalysis: Codable, Identifiable {
    let id = UUID()
    let summary: String
    let keyDecisions: [Decision]
    let actionItems: [ActionItem]
    let followUpEmail: FollowUpEmail?

    enum CodingKeys: String, CodingKey {
        case summary, keyDecisions, actionItems, followUpEmail
    }
}
