<p align="center"><img src="docs/icon.png" width="128" alt="Dawn icon: a striped red sun rising over a cream horizon"></p>

<h1 align="center">Dawn</h1>

<p align="center">Starts your Claude window before you sit down. A small app for the macOS menu bar.</p>

<p align="center">
  <a href="https://github.com/Kungie/dawn/releases/latest"><img src="https://img.shields.io/github/v/release/Kungie/dawn?label=release&color=e2231a&labelColor=2a1b19&style=flat-square" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-f3e9d6?logo=apple&logoColor=f3e9d6&labelColor=2a1b19&style=flat-square&color=050303" alt="macOS 13 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-e2231a?labelColor=2a1b19&style=flat-square" alt="Licence: AGPL-3.0"></a>
</p>

<p align="center"><img src="docs/readme.png" width="540" alt="Dawn in a Mac menu bar: a striped sun with 1:44 next to it, highlighted, and Dawn's panel hanging under it with a red pixel notch: 1:44 left in the window, resets at 11:00, started by Dawn's ping; the morning ping at 06:30 Mon–Fri; 9.5 hours started early this week."></p>

<p align="center"><a href="https://github.com/Kungie/dawn/releases/latest/download/Dawn.zip"><b>Download for Mac</b></a> · by <a href="https://github.com/Kungie">Vektor Labs</a></p>

---

Claude's usage window is five hours long and starts with your first message. Claude.ai, the desktop app and Claude Code all draw from the same pool. Start at nine, work properly, and you can be out of Claude by half past eleven with nothing to do until two.

Dawn moves the clock. At 06:30, or whenever you set it, it wakes your sleeping Mac for a minute and sends one tiny message through the official Claude Code command line tool, signed in with your own account. Your window starts while you're still asleep, so by the time you sit down at nine the next fresh one is two and a half hours away instead of five.

It doesn't give you more Claude. Your weekly limit stays exactly where Anthropic put it, and the ping is one short message to the smallest model. Dawn only moves the timing.

## What's in the menu bar

A small striped sun, and while a window is running, the time left in it. Click it and you get Dawn's screen: the countdown, when the window resets, and who started it. When no window is running it shows when the next ping goes out.

If you add the Claude Code hook (one click in Settings), the sun gets a ringed dot whenever Claude Code is waiting for you, and the panel shows what it's asking. When Claude finishes a task, the sun gets a solid dot and Dawn plays a short space ping. The sound has its own switch in Settings. Click either alert and Dawn takes you to that session: the right tab in Terminal or iTerm2, or the app it runs in (an editor, the Claude desktop app), on whichever Desktop it is. Nothing gets moved to the Desktop you're on.

<p align="center"><img src="docs/panel-asking.png" width="340" alt="The panel with a red banner: Claude Code is waiting, Claude needs your permission to use Bash."> &nbsp; <img src="docs/panel-settings.png" width="340" alt="Dawn's settings: morning ping time and days, setup checks for Claude Code, the scheduled wake and the hook, the space ping switch, open at login, and the last four pings."></p>

Everything you set once lives behind **Settings** at the bottom of the panel: the morning ping time and days, the setup checks, the sound and open at login. The panel itself stays a clock.

## Install

Dawn needs macOS 13 or later, on Apple silicon or Intel, and [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) installed and signed in once.

