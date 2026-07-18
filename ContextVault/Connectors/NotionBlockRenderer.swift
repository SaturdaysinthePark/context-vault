import Foundation

/// Converts Notion block JSON into Markdown-ish plain text. Pure functions
/// over decoded JSON dictionaries so it's unit-testable without networking.
enum NotionBlockRenderer {

    /// Render an array of block objects (as decoded JSON dictionaries).
    /// `children` maps a block ID to its fetched child blocks (one level).
    static func render(blocks: [[String: Any]], children: [String: [[String: Any]]] = [:]) -> String {
        var lines: [String] = []
        var numberedIndex = 0

        for block in blocks {
            guard let type = block["type"] as? String else { continue }
            if type == "numbered_list_item" { numberedIndex += 1 } else { numberedIndex = 0 }

            guard let rendered = renderBlock(block, type: type, numberedIndex: numberedIndex) else { continue }
            lines.append(rendered)

            if let id = block["id"] as? String, let kids = children[id], !kids.isEmpty {
                let childText = render(blocks: kids, children: children)
                lines.append(contentsOf: childText
                    .components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .map { "  \($0)" })
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func renderBlock(_ block: [String: Any], type: String, numberedIndex: Int) -> String? {
        guard let payload = block[type] as? [String: Any] else { return nil }
        let text = richText(payload)

        switch type {
        case "paragraph":
            return text.isEmpty ? nil : text
        case "heading_1":
            return "# \(text)"
        case "heading_2":
            return "## \(text)"
        case "heading_3":
            return "### \(text)"
        case "bulleted_list_item":
            return "- \(text)"
        case "numbered_list_item":
            return "\(numberedIndex). \(text)"
        case "to_do":
            let checked = payload["checked"] as? Bool ?? false
            return "- [\(checked ? "x" : " ")] \(text)"
        case "quote":
            return "> \(text)"
        case "callout":
            return "> \(text)"
        case "code":
            let language = payload["language"] as? String ?? ""
            return "```\(language)\n\(text)\n```"
        case "toggle":
            return text.isEmpty ? nil : text
        case "divider":
            return "---"
        default:
            // Unsupported block types (tables, embeds, media…) are skipped.
            return nil
        }
    }

    /// Concatenate a block payload's rich_text runs into plain text.
    static func richText(_ payload: [String: Any]) -> String {
        guard let runs = payload["rich_text"] as? [[String: Any]] else { return "" }
        return runs.compactMap { $0["plain_text"] as? String }.joined()
    }

    /// Extract a page title from a page object's properties.
    static func pageTitle(from page: [String: Any]) -> String {
        guard let properties = page["properties"] as? [String: Any] else { return "Untitled" }
        for value in properties.values {
            guard let property = value as? [String: Any],
                  property["type"] as? String == "title",
                  let runs = property["title"] as? [[String: Any]] else { continue }
            let title = runs.compactMap { $0["plain_text"] as? String }.joined()
            return title.isEmpty ? "Untitled" : title
        }
        return "Untitled"
    }
}
