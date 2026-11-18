import Foundation

/// A mail message reduced to what the vault needs.
struct ParsedMail: Sendable, Equatable {
    var id: String
    var threadID: String
    var subject: String
    /// The From header: "Amazon.com <ship-confirm@amazon.com>".
    var sender: String
    var date: Date
    /// The readable body as plain text.
    var text: String
    /// schema.org JSON-LD blocks found in the HTML body.
    var structuredData: [String]
    var labelIDs: [String]
}

/// Turns a Gmail API message (`users.messages.get`, `format=full`) into
/// plain text plus any structured data. Pure and synchronous.
///
/// The HTML body is read for two things and then discarded: the JSON-LD
/// blocks senders embed to describe an order or booking, and the readable
/// text. Attachments are ignored.
enum GmailMessageParser {

    // MARK: Gmail API shapes

    struct Message: Decodable {
        var id: String
        var threadId: String
        var labelIds: [String]?
        var snippet: String?
        /// Milliseconds since 1970, as a string.
        var internalDate: String?
        var payload: Part?
    }

    struct Part: Decodable {
        var mimeType: String?
        var filename: String?
        var headers: [Header]?
        var body: Body?
        var parts: [Part]?
    }

    struct Header: Decodable {
        var name: String
        var value: String
    }

    struct Body: Decodable {
        var size: Int?
        /// base64url-encoded content.
        var data: String?
    }

    // MARK: Parsing

    static func parse(_ data: Data) throws -> ParsedMail {
        parse(try JSONDecoder().decode(Message.self, from: data))
    }

    static func parse(_ message: Message) -> ParsedMail {
        let headers = message.payload?.headers ?? []
        func header(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }

        var plain: String?
        var html: String?
        if let payload = message.payload {
            collectBodies(payload, plain: &plain, html: &html)
        }

        let htmlText = html.map(plainText(fromHTML:))
        let text: String
        switch (plain?.trimmingCharacters(in: .whitespacesAndNewlines), htmlText) {
        case let (plain?, htmlText?):
            // Many senders ship a token plain part ("View this email in
            // your browser") beside the real HTML. Prefer the fuller one.
            text = plain.count * 3 < htmlText.count ? htmlText : plain
        case let (plain?, nil):
            text = plain
        case let (nil, htmlText?):
            text = htmlText
        default:
            text = message.snippet ?? ""
        }

        let milliseconds = message.internalDate.flatMap(Double.init) ?? 0
        return ParsedMail(
            id: message.id,
            threadID: message.threadId,
            subject: decodeEncodedWords(header("Subject")),
            sender: decodeEncodedWords(header("From")),
            date: milliseconds > 0 ? Date(timeIntervalSince1970: milliseconds / 1000) : .now,
            text: collapseWhitespace(text),
            structuredData: html.map(SchemaOrgExtractor.jsonLDBlocks(inHTML:)) ?? [],
            labelIDs: message.labelIds ?? []
        )
    }

    /// Walks the MIME tree for the first text/plain and text/html bodies,
    /// skipping attachments.
    private static func collectBodies(_ part: Part, plain: inout String?, html: inout String?) {
        let isAttachment = !(part.filename ?? "").isEmpty
        if !isAttachment, let encoded = part.body?.data, let data = decodeBase64URL(encoded) {
            let content = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            switch (part.mimeType ?? "").lowercased() {
            case "text/plain" where plain == nil: plain = content
            case "text/html" where html == nil: html = content
            default: break
            }
        }
        for child in part.parts ?? [] {
            collectBodies(child, plain: &plain, html: &html)
        }
    }

    // MARK: Decoding helpers

