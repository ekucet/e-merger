# E-Merger — AI Context

> Native macOS SwiftUI app that lists open **Bitbucket Server / Data Center** pull
> requests across the user's **own** accounts (e.g. a "Müdür" and a "Geliştirici"
> identity on the same server), approves / merges / comments with whichever of
> those accounts the user picks, and promotes releases through a branch chain. Public, MIT, generic — **no
> customer/bank-specific data belongs in this repo.**

## Hard rules

1. **Public repo.** Never commit secrets, real server hostnames, usernames, project
   keys, repo slugs or local absolute paths. Config lives in
   `~/Library/Application Support/E-Merger/config.json`; tokens live **only** in the
   Keychain (`KeychainStore`, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`).
2. **Own accounts only.** The app is a multi-account client for one person's own
   identities (like `gh auth switch`). There is deliberately **no** token export,
   sync, sharing or "act as a teammate" feature — don't add one. Every action is
   written to the local `ActivityLog` with the acting account.
3. The Xcode project is **generated**, not committed. After adding/removing a Swift
   file, update `SOURCES` in `generate_pbxproj.py` and re-run it. `.xcodeproj` is
   git-ignored.
4. macOS 14+. **Sparkle** (auto-update) is the **only** allowed dependency (SPM,
   wired by `generate_pbxproj.py`).
5. **Must compile clean under Swift 6 language mode** (CI is stricter than a local
   Xcode). Verify before tagging:
   `xcodebuild -project EMerger.xcodeproj -scheme EMerger -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO SWIFT_VERSION=6 build`
6. **SwiftUI view structs and the stores are `@MainActor`.** `AccountStore`,
   `PullRequestStore`, `ActivityLog` are `@Observable @MainActor`; `BitbucketClient`
   is a `Sendable` value type usable from any task.
7. File headers: `// Created by Mr. t.` UI strings are Turkish.

## Layout

```
EMerger/
├── EMergerApp.swift            @main; owns AccountStore, ActivityLog, PullRequestStore
├── Models/                     BitbucketAccount (+ BitbucketCredential, WatchedRepository),
│                               BitbucketModels (BB* wire types), PullRequestItem
│                               (aggregated PR + per-account relation + filter enum),
│                               AppSettings, EMergerError,
│                               ReleasePipeline (branch chain + stages + plan())
├── Services/                   KeychainStore, BitbucketClient (REST), AccountStore
│                               (config.json), PullRequestStore (aggregate + actions),
│                               ActivityLog (activity.jsonl), Notifier,
│                               ReleaseRunner (runs a chain hop by hop)
├── Views/                      Components (Brand palette, tiles, confetti, toast),
│                               ContentView (split view), PullRequestListView,
│                               PullRequestDetailView, SettingsView (+ Accounts /
│                               Depolar / Yayın / Genel tabs), AccountEditorView,
│                               ActivityLogView, UpdaterView, ReleaseFlowView ("Yayına
│                               al" sheet), ReleaseSettingsView (Yayın tab + editor)
├── Resources/Assets.xcassets   AppIcon (drawn by scripts/generate_icon.swift), AccentColor
├── Info.plist                  Sparkle keys + ATS (local networking only)
└── EMerger.entitlements        unsandboxed, network client
generate_pbxproj.py             project generator (source of truth for the target)
scripts/                        build-app.sh, build-dmg.sh (unsigned), release-dmg.sh
                                (sign + notarize + staple, CI), update_appcast.py, e2e.sh,
                                generate_icon.swift (re-draws every AppIcon size)
tests/                          mock_bitbucket.py (stdlib Bitbucket REST mock),
                                Harness.swift (headless end-to-end run of Models+Services)
.github/workflows/release.yml   tag v* -> sign + notarize + Release + cask/appcast bump
Casks/e-merger.rb               Homebrew cask (auto-bumped by CI)
```

## Architecture

- **Accounts**: `BitbucketAccount` = label + server URL + resolved username/slug.
  `AccountEditorView` → "Doğrula" first runs `BitbucketClient.detectBaseURL`
  (probes the entered URL, then `/bitbucket`, `/stash` via the public
  `application-properties` endpoint — corporate installs answer 503 at the host
  root), then `whoami()`: `GET …/dashboard/pull-requests?limit=1` and reads the
  `X-AUSERNAME` response header (401 on a bad token; the applinks `whoami` servlet
  is only a fallback because Data Center returns an empty body for HTTP access
  tokens), then `GET /rest/api/1.0/users/{slug}` to fill display name and slug.
  Auth is `Bearer <HTTP access token>` or `Basic user:password`
  (`BitbucketCredential.mode`).
- **Listing**: `PullRequestStore.refresh()` fans out per enabled account:
  `GET /rest/api/1.0/dashboard/pull-requests?state=OPEN` (PRs the account authors /
  reviews / participates in) **plus** every `WatchedRepository`
  (`GET /projects/{k}/repos/{s}/pull-requests?state=OPEN`), paginated. Results are
  merged by `PROJECT/repo#id`; `seenBy` records which accounts' tokens returned the
  PR, `relations` records per account whether it is author / reviewer / approved.
  A dashboard omits PRs the account is not author / reviewer / participant of —
  typically a PR my other account opened without reviewers — so every PR is then
  probed (`GET …/pull-requests/{id}`) with each account that has not seen it;
  success adds the account to `seenBy` (and thus to the approve / merge buttons).
  Approving as a non-reviewer makes the account a PARTICIPANT, which Bitbucket's
  minimum-approvals check counts.
  Merge status (`GET …/merge` → `canMerge` + vetoes) is fetched after each refresh in
  batches of 4, so the list's `phase` and the "Hazır" filter work unselected; an
  unchanged, already mergeable PR skips the re-check. It is also re-read on selection
  and after every action. A failing account keeps its last known PRs in the list.
- **Actions** (`PullRequestStore`): approve / unapprove / needs-work =
  `PUT …/participants/{userSlug}` with `{"status": …}` — Bitbucket refuses the
  author approving their own PR (409), so `accountsThatCanApprove` never offers the
  authoring account. Merge = `POST …/merge?version=N` (optimistic lock; a 409
  "out-of-date" re-reads the PR and surfaces `EMergerError.outOfDate`; vetoes map
  to `.vetoed`). "Onayla + Merge" approves with one account, polls `canMerge`
  (≤8 × 1.5 s), then merges with the chosen merge account. Comment =
  `POST …/comments`. Every mutating call carries `X-Atlassian-Token: no-check`.
- **Release flow ("Yayına al", ⇧⌘R)**: `ReleasePipeline` = repo + source branch +
  ordered stages (`dev → release/tst → release/uat → release/liv`) + merge strategy
  (`ff-only` default) + two accounts. `plan(upTo:)` yields one `ReleaseStep` per hop
  with opener/approver **alternating** from the starter account (the author can never
  approve). `ReleaseRunner.run` executes hops in order: compare branch heads
  (`GET …/branches?filterText=`; equal → skipped) → `POST …/pull-requests` with the
  opener (409 `DuplicatePullRequestException` → adopt `existingPullRequest`, and if
  its author is the would-be approver the other account acts; 409
  `EmptyPullRequestException` → skipped) → approve with the partner → poll
  `GET …/merge` every 5 s until `canMerge` (conflict → fail; approval-only vetoes
  after 3 polls → fail; `waitMinutes` timeout) → `POST …/merge` with `strategyId`
  (409 out-of-date → re-read + retry once). Every call is logged (`open-pr`,
  `approve`, `merge`). A run survives closing the sheet; `cancel()` stops after the
  current call. The final stage asks for confirmation when `confirmMerge` is on.
  Chains are stored in `config.json` (`releasePipelines`); `Config` decodes with
  `decodeIfPresent` so older files never lose their accounts.
- **Look & feel**: the icon's mascot is Mergino, a merge road sign with a moustache
  (an original character; don't copy existing meme characters). `Brand` holds the
  palette: sign yellow for the one primary button per screen (text on it is `Brand.ink`),
  sky blue for tinted text. Playful copy is for empty states and successes; errors and
  destructive confirmations stay plain. Confetti is skipped under Reduce Motion.
- **No CI.** By decision (2026-11-05) the app neither shows build statuses nor
  triggers CI — it is only for approving, merging and promoting releases. Don't
  add CI features back.
- **Notifications**: after a refresh, PRs that newly need one of my approvals post a
  local `UNUserNotification` (`Notifier`), gated by `AppSettings.notifyNewApprovals`.
- **Auto-update (Sparkle)**: identical to FlightKit — `UpdaterController` owns
  `SPUStandardUpdaterController`; `Info.plist` carries `SUFeedURL` (appcast on raw
  `main`) + `SUPublicEDKey`; checks on launch + daily, **notify + ask**, never silent.
  CI signs each DMG with EdDSA and `scripts/update_appcast.py` inserts the item.

## Gotchas

- **Keychain prompts on dev builds.** Items are ACL-bound to the creating binary;
  an unsigned dev build may prompt after every rebuild and a CLI test binary
  cannot read items the app wrote (and vice versa). The notarized release is
  stable. The harness therefore writes its own items and deletes them on exit.
- `EMERGER_SUPPORT_DIR` overrides the Application Support directory (used by
  `scripts/e2e.sh` so tests never touch the real config). Don't remove it.
- **Context path.** Bitbucket is often served under `https://host/bitbucket`; the
  host root returns 503. Keep the path in `serverURL` (the client appends REST
  paths to it) and keep `detectBaseURL` in the verify flow. The mock mirrors this
  (`scripts/e2e.sh` starts it with `/bitbucket`).
- **Identity.** The applinks `whoami` servlet returns an empty body for HTTP
  access tokens on Data Center (verified on 9.4) and HTML behind SSO; the username
  comes from `X-AUSERNAME` on any authenticated REST response. The field can still
  be typed by hand.
- `ATS`: only `NSAllowsLocalNetworking` is enabled (for the mock on localhost).
  Production servers must be HTTPS with a chain the Mac trusts.
- Sparkle signing / bootstrap gotchas are the same as FlightKit's: sign the
  framework inside-out before the outer app; the appcast URL 404s until the first
  release populates it.

## Build / test / release

```sh
python3 generate_pbxproj.py && open EMerger.xcodeproj       # dev
scripts/e2e.sh                                              # mock server + headless harness
scripts/build-dmg.sh 1.0.0                                  # local UNSIGNED dmg
git tag v1.0.0 && git push origin v1.0.0                    # CI: sign+notarize+release
```

Release builds are **Developer ID signed + notarized + stapled**. CI needs repo
secrets `DEVELOPER_ID_CERT_P12_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`,
`SIGNING_IDENTITY`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64` and
`SPARKLE_ED_PRIVATE_KEY` (public half = `SUPublicEDKey` in `Info.plist`; generated
with `generate_keys --account e-merger`). Distribution: GitHub Releases
(`E-Merger-<v>.dmg`) and `brew install --cask e-merger` (tap `ersel95/e-merger`).
