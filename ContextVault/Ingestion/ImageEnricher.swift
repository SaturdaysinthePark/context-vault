import Foundation
import Vision
import UIKit

/// On-device image understanding: OCR (screenshots, receipts, whiteboards
/// are text goldmines) plus scene classification for a one-line caption.
/// Only runs for images inside explicitly chosen folders — effort follows
/// user intent. TODO(iOS 27): upgrade captioning to the Foundation Models
/// vision capability.
enum ImageEnricher {

    struct Result {
        var text: String
        var fidelity: ContentFidelity
    }

    static func enrich(data: Data, filename: String) -> Result? {
        guard let cgImage = UIImage(data: data)?.cgImage else { return nil }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        let classifyRequest = VNClassifyImageRequest()

        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([textRequest, classifyRequest])

        let recognizedText = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let labels = (classifyRequest.results ?? [])
            .filter { $0.confidence > 0.4 }
            .prefix(5)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }

        var parts: [String] = []
        if !labels.isEmpty {
            parts.append("\(filename) — an image of: \(labels.joined(separator: ", ")).")
        }
        if !recognizedText.isEmpty {
            parts.append("Text found in the image:\n\(String(recognizedText.prefix(8000)))")
        }
        guard !parts.isEmpty else { return nil }
        return Result(text: parts.joined(separator: "\n\n"), fidelity: .captioned)
    }
}
