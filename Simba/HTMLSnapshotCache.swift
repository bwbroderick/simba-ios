import UIKit
import WebKit

class HTMLSnapshotCache {
    static let shared = HTMLSnapshotCache()
    static let didStoreNotification = Notification.Name("HTMLSnapshotCacheDidStore")
    static let didCompleteNotification = Notification.Name("HTMLSnapshotCacheDidComplete")

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let manifestURL: URL
    private let maxCacheSize = 100  // Increased for multi-page
    private var cacheManifest: [CacheEntry] = []
    private var pageCountMap: [String: Int] = [:]  // baseKey -> pageCount
    private var completedRenders: Set<String> = []  // baseKeys that are fully rendered
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

    // MARK: - Multi-page support

    func pageCount(for baseKey: String) -> Int? {
        queue.sync { pageCountMap[baseKey] }
    }

    func setPageCount(_ count: Int, for baseKey: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.pageCountMap[baseKey] = count
        }
    }

    func isComplete(baseKey: String) -> Bool {
        queue.sync { completedRenders.contains(baseKey) }
    }

    func markComplete(baseKey: String) {
        queue.async(flags: .barrier) { [weak self] in
            self?.completedRenders.insert(baseKey)
        }
        // Notify that this baseKey is fully rendered
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: HTMLSnapshotCache.didCompleteNotification,
                object: nil,
                userInfo: ["baseKey": baseKey]
            )
        }
    }

    func images(for baseKey: String) -> [UIImage]? {
        guard let count = pageCount(for: baseKey), isComplete(baseKey: baseKey) else {
            return nil
        }
        var images: [UIImage] = []
        for i in 0..<count {
            let pageKey = "\(baseKey)_p\(i)"
            guard let img = image(for: pageKey) else { return nil }
            images.append(img)
        }
        return images
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

                // Notify observers that this key is now available
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: HTMLSnapshotCache.didStoreNotification,
                        object: nil,
                        userInfo: ["key": key]
                    )
                }
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
        let screenWidth = UIScreen.main.bounds.width * 0.8
        let pageHeight: CGFloat = UIScreen.main.bounds.height * 0.6
        let size = CGSize(width: screenWidth, height: pageHeight)

        Task.detached(priority: .background) {
            for thread in threads.prefix(maxCount) {
                guard let html = thread.htmlBody, !html.isEmpty else { continue }

                let baseKey = "\(html.hashValue)_\(Int(size.width))x\(Int(size.height))"

                // Skip if already complete
                if self.isComplete(baseKey: baseKey) { continue }

                await self.renderMultiPageAndCache(html: html, baseKey: baseKey, pageSize: size)
            }
        }
    }

    @MainActor
    private func renderMultiPageAndCache(html: String, baseKey: String, pageSize: CGSize) async {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true

        // Create webview with full width but large height for content
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: pageSize.width, height: 10000), configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        webView.scrollView.isScrollEnabled = true

        let styledHTML = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=\(Int(pageSize.width)), initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
              * { box-sizing: border-box; }
              html, body { margin: 0; padding: 0; width: \(Int(pageSize.width))px; }
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

        // Wait for load
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Get content height
        guard let contentHeight = try? await webView.evaluateJavaScript("document.body.scrollHeight") as? CGFloat,
              contentHeight > 0 else {
            return
        }

        let expectedPages = max(1, Int(ceil(contentHeight / pageSize.height)))
        setPageCount(expectedPages, for: baseKey)

        // Resize webview to full content height
        webView.frame = CGRect(x: 0, y: 0, width: pageSize.width, height: contentHeight)

        // Capture each page
        for pageIndex in 0..<expectedPages {
            let yOffset = CGFloat(pageIndex) * pageSize.height
            let remainingHeight = contentHeight - yOffset
            let captureHeight = min(pageSize.height, remainingHeight)

            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.rect = CGRect(x: 0, y: yOffset, width: pageSize.width, height: captureHeight)

            if let image = try? await webView.takeSnapshot(configuration: snapshotConfig) {
                let pageKey = "\(baseKey)_p\(pageIndex)"
                store(image: image, for: pageKey)
            }
        }

        // Mark as complete
        markComplete(baseKey: baseKey)
    }
}
