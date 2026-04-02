import Foundation

// MARK: - PersistentFeed ↔ SubscribedFeed

extension PersistentFeed {

    convenience init(from subscribedFeed: SubscribedFeed) {
        self.init(
            id: subscribedFeed.id,
            title: subscribedFeed.title,
            feedURL: subscribedFeed.url,
            feedDescription: subscribedFeed.feedDescription,
            addedDate: subscribedFeed.addedDate,
            lastFetchError: subscribedFeed.lastFetchError,
            lastFetchErrorDate: subscribedFeed.lastFetchErrorDate
        )
    }

    func toSubscribedFeed() -> SubscribedFeed {
        SubscribedFeed(
            id: id,
            title: title,
            url: feedURL,
            feedDescription: feedDescription,
            addedDate: addedDate,
            lastFetchError: lastFetchError,
            lastFetchErrorDate: lastFetchErrorDate
        )
    }
}

// MARK: - PersistentArticle ↔ Article

extension PersistentArticle {

    convenience init(from article: Article) {
        self.init(
            articleID: article.id,
            title: article.title,
            link: article.link,
            articleDescription: article.articleDescription,
            snippet: article.snippet,
            publishedDate: article.publishedDate,
            thumbnailURL: article.thumbnailURL,
            author: article.author,
            categories: article.categories
        )
    }

    func toArticle() -> Article {
        Article(
            id: articleID,
            title: title,
            link: link,
            articleDescription: articleDescription,
            snippet: snippet,
            publishedDate: publishedDate,
            thumbnailURL: thumbnailURL,
            author: author,
            categories: categories
        )
    }
}

// MARK: - PersistentArticleContent ↔ ArticleContent

extension PersistentArticleContent {

    convenience init(from content: ArticleContent) {
        self.init(
            title: content.title,
            byline: content.byline,
            htmlContent: content.htmlContent,
            textContent: content.textContent
        )
    }

    func toArticleContent() -> ArticleContent {
        ArticleContent(
            title: title,
            byline: byline,
            htmlContent: htmlContent,
            textContent: textContent
        )
    }
}
