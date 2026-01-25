import UIKit
import WebKit

class HTMLSnapshotCache {
    static let shared = HTMLSnapshotCache()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let manifestURL: URL
    private let maxCacheSize = 50
    private var cacheManifest: [CacheEntry] = []
    private let queue = DispatchQueue(label: "com.simba.htmlsnapshotcache", attributes: .concurrent)

    struct CacheEntry: Codable {
        let key: String
        let timestamp: Date
        let filename: String
    }

    init() {
        cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("html-snapshots")
        manifestURL = cacheDirectory.appendingPathComponent("manifest.json")

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        loadManifest()
    }

    func image(for key: String) -> UIImage? {
        if let image = memoryCache.object(forKey: key as NSString) {
            updateTimestamp(for: key)
            return image
        }

        var foundEntry: CacheEntry?
        queue.sync {
            foundEntry = cacheManifest.first(where: { $0.key == key })
        }

        guard let entry = foundEntry else { return nil }

        let fileURL = cacheDirectory.appendingPathComponent(entry.filename)
        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        memoryCache.setObject(image, forKey: key as NSString)
        updateTimestamp(for: key)
        return image
    }

    func store(image: UIImage, for key: String) {
        memoryCache.setObject(image, forKey: key as NSString)

        let filename = "\(abs(key.hashValue)).png"
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }

            if let data = image.pngData() {
                try? data.write(to: fileURL)

                self.cacheManifest.removeAll { $0.key == key }

                let entry = CacheEntry(key: key, timestamp: Date(), filename: filename)
                self.cacheManifest.append(entry)

                self.evictIfNeeded()
                self.saveManifest()
            }
        }
    }

    private func updateTimestamp(for key: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            if let index = self.cacheManifest.firstIndex(where: { $0.key == key }) {
                let entry = self.cacheManifest[index]
                self.cacheManifest.remove(at: index)
                self.cacheManifest.append(CacheEntry(key: entry.key, timestamp: Date(), filename: entry.filename))
                self.saveManifest()
            }
        }
    }

    private func evictIfNeeded() {
        cacheManifest.sort { $0.timestamp < $1.timestamp }

        while cacheManifest.count > maxCacheSize {
            let oldest = cacheManifest.removeFirst()
            let fileURL = cacheDirectory.appendingPathComponent(oldest.filename)
            try? fileManager.removeItem(at: fileURL)
            memoryCache.removeObject(forKey: oldest.key as NSString)
        }
    }

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode([CacheEntry].self, from: data) else {
            return
        }
        cacheManifest = manifest
    }

    private func saveManifest() {
        guard let data = try? JSONEncoder().encode(cacheManifest) else { return }
        try? data.write(to: manifestURL, options: [.atomic])
    }

    func preRenderInBackground(threads: [EmailThread], maxCount: Int = 20) {
        let screenWidth = UIScreen.main.bounds.width * 0.8 - 32
        let size = CGSize(width: screenWidth, height: 400)

        Task.detached(priority: .background) {
            for thread in threads.prefix(maxCount) {
                guard let html = thread.htmlBody, !html.isEmpty else { continue }

                let key = "\(html.hashValue)_\(Int(size.width))x\(Int(size.height))"

                if self.image(for: key) != nil { continue }

                await self.renderAndCache(html: html, key: key, size: size)
            }
        }
    }

    @MainActor
    private func renderAndCache(html: String, key: String, size: CGSize) async {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        let webView = WKWebView(frame: CGRect(origin: .zero, size: size), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        webView.scrollView.isScrollEnabled = false

        let styledHTML = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=\(Int(size.width)), initial-scale=1.0, maximum-scale=1.0">
            <style>
              * { box-sizing: border-box; }
              html, body { margin: 0; padding: 0; width: \(Int(size.width))px; height: \(Int(size.height))px; overflow: hidden; }
              body { font-family: -apple-system, Helvetica, Arial, sans-serif; font-size: 15px; line-height: 1.5; color: #222; padding: 16px; background: #f7f7f7; }
              img { max-width: 100%; height: auto; display: block; }
              a { color: #111; }
              pre, code { white-space: pre-wrap; word-wrap: break-word; }
              table { max-width: 100%; }
            </style>
          </head>
          <body>\(html)</body>
        </html>
        """

        webView.loadHTMLString(styledHTML, baseURL: nil)

        try? await Task.sleep(nanoseconds: 500_000_000)

        let snapshotConfig = WKSnapshotConfiguration()
        snapshotConfig.rect = CGRect(origin: .zero, size: size)

        if let image = try? await webView.takeSnapshot(configuration: snapshotConfig) {
            store(image: image, for: key)
        }
    }
}
