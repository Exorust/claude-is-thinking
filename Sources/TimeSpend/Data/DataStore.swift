import Foundation
import GRDB

final class DataStore {
    private var dbPool: DatabasePool?

    private var dbPath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TimeSpend")
        return dir.appendingPathComponent("data.db").path
    }

    func initialize() {
        do {
            let dir = (dbPath as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            var config = Configuration()
            config.prepareDatabase { db in
                db.trace { print("[SQL] \($0)") }
            }

            dbPool = try DatabasePool(path: dbPath, configuration: config)
            try migrate()
            pruneOldData()
            rebuildDailySummaries()
        } catch {
            print("[TimeSpend] Database init failed: \(error)")
        }
    }

    // MARK: - Migration

    private func migrate() throws {
        guard let db = dbPool else { return }

        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "wait_sessions") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("startTime", .datetime).notNull()
                t.column("endTime", .datetime)
                t.column("durationSeconds", .integer)
                t.column("aiTool", .text).notNull().defaults(to: "claude_code")
                t.column("sessionId", .text)
            }

            try db.create(table: "daily_summaries") { t in
                t.primaryKey("date", .text)
                t.column("totalWaitSeconds", .integer).notNull().defaults(to: 0)
                t.column("sessionCount", .integer).notNull().defaults(to: 0)
                t.column("longestSessionSeconds", .integer).notNull().defaults(to: 0)
                t.column("avgSessionSeconds", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            // Indexes
            try db.create(index: "idx_sessions_start", on: "wait_sessions", columns: ["startTime"])
            try db.create(index: "idx_sessions_aid", on: "wait_sessions", columns: ["aiTool"])
        }

        try migrator.migrate(db)
    }

    // MARK: - Sessions

    func saveSession(_ session: WaitSession) {
        guard let db = dbPool else { return }
        do {
            try db.write { db in
                var s = session
                try s.insert(db)

                // Incrementally update daily summary
                if let endTime = session.endTime {
                    let dateStr = Self.dateString(from: endTime)
                    try updateDailySummary(db: db, date: dateStr)
                }
            }
        } catch {
            print("[TimeSpend] Save session failed: \(error)")
        }
    }

    // MARK: - Dashboard Queries

    func getDashboardData(activeSessionStart: Date?) -> DashboardData {
        guard let db = dbPool else {
            return emptyDashboard()
        }

        do {
            return try db.read { db in
                let now = Date()
                let calendar = Calendar.current
                let todayStart = calendar.startOfDay(for: now)
                let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!

                // Today's stats
                let todaySessions = try WaitSession
                    .filter(Column("startTime") >= todayStart)
                    .fetchAll(db)

                let todayTotal = todaySessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
                let todayLongest = todaySessions.map { $0.durationSeconds ?? 0 }.max() ?? 0
                let todayAvg = todaySessions.isEmpty ? 0 : todayTotal / todaySessions.count

                // Week stats
                let weekSessions = try WaitSession
                    .filter(Column("startTime") >= weekStart)
                    .fetchAll(db)

                let weekTotal = weekSessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
                let weekLongest = weekSessions.map { $0.durationSeconds ?? 0 }.max() ?? 0
                let weekAvg = weekSessions.isEmpty ? 0 : weekTotal / weekSessions.count

                // Weekly chart data (7 days)
                var chartData: [DashboardData.DayData] = []
                let dayFormatter = DateFormatter()
                dayFormatter.dateFormat = "EEE"

                for i in (0..<7).reversed() {
                    let date = calendar.date(byAdding: .day, value: -i, to: now)!
                    let dayStart = calendar.startOfDay(for: date)
                    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

                    let daySessions = try WaitSession
                        .filter(Column("startTime") >= dayStart && Column("startTime") < dayEnd)
                        .fetchAll(db)

                    let dayTotal = daySessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
                    let isToday = calendar.isDateInToday(date)

                    chartData.append(DashboardData.DayData(
                        label: isToday ? "Today" : dayFormatter.string(from: date),
                        seconds: dayTotal,
                        sessionCount: daySessions.count,
                        isToday: isToday
                    ))
                }

                // Recent sessions (last 5)
                let recentSessions = try WaitSession
                    .order(Column("startTime").desc)
                    .limit(5)
                    .fetchAll(db)

                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"

                var sessionData: [DashboardData.SessionData] = recentSessions.map { session in
                    let timeStr = timeFormatter.string(from: session.startTime)
                    let duration = session.durationSeconds ?? 0
                    let durationStr = Self.formatDuration(duration)
                    return DashboardData.SessionData(
                        time: timeStr,
                        duration: durationStr,
                        isLong: duration > 900,
                        isActive: false
                    )
                }

                // Prepend active session if any
                let isActive = activeSessionStart != nil
                var activeElapsed = 0
                if let start = activeSessionStart {
                    activeElapsed = Int(now.timeIntervalSince(start))
                    let timeStr = timeFormatter.string(from: start)
                    sessionData.insert(DashboardData.SessionData(
                        time: timeStr,
                        duration: "\(Self.formatDuration(activeElapsed)) (active)",
                        isLong: false,
                        isActive: true
                    ), at: 0)
                    if sessionData.count > 5 {
                        sessionData.removeLast()
                    }
                }

                return DashboardData(
                    todayTotal: todayTotal + (isActive ? activeElapsed : 0),
                    weekTotal: weekTotal + (isActive ? activeElapsed : 0),
                    todayPrompts: todaySessions.count + (isActive ? 1 : 0),
                    weekPrompts: weekSessions.count + (isActive ? 1 : 0),
                    todayAvgWait: todayAvg,
                    weekAvgWait: weekAvg,
                    todayLongest: max(todayLongest, isActive ? activeElapsed : 0),
                    weekLongest: max(weekLongest, isActive ? activeElapsed : 0),
                    weeklyChart: chartData,
                    recentSessions: sessionData,
                    isActive: isActive,
                    activeElapsed: activeElapsed
                )
            }
        } catch {
            print("[TimeSpend] Dashboard query failed: \(error)")
            return emptyDashboard()
        }
    }

    func getTodayTotalSeconds() -> Int {
        guard let db = dbPool else { return 0 }
        do {
            return try db.read { db in
                let todayStart = Calendar.current.startOfDay(for: Date())
                let total = try WaitSession
                    .filter(Column("startTime") >= todayStart)
                    .select(sum(Column("durationSeconds")))
                    .fetchOne(db) ?? 0
                return total
            }
        } catch {
            return 0
        }
    }

    // MARK: - Settings

    func getSetting(_ key: SettingsKey) -> String? {
        guard let db = dbPool else { return nil }
        return try? db.read { db in
            try AppSetting.filter(Column("key") == key.rawValue).fetchOne(db)?.value
        }
    }

    func setSetting(_ key: SettingsKey, value: String) {
        guard let db = dbPool else { return }
        try? db.write { db in
            try AppSetting(key: key.rawValue, value: value).save(db)
        }
    }

    // MARK: - Maintenance

    private func pruneOldData() {
        guard let db = dbPool else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date())!
        try? db.write { db in
            try WaitSession.filter(Column("startTime") < cutoff).deleteAll(db)
            let cutoffStr = Self.dateString(from: cutoff)
            try DailySummary.filter(Column("date") < cutoffStr).deleteAll(db)
        }
    }

    private func rebuildDailySummaries() {
        guard let db = dbPool else { return }
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!

        try? db.write { db in
            // Delete and rebuild last 30 days
            let cutoffStr = Self.dateString(from: thirtyDaysAgo)
            try DailySummary.filter(Column("date") >= cutoffStr).deleteAll(db)

            let sessions = try WaitSession
                .filter(Column("startTime") >= thirtyDaysAgo)
                .fetchAll(db)

            // Group by date
            var grouped: [String: [WaitSession]] = [:]
            for session in sessions {
                let dateStr = Self.dateString(from: session.startTime)
                grouped[dateStr, default: []].append(session)
            }

            for (dateStr, _) in grouped {
                try updateDailySummary(db: db, date: dateStr)
            }
        }
    }

    private func updateDailySummary(db: Database, date: String) throws {
        let dayStart = Self.dateFromString(date)!
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!

        let sessions = try WaitSession
            .filter(Column("startTime") >= dayStart && Column("startTime") < dayEnd)
            .fetchAll(db)

        let totalSeconds = sessions.reduce(0) { $0 + ($1.durationSeconds ?? 0) }
        let longest = sessions.map { $0.durationSeconds ?? 0 }.max() ?? 0
        let avg = sessions.isEmpty ? 0 : totalSeconds / sessions.count

        let summary = DailySummary(
            date: date,
            totalWaitSeconds: totalSeconds,
            sessionCount: sessions.count,
            longestSessionSeconds: longest,
            avgSessionSeconds: avg
        )
        try summary.save(db)
    }

    // MARK: - Helpers

    static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let m = seconds / 60
            let s = seconds % 60
            return "\(m)m \(s)s"
        } else {
            let h = seconds / 3600
            let m = (seconds % 3600) / 60
            return "\(h)h \(m)m"
        }
    }

    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func dateFromString(_ str: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: str)
    }

    private func emptyDashboard() -> DashboardData {
        DashboardData(
            todayTotal: 0, weekTotal: 0,
            todayPrompts: 0, weekPrompts: 0,
            todayAvgWait: 0, weekAvgWait: 0,
            todayLongest: 0, weekLongest: 0,
            weeklyChart: [], recentSessions: [],
            isActive: false, activeElapsed: 0
        )
    }
}
