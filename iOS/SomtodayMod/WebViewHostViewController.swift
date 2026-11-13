import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Loads leerling.somtoday.nl in a WKWebView and injects the Somtoday Mod
/// bundle, mirroring the Android-WebView app behaviour:
/// - desktop user agent
/// - mod script injected at document end
/// - external links opened outside the webview
/// - skeleton loading screen until Somtoday has loaded
/// - spinner overlay with tap-to-retry when the site cannot be reached
final class WebViewHostViewController: UIViewController {
    private static let startURL = URL(string: "https://leerling.somtoday.nl/")!
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    private static let maxLoadRetries = 3

    private var webView: WKWebView!
    private var progressView: UIProgressView!
    private var skeletonController: UIHostingController<SkeletonView>?
    private var errorOverlay: UIView?
    private var progressObservation: NSKeyValueObservation?
    private var pendingOpenPanelCompletion: (([URL]?) -> Void)?
    private var loadRetryCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupWebView()
        setupSkeleton()
        webView.load(URLRequest(url: Self.startURL))
    }

    deinit {
        progressObservation?.invalidate()
    }

    // MARK: Setup

    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        // Weak proxy so the webview does not retain this view controller
        contentController.add(WeakScriptMessageHandler(delegate: self), name: "somtodaymod")

        if let script = loadModScript() {
            let userScript = WKUserScript(
                source: script,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            contentController.addUserScript(userScript)
        }
        configuration.userContentController = contentController

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = .systemBackground

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(didPullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        progressView = UIProgressView(progressViewStyle: .bar)
        progressView.progress = 0
        progressView.translatesAutoresizingMaskIntoConstraints = false

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        view.addSubview(progressView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        progressObservation = webView.observe(
            \.estimatedProgress,
            options: [.initial, .new]
        ) { [weak self] webView, _ in
            self?.progressView.setProgress(Float(webView.estimatedProgress), animated: true)
        }
    }

    private func loadModScript() -> String? {
        guard
            let url = Bundle.main.url(forResource: "SomtodayMod-iOS", withExtension: "js"),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("SomtodayMod-iOS.js is missing from the app bundle")
            return nil
        }
        return source
    }

    private func setupSkeleton() {
        let skeleton = SkeletonView(theme: ThemeStore.theme(for: traitCollection))
        let controller = UIHostingController(rootView: skeleton)
        controller.view.backgroundColor = .clear
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        controller.didMove(toParent: self)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        skeletonController = controller
    }

    // MARK: Skeleton handling

    private func hideSkeleton() {
        guard let controller = skeletonController else { return }
        skeletonController = nil
        UIView.animate(withDuration: 0.3, animations: {
            controller.view.alpha = 0
        }, completion: { _ in
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
        })
    }

    // MARK: Error handling (spinner overlay, like the Android app)

    private func showErrorOverlay() {
        guard errorOverlay == nil else { return }
        hideSkeleton()

        let overlay = UIView()
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.backgroundColor = .systemBackground

        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        overlay.addSubview(spinner)

        let label = UILabel()
        label.text = "Geen verbinding — tik om opnieuw te proberen"
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .callout)
        label.textColor = .secondaryLabel
        label.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(label)

        overlay.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(errorOverlayTapped))
        )

        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            spinner.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: overlay.centerYAnchor, constant: -20),

            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            label.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -32)
        ])
        errorOverlay = overlay
    }

    private func hideErrorOverlay() {
        errorOverlay?.removeFromSuperview()
        errorOverlay = nil
    }

    @objc private func errorOverlayTapped() {
        loadRetryCount = 0
        hideErrorOverlay()
        webView.reload()
    }

    @objc private func didPullToRefresh() {
        webView.reload()
    }
}

// MARK: Script messages (Somtoday Mod -> native app)

extension WebViewHostViewController: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "somtodaymod" else { return }
        let body = message.body as? [String: Any]
        if let theme = body?["theme"] as? String, body?["type"] as? String == "SAVE_THEME" {
            ThemeStore.save(theme)
        }
    }
}

/// WKUserContentController retains its message handlers strongly; this proxy
/// only keeps a weak reference so the view controller can still deallocate.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

// MARK: Navigation

extension WebViewHostViewController: WKNavigationDelegate {
    private func isSomtodayURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host == "som.today"
            || host.hasSuffix(".som.today")
            || host == "somtoday.nl"
            || host.hasSuffix(".somtoday.nl")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let target = navigationAction.request.url

        // Always keep Somtoday (leerling, inloggen, som.today) inside the app
        if isSomtodayURL(target) {
            decisionHandler(.allow)
            return
        }

        // Mirror the Android app: while the student site is open, a user-tapped
        // link leaving Somtoday opens outside the app. Everything else (login
        // redirects, e.g. to Microsoft/Entra, and programmatic loads) stays in
        // the webview so authentication keeps working.
        let isMainNavLink = navigationAction.navigationType == .linkActivated
            && navigationAction.targetFrame?.isMainFrame != false
        let isOnStudentSite = webView.url?.host?.lowercased() == "leerling.somtoday.nl"
        if isMainNavLink, isOnStudentSite, let external = target {
            UIApplication.shared.open(external, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.scrollView.refreshControl?.endRefreshing()
        progressView.setProgress(0, animated: false)
        loadRetryCount = 0
        hideErrorOverlay()

        if isSomtodayURL(webView.url) {
            // Small delay so the skeleton does not flash (same as GeckoView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.hideSkeleton()
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        handleLoadFailure()
    }

    private func handleLoadFailure() {
        webView.scrollView.refreshControl?.endRefreshing()
        // Retry a few times while the skeleton is still showing, then fall
        // back to a spinner overlay, like the Android app
        if skeletonController != nil, loadRetryCount < Self.maxLoadRetries {
            loadRetryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, self.errorOverlay == nil else { return }
                self.webView.load(URLRequest(url: Self.startURL))
            }
        } else {
            showErrorOverlay()
        }
    }
}

// MARK: UI (file upload, javascript dialogs, popups)

extension WebViewHostViewController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        pendingOpenPanelCompletion = completionHandler

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = parameters.allowsMultipleSelection
        picker.delegate = self
        present(picker, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel) { _ in completionHandler(false) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        alert.addAction(UIAlertAction(title: "Annuleren", style: .cancel) { _ in completionHandler(nil) })
        present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // window.open (e.g. update checker) opens outside the app
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }
}

// MARK: Document picker result

extension WebViewHostViewController: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        // Copy to a temporary location so the webview can read the file
        // without needing security-scoped access
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        let copies = urls.compactMap { url -> URL? in
            let target = temporaryDirectory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)
            do {
                try fileManager.copyItem(at: url, to: target)
                return target
            } catch {
                return nil
            }
        }
        pendingOpenPanelCompletion?(copies.isEmpty ? nil : copies)
        pendingOpenPanelCompletion = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pendingOpenPanelCompletion?(nil)
        pendingOpenPanelCompletion = nil
    }
}
