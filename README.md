<h1 align="center">
  <img src="docs/icon.png" width="104" alt="Dawn icon: a striped red sun rising over a cream horizon"><br>
  Dawn
</h1>

<p align="center">Starts your Claude window before you sit down and refreshes it automatically. A small app for the macOS menu bar.</p>

<p align="center">
  <a href="https://github.com/Kungie/dawn/releases/latest"><img src="https://img.shields.io/github/v/release/Kungie/dawn?label=release&color=e2231a&labelColor=2a1b19&style=flat-square" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-f3e9d6?logo=apple&logoColor=f3e9d6&labelColor=2a1b19&style=flat-square&color=050303" alt="macOS 13 or later">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-e2231a?labelColor=2a1b19&style=flat-square" alt="Licence: AGPL-3.0"></a>
</p>

<p align="center"><img src="docs/readme.png" width="540" alt="Dawn in a Mac menu bar: a striped sun with 1:44 next to it, highlighted, and Dawn's panel hanging under it with a red pixel notch: 1:44 left in the window, resets at 11:00, started by Dawn's ping; the morning ping at 06:30 Mon–Fri; 9.5 hours started early this week."></p>

<p align="center"><a href="https://github.com/Kungie/dawn/releases/latest/download/Dawn.dmg"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2FKungie%2Fdawn%2Fbadges%2Fdownloads.json" alt="Download for Mac (total downloads)"></a></p>

---

Claude's usage window is five hours long and starts with your first message. Claude.ai, the desktop app and Claude Code all draw from the same pool. Start at nine, work properly, and you can be out of Claude by half past eleven with nothing to do until two.

Dawn moves the clock. At 06:30, or whenever you set it, it wakes your sleeping Mac for a minute and sends one tiny message through the official Claude Code command line tool, signed in with your own account. Your window starts while you're still asleep, so by the time you sit down at nine the next fresh one is two and a half hours away instead of five.

With **Auto refresh** on, Dawn keeps going after that: a minute after each window resets it sends the next ping, using Claude's own reset time when it has it, and 5 h 1 min after the last ping when it doesn't (06:30, 11:31, 16:32, 21:33). It stops before a ping whose window would still be running at the next morning ping, and it needs the Mac to be awake at those times.

It doesn't give you more Claude. Your weekly limit stays exactly where Anthropic put it, and the ping is one short message to the smallest model. Dawn only moves the timing.

## What's in the menu bar

A small striped sun. In Settings you can put the time left in the window or the share used next to it (*Menu bar shows*: Time, Usage or None); by default it's just the sun. Click it and you get Dawn's screen: the countdown, when the window resets, and who started it. When no window is running it shows when the next ping goes out.

If you add the Claude Code hook (one click in Settings), the sun gets a ringed dot whenever Claude Code is waiting for you, and the panel shows what it's asking. When Claude finishes a task, the sun gets a solid dot and Dawn plays a short space ping; Auto refresh plays it too when it starts a new window. The sound has its own switch in Settings. Click either alert and Dawn takes you to that session: the right tab in Terminal or iTerm2, or the app it runs in (an editor, the Claude desktop app), on whichever Desktop it is. Nothing gets moved to the Desktop you're on.

<p align="center"><img src="docs/panel-asking.png" width="340" alt="The panel with a red banner: Claude Code is waiting, Claude needs your permission to use Bash."> &nbsp; <img src="docs/panel-settings.png" width="340" alt="Dawn's settings: morning ping time and days, setup checks for Claude Code, the scheduled wake and the hook, the space ping switch, open at login, and the last four pings."></p>

Everything you set once lives behind **Settings** at the bottom of the panel: the morning ping time and days, the setup checks, the sound, what the menu bar shows, and open at login. The panel itself stays a clock.

## Install

