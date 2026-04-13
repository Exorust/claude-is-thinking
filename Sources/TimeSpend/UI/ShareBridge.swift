import Foundation
import WebKit

final class ShareBridge: NSObject, WKScriptMessageHandler {
    private let webView: WKWebView
    private let dataStore: DataStore
    var shareCardRenderer: ShareCardRenderer?
    var eventProcessor: EventProcessor?

    init(webView: WKWebView, dataStore: DataStore) {
        self.webView = webView
        self.dataStore = dataStore
        super.init()

        webView.configuration.userContentController.add(self, name: "share")
    }

    func pushShareData() {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let escaped = jsonString.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.updateShareData('\(escaped)')"
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(js)
        }
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        let period = body["period"] as? String ?? "week"

        switch type {
        case "renderPreview":
            renderPreview(period: period)

        case "copyForShare":
            copyForShare(period: period)

        case "openURL":
            if let urlString = body["url"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case "shareAndOpen":
            let urlString = body["url"] as? String
            shareAndOpen(period: period, urlString: urlString)

        case "copyToClipboard":
            copyToClipboard(period: period)

        case "shareMenu":
            shareMenu(period: period)

        case "savePNG":
            savePNG(period: period)

        default:
            break
        }
    }

    // MARK: - Actions

    private func renderPreview(period: String) {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        shareCardRenderer?.renderCard(data: data, period: period) { [weak self] image in
            guard let self = self, let image = image,
                  let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

            let base64 = pngData.base64EncodedString()
            let dataURL = "data:image/png;base64,\(base64)"
            let js = "window.setSharePreview('\(dataURL)')"
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(js)
            }
        }
    }

    private func copyImageToClipboard(_ image: NSImage) {
        guard let pngData = pngData(from: image) else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(pngData, forType: .png)
    }

    private func saveImageToDownloads(_ image: NSImage, period: String) {
        guard let pngData = pngData(from: image) else { return }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let filename = "claude-is-thinking-\(period).png"
        let url = downloads.appendingPathComponent(filename)
        try? pngData.write(to: url)
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapRep.representation(using: .png, properties: [:])
    }

    private func copyForShare(period: String) {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        shareCardRenderer?.renderCard(data: data, period: period) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.copyImageToClipboard(image)
            self.saveImageToDownloads(image, period: period)

            // Notify JS that image is on clipboard
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript("window.imageCopied()")
            }
        }
    }

    private func shareAndOpen(period: String, urlString: String?) {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        shareCardRenderer?.renderCard(data: data, period: period) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.copyImageToClipboard(image)

            if let urlString = urlString, let url = URL(string: urlString) {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func copyToClipboard(period: String) {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        shareCardRenderer?.renderCard(data: data, period: period) { [weak self] image in
            guard let self = self, let image = image else { return }
            self.copyImageToClipboard(image)
            self.saveImageToDownloads(image, period: period)
        }
    }

    private func shareMenu(period: String) {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        shareCardRenderer?.renderCard(data: data, period: period) { image in
            guard let image = image else { return }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("claude-is-thinking-card.png")
            if let tiffData = image.tiffRepresentation,
               let bitmapRep = NSBitmapImageRep(data: tiffData),
               let pngData = bitmapRep.representation(using: .png, properties: [:]) {
                try? pngData.write(to: tempURL)

                DispatchQueue.main.async {
                    let picker = NSSharingServicePicker(items: [tempURL])
                    if let contentView = NSApp.keyWindow?.contentView {
                        picker.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .minY)
                    }
                }
            }
        }
    }

    private func savePNG(period: String) {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        shareCardRenderer?.renderCard(data: data, period: period) { image in
            guard let image = image,
                  let tiffData = image.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let pngData = bitmapRep.representation(using: .png, properties: [:]) else { return }

            DispatchQueue.main.async {
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.png]
                savePanel.nameFieldStringValue = "claude-is-thinking-\(period).png"
                savePanel.title = "Save Share Card"

                if savePanel.runModal() == .OK, let url = savePanel.url {
                    try? pngData.write(to: url)
                }
            }
        }
    }
}
