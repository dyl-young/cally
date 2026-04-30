# Cally

A tiny native macOS menu bar app that shows your Google Calendar meetings and lets you join Google Meet calls in one click. Personal replacement for the Notion Calendar menu bar.

## Features (v1)

- Menu bar shows next meeting + countdown (e.g. `Standup · in 19m`, `Standup · 19m left`)
- Popover lists Now / Today / Tomorrow / Day-3 events
- Hover an event with a Meet link → "Join" button
- macOS notification 1 minute before each meeting (with Join action)
- Launch at login
- Native Swift + SwiftUI, ~30–50MB RAM
- Single Google account; multi-account ready in storage

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
6. Copy the **client ID** (looks like `1234-abc.apps.googleusercontent.com`)

### 2. Plug the client ID into the app

Either edit `Sources/Auth/AuthConfig.swift` and replace `YOUR_GOOGLE_OAUTH_CLIENT_ID...`, or set an environment variable when running from Xcode:

- In Xcode → Edit Scheme → Run → Arguments → Environment Variables
- Add `CALLY_GOOGLE_CLIENT_ID = <your client ID>`

### 3. Generate and open the project

```sh
xcodegen
open Cally.xcodeproj
```

### 4. Run

Hit ⌘R in Xcode. The calendar icon appears in your menu bar — click it, sign in with Google, then your events will appear.

## Architecture

```
Sources/
├── App/                # @main, AppDelegate, AppState
├── Auth/               # OAuth (PKCE + loopback), Keychain, account/token storage
├── Calendar/           # Google Calendar API client, sync manager (syncToken), cache
├── MenuBar/            # NSStatusItem controller, title formatter
├── Notifications/      # 1-min-before banner with Join action
├── UI/                 # SwiftUI popover, rows, sign-in, settings
└── Util/               # NSColor hex helper
```

## Decisions

See `~/.claude/projects/-Users-dylan-young-Desktop-repos-personal-cally/memory/project_cally_overview.md` for the locked v1 spec.

Key choices:
- **Polling, not webhooks**: incremental polling with `syncToken` avoids running a public HTTPS endpoint
- **Personal-only, unsigned**: no Apple Developer Program, run from Xcode locally
- **NSPopover with SwiftUI inside**: more flexible than `NSMenu`, native feel
- **Meet only**: skip Zoom/Teams URL parsing v1

## Roadmap (v2 ideas, not built)

- Multi-calendar selection in Settings
- Multi-account
- Zoom / Teams link detection
- Global hotkeys (Cmd+Ctrl+J to join next meeting)
- Custom title threshold
- Configurable notification lead times
