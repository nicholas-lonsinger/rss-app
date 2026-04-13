import Testing
import Foundation
import UIKit
@testable import RSSApp

@Suite("FeedIconService Tests")
struct FeedIconServiceTests {

    /// Per-test temporary cache directory. Swift Testing re-instantiates the suite for each
    /// `@Test`, so each test gets a fresh UUID-named subdirectory under the system temporary
    /// directory — on-disk fixtures never touch the real user caches directory
    /// (`<Caches>/feed-icons`), and cross-test isolation is guaranteed. Tests that prime the
    /// cache via `writeCacheFile` add their own `defer`-based cleanup for deterministic
    /// teardown within a single test; any files that leak on a hard crash are bounded by
    /// iOS's periodic purge of the system temp directory.
    let cacheDirectory: URL
    let service: FeedIconService

    init() {
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FeedIconServiceTests-\(UUID().uuidString)", isDirectory: true)
        service = FeedIconService(cacheDirectoryOverride: cacheDirectory)
    }

    // MARK: - resolveIconCandidates

    @Test("Returns empty when no URLs provided")
    func resolveWithNoURLs() async {
        let result = await service.resolveIconCandidates(feedSiteURL: nil, feedImageURL: nil)

        #expect(result.isEmpty)
    }

    @Test("Ignores feedImageURL with non-HTTP scheme")
    func resolveIgnoresDataScheme() async {
        let dataURL = URL(string: "data:image/png;base64,abc")!
        let result = await service.resolveIconCandidates(feedSiteURL: nil, feedImageURL: dataURL)

        #expect(result.isEmpty)
    }

    @Test("Includes feedImageURL as first candidate when HTTP")
    func resolveIncludesFeedImageURL() async {
        let imageURL = URL(string: "https://example.com/logo.png")!
        let result = await service.resolveIconCandidates(feedSiteURL: nil, feedImageURL: imageURL)

        #expect(result.first == imageURL)
    }

    @Test("Includes favicon.ico fallback for site URL when HTML fetch fails")
    func resolveFallbackFaviconWhenHTMLFails() async {
        let siteURL = URL(string: "https://unreachable-test-host.invalid")!
        let result = await service.resolveIconCandidates(feedSiteURL: siteURL, feedImageURL: nil)

        // HTML fetch fails for unreachable host, but /favicon.ico fallback should still appear
        #expect(result.contains(URL(string: "https://unreachable-test-host.invalid/favicon.ico")!))
    }

    @Test("Feed image URL appears before favicon.ico fallback")
    func resolveFeedImageBeforeFavicon() async throws {
        let imageURL = URL(string: "https://example.com/logo.png")!
        let siteURL = URL(string: "https://unreachable-test-host.invalid")!
        let result = await service.resolveIconCandidates(feedSiteURL: siteURL, feedImageURL: imageURL)

        #expect(result.first == imageURL)
        // favicon.ico should come after the feed image URL
        let faviconURL = URL(string: "https://unreachable-test-host.invalid/favicon.ico")!
        let imageIndex = try #require(result.firstIndex(of: imageURL))
        let faviconIndex = try #require(result.firstIndex(of: faviconURL))
        #expect(imageIndex < faviconIndex)
    }

    // MARK: - assembleCandidates (priority ordering)

