//
//  ReleaseRunner.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation
import Observation

enum ReleaseStepStatus: Hashable, Sendable {
    case pending
    case running(String)
    case done(String)
    case skipped(String)
    case failed(String)
    case cancelled

    var message: String? {
        switch self {
        case .pending: return nil
        case .running(let s), .done(let s), .skipped(let s), .failed(let s): return s
        case .cancelled: return "Durduruldu"
        }
    }

    var isFinished: Bool {
        switch self {
        case .done, .skipped: return true
        default: return false
        }
    }
}

struct ReleaseStepState: Identifiable, Hashable, Sendable {
    let step: ReleaseStep
    var status: ReleaseStepStatus = .pending
    var pullRequestID: Int?
    var pullRequestURL: URL?

    var id: Int { step.index }
}

enum ReleaseOutcome: Hashable, Sendable {
    case success
    case failed(String)
    case cancelled
}

/// Executes a `ReleasePipeline` hop by hop: compare branch heads → open the PR with
/// the opener account → approve with the partner → wait until Bitbucket reports it
/// mergeable → merge with the partner (fast-forward only by default) → next hop.
/// Every call is written to the `ActivityLog` with the acting account. One run at a
/// time; the run survives closing the sheet and can be cancelled.
@Observable
@MainActor
final class ReleaseRunner {
    private(set) var pipeline: ReleasePipeline?
    private(set) var targetStageIndex = 0
    private(set) var steps: [ReleaseStepState] = []
    private(set) var isRunning = false
    private(set) var outcome: ReleaseOutcome?
    private(set) var startedAt: Date?

    /// Pause between merge-check polls (tests shorten it).
    var pollInterval: Duration = .seconds(5)

    private var task: Task<Void, Never>?
    private let accounts: AccountStore
    private let log: ActivityLog
    private let prs: PullRequestStore

    init(accounts: AccountStore, log: ActivityLog, prs: PullRequestStore) {
        self.accounts = accounts
        self.log = log
        self.prs = prs
    }

    var finishedCount: Int { steps.filter { $0.status.isFinished }.count }

    var progressText: String { "\(finishedCount)/\(steps.count)" }

    /// Starts a run in the background (see `run` for the awaitable form).
    func start(_ pipeline: ReleasePipeline, upTo stageIndex: Int) {
        guard !isRunning else { return }
        task = Task { await run(pipeline, upTo: stageIndex) }
    }

    func cancel() {
        task?.cancel()
    }

    /// Forget the last run so the sheet shows a fresh plan.
    func reset() {
        guard !isRunning else { return }
        steps = []
        outcome = nil
        pipeline = nil
        startedAt = nil
    }

    @discardableResult
    func run(_ pipeline: ReleasePipeline, upTo stageIndex: Int) async -> ReleaseOutcome {
        guard !isRunning else { return .failed("Zaten bir yayın akışı çalışıyor.") }
        isRunning = true
        outcome = nil
        startedAt = Date()
        self.pipeline = pipeline
        targetStageIndex = stageIndex
        steps = pipeline.plan(upTo: stageIndex).map { ReleaseStepState(step: $0) }
        defer { isRunning = false }

        var result: ReleaseOutcome = .success
        for i in steps.indices {
            if Task.isCancelled {
                steps[i].status = .cancelled
                result = .cancelled
                break
            }
            do {
                try await runStep(at: i, pipeline: pipeline)
            } catch is CancellationError {
                steps[i].status = .cancelled
                result = .cancelled
                break
            } catch {
                steps[i].status = .failed(error.localizedDescription)
                result = .failed(error.localizedDescription)
                break
            }
        }
        outcome = result
        await prs.refresh()
        notify(result, pipeline: pipeline)
        return result
    }

    // MARK: One hop

