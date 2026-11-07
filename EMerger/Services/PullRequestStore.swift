//
//  PullRequestStore.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation
import Observation

/// Aggregates open pull requests across all of the user's accounts and performs
/// actions (approve / merge / comment) with the account the user picks.
/// Every action is recorded in `ActivityLog`.
@Observable
@MainActor
final class PullRequestStore {
    let accounts: AccountStore
    let log: ActivityLog

    private(set) var items: [PullRequestItem] = []
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Per-account failure of the last refresh, keyed on account id.
    private(set) var accountErrors: [String: String] = [:]
    /// PR keys with an action in flight.
    private(set) var busy: Set<String> = []
    /// Last action failure, surfaced by the UI as an alert.
    var lastActionError: String?
    /// Last action success, surfaced briefly by the UI.
    var lastActionMessage: String?
    /// Successful merges this session; the UI throws confetti when it grows.
    private(set) var mergeCount = 0

    private var autoRefreshTask: Task<Void, Never>?
    private var previousAwaiting: Set<String>?

    init(accounts: AccountStore, log: ActivityLog) {
        self.accounts = accounts
        self.log = log
    }

    func item(for key: String) -> PullRequestItem? {
        items.first { $0.id == key }
    }

    // MARK: Refresh

    /// Fetches every account's dashboard (+ watched repos), merges them by PR key
    /// and keeps each PR's last merge status. Safe to call while a refresh is running (no-op).
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let enabled = accounts.enabledAccounts
        let watched = accounts.watchedRepos
        var errors: [String: String] = [:]

        var fetched: [(account: BitbucketAccount, prs: [BBPullRequest])] = []
        await withTaskGroup(of: (BitbucketAccount, Result<[BBPullRequest], Error>).self) { group in
            for account in enabled {
                let client: BitbucketClient
                do {
                    client = try accounts.client(for: account)
                } catch {
                    errors[account.id] = error.localizedDescription
                    continue
                }
                group.addTask {
                    do {
                        var all = try await client.dashboardPullRequests()
                        // A watched repo this account cannot read must not discard its whole dashboard.
                        for repo in watched {
                            if let extra = try? await client.pullRequests(project: repo.projectKey, repo: repo.slug) {
                                all.append(contentsOf: extra)
                            }
                        }
                        return (account, .success(all))
                    } catch {
                        return (account, .failure(error))
                    }
                }
            }
            for await (account, result) in group {
                switch result {
                case .success(let prs): fetched.append((account, prs))
                case .failure(let error): errors[account.id] = error.localizedDescription
                }
            }
        }

        // Merge by key, keeping the freshest copy of each PR.
        var merged: [String: PullRequestItem] = [:]
        let previous = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        for (account, prs) in fetched {
            for pr in prs where pr.isOpen {
                let key = pr.key
                if var existing = merged[key] {
                    if pr.version > existing.pr.version || (pr.updatedDate ?? 0) > (existing.pr.updatedDate ?? 0) {
                        existing.pr = pr
                    }
                    if !existing.seenBy.contains(account.id) { existing.seenBy.append(account.id) }
                    merged[key] = existing
                } else {
                    merged[key] = PullRequestItem(id: key, pr: pr, seenBy: [account.id], relations: [:])
                }
            }
        }

        // A dashboard only lists PRs the account authors / reviews / participates in,
        // so a PR one of my accounts opened without reviewers is invisible to my other
        // account's dashboard — yet that account can open and approve it. Probe every
        // PR with each account that has not seen it; success adds the account to
        // `seenBy`, failure (no repository access) silently leaves it out.
        let probes: [(key: String, accountID: String, client: BitbucketClient)] = merged.values.flatMap { item in
            enabled.compactMap { account in
                guard !item.seenBy.contains(account.id), errors[account.id] == nil,
                      let client = try? accounts.client(for: account) else { return nil }
                return (item.id, account.id, client)
            }
        }
        if !probes.isEmpty {
            await withTaskGroup(of: (String, String, BBPullRequest?).self) { group in
                for probe in probes {
                    guard let item = merged[probe.key] else { continue }
                    let project = item.pr.toRef.repository.project.key
                    let repo = item.pr.toRef.repository.slug
                    let id = item.pr.id
                    group.addTask {
                        let pr = try? await probe.client.pullRequest(project: project, repo: repo, id: id)
                        return (probe.key, probe.accountID, pr)
                    }
                }
                for await (key, accountID, pr) in group {
                    guard let pr, pr.isOpen, var item = merged[key] else { continue }
                    if pr.version > item.pr.version { item.pr = pr }
                    if !item.seenBy.contains(accountID) { item.seenBy.append(accountID) }
                    merged[key] = item
                }
            }
        }

