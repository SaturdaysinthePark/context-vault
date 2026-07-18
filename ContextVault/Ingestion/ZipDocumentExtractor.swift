import Foundation
import ZIPFoundation

/// Text extraction for zip-based formats. EPUB and DOCX are literally zip
/// archives of XHTML/XML — unzip, strip tags, done. Plain archives yield a
/// contents listing, which is still useful context ("what's in that zip?").
enum ZipDocumentExtractor {

    struct Result {
        var text: String
        var fidelity: ContentFidelity
    }

    static let textCap = 200_000 // chars, keep giant books bounded

    /// Extract whatever text the archive offers.
    static func extract(data: Data, filename: String) -> Result? {
        guard let archive = try? Archive(data: data, accessMode: .read) else { return nil }
        let entryPaths = archive.map(\.path)

        // DOCX: the document body lives in word/document.xml.
        if entryPaths.contains("word/document.xml") {
            if let xml = read(archive, path: "word/document.xml") {
                // Word separates runs/paragraphs with tags; keep paragraph breaks.
                let withBreaks = xml
                    .replacingOccurrences(of: "</w:p>", with: "\n")
                    .replacingOccurrences(of: "<w:tab/>", with: "\t")
                let text = stripTags(withBreaks)
                if !text.isEmpty {
                    return Result(text: String(text.prefix(textCap)), fidelity: .extracted)
                }
            }
        }

        // EPUB: concatenate the XHTML chapters in archive order.
        let chapterPaths = entryPaths.filter {
            $0.hasSuffix(".xhtml") || $0.hasSuffix(".html") || $0.hasSuffix(".htm")
        }
        if !chapterPaths.isEmpty {
            var chapters: [String] = []
            var total = 0
            for path in chapterPaths {
                guard total < textCap, let html = read(archive, path: path) else { continue }
                let text = stripTags(html)
                guard !text.isEmpty else { continue }
                chapters.append(text)
                total += text.count
            }
            if !chapters.isEmpty {
                return Result(text: String(chapters.joined(separator: "\n\n").prefix(textCap)), fidelity: .extracted)
            }
        }

        // Plain archive: a contents listing is real context.
        let listing = entryPaths
            .filter { !$0.hasSuffix("/") }
            .prefix(40)
            .joined(separator: ", ")
        guard !listing.isEmpty else { return nil }
        let more = entryPaths.count > 40 ? " and \(entryPaths.count - 40) more files" : ""
        return Result(
            text: "\(filename) — an archive containing: \(listing)\(more).",
            fidelity: .metadataOnly
        )
    }

    // MARK: Helpers

    private static func read(_ archive: Archive, path: String) -> String? {
        guard let entry = archive[path] else { return nil }
        var data = Data()
        _ = try? archive.extract(entry) { chunk in
            data.append(chunk)
        }
        return String(data: data, encoding: .utf8)
    }

    /// Strip XML/HTML tags, decode common entities, collapse whitespace.
    static func stripTags(_ markup: String) -> String {
        var text = markup
        // Drop head/style/script blocks wholesale.
        text = text.replacing(#/(?i)<(head|style|script)[^>]*>[\s\S]*?</\1>/#, with: " ")
        // Block-level closers become newlines so paragraphs survive.
        text = text.replacing(#/(?i)</(p|div|h[1-6]|li|tr|br)>/#, with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacing(#/<[^>]+>/#, with: " ")
        for (entity, plain) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " ")] {
            text = text.replacingOccurrences(of: entity, with: plain)
        }
        // Collapse runs of spaces/tabs, keep newlines meaningful.
        text = text.replacing(#/[ \t]+/#, with: " ")
        text = text.replacing(#/\n{3,}/#, with: "\n\n")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
