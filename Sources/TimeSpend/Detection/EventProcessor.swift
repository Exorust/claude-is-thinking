import Foundation

final class EventProcessor {
    private let dataStore: DataStore
    private let onSessionUpdate: () -> Void
    private let onSessionEnd: ((Int) -> Void)?

    // File watching
    private var fileHandle: FileHandle?
    private var dispatchSource: DispatchSourceFileSystemObject?
    private var lastReadOffset: UInt64 = 0
    private var pendingBuffer: String = ""  // Holds incomplete trailing line

    // Serial queue for thread-safe access to openSessions and file reading
    private let processingQueue = DispatchQueue(label: "dev.timespend.eventprocessor")

    // Open sessions: session_id -> HookEvent (the prompt_start event)
    private var openSessions: [String: HookEvent] = [:]

    // Orphan detection
    private var orphanCheckPaused = false

    // Public: active session tracking for menu bar timer
    var activeSessionStartTime: Date? {
        // Read from processing queue for thread safety
        return processingQueue.sync {
            guard let oldest = openSessions.values.min(by: { $0.ts < $1.ts }) else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(oldest.ts))
        }
    }

    private var eventsFilePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.timespend/events.jsonl"
    }

    init(dataStore: DataStore, onSessionUpdate: @escaping () -> Void, onSessionEnd: ((Int) -> Void)? = nil) {
        self.dataStore = dataStore
        self.onSessionUpdate = onSessionUpdate
        self.onSessionEnd = onSessionEnd
    }

    deinit {
        stopWatching()
    }

    // MARK: - File Watching

    func startWatching() {
        let path = eventsFilePath

        // Ensure file exists
        if !FileManager.default.fileExists(atPath: path) {
            let dir = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: path, contents: nil)
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            print("[TimeSpend] Failed to open events file: \(path)")
            return
        }

        fileHandle = handle

        // Restore persisted offset, or seek to end if none saved
        if let savedOffset = dataStore.getSetting(.eventsFileOffset),
           let offset = UInt64(savedOffset) {
            // Validate offset is within file bounds
            handle.seekToEndOfFile()
            let fileSize = handle.offsetInFile
            if offset <= fileSize {
                handle.seek(toFileOffset: offset)
                lastReadOffset = offset
            } else {
                // File was truncated/rotated since last run, start from beginning
                handle.seek(toFileOffset: 0)
                lastReadOffset = 0
            }
        } else {
            // First launch: seek to end (don't replay historical events)
            handle.seekToEndOfFile()
            lastReadOffset = handle.offsetInFile
        }

        // Watch for writes using GCD dispatch source on serial queue
        let fd = handle.fileDescriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend],
            queue: processingQueue
        )

        source.setEventHandler { [weak self] in
            self?.readNewEvents()
        }

        source.setCancelHandler { [weak self] in
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
        }

        dispatchSource = source
        source.resume()
    }

    func stopWatching() {
        dispatchSource?.cancel()
        dispatchSource = nil
    }

    // MARK: - Event Processing

    /// Called on processingQueue (serial) — no concurrent access to openSessions or fileHandle
    private func readNewEvents() {
        guard let handle = fileHandle else { return }

        handle.seek(toFileOffset: lastReadOffset)
        let data = handle.readDataToEndOfFile()

        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

        // Prepend any incomplete line from previous read
        let fullText = pendingBuffer + text
        pendingBuffer = ""

        // Split into lines. If text doesn't end with newline, last element is incomplete.
        let lines = fullText.components(separatedBy: "\n")

        let hasTrailingNewline = fullText.hasSuffix("\n")
        let completeLines: ArraySlice<String>

        if hasTrailingNewline {
            completeLines = lines[...]
            // Advance offset to end of all data read
            lastReadOffset = handle.offsetInFile
        } else {
            // Last line is incomplete — hold it back
            completeLines = lines.dropLast()
            pendingBuffer = lines.last ?? ""
            // Advance offset only up to the last complete line
            let completedBytes = fullText.count - pendingBuffer.count
            lastReadOffset += UInt64(completedBytes)
        }

        let decoder = JSONDecoder()

        for line in completeLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard let lineData = trimmed.data(using: .utf8),
                  let event = try? decoder.decode(HookEvent.self, from: lineData) else {
                // Malformed line: skip without crashing
                continue
            }

            processEvent(event)
        }

        // Persist offset periodically
        persistOffset()
    }

    /// Called on processingQueue (serial)
    private func processEvent(_ event: HookEvent) {
        switch event.event {
        case "prompt_start":
            openSessions[event.sessionId] = event
            DispatchQueue.main.async { self.onSessionUpdate() }

        case "response_end":
            guard let startEvent = openSessions.removeValue(forKey: event.sessionId) else {
                // response_end with no matching prompt_start: skip
                return
            }

            let duration = event.ts - startEvent.ts
            guard duration > 0 else { return }

            let session = WaitSession(
                startTime: Date(timeIntervalSince1970: TimeInterval(startEvent.ts)),
                endTime: Date(timeIntervalSince1970: TimeInterval(event.ts)),
                durationSeconds: duration,
                aiTool: "claude_code",
                sessionId: event.sessionId
            )

            dataStore.saveSession(session)
            DispatchQueue.main.async {
                self.onSessionUpdate()
                self.onSessionEnd?(duration)
            }

        default:
            // Unknown event type: skip
            break
        }
    }

    private func persistOffset() {
        dataStore.setSetting(.eventsFileOffset, value: String(lastReadOffset))
    }

    // MARK: - Orphan Detection

    func checkOrphans() {
        processingQueue.async { [weak self] in
            self?.checkOrphansOnQueue()
        }
    }

    /// Called on processingQueue (serial)
    private func checkOrphansOnQueue() {
        guard !orphanCheckPaused else { return }

        let now = Date()
        var closedIds: [String] = []

        for (sessionId, event) in openSessions {
            // Check if PID is still alive
            let pidAlive = kill(Int32(event.pid), 0) == 0

            if !pidAlive {
                // PID is dead, close the session
                closedIds.append(sessionId)
                closeOrphanSession(event, endTs: Int(now.timeIntervalSince1970))
            } else {
                // PID alive — check if it was recycled (different process now using same PID)
                let currentPidStart = getProcessStartTime(pid: event.pid)
                if currentPidStart != 0 && event.pidStart != 0 && currentPidStart != event.pidStart {
                    // PID was recycled — different process
                    closedIds.append(sessionId)
                    closeOrphanSession(event, endTs: Int(now.timeIntervalSince1970))
                }
                // Otherwise: PID alive with same start time = genuine long session, keep it open
            }
        }

        for id in closedIds {
            openSessions.removeValue(forKey: id)
        }

        if !closedIds.isEmpty {
            DispatchQueue.main.async { self.onSessionUpdate() }
        }
    }

    private func closeOrphanSession(_ event: HookEvent, endTs: Int) {
        let duration = endTs - event.ts
        guard duration > 0 else { return }

        let session = WaitSession(
            startTime: Date(timeIntervalSince1970: TimeInterval(event.ts)),
            endTime: Date(timeIntervalSince1970: TimeInterval(endTs)),
            durationSeconds: duration,
            aiTool: "claude_code",
            sessionId: event.sessionId
        )

        dataStore.saveSession(session)
    }

    private func getProcessStartTime(pid: Int) -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "lstart=", "-p", "\(pid)"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                return 0
            }

            // Use fixed locale to avoid locale-dependent date parsing issues
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE MMM dd HH:mm:ss yyyy"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            if let date = formatter.date(from: output) {
                return Int(date.timeIntervalSince1970)
            }
        } catch {
            // Process not found or other error
        }

        return 0
    }

    func pauseOrphanDetection() {
        orphanCheckPaused = true
    }

    func resumeOrphanDetection() {
        orphanCheckPaused = false
    }

    // MARK: - Events File Maintenance

    func rotateEventsFileIfNeeded() {
        processingQueue.async { [weak self] in
            self?.rotateOnQueue()
        }
    }

    /// Called on processingQueue (serial)
    private func rotateOnQueue() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: eventsFilePath),
              let size = attrs[.size] as? UInt64 else { return }

        // Rotate at 1MB
        if size > 1_000_000 {
            stopWatching()
            // Rename old file instead of truncating (preserves data for debugging)
            let archivePath = eventsFilePath + ".old"
            try? FileManager.default.removeItem(atPath: archivePath)
            try? FileManager.default.moveItem(atPath: eventsFilePath, toPath: archivePath)
            // Create fresh file
            FileManager.default.createFile(atPath: eventsFilePath, contents: nil)
            lastReadOffset = 0
            pendingBuffer = ""
            persistOffset()
            startWatching()
        }
    }
}
