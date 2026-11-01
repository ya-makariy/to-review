# ToReview — notes for coding agents

- Everything in this repo is in English: code, comments, UI strings, docs, commits.
- Target: macOS 26+, Swift 6 strict concurrency, SwiftUI + AppKit (`NSStatusItem`, `NSPopover`, `NSWindow`).
- The Xcode project is generated: edit `project.yml`, then `xcodegen generate`. Never commit `ToReview.xcodeproj`.
- Build from CLI with `scripts/build.sh` (sets `DEVELOPER_DIR` to `/Applications/Xcode.app`, because
  `xcode-select` may point at the Command Line Tools). Tests: `cd Packages/ToReviewCore && swift test`.
- To test a change live use `scripts/run.sh`: it also kills the `ToReviewWidget` process. macOS keeps the
  widget extension running across rebuilds, so otherwise widgets keep running the old code.
- Signing is ad-hoc (`CODE_SIGN_IDENTITY=-`), no team. App Groups don't work without a provisioning
  profile (Xcode refuses `group.*`; the sandbox denies writes to legacy-style ids), so app and widget share
  `~/Library/Application Support/ToReview/` through a `temporary-exception.files.home-relative-path.read-write`
  entitlement. The path is duplicated in `project.yml` and `SharedStorage.relativePath` — keep them in sync.
- Only the app fetches. The widget reads `snapshot.json` from the shared directory via `SnapshotStore`.
  Everything shared is a JSON file (`settings.json`, `accounts.json`, `seen.json`, `widget-state.json`).
- Keep `ToReviewCore` free of AppKit/SwiftUI so it stays testable with `swift test`.
- Provider mapping lives in `GitHubProvider.map` / `GitLabProvider.map`; add fixture JSON under
  `Packages/ToReviewCore/Tests/ToReviewCoreTests/Fixtures` when changing queries.
