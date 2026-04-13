import Foundation
import WebKit

final class DashboardBridge: NSObject, WKScriptMessageHandler {
    private let webView: WKWebView
    private let dataStore: DataStore
    var onOpenSettings: (() -> Void)?
    var onOpenShare: (() -> Void)?
    private var eventProcessor: EventProcessor?

    init(webView: WKWebView, dataStore: DataStore) {
        self.webView = webView
        self.dataStore = dataStore
        super.init()

        webView.configuration.userContentController.add(self, name: "action")
    }

    func setEventProcessor(_ processor: EventProcessor) {
        self.eventProcessor = processor
    }

    // MARK: - Push Data to WebView

    func refreshDashboard() {
        let activeStart = eventProcessor?.activeSessionStartTime
        let data = dataStore.getDashboardData(activeSessionStart: activeStart)

        let encoder = JSONEncoder()
        guard let jsonData = try? encoder.encode(data),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let escaped = jsonString.replacingOccurrences(of: "'", with: "\\'")
        let js = "window.updateDashboard('\(escaped)')"
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(js)
        }

        // Also push settings state
        pushSettings()
    }

    func updateLiveTimer(seconds: Int) {
        let js = "window.updateLiveTimer(\(seconds))"
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(js)
        }
    }

    func showFirstRun() {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("window.showFirstRun()")
        }
    }

    func pushSettings() {
        let grassThreshold = Int(dataStore.getSetting(.grassThreshold) ?? "180") ?? 180
        let launchAtLogin = dataStore.getSetting(.launchAtLogin) == "true"
        let hooksInstalled = HookInstaller().isInstalled
        let appearance = dataStore.getSetting(.appearance) ?? "system"
        let accentColor = dataStore.getSetting(.accentColor) ?? "orange"

        let settings: [String: Any] = [
            "grassThreshold": grassThreshold,
            "launchAtLogin": launchAtLogin,
            "hooksInstalled": hooksInstalled,
            "appearance": appearance,
            "accentColor": accentColor
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

    // MARK: - Receive Messages from WebView

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }

        switch type {
        case "enableTracking":
            handleEnableTracking()

        case "disableTracking":
            handleDisableTracking()

        case "fixTracking":
            handleEnableTracking()

        case "openURL":
            if let urlString = body["url"] as? String, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        case "setSetting":
            if let key = body["key"] as? String, let value = body["value"] as? String {
                handleSetSetting(key: key, value: value)
            }

        case "openSettings":
            DispatchQueue.main.async {
                self.onOpenSettings?()
            }

        case "openShare":
            DispatchQueue.main.async {
                self.onOpenShare?()
            }

        case "quit":
            NSApp.terminate(nil)

        case "forceStopSessions":
            eventProcessor?.forceCloseAllSessions()

        default:
            break
        }
    }

    // MARK: - Action Handlers

    private func handleEnableTracking() {
        let installer = HookInstaller()
        do {
            try installer.install()
            dataStore.setSetting(.hooksInstalled, value: "true")
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript("window.showDashboard()")
                self.refreshDashboard()
            }
        } catch {
            print("[TimeSpend] Hook install failed: \(error)")
            let js = "document.querySelector('.first-run p').textContent = 'Hook installation failed. Check console for details.'"
            DispatchQueue.main.async {
                self.webView.evaluateJavaScript(js)
            }
        }
    }

    private func handleDisableTracking() {
        let installer = HookInstaller()
        do {
            try installer.uninstall()
            dataStore.setSetting(.hooksInstalled, value: "false")
            pushSettings()
        } catch {
            print("[TimeSpend] Hook uninstall failed: \(error)")
        }
    }

    private func handleSetSetting(key: String, value: String) {
        if let settingsKey = SettingsKey(rawValue: key) {
            dataStore.setSetting(settingsKey, value: value)
        }
    }
}