    @Test("og:image appears before link icons in candidates (no platform redirect)")
    func assembleCandidatesOgImageBeforeLinkIcons() {
        let siteURL = URL(string: "https://myblog.example.com")!
        let ogImage = URL(string: "https://cdn.example.com/blog-logo.png")!
        let linkIcon = URL(string: "https://myblog.example.com/favicon.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [linkIcon],
            appleTouchIconURLs: [],
            ogImageURL: ogImage,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: siteURL,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        // og:image (priority 2) should come before link icon (priority 3)
        guard let ogIndex = candidates.firstIndex(of: ogImage),
              let linkIndex = candidates.firstIndex(of: linkIcon) else {
            Issue.record("Expected both og:image and link icon in candidates")
            return
        }
        #expect(ogIndex < linkIndex)
    }

    @Test("Platform redirect skips HTML icons (og:image, link icons, apple-touch-icons)")
    func assembleCandidatesPlatformRedirectSkipsHTMLIcons() {
        let siteURL = URL(string: "https://myblog.example.com")!
        let ogImage = URL(string: "https://medium.com/og-generic.png")!
        let appleTouchIcon = URL(string: "https://medium.com/apple-touch.png")!
        let linkIcon = URL(string: "https://medium.com/favicon.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [appleTouchIcon, linkIcon],
            appleTouchIconURLs: [appleTouchIcon],
            ogImageURL: ogImage,
            redirectedHost: "medium.com"
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: siteURL,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        #expect(!candidates.contains(ogImage), "Platform og:image should be excluded")
        #expect(!candidates.contains(appleTouchIcon), "Platform apple-touch-icon should be excluded")
        #expect(!candidates.contains(linkIcon), "Platform link icon should be excluded")
        #expect(candidates.contains(URL(string: "https://myblog.example.com/favicon.ico")!))
        #expect(candidates.contains(URL(string: "https://medium.com/favicon.ico")!))
    }

    @Test("Feed image URL appears before og:image in candidates")
    func assembleCandidatesFeedImageBeforeOgImage() {
        let feedImage = URL(string: "https://example.com/feed-logo.png")!
        let ogImage = URL(string: "https://cdn.example.com/og-logo.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [],
            appleTouchIconURLs: [],
            ogImageURL: ogImage,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: URL(string: "https://example.com")!,
            feedImageURL: feedImage,
            htmlResult: htmlResult
        )

        #expect(candidates.first == feedImage)
        guard let feedIndex = candidates.firstIndex(of: feedImage),
              let ogIndex = candidates.firstIndex(of: ogImage) else {
            Issue.record("Expected both feed image and og:image in candidates")
            return
        }
        #expect(feedIndex < ogIndex)
    }

    @Test("Redirected host favicon appears after original host favicon")
    func assembleCandidatesRedirectedHostFaviconLast() {
        let siteURL = URL(string: "https://myblog.example.com")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [],
            appleTouchIconURLs: [],
            ogImageURL: nil,
            redirectedHost: "medium.com"
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: siteURL,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        let originalFavicon = URL(string: "https://myblog.example.com/favicon.ico")!
        let redirectedFavicon = URL(string: "https://medium.com/favicon.ico")!
        guard let originalIndex = candidates.firstIndex(of: originalFavicon),
              let redirectedIndex = candidates.firstIndex(of: redirectedFavicon) else {
            Issue.record("Expected both original and redirected favicons in candidates")
            return
        }
        #expect(originalIndex < redirectedIndex)
    }

    @Test("No redirected host favicon when hosts match")
    func assembleCandidatesNoRedirectNoExtraFavicon() {
        let siteURL = URL(string: "https://example.com")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [],
            appleTouchIconURLs: [],
            ogImageURL: nil,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: siteURL,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        // Only the original host's favicon should appear
        #expect(candidates.count == 1)
        #expect(candidates[0] == URL(string: "https://example.com/favicon.ico")!)
    }

    @Test("Full priority order with all sources present (no platform redirect)")
    func assembleCandidatesFullPriorityOrder() {
        let feedImage = URL(string: "https://myblog.example.com/rss-logo.png")!
        let siteURL = URL(string: "https://myblog.example.com")!
        let ogImage = URL(string: "https://myblog.example.com/og-cover.jpg")!
        let appleTouchIcon = URL(string: "https://myblog.example.com/apple-touch.png")!
        let linkIcon = URL(string: "https://myblog.example.com/favicon.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [appleTouchIcon, linkIcon],
            appleTouchIconURLs: [appleTouchIcon],
            ogImageURL: ogImage,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: siteURL,
            feedImageURL: feedImage,
            htmlResult: htmlResult
        )

        let originalFavicon = URL(string: "https://myblog.example.com/favicon.ico")!

        // Verify all 5 candidates present in correct priority order
        #expect(candidates.count == 5)
        #expect(candidates[0] == feedImage)           // Priority 1
        #expect(candidates[1] == ogImage)             // Priority 2
        #expect(candidates[2] == appleTouchIcon)      // Priority 3a
        #expect(candidates[3] == linkIcon)            // Priority 3b
        #expect(candidates[4] == originalFavicon)     // Priority 4
    }

    @Test("Full priority order with platform redirect: only feed image and favicons")
    func assembleCandidatesFullPriorityOrderWithPlatformRedirect() {
        let feedImage = URL(string: "https://myblog.example.com/rss-logo.png")!
        let siteURL = URL(string: "https://myblog.example.com")!
        let ogImage = URL(string: "https://cdn.medium.com/blog-cover.jpg")!
        let appleTouchIcon = URL(string: "https://medium.com/apple-touch.png")!
        let linkIcon = URL(string: "https://medium.com/favicon.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [appleTouchIcon, linkIcon],
            appleTouchIconURLs: [appleTouchIcon],
            ogImageURL: ogImage,
            redirectedHost: "medium.com"
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: siteURL,
            feedImageURL: feedImage,
            htmlResult: htmlResult
        )

        let originalFavicon = URL(string: "https://myblog.example.com/favicon.ico")!
        let redirectedFavicon = URL(string: "https://medium.com/favicon.ico")!

        // Platform redirect: HTML icons (og:image, apple-touch-icon, link icon) are skipped.
        // Only feed XML image and favicon fallbacks remain.
        #expect(candidates.count == 3)
        #expect(candidates[0] == feedImage)           // Priority 1
        #expect(candidates[1] == originalFavicon)     // Priority 4
        #expect(candidates[2] == redirectedFavicon)   // Priority 5
    }

    @Test("assembleCandidates returns empty when no inputs provided")
    func assembleCandidatesEmpty() {
        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: nil,
            feedImageURL: nil,
            htmlResult: nil
        )

        #expect(candidates.isEmpty)
    }

    @Test("www-only redirect is not treated as a platform redirect")
    func assembleCandidatesWWWRedirectDoesNotSkipHTMLIcons() {
        // example.com → www.example.com is a same-domain www-redirect, not a
        // cross-platform redirect; HTML icons should be included as normal.
        let siteURL = URL(string: "https://example.com")!
        let ogImage = URL(string: "https://www.example.com/og.png")!
        let appleTouchIcon = URL(string: "https://www.example.com/apple-touch.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [appleTouchIcon],
            appleTouchIconURLs: [appleTouchIcon],
            ogImageURL: ogImage,
            redirectedHost: nil  // strippingWWWPrefix normalization keeps redirectedHost nil
        )

        let candidates = FeedIconService.assembleCandidates(
            feedSiteURL: siteURL,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        #expect(candidates.contains(ogImage), "og:image should be included for www-redirect")
        #expect(candidates.contains(appleTouchIcon), "apple-touch-icon should be included for www-redirect")
    }

    // MARK: - assembleTypedCandidates (source type assignment)

    @Test("Feed XML candidate is assigned .feedXML type")
    func assembleTypedCandidatesFeedXMLType() {
        let feedImage = URL(string: "https://example.com/logo.png")!

        let candidates = FeedIconService.assembleTypedCandidates(
            feedSiteURL: nil,
            feedImageURL: feedImage,
            htmlResult: nil
        )

        #expect(candidates.count == 1)
        #expect(candidates[0].type == .feedXML)
        #expect(candidates[0].url == feedImage)
    }

    @Test("og:image candidate is assigned .ogImage type")
    func assembleTypedCandidatesOgImageType() {
        let ogImage = URL(string: "https://cdn.example.com/og.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [],
            appleTouchIconURLs: [],
            ogImageURL: ogImage,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleTypedCandidates(
            feedSiteURL: URL(string: "https://example.com")!,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        // favicon.ico fallback + og:image
        let ogCandidate = candidates.first { $0.url == ogImage }
        #expect(ogCandidate?.type == .ogImage)
    }

    @Test("Apple-touch-icon candidates are assigned .appleTouchIcon type")
    func assembleTypedCandidatesAppleTouchIconType() {
        let appleTouchIcon = URL(string: "https://example.com/apple-touch.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [appleTouchIcon],
            appleTouchIconURLs: [appleTouchIcon],
            ogImageURL: nil,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleTypedCandidates(
            feedSiteURL: URL(string: "https://example.com")!,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        let candidate = candidates.first { $0.url == appleTouchIcon }
        #expect(candidate?.type == .appleTouchIcon)
    }

    @Test("www-prefixed apple-touch-icon is treated as same-host and keeps .appleTouchIcon type")
    func assembleTypedCandidatesWWWAppleTouchIconKeptAsSameHost() {
        // Icons served from www.example.com are same-host for example.com after
        // www-prefix normalization and should retain the full .appleTouchIcon type bonus.
        let appleTouchIcon = URL(string: "https://www.example.com/apple-touch.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [appleTouchIcon],
            appleTouchIconURLs: [appleTouchIcon],
            ogImageURL: nil,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleTypedCandidates(
            feedSiteURL: URL(string: "https://example.com")!,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        let candidate = candidates.first { $0.url == appleTouchIcon }
        #expect(candidate?.type == .appleTouchIcon, "www-prefixed apple-touch-icon should not be downgraded")
    }

    @Test("Cross-domain apple-touch-icon is downgraded to .linkIcon type")
    func assembleTypedCandidatesCrossDomainAppleTouchIconDowngraded() {
        // Scenario: netflixtechblog.com served via CNAME by Medium — the apple-touch-icon
        // URL points to Medium's CDN (miro.medium.com), not the publication's own domain.
        // It should be treated as .linkIcon (lower type bonus) so the publication-specific
        // og:image can win over the platform's generic icon.
        let appleTouchIcon = URL(string: "https://miro.medium.com/max/192/1*abc.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [appleTouchIcon],
            appleTouchIconURLs: [appleTouchIcon],
            ogImageURL: nil,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleTypedCandidates(
            feedSiteURL: URL(string: "https://netflixtechblog.com")!,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        let candidate = candidates.first { $0.url == appleTouchIcon }
        #expect(candidate?.type == .linkIcon, "Cross-domain apple-touch-icon should be downgraded to .linkIcon")
    }

    @Test("Link icon candidates not in appleTouchIconURLs are assigned .linkIcon type")
    func assembleTypedCandidatesLinkIconType() {
        let linkIcon = URL(string: "https://example.com/favicon.png")!
        let htmlResult = FeedIconService.HTMLIconResult(
            linkIcons: [linkIcon],
            appleTouchIconURLs: [],
            ogImageURL: nil,
            redirectedHost: nil
        )

        let candidates = FeedIconService.assembleTypedCandidates(
            feedSiteURL: URL(string: "https://example.com")!,
            feedImageURL: nil,
            htmlResult: htmlResult
        )

        let candidate = candidates.first { $0.url == linkIcon }
        #expect(candidate?.type == .linkIcon)
    }

    @Test("favicon.ico fallback candidates are assigned .faviconICO type")
    func assembleTypedCandidatesFaviconICOType() {
        let siteURL = URL(string: "https://example.com")!

        let candidates = FeedIconService.assembleTypedCandidates(
            feedSiteURL: siteURL,
            feedImageURL: nil,
            htmlResult: nil
        )

        let faviconURL = URL(string: "https://example.com/favicon.ico")!
        let candidate = candidates.first { $0.url == faviconURL }
        #expect(candidate?.type == .faviconICO)
    }

    // MARK: - scoreIconCandidate

    @Test("Square image scores higher than wide banner for same source type")
    @MainActor
    func scorePreferssquareOverWideBanner() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let squareImage = UIGraphicsImageRenderer(size: CGSize(width: 96, height: 96), format: format)
            .image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 96, height: 96)) }
        let bannerImage = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 630), format: format)
            .image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 630)) }

        let squareScore = FeedIconService.scoreIconCandidate(image: squareImage, type: .ogImage)
        let bannerScore = FeedIconService.scoreIconCandidate(image: bannerImage, type: .ogImage)

        #expect(squareScore > bannerScore)
    }

    @Test("apple-touch-icon type bonus exceeds og:image for same dimensions")
    @MainActor
    func scoreAppleTouchIconOutranksSameShapeOgImage() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Both 180×180 (square, good dimensions) — source type is the differentiator
        let image = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format)
            .image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 180)) }

        let appleTouchScore = FeedIconService.scoreIconCandidate(image: image, type: .appleTouchIcon)
        let ogScore = FeedIconService.scoreIconCandidate(image: image, type: .ogImage)

        #expect(appleTouchScore > ogScore)
    }

    @Test("Score is in [0, 1] range for representative inputs")
    @MainActor
    func scoreIsBoundedInZeroToOne() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let cases: [(CGSize, IconCandidateType)] = [
            (CGSize(width: 16, height: 16), .faviconICO),
            (CGSize(width: 96, height: 96), .appleTouchIcon),
            (CGSize(width: 1200, height: 630), .ogImage),
            (CGSize(width: 180, height: 180), .feedXML),
            (CGSize(width: 32, height: 32), .linkIcon),
        ]

        for (size, type) in cases {
            let image = UIGraphicsImageRenderer(size: size, format: format)
                .image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(origin: .zero, size: size)) }
            let score = FeedIconService.scoreIconCandidate(image: image, type: type)
            #expect(score >= 0.0 && score <= 1.0, "Score \(score) out of range for size \(size) type \(type)")
        }
    }

    @Test("A 180x180 feed XML image passes the fast-path threshold")
    @MainActor
    func fastPathPassesFor180x180FeedXMLImage() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 180, height: 180), format: format)
            .image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 180, height: 180)) }

        #expect(FeedIconService.passesFastPathThreshold(image: image))
    }

    @Test("A 1200x630 feed XML image does not pass the fast-path threshold")
    @MainActor
    func fastPathFailsForWideBannerFeedXMLImage() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 630), format: format)
            .image { ctx in UIColor.red.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1200, height: 630)) }

        #expect(!FeedIconService.passesFastPathThreshold(image: image))
    }

    // MARK: - cachedIconFileURL

    @Test("Returns nil for uncached feed ID")
    func cachedIconFileURLReturnsNilForMissing() {
        let result = service.cachedIconFileURL(for: UUID())

        #expect(result == nil)
    }

    // MARK: - deleteCachedIcon

    @Test("Does not throw for non-existent feed ID")
    func deleteCachedIconNoThrow() {
        service.deleteCachedIcon(for: UUID())
    }

    // MARK: - loadValidatedIcon

    @Test("Returns nil when no cached icon exists")
    func loadValidatedIconReturnsNilWhenUncached() async {
        let result = await service.loadValidatedIcon(for: UUID())

        #expect(result == nil)
    }

    @Test("Returns decoded image when cached file is valid and visible")
    @MainActor
    func loadValidatedIconReturnsImageForValidCache() async throws {
        let cleanupDir = cacheDirectory
        defer { try? FileManager.default.removeItem(at: cleanupDir) }

        let feedID = UUID()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let pngData = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .pngData { ctx in
                UIColor.red.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        let fileURL = try writeCacheFile(feedID: feedID, data: pngData)

        let image = await service.loadValidatedIcon(for: feedID)

        #expect(image != nil)
        // Valid icons must remain on disk after a successful load
        #expect(FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test("Deletes cached file and returns nil when data is not a decodable image")
    func loadValidatedIconDeletesUndecodableFile() async throws {
        let cleanupDir = cacheDirectory
        defer { try? FileManager.default.removeItem(at: cleanupDir) }

        let feedID = UUID()
        let garbage = Data("not a real image".utf8)
        let fileURL = try writeCacheFile(feedID: feedID, data: garbage)

        let image = await service.loadValidatedIcon(for: feedID)

        #expect(image == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test("Deletes cached file and returns nil when image is fully transparent")
    @MainActor
    func loadValidatedIconDeletesTransparentImage() async throws {
        let cleanupDir = cacheDirectory
        defer { try? FileManager.default.removeItem(at: cleanupDir) }

        let feedID = UUID()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let pngData = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .pngData { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
        let fileURL = try writeCacheFile(feedID: feedID, data: pngData)

        let image = await service.loadValidatedIcon(for: feedID)

        #expect(image == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test("Deletes cached file and returns nil when image is below visibility threshold")
    @MainActor
    func loadValidatedIconDeletesBelowThresholdImage() async throws {
        let cleanupDir = cacheDirectory
        defer { try? FileManager.default.removeItem(at: cleanupDir) }

        // 20x20 = 400 pixels; 3 opaque pixels = 0.75%, below the 1% threshold.
        // This exercises the `hasVisibleContent` delegation path for sub-threshold
        // (but non-transparent) icons — e.g. tracking-pixel or 1-px decoration favicons.
        let feedID = UUID()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let pngData = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format)
            .pngData { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
                UIColor.red.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 3, height: 1))
            }
        let fileURL = try writeCacheFile(feedID: feedID, data: pngData)

        let image = await service.loadValidatedIcon(for: feedID)

        #expect(image == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    @Test("Handles concurrent invocations against an undecodable cache file")
    func loadValidatedIconHandlesConcurrentInvocations() async throws {
        let cleanupDir = cacheDirectory
        defer { try? FileManager.default.removeItem(at: cleanupDir) }

        // Two FeedIconView instances mounted for the same feed could hit
        // loadValidatedIcon simultaneously. The detached delete path must
        // tolerate one deleter racing ahead of the other without crashing.
        let feedID = UUID()
        let garbage = Data("not a real image".utf8)
        let fileURL = try writeCacheFile(feedID: feedID, data: garbage)

        async let first = service.loadValidatedIcon(for: feedID)
        async let second = service.loadValidatedIcon(for: feedID)
        let (a, b) = await (first, second)

        #expect(a == nil)
        #expect(b == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)))
    }

    // MARK: - resolveAndCacheIcon miss-tracker integration

    @Test("resolveAndCacheIcon records exactly one miss when all candidates fail")
    func resolveAndCacheIconRecordsOneMissWhenAllCandidatesFail() async {
        let tracker = FeedIconMissTracker()
        let isolatedService = FeedIconService(cacheDirectoryOverride: cacheDirectory, missTracker: tracker)
        let feedID = UUID()
        // Use a URL under a reserved TLD — guaranteed to fail DNS resolution without touching the network.
        let siteURL = URL(string: "https://example-invalid-no-icon.invalid")!

        _ = await isolatedService.resolveAndCacheIcon(feedSiteURL: siteURL, feedImageURL: nil, feedID: feedID)

        // After one resolveAndCacheIcon call with all candidates failing, the tracker
        // should have recorded exactly 1 miss. Calling recordMiss again should return 2.
        let nextCount = await tracker.recordMiss(for: feedID)
        #expect(nextCount == 2)
    }

    // MARK: - Test helpers

    /// Writes `data` to the path the `service` expects for `feedID`'s cached icon. Primes
    /// the cache without going through the network-backed caching path. The destination is
    /// the suite's isolated `cacheDirectory`, not the real user caches directory.
    private func writeCacheFile(feedID: UUID, data: Data) throws -> URL {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let fileURL = cacheDirectory.appendingPathComponent("\(feedID.uuidString).png")
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    // MARK: - hasVisibleContent

    @Test("Rejects fully transparent image")
    @MainActor
    func hasVisibleContentRejectsTransparent() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        let image = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        #expect(!FeedIconService.hasVisibleContent(image))
    }

    @Test("Accepts fully opaque image")
    @MainActor
    func hasVisibleContentAcceptsOpaque() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        #expect(FeedIconService.hasVisibleContent(image))
    }

    @Test("Accepts image with small visible region above threshold")
    @MainActor
    func hasVisibleContentAcceptsPartiallyVisible() {
        // 10x10 image with 1 opaque pixel = 1% — at threshold
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format)
        let image = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        #expect(FeedIconService.hasVisibleContent(image))
    }

    @Test("Rejects image below visibility threshold")
    @MainActor
    func hasVisibleContentRejectsBelowThreshold() {
        // 20x20 = 400 pixels; 3 opaque pixels = 0.75%, below the 1% threshold
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20), format: format)
        let image = renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 1))
        }

        #expect(!FeedIconService.hasVisibleContent(image))
    }

    @Test("Accepts opaque image without alpha channel")
    @MainActor
    func hasVisibleContentAcceptsOpaqueNoAlpha() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }

        #expect(FeedIconService.hasVisibleContent(image))
    }

    // MARK: - analyzeIconPixels (luminance + visibility)

    @Test("Analysis classifies a fully white image as needing a dark background")
    @MainActor
    func analyzeIconPixelsClassifiesWhiteAsNeedingDarkBackground() {
        // White-on-transparent favicons (e.g. Apple Insider) are the reason
        // the feature exists (issue #342). They must map to a black tile so
        // the icon is still visible.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }

        let stats = FeedIconService.analyzeIconPixels(image)
        #expect(stats.isVisible == true)
        // White is luminance 1.0; tiny drift is tolerated for bitmap roundtrip.
        #expect(stats.averageLuminance > 0.95)
        #expect(FeedIconService.classifyBackgroundStyle(averageLuminance: stats.averageLuminance) == .dark)
    }

    @Test("Analysis classifies a fully black image as needing a light background")
    @MainActor
    func analyzeIconPixelsClassifiesBlackAsNeedingLightBackground() {
        // Black-on-transparent icons are the other side of the bug: they
        // disappeared against the old black tile. They must map to a white
        // tile so the icon stays visible.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .image { ctx in
                UIColor.black.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }

        let stats = FeedIconService.analyzeIconPixels(image)
        #expect(stats.isVisible == true)
        #expect(stats.averageLuminance < 0.05)
        #expect(FeedIconService.classifyBackgroundStyle(averageLuminance: stats.averageLuminance) == .light)
    }

    @Test("Analysis ignores fully transparent pixels when averaging luminance")
    @MainActor
    func analyzeIconPixelsIgnoresTransparentPixels() {
        // Half-transparent, half opaque-white icon: the transparent half
        // must not drag the luminance average toward zero. Otherwise a
        // single opaque white stroke on a transparent canvas — the exact
        // Apple-Insider case — would misclassify as dark.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
                UIColor.white.setFill()
                // Only the top row is opaque, but those pixels are fully white.
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 1))
            }

        let stats = FeedIconService.analyzeIconPixels(image)
        #expect(stats.isVisible == true)
        // Average should reflect the opaque pixels only, not the 0-alpha background.
        #expect(stats.averageLuminance > 0.95)
        #expect(FeedIconService.classifyBackgroundStyle(averageLuminance: stats.averageLuminance) == .dark)
    }

    @Test("Analysis reports not visible for fully transparent image")
    @MainActor
    func analyzeIconPixelsReportsNotVisibleForTransparent() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
            .image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }

        let stats = FeedIconService.analyzeIconPixels(image)
        #expect(stats.isVisible == false)
    }

    // MARK: - ICO Decoding

    @Test("Decodes ICO file with embedded PNG")
    @MainActor
    func decodeICOWithPNG() {
        // Create a 16x16 1x-scale PNG to avoid Retina scaling
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16), format: format)
        let pngData = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }

        // Wrap in ICO container: 6-byte header + 16-byte directory entry + PNG data
        var ico = Data()
        // Header: reserved=0, type=1 (icon), count=1
        ico.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x01, 0x00])
        // Directory entry: width=16, height=16, colorCount=0, reserved=0
        ico.append(contentsOf: [16, 16, 0, 0])
        // planes=1, bitCount=32
        ico.append(contentsOf: [0x01, 0x00, 0x20, 0x00])
        // bytesInRes (little-endian)
        let size = UInt32(pngData.count)
        ico.append(contentsOf: withUnsafeBytes(of: size.littleEndian) { Array($0) })
        // imageOffset = 22 (6 header + 16 entry)
        let offset: UInt32 = 22
        ico.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
        // PNG data
        ico.append(pngData)

        let image = FeedIconService.decodeICO(ico)
        #expect(image != nil)
        #expect(image!.size.width == 16)
        #expect(image!.size.height == 16)
    }

    @Test("Decodes real BMP-based ICO file (16x16 4-bit)")
    func decodeICORealBMP() {
        // Real favicon.ico from krebsonsecurity.com — 16x16, 4-bit BMP in ICO container
        let base64 = "AAABAAEAEBAQAAAAAAAoAQAAFgAAACgAAAAQAAAAIAAAAAEABAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA////AHh4eADIyMgAVVVVAMzMzAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABUJAQkMAAAAgBQUDACAAAgAAADAAAgAgAAAFAAAAIEAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAD//wAA//8AAP//AAD//wAA4A8AAMAHAACEQwAABMEAAARBAAD//wAA/H8AAP//AAD//wAA//8AAP//AAD//wAA"
        guard let data = Data(base64Encoded: base64) else {
            Issue.record("Failed to decode base64 test data")
            return
        }

        let image = FeedIconService.decodeICO(data)
        #expect(image != nil, "BMP-based ICO should decode successfully")
    }

    @Test("Returns nil for non-ICO data")
    func decodeICORejectsNonICO() {
        let garbage = Data("not an ico file".utf8)
        #expect(FeedIconService.decodeICO(garbage) == nil)
    }

    @Test("Returns nil for empty data")
    func decodeICORejectsEmpty() {
        #expect(FeedIconService.decodeICO(Data()) == nil)
    }

    @Test("Selects the largest image from multi-image ICO")
    @MainActor
    func decodeICOSelectsLargest() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
            .pngData { ctx in UIColor.blue.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8)) }
        let large = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32), format: format)
            .pngData { ctx in UIColor.green.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 32, height: 32)) }

        var ico = Data()
        // Header: count=2
        ico.append(contentsOf: [0x00, 0x00, 0x01, 0x00, 0x02, 0x00])

        // Entry 1: 8x8
        let offset1: UInt32 = 6 + 16 + 16 // after header + 2 entries
        ico.append(contentsOf: [8, 8, 0, 0, 0x01, 0x00, 0x20, 0x00])
        let size1 = UInt32(small.count)
        ico.append(contentsOf: withUnsafeBytes(of: size1.littleEndian) { Array($0) })
        ico.append(contentsOf: withUnsafeBytes(of: offset1.littleEndian) { Array($0) })

        // Entry 2: 32x32
        let offset2 = offset1 + size1
        ico.append(contentsOf: [32, 32, 0, 0, 0x01, 0x00, 0x20, 0x00])
        let size2 = UInt32(large.count)
        ico.append(contentsOf: withUnsafeBytes(of: size2.littleEndian) { Array($0) })
        ico.append(contentsOf: withUnsafeBytes(of: offset2.littleEndian) { Array($0) })

        // Image data
        ico.append(small)
        ico.append(large)

        let image = FeedIconService.decodeICO(ico)
        #expect(image != nil)
        #expect(image!.size.width == 32)
        #expect(image!.size.height == 32)
    }
}

