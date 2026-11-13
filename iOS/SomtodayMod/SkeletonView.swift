import SwiftUI

/// Native loading screen shown while Somtoday loads inside the WKWebView.
/// Loads the same skeleton HTML files as the Android-GeckoView app.
struct SkeletonView: View {
    let theme: String

    var body: some View {
        SkeletonWebView(theme: theme)
            .ignoresSafeArea()
            .transition(.opacity)
    }
}

private struct SkeletonWebView: UIViewRepresentable {
    let theme: String

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.scrollView.isScrollEnabled = false
        if let url = Bundle.main.url(
            forResource: "skeleton-\(theme)",
            withExtension: "html",
            subdirectory: nil
        ) {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
