import Foundation
import SwiftData

@Model
final class PersistentArticleContent {

    var title: String
    var byline: String?
    var htmlContent: String
    var textContent: String
    var extractedDate: Date

    // MARK: - Relationships

    var article: PersistentArticle?

    init(
        title: String,
        byline: String? = nil,
        htmlContent: String,
        textContent: String,
        extractedDate: Date = Date()
    ) {
        self.title = title
        self.byline = byline
        self.htmlContent = htmlContent
        self.textContent = textContent
        self.extractedDate = extractedDate
    }
}
