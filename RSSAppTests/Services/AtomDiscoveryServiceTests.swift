import Testing
import Foundation
@testable import RSSApp

@Suite("AtomDiscoveryService")
struct AtomDiscoveryServiceTests {

    // MARK: - Helpers

    /// Error injected by the test fetcher when a URL has no canned response.
    private struct FetcherError: Error {}

    /// Tracks fetch calls and returns canned data for each URL. If a URL has no
    /// entry it throws, so tests don't accidentally rely on live defaults.
    private final class ScriptedFetcher: @unchecked Sendable {
        var responses: [URL: Result<(Data, HTTPURLResponse), any Error>] = [:]
        private(set) var fetchedURLs: [URL] = []

        func register(url: URL, html: String, statusCode: Int = 200) {
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            responses[url] = .success((Data(html.utf8), response))
        }

        func registerFailure(url: URL, error: any Error = FetcherError()) {
            responses[url] = .failure(error)
        }

        /// Returns an @Sendable fetcher that reads from this scripted table.
        /// `self` is captured unchecked — fine in single-threaded test contexts.
        func fetcher() -> @Sendable (URL) async throws -> (Data, URLResponse) {
            let box = self
            return { url in
                box.fetchedURLs.append(url)
                guard let result = box.responses[url] else {
                    throw FetcherError()
                }
                switch result {
                case .success(let (data, response)):
                    return (data, response as URLResponse)
                case .failure(let error):
                    throw error
                }
            }
        }
    }

    private static let atomLinkHTML = """
        <html><head>
          <link rel="alternate" type="application/atom+xml" href="https://example.com/blog/atom.xml" />
        </head></html>
        """

    private static let rootAtomLinkHTML = """
        <html><head>
          <link rel="alternate" type="application/atom+xml" href="https://example.com/atom.xml" />
        </head></html>
        """

    private static let noLinkHTML = """
        <html><head><title>Plain page</title></head><body><p>Nothing here</p></body></html>
        """

    // MARK: - Discovery behavior

    @Test("Prefers subfolder match over root")
    func prefersSubfolderMatch() async {
        let scripted = ScriptedFetcher()
        scripted.register(
            url: URL(string: "https://example.com/blog/")!,
            html: Self.atomLinkHTML
        )
        scripted.register(
            url: URL(string: "https://example.com/")!,
            html: Self.rootAtomLinkHTML
        )

        let service = AtomDiscoveryService(fetchData: scripted.fetcher())
        let result = await service.discoverAtomAlternate(
            forFeedAt: URL(string: "https://example.com/blog/feed")!
        )

        #expect(result?.absoluteString == "https://example.com/blog/atom.xml")
        // Subfolder succeeded, so root should not have been fetched.
        #expect(scripted.fetchedURLs == [URL(string: "https://example.com/blog/")!])
    }

