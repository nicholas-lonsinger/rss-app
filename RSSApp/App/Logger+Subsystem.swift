import os

extension Logger {
    static let appSubsystem = "com.nicholas-lonsinger.rss-app"

    init(category: String) {
        self.init(subsystem: Self.appSubsystem, category: category)
    }
}
