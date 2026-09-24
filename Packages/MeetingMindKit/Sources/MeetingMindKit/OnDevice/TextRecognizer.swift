#if canImport(Vision)
import CoreGraphics
import Vision

/// Reads the text in a photo (a whiteboard, a slide, a receipt) on the device, so search can find it.
public enum TextRecognizer {
    /// The recognized lines, top to bottom, or "" when the photo has no text. Slow (about a
    /// second for a phone photo), so call it off the main actor.
    public static func text(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
#endif
