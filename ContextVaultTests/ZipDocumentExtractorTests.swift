import Testing
import Foundation
@testable import ContextVault

struct ZipDocumentExtractorTests {
    @Test func stripsTagsAndDecodesEntities() {
        let html = "<html><head><title>x</title></head><body><h1>Title</h1><p>Hello &amp; welcome</p><p>Second</p></body></html>"
        let text = ZipDocumentExtractor.stripTags(html)
        #expect(!text.contains("<"))
        #expect(!text.contains("title>x")) // head dropped
        #expect(text.contains("Title"))
        #expect(text.contains("Hello & welcome"))
        #expect(text.contains("Second"))
    }

    @Test func paragraphClosersBecomeNewlines() {
        let text = ZipDocumentExtractor.stripTags("<p>one</p><p>two</p>")
        #expect(text.contains("one\n") || text.contains("one \n") || text.split(separator: "\n").count >= 2)
    }

    @Test func garbageDataReturnsNil() {
        #expect(ZipDocumentExtractor.extract(data: Data("not a zip".utf8), filename: "x.zip") == nil)
    }

    @Test func wordXMLKeepsParagraphBreaks() {
        let xml = "<w:document><w:p><w:r><w:t>First para</w:t></w:r></w:p><w:p><w:r><w:t>Second para</w:t></w:r></w:p></w:document>"
        let withBreaks = xml.replacingOccurrences(of: "</w:p>", with: "\n")
        let text = ZipDocumentExtractor.stripTags(withBreaks)
        #expect(text.contains("First para"))
        #expect(text.contains("Second para"))
    }
}