**Download.** Get `Dawn.zip` from the [latest release](https://github.com/Kungie/dawn/releases/latest), unzip it and move `Dawn.app` to Applications. Dawn isn't notarized by Apple yet, so the first time macOS will say it can't check it: open System Settings › Privacy & Security, scroll down and click **Open Anyway**. After that it opens normally.

**Or build it yourself** with the Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/Kungie/dawn.git
```

```bash
cd dawn && make install
```

That builds `Dawn.app`, copies it to `/Applications` and opens it. Then open **Settings** in the panel, switch on the morning ping, pick a time and days, and click **Set up** next to *Wake the Mac*. macOS asks for your administrator password once, because scheduling a wake is a system setting.

`make app` builds a universal `build/Dawn.app` and `build/Dawn.zip`, signed ad hoc.

## How it works, honestly

**The ping.** Dawn runs `claude -p "ping" --model haiku` in its own folder (`~/Library/Application Support/Dawn/Dawn-ping`). That's the official CLI, using the login it already has. Dawn never reads, copies or stores your Claude credentials and never uses an API key. If a window is already running at ping time, Dawn skips the ping, since it would change nothing.

**The wake.** Dawn sets a repeating wake one minute before ping time with macOS's own `pmset`. macOS keeps only one repeating wake, so this replaces any other one you had; Dawn shows the current schedule in Setup. While the ping runs, Dawn holds a power assertion so the Mac stays awake.

**Things that can go wrong.** The Mac has to be plugged in and asleep, not shut down. On battery, macOS may skip a scheduled wake. With the lid closed, macOS sometimes drops back to sleep quickly; it's most reliable with the lid open. Check **Recent** in the panel for the first few mornings, or run `pmset -g log | grep -i wake` in Terminal.

**The countdown is an estimate.** Dawn reads the timestamps of Claude's replies in Claude Code's local logs (`~/.claude/projects`), the same logs community tools use, and rounds the window start down to the hour. It only sees Claude Code: the terminal, IDEs and the desktop app's Code tab. Chats in Claude.ai or the desktop app's chat don't appear there, so if you start your day in one of those, click **I started in Claude.ai**. Anthropic's own usage page is the source of truth.

**The hook.** *Add* writes two entries in `~/.claude/settings.json`, one under `hooks.Notification` and one under `hooks.Stop`, keeps everything else, and saves a backup next to it the first time (`settings.json.dawn-backup`). Claude Code then runs `Dawn hook` when it's waiting for you and `Dawn hook stop` when it has finished; both pass a short message to the app and exit. The message includes which app the session runs in and its terminal device, found by walking up the process tree, so a click on the alert can go there. To select the exact Terminal or iTerm2 tab, macOS asks once whether Dawn may control that app. For editors, Dawn can also raise the window of that project if you give it Accessibility access; without it, the app comes to the front. *Remove* takes the entries out again. The space ping is made in code when it plays; no sound files ship with the app.

**Privacy.** Nothing leaves your Mac except the ping itself, which goes to Anthropic through Claude Code like any other message you send. Dawn has no telemetry, no account and no server.

## Is it allowed?

Dawn only drives the official Claude Code CLI on your own Mac, with your own account, once a morning, the same as typing a message yourself at 06:30. Anthropic sets the limits and the rules and can change them. Read their terms and decide for yourself. If scheduled pings ever stop making sense, Dawn is still a decent window clock.

Dawn is an independent project by Vektor Labs and is not affiliated with, endorsed by or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic, PBC.

## For tinkerers

Dawn is one Swift package with no dependencies. `Sources/Dawn` has the menu bar app (`DawnApp`, `PanelView`), the window estimate (`UsageLog`), the ping (`PingRunner`), the wake, hook and login item (`SystemSetup`), the space ping (`SpacePing`) and the Ident theme (`Theme`). The same binary has a few command line modes:

```bash
/Applications/Dawn.app/Contents/MacOS/Dawn status
```

`status` prints what Dawn sees: where `claude` is, the scheduled wake, the hook, and the current window estimate. `hook` and `hook stop` are what Claude Code calls. `ping-sound` plays the finish sound, and `session` prints which app and terminal the hook would report from where you run it. `snapshot <folder>` renders the panel with demo data (that's where the pictures above come from), and `icon <file>` draws the app icon.

`make app` builds `build/Dawn.app`, `make run` opens it, `make snapshots` refreshes the pictures in `docs/`.

## Licence

Dawn is free software under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0): you can use, study, change and share it, and if you share a changed version, you share its source under the same licence. See [NOTICE](NOTICE). The bundled fonts (Archivo, VT323, Space Grotesk, Space Mono) are under the SIL Open Font License 1.1; their licence files sit next to them in `Resources/Fonts`.