// MARK: - HTMLUtilities Icon Extraction Tests

@Suite("HTMLUtilities extractIconURLs Tests")
struct HTMLUtilitiesIconExtractionTests {

    let baseURL = URL(string: "https://example.com")!

    @Test("Extracts apple-touch-icon href")
    func extractsAppleTouchIcon() {
        let html = """
            <html><head>
            <link rel="apple-touch-icon" href="/apple-icon-180.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/apple-icon-180.png")
    }

    @Test("Extracts link rel=icon href")
    func extractsLinkIcon() {
        let html = """
            <html><head>
            <link rel="icon" href="/favicon.png" type="image/png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/favicon.png")
    }

    @Test("Extracts link rel='shortcut icon' href")
    func extractsShortcutIcon() {
        let html = """
            <html><head>
            <link rel="shortcut icon" href="/favicon.ico">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/favicon.ico")
    }

    @Test("Apple-touch-icon has priority over link icon")
    func priorityOrder() {
        let html = """
            <html><head>
            <link rel="icon" href="/favicon.png">
            <link rel="apple-touch-icon" href="/apple-icon.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 2)
        #expect(urls[0].absoluteString == "https://example.com/apple-icon.png")
        #expect(urls[1].absoluteString == "https://example.com/favicon.png")
    }

    @Test("Resolves protocol-relative URL")
    func resolvesProtocolRelativeURL() {
        let html = """
            <html><head>
            <link rel="icon" href="//cdn.example.com/icon.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://cdn.example.com/icon.png")
    }

    @Test("Resolves absolute URL unchanged")
    func absoluteURLUnchanged() {
        let html = """
            <html><head>
            <link rel="icon" href="https://other.com/icon.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://other.com/icon.png")
    }

    @Test("Returns empty array for HTML with no icon tags")
    func noIconTags() {
        let html = """
            <html><head>
            <title>No Icons</title>
            <link rel="stylesheet" href="/style.css">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.isEmpty)
    }

    @Test("Handles href before rel attribute order")
    func hrefBeforeRel() {
        let html = """
            <html><head>
            <link href="/icon.png" rel="icon">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 1)
        #expect(urls[0].absoluteString == "https://example.com/icon.png")
    }

    @Test("Case-insensitive matching for rel values")
    func caseInsensitive() {
        let html = """
            <html><head>
            <link rel="Icon" href="/icon.png">
            <link rel="Apple-Touch-Icon" href="/apple.png">
            </head></html>
            """
        let urls = HTMLUtilities.extractIconURLs(from: html, baseURL: baseURL)

        #expect(urls.count == 2)
    }
}