Dawn needs macOS 13 or later, on Apple silicon or Intel, and [Claude Code](https://docs.claude.com/en/docs/claude-code/setup) installed and signed in once.

**Download.** Get `Dawn.dmg` from the [latest release](https://github.com/Kungie/dawn/releases/latest), open it and drag Dawn into Applications. (`Dawn.zip` is there too, if you'd rather unzip.) Dawn isn't notarized by Apple yet, so the first time macOS will say it can't check it: open System Settings › Privacy & Security, scroll down and click **Open Anyway**. After that it opens normally.

**Or build it yourself** with the Xcode Command Line Tools (`xcode-select --install`):

```bash
git clone https://github.com/Kungie/dawn.git
```

```bash
cd dawn && make install
```

That builds `Dawn.app`, copies it to `/Applications` and opens it. Then open **Settings** in the panel, switch on the morning ping, pick a time and days, and click **Set up** next to *Wake the Mac*. macOS asks for your administrator password once, because scheduling a wake is a system setting.

`make app` builds a universal `build/Dawn.app` and `build/Dawn.zip`, signed ad hoc. With [dmgbuild](https://github.com/dmgbuild/dmgbuild) installed (`pip install dmgbuild`, or point `DMGBUILD` at it), it also makes `build/Dawn.dmg` with the drag-to-Applications window.

## How it works, honestly

**The ping.** Dawn runs `claude -p "ping" --model haiku` in its own folder (`~/Library/Application Support/Dawn/Dawn-ping`). That's the official CLI, using the login it already has. Dawn never reads, copies or stores your Claude credentials and never uses an API key. If a window is already running at ping time, Dawn skips the ping, since it would change nothing.

**The wake.** Dawn sets a repeating wake one minute before ping time with macOS's own `pmset`. macOS keeps only one repeating wake, so this replaces any other one you had; Dawn shows the current schedule in Setup. While the ping runs, Dawn holds a power assertion so the Mac stays awake.

**Things that can go wrong.** The Mac has to be plugged in and asleep, not shut down. On battery, macOS may skip a scheduled wake. With the lid closed, macOS sometimes drops back to sleep quickly; it's most reliable with the lid open. Check **Recent** in the panel for the first few mornings, or run `pmset -g log | grep -i wake` in Terminal.

**The countdown comes from Claude when it can.** Every two minutes Dawn runs `claude -p /usage --no-session-persistence`. Claude Code answers `/usage` itself, without sending anything to the model, so it uses none of your limit and leaves no session behind; Dawn reads the current session line from it (share used and reset time). It covers Claude.ai and the desktop app too, since they share the window. Every ping Dawn sends asks Claude Code for its JSON output, which includes the real reset time of your five-hour window and the share used, and Dawn takes it from there. If the panel only has an estimate while a window runs, **SYNC ↻** asks `/usage` right away, and only if that says nothing sends one short ping inside the window. With the Claude Code hook added, Dawn also becomes Claude Code's status line, and Claude Code hands its status line the real reset time of the current five-hour window and how much of it is used (`rate_limits.five_hour`, Pro and Max plans, after the first response in a session). Dawn shows exactly that, with the share used, and Auto refresh pings a minute after that reset. If you already had a status line, Dawn runs it and shows its output as before; *Remove* puts it back. Without that data, the countdown is an estimate: Dawn reads the timestamps of Claude's replies in Claude Code's local logs (`~/.claude/projects`), the same logs community tools use, counting five hours from the first message. It only sees Claude Code: the terminal, IDEs and the desktop app's Code tab. Chats in Claude.ai or the desktop app's chat don't appear there, so if you start your day in one of those, click **I started in Claude.ai**. Anthropic's own usage page is the source of truth.

**The hook.** *Add* writes two entries in `~/.claude/settings.json`, one under `hooks.Notification` and one under `hooks.Stop`, sets `statusLine` to `Dawn statusline` (keeping yours to run behind it), keeps everything else, and saves a backup next to it the first time (`settings.json.dawn-backup`). Claude Code then runs `Dawn hook` when it's waiting for you and `Dawn hook stop` when it has finished; both pass a short message to the app and exit. The message includes which app the session runs in and its terminal device, found by walking up the process tree, so a click on the alert can go there. To select the exact Terminal or iTerm2 tab, macOS asks once whether Dawn may control that app. For editors, Dawn can also raise the window of that project if you give it Accessibility access; without it, the app comes to the front. *Remove* takes the entries out again. The space ping is made in code when it plays; no sound files ship with the app.

**Privacy.** Nothing leaves your Mac except the ping itself, which goes to Anthropic through Claude Code like any other message you send, and the `/usage` check, which Claude Code makes to Anthropic the same way it does when you type `/usage`. Dawn has no telemetry, no account and no server.

## Is it allowed?

Dawn only drives the official Claude Code CLI on your own Mac, with your own account, once a morning, the same as typing a message yourself at 06:30. Anthropic sets the limits and the rules and can change them. Read their terms and decide for yourself. If scheduled pings ever stop making sense, Dawn is still a decent window clock.

Dawn is an independent project and is not affiliated with, endorsed by or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic, PBC.

## For tinkerers

Dawn is one Swift package with no dependencies. `Sources/Dawn` has the menu bar app (`DawnApp`, `PanelView`), the window estimate (`UsageLog`), the ping (`PingRunner`), the wake, hook and login item (`SystemSetup`), the space ping (`SpacePing`) and the Ident theme (`Theme`). The same binary has a few command line modes:

```bash
/Applications/Dawn.app/Contents/MacOS/Dawn status
```

`status` prints what Dawn sees: where `claude` is, the scheduled wake, the hook, and the current window estimate. `hook`, `hook stop` and `statusline` are what Claude Code calls; `hook-install` and `hook-remove` do what Add and Remove in Settings do. `schedule` prints today's morning ping and its Auto refresh follow-ups, `usage` prints what `/usage` says about the current window, `sync` sends a ping to read the reset time, `ping-sound` plays the finish sound, and `session` prints which app and terminal the hook would report from where you run it. `snapshot <folder>` renders the panel with demo data (that's where the pictures above come from), `icon <file>` draws the app icon and `dmg-background <folder>` the installer window.

`make app` builds `build/Dawn.app`, `make run` opens it, `make snapshots` refreshes the pictures in `docs/`.

## Licence

Dawn is free software under the [GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0): you can use, study, change and share it, and if you share a changed version, you share its source under the same licence. See [NOTICE](NOTICE). The bundled fonts (Archivo, VT323, Space Grotesk, Space Mono) are under the SIL Open Font License 1.1; their licence files sit next to them in `Resources/Fonts`.
