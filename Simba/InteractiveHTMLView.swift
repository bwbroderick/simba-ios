import SwiftUI
import WebKit

struct InteractiveHTMLView: UIViewRepresentable {
    let html: String
    var onLinkTap: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        webView.scrollView.backgroundColor = UIColor(white: 0.97, alpha: 1.0)

        // Enable text selection
        webView.configuration.preferences.isTextInteractionEnabled = true

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let styledHTML = wrapHTML(html)
        webView.loadHTMLString(styledHTML, baseURL: nil)
    }

    private func wrapHTML(_ html: String) -> String {
        """
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=3.0, user-scalable=yes">
            <style>
              * { box-sizing: border-box; }
              html, body {
                margin: 0;
                padding: 0;
                width: 100%;
                -webkit-text-size-adjust: 100%;
              }
              body {
                font-family: -apple-system, Helvetica, Arial, sans-serif;
                font-size: 16px;
                line-height: 1.6;
                color: #222;
                padding: 16px;
                background: #f7f7f7;
                word-wrap: break-word;
                overflow-wrap: break-word;
              }
              img {
                max-width: 100%;
                height: auto;
                display: block;
              }
              a {
                color: #0066cc;
                text-decoration: underline;
              }
              pre, code {
                white-space: pre-wrap;
                word-wrap: break-word;
                background: #e8e8e8;
                padding: 2px 6px;
                border-radius: 4px;
                font-size: 14px;
              }
              pre {
                padding: 12px;
              }
              table {
                max-width: 100%;
                border-collapse: collapse;
              }
              td, th {
                padding: 8px;
              }
              blockquote {
                margin: 12px 0;
                padding-left: 16px;
                border-left: 3px solid #ccc;
                color: #555;
              }
            </style>
          </head>
          <body>\(html)</body>
        </html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onLinkTap: ((URL) -> Void)?

        init(onLinkTap: ((URL) -> Void)?) {
            self.onLinkTap = onLinkTap
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial HTML load
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Handle link taps
            if let url = navigationAction.request.url,
               navigationAction.navigationType == .linkActivated {
                if let onLinkTap = onLinkTap {
                    onLinkTap(url)
                } else {
                    // Default: open in Safari
                    UIApplication.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }
    }
}