// MARK: - FeedIconMissTracker Tests

@Suite("FeedIconMissTracker Tests")
struct FeedIconMissTrackerTests {

    @Test("Miss count starts at zero for unknown feed")
    func initialMissCountIsZero() async {
        let tracker = FeedIconMissTracker()
        // If the counter starts at 0, the first recordMiss returns 1
        let firstMiss = await tracker.recordMiss(for: UUID())
        #expect(firstMiss == 1)
    }

    @Test("recordMiss increments counter and returns new count")
    func recordMissIncrementsCounter() async {
        let tracker = FeedIconMissTracker()
        let feedID = UUID()

        let first = await tracker.recordMiss(for: feedID)
        let second = await tracker.recordMiss(for: feedID)

        #expect(first == 1)
        #expect(second == 2)
    }

    @Test("recordSuccess resets counter to zero")
    func recordSuccessResetsCounter() async {
        let tracker = FeedIconMissTracker()
        let feedID = UUID()

        _ = await tracker.recordMiss(for: feedID)
        _ = await tracker.recordMiss(for: feedID)
        await tracker.recordSuccess(for: feedID)

        // If the counter was reset to 0, the next miss returns 1
        let afterReset = await tracker.recordMiss(for: feedID)
        #expect(afterReset == 1)
    }