        // A VPN drop or an expired token says nothing about the PRs themselves: keep the
        // last known copy of whatever the failing account saw until it answers again.
        for (key, old) in previous where merged[key] == nil && old.seenBy.contains(where: { errors[$0] != nil }) {
            merged[key] = old
        }

        // Show the last known merge status while the new one loads. Merge checks can
        // change without the PR changing (a build finishing), so only an unchanged,
        // already mergeable PR skips the re-check.
        var statusKeys: [String] = []
        for key in merged.keys {
            guard var item = merged[key] else { continue }
            item.relations = Self.relations(for: item.pr, accounts: enabled)
            let old = previous[key]
            item.mergeStatus = old?.mergeStatus
            if old?.pr != item.pr || old?.mergeStatus?.canMerge != true { statusKeys.append(key) }
            merged[key] = item
        }

        items = merged.values.sorted { ($0.pr.updatedDate ?? 0) > ($1.pr.updatedDate ?? 0) }
        accountErrors = errors
        if !fetched.isEmpty { lastRefresh = Date() }
        notifyNewApprovalsIfNeeded()
        await loadMergeStatuses(for: statusKeys)
    }

    /// Fills the list's "Hazır" / "Çakışma" states without waiting for a PR to be
    /// selected, a few requests at a time: `GET …/merge` runs the server's merge checks.
    private func loadMergeStatuses(for keys: [String]) async {
        let batchSize = 4
        for start in stride(from: 0, to: keys.count, by: batchSize) {
            let batch = keys[start..<min(start + batchSize, keys.count)]
            await withTaskGroup(of: Void.self) { group in
                for key in batch {
                    group.addTask { await self.loadMergeStatus(for: key) }
                }
            }
        }
    }

    /// Re-reads one PR (and its merge status) through `account`.
    func refreshOne(_ key: String, via account: BitbucketAccount) async throws {
        guard let idx = items.firstIndex(where: { $0.id == key }) else { return }
        let client = try accounts.client(for: account)
        let pr = items[idx].pr
        let fresh = try await client.pullRequest(project: pr.projectKey, repo: pr.repoSlug, id: pr.id)
        let status = try? await client.mergeStatus(project: pr.projectKey, repo: pr.repoSlug, id: pr.id)
        guard let idx2 = items.firstIndex(where: { $0.id == key }) else { return }
        var item = items[idx2]
        item.pr = fresh
        item.relations = Self.relations(for: fresh, accounts: accounts.enabledAccounts)
        item.mergeStatus = status
        if !fresh.isOpen {
            items.remove(at: idx2)
        } else {
            items[idx2] = item
        }
    }

    func loadMergeStatus(for key: String) async {
        guard let item = item(for: key), let account = actingAccount(for: item) else { return }
        guard let client = try? accounts.client(for: account) else { return }
        let pr = item.pr
        guard let status = try? await client.mergeStatus(project: pr.projectKey, repo: pr.repoSlug, id: pr.id) else { return }
        if let idx = items.firstIndex(where: { $0.id == key }) {
            items[idx].mergeStatus = status
        }
    }

    // MARK: Actions

    func setStatus(_ key: String, with account: BitbucketAccount, status: BBParticipantStatus) async throws {
        guard let item = item(for: key) else { return }
        let action: String
        switch status {
        case .approved: action = "approve"
        case .unapproved: action = "unapprove"
        case .needsWork: action = "needs-work"
        }
        try await perform(key, logAs: action, with: account) {
            let client = try self.accounts.client(for: account)
            let pr = item.pr
            try await client.setParticipantStatus(
                project: pr.projectKey, repo: pr.repoSlug, id: pr.id,
                userSlug: account.effectiveSlug, status: status
            )
        }
        try await refreshOne(key, via: account)
        switch status {
        case .approved: lastActionMessage = "👍 \(account.label) onayladı: \(item.pr.title)"
        case .unapproved: lastActionMessage = "↩️ \(account.label) kararını geri aldı: \(item.pr.title)"
        case .needsWork: lastActionMessage = "🔧 \(account.label) düzeltme istedi: \(item.pr.title)"
        }
    }

    func approve(_ key: String, with account: BitbucketAccount) async throws {
        try await setStatus(key, with: account, status: .approved)
    }

    func merge(_ key: String, with account: BitbucketAccount, message: String? = nil) async throws {
        guard let item = item(for: key) else { return }
        do {
            try await perform(key, logAs: "merge", with: account) {
                let client = try self.accounts.client(for: account)
                let pr = item.pr
                _ = try await client.merge(project: pr.projectKey, repo: pr.repoSlug, id: pr.id, version: pr.version, message: message)
            }
        } catch EMergerError.outOfDate(let v) {
            try? await refreshOne(key, via: account)
            throw EMergerError.outOfDate(currentVersion: v)
        }
        items.removeAll { $0.id == key }
        lastActionMessage = "🤌 Mamma mia! \(account.label) merge etti: \(item.pr.title)"
        mergeCount += 1
    }

    /// Approve with one account, wait until Bitbucket reports the PR mergeable, then merge.
    func approveAndMerge(_ key: String, approveWith: BitbucketAccount, mergeWith: BitbucketAccount) async throws {
        try await approve(key, with: approveWith)
        // Merge checks (required approvals, builds) can lag a moment behind the approval.
        for attempt in 0..<8 {
            await loadMergeStatus(for: key)
            if item(for: key)?.mergeStatus?.canMerge == true { break }
            if attempt == 7 {
                let vetoes = item(for: key)?.mergeStatus?.vetoTexts ?? []
                throw EMergerError.vetoed(vetoes.isEmpty ? ["Bitbucket PR'ı henüz merge edilebilir saymıyor."] : vetoes)
            }
            try await Task.sleep(for: .seconds(1.5))
        }
        try await merge(key, with: mergeWith)
    }

    func comment(_ key: String, with account: BitbucketAccount, text: String) async throws {
        guard let item = item(for: key) else { return }
        try await perform(key, logAs: "comment", with: account) {
            let client = try self.accounts.client(for: account)
            let pr = item.pr
            try await client.comment(project: pr.projectKey, repo: pr.repoSlug, id: pr.id, text: text)
        }
        try await refreshOne(key, via: account)
        lastActionMessage = "💬 \(account.label) yorum yazdı: \(item.pr.title)"
    }

    /// Any account whose token sees the PR (for read-only calls).
    func actingAccount(for item: PullRequestItem) -> BitbucketAccount? {
        for id in item.seenBy {
            if let account = accounts.account(id: id) { return account }
        }
        return nil
    }

    /// Default account to merge with: the preferred one if it sees the PR,
    /// otherwise the first non-author account, otherwise anyone who sees it.
    func defaultMergeAccount(for item: PullRequestItem) -> BitbucketAccount? {
        let candidates = item.accountsThatCanMerge(from: accounts.enabledAccounts)
        let preferred = AppSettings.preferredMergeAccount
        if let pick = candidates.first(where: { $0.id == preferred }) { return pick }
        if let pick = candidates.first(where: { !item.isAuthoredBy($0) }) { return pick }
        return candidates.first
    }

    // MARK: Auto refresh

    func startAutoRefresh(seconds: Int) {
        autoRefreshTask?.cancel()
        guard seconds > 0 else { autoRefreshTask = nil; return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    // MARK: Internals

    private func perform(_ key: String, logAs action: String, with account: BitbucketAccount, _ work: () async throws -> Void) async throws {
        guard let item = item(for: key) else { return }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await work()
            log.record(ActivityEntry(accountLabel: account.label, username: account.username, action: action, prKey: key, prTitle: item.pr.title, success: true))
        } catch {
            log.record(ActivityEntry(accountLabel: account.label, username: account.username, action: action, prKey: key, prTitle: item.pr.title, success: false, detail: error.localizedDescription))
            throw error
        }
    }

    nonisolated static func relations(for pr: BBPullRequest, accounts: [BitbucketAccount]) -> [String: AccountRelation] {
        var out: [String: AccountRelation] = [:]
        for account in accounts {
            let slug = account.effectiveSlug.lowercased()
            let name = account.username.lowercased()
            func matches(_ user: BBUser) -> Bool {
                user.effectiveSlug.lowercased() == slug || user.name.lowercased() == name
            }
            let isAuthor = matches(pr.author.user)
            let reviewer = pr.reviewers.first { matches($0.user) }
            let participant = reviewer ?? pr.participants?.first { matches($0.user) }
            out[account.id] = AccountRelation(
                accountID: account.id,
                isAuthor: isAuthor,
                isReviewer: reviewer != nil,
                status: participant?.participantStatus
            )
        }
        return out
    }

    private func notifyNewApprovalsIfNeeded() {
        let awaiting = Set(items.filter(\.awaitingMyApproval).map(\.id))
        defer { previousAwaiting = awaiting }
        guard AppSettings.notifyNewApprovals, let previous = previousAwaiting else { return }
        let fresh = awaiting.subtracting(previous)
        guard !fresh.isEmpty else { return }
        for key in fresh {
            guard let item = item(for: key) else { continue }
            let who = item.accountsThatCanApprove(from: accounts.enabledAccounts).map(\.label).joined(separator: ", ")
            Notifier.post(
                title: "Onay bekleyen PR",
                body: "\(item.repoDisplay)#\(item.pr.id) · \(item.pr.title)" + (who.isEmpty ? "" : " — \(who)"),
                identifier: key
            )
        }
    }
}
