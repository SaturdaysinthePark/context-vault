import Foundation
import PDFKit

/// Per-file-type enrichment strategies: decide what we can extract from a
/// file and synthesize indexable text for what we can't. The mimetype map is
/// source-agnostic so future connectors (Dropbox, …) reuse it.
enum FileEnricher {

    enum Strategy: Equatable {
        /// Google-native file: export via Drive with this mimetype, content is text.
        case export(mime: String)
        /// Download; content is already text.
        case downloadText
        /// Download; extract text with PDFKit.
        case pdf
        /// Download; unzip and extract text (EPUB/DOCX). Phase 3.
        case zipDocument
        /// Download; OCR + classify. Phase 4, only in enrichment scope.
        case image
        /// Don't download; synthesize a metadata memory from the listing row.
        case metadataOnly
        /// Ignore entirely.
        case skip
    }

    /// Max bytes we'll download for content extraction.
    static let downloadCap = 15 * 1024 * 1024

    // MARK: Routing

    /// Decide handling for a file. `inEnrichmentScope` = the file sits inside
    /// folders the user explicitly selected (sync scope or a collection
    /// subscription) — effort follows explicit intent; media outside scope is
    /// skipped so a whole-Drive sync doesn't flood the vault.
    static func strategy(for mimeType: String, inEnrichmentScope: Bool) -> Strategy {
        switch mimeType {
        case "application/vnd.google-apps.document":
            return .export(mime: "text/plain")
        case "application/vnd.google-apps.spreadsheet":
            return .export(mime: "text/csv")
        case "application/vnd.google-apps.presentation":
            return .export(mime: "text/plain")
        case let mime where mime.hasPrefix("text/"):
            return .downloadText
        case "application/pdf":
            return .pdf
        case "application/epub+zip",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            return .zipDocument
        case "application/zip", "application/x-zip-compressed":
            return inEnrichmentScope ? .zipDocument : .skip
        case let mime where mime.hasPrefix("image/"):
            return inEnrichmentScope ? .image : .skip
        case let mime where mime.hasPrefix("audio/") || mime.hasPrefix("video/"):
            return inEnrichmentScope ? .metadataOnly : .skip
        case "application/vnd.google-apps.folder",
             "application/vnd.google-apps.shortcut",
             "application/vnd.google-apps.form",
             "application/vnd.google-apps.map":
            return .skip
        case "application/msword",
             "application/rtf",
             "application/vnd.oasis.opendocument.text",
             "application/vnd.openxmlformats-officedocument.presentationml.presentation",
             "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
             "application/vnd.apple.pages",
             "application/vnd.apple.keynote",
             "application/vnd.apple.numbers",
             "application/vnd.ms-excel",
             "application/vnd.ms-powerpoint":
            return .metadataOnly
        default:
            // Unknown types: worth knowing about if the user scoped the
            // folder; noise otherwise.
            return inEnrichmentScope ? .metadataOnly : .skip
        }
    }

    /// Short human label for a mimetype.
    static func fileKind(for mimeType: String) -> String {
        switch mimeType {
        case "application/vnd.google-apps.document": "Google Doc"
        case "application/vnd.google-apps.spreadsheet": "Sheet"
        case "application/vnd.google-apps.presentation": "Slides"
        case "application/pdf": "PDF"
        case "application/epub+zip": "EPUB"
        case "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
             "application/msword": "Word doc"
        case "application/vnd.openxmlformats-officedocument.presentationml.presentation",
             "application/vnd.ms-powerpoint": "Presentation"
        case "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
             "application/vnd.ms-excel": "Spreadsheet"
        case "application/zip", "application/x-zip-compressed": "Archive"
        case "application/rtf": "RTF"
        case let mime where mime.hasPrefix("image/"): "Image"
        case let mime where mime.hasPrefix("audio/"): "Audio"
        case let mime where mime.hasPrefix("video/"): "Video"
        case let mime where mime.hasPrefix("text/"): "Text"
        default: "File"
        }
    }

    // MARK: Metadata stubs

    /// Indexable body for a file whose content we can't read (yet). Even
    /// metadata lets Siri/chat answer "do I have X / where is it".
    static func stubBody(name: String, kind: String, folderPath: String?, modified: Date) -> String {
        let location = folderPath.map { " in \($0)" } ?? ""
        let date = modified.formatted(date: .abbreviated, time: .omitted)
        return """
            \(name) — a \(kind)\(location), last modified \(date). \
            The file's content isn't readable in Context Vault yet; its name, \
            type, and location are indexed so you can still find and ask about it.
            """
    }

    // MARK: PDF

    /// Extract a PDF's text layer. Returns nil for scanned/image-only PDFs
    /// (OCR fallback arrives with image enrichment in phase 4).
    static func extractPDFText(_ data: Data, pageCap: Int = 100) -> String? {
        guard let document = PDFDocument(data: data) else { return nil }
        var pages: [String] = []
        for index in 0..<min(document.pageCount, pageCap) {
            if let text = document.page(at: index)?.string {
                pages.append(text)
            }
        }
        let combined = pages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }
}
