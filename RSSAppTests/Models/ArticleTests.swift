import Testing
import Foundation
@testable import RSSApp

@Suite("Article Tests")
struct ArticleTests {

    @Test("Article stores all properties correctly")
    func articleCreation() {
        let article = TestFixtures.makeArticle()

        #expect(article.id == "test-id")
        #expect(article.title == "Test Article")
        #expect(article.link?.absoluteString == "https://example.com/article")
        #expect(article.articleDescription == "<p>Test description</p>")
        #expect(article.snippet == "Test description")
        #expect(article.publishedDate != nil)
        #expect(article.thumbnailURL?.absoluteString == "https://example.com/thumb.jpg")
    }

    @Test("Article with nil optionals")
    func articleWithNilOptionals() {
        let article = TestFixtures.makeArticle(
            link: nil,
            publishedDate: nil,
            thumbnailURL: nil
        )

        #expect(article.link == nil)
        #expect(article.publishedDate == nil)
        #expect(article.thumbnailURL == nil)
    }

    @Test("Article conforms to Identifiable")
    func identifiable() {
        let article1 = TestFixtures.makeArticle(id: "a")
        let article2 = TestFixtures.makeArticle(id: "b")

        #expect(article1.id == "a")
        #expect(article2.id == "b")
        #expect(article1.id != article2.id)
    }

    @Test("Article conforms to Hashable")
    func hashable() {
        let article1 = TestFixtures.makeArticle(id: "same-id", title: "Same Title")
        let article2 = TestFixtures.makeArticle(id: "same-id", title: "Same Title")

        #expect(article1.hashValue == article2.hashValue)

        var set: Set<Article> = [article1]
        set.insert(article2)
        #expect(set.count == 1)
    }

    @Test("Articles with different fields are not equal")
    func differentArticlesNotEqual() {
        let article1 = TestFixtures.makeArticle(id: "a", title: "Title A")
        let article2 = TestFixtures.makeArticle(id: "b", title: "Title B")

        #expect(article1 != article2)
    }
}
