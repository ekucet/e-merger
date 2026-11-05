import Foundation

/// Headless end-to-end check of the Models + Services layer against the mock
/// Bitbucket on localhost:7990, using the same config.json / Keychain items the
/// app uses. Prints a PASS/FAIL line per step.
private let testConfig = """
{
  "accounts": [
    {"id": "acc-mudur", "label": "Müdür", "serverURL": "http://localhost:7990/bitbucket", "username": "mudur", "displayName": "Ersel (Müdür)", "userSlug": "mudur", "isEnabled": true},
    {"id": "acc-dev", "label": "Geliştirici", "serverURL": "http://localhost:7990/bitbucket", "username": "gelistirici", "displayName": "Ersel (Geliştirici)", "userSlug": "gelistirici", "isEnabled": true}
  ],
  "watchedRepos": [{"id": "wr-1", "projectKey": "CORE", "slug": "payments"}],
  "ciTriggers": [{"id": "ci-1", "name": "Mock CI", "urlTemplate": "http://localhost:7990/ci/trigger?branch={branch}&pr={prId}", "method": "POST", "bodyTemplate": "{\\"repo\\":\\"{project}/{repo}\\",\\"commit\\":\\"{commit}\\"}", "contentType": "application/json", "secretHeaderName": "", "repoFilter": ""}]
}
"""

@main @MainActor
struct Harness {
    nonisolated(unsafe) static var failures = 0

    static func check(_ name: String, _ condition: Bool, _ detail: String = "") {
        print((condition ? "PASS" : "FAIL") + "  \(name)" + (detail.isEmpty ? "" : "  — \(detail)"))
        if !condition { failures += 1 }
    }

