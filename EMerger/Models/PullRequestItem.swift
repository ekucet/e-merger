//
//  PullRequestItem.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

/// How one of the user's accounts relates to a PR.
struct AccountRelation: Hashable, Sendable {
    let accountID: String
    let isAuthor: Bool
    let isReviewer: Bool
    let status: BBParticipantStatus?

    var hasApproved: Bool { status == .approved }
}

/// A pull request as seen through all of the user's accounts at once.
struct PullRequestItem: Identifiable, Hashable, Sendable {
    /// `PROJECT/repo#id`
    let id: String
    var pr: BBPullRequest
    /// Account ids whose token returned (and can therefore act on) this PR.
    var seenBy: [String]
    /// Per-account relation, keyed on account id.
    var relations: [String: AccountRelation]
    var mergeStatus: BBMergeStatus? = nil

    var repoDisplay: String { pr.toRef.repository.display }

    /// Accounts that may approve: anyone who sees the PR and is not its author
    /// and has not approved yet.
    func accountsThatCanApprove(from accounts: [BitbucketAccount]) -> [BitbucketAccount] {
        accounts.filter { account in
            guard seenBy.contains(account.id) else { return false }
            guard let rel = relations[account.id] else { return !isAuthoredBy(account) }
            return !rel.isAuthor && !rel.hasApproved
        }
    }

    /// Accounts that currently hold an approval on the PR.
    func accountsThatApproved(from accounts: [BitbucketAccount]) -> [BitbucketAccount] {
        accounts.filter { relations[$0.id]?.hasApproved == true }
    }

    /// Accounts that can attempt a merge (anyone who sees it — Bitbucket enforces
    /// the actual permission).
    func accountsThatCanMerge(from accounts: [BitbucketAccount]) -> [BitbucketAccount] {
        accounts.filter { seenBy.contains($0.id) }
    }

    func isAuthoredBy(_ account: BitbucketAccount) -> Bool {
        let author = pr.author.user
        let slug = account.effectiveSlug.lowercased()
        return author.effectiveSlug.lowercased() == slug
            || author.name.lowercased() == account.username.lowercased()
    }

    var isAuthoredByAnyOfMine: Bool {
        relations.values.contains { $0.isAuthor }
    }

    /// One of my accounts could approve this right now: it sees the PR, is not the
    /// author, has not approved — and is either a listed reviewer or the PR was
    /// opened by another of my accounts (no reviewer added yet, my other identity
    /// is the one expected to approve).
    var awaitingMyApproval: Bool {
        relations.values.contains { rel in
            seenBy.contains(rel.accountID) && !rel.isAuthor && !rel.hasApproved
                && (rel.isReviewer || isAuthoredByAnyOfMine)
        }
    }

    var isMerged: Bool { pr.state == "MERGED" }

    /// The one state the list leads with, most urgent first.
    var phase: PullRequestPhase {
        if mergeStatus?.conflicted == true { return .conflicted }
        if pr.allParticipants.contains(where: { $0.participantStatus == .needsWork }) { return .needsWork }
        if mergeStatus?.canMerge == true { return .ready }
        if awaitingMyApproval { return .awaitingMe }
        return .waiting
    }

    /// Case-insensitive match on title, repo, author, either branch; `12` or `#12` matches the id.
    func matches(search text: String) -> Bool {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        if String(pr.id) == needle || "#\(pr.id)" == needle { return true }
        return [pr.title, repoDisplay, pr.author.user.shownName, pr.author.user.name, pr.fromRef.branchName, pr.toRef.branchName]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

/// A PR's at-a-glance state in the list.
enum PullRequestPhase: Sendable {
    case conflicted
    case needsWork
    case ready
    case awaitingMe
    case waiting

    var title: String {
        switch self {
        case .conflicted: return "Çakışma"
        case .needsWork: return "Düzeltme istendi"
        case .ready: return "Hazır"
        case .awaitingMe: return "Onay"
        case .waiting: return "Bekliyor"
        }
    }

    var systemImage: String {
        switch self {
        case .conflicted: return "exclamationmark.triangle.fill"
        case .needsWork: return "wrench.adjustable.fill"
        case .ready: return "checkmark"
        case .awaitingMe: return "hand.wave.fill"
        case .waiting: return "hourglass"
        }
    }
}

/// Sidebar filter.
enum PullRequestFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case awaitingMe
    case ready
    case mine

    var id: String { rawValue }

    /// Short enough for four tiles in the narrowest sidebar.
    var title: String {
        switch self {
        case .all: return "Tümü"
        case .awaitingMe: return "Onayım"
        case .ready: return "Hazır"
        case .mine: return "Benim"
        }
    }

    var emptyTitle: String {
        switch self {
        case .all: return "Açık PR yok 🌴"
        case .awaitingMe: return "Sıra sende değil 😎"
        case .ready: return "Merge'e hazır PR yok"
        case .mine: return "Açtığın PR yok"
        }
    }

    var emptyDetail: String {
        switch self {
        case .all: return "Her şey tertemiz. Kahveni tazeleyebilirsin."
        case .awaitingMe: return "Onayını bekleyen PR kalmadı."
        case .ready: return "Onaylar tamamlanınca burada görünecekler."
        case .mine: return "Hesaplarının açtığı PR'lar burada görünür."
        }
    }

    func matches(_ item: PullRequestItem) -> Bool {
        switch self {
        case .all: return true
        case .awaitingMe: return item.awaitingMyApproval
        case .ready: return item.mergeStatus?.canMerge == true
        case .mine: return item.isAuthoredByAnyOfMine
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "tray.full"
        case .awaitingMe: return "hand.raised"
        case .ready: return "checkmark.circle"
        case .mine: return "person"
        }
    }
}
