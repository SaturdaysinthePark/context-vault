import Foundation

/// Splits normalized text into retrieval-sized chunks.
///
/// The on-device Foundation Model has a small context window (4K tokens on
/// iOS 26, 8K on iOS 27), so chunks are sized well below that to leave room
/// for instructions, the question, and multiple retrieved chunks. Sizes are
/// in characters (~4 chars/token as a working ratio).
enum Chunker {
    struct Chunk: Equatable {
        var index: Int
        var text: String
    }

    static let targetSize = 1600   // ~400 tokens
    static let overlap = 200       // keep continuity across boundaries

    static func chunk(_ text: String, targetSize: Int = targetSize, overlap: Int = overlap) -> [Chunk] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.count > targetSize else { return [Chunk(index: 0, text: trimmed)] }

        // Prefer paragraph boundaries; fall back to hard splits inside
        // paragraphs that exceed the target on their own.
        var paragraphs: [String] = []
        for p in trimmed.components(separatedBy: "\n\n") {
            let para = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !para.isEmpty else { continue }
            if para.count <= targetSize {
                paragraphs.append(para)
            } else {
                paragraphs.append(contentsOf: hardSplit(para, size: targetSize))
            }
        }

        var chunks: [Chunk] = []
        var current = ""
        for para in paragraphs {
            if current.isEmpty {
                current = para
            } else if current.count + para.count + 2 <= targetSize {
                current += "\n\n" + para
            } else {
                chunks.append(Chunk(index: chunks.count, text: current))
                let tail = String(current.suffix(overlap))
                current = tail + "\n\n" + para
            }
        }
        if !current.isEmpty {
            chunks.append(Chunk(index: chunks.count, text: current))
        }
        return chunks
    }

    private static func hardSplit(_ text: String, size: Int) -> [String] {
        var result: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            let end = text.index(start, offsetBy: size, limitedBy: text.endIndex) ?? text.endIndex
            result.append(String(text[start..<end]))
            start = end
        }
        return result
    }
}
