import Testing
import Foundation
@testable import ContextVault

struct FileEnricherTests {
    @Test func routesGoogleNativeTypesToExport() {
        #expect(FileEnricher.strategy(for: "application/vnd.google-apps.document", inEnrichmentScope: false)
                == .export(mime: "text/plain"))
        #expect(FileEnricher.strategy(for: "application/vnd.google-apps.spreadsheet", inEnrichmentScope: false)
                == .export(mime: "text/csv"))
        #expect(FileEnricher.strategy(for: "application/vnd.google-apps.presentation", inEnrichmentScope: false)
                == .export(mime: "text/plain"))
    }

    @Test func routesTextAndPDF() {
        #expect(FileEnricher.strategy(for: "text/markdown", inEnrichmentScope: false) == .downloadText)
        #expect(FileEnricher.strategy(for: "text/plain", inEnrichmentScope: false) == .downloadText)
        #expect(FileEnricher.strategy(for: "application/pdf", inEnrichmentScope: false) == .pdf)
    }

    @Test func zipBasedDocumentsGetRealExtraction() {
        #expect(FileEnricher.strategy(for: "application/epub+zip", inEnrichmentScope: false) == .zipDocument)
        #expect(FileEnricher.strategy(
            for: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            inEnrichmentScope: false
        ) == .zipDocument)
    }

    @Test func otherDocumentTypesAlwaysGetAtLeastMetadata() {
        for mime in ["application/rtf", "application/vnd.ms-excel"] {
            #expect(FileEnricher.strategy(for: mime, inEnrichmentScope: false) == .metadataOnly)
        }
    }

    @Test func mediaOnlyCountsInsideEnrichmentScope() {
        #expect(FileEnricher.strategy(for: "image/png", inEnrichmentScope: false) == .skip)
        #expect(FileEnricher.strategy(for: "image/png", inEnrichmentScope: true) == .metadataOnly)
        #expect(FileEnricher.strategy(for: "video/mp4", inEnrichmentScope: false) == .skip)
        #expect(FileEnricher.strategy(for: "audio/mpeg", inEnrichmentScope: true) == .metadataOnly)
    }

    @Test func systemTypesAreSkipped() {
        #expect(FileEnricher.strategy(for: "application/vnd.google-apps.folder", inEnrichmentScope: true) == .skip)
        #expect(FileEnricher.strategy(for: "application/vnd.google-apps.shortcut", inEnrichmentScope: true) == .skip)
    }

    @Test func stubBodyMentionsNameKindAndLocation() {
        let body = FileEnricher.stubBody(
            name: "Atomic Habits.epub",
            kind: "EPUB",
            folderPath: "/eBooks",
            modified: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(body.contains("Atomic Habits.epub"))
        #expect(body.contains("EPUB"))
        #expect(body.contains("/eBooks"))
        #expect(body.contains("indexed"))
    }

    @Test func fileKindLabels() {
        #expect(FileEnricher.fileKind(for: "application/pdf") == "PDF")
        #expect(FileEnricher.fileKind(for: "application/epub+zip") == "EPUB")
        #expect(FileEnricher.fileKind(for: "image/jpeg") == "Image")
        #expect(FileEnricher.fileKind(for: "application/octet-stream") == "File")
    }

    @Test func pdfExtractionReturnsNilForGarbage() {
        #expect(FileEnricher.extractPDFText(Data("not a pdf".utf8)) == nil)
    }
}