    @Test("Counters are isolated per feed ID")
    func countersIsolatedPerFeed() async {
        let tracker = FeedIconMissTracker()
        let feedA = UUID()
        let feedB = UUID()

        _ = await tracker.recordMiss(for: feedA)
        let secondA = await tracker.recordMiss(for: feedA)
        let firstB = await tracker.recordMiss(for: feedB)

        #expect(secondA == 2)
        #expect(firstB == 1)
    }

    @Test("recordSuccess on feed with no misses is a no-op")
    func recordSuccessNoMissesIsNoOp() async {
        let tracker = FeedIconMissTracker()
        let feedID = UUID()

        await tracker.recordSuccess(for: feedID)

        // If success was a no-op, the next miss returns 1 (counter still at 0)
        let firstMiss = await tracker.recordMiss(for: feedID)
        #expect(firstMiss == 1)
    }

    @Test("Miss count after success followed by a new miss is one")
    func missCountRestartsAfterSuccess() async {
        let tracker = FeedIconMissTracker()
        let feedID = UUID()

        _ = await tracker.recordMiss(for: feedID)
        _ = await tracker.recordMiss(for: feedID)
        await tracker.recordSuccess(for: feedID)
        let afterReset = await tracker.recordMiss(for: feedID)

        #expect(afterReset == 1)
    }
}
