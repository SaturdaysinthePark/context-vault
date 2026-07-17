import Foundation

/// Normalizes source content into plain, indexable text.
/// Strips Markdown syntax noise while preserving the words that matter for
/// semantic indexing; extracts a title when the document provides one.
enum MarkdownNormalizer {
    struct Result {
        var title: String
        var body: String
    }

    static func normalize(filename: String, rawMarkdown: String) -> Result {
        var lines = rawMarkdown.components(separatedBy: .newlines)

        // Strip YAML front matter.
        if lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") {
            lines.removeSubrange(0...end)
        }

        // Title: first H1 wins, else the filename without extension.
        var title = (filename as NSString).deletingPathExtension
        if let h1Index = lines.firstIndex(where: { $0.hasPrefix("# ") }) {
            title = String(lines[h1Index].dropFirst(2)).trimmingCharacters(in: .whitespaces)
            lines.remove(at: h1Index)
        }

        let body = lines
            .map(stripInlineSyntax)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Result(title: title, body: body)
    }

    private static func stripInlineSyntax(_ line: String) -> String {
        var s = line
        // Heading markers, blockquotes, list bullets.
        s = s.replacing(/^#{1,6}\s+/, with: "")
        s = s.replacing(/^>\s?/, with: "")
        s = s.replacing(/^[-*+]\s+/, with: "")
        // Wiki links [[Note|Alias]] -> Alias, [[Note]] -> Note.
        s = s.replacing(/\[\[([^\]|]+)\|([^\]]+)\]\]/) { String($0.output.2) }
        s = s.replacing(/\[\[([^\]]+)\]\]/) { String($0.output.1) }
        // Markdown links [text](url) -> text.
        s = s.replacing(/\[([^\]]+)\]\([^)]+\)/) { String($0.output.1) }
        // Emphasis and inline code markers.
        s = s.replacingOccurrences(of: "**", with: "")
        s = s.replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: "`", with: "")
        return s
    }
}
