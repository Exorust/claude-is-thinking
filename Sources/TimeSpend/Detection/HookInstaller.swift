import Foundation

final class HookInstaller {
    private let claudeSettingsPath: String
    private let hookScriptPath: String
    private let eventsFilePath: String

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        claudeSettingsPath = "\(home)/.claude/settings.json"

        // Use ~/.timespend/ for hook script and events file.
        // No spaces in the path. Claude Code splits unquoted command strings on spaces,
        // so ~/Library/Application Support/... breaks silently.
        let timeSpendDir = "\(home)/.timespend"
        hookScriptPath = "\(timeSpendDir)/timespend-hook.sh"
        eventsFilePath = "\(timeSpendDir)/events.jsonl"
    }

    var isInstalled: Bool {
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        // Check for our hooks in UserPromptSubmit or Stop (current format)
        // Also check PreToolUse/PostResponse (old format, for backwards compat)
        let hookNames = ["UserPromptSubmit", "Stop", "PreToolUse", "PostResponse"]
        for name in hookNames {
            if let entries = hooks[name] as? [[String: Any]] {
                let hasOurs = entries.contains { entry in
                    // New format: hooks array inside entry
                    if let innerHooks = entry["hooks"] as? [[String: Any]] {
                        return innerHooks.contains { ($0["command"] as? String)?.contains("timespend-hook.sh") == true }
                    }
                    // Old format: command directly on entry
                    return (entry["command"] as? String)?.contains("timespend-hook.sh") == true
                }
                if hasOurs { return true }
            }
        }

        return false
    }

    func install() throws {
        try ensureDirectories()
        try installHookScript()
        try mergeClaudeSettings()
    }

    func uninstall() throws {
        try removeFromClaudeSettings()
    }

    // MARK: - Private

    private func ensureDirectories() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let timeSpendDir = "\(home)/.timespend"
        try FileManager.default.createDirectory(atPath: timeSpendDir, withIntermediateDirectories: true)

        // Ensure events file exists
        if !FileManager.default.fileExists(atPath: eventsFilePath) {
            FileManager.default.createFile(atPath: eventsFilePath, contents: nil)
        }

        // Ensure .claude directory exists
        let claudeDir = "\(home)/.claude"
        try FileManager.default.createDirectory(atPath: claudeDir, withIntermediateDirectories: true)
    }

    private func installHookScript() throws {
        // Copy hook script from bundle to Application Support
        if let bundledHookURL = Bundle.module.url(forResource: "timespend-hook", withExtension: "sh", subdirectory: "Resources/Hook") {
            let dest = URL(fileURLWithPath: hookScriptPath)
            if FileManager.default.fileExists(atPath: hookScriptPath) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: bundledHookURL, to: dest)
        } else {
            // Write the hook script directly if bundle resource not found
            try writeHookScript()
        }

        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptPath)
    }

    private func writeHookScript() throws {
        let script = """
        #!/bin/bash
        # Claude is Thinking? hook script - writes events to JSONL for tracking Claude Code wait time
        # Called by Claude Code hooks. Arg 1: event type (prompt_start | response_end)

        EVENTS_DIR="$HOME/.timespend"
        EVENTS_FILE="$EVENTS_DIR/events.jsonl"
        LOCK_FILE="$EVENTS_DIR/events.lock"
        EVENT_TYPE="${1:-unknown}"
        TS=$(date +%s)

        STDIN_JSON=$(cat)
        SESSION_ID=""
        if [ -n "$STDIN_JSON" ]; then
            SESSION_ID=$(echo "$STDIN_JSON" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//;s/"$//')
        fi
        if [ -z "$SESSION_ID" ]; then
            PPID_START=$(LANG=C ps -o lstart= -p $PPID 2>/dev/null | tr -s ' ')
            if [ -n "$PPID_START" ]; then
                SESSION_ID="ppid-${PPID}-$(echo "$PPID_START" | cksum | cut -d' ' -f1)"
            else
                SESSION_ID="pid-$$-$TS"
            fi
        fi

        PID_START=$(LANG=C ps -o lstart= -p $PPID 2>/dev/null | xargs -I{} date -j -f "%c" "{}" "+%s" 2>/dev/null || echo "0")

        mkdir -p "$EVENTS_DIR"

        (
            flock -x 200 2>/dev/null || true
            printf '{\"event\":\"%s\",\"ts\":%s,\"session_id\":\"%s\",\"pid\":%s,\"pid_start\":%s}\\n' \\
                "$EVENT_TYPE" "$TS" "$SESSION_ID" "$PPID" "$PID_START" >> "$EVENTS_FILE"
        ) 200>"$LOCK_FILE"
        """
        try script.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)
    }

    private func mergeClaudeSettings() throws {
        var settings: [String: Any] = [:]

        // Read existing settings if present
        if let data = FileManager.default.contents(atPath: claudeSettingsPath) {
            if let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            }
        }

        // Back up existing settings
        let backupPath = claudeSettingsPath + ".bak"
        if FileManager.default.fileExists(atPath: claudeSettingsPath) {
            if FileManager.default.fileExists(atPath: backupPath) {
                try FileManager.default.removeItem(atPath: backupPath)
            }
            try FileManager.default.copyItem(atPath: claudeSettingsPath, toPath: backupPath)
        }

        // Merge hooks using correct Claude Code hook format:
        // hooks.EventName = [{ matcher: "", hooks: [{ type: "command", command: "...", timeout: 5 }] }]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let hookEntry: ([String: Any]) -> [String: Any] = { inner in
            return [
                "matcher": "",
                "hooks": [inner]
            ]
        }

        // UserPromptSubmit -> prompt_start (fires once when user submits a prompt)
        var promptSubmit = hooks["UserPromptSubmit"] as? [[String: Any]] ?? []
        let hasPromptHook = promptSubmit.contains { entry in
            if let innerHooks = entry["hooks"] as? [[String: Any]] {
                return innerHooks.contains { ($0["command"] as? String)?.contains("timespend-hook.sh") == true }
            }
            return (entry["command"] as? String)?.contains("timespend-hook.sh") == true
        }
        if !hasPromptHook {
            promptSubmit.append(hookEntry([
                "type": "command",
                "command": "\(hookScriptPath) prompt_start",
                "timeout": 5
            ]))
        }
        hooks["UserPromptSubmit"] = promptSubmit

        // Stop -> response_end (fires once when Claude finishes responding)
        var stopHooks = hooks["Stop"] as? [[String: Any]] ?? []
        let hasStopHook = stopHooks.contains { entry in
            if let innerHooks = entry["hooks"] as? [[String: Any]] {
                return innerHooks.contains { ($0["command"] as? String)?.contains("timespend-hook.sh") == true }
            }
            return (entry["command"] as? String)?.contains("timespend-hook.sh") == true
        }
        if !hasStopHook {
            stopHooks.append(hookEntry([
                "type": "command",
                "command": "\(hookScriptPath) response_end",
                "timeout": 5
            ]))
        }
        hooks["Stop"] = stopHooks

        // Clean up old wrong hook names if present
        if var old = hooks["PreToolUse"] as? [[String: Any]] {
            old.removeAll { entry in
                if let innerHooks = entry["hooks"] as? [[String: Any]] {
                    return innerHooks.contains { ($0["command"] as? String)?.contains("timespend-hook.sh") == true }
                }
                return (entry["command"] as? String)?.contains("timespend-hook.sh") == true
            }
            hooks["PreToolUse"] = old.isEmpty ? nil : old
        }
        if var old = hooks["PostResponse"] as? [[String: Any]] {
            old.removeAll { entry in
                if let innerHooks = entry["hooks"] as? [[String: Any]] {
                    return innerHooks.contains { ($0["command"] as? String)?.contains("timespend-hook.sh") == true }
                }
                return (entry["command"] as? String)?.contains("timespend-hook.sh") == true
            }
            hooks["PostResponse"] = old.isEmpty ? nil : old
        }

        settings["hooks"] = hooks

        // Atomic write: temp file + rename
        try atomicWriteJSON(settings, to: claudeSettingsPath)
    }

    private func removeFromClaudeSettings() throws {
        guard let data = FileManager.default.contents(atPath: claudeSettingsPath),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else {
            return
        }

        // Remove our hooks from all possible event names
        let hookNames = ["UserPromptSubmit", "Stop", "PreToolUse", "PostResponse"]
        for name in hookNames {
            if var entries = hooks[name] as? [[String: Any]] {
                entries.removeAll { entry in
                    if let innerHooks = entry["hooks"] as? [[String: Any]] {
                        return innerHooks.contains { ($0["command"] as? String)?.contains("timespend-hook.sh") == true }
                    }
                    return (entry["command"] as? String)?.contains("timespend-hook.sh") == true
                }
                hooks[name] = entries.isEmpty ? nil : entries
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try atomicWriteJSON(settings, to: claudeSettingsPath)
    }

    /// Write JSON to file atomically: write temp file, fsync, rename.
    /// rename() is atomic on macOS APFS/HFS+ and replaces the destination.
    private func atomicWriteJSON(_ object: [String: Any], to path: String) throws {
        let jsonData = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        let tmpPath = path + ".tmp"
        let tmpURL = URL(fileURLWithPath: tmpPath)

        try jsonData.write(to: tmpURL)

        // fsync to ensure data is on disk before rename
        if let fd = fopen(tmpPath, "r") {
            fsync(fileno(fd))
            fclose(fd)
        }

        // Atomic rename (replaces destination if it exists)
        if rename(tmpPath, path) != 0 {
            // Fallback: remove tmp and write directly
            try? FileManager.default.removeItem(atPath: tmpPath)
            try jsonData.write(to: URL(fileURLWithPath: path))
        }
    }
}
