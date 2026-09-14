//
//  AISettingsView.swift
//  Instant Notes
//
// Settings UI for AI configuration (API key, model selection).

import SwiftUI

struct AISettingsView: View {
    @State private var apiKey = ""
    @AppStorage("gemini_model") private var modelName = "gemini-3-flash-preview"
    @AppStorage("ai_enabled") private var aiEnabled = true
    @Environment(\.dismiss) private var dismiss

    init() {
        _apiKey = State(wrappedValue: KeychainHelper().getString(forKey: "gemini_api_key") ?? "")
    }

    var body: some View {
        Form {
            Section("API Key") {
                HStack(spacing: 10) {
                    if !apiKey.isEmpty {
                        TextField("Enter API key", text: $apiKey)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                    } else {
                        Text("Not configured")
                            .foregroundStyle(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }

                    if !apiKey.isEmpty {
                        Button(role: .destructive) { apiKey = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Model") {
                Picker("Gemini Model", selection: $modelName) {
                    ForEach(geminiModels, id: \.name) { model in
                        Text(model.displayName).tag(model.name)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("AI Features") {
                Toggle("Auto-organize notes", isOn: $aiEnabled)

                if !apiKey.isEmpty {
                    Text("AI features are enabled and ready.")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Text("Enter an API key above to enable AI features (Gemini free tier).")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Section("Rate Limits") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free tier limits:")
                        .font(.subheadline.bold())
                    Text("• ~10-15 requests per minute\n• ~few hundred per day\n• AI runs on demand only — no background processing")
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .navigationTitle("AI Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if !apiKey.isEmpty {
                        KeychainHelper().set(apiKey, forKey: "gemini_api_key")
                    } else {
                        KeychainHelper().remove(forKey: "gemini_api_key")
                    }
                    dismiss()
                }
            }
        }
    }

    private var geminiModels: [GeminiModelOption] {
        [
            GeminiModelOption(name: "gemini-3-flash-preview", displayName: "Flash (Free tier)"),
            GeminiModelOption(name: "gemini-2.5-pro-preview-05-06", displayName: "Pro (Paid tier)"),
        ]
    }

    struct GeminiModelOption: Identifiable {
        let name: String
        let displayName: String
        var id: String { name }
    }
}

// MARK: - Keychain helper (stub for iOS — in production use Security.framework)

struct KeychainHelper {
    func getString(forKey key: String) -> String? {
        // Stub: returns nil on non-iOS targets
        #if os(iOS)
        guard let data = SecItemCopyMatchingKeyed(key), let result = String(data: data, encoding: .utf8) else {
            return nil
        }
        return result
        #else
        return UserDefaults.standard.string(forKey: "keychain_\(key)")
        #endif
    }

    func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        #if os(iOS)
        SecItemAddKeyed(key, data)
        #else
        UserDefaults.standard.set(value, forKey: "keychain_\(key)")
        #endif
    }

    func remove(forKey key: String) {
        #if os(iOS)
        SecItemDeleteKeyed(key)
        #else
        UserDefaults.standard.removeObject(forKey: "keychain_\(key)")
        #endif
    }
}
