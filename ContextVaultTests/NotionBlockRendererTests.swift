import Testing
@testable import ContextVault

struct NotionBlockRendererTests {
    private func block(_ type: String, _ text: String, extra: [String: Any] = [:], id: String = "b1") -> [String: Any] {
        var payload: [String: Any] = ["rich_text": [["plain_text": text]]]
        payload.merge(extra) { a, _ in a }
        return ["id": id, "type": type, type: payload]
    }

    @Test func rendersBasicBlocks() {
        let text = NotionBlockRenderer.render(blocks: [
            block("heading_1", "Title"),
            block("paragraph", "Hello world"),
            block("bulleted_list_item", "Point one"),
            block("quote", "Wise words"),
        ])
        #expect(text.contains("# Title"))
        #expect(text.contains("Hello world"))
        #expect(text.contains("- Point one"))
        #expect(text.contains("> Wise words"))
    }

    @Test func numbersSequentialListItems() {
        let text = NotionBlockRenderer.render(blocks: [
            block("numbered_list_item", "First"),
            block("numbered_list_item", "Second"),
            block("paragraph", "Break"),
            block("numbered_list_item", "Restart"),
        ])
        #expect(text.contains("1. First"))
        #expect(text.contains("2. Second"))
        #expect(text.contains("1. Restart"))
    }

    @Test func rendersTodoCheckboxes() {
        let text = NotionBlockRenderer.render(blocks: [
            block("to_do", "Done thing", extra: ["checked": true]),
            block("to_do", "Open thing", extra: ["checked": false]),
        ])
        #expect(text.contains("- [x] Done thing"))
        #expect(text.contains("- [ ] Open thing"))
    }

    @Test func rendersCodeWithLanguage() {
        let text = NotionBlockRenderer.render(blocks: [
            block("code", "print(1)", extra: ["language": "swift"]),
        ])
        #expect(text.contains("```swift"))
        #expect(text.contains("print(1)"))
    }

    @Test func skipsUnsupportedAndEmptyBlocks() {
        let text = NotionBlockRenderer.render(blocks: [
            block("paragraph", ""),
            ["id": "x", "type": "image", "image": [String: Any]()],
            block("paragraph", "Kept"),
        ])
        #expect(text == "Kept")
    }

    @Test func indentsChildren() {
        let parent = block("bulleted_list_item", "Parent", id: "p1")
        let child = block("bulleted_list_item", "Child", id: "c1")
        let text = NotionBlockRenderer.render(blocks: [parent], children: ["p1": [child]])
        #expect(text.contains("- Parent"))
        #expect(text.contains("  - Child"))
    }

    @Test func concatenatesRichTextRuns() {
        let payload: [String: Any] = ["rich_text": [["plain_text": "Hello "], ["plain_text": "world"]]]
        #expect(NotionBlockRenderer.richText(payload) == "Hello world")
    }

    @Test func extractsPageTitle() {
        let page: [String: Any] = [
            "properties": [
                "Name": ["type": "title", "title": [["plain_text": "My Page"]]],
                "Tags": ["type": "multi_select"],
            ]
        ]
        #expect(NotionBlockRenderer.pageTitle(from: page) == "My Page")
        #expect(NotionBlockRenderer.pageTitle(from: [:]) == "Untitled")
    }
}
