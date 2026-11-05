# E-Merger

A small, native **macOS app** for people who hold **more than one Bitbucket
account** on the same server (for example a *manager* identity that approves and a
*developer* identity that writes code). It lists every open pull request your
accounts can see, shows who still has to approve and whether CI is green, and lets
you **approve, merge, comment or trigger CI with the account you choose** — one
window, one click, no juggling two machines or two browser profiles.

> **Own accounts only.** E-Merger is a multi-account client for *your* identities,
> like `gh auth switch` with a GUI. Tokens are stored in the macOS Keychain of the
> Mac you typed them on, never in a file, never exported, never shared. Every action
> is written to a local activity log with the account that performed it.

## Features

- **Multiple accounts** (label + server + HTTP access token or user/password);
  "Doğrula" resolves the Bitbucket username for you.
- **One list for everything** — each account's dashboard (PRs you author / review)
  plus any repositories you choose to watch; merged, deduplicated, searchable, with
  filters *Tümü · Onayımı bekleyen · Merge'e hazır · Benim açtıklarım*.
- **Per-PR detail** — reviewers and their status, latest-commit build results, merge
  check with Bitbucket's vetoes (required approvals, conflicts, failed builds…).
- **Actions with the right account** — *Onayla · Müdür*, *Merge · Müdür*,
  *Onayla + Merge* (approve, wait until mergeable, merge), un-approve / needs-work,
  comment. The authoring account is never offered for approval (Bitbucket forbids
  it anyway).
- **CI trigger** — optional HTTP hook per repo (Jenkins `buildWithParameters`,
  Bamboo, webhook) with `{branch}`, `{prId}`, `{commit}` … placeholders; can fire
  automatically after approve.
- **Notifications** when a PR newly needs one of your approvals; auto-refresh.
- **Activity log** (⇧⌘L) — who did what, when.
- **Auto-update** via Sparkle (notarized builds, asks before installing).

## Install

### Homebrew

```sh
brew tap ersel95/e-merger https://github.com/ersel95/e-merger
brew install --cask e-merger
```

### DMG

Download `E-Merger-<version>.dmg` from
[Releases](https://github.com/ersel95/e-merger/releases), open it, drag
**E-Merger** to **Applications**.

Release builds are Developer ID signed and notarized. (Only builds you compile
yourself are unsigned; if Gatekeeper blocks one:
`xattr -dr com.apple.quarantine /Applications/E-Merger.app`.)

## Setup

1. **Ayarlar › Hesaplar › Hesap ekle…** — label (e.g. *Müdür*), server URL, token.
   The server URL is the Bitbucket root as you see it in the browser, including a
   context path if there is one (e.g. `https://git.example.com/bitbucket`);
   **Doğrula** also finds `/bitbucket` and `/stash` on its own when the host root
   answers 503. Create the token in Bitbucket under *Manage account › HTTP access
   tokens* with **Repository: Write** (approve/comment) — and **Repository: Admin**
   only if your server requires it for merges. Press **Doğrula**, then **Kaydet**.
2. Repeat for the second identity (e.g. *Geliştirici*).
3. Optional — **Depolar**: add `PROJECT/repo` entries whose *all* open PRs should be
   listed even when neither account is a participant.
4. Optional — **CI**: add a trigger if your pipeline is not already started by a
   Bitbucket webhook on approve/merge.

## Build from source

```sh
python3 generate_pbxproj.py && open EMerger.xcodeproj   # Xcode 15+, macOS 14+
scripts/e2e.sh                                          # mock Bitbucket + headless end-to-end test
scripts/build-dmg.sh dev                                # unsigned DMG in dist/
```

See [CLAUDE.md](CLAUDE.md) for the architecture and the release pipeline.

## License

MIT
