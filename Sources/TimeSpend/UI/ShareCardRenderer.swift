import AppKit
import WebKit

final class ShareCardRenderer {
    private var offscreenWebView: WKWebView?

    static let taglines = [
        "Not a productivity app. An emotional support animal for loading screens.",
        "Quantifying the noble art of staring at your terminal.",
        "Software that knows too much about your shame.",
        "What if your menu bar had the energy of a disappointed friend?",
        "Most dashboards tell you how well you're doing. This one doesn't.",
        "\"Claude is cooking\" — said like someone on the Titanic saying \"the ship feels very stable.\"",
        "A quantified-self app for terminal-based waiting.",
        "Every \"I'm so much faster now\" quietly omits the 51 minutes becoming one with your chair.",
        "Screen Time for people whose addiction is hoping the next response fixes the last one.",
        "Duolingo, but the owl is a menu bar icon judging your life choices.",
        "It's not time tracking. It's loss tracking.",
        "If \"touch grass\" were a native Mac utility.",
        "Built for the micro-hobby of opening a second tab while Claude \"just thinks for a sec.\"",
        "The future is here. It involves pacing around your kitchen waiting for a shell command.",
        "Timer, dashboard, PNG export, and spiritual damage assessment.",
        "You're not blocked. You're in a long-distance relationship with an autocomplete.",
        "Living in the space between \"almost done\" and \"why am I alphabetizing my desk drawer?\"",
        "At some point the stat card stops being analytics and starts being a cry for help.",
        "This app does not improve your workflow. It just bears witness to it.",
        "Every great software category starts with a pain point. This one starts with a self-own.",
    ]

    init() {
        // Pre-create offscreen WebView for card rendering
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 400, height: 500), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        self.offscreenWebView = webView
    }

    func renderCard(data: DashboardData, period: String, tagline: String? = nil, completion: @escaping (NSImage?) -> Void) {
        let selectedTagline = tagline ?? ShareCardRenderer.taglines.randomElement()!
        let html = generateCardHTML(data: data, period: period, tagline: selectedTagline)

        guard let webView = offscreenWebView else {
            completion(nil)
            return
        }

        webView.loadHTMLString(html, baseURL: nil)

        // Wait for render, then snapshot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 400, height: 500)

            webView.takeSnapshot(with: config) { image, error in
                if let error = error {
                    print("[TimeSpend] Snapshot failed: \(error)")
                    completion(nil)
                    return
                }
                completion(image)
            }
        }
    }

    private func generateCardHTML(data: DashboardData, period: String, tagline: String) -> String {
        let isWeekly = period == "week"
        let totalSeconds = isWeekly ? data.weekTotal : data.todayTotal
        let prompts = isWeekly ? data.weekPrompts : data.todayPrompts
        let avgWait = isWeekly ? data.weekAvgWait : data.todayAvgWait
        let longest = isWeekly ? data.weekLongest : data.todayLongest
        let periodLabel = isWeekly ? "this week" : "today"

        let heroText = DataStore.formatDuration(totalSeconds)
        let avgText = DataStore.formatDuration(avgWait)
        let longestText = DataStore.formatDuration(longest)

        // Grass equivalent
        let grassEquivalent = grassEquivalentText(seconds: totalSeconds)

        // Date range
        let dateRange: String
        if isWeekly {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            let calendar = Calendar.current
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!
            let yearFormatter = DateFormatter()
            yearFormatter.dateFormat = "yyyy"
            dateRange = "\(formatter.string(from: weekStart)) - \(formatter.string(from: Date())), \(yearFormatter.string(from: Date()))"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            dateRange = formatter.string(from: Date())
        }

        return """
        <!DOCTYPE html>
        <html><head><meta charset="UTF-8"><style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body {
            width: 400px; height: 500px;
            font-family: -apple-system, 'SF Mono', 'Menlo', monospace;
            background: linear-gradient(135deg, #0a0a0a 0%, #1a1a1a 50%, #0f1f0f 100%);
            color: #e5e5e5;
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .card {
            text-align: center;
            padding: 32px;
          }
          .brand {
            font-size: 10px;
            text-transform: uppercase;
            letter-spacing: 2px;
            color: #4ade80;
            margin-bottom: 8px;
          }
          .tagline {
            font-size: 9px;
            color: #555;
            font-style: italic;
            max-width: 280px;
            margin: 0 auto 24px;
            line-height: 1.4;
          }
          .hero {
            font-size: 56px;
            font-weight: 700;
            color: #fff;
            letter-spacing: -3px;
            line-height: 1;
          }
          .subtitle {
            font-size: 14px;
            color: #999;
            margin-top: 8px;
            margin-bottom: 32px;
          }
          .stats {
            font-size: 11px;
            color: #777;
            margin-bottom: 16px;
          }
          .grass {
            font-size: 12px;
            color: #4ade80;
            font-style: italic;
            margin-bottom: 32px;
          }
          .date {
            font-size: 10px;
            color: #555;
          }
          .watermark {
            font-size: 9px;
            color: #333;
            margin-top: 12px;
          }
        </style></head><body>
        <div class="card">
          <div class="brand">Claude is Thinking?</div>
          <div class="tagline">\(tagline.replacingOccurrences(of: "\"", with: "&quot;"))</div>
          <div class="hero">\(heroText)</div>
          <div class="subtitle">waiting for Claude Code \(periodLabel)</div>
          <div class="stats">\(prompts) prompts &bull; avg \(avgText)/wait &bull; longest: \(longestText)</div>
          <div class="grass">\(grassEquivalent)</div>
          <div class="date">\(dateRange)</div>
          <div class="watermark">claudeisthinking.com</div>
        </div>
        </body></html>
        """
    }

    private func grassEquivalentText(seconds: Int) -> String {
        let minutes = seconds / 60
        let equivalents = [
            (threshold: 300, text: "That's enough time to make a cup of pour-over coffee"),
            (threshold: 600, text: "That's enough time to take a walk around the block"),
            (threshold: 1200, text: "That's enough time to do a quick yoga session"),
            (threshold: 1800, text: "That's enough time to cook a simple meal"),
            (threshold: 3600, text: "That's enough time to watch an episode of your favorite show"),
            (threshold: 5400, text: "That's enough time to bake a loaf of bread"),
            (threshold: 7200, text: "That's enough time to hike a local trail"),
            (threshold: 14400, text: "That's enough time to drive to the beach and back"),
            (threshold: 21600, text: "That's enough time to fly from SF to LA... twice"),
        ]

        let match = equivalents.last { seconds >= $0.threshold }
        if let match = match {
            return match.text
        }

        // Fallback: walking distance (assumes 3 mph walking speed)
        let miles = Double(minutes) / 20.0
        return String(format: "That's enough time to walk %.1f miles", miles)
    }
}
