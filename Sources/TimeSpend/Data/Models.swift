import Foundation
import GRDB

// MARK: - Database Records

struct WaitSession: Codable, FetchableRecord, PersistableRecord, Identifiable {
    var id: Int64?
    var startTime: Date
    var endTime: Date?
    var durationSeconds: Int?
    var aiTool: String
    var sessionId: String?

    static let databaseTableName = "wait_sessions"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct DailySummary: Codable, FetchableRecord, PersistableRecord {
    var date: String // "YYYY-MM-DD"
    var totalWaitSeconds: Int
    var sessionCount: Int
    var longestSessionSeconds: Int
    var avgSessionSeconds: Int

    static let databaseTableName = "daily_summaries"
}

struct AppSetting: Codable, FetchableRecord, PersistableRecord {
    var key: String
    var value: String

    static let databaseTableName = "settings"
}

// MARK: - Hook Events

struct HookEvent: Codable {
    let event: String       // "prompt_start" or "response_end"
    let ts: Int             // unix timestamp
    let sessionId: String   // ties start/end pairs
    let pid: Int
    let pidStart: Int       // process start time for PID recycling detection

    enum CodingKeys: String, CodingKey {
        case event, ts
        case sessionId = "session_id"
        case pid
        case pidStart = "pid_start"
    }
}

// MARK: - Dashboard Data

struct DashboardData: Codable {
    let todayTotal: Int           // seconds
    let weekTotal: Int            // seconds
    let todayPrompts: Int
    let weekPrompts: Int
    let todayAvgWait: Int         // seconds
    let weekAvgWait: Int          // seconds
    let todayLongest: Int         // seconds
    let weekLongest: Int          // seconds
    let weeklyChart: [DayData]
    let recentSessions: [SessionData]
    let isActive: Bool
    let activeElapsed: Int        // seconds if active

    struct DayData: Codable {
        let label: String         // "Mon", "Tue", etc.
        let seconds: Int
        let sessionCount: Int
        let isToday: Bool
    }

    struct SessionData: Codable {
        let time: String          // "10:41 AM"
        let duration: String      // "8m 12s" or "0:47 (active)"
        let isLong: Bool          // > 15 min
        let isActive: Bool
    }
}

// MARK: - Settings Keys

enum SettingsKey: String {
    case grassThreshold = "grass_threshold"      // seconds, 0 = off
    case launchAtLogin = "launch_at_login"       // "true" / "false"
    case hooksInstalled = "hooks_installed"       // "true" / "false"
    case dashboardView = "dashboard_view"         // "today" / "week"
    case eventsFileOffset = "events_file_offset"  // UInt64 as string
    case appearance = "appearance"                // "system" / "light" / "dark"
    case accentColor = "accent_color"             // "orange" / "green"
}
