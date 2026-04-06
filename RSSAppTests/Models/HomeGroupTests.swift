import Testing
@testable import RSSApp

@Suite("HomeGroup Tests")
struct HomeGroupTests {

    @Test("allCases contains four groups in order")
    func allCases() {
        let cases = HomeGroup.allCases
        #expect(cases.count == 4)
        #expect(cases[0] == .allArticles)
        #expect(cases[1] == .unreadArticles)
        #expect(cases[2] == .savedArticles)
        #expect(cases[3] == .allFeeds)
    }

    @Test("each group has a unique id")
    func uniqueIDs() {
        let ids = Set(HomeGroup.allCases.map(\.id))
        #expect(ids.count == 4)
    }

    @Test("titles are non-empty")
    func titles() {
        for group in HomeGroup.allCases {
            #expect(!group.title.isEmpty)
        }
    }

    @Test("systemImage names are non-empty")
    func systemImages() {
        for group in HomeGroup.allCases {
            #expect(!group.systemImage.isEmpty)
        }
    }

    @Test("allArticles properties")
    func allArticlesProperties() {
        let group = HomeGroup.allArticles
        #expect(group.title == "All Articles")
        #expect(group.systemImage == "doc.text")
        #expect(group.id == "all-articles")
    }

    @Test("unreadArticles properties")
    func unreadArticlesProperties() {
        let group = HomeGroup.unreadArticles
        #expect(group.title == "Unread Articles")
        #expect(group.systemImage == "envelope.badge")
        #expect(group.id == "unread-articles")
    }

    @Test("savedArticles properties")
    func savedArticlesProperties() {
        let group = HomeGroup.savedArticles
        #expect(group.title == "Saved Articles")
        #expect(group.systemImage == "bookmark.fill")
        #expect(group.id == "saved-articles")
    }

    @Test("allFeeds properties")
    func allFeedsProperties() {
        let group = HomeGroup.allFeeds
        #expect(group.title == "All Feeds")
        #expect(group.systemImage == "list.bullet")
        #expect(group.id == "all-feeds")
    }

    @Test("conforms to Hashable")
    func hashable() {
        var set = Set<HomeGroup>()
        set.insert(.allArticles)
        set.insert(.unreadArticles)
        set.insert(.savedArticles)
        set.insert(.allFeeds)
        #expect(set.count == 4)
    }
}
