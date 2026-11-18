import Foundation
import Testing
@testable import ContextVault

/// Turning Gmail API messages into text and structured data.
/// All fixtures are fictional.
struct GmailMessageParserTests {

    /// base64url without padding, as the Gmail API sends bodies.
    private func encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func message(plain: String? = nil, html: String? = nil, subject: String = "Your order has shipped") -> Data {
        var parts: [[String: Any]] = []
        if let plain {
            parts.append(["mimeType": "text/plain", "filename": "", "body": ["data": encode(plain)]])
        }
        if let html {
            parts.append(["mimeType": "text/html", "filename": "", "body": ["data": encode(html)]])
        }
        // An attachment whose content must be ignored.
        parts.append(["mimeType": "text/plain", "filename": "invoice.txt", "body": ["data": encode("ATTACHMENT")]])

        let json: [String: Any] = [
            "id": "msg-1",
            "threadId": "thread-1",
            "labelIds": ["CATEGORY_UPDATES", "INBOX"],
            "snippet": "Snippet text",
            "internalDate": "1794916800000",
            "payload": [
                "mimeType": "multipart/mixed",
                "headers": [
                    ["name": "From", "value": "Amazon.com <ship-confirm@example.com>"],
                    ["name": "subject", "value": subject]
                ],
                "parts": [["mimeType": "multipart/alternative", "parts": parts]]
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    @Test func headersDateAndIdentifiersAreRead() throws {
        let mail = try GmailMessageParser.parse(message(plain: "Your package is on its way."))

        #expect(mail.id == "msg-1")
        #expect(mail.threadID == "thread-1")
        #expect(mail.subject == "Your order has shipped")
        #expect(mail.sender == "Amazon.com <ship-confirm@example.com>")
        #expect(mail.date == Date(timeIntervalSince1970: 1_794_916_800))
        #expect(mail.labelIDs == ["CATEGORY_UPDATES", "INBOX"])
        #expect(mail.text == "Your package is on its way.")
    }

    @Test func attachmentsAreIgnored() throws {
        let mail = try GmailMessageParser.parse(message(plain: "Body text"))
        #expect(!mail.text.contains("ATTACHMENT"))
    }

    @Test func htmlIsReducedToReadableText() throws {
        let html = """
        <html><head><title>Ignored</title><style>p { color: red; }</style></head>
        <body>
          <h1>Shipped!</h1>
          <p>Your order of <b>The Twelve Kingdoms</b> is on its&nbsp;way.</p>
          <table><tr><td>Arriving</td><td>Thursday</td></tr></table>
          <script>track();</script>
          <!-- a comment -->
          <p>Thanks &amp; enjoy &#8212; the team&#x2019;s best</p>
        </body></html>
        """
        let mail = try GmailMessageParser.parse(message(html: html))

        // Block elements become paragraphs; scripts, styles, comments and
        // the document head leave nothing behind.
        #expect(mail.text == """
            Shipped!

            Your order of The Twelve Kingdoms is on its way.

            Arriving Thursday

            Thanks & enjoy — the team’s best
            """)
    }

    @Test func aTokenPlainPartLosesToTheRealHTML() throws {
        let html = "<p>" + String(repeating: "Your order of The Twelve Kingdoms arrives Thursday. ", count: 5) + "</p>"
        let mail = try GmailMessageParser.parse(message(plain: "View in browser", html: html))
        #expect(mail.text.contains("Twelve Kingdoms"))
        #expect(!mail.text.contains("View in browser"))
    }

    @Test func aRealPlainPartIsPreferred() throws {
        let plain = "Your order of The Twelve Kingdoms arrives Thursday."
        let mail = try GmailMessageParser.parse(message(plain: plain, html: "<p>\(plain)</p>"))
        #expect(mail.text == plain)
    }

    @Test func structuredDataIsCollectedFromTheHTML() throws {
        let html = """
        <html><head><script type="application/ld+json">{"@type":"Order","orderNumber":"113-1"}</script></head>
        <body><p>Thanks for your order.</p></body></html>
        """
        let mail = try GmailMessageParser.parse(message(html: html))
        #expect(mail.structuredData == [#"{"@type":"Order","orderNumber":"113-1"}"#])
        // The markup itself must not leak into the readable text.
        #expect(!mail.text.contains("orderNumber"))
    }

    @Test func aMessageWithNoBodyFallsBackToItsSnippet() throws {
        let json: [String: Any] = ["id": "m", "threadId": "t", "snippet": "Only a snippet", "payload": ["headers": []]]
        let mail = try GmailMessageParser.parse(JSONSerialization.data(withJSONObject: json))
        #expect(mail.text == "Only a snippet")
        #expect(mail.subject == "")
    }

    @Test func base64URLHandlesPaddingAndTheURLAlphabet() {
        // "??>>" encodes to "Pz8+Pg==" in standard base64.
        #expect(GmailMessageParser.decodeBase64URL("Pz8-Pg").map { String(decoding: $0, as: UTF8.self) } == "??>>")
        #expect(GmailMessageParser.decodeBase64URL("YQ").map { String(decoding: $0, as: UTF8.self) } == "a")
        #expect(GmailMessageParser.decodeBase64URL("YWI").map { String(decoding: $0, as: UTF8.self) } == "ab")
        #expect(GmailMessageParser.decodeBase64URL("YWJj").map { String(decoding: $0, as: UTF8.self) } == "abc")
    }

    @Test func encodedWordsInHeadersAreDecoded() {
        // Base64 and quoted-printable forms of non-ASCII header text.
        #expect(GmailMessageParser.decodeEncodedWords("=?UTF-8?B?Q2Fmw6kgUsOpc3Vtw6k=?=") == "Café Résumé")
        #expect(GmailMessageParser.decodeEncodedWords("=?utf-8?Q?Caf=C3=A9_del_Mar?= <hello@example.com>") == "Café del Mar <hello@example.com>")
        #expect(GmailMessageParser.decodeEncodedWords("=?ISO-8859-1?Q?Caf=E9?=") == "Café")
        // Adjacent encoded words join without the space between them.
        #expect(GmailMessageParser.decodeEncodedWords("=?UTF-8?B?Q2Fmw6k=?= =?UTF-8?B?IFLDqXN1bcOp?=") == "Café Résumé")
        // Plain headers pass through untouched.
        #expect(GmailMessageParser.decodeEncodedWords("Your order has shipped") == "Your order has shipped")
        #expect(GmailMessageParser.decodeEncodedWords("Re: 2 + 2 =? 4") == "Re: 2 + 2 =? 4")
    }

    @Test func entitiesAreDecoded() {
        #expect(GmailMessageParser.decodeEntities("Tom &amp; Jerry &lt;3 &quot;cheese&quot;") == "Tom & Jerry <3 \"cheese\"")
        #expect(GmailMessageParser.decodeEntities("it&#39;s &#8364;5 &#x1F600;") == "it's €5 😀")
        #expect(GmailMessageParser.decodeEntities("no entities here") == "no entities here")
        // Text that was escaped twice is unescaped once, not twice.
        #expect(GmailMessageParser.decodeEntities("&amp;lt;b&amp;gt; and &amp;#39;") == "&lt;b&gt; and &#39;")
        // An unknown or malformed entity is left as written.
        #expect(GmailMessageParser.decodeEntities("&bogus; &#xZZ;") == "&bogus; &#xZZ;")
    }

    @Test func whitespaceIsCollapsed() {
        let messy = "  First   line \r\n\r\n\r\n\n  second\tline  \n\n"
        #expect(GmailMessageParser.collapseWhitespace(messy) == "First line\n\nsecond line")
    }

    @Test func senderNameIsDerivedForCounterparts() {
        func name(_ sender: String?) -> String? {
            EvidenceInput(
                id: UUID(), title: "", body: "", sourceType: .gmail, sourceAccountID: nil,
                sender: sender, threadKey: nil, structuredData: [], date: .now
            ).senderName
        }
        #expect(name("Amazon.com <ship-confirm@example.com>") == "Amazon.com")
        #expect(name("\"Lakeside Dental\" <office@example.com>") == "Lakeside Dental")
        #expect(name("billing@cascadepower.example") == "Cascadepower")
        #expect(name("<no-reply@northwind.example>") == "Northwind")
        #expect(name(nil) == nil)
    }
}
