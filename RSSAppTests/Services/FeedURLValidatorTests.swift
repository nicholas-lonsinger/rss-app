import Testing
import Foundation
@testable import RSSApp

@Suite("FeedURLValidator Tests")
struct FeedURLValidatorTests {

    @Test("Valid HTTPS URL returns success")
    func validHTTPS() {
        let result = FeedURLValidator.validate("https://example.com/feed")
        #expect(result == .success(URL(string: "https://example.com/feed")!))
    }

    @Test("Valid HTTP URL returns success")
    func validHTTP() {
        let result = FeedURLValidator.validate("http://example.com/feed")
        #expect(result == .success(URL(string: "http://example.com/feed")!))
    }

    @Test("Input without scheme gets https prepended")
    func prependsScheme() {
        let result = FeedURLValidator.validate("example.com/feed")
        #expect(result == .success(URL(string: "https://example.com/feed")!))
    }

    @Test("Empty string returns failure")
    func emptyString() {
        let result = FeedURLValidator.validate("")
        #expect(result == .failure(.invalidURL))
    }

    @Test("Whitespace-only string returns failure")
    func whitespaceOnly() {
        let result = FeedURLValidator.validate("   \n  ")
        #expect(result == .failure(.invalidURL))
    }

    @Test("FTP scheme returns failure")
    func ftpScheme() {
        let result = FeedURLValidator.validate("ftp://example.com/feed")
        #expect(result == .failure(.invalidURL))
    }

    @Test("feed:// scheme returns failure")
    func feedScheme() {
        let result = FeedURLValidator.validate("feed://example.com/feed")
        #expect(result == .failure(.invalidURL))
    }

    @Test("URL with query parameters succeeds")
    func queryParameters() {
        let result = FeedURLValidator.validate("https://example.com/feed?format=rss")
        #expect(result == .success(URL(string: "https://example.com/feed?format=rss")!))
    }

    @Test("Leading and trailing whitespace is trimmed")
    func trimmedWhitespace() {
        let result = FeedURLValidator.validate("  https://example.com/feed  ")
        #expect(result == .success(URL(string: "https://example.com/feed")!))
    }

    @Test("Scheme-only URL without host returns failure")
    func schemeOnlyNoHost() {
        let result = FeedURLValidator.validate("https://")
        #expect(result == .failure(.invalidURL))
    }

    @Test("mailto scheme without :// gets https prepended and passes")
    func mailtoScheme() {
        // mailto: has no "://" so the validator prepends https://
        let result = FeedURLValidator.validate("mailto:user@example.com")
        if case .success = result { } else {
            Issue.record("Expected success since mailto: lacks :// and gets https:// prepended")
        }
    }

    @Test("URL with port succeeds")
    func urlWithPort() {
        let result = FeedURLValidator.validate("https://example.com:8080/feed")
        #expect(result == .success(URL(string: "https://example.com:8080/feed")!))
    }

    @Test("URL with fragment succeeds")
    func urlWithFragment() {
        let result = FeedURLValidator.validate("https://example.com/feed#section")
        #expect(result == .success(URL(string: "https://example.com/feed#section")!))
    }

    @Test("Double scheme https://https:// parses as valid URL")
    func doubleScheme() {
        // URL(string:) parses "https://https://example.com" with host "https" — not rejected
        let result = FeedURLValidator.validate("https://https://example.com")
        if case .success = result { } else {
            Issue.record("Expected success since URL parses with host 'https'")
        }
    }
}
