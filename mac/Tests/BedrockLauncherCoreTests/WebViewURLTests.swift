import Foundation
import Testing
@testable import BedrockLauncherCore

@Suite struct WebViewURLTests {
    let prefix = "ms-xal-0000000048183522://auth"

    @Test func matchesCustomSchemePrefix() {
        #expect(WebViewURL.isEnd(URL(string: "ms-xal-0000000048183522://auth?code=abc&state=1")!, prefix: prefix))
    }

    @Test func rejectsOtherURLs() {
        #expect(!WebViewURL.isEnd(URL(string: "https://login.live.com/oauth20_authorize.srf")!, prefix: prefix))
        #expect(!WebViewURL.isEnd(URL(string: "ms-xal-0000000048183522://other")!, prefix: prefix))
    }

    @Test func matchesSchemeCaseInsensitively() {
        #expect(WebViewURL.isEnd(URL(string: "MS-XAL-0000000048183522://auth?code=x")!, prefix: prefix))
    }
}
