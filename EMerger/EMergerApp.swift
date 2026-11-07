//
//  EMergerApp.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

@main
@MainActor
struct EMergerApp: App {
    @State private var accounts: AccountStore
    @State private var log: ActivityLog
    @State private var prs: PullRequestStore
    /// Runs "Yayına al" chains (dev → release/tst → …) one hop at a time.
    @State private var releases: ReleaseRunner
    /// Sparkle auto-updater — checks the GitHub appcast on launch and offers any
    /// newer notarized build (notify + confirm, never silent). See `UpdaterView`.
    @StateObject private var updater = UpdaterController()
    @Environment(\.openWindow) private var openWindow

    /// UI strings are Turkish; dates and relative times must not fall back to the system language.
    private static let locale = Locale(identifier: "tr_TR")

    init() {
        let accounts = AccountStore()
        let log = ActivityLog()
        let prs = PullRequestStore(accounts: accounts, log: log)
        _accounts = State(initialValue: accounts)
        _log = State(initialValue: log)
        _prs = State(initialValue: prs)
        _releases = State(initialValue: ReleaseRunner(accounts: accounts, log: log, prs: prs))
    }

    var body: some Scene {
        WindowGroup("E-Merger") {
            ContentView(accounts: accounts, prs: prs, releases: releases)
                .frame(minWidth: 1040, minHeight: 640)
                .fontDesign(.rounded)
                .environment(\.locale, Self.locale)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updater.controller.updater)
            }
            CommandGroup(after: .toolbar) {
                Button("Yenile") {
                    Task { await prs.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(prs.isRefreshing)
            }
            CommandGroup(after: .windowList) {
                Button("İşlem Günlüğü") {
                    openWindow(id: "activity")
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }

        Window("İşlem Günlüğü", id: "activity") {
            ActivityLogView(log: log)
                .frame(minWidth: 760, minHeight: 400)
                .fontDesign(.rounded)
                .environment(\.locale, Self.locale)
        }

        Settings {
            SettingsView(accounts: accounts, prs: prs)
                .fontDesign(.rounded)
                .environment(\.locale, Self.locale)
        }
    }
}
