//
//  ContentView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

@MainActor
struct ContentView: View {
    @Bindable var accounts: AccountStore
    @Bindable var prs: PullRequestStore
    let releases: ReleaseRunner

    @AppStorage(AppSettings.filterKey) private var filterRaw = PullRequestFilter.all.rawValue
    @AppStorage(AppSettings.refreshIntervalKey) private var refreshInterval = AppSettings.defaultRefreshInterval
    @State private var selectionID: String?
    @State private var searchText = ""
    @State private var showError = false
    @State private var showRelease = false

    private var filter: PullRequestFilter {
        PullRequestFilter(rawValue: filterRaw) ?? .all
    }

    private var filteredItems: [PullRequestItem] {
        let enabled = accounts.enabledAccounts
        let base: [PullRequestItem]
        switch filter {
        case .all:
            base = prs.items
        case .awaitingMe:
            base = prs.items.filter { !$0.accountsThatCanApprove(from: enabled).isEmpty }
        case .ready:
            base = prs.items.filter { $0.mergeStatus?.canMerge == true || $0.pr.approvedCount > 0 }
        case .mine:
            base = prs.items.filter(\.isAuthoredByAnyOfMine)
        }
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return base }
        return base.filter {
            $0.pr.title.localizedCaseInsensitiveContains(needle)
                || $0.repoDisplay.localizedCaseInsensitiveContains(needle)
                || $0.pr.author.user.shownName.localizedCaseInsensitiveContains(needle)
                || $0.pr.fromRef.branchName.localizedCaseInsensitiveContains(needle)
                || String($0.pr.id) == needle
        }
    }

    private var selectedItem: PullRequestItem? {
        prs.items.first { $0.id == selectionID }
    }

    /// The release chain of the selected PR's repository, if one is configured.
    private var pipelineForSelection: String? {
        guard let item = selectedItem else { return nil }
        return accounts.releasePipelines.first {
            $0.projectKey.caseInsensitiveCompare(item.pr.projectKey) == .orderedSame
                && $0.repoSlug.caseInsensitiveCompare(item.pr.repoSlug) == .orderedSame
        }?.id
    }

    var body: some View {
        NavigationSplitView {
            PullRequestListView(
                items: filteredItems,
                accounts: accounts,
                prs: prs,
                selectionID: $selectionID,
                filterRaw: $filterRaw
            )
            .navigationSplitViewColumnWidth(min: 340, ideal: 400)
        } detail: {
            if accounts.enabledAccounts.isEmpty {
                noAccounts
            } else if let item = selectedItem {
                PullRequestDetailView(item: item, accounts: accounts, prs: prs)
                    .id(item.id)
            } else {
                emptyDetail
            }
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Başlık, repo, yazar, branch…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let date = prs.lastRefresh {
                    Text(date, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Button {
                    showRelease = true
                } label: {
                    if releases.isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Yayın \(releases.progressText)")
                        }
                    } else {
                        Label("Yayına al", systemImage: "shippingbox")
                    }
                }
                .help("Yayına al — dev → release/tst → … (⇧⌘R)")
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(accounts.enabledAccounts.isEmpty)
                Button {
                    Task { await prs.refresh() }
                } label: {
                    if prs.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Yenile", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(prs.isRefreshing)
                .help("Yenile (⌘R)")
            }
        }
        .task {
            Notifier.requestAuthorizationIfNeeded()
            await prs.refresh()
            prs.startAutoRefresh(seconds: refreshInterval)
        }
        .onChange(of: refreshInterval) { _, newValue in
            prs.startAutoRefresh(seconds: newValue)
        }
        .onChange(of: accounts.accounts) { _, _ in
            Task { await prs.refresh() }
        }
        .onChange(of: prs.lastActionError) { _, newValue in
            showError = newValue != nil
        }
        .alert("İşlem başarısız", isPresented: $showError, presenting: prs.lastActionError) { _ in
            Button("Tamam") { prs.lastActionError = nil }
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showRelease) {
            ReleaseFlowView(accounts: accounts, runner: releases, initialPipelineID: pipelineForSelection) {
                showRelease = false
            }
        }
    }

    private var noAccounts: some View {
        ContentUnavailableView {
            Label("Hesap yok", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text("Bitbucket hesaplarını ekle — örneğin Müdür ve Geliştirici. Token'lar yalnızca bu Mac'in Keychain'inde saklanır.")
        } actions: {
            SettingsLink {
                Text("Hesap ekle…")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView {
            Label(prs.items.isEmpty ? "Açık PR yok" : "Bir PR seç", systemImage: "arrow.triangle.merge")
        } description: {
            Text(prs.items.isEmpty
                 ? "Hesaplarının gördüğü açık pull request yok. Dashboard'da görünmeyen bir repo için Ayarlar › Depolar'dan izleme ekleyebilirsin."
                 : "Soldan bir PR seç; onaylama ve merge işlemleri burada.")
        }
    }
}
