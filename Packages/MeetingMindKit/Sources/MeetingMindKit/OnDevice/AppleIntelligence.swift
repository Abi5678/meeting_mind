import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Every AI feature runs on Apple's on-device model, so each one checks here first.
public enum AppleIntelligence {
    /// Why the on-device model can't run right now, in words for the user; nil when it can.
    public static var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.deviceNotEligible):
                return "This needs a device with Apple Intelligence: iPhone 15 Pro or later, or an iPad or Mac with an M-series chip."
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Turn on Apple Intelligence in Settings to use this."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still getting ready on this device. Try again in a few minutes."
            case .unavailable:
                return "Apple Intelligence isn't available on this device right now."
            }
        }
        #endif
        return "This needs Apple Intelligence, which comes with iOS 26 on supported devices."
    }
}

public enum OnDeviceAIError: Error, Equatable, Sendable {
    /// There is no note text to work from.
    case emptyNotes
    /// The model found nothing in the notes to ask about.
    case notEnoughContent
    /// The meeting has no transcript or notes to answer from.
    case emptyMeeting
    /// The model answered with nothing.
    case emptyResponse
}

extension OnDeviceAIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyNotes: "Write a few notes first."
        case .notEnoughContent: "There isn't enough in this note to quiz you on yet. Add a few more lines."
        case .emptyMeeting: "This meeting has no transcript or notes to answer from yet."
        case .emptyResponse: "Apple Intelligence didn't come back with an answer. Try asking another way."
        }
    }
}

extension String {
    /// The first `maxWords` words, so a long note can't overflow the on-device model's context.
    func prefix(words maxWords: Int) -> String {
        let words = split(whereSeparator: \.isWhitespace)
        return words.count <= maxWords ? self : words.prefix(maxWords).joined(separator: " ")
    }
}
