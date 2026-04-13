# Claude is Thinking?

**You know that feeling.** You hit enter on a prompt, Claude starts "thinking," and suddenly you're reorganizing your desk drawer, making coffee, questioning your career choices, and wondering if the AI is writing a novel in there.

This app measures exactly how much of your life you've donated to that blinking cursor.

![menu bar timer](https://img.shields.io/badge/menu_bar-timer-E8734A) ![macOS 13+](https://img.shields.io/badge/macOS-13%2B-333) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138) ![License MIT](https://img.shields.io/badge/license-MIT-blue)

## What It Does

A macOS menu bar app that tracks how long you spend waiting for Claude Code to respond. It won't make Claude faster. It will make you aware of how much time you spend in a long-distance relationship with an autocomplete.

- **Live timer** in the menu bar while Claude is thinking (the number goes up. that's the feature.)
- **Dashboard** with today's total, weekly chart, average wait, longest session, and recent activity
- **Share cards** — generate a PNG stat card and post your shame to Twitter, LinkedIn, or Reddit
- **Touch grass notifications** — gentle (and increasingly less gentle) reminders that the outside world exists
- **Break glass button** — for when Claude gets stuck and you need to end the suffering manually
- **Theme support** — Claude Orange or Terminal Green, because aesthetics matter when you're waiting

## Install

### Homebrew

```bash
brew tap Exorust/tap
brew install --cask claude-is-thinking
```

### Download

Grab the latest `.dmg` from [Releases](../../releases). Open it. Drag to Applications. Question nothing.

### Build from source

Requires Swift 5.9+ and macOS 13+. For people who enjoy waiting for builds while tracking how long they wait for AI.

```bash
git clone https://github.com/Exorust/claude-is-thinking.git
cd claude-is-thinking/TimeSpend
swift build
./scripts/bundle-app.sh
open "build/Claude is Thinking?.app"
```

## How It Works

Claude is Thinking? uses [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — no process monitoring, no accessibility permissions, no heuristics, no vibes.

On first launch, click **Enable Tracking** to install two hooks into `~/.claude/settings.json`:

- `UserPromptSubmit` — fires when you send a prompt (starts the clock on your existential wait)
- `Stop` — fires when Claude finishes responding (sweet relief)

Events are written to a local JSONL file, paired into sessions, and stored in SQLite. That's it. No cloud. No telemetry. Just you and your numbers.

**Your data never leaves your Mac.**

## Usage

1. Launch the app. A timer icon appears in your menu bar.
2. Click **Enable Tracking** on the first-run screen.
3. Use Claude Code normally. Watch the timer count up. Feel things.
4. Click the menu bar icon to see your dashboard.
5. Click **Share Your Stats** to generate a card and broadcast your patience to the world.

### Settings

- **Touch grass threshold** — when to start nudging you (2m, 3m, or 5m of cumulative wait time)
- **Accent color** — Claude Orange or Terminal Green
- **Theme** — System, Light, or Dark
- **Launch at login** — start automatically, because you'll forget otherwise
- **Disable tracking** — for when ignorance becomes bliss again

## Privacy

- **Never** reads your terminal content or Claude Code conversations
- Only records timestamps: when a prompt was sent and when a response finished
- All data is stored locally. Nothing is sent anywhere. Ever.
- Share cards are generated locally. Social sharing opens your browser with the image on your clipboard.

## Requirements

- macOS 13 (Ventura) or later
- Claude Code CLI installed
- A willingness to confront uncomfortable truths about your workflow

## License

MIT — do whatever you want with it. We're all just killing time anyway.
