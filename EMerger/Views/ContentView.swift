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
    @AppStorage(AppSettings.groupByRepoKey) private var groupByRepo = false
    @AppStorage(AppSettings.refreshIntervalKey) private var refreshInterval = AppSettings.defaultRefreshInterval
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectionID: String?
    @State private var searchText = ""
    @State private var showRelease = false
    @State private var showConfetti = false

    private var filter: PullRequestFilter {
        PullRequestFilter(rawValue: filterRaw) ?? .all
    }

    private var searchedItems: [PullRequestItem] {
        prs.items.filter { $0.matches(search: searchText) }
    }

    private var counts: [PullRequestFilter: Int] {
        let searched = searchedItems
        return Dictionary(uniqueKeysWithValues: PullRequestFilter.allCases.map { f in
            (f, searched.filter(f.matches).count)
        })
    }

    private var filteredItems: [PullRequestItem] {
        let base = searchedItems.filter(filter.matches)
        guard groupByRepo else { return base }
        let byRepo = Dictionary(grouping: base, by: \.repoDisplay)
        return byRepo.keys.sorted().flatMap { byRepo[$0] ?? [] }
    }

    private var awaitingCount: Int {
        prs.items.filter(\.awaitingMyApproval).count
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
                counts: counts,
                searchText: searchText,
                accounts: accounts,
                prs: prs,
                selectionID: $selectionID,
                filterRaw: $filterRaw,
                groupByRepo: $groupByRepo
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
        .searchable(text: $searchText, placement: .sidebar, prompt: "Başlık, repo, yazar, dal, #no…")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    openWindow(id: "activity")
                } label: {
                    Label("İşlem Günlüğü", systemImage: "list.bullet.rectangle")
                }
                .help("İşlem Günlüğü (⇧⌘L)")
                Button {
                    showRelease = true
                } label: {
                    if releases.isRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Yayın \(releases.progressText)")
                        }
                    } else {
                        Label("Yayına al", systemImage: "airplane.departure")
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
        .overlay {
            if showConfetti {
                ConfettiView()
            }
        }
        .overlay(alignment: .bottom) {
            if let message = prs.lastActionMessage {
                ToastView(message: message)
                    .padding(.bottom, 20)
                    .padding(.horizontal, 40)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: prs.lastActionMessage)
        .task {
            Notifier.requestAuthorizationIfNeeded()
            await prs.refresh()
            prs.startAutoRefresh(seconds: refreshInterval)
        }
        .task(id: prs.lastActionMessage) {
            guard let message = prs.lastActionMessage else { return }
            AccessibilityNotification.Announcement(message).post()
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { prs.lastActionMessage = nil }
        }
        .task(id: prs.mergeCount) {
            guard prs.mergeCount > 0, !reduceMotion else { return }
            showConfetti = true
            try? await Task.sleep(for: .seconds(ConfettiView.duration))
            if !Task.isCancelled { showConfetti = false }
        }
        .onChange(of: refreshInterval) { _, newValue in
            prs.startAutoRefresh(seconds: newValue)
        }
        .onChange(of: accounts.accounts) { _, _ in
            Task { await prs.refresh() }
        }
        .onChange(of: filteredItems.map(\.id)) { old, new in
            advanceSelection(from: old, to: new)
        }
        .onChange(of: awaitingCount, initial: true) { _, count in
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
        .alert(
            "İşlem başarısız",
            isPresented: Binding(
                get: { prs.lastActionError != nil },
                set: { if !$0 { prs.lastActionError = nil } }
            ),
            presenting: prs.lastActionError
        ) { _ in
            Button("Tamam") {}
        } message: { message in
            Text(message)
        }
        .sheet(isPresented: $showRelease) {
            ReleaseFlowView(accounts: accounts, runner: releases, initialPipelineID: pipelineForSelection) {
                showRelease = false
            }
        }
    }

    /// When the selected PR leaves (merged, closed), move to its neighbour so the next
    /// one is ready to review. A filter change keeps the selection.
    private func advanceSelection(from old: [String], to new: [String]) {
        guard let selectionID, !prs.items.contains(where: { $0.id == selectionID }),
              let index = old.firstIndex(of: selectionID) else { return }
        self.selectionID = new.indices.contains(index) ? new[index] : new.last
    }

    private var noAccounts: some View {
        ContentUnavailableView {
            Mascot()
            Text("Merhaba! 👋")
        } description: {
            Text("Bitbucket hesaplarını ekle — örneğin Müdür ve Geliştirici. Token'lar yalnızca bu Mac'in Keychain'inde saklanır.")
        } actions: {
            SettingsLink {
                Text("Hesap ekle…")
            }
            .buttonStyle(BrandButtonStyle())
        }
    }

    @ViewBuilder
    private var emptyDetail: some View {
        if prs.items.isEmpty && prs.lastRefresh == nil && prs.isRefreshing {
            ContentUnavailableView {
                Mascot()
                Text("PR'lar toplanıyor…")
            }
        } else if prs.items.isEmpty && !prs.accountErrors.isEmpty {
            ContentUnavailableView(
                "Sunucuya ulaşılamadı",
                systemImage: "network.slash",
                description: Text("Soldaki uyarıda hangi hesabın bağlanamadığı yazıyor. VPN'i ve token'ları kontrol et.")
            )
        } else if prs.items.isEmpty {
            ContentUnavailableView {
                Mascot()
                Text("Her şey tertemiz 🌴")
            } description: {
                Text("Hesaplarının gördüğü açık PR yok. Dashboard'da görünmeyen bir repo için Ayarlar › Depolar'dan izleme ekleyebilirsin.")
            }
        } else {
            ContentUnavailableView {
                Mascot()
                Text(awaitingCount > 0 ? "\(awaitingCount) PR seni bekliyor 👀" : "Bir PR seç")
            } description: {
                Text("Soldan bir PR seç; onaylama ve merge işlemleri burada.")
            }
        }
    }
}
