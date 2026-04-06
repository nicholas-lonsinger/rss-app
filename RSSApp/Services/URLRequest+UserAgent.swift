import Foundation

extension URLRequest {

    /// A mobile Safari User-Agent string used to avoid 403 blocks from CDNs
    /// (Cloudflare, Medium, Substack) that reject default library agents.
    static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 19_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/19.0 Mobile/15E148 Safari/604.1"

    /// Sets a browser-like User-Agent header on this request.
    mutating func setBrowserUserAgent() {
        setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
    }
}
