import AppKit
import WebKit

/// Google's Android account sign-in page in a window. When the page finishes
/// it sets an `oauth_token` cookie; the window hands that token back and closes.
@MainActor
final class GoogleSignInWindow: NSObject, NSWindowDelegate, WKHTTPCookieStoreObserver {
    static let startURL = URL(string: "https://accounts.google.com/embedded/setup/v2/android?source=com.android.settings&xoauth_display_name=Android%20Phone&canFrp=1&canSk=1&lang=en&langCountry=en_us&hl=en-US&cc=us")!

    /// The page calls these on an Android phone; it only needs them to exist.
    static let bridgeScript = """
    window.mm = {
      showView: function() {},
      setAccountIdentifier: function() {},
      log: function() {}
    };
    """

    private let window: NSWindow
    private let webView: WKWebView
    private var completion: ((String?) -> Void)?
    private var keepAlive: GoogleSignInWindow?

    /// Opens the window. `completion` gets the token, or nil when closed.
    static func present(completion: @escaping (String?) -> Void) {
        let w = GoogleSignInWindow(completion: completion)
        w.keepAlive = w
    }

    private init(completion: @escaping (String?) -> Void) {
        self.completion = completion
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.userContentController.addUserScript(
            WKUserScript(source: Self.bridgeScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        config.websiteDataStore.httpCookieStore.add(self)
        window.title = "Sign in to Google"
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        webView.load(URLRequest(url: Self.startURL))
    }

    nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        Task { @MainActor in
            let cookies = await cookieStore.allCookies()
            if let token = cookies.first(where: { $0.name == "oauth_token" })?.value {
                self.finish(token)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    private func finish(_ token: String?) {
        guard let completion else { return }
        self.completion = nil
        webView.configuration.websiteDataStore.httpCookieStore.remove(self)
        window.close()
        completion(token)
        keepAlive = nil
    }
}
