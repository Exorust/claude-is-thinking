import Foundation
import WebKit

final class SettingsBridge: NSObject, WKScriptMessageHandler {
    private let webView: WKWebView
    private let dataStore: DataStore
    var onSettingsChanged: (() -> Void)?
    var onDisableTracking: (() -> Void)?

    init(webView: WKWebView, dataStore: DataStore) {
        self.webView = webView
        self.dataStore = dataStore
        super.init()

        webView.configuration.userContentController.add(self, name: "settings")
    }

    func pushSettings() {
        let grassThreshold = Int(dataStore.getSetting(.grassThreshold) ?? "180") ?? 180
        let launchAtLogin = dataStore.getSetting(.launchAtLogin) == "true"
        let hooksInstalled = HookInstaller().isInstalled
        let appearance = dataStore.getSetting(.appearance) ?? "system"

        let settings: [String: Any] = [
            "grassThreshold": grassThreshold,
            "launchAtLogin": launchAtLogin,
            "hooksInstalled": hooksInstalled,
            "appearance": appearance
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: settings),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let escaped = jsonString.replacingOccurrences(of: "'", with: "\\'")
            let js = "window.updateSettings('\(escaped)')"
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(js)
            }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "setSetting":
            if let key = body["key"] as? String, let value = body["value"] as? String {
                if let settingsKey = SettingsKey(rawValue: key) {
                    dataStore.setSetting(settingsKey, value: value)
                    onSettingsChanged?()
                }
            }

        case "disableTracking":
            onDisableTracking?()

        case "reinstallHooks":
            handleReinstallHooks()

        default:
            break
        }
    }

    private func handleReinstallHooks() {
        let installer = HookInstaller()
        do {
            try installer.uninstall()
            try installer.install()
            dataStore.setSetting(.hooksInstalled, value: "true")
            onSettingsChanged?()
            pushSettings()
        } catch {
            print("[TimeSpend] Hook reinstall failed: \(error)")
        }
    }
}
