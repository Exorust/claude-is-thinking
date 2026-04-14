<div align="center">

# Claude Still Thinking?

**You know that feeling.** You hit enter on a prompt, Claude starts "thinking,"<br>and suddenly you're reorganizing your desk drawer, making coffee, and wondering<br>if the AI is writing a novel in there.

*This app measures exactly how much of your life you've donated to that blinking cursor.*

![menu bar timer](https://img.shields.io/badge/menu_bar-timer-E8734A) ![macOS 13+](https://img.shields.io/badge/macOS-13%2B-333) ![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138) ![License MIT](https://img.shields.io/badge/license-MIT-blue)

<br>

<img height="500" alt="Dashboard" src="https://github.com/user-attachments/assets/81655fdf-b222-4365-b9b7-718135b889a4" />&nbsp;&nbsp;&nbsp;&nbsp;<img height="500" alt="Share Card" src="https://github.com/user-attachments/assets/8e8428d8-ef87-4975-bd72-6bcc9017b15d" />

</div>

## Features

- **Live timer** in the menu bar while Claude is thinking (the number goes up. that's the feature.)
- **Dashboard** with today's total, weekly chart, average wait, longest session, and recent activity
- **Share cards** — generate a PNG stat card and post your shame to Twitter, LinkedIn, or Reddit
- **Touch grass notifications** — gentle (and increasingly less gentle) reminders that the outside world exists
- **Break glass button** — for when Claude gets stuck and you need to end the suffering manually
- **Theme support** — Claude Orange or Terminal Green, because aesthetics matter when you're waiting

## Install

Requires macOS 13+ and Swift 5.9+. One command, about a minute.

```bash
git clone https://github.com/Exorust/claude-still-thinking.git && cd claude-still-thinking/TimeSpend && ./scripts/install.sh
```

We build from source because Apple's Gatekeeper blocks any app that isn't signed with a $99/year developer certificate — even if the code is fully open source and you can read every line. Building locally sidesteps all of that. Thanks, Apple.

<details>
<summary><b>Alternative installs</b> (Homebrew / DMG)</summary>

**Homebrew:**
```bash
brew tap Exorust/tap
brew install --cask claude-still-thinking
```

**DMG:** Grab the latest `.dmg` from [Releases](../../releases). If macOS says it's "damaged" (see above re: Apple), right-click the app → Open → click "Open", or run:
```bash
xattr -cr "/Applications/Claude Still Thinking?.app"
```
</details>

## How It Works

Claude Still Thinking? uses [Claude Code hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — no process monitoring, no accessibility permissions, no heuristics, no vibes.

On first launch, click **Enable Tracking** to install two hooks into `~/.claude/settings.json`:

- **`UserPromptSubmit`** — fires when you send a prompt (starts the clock)
- **`Stop`** — fires when Claude finishes responding (sweet relief)

Events are written to a local JSONL file, paired into sessions, and stored in SQLite. No cloud. No telemetry. Just you and your numbers.

## Usage

1. Launch the app. A timer icon appears in your menu bar.
2. Click **Enable Tracking** on the first-run screen.
3. Use Claude Code normally. Watch the timer count up. Feel things.
4. Click the menu bar icon to see your dashboard.
5. Click **Share Your Stats** to generate a card and broadcast your patience to the world.

### Settings

- **Touch grass threshold** — when to start nudging you (2m, 3m, or 5m)
- **Accent color** — Claude Orange or Terminal Green
- **Theme** — System, Light, or Dark
- **Launch at login** — because you'll forget otherwise
- **Disable tracking** — for when ignorance becomes bliss

## Privacy

Your data never leaves your Mac. The app never reads your terminal content or Claude Code conversations — it only records timestamps. Share cards are generated locally. Nothing is sent anywhere. Ever.

## License

MIT — do whatever you want with it. We're all just killing time anyway.
