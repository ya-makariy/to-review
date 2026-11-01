# ToReview

A macOS menu-bar app and widget set that keeps pull requests waiting for your review
one glance away — across any number of GitHub and GitLab accounts, including
GitHub Enterprise and self-managed GitLab.

- **Status bar** — `↓ 3 ↑ 2`: incoming (you're reviewer or assignee) and outgoing (you're
  the author). A red dot appears when a new incoming PR has arrived since you last looked.
- **Popover** — click the counters for a compact list; click a PR to open it in the browser.
- **Widgets** — small (1×1), medium (2×1) and large (2×2). Small widgets can page through
  accounts with ‹ › buttons or be pinned to one account.
- **Main window** — Liquid Glass UI with all accounts, incoming and outgoing lists,
  connection status and account management.
- **Notifications** — a macOS notification for every new incoming PR.
- **Resilient** — if an account stops responding you keep the last successfully fetched
  PRs with a warning banner instead of an empty list.

Requires **macOS 26 Tahoe** or later.

## Install

### Homebrew (coming soon)

```sh
brew install --cask --no-quarantine ya-makariy/tap/to-review
```

`--no-quarantine` is required because the app is not notarized (see [Signing](#signing)).

### Build from source

```sh
git clone https://github.com/ya-makariy/to-review.git
cd to-review
scripts/bootstrap.sh          # installs XcodeGen, generates ToReview.xcodeproj
open ToReview.xcodeproj       # Run the "ToReview" scheme
# or, without the IDE:
scripts/build.sh
open build/DerivedData/Build/Products/Debug/ToReview.app
```

Needs Xcode 26 or later. The project file is generated from `project.yml`; don't edit the
`.xcodeproj` by hand.

## Connecting accounts

Open the main window (click the status item → **Open ToReview**) and press **+**.

### Personal access token (any host)

| Provider | Scopes |
|----------|--------|
| GitHub   | Classic token: `repo`, `read:user`. Fine-grained token: *Pull requests → Read*, *Metadata → Read* for the repositories you care about. |
| GitLab   | `read_api` |

Tokens are stored in the macOS Keychain. The host field accepts any base URL, e.g.
`https://gitlab.company.com` or `https://ghe.corp.example`.

### Sign in with browser (OAuth device flow, github.com and gitlab.com only)

Device flow needs a public OAuth client id. There is none bundled, so register one once:

**GitHub** — Settings → Developer settings → OAuth Apps → *New OAuth App*.
Any homepage / callback URL works. After creating it, tick **Enable Device Flow**.
Copy the *Client ID*.

**GitLab** — Preferences → Applications → *Add new application*.
Untick *Confidential*, tick the `read_api` scope, use `urn:ietf:wg:oauth:2.0:oob` as the
redirect URI. Copy the *Application ID*. Device flow needs GitLab 17.2 or newer.

Paste the ids in **Settings → Accounts → OAuth client ids** (or into
`Packages/ToReviewCore/Sources/ToReviewCore/Auth/OAuthConfig.swift` before building).
Self-managed hosts always use tokens.

## What counts as "incoming"

An open, non-draft PR where you are a requested reviewer **or** an assignee, that you did not
author. PRs you have already approved are hidden by default (Settings → General).
Outgoing PRs are everything you authored that is still open, drafts included.

## Settings

- **Sync interval** — 1 to 30 minutes (default 5). Widgets show whatever the app fetched last,
  so keep the app running or enable *Launch at login*.
- **Status bar mode** — both counters or incoming only.
- **Display fields** — toggle author, CI status, age, approvals and comments separately for
  the app and for widgets.

## Signing

The project ships **ad-hoc signed** (no Apple Developer Program membership yet). Consequences:

- Gatekeeper refuses to open a downloaded build until the quarantine flag is removed
  (`brew --no-quarantine`, or `xattr -d com.apple.quarantine ToReview.app`).
- Keychain may ask for access after you install a new build. Choose *Always Allow*.

Everything works the same once the app is running. A notarized build is on the roadmap.

## Architecture

```
Packages/ToReviewCore   Models, GraphQL providers (GitHub, GitLab), device flow, Keychain,
                        snapshot/seen stores, sync engine. Shared by app and widget. Unit-tested.
ToReview/               Menu-bar app: NSStatusItem + SwiftUI label, popover, main window,
                        account editor, settings, notifications, polling.
ToReviewWidget/         WidgetKit extension. Reads the snapshot the app wrote; never touches
                        the network or the Keychain.
```

Only the app talks to the APIs. After every sync it writes `snapshot.json` to
`~/Library/Application Support/ToReview/` (shared with the widget through a sandbox
file exception, since App Groups need a provisioning profile) and asks WidgetKit to reload.

## Development

```sh
scripts/bootstrap.sh                          # once
scripts/build.sh                              # debug build
scripts/run.sh                                # debug build + restart app and widget process
cd Packages/ToReviewCore && swift test        # unit tests
scripts/build-release.sh                      # dist/ToReview-<version>.zip + sha256
```

## License

MIT