    @Test("Falls back to root when subfolder has no Atom link")
    func fallsBackToRoot() async {
        let scripted = ScriptedFetcher()
        scripted.register(
            url: URL(string: "https://example.com/blog/")!,
            html: Self.noLinkHTML
        )
        scripted.register(
            url: URL(string: "https://example.com/")!,
            html: Self.rootAtomLinkHTML
        )

        let service = AtomDiscoveryService(fetchData: scripted.fetcher())
        let result = await service.discoverAtomAlternate(
            forFeedAt: URL(string: "https://example.com/blog/feed")!
        )

        #expect(result?.absoluteString == "https://example.com/atom.xml")
        #expect(scripted.fetchedURLs == [
            URL(string: "https://example.com/blog/")!,
            URL(string: "https://example.com/")!,
        ])
    }

    @Test("Returns nil when neither subfolder nor root has an Atom link")
    func returnsNilWhenNoMatches() async {
        let scripted = ScriptedFetcher()
        scripted.register(url: URL(string: "https://example.com/blog/")!, html: Self.noLinkHTML)
        scripted.register(url: URL(string: "https://example.com/")!, html: Self.noLinkHTML)

        let service = AtomDiscoveryService(fetchData: scripted.fetcher())
        let result = await service.discoverAtomAlternate(
            forFeedAt: URL(string: "https://example.com/blog/feed")!
        )

        #expect(result == nil)
    }

    @Test("Returns nil when fetch throws")
    func returnsNilOnFetchError() async {
        let scripted = ScriptedFetcher()
        scripted.registerFailure(url: URL(string: "https://example.com/blog/")!)
        scripted.registerFailure(url: URL(string: "https://example.com/")!)

        let service = AtomDiscoveryService(fetchData: scripted.fetcher())
        let result = await service.discoverAtomAlternate(
            forFeedAt: URL(string: "https://example.com/blog/feed")!
        )

        #expect(result == nil)
    }

    @Test("Returns nil when HTTP status is 404")
    func returnsNilOn404() async {
        let scripted = ScriptedFetcher()
        scripted.register(
            url: URL(string: "https://example.com/blog/")!,
            html: "",
            statusCode: 404
        )
        scripted.register(
            url: URL(string: "https://example.com/")!,
            html: "",
            statusCode: 404
        )

        let service = AtomDiscoveryService(fetchData: scripted.fetcher())
        let result = await service.discoverAtomAlternate(
            forFeedAt: URL(string: "https://example.com/blog/feed")!
        )

        #expect(result == nil)
    }

    @Test("Ignores discovered URL that equals the feed URL")
    func ignoresSelfReference() async {
        // Page advertises an Atom link whose href happens to match the URL the
        // user already entered — there's nothing to offer them.
        let feedURL = URL(string: "https://example.com/blog/feed")!
        let html = """
            <link rel="alternate" type="application/atom+xml" href="https://example.com/blog/feed" />
            """

        let scripted = ScriptedFetcher()
        scripted.register(url: URL(string: "https://example.com/blog/")!, html: html)
        scripted.register(url: URL(string: "https://example.com/")!, html: html)

        let service = AtomDiscoveryService(fetchData: scripted.fetcher())
        let result = await service.discoverAtomAlternate(forFeedAt: feedURL)

        #expect(result == nil)
    }

    @Test("Does not re-fetch when subfolder URL equals root URL")
    func doesNotDuplicateFetchWhenSubfolderIsRoot() async {
        // A feed at the site root has subfolder == root, so discovery should
        // make exactly one HTTP call, not two.
        let scripted = ScriptedFetcher()
        scripted.register(url: URL(string: "https://example.com/")!, html: Self.noLinkHTML)

        let service = AtomDiscoveryService(fetchData: scripted.fetcher())
        let result = await service.discoverAtomAlternate(
            forFeedAt: URL(string: "https://example.com/feed")!
        )

        #expect(result == nil)
        #expect(scripted.fetchedURLs.count == 1)
    }

    // MARK: - URL derivations

    @Test("subfolderURL strips the feed filename")
    func subfolderStripsFilename() {
        let url = URL(string: "https://example.com/blog/feed.xml")!
        let result = AtomDiscoveryService.subfolderURL(for: url)
        #expect(result?.absoluteString == "https://example.com/blog/")
    }

    @Test("subfolderURL of a root feed returns the site root")
    func subfolderOfRootFeed() {
        let url = URL(string: "https://example.com/feed")!
        let result = AtomDiscoveryService.subfolderURL(for: url)
        #expect(result?.absoluteString == "https://example.com/")
    }

    @Test("subfolderURL preserves directory paths as-is")
    func subfolderPreservesDirectoryPath() {
        // Directory-style feed URLs (trailing slash) are kept as the
        // subfolder target — they already point at an HTML listing, not
        // at a file. Walking up would skip past the page that's most
        // likely to advertise the feed's Atom alternate.
        let url = URL(string: "https://example.com/a/b/c/")!
        let result = AtomDiscoveryService.subfolderURL(for: url)
        #expect(result?.absoluteString == "https://example.com/a/b/c/")
    }

    @Test("subfolderURL of a bare directory URL is the URL itself")
    func subfolderOfBareDirectoryFeed() {
        // Regression guard for the gemini-code-assist PR review: previously
        // `https://example.com/blog/` was incorrectly walked up to
        // `https://example.com/`, skipping past the blog listing HTML that
        // is the most likely place to find an Atom alternate link.
        let url = URL(string: "https://example.com/blog/")!
        let result = AtomDiscoveryService.subfolderURL(for: url)
        #expect(result?.absoluteString == "https://example.com/blog/")
    }

    @Test("subfolderURL strips query parameters")
    func subfolderStripsQuery() {
        let url = URL(string: "https://example.com/blog/feed?format=rss")!
        let result = AtomDiscoveryService.subfolderURL(for: url)
        #expect(result?.absoluteString == "https://example.com/blog/")
    }

    @Test("rootURL returns scheme/host with path /")
    func rootURLAtSiteRoot() {
        let url = URL(string: "https://example.com/blog/feed?x=1#frag")!
        let result = AtomDiscoveryService.rootURL(for: url)
        #expect(result?.absoluteString == "https://example.com/")
    }
}