    static func main() async {
        // The harness writes its own (fake) credentials so the Keychain ACL
        // belongs to this binary — no access prompt.
        try! KeychainStore.saveCredential(BitbucketCredential(mode: .bearer, secret: "tok-mudur"), forAccountID: "acc-mudur")
        try! KeychainStore.saveCredential(BitbucketCredential(mode: .bearer, secret: "tok-dev"), forAccountID: "acc-dev")
        defer {
            try? KeychainStore.deleteCredential(forAccountID: "acc-mudur")
            try? KeychainStore.deleteCredential(forAccountID: "acc-dev")
        }
        let dir = AccountStore.supportDirectory
        precondition(ProcessInfo.processInfo.environment["EMERGER_SUPPORT_DIR"] != nil, "run via scripts/e2e.sh (EMERGER_SUPPORT_DIR must be set)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try! Data(testConfig.utf8).write(to: dir.appendingPathComponent("config.json"))
        let accounts = AccountStore()
        let log = ActivityLog()
        let store = PullRequestStore(accounts: accounts, log: log)
        let mudur = accounts.accounts.first { $0.label == "Müdür" }!
        let dev = accounts.accounts.first { $0.label == "Geliştirici" }!
        print("accounts:", accounts.accounts.map { "\($0.label)=\($0.username)" })

        // Server root detection + identity (the mock serves under /bitbucket, 503 at "/",
        // and its whoami servlet is empty like Data Center with HTTP access tokens).
        let detected = await BitbucketClient.detectBaseURL(from: URL(string: "http://localhost:7990")!)
        check("context path /bitbucket auto-detected from host root", detected?.absoluteString == "http://localhost:7990/bitbucket", detected?.absoluteString ?? "nil")
        let kept = await BitbucketClient.detectBaseURL(from: URL(string: "http://localhost:7990/bitbucket")!)
        check("explicit context path kept as-is", kept?.absoluteString == "http://localhost:7990/bitbucket", kept?.absoluteString ?? "nil")
        let none = await BitbucketClient.detectBaseURL(from: URL(string: "http://localhost:7991")!)
        check("unreachable host → nil", none == nil, none?.absoluteString ?? "nil")
        do {
            let who = try await accounts.client(for: mudur).whoami()
            check("whoami via X-AUSERNAME (servlet empty)", who == "mudur", who)
            let user = try await accounts.client(for: dev).user(slug: "gelistirici")
            check("user lookup by slug", user.name == "gelistirici" && user.effectiveSlug == "gelistirici", user.name)
        } catch { check("whoami / user lookup", false, error.localizedDescription) }

        await store.refresh()
        print("accountErrors:", store.accountErrors)
        for item in store.items {
            let seen = item.seenBy.compactMap { accounts.account(id: $0)?.label }
            let rel = item.relations.values.map { r -> String in
                let a = accounts.account(id: r.accountID)?.label ?? r.accountID
                return "\(a):\(r.isAuthor ? "author" : r.isReviewer ? "reviewer" : "-")/\(r.status?.rawValue ?? "none")"
            }.sorted()
            print("  \(item.id) v\(item.pr.version) \(item.pr.approvedCount)/\(item.pr.reviewers.count) build=\(item.overallBuild) seen=\(seen) \(rel)")
        }
        check("7 open PRs aggregated", store.items.count == 7, "\(store.items.count)")
        check("no account errors", store.accountErrors.isEmpty)

        let pr1 = "MOB/ios-app#1", pr2 = "MOB/ios-app#2", pr3 = "MOB/android-app#3"
        let pr4 = "CORE/payments#4", pr5 = "MOB/ios-app#5", pr6 = "CORE/payments#6"
        check("PR6 (no reviewers) found via watched repo", store.item(for: pr6) != nil)

        // PR7: opened by Geliştirici, no reviewers, repo not watched → only the author's
        // dashboard lists it; Müdür must be found via the per-PR probe and be offered.
        let pr7 = "MOB/ios-app#7"
        if let i7 = store.item(for: pr7) {
            let seen = i7.seenBy.compactMap { accounts.account(id: $0)?.label }.sorted()
            check("PR7 seen by both accounts after probe", seen == ["Geliştirici", "Müdür"], "\(seen)")
            check("PR7 approvable by Müdür although not a reviewer", i7.accountsThatCanApprove(from: accounts.enabledAccounts).map(\.label) == ["Müdür"])
            check("PR7 awaiting my approval (opened by my other account)", i7.awaitingMyApproval)
            check("PR7 not awaiting for a stranger's PR logic (PR6 has no reviewers, same author) → both flagged", store.item(for: pr6)?.awaitingMyApproval == true)
        } else {
            check("PR7 found via probe", false, store.items.map(\.id).joined(separator: ","))
        }
        check("PR1 seen by both accounts", store.item(for: pr1)?.seenBy.count == 2)
        check("PR5 build failed", store.item(for: pr5)?.overallBuild == .failed)
        check("PR3 build in progress", store.item(for: pr3)?.overallBuild == .inProgress)

        if let i1 = store.item(for: pr1) {
            let can = i1.accountsThatCanApprove(from: accounts.enabledAccounts).map(\.label)
            check("PR1 approvable only by Müdür (dev is author)", can == ["Müdür"], "\(can)")
            check("PR1 awaiting my approval", i1.awaitingMyApproval)
            check("PR1 authored by one of mine", i1.isAuthoredByAnyOfMine)
        }
        if let i4 = store.item(for: pr4) {
            let can = i4.accountsThatCanApprove(from: accounts.enabledAccounts).map(\.label)
            check("PR4 approvable only by Geliştirici (müdür is author)", can == ["Geliştirici"], "\(can)")
            check("PR4 default merge account is Geliştirici (non-author)", store.defaultMergeAccount(for: i4)?.label == "Geliştirici")
        }

        // Merge status
        await store.loadMergeStatus(for: pr1)
        check("PR1 not mergeable before approval", store.item(for: pr1)?.mergeStatus?.canMerge == false, "\(String(describing: store.item(for: pr1)?.mergeStatus))")

        // Approve PR1 with Müdür
        do {
            try await store.approve(pr1, with: mudur)
            let i1 = store.item(for: pr1)
            check("PR1 approved → Müdür relation approved", i1?.relations[mudur.id]?.hasApproved == true)
            check("PR1 version bumped", (i1?.pr.version ?? 0) >= 1, "v\(i1?.pr.version ?? -1)")
            check("PR1 mergeable after approval", i1?.mergeStatus?.canMerge == true)
            check("PR1 no longer approvable by anyone", i1?.accountsThatCanApprove(from: accounts.enabledAccounts).isEmpty == true)
        } catch { check("approve PR1", false, error.localizedDescription) }

        // Author cannot approve own PR (dev on PR1)
        do {
            try await store.approve(pr1, with: dev)
            check("author self-approve rejected", false, "unexpectedly succeeded")
        } catch { check("author self-approve rejected", true, error.localizedDescription) }

        // PR7: approve with my other account although it is not a reviewer (becomes a
        // participant), then merge with it.
        do {
            try await store.approve(pr7, with: mudur)
            let i7 = store.item(for: pr7)
            check("PR7 approved by Müdür as participant", i7?.relations[mudur.id]?.hasApproved == true, "\(String(describing: i7?.relations[mudur.id]))")
            check("PR7 participant approval satisfies merge check", i7?.mergeStatus?.canMerge == true, "\(String(describing: i7?.mergeStatus?.vetoes))")
            check("PR7 no longer awaiting my approval", i7?.awaitingMyApproval == false)
            try await store.merge(pr7, with: mudur)
            check("PR7 merged by Müdür and removed", store.item(for: pr7) == nil)
        } catch { check("approve + merge PR7", false, error.localizedDescription) }

        // Un-approve then re-approve
        do {
            try await store.setStatus(pr1, with: mudur, status: .unapproved)
            check("PR1 unapproved", store.item(for: pr1)?.relations[mudur.id]?.hasApproved == false)
            try await store.setStatus(pr1, with: mudur, status: .needsWork)
            check("PR1 needs-work", store.item(for: pr1)?.relations[mudur.id]?.status == .needsWork)
            try await store.approve(pr1, with: mudur)
        } catch { check("status toggles", false, error.localizedDescription) }

        // Merge PR2 (already mergeable) with Müdür
        do {
            try await store.merge(pr2, with: mudur)
            check("PR2 merged and removed from list", store.item(for: pr2) == nil)
        } catch { check("merge PR2", false, error.localizedDescription) }

        // Merge PR3 → conflicted veto
        do {
            try await store.merge(pr3, with: mudur)
            check("PR3 conflicted merge rejected", false, "unexpectedly succeeded")
        } catch EMergerError.vetoed(let reasons) {
            check("PR3 conflicted merge rejected (vetoed)", true, reasons.joined(separator: "; "))
        } catch { check("PR3 conflicted merge rejected (vetoed)", false, error.localizedDescription) }

        // Out-of-date version → mock returns 409 with currentVersion
        if var stale = store.item(for: pr5) {
            // Approve via Müdür first so merge is allowed, then simulate stale version by approving again as a bump.
            do {
                try await store.approve(pr5, with: mudur)
                stale = store.item(for: pr5)!
                // Bump the server-side version behind the store's back.
                let client = try accounts.client(for: mudur)
                try await client.setParticipantStatus(project: "MOB", repo: "ios-app", id: 5, userSlug: "mudur", status: .unapproved)
                try await client.setParticipantStatus(project: "MOB", repo: "ios-app", id: 5, userSlug: "mudur", status: .approved)
                _ = stale
                try await store.merge(pr5, with: mudur)
                check("stale merge rejected", false, "unexpectedly succeeded")
            } catch EMergerError.outOfDate(let v) {
                check("stale merge rejected (outOfDate)", true, "current=\(v ?? -1)")
                check("PR5 refreshed to current version after 409", store.item(for: pr5)?.pr.version == v)
            } catch { check("stale merge rejected (outOfDate)", false, error.localizedDescription) }
        }

        // Approve + merge PR5 (now at fresh version)
        do {
            try await store.approveAndMerge(pr5, approveWith: mudur, mergeWith: mudur)
            check("approveAndMerge PR5 (already approved → straight to merge)", store.item(for: pr5) == nil)
        } catch { check("approveAndMerge PR5", false, error.localizedDescription) }

        // Comment on PR4 as Geliştirici
        do {
            try await store.comment(pr4, with: dev, text: "E-Merger harness yorumu")
            check("comment PR4", (store.item(for: pr4)?.pr.properties?.commentCount ?? 0) >= 1)
        } catch { check("comment PR4", false, error.localizedDescription) }

        // CI trigger on PR1
        if let trigger = accounts.ciTriggers.first {
            do {
                try await store.triggerCI(pr1, trigger: trigger, with: mudur)
                check("CI trigger fired", true, store.lastActionMessage ?? "")
            } catch { check("CI trigger fired", false, error.localizedDescription) }
        } else {
            check("CI trigger configured", false)
        }

        // Activity log
        let actions = log.entries.prefix(12).map { "\($0.accountLabel):\($0.action):\($0.success ? "ok" : "fail")" }
        print("log (newest first):", actions)
        check("log has approve by Müdür", log.entries.contains { $0.action == "approve" && $0.accountLabel == "Müdür" && $0.success })
        check("log has merge by Müdür", log.entries.contains { $0.action == "merge" && $0.accountLabel == "Müdür" && $0.success })
        check("log has failed self-approve by Geliştirici", log.entries.contains { $0.action == "approve" && $0.accountLabel == "Geliştirici" && !$0.success })

        // Wrong token → unauthorized surfaced per account
        var bad = mudur
        bad.id = "acc-bad"; bad.label = "Bozuk"
        try? KeychainStore.saveCredential(BitbucketCredential(mode: .bearer, secret: "nope"), forAccountID: bad.id)
        try? accounts.upsert(bad, credential: nil)
        await store.refresh()
        check("bad token → accountErrors entry", store.accountErrors[bad.id]?.contains("401") == true || store.accountErrors[bad.id]?.contains("reddedildi") == true, store.accountErrors[bad.id] ?? "nil")
        accounts.remove(accountID: bad.id)

        try? KeychainStore.deleteCredential(forAccountID: "acc-mudur")
        try? KeychainStore.deleteCredential(forAccountID: "acc-dev")
        print(failures == 0 ? "\nALL PASS" : "\n\(failures) FAILURE(S)")
        exit(failures == 0 ? 0 : 1)
    }
}
