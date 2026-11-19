import XCTest
@testable import NEWSFLOWCore

final class ArticleTextExtractorTests: XCTestCase {
    func testExtractsArticleTextAndRemovesPageChrome() {
        let paragraph = String(repeating: "This is a useful paragraph about the story. ", count: 8)
        let html = """
        <html><body><nav>Navigation and links</nav><article>
        <h1>Headline</h1><p>First &amp; foremost.</p><p>\(paragraph)</p>
        <script>trackingCode()</script></article><footer>Footer links</footer></body></html>
        """
        let text = ArticleTextExtractor.extract(from: Data(html.utf8))
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("First & foremost.") == true)
        XCTAssertFalse(text?.contains("Navigation") == true)
        XCTAssertFalse(text?.contains("trackingCode") == true)
    }

    func testRejectsShortOrUnstructuredPages() {
        XCTAssertNil(ArticleTextExtractor.extract(from: Data("<html><body>Sign in</body></html>".utf8)))
    }

    func testDecodesNumericEntities() {
        let paragraph = String(repeating: "A long article text ", count: 20)
        let html = "<article><p>&#8212; \(paragraph)</p></article>"
        XCTAssertTrue(ArticleTextExtractor.extract(from: Data(html.utf8))?.hasPrefix("—") == true)
    }
}
