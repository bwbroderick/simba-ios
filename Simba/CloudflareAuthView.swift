import SwiftUI
import WebKit

struct CloudflareAuthView: UIViewRepresentable {
    let onAuthenticated: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthenticated: onAuthenticated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Clear stale CF_Authorization and cf_clearance cookies before starting auth
        let cookieStore = config.websiteDataStore.httpCookieStore
        cookieStore.getAllCookies { cookies in
            for cookie in cookies where cookie.name == "CF_Authorization" || cookie.name == "cf_clearance" {
                cookieStore.delete(cookie)
            }
            DispatchQueue.main.async {
                let url = URL(string: "https://api.ai-simba.com/api/v1/stats")!
                webView.load(URLRequest(url: url))
            }
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let onAuthenticated: (String) -> Void
        private var foundToken = false

        init(onAuthenticated: @escaping (String) -> Void) {
            self.onAuthenticated = onAuthenticated
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Only check for token when we've navigated back to our API domain
            guard let url = webView.url,
                  url.host?.contains("ai-simba.com") == true,
                  !foundToken else { return }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.foundToken else { return }
                for cookie in cookies {
                    if cookie.name == "CF_Authorization" {
                        self.foundToken = true

                        // Copy ALL cookies from WKWebView to URLSession's cookie storage
                        // so URLSession gets cf_clearance and other Cloudflare cookies
                        for c in cookies {
                            HTTPCookieStorage.shared.setCookie(c)
                        }

                        DispatchQueue.main.async {
                            self.onAuthenticated(cookie.value)
                        }
                        return
                    }
                }
            }
        }
    }
}