    private func runStep(at i: Int, pipeline: ReleasePipeline) async throws {
        let step = steps[i].step
        guard let opener = accounts.account(id: step.openerAccountID),
              let approver = accounts.account(id: step.approverAccountID) else {
            throw EMergerError.release("Akıştaki hesaplardan biri artık tanımlı değil. Ayarlar › Yayın'dan düzenle.")
        }
        let openerClient = try accounts.client(for: opener)
        let approverClient = try accounts.client(for: approver)
        let project = pipeline.projectKey
        let repo = pipeline.repoSlug

        // 1. Nothing to do when the target already points at the source head.
        setStatus(i, .running("Dallar karşılaştırılıyor"))
        guard let from = try await openerClient.branch(project: project, repo: repo, name: step.fromBranch) else {
            throw EMergerError.release("Dal bulunamadı: \(step.fromBranch)")
        }
        guard let to = try await openerClient.branch(project: project, repo: repo, name: step.toBranch) else {
            throw EMergerError.release("Dal bulunamadı: \(step.toBranch)")
        }
        if let a = from.latestCommit, a == to.latestCommit {
            setStatus(i, .skipped("\(step.toBranch) zaten \(step.fromBranch) ile aynı"))
            return
        }
        try Task.checkCancellation()

        // 2. Open the PR with the opener — or adopt the open PR that already exists.
        setStatus(i, .running("PR açılıyor · \(opener.label)"))
        var pr: BBPullRequest
        var actor = approver
        var actorClient = approverClient
        do {
            pr = try await openerClient.createPullRequest(
                project: project, repo: repo,
                title: pipeline.title(for: step),
                description: "E-Merger yayın akışı · \(pipeline.chainDisplay)",
                fromBranch: step.fromBranch, toBranch: step.toBranch,
                reviewers: pipeline.addPartnerAsReviewer ? [approver.username] : []
            )
            record(opener, "open-pr", pr, success: true)
        } catch EMergerError.duplicatePullRequest(let existing) {
            pr = existing
            // The author of the existing PR cannot approve it: the other account acts.
            if existing.author.user.name.caseInsensitiveCompare(approver.username) == .orderedSame {
                actor = opener
                actorClient = openerClient
            }
            record(opener, "open-pr", pr, success: true, detail: "Açık PR zaten vardı, o kullanıldı")
        } catch EMergerError.emptyPullRequest {
            setStatus(i, .skipped("\(step.fromBranch) ile \(step.toBranch) arasında değişiklik yok"))
            return
        } catch {
            recordFailure(opener, "open-pr", step: step, error: error)
            throw error
        }
        steps[i].pullRequestID = pr.id
        steps[i].pullRequestURL = pr.webURL

        // 3. Approve with the partner (skip if that account already did).
        try Task.checkCancellation()
        let alreadyApproved = pr.allParticipants.contains {
            $0.approved && $0.user.name.caseInsensitiveCompare(actor.username) == .orderedSame
        }
        if !alreadyApproved {
            setStatus(i, .running("Onaylanıyor · \(actor.label)"))
            do {
                try await actorClient.setParticipantStatus(
                    project: project, repo: repo, id: pr.id,
                    userSlug: actor.effectiveSlug, status: .approved
                )
                record(actor, "approve", pr, success: true)
            } catch {
                recordFailure(actor, "approve", step: step, error: error, prID: pr.id)
                throw error
            }
        }

        // 4. Wait until Bitbucket's merge checks pass (builds, required reviewers…).
        let deadline = Date().addingTimeInterval(TimeInterval(max(pipeline.waitMinutes, 1)) * 60)
        var polls = 0
        var status = try await actorClient.mergeStatus(project: project, repo: repo, id: pr.id)
        while !status.canMerge {
            let vetoes = status.vetoTexts
            if status.conflicted == true {
                throw EMergerError.vetoed(vetoes.isEmpty ? ["Çakışma var"] : vetoes)
            }
            // An approval that Bitbucket refuses to count will never clear by waiting.
            if polls >= 3, !vetoes.isEmpty, vetoes.allSatisfy({ $0.localizedCaseInsensitiveContains("approv") || $0.localizedCaseInsensitiveContains("onay") }) {
                throw EMergerError.vetoed(vetoes)
            }
            guard Date() < deadline else {
                throw EMergerError.release("Bekleme süresi doldu (\(pipeline.waitMinutes) dk): " + (vetoes.isEmpty ? "merge kontrolü geçmedi" : vetoes.joined(separator: " · ")))
            }
            setStatus(i, .running("Bekleniyor · " + (vetoes.first ?? "merge kontrolü")))
            try await Task.sleep(for: pollInterval)
            polls += 1
            status = try await actorClient.mergeStatus(project: project, repo: repo, id: pr.id)
        }

        // 5. Merge with the partner.
        try Task.checkCancellation()
        setStatus(i, .running("Merge ediliyor · \(actor.label)"))
        let strategy = pipeline.strategyId.isEmpty ? nil : pipeline.strategyId
        do {
            var fresh = try await actorClient.pullRequest(project: project, repo: repo, id: pr.id)
            do {
                _ = try await actorClient.merge(project: project, repo: repo, id: pr.id, version: fresh.version, strategyId: strategy)
            } catch EMergerError.outOfDate {
                fresh = try await actorClient.pullRequest(project: project, repo: repo, id: pr.id)
                _ = try await actorClient.merge(project: project, repo: repo, id: pr.id, version: fresh.version, strategyId: strategy)
            }
            record(actor, "merge", fresh, success: true, detail: strategy.map { MergeStrategy.title(for: $0) } ?? "")
        } catch {
            recordFailure(actor, "merge", step: step, error: error, prID: pr.id)
            throw error
        }
        setStatus(i, .done("PR #\(pr.id) merge edildi · \(actor.label)"))
    }

    // MARK: Helpers

    private func setStatus(_ i: Int, _ status: ReleaseStepStatus) {
        guard steps.indices.contains(i) else { return }
        steps[i].status = status
    }

    private func record(_ account: BitbucketAccount, _ action: String, _ pr: BBPullRequest, success: Bool, detail: String = "") {
        log.record(ActivityEntry(
            accountLabel: account.label, username: account.username,
            action: action, prKey: pr.key, prTitle: pr.title, success: success, detail: detail
        ))
    }

    private func recordFailure(_ account: BitbucketAccount, _ action: String, step: ReleaseStep, error: Error, prID: Int? = nil) {
        guard let pipeline else { return }
        let key = prID.map { "\(pipeline.repoDisplay)#\($0)" } ?? pipeline.repoDisplay
        log.record(ActivityEntry(
            accountLabel: account.label, username: account.username,
            action: action, prKey: key, prTitle: "\(step.fromBranch) → \(step.toBranch)",
            success: false, detail: error.localizedDescription
        ))
    }

    private func notify(_ result: ReleaseOutcome, pipeline: ReleasePipeline) {
        let stage = pipeline.stages.indices.contains(targetStageIndex) ? pipeline.stages[targetStageIndex].label : ""
        switch result {
        case .success:
            Notifier.post(title: "Yayın tamamlandı", body: "\(pipeline.name) → \(stage)", identifier: "release-\(pipeline.id)")
        case .failed(let message):
            Notifier.post(title: "Yayın durdu: \(pipeline.name) → \(stage)", body: message, identifier: "release-\(pipeline.id)")
        case .cancelled:
            break
        }
    }
}
