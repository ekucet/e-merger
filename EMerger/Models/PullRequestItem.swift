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
    var buildStatuses: [BBBuildStatus] = []
    var mergeStatus: BBMergeStatus? = nil

    var repoDisplay: String { pr.toRef.repository.display }

    /// Worst-case roll-up of the latest commit's build statuses.
    var overallBuild: BBBuildState {
        let states = buildStatuses.map(\.buildState)
        if states.contains(.failed) { return .failed }
        if states.contains(.inProgress) { return .inProgress }
        if states.contains(.successful) { return .successful }
        return .unknown
    }

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

    var awaitingMyApproval: Bool {
        relations.values.contains { !$0.isAuthor && !$0.hasApproved && $0.isReviewer }
    }

    var isMerged: Bool { pr.state == "MERGED" }
}

/// Sidebar filter.
enum PullRequestFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case awaitingMe
    case ready
    case mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Tümü"
        case .awaitingMe: return "Onayımı bekleyen"
        case .ready: return "Merge'e hazır"
        case .mine: return "Benim açtıklarım"
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
