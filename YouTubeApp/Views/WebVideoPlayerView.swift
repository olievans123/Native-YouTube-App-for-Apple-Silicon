import SwiftUI
import WebKit

struct WebVideoPlayerView: NSViewRepresentable {
    let videoId: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Allow inline playback
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false

        // Custom user agent to avoid restrictions
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only load if video changed
        if webView.url?.absoluteString.contains(videoId) != true {
            // Load full watch page instead of embed
            let watchURL = "https://www.youtube.com/watch?v=\(videoId)"

            if let url = URL(string: watchURL) {
                webView.load(URLRequest(url: url))
            }
        }
    }
}
