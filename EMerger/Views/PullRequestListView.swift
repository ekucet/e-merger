//
//  PullRequestListView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

@MainActor
struct PullRequestListView: View {
    let items: [PullRequestItem]
    /// Items per filter, after the search text.
    let counts: [PullRequestFilter: Int]
    let searchText: String
    @Bindable var accounts: AccountStore
    @Bindable var prs: PullRequestStore
    @Binding var selectionID: String?
    @Binding var filterRaw: String
    @Binding var groupByRepo: Bool

    private var filter: PullRequestFilter {
        PullRequestFilter(rawValue: filterRaw) ?? .all
    }

    /// Consecutive runs of one repository; `ContentView` already ordered `items`.
    private var groups: [(repo: String, items: [PullRequestItem])] {
        var out: [(repo: String, items: [PullRequestItem])] = []
        for item in items {
            if out.last?.repo == item.repoDisplay {
                out[out.count - 1].items.append(item)
            } else {
                out.append((item.repoDisplay, [item]))
            }
        }
        return out
    }

    private var failingAccounts: [(account: BitbucketAccount, error: String)] {
        accounts.enabledAccounts.compactMap { account in
            prs.accountErrors[account.id].map { (account, $0) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterTiles
            if !failingAccounts.isEmpty {
                errorBanner
            }

            List(selection: $selectionID) {
                if groupByRepo {
                    ForEach(groups, id: \.repo) { group in
                        Section(group.repo) {
                            rows(group.items, showsRepo: false)
                        }
                    }
                } else {
                    rows(items, showsRepo: true)
                }
            }
            .listStyle(.sidebar)
            .overlay { emptyOverlay }

            Divider()
            footer
        }
    }

    private func rows(_ items: [PullRequestItem], showsRepo: Bool) -> some View {
        ForEach(items) { item in
            PullRequestRow(
                item: item,
                accounts: accounts.enabledAccounts,
                isBusy: prs.busy.contains(item.id),
                showsRepo: showsRepo
            )
            .tag(item.id)
            .contextMenu { contextMenu(for: item) }
        }
    }

    @ViewBuilder
    private func contextMenu(for item: PullRequestItem) -> some View {
        if let url = item.pr.webURL {
            Link("Bitbucket'ta aç", destination: url)
            Button("Bağlantıyı kopyala") { copyToPasteboard(url.absoluteString) }
        }
        Button("Dal adını kopyala") { copyToPasteboard(item.pr.fromRef.branchName) }
    }

    /// Four colored tiles: the count is the point, the filter is one click away.
    private var filterTiles: some View {
        HStack(spacing: 6) {
            ForEach(PullRequestFilter.allCases) { f in
                FilterTile(filter: f, count: counts[f, default: 0], isSelected: f == filter) {
                    filterRaw = f.rawValue
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// A dropped VPN or an expired token: say so where the list goes stale.
    private var errorBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(failingAccounts, id: \.account.id) { failure in
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(failure.account.label).font(.caption.weight(.semibold))
                        Text(failure.error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .help(failure.error)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                Button("Tekrar dene") {
                    Task { await prs.refresh() }
                }
                .disabled(prs.isRefreshing)
                SettingsLink { Text("Hesaplar…") }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if !items.isEmpty {
            EmptyView()
        } else if accounts.enabledAccounts.isEmpty {
            ContentUnavailableView("Hesap yok", systemImage: "person.crop.circle.badge.plus")
        } else if prs.lastRefresh == nil && prs.isRefreshing {
            ProgressView("PR'lar yükleniyor…")
        } else if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else if prs.items.isEmpty && !failingAccounts.isEmpty {
            ContentUnavailableView(
                "Sunucuya ulaşılamadı",
                systemImage: "network.slash",
                description: Text("VPN bağlantını ve token'larını kontrol et.")
            )
        } else {
            ContentUnavailableView(filter.emptyTitle, systemImage: filter.systemImage, description: Text(filter.emptyDetail))
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(accounts.accounts) { account in
                HStack(spacing: 7) {
                    InitialsAvatar(name: account.label, size: 18)
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(statusColor(for: account))
                                .frame(width: 7, height: 7)
                                .overlay(Circle().strokeBorder(.background, lineWidth: 1))
                                .offset(x: 2, y: 2)
                        }
                    Text(account.label).font(.caption.weight(.semibold))
                    Text(account.username.isEmpty ? "kullanıcı yok" : account.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(statusText(for: account))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            HStack(spacing: 3) {
                if let date = prs.lastRefresh {
                    Text("Son güncelleme")
                    Text(date, format: .dateTime.hour().minute())
                }
                Spacer()
                Toggle(isOn: $groupByRepo) {
                    Image(systemName: "square.stack.3d.up")
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .help("Depoya göre grupla")
                .accessibilityLabel("Depoya göre grupla")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statusColor(for account: BitbucketAccount) -> Color {
        if !account.isEnabled { return .gray }
        if prs.accountErrors[account.id] != nil { return .orange }
        if !accounts.hasCredential(account) { return .red }
        return .green
    }

    private func statusText(for account: BitbucketAccount) -> String {
        if !account.isEnabled { return "Kapalı" }
        if prs.accountErrors[account.id] != nil { return "Hata" }
        if !accounts.hasCredential(account) { return "Token yok" }
        return ""
    }
}

private struct FilterTile: View {
    let filter: PullRequestFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                Text("\(count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(filter.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(filter.tint))
            .background(
                isSelected ? AnyShapeStyle(filter.tint.gradient) : AnyShapeStyle(filter.tint.opacity(0.13)),
                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .animation(.snappy, value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filter.title), \(count) PR")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

@MainActor
struct PullRequestRow: View {
    let item: PullRequestItem
    let accounts: [BitbucketAccount]
    let isBusy: Bool
    var showsRepo = true
    @Environment(\.backgroundProminence) private var prominence

    private var phase: PullRequestPhase { item.phase }

    private var phaseText: String {
        guard phase == .awaitingMe else { return phase.title }
        let names = item.accountsThatCanApprove(from: accounts).map(\.label).joined(separator: ", ")
        return names.isEmpty ? phase.title : "\(phase.title) · \(names)"
    }

    private var authorText: String {
        if let mine = accounts.first(where: { item.isAuthoredBy($0) }) { return "\(mine.label) (sen)" }
        return item.pr.author.user.shownName
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            PhaseTile(phase: phase, isBusy: isBusy)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.pr.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(showsRepo ? "\(item.repoDisplay) #\(item.pr.id)" : "#\(item.pr.id)")
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text("·")
                    Text(authorText).lineLimit(1)
                    Spacer(minLength: 4)
                    if let date = item.pr.updatedAt {
                        Text(date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text(phaseText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(phase.tint))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    CountLabel(text: item.pr.approvalSummary, systemImage: "person.2.fill", help: "Onaylar: \(item.pr.approvalSummary)")
                    if let tasks = item.pr.properties?.openTaskCount, tasks > 0 {
                        CountLabel(text: "\(tasks)", systemImage: "checklist", help: "\(tasks) açık görev")
                    }
                    if let comments = item.pr.properties?.commentCount, comments > 0 {
                        CountLabel(text: "\(comments)", systemImage: "bubble.left.fill", help: "\(comments) yorum")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
