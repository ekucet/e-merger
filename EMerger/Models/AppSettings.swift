//
//  AppSettings.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

/// App-wide preferences in `UserDefaults` (the Settings window binds them via
/// `@AppStorage`).
enum AppSettings {
    /// Seconds between automatic refreshes; `0` disables auto-refresh.
    static let refreshIntervalKey = "EMerger.settings.refreshInterval"
    static let defaultRefreshInterval = 60

    /// Ask for confirmation before merging.
    static let confirmMergeKey = "EMerger.settings.confirmMerge"

    /// Post a macOS notification when a PR newly needs one of my approvals.
    static let notifyNewApprovalsKey = "EMerger.settings.notifyNewApprovals"

    /// Account id preferred for merges ("" = ask / first eligible).
    static let preferredMergeAccountKey = "EMerger.settings.preferredMergeAccount"

    /// After approving, run the CI trigger(s) that apply to the PR.
    static let triggerCIAfterApproveKey = "EMerger.settings.triggerCIAfterApprove"

    /// Remembered sidebar filter.
    static let filterKey = "EMerger.ui.filter"

    static var refreshInterval: Int {
        UserDefaults.standard.object(forKey: refreshIntervalKey) as? Int ?? defaultRefreshInterval
    }

    static var confirmMerge: Bool {
        UserDefaults.standard.object(forKey: confirmMergeKey) as? Bool ?? true
    }

    static var notifyNewApprovals: Bool {
        UserDefaults.standard.object(forKey: notifyNewApprovalsKey) as? Bool ?? true
    }

    static var preferredMergeAccount: String {
        UserDefaults.standard.string(forKey: preferredMergeAccountKey) ?? ""
    }

    static var triggerCIAfterApprove: Bool {
        UserDefaults.standard.object(forKey: triggerCIAfterApproveKey) as? Bool ?? false
    }
}