    /// Gmail uses the URL-safe base64 alphabet, usually without padding.
    static func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64, options: .ignoreUnknownCharacters)
    }

    /// Decodes RFC 2047 encoded words in a header ("=?UTF-8?B?…?="), which
    /// is how non-ASCII subjects and sender names travel. Text without
    /// encoded words is returned unchanged.
    static func decodeEncodedWords(_ header: String) -> String {
        guard header.contains("=?"),
              let regex = try? NSRegularExpression(pattern: #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#) else {
            return header
        }
        // Rebuild the header left to right, replacing each encoded word.
        var result = ""
        var cursor = header.startIndex
        let matches = regex.matches(in: header, range: NSRange(header.startIndex..., in: header))
        for match in matches {
            guard let whole = Range(match.range, in: header),
                  let charsetRange = Range(match.range(at: 1), in: header),
                  let encodingRange = Range(match.range(at: 2), in: header),
                  let payloadRange = Range(match.range(at: 3), in: header) else { continue }

            // Whitespace between two adjacent encoded words is not content.
            let between = header[cursor..<whole.lowerBound]
            let isGapBetweenWords = cursor != header.startIndex
                && between.allSatisfy { $0 == " " || $0 == "\t" }
            if !isGapBetweenWords {
                result += between
            }

            let charset = header[charsetRange].lowercased()
            let payload = String(header[payloadRange])
            let data: Data?
            if header[encodingRange].lowercased() == "b" {
                data = Data(base64Encoded: payload)
            } else {
                data = decodeQEncoding(payload)
            }
            let encoding: String.Encoding = charset.contains("8859-1") || charset.contains("1252") ? .isoLatin1 : .utf8
            if let data, let decoded = String(data: data, encoding: encoding) {
                result += decoded
            } else {
                result += header[whole]
            }
            cursor = whole.upperBound
        }
        result += header[cursor...]
        return result
    }

    /// "Q" encoding: underscores are spaces and =XX is a hex byte.
    private static func decodeQEncoding(_ text: String) -> Data {
        var bytes: [UInt8] = []
        var iterator = Array(text.utf8).makeIterator()
        while let byte = iterator.next() {
            if byte == UInt8(ascii: "_") {
                bytes.append(UInt8(ascii: " "))
            } else if byte == UInt8(ascii: "="),
                      let high = iterator.next(), let low = iterator.next(),
                      let value = UInt8(String(decoding: [high, low], as: UTF8.self), radix: 16) {
                bytes.append(value)
            } else {
                bytes.append(byte)
            }
        }
        return Data(bytes)
    }

    // MARK: HTML to text

    /// A deliberately small HTML-to-text conversion: drop what is not
    /// content, turn block boundaries into line breaks, strip the tags,
    /// decode entities. Good enough for a model and a search index to
    /// read; it does not try to preserve layout.
    static func plainText(fromHTML html: String) -> String {
        var text = html

        // Remove elements whose content is not readable text.
        for element in ["script", "style", "head", "title"] {
            text = replace(text, pattern: "<\(element)\\b[^>]*>[\\s\\S]*?</\(element)>", with: " ")
        }
        text = replace(text, pattern: "<!--[\\s\\S]*?-->", with: " ")

        // Block boundaries become line breaks; table cells become spaces.
        text = replace(text, pattern: "<br\\s*/?>", with: "\n")
        text = replace(text, pattern: "</(p|div|tr|li|h[1-6]|table|blockquote|section|article)>", with: "\n")
        text = replace(text, pattern: "</(td|th)>", with: " ")

        // Everything else that looks like a tag goes.
        text = replace(text, pattern: "<[^>]+>", with: "")

        return collapseWhitespace(decodeEntities(text))
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named: [(String, String)] = [
            ("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"),
            ("&rsquo;", "’"), ("&lsquo;", "‘"), ("&rdquo;", "”"), ("&ldquo;", "“"),
            ("&copy;", "©"), ("&reg;", "®"), ("&trade;", "™"), ("&zwnj;", ""), ("&zwj;", "")
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }

        // "&amp;" goes last, so "&amp;lt;" becomes "&lt;" and stops there
        // instead of being decoded a second time.
        func decodingAmpersands(_ text: String) -> String {
            text.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
        }

        // Numeric entities: &#8217; and &#x2019;
        guard result.contains("&#"),
              let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);", options: [.caseInsensitive]) else {
            return decodingAmpersands(result)
        }
        let source = result
        var decoded = ""
        var cursor = source.startIndex
        for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            guard let whole = Range(match.range, in: source),
                  let hexRange = Range(match.range(at: 1), in: source),
                  let digitsRange = Range(match.range(at: 2), in: source) else { continue }
            decoded += source[cursor..<whole.lowerBound]
            if let value = UInt32(source[digitsRange], radix: source[hexRange].isEmpty ? 10 : 16),
               let scalar = Unicode.Scalar(value) {
                decoded.unicodeScalars.append(scalar)
            } else {
                decoded += source[whole]
            }
            cursor = whole.upperBound
        }
        decoded += source[cursor...]
        return decodingAmpersands(decoded)
    }

    /// Collapses runs of spaces and blank lines, and trims each line.
    static func collapseWhitespace(_ text: String) -> String {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: "\n")
            .map { line in
                line.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            }

        var result: [String] = []
        var previousBlank = true
        for line in lines {
            let blank = line.isEmpty
            if blank && previousBlank { continue }
            result.append(line)
            previousBlank = blank
        }
        while result.last?.isEmpty == true { result.removeLast() }
        return result.joined(separator: "\n")
    }

    private static func replace(_ text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
