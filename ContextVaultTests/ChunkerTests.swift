import Testing
@testable import ContextVault

struct ChunkerTests {
    @Test func emptyTextProducesNoChunks() {
        #expect(Chunker.chunk("").isEmpty)
        #expect(Chunker.chunk("   \n\n  ").isEmpty)
    }

    @Test func shortTextIsSingleChunk() {
        let chunks = Chunker.chunk("Hello world")
        #expect(chunks.count == 1)
        #expect(chunks[0].text == "Hello world")
    }

    @Test func longTextSplitsAtParagraphs() {
        let paragraph = String(repeating: "word ", count: 100).trimmingCharacters(in: .whitespaces)
        let text = Array(repeating: paragraph, count: 10).joined(separator: "\n\n")
        let chunks = Chunker.chunk(text)
        #expect(chunks.count > 1)
        for chunk in chunks {
            // Overlap tails can push slightly past target; allow headroom.
            #expect(chunk.text.count <= Chunker.targetSize + Chunker.overlap + paragraph.count)
        }
    }

    @Test func oversizedParagraphIsHardSplit() {
        let text = String(repeating: "x", count: Chunker.targetSize * 3)
        let chunks = Chunker.chunk(text)
        #expect(chunks.count >= 3)
    }

    @Test func indicesAreSequential() {
        let paragraph = String(repeating: "word ", count: 100)
        let text = Array(repeating: paragraph, count: 8).joined(separator: "\n\n")
        let chunks = Chunker.chunk(text)
        #expect(chunks.map(\.index) == Array(0..<chunks.count))
    }
}

struct MarkdownNormalizerTests {
    @Test func extractsH1Title() {
        let result = MarkdownNormalizer.normalize(
            filename: "note.md",
            rawMarkdown: "# My Title\n\nBody text here."
        )
        #expect(result.title == "My Title")
        #expect(result.body == "Body text here.")
    }

    @Test func fallsBackToFilename() {
        let result = MarkdownNormalizer.normalize(
            filename: "Meeting Notes.md",
            rawMarkdown: "Just some text."
        )
        #expect(result.title == "Meeting Notes")
    }

    @Test func stripsFrontMatter() {
        let md = "---\ntags: [a, b]\n---\nContent after front matter."
        let result = MarkdownNormalizer.normalize(filename: "x.md", rawMarkdown: md)
        #expect(!result.body.contains("tags:"))
        #expect(result.body.contains("Content after front matter."))
    }

    @Test func resolvesWikiLinks() {
        let result = MarkdownNormalizer.normalize(
            filename: "x.md",
            rawMarkdown: "See [[Other Note]] and [[Real Name|Alias]]."
        )
        #expect(result.body.contains("Other Note"))
        #expect(result.body.contains("Alias"))
        #expect(!result.body.contains("[["))
    }

    @Test func stripsMarkdownLinks() {
        let result = MarkdownNormalizer.normalize(
            filename: "x.md",
            rawMarkdown: "Read [the docs](https://example.com) today."
        )
        #expect(result.body.contains("the docs"))
        #expect(!result.body.contains("example.com"))
    }
}
