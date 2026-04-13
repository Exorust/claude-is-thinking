import AppKit
import WebKit
import os.log

private let logger = Logger(subsystem: "dev.timespend.app", category: "App")

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var webView: WKWebView!
    private var eventMonitor: Any?
    private var webViewLoaded = false

    // Core services
    private var dataStore: DataStore!
    private var eventProcessor: EventProcessor!
    private var hookInstaller: HookInstaller!
    private var grassNotifier: GrassNotifier!
    private var dashboardBridge: DashboardBridge!
    private var shareCardRenderer: ShareCardRenderer!

    // Settings window
    private var settingsWindow: NSWindow?
    private var settingsWebView: WKWebView?
    private var settingsBridge: SettingsBridge?

    // Share window
    private var shareWindow: NSWindow?
    private var shareWebView: WKWebView?
    private var shareBridge: ShareBridge?

    // Timer state
    private var menuBarUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon, this is a menu bar only app
        NSApp.setActivationPolicy(.accessory)

        setupDataStore()
        setupMenuBar()
        setupPopover()
        setupServices()
        startMonitoring()

        // Listen for sleep/wake
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsnc.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: - Setup

    private func setupDataStore() {
        dataStore = DataStore()
        dataStore.initialize()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Claude is Thinking?")
            button.image?.size = NSSize(width: 16, height: 16)
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    private func setupPopover() {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        config.userContentController = userContentController

        // Allow file access for loading local HTML
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 640), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self

        // Set up the bridge
        dashboardBridge = DashboardBridge(webView: webView, dataStore: dataStore)
        shareCardRenderer = ShareCardRenderer()

        // Load dashboard HTML from resource bundle
        loadDashboardHTML()

        popover = NSPopover()
        popover.contentSize = NSSize(width: 380, height: 640)
        popover.behavior = .transient
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = webView
    }

    private func loadDashboardHTML() {
        // Try Bundle.module first (works in SPM debug builds)
        if let htmlURL = Bundle.module.url(forResource: "dashboard", withExtension: "html", subdirectory: "Resources") {
            logger.info("Loading dashboard from Bundle.module: \(htmlURL.absoluteString)")
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            return
        }

        // Fallback: look in the .app bundle's Resources directory for the SPM resource bundle
        let resourceBundleName = "TimeSpend_TimeSpend"
        if let resourceBundleURL = Bundle.main.url(forResource: resourceBundleName, withExtension: "bundle"),
           let resourceBundle = Bundle(url: resourceBundleURL),
           let htmlURL = resourceBundle.url(forResource: "dashboard", withExtension: "html", subdirectory: "Resources") {
            logger.info("Loading dashboard from app bundle: \(htmlURL.absoluteString)")
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            return
        }

        // Last resort: check next to the executable
        let executableURL = Bundle.main.executableURL!.deletingLastPathComponent()
        let possiblePaths = [
            executableURL.appendingPathComponent("\(resourceBundleName).bundle/Resources/dashboard.html"),
            executableURL.deletingLastPathComponent().appendingPathComponent("Resources/\(resourceBundleName).bundle/Resources/dashboard.html"),
        ]

        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path.path) {
                logger.info("Loading dashboard from fallback: \(path.absoluteString)")
                webView.loadFileURL(path, allowingReadAccessTo: path.deletingLastPathComponent())
                return
            }
        }

        logger.error("Could not find dashboard.html in any bundle location")
        logger.error("Bundle.main.bundlePath: \(Bundle.main.bundlePath)")
        logger.error("Bundle.main.resourcePath: \(Bundle.main.resourcePath ?? "nil")")
    }

    private func setupServices() {
        hookInstaller = HookInstaller()
        grassNotifier = GrassNotifier(dataStore: dataStore)
        grassNotifier.requestPermission()

        eventProcessor = EventProcessor(dataStore: dataStore, onSessionUpdate: { [weak self] in
            self?.handleSessionUpdate()
        }, onSessionEnd: { [weak self] durationSeconds in
            self?.grassNotifier.notifySessionEnd(durationSeconds: durationSeconds)
        })

        dashboardBridge.setEventProcessor(eventProcessor)
        dashboardBridge.onOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }
        dashboardBridge.onOpenShare = { [weak self] in
            self?.openShareWindow()
        }
    }

    private func startMonitoring() {
        eventProcessor.startWatching()

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.eventProcessor.checkOrphans()
        }

        menuBarUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateMenuBarTimer()
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logger.info("WebView loaded successfully")
        webViewLoaded = true
        pushInitialState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("WebView failed to load: \(error.localizedDescription)")
    }

    private func pushInitialState() {
        if hookInstaller.isInstalled {
            dashboardBridge.refreshDashboard()
        } else {
            dashboardBridge.showFirstRun()
        }
    }

    // MARK: - Menu Bar Timer

    private func updateMenuBarTimer() {
        guard let button = statusItem.button else { return }

        if let activeStart = eventProcessor.activeSessionStartTime {
            let elapsed = Int(Date().timeIntervalSince(activeStart))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            button.title = " \(minutes):\(String(format: "%02d", seconds))"
            button.image = nil
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Claude is Thinking?")
            button.image?.size = NSSize(width: 16, height: 16)
        }
    }

    // MARK: - Session Updates

    private func handleSessionUpdate() {
        if popover.isShown {
            dashboardBridge.refreshDashboard()
        }
        grassNotifier.checkThreshold()
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            stopEventMonitor()
        } else {
            if let button = statusItem.button {
                // Refresh state every time popover opens
                if webViewLoaded {
                    if hookInstaller.isInstalled {
                        dashboardBridge.refreshDashboard()
                    } else {
                        dashboardBridge.showFirstRun()
                    }
                }
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                startEventMonitor()
            }
        }
    }

    private func startEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let self = self, self.popover.isShown {
                self.popover.performClose(nil)
                self.stopEventMonitor()
            }
        }
    }

    private func stopEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Share Window

    func openShareWindow() {
        if let window = shareWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 750), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        shareWebView = wv

        let bridge = ShareBridge(webView: wv, dataStore: dataStore)
        bridge.shareCardRenderer = shareCardRenderer
        bridge.eventProcessor = eventProcessor
        shareBridge = bridge

        // Load share HTML
        if let htmlURL = Bundle.module.url(forResource: "share", withExtension: "html", subdirectory: "Resources") {
            wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            let resourceBundleName = "TimeSpend_TimeSpend"
            if let resourceBundleURL = Bundle.main.url(forResource: resourceBundleName, withExtension: "bundle"),
               let resourceBundle = Bundle(url: resourceBundleURL),
               let htmlURL = resourceBundle.url(forResource: "share", withExtension: "html", subdirectory: "Resources") {
                wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            }
        }

        // Push share data after a short delay for WebView to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            bridge.pushShareData()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 750),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Share Your Stats"
        window.contentView = wv
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        shareWindow = window
    }

    // MARK: - Settings Window

    func openSettingsWindow() {
        // If already open, bring to front
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 500), configuration: config)
        wv.setValue(false, forKey: "drawsBackground")
        settingsWebView = wv

        let bridge = SettingsBridge(webView: wv, dataStore: dataStore)
        bridge.onSettingsChanged = { [weak self] in
            self?.dashboardBridge.refreshDashboard()
        }
        bridge.onDisableTracking = { [weak self] in
            let installer = HookInstaller()
            try? installer.uninstall()
            self?.dataStore.setSetting(.hooksInstalled, value: "false")
            self?.dashboardBridge.refreshDashboard()
            bridge.pushSettings()
        }
        settingsBridge = bridge

        // Load settings HTML
        if let htmlURL = Bundle.module.url(forResource: "settings", withExtension: "html", subdirectory: "Resources") {
            wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            let resourceBundleName = "TimeSpend_TimeSpend"
            if let resourceBundleURL = Bundle.main.url(forResource: resourceBundleName, withExtension: "bundle"),
               let resourceBundle = Bundle(url: resourceBundleURL),
               let htmlURL = resourceBundle.url(forResource: "settings", withExtension: "html", subdirectory: "Resources") {
                wv.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
            }
        }

        // Push settings after a short delay for WebView to load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            bridge.pushSettings()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude is Thinking? Settings"
        window.contentView = wv
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    // MARK: - Sleep/Wake

    @objc private func systemWillSleep(_ notification: Notification) {
        eventProcessor.pauseOrphanDetection()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        eventProcessor.resumeOrphanDetection()
    }
}
