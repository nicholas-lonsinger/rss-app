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
        // Compute the clamped sort key. Three cases:
        //   1. `publishedDate` is in the past → use it directly (the common case).
        //   2. `publishedDate` is in the future (e.g., Cloudflare scheduled posts) →
        //      clamp to ingestion time so it sorts as fresh, not by an inflated future
        //      timestamp that would pin it to the top of newest-first lists.
        //   3. `publishedDate` is `nil` (parser rejected an implausible date, or the
        //      feed simply omitted it) → fall back to ingestion time so the article
        //      still has a stable, non-optional sort key.
        // The original `publishedDate` is passed through unchanged for a planned
        // content-update detection feature that compares pubDate values across refreshes.
        let now = Date()
        let sortDate = min(article.publishedDate ?? now, now)
        self.init(
            articleID: article.id,
            title: article.title,
            link: article.link,
            articleDescription: article.articleDescription,
            snippet: article.snippet,
            publishedDate: article.publishedDate,
            thumbnailURL: article.thumbnailURL,
            author: article.author,
            categories: article.categories,
            sortDate: sortDate
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
