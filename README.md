# Cally

A tiny native macOS menu bar app that shows your Google Calendar meetings and lets you join Google Meet calls in one click. Personal replacement for the Notion Calendar menu bar.

## Features

- Menu bar shows next meeting + countdown next to a coloured calendar bar (e.g. `Standup · in 19m`, `Standup · 19m left`, `Standup · now`). Falls back to a calendar SF Symbol when nothing is scheduled in the next 12 hours.
- Native `NSMenu` lists events grouped by **Ending in Xm** (in-progress), **Upcoming in X min** (next event within 30 min), **Today**, **Tomorrow**, and a named day-3.
- Click any event to open it in Google Calendar; "Join Google Meet meeting" sub-row on current/upcoming events launches the call.
- Multi-account: link several Google accounts and pick which calendars from each show up.
- Conflict aware: when two events start at the same time, the title shows `+N` and the menu lists them all in a single section.
- Local notification 1 minute before each Meet event, with a Join action.
- Global hotkey ⌘⌃K opens the menu (and Enter on a highlighted event launches it).
- Launch at login, offline cached events, ⌘1 to open Google Calendar in the browser, ⌘, for Settings.
- Native Swift 6 + SwiftUI + AppKit, ~30–50 MB RAM.

## Prerequisites

- macOS 14+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Setup

### 1. Create a Google OAuth client

1. Go to <https://console.cloud.google.com>
2. Create a new project (e.g. "Cally")
3. **APIs & Services → Library** → enable **Google Calendar API**
4. **APIs & Services → OAuth consent screen** → External → add yourself as a test user with the Calendar scopes
5. **APIs & Services → Credentials** → Create credentials → **OAuth client ID** → Application type **Desktop app**
6. Copy the **client ID** and **client secret**

### 2. Drop the credentials into `.env`

```sh
cp .env.example .env
# edit .env and paste in CALLY_GOOGLE_CLIENT_ID and CALLY_GOOGLE_CLIENT_SECRET
```

`.env` is gitignored. Google's Desktop OAuth flow requires the client secret in the token exchange even with PKCE, so both values are needed. Treat the secret as low-sensitivity (it's "public" in the installed-app sense) but keep it out of source.

### 3. Bootstrap

```sh
make setup           # generates Sources/Generated/Secrets.swift then Cally.xcodeproj
```

`Secrets.swift` is regenerated automatically as a pre-build phase, so changes to `.env` are picked up on every build. Re-run `make setup` (or `make project`) when you change `project.yml` or `.env`.

## Daily workflows

Two flows, no Xcode required.

### Dev — iterate on changes

```sh
make dev
```

Builds Debug into `build/dev`, kills any running Cally, and launches the bundle. Edit code → `make dev` → click the menu bar icon. Tokens and event cache live in `~/Library/Application Support/Cally/` (bundle-id keyed, not path keyed), so sign-in survives every rebuild.

If a build fails silently, remove `-quiet` from the `dev` target in the `Makefile` to see Xcode's diagnostics.

### Install — promote to `/Applications`

```sh
make install
```

Builds Release into `build/release`, kills any running Cally, `ditto`s the bundle into `/Applications/Cally.app`, and launches it. Use this when the dev build is solid and you want it surviving reboots.

**One-time gotcha after the first install:** open **Cally → Settings** and toggle **Launch at login** off then on. `SMAppService.mainApp` binds the login item to the bundle's current path, so it needs re-registering after the app moves into `/Applications`. Subsequent `make install` runs reuse the same path, so this is genuinely one-time.

Only one Cally runs at a time — both targets `pkill -x Cally` first, so the dev and installed bundles won't fight over the menu bar.

### Opening in Xcode (optional)

If you want to debug with breakpoints or use Xcode's tooling: `open Cally.xcodeproj` and ⌘R. The Xcode-run build is tied to Xcode's lifetime — quit Xcode and the menu bar icon goes with it.

## Architecture

```text
Sources/
├── App/                # @main, AppDelegate, AppState
├── Auth/               # OAuth (PKCE + loopback), file-based SecretsStore, account/token storage
├── Calendar/           # Google Calendar API client, sync manager (syncToken), cache
├── MenuBar/            # NSStatusItem, NSMenu builder, title formatter, global hotkey
├── Notifications/      # 1-min-before banner with Join action
├── UI/                 # Settings window, event grouping
└── Util/               # NSColor hex helper
```

## Decisions

Key choices:

- **Polling, not webhooks**: incremental polling with `syncToken` per `(account, calendar)` avoids running a public HTTPS endpoint.
- **Personal-only, unsigned**: no Apple Developer Program, run from Xcode locally.
- **Native `NSMenu`, not `NSPopover`**: gives us system-standard highlighting, scroll behaviour, and Enter-to-launch on the keyboard-selected row. Custom `NSView` menu items broke Enter-key actions, so events are rendered as native `NSMenuItem`s with `attributedTitle` + a 16×16 image holding the calendar colour bar.
- **File-based SecretsStore, not Keychain**: ad-hoc signing changes the binary signature on every rebuild, which invalidates Keychain ACLs and triggers password prompts. A `0600` JSON file in Application Support sidesteps this for personal use.
- **Manually-managed Settings window**: macOS 14+ deprecates the `Settings` SwiftUI scene's open path; a plain `NSWindow` + `NSHostingController` avoids the "Please use SettingsLink" warning.
- **Meet only**: no Zoom/Teams URL parsing.
