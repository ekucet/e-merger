//
//  AccountStore.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation
import Observation

/// Persisted configuration: the user's accounts, watched repositories and CI
/// triggers — everything **except** secrets, which go through `KeychainStore`.
/// Stored at `~/Library/Application Support/E-Merger/config.json`.
@Observable
@MainActor
final class AccountStore {
    private(set) var accounts: [BitbucketAccount] = []
    private(set) var watchedRepos: [WatchedRepository] = []
    private(set) var ciTriggers: [CITrigger] = []
    private(set) var releasePipelines: [ReleasePipeline] = []

    private struct Config: Codable {
        var accounts: [BitbucketAccount] = []
        var watchedRepos: [WatchedRepository] = []
        var ciTriggers: [CITrigger] = []
        var releasePipelines: [ReleasePipeline] = []

        init() {}

        /// Keys added in later versions may be missing from an older file; never
        /// let that wipe the user's accounts.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            accounts = try c.decodeIfPresent([BitbucketAccount].self, forKey: .accounts) ?? []
            watchedRepos = try c.decodeIfPresent([WatchedRepository].self, forKey: .watchedRepos) ?? []
            ciTriggers = try c.decodeIfPresent([CITrigger].self, forKey: .ciTriggers) ?? []
            releasePipelines = try c.decodeIfPresent([ReleasePipeline].self, forKey: .releasePipelines) ?? []
        }
    }

    /// `~/Library/Application Support/E-Merger`, or `$EMERGER_SUPPORT_DIR` when set
    /// (used by `tests/` so the end-to-end harness never touches the real config).
    static let supportDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["EMERGER_SUPPORT_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("E-Merger", isDirectory: true)
    }()

    private var configURL: URL { Self.supportDirectory.appendingPathComponent("config.json") }

    init() {
        load()
    }

    var enabledAccounts: [BitbucketAccount] {
        accounts.filter { $0.isEnabled && $0.isConfigured }
    }

    func account(id: String) -> BitbucketAccount? {
        accounts.first { $0.id == id }
    }

    // MARK: Accounts

    func upsert(_ account: BitbucketAccount, credential: BitbucketCredential?) throws {
        if let credential {
            try KeychainStore.saveCredential(credential, forAccountID: account.id)
        }
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
        } else {
            accounts.append(account)
        }
        save()
    }

    func remove(accountID: String) {
        accounts.removeAll { $0.id == accountID }
        try? KeychainStore.deleteCredential(forAccountID: accountID)
        save()
    }

    func credential(for account: BitbucketAccount) -> BitbucketCredential? {
        try? KeychainStore.loadCredential(forAccountID: account.id)
    }

    func hasCredential(_ account: BitbucketAccount) -> Bool {
        credential(for: account)?.authorizationHeader != nil
    }

    func client(for account: BitbucketAccount) throws -> BitbucketClient {
        guard let credential = credential(for: account) else {
            throw EMergerError.missingCredential(accountLabel: account.label)
        }
        return try BitbucketClient(account: account, credential: credential)
    }

    // MARK: Watched repos

    func addWatchedRepo(projectKey: String, slug: String) {
        let key = projectKey.trimmingCharacters(in: .whitespaces).uppercased()
        let repo = slug.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !repo.isEmpty else { return }
        guard !watchedRepos.contains(where: { $0.projectKey == key && $0.slug == repo }) else { return }
        watchedRepos.append(WatchedRepository(projectKey: key, slug: repo))
        save()
    }

    func removeWatchedRepo(id: String) {
        watchedRepos.removeAll { $0.id == id }
        save()
    }

    // MARK: CI triggers

    func upsert(_ trigger: CITrigger, secret: String?) throws {
        if let secret {
            try KeychainStore.saveCISecret(secret, forTriggerID: trigger.id)
        }
        if let idx = ciTriggers.firstIndex(where: { $0.id == trigger.id }) {
            ciTriggers[idx] = trigger
        } else {
            ciTriggers.append(trigger)
        }
        save()
    }

    func removeTrigger(id: String) {
        ciTriggers.removeAll { $0.id == id }
        try? KeychainStore.deleteCISecret(forTriggerID: id)
        save()
    }

    func triggers(for pr: BBPullRequest) -> [CITrigger] {
        ciTriggers.filter { $0.applies(to: pr) }
    }

    // MARK: Release pipelines

    func pipeline(id: String) -> ReleasePipeline? {
        releasePipelines.first { $0.id == id }
    }

    func upsert(_ pipeline: ReleasePipeline) {
        if let idx = releasePipelines.firstIndex(where: { $0.id == pipeline.id }) {
            releasePipelines[idx] = pipeline
        } else {
            releasePipelines.append(pipeline)
        }
        save()
    }

    func removePipeline(id: String) {
        releasePipelines.removeAll { $0.id == id }
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: configURL) else { return }
        if let config = try? JSONDecoder().decode(Config.self, from: data) {
            accounts = config.accounts
            watchedRepos = config.watchedRepos
            ciTriggers = config.ciTriggers
            releasePipelines = config.releasePipelines
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var config = Config()
            config.accounts = accounts
            config.watchedRepos = watchedRepos
            config.ciTriggers = ciTriggers
            config.releasePipelines = releasePipelines
            try encoder.encode(config).write(to: configURL, options: .atomic)
        } catch {
            NSLog("E-Merger: config kaydedilemedi: \(error.localizedDescription)")
        }
    }
}
