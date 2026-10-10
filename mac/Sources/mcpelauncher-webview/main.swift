// The Microsoft sign-in window the game opens through the launcher.
//
// Usage: mcpelauncher-webview <start-url> <end-url-prefix>
//
// Shows <start-url>. When a page navigates to a URL starting with
// <end-url-prefix>, prints that URL and exits. Closing the window exits
// without printing, which the game treats as a cancelled sign-in.
import AppKit
import BedrockLauncherCore
import WebKit

@MainActor
final class SignInWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    let window: NSWindow
    let webView: WKWebView
    let endPrefix: String

    init(start: URL, endPrefix: String) {
        self.endPrefix = endPrefix
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Sign in"
        window.contentView = webView
        window.delegate = self
        webView.navigationDelegate = self
        webView.load(URLRequest(url: start))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // The end URL uses a custom scheme that never loads, so catch it here.
        if let url = action.request.url, WebViewURL.isEnd(url, prefix: endPrefix) {
            decisionHandler(.cancel)
            print(url.absoluteString)
            fflush(stdout)
            exit(0)
        }
        decisionHandler(.allow)
    }

    func windowWillClose(_ notification: Notification) {
        exit(0)
    }
}

let args = CommandLine.arguments
guard args.count >= 3, let start = URL(string: args[1]) else {
    FileHandle.standardError.write(Data("usage: mcpelauncher-webview <start-url> <end-url-prefix>\n".utf8))
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
MainActor.assumeIsolated {
    let signIn = SignInWindow(start: start, endPrefix: args[2])
    withExtendedLifetime(signIn) { app.run() }
}
