#!/bin/bash
# Claude is Thinking? hook script - writes events to JSONL for tracking Claude Code wait time
# Called by Claude Code hooks. Arg 1: event type (prompt_start | response_end)
# Claude Code passes JSON context on stdin including session_id

EVENTS_DIR="$HOME/.timespend"
EVENTS_FILE="$EVENTS_DIR/events.jsonl"
LOCK_FILE="$EVENTS_DIR/events.lock"
EVENT_TYPE="${1:-unknown}"
TS=$(date +%s)

# Read stdin (Claude Code passes JSON context)
STDIN_JSON=$(cat)

# Extract session_id from stdin JSON without python3 dependency.
# Claude Code guarantees: {"session_id": "...", ...}
# Try multiple extraction methods in order of reliability.
SESSION_ID=""

# Method 1: grep + sed (works on all macOS/Linux)
if [ -z "$SESSION_ID" ] && [ -n "$STDIN_JSON" ]; then
    SESSION_ID=$(echo "$STDIN_JSON" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"session_id"[[:space:]]*:[[:space:]]*"//;s/"$//')
fi

# Method 2: python3 (fallback)
if [ -z "$SESSION_ID" ] && [ -n "$STDIN_JSON" ] && command -v python3 &>/dev/null; then
    SESSION_ID=$(echo "$STDIN_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session_id',''))" 2>/dev/null)
fi

# Method 3: use PPID + process start time as stable session identifier
# (PPID is the Claude Code process, stable across hook calls within one session)
if [ -z "$SESSION_ID" ]; then
    PPID_START=$(LANG=C ps -o lstart= -p $PPID 2>/dev/null | tr -s ' ')
    if [ -n "$PPID_START" ]; then
        # Create a deterministic ID from PPID + its start time
        SESSION_ID="ppid-${PPID}-$(echo "$PPID_START" | cksum | cut -d' ' -f1)"
    else
        SESSION_ID="pid-$$-$TS"
    fi
    # Log fallback for debugging
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] session_id extraction failed, using fallback: $SESSION_ID (event: $EVENT_TYPE)" >> "$EVENTS_DIR/debug.log" 2>/dev/null
fi

# Get parent process start time for PID recycling detection
PID_START=$(LANG=C ps -o lstart= -p $PPID 2>/dev/null | xargs -I{} date -j -f "%c" "{}" "+%s" 2>/dev/null || echo "0")

# Ensure directory exists
mkdir -p "$EVENTS_DIR"

# Atomic append with file locking
(
    flock -x 200 2>/dev/null || true
    printf '{"event":"%s","ts":%s,"session_id":"%s","pid":%s,"pid_start":%s}\n' \
        "$EVENT_TYPE" "$TS" "$SESSION_ID" "$PPID" "$PID_START" >> "$EVENTS_FILE"
) 200>"$LOCK_FILE"
