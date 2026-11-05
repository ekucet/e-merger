//
//  ReleasePipeline.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

/// A promotion chain for one repository, e.g. `dev → release/tst → release/uat →
/// release/liv`. Every hop is a pull request **opened by one of my accounts and
/// approved + merged by the other**; the two roles swap on each hop, because
/// Bitbucket never lets the author approve their own PR. "Yayına al" runs the
/// chain up to the stage the user picks, one hop after the other.
struct ReleasePipeline: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// Shown in the picker, e.g. "ios-app".
    var name: String
    var projectKey: String
    var repoSlug: String
    /// Where every release starts, e.g. `dev`.
    var sourceBranch: String = "dev"
    /// Ordered stages; each one is the target branch of a hop.
    var stages: [ReleaseStage] = ReleaseStage.defaults
    /// Bitbucket merge strategy id (`ff-only`, `ff`, `no-ff`, `squash`…); empty =
    /// the repository's default.
    var strategyId: String = MergeStrategy.ffOnly.id
    /// Opens the first PR (then approves + merges the second, opens the third…).
    var starterAccountID: String = ""
    /// Approves + merges the first PR (then opens the second…).
    var partnerAccountID: String = ""
    /// Add the approving account as reviewer when opening the PR.
    var addPartnerAsReviewer: Bool = true
    /// PR title; placeholders `{from} {to} {stage} {repo}`.
    var titleTemplate: String = "Release {stage}: {from} → {to}"
    /// How long a hop may wait for Bitbucket to report the PR mergeable (builds,
    /// required checks) before the run is abandoned.
    var waitMinutes: Int = 30

    var repoDisplay: String { "\(projectKey)/\(repoSlug)" }

    var chainDisplay: String {
        ([sourceBranch] + stages.map(\.branch)).joined(separator: " → ")
    }

    var isValid: Bool {
        !projectKey.trimmingCharacters(in: .whitespaces).isEmpty
            && !repoSlug.trimmingCharacters(in: .whitespaces).isEmpty
            && !sourceBranch.trimmingCharacters(in: .whitespaces).isEmpty
            && !stages.isEmpty
            && stages.allSatisfy { !$0.branch.trimmingCharacters(in: .whitespaces).isEmpty }
            && !starterAccountID.isEmpty
            && !partnerAccountID.isEmpty
            && starterAccountID != partnerAccountID
    }

    /// The hops needed to bring `sourceBranch` up to `stages[stageIndex]`, with the
    /// opener / approver roles alternating from the starter account.
    func plan(upTo stageIndex: Int) -> [ReleaseStep] {
        guard !stages.isEmpty else { return [] }
        let last = min(max(stageIndex, 0), stages.count - 1)
        var steps: [ReleaseStep] = []
        var from = sourceBranch
        for i in 0...last {
            let starterOpens = i.isMultiple(of: 2)
            steps.append(ReleaseStep(
                index: i,
                fromBranch: from,
                toBranch: stages[i].branch,
                stageLabel: stages[i].label,
                openerAccountID: starterOpens ? starterAccountID : partnerAccountID,
                approverAccountID: starterOpens ? partnerAccountID : starterAccountID
            ))
            from = stages[i].branch
        }
        return steps
    }

    func title(for step: ReleaseStep) -> String {
        let template = titleTemplate.trimmingCharacters(in: .whitespaces).isEmpty ? "{from} → {to}" : titleTemplate
        return template
            .replacingOccurrences(of: "{from}", with: step.fromBranch)
            .replacingOccurrences(of: "{to}", with: step.toBranch)
            .replacingOccurrences(of: "{stage}", with: step.stageLabel)
            .replacingOccurrences(of: "{repo}", with: repoSlug)
    }

    static let titlePlaceholders = ["{from}", "{to}", "{stage}", "{repo}"]
}

/// One target of the chain: a short label for the UI and the branch it maps to.
struct ReleaseStage: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var label: String
    var branch: String

    static let defaults = [
        ReleaseStage(label: "TST", branch: "release/tst"),
        ReleaseStage(label: "UAT", branch: "release/uat"),
        ReleaseStage(label: "LIV", branch: "release/liv"),
    ]
}

/// One hop of a planned run.
struct ReleaseStep: Identifiable, Hashable, Sendable {
    let index: Int
    let fromBranch: String
    let toBranch: String
    let stageLabel: String
    let openerAccountID: String
    let approverAccountID: String

    var id: Int { index }
}

/// Bitbucket Server merge strategies the user can pick for a chain.
struct MergeStrategy: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    static let ffOnly = MergeStrategy(id: "ff-only", title: "Yalnızca fast-forward")

    static let all: [MergeStrategy] = [
        ffOnly,
        MergeStrategy(id: "ff", title: "Fast-forward (mümkünse)"),
        MergeStrategy(id: "no-ff", title: "Merge commit (no-ff)"),
        MergeStrategy(id: "rebase-ff-only", title: "Rebase, yalnızca fast-forward"),
        MergeStrategy(id: "squash", title: "Squash"),
        MergeStrategy(id: "", title: "Deponun varsayılanı"),
    ]

    static func title(for id: String) -> String {
        all.first { $0.id == id }?.title ?? id
    }
}
