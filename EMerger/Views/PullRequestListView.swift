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
    @Bindable var accounts: AccountStore
    @Bindable var prs: PullRequestStore
    @Binding var selectionID: String?
    @Binding var filterRaw: String

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filtre", selection: $filterRaw) {
                ForEach(PullRequestFilter.allCases) { f in
                    Text(f.title).tag(f.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            List(selection: $selectionID) {
                ForEach(items) { item in
                    PullRequestRow(item: item, accounts: accounts.enabledAccounts, isBusy: prs.busy.contains(item.id))
                        .tag(item.id)
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if items.isEmpty && !prs.isRefreshing {
                    Text("Bu filtrede PR yok")
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            accountStrip
        }
    }

    private var accountStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            if accounts.accounts.isEmpty {
                Text("Hesap tanımlı değil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(accounts.accounts) { account in
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor(for: account))
                        .frame(width: 7, height: 7)
                    Text(account.label).font(.caption).bold()
                    Text(account.username.isEmpty ? "kullanıcı yok" : account.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    if let error = prs.accountErrors[account.id] {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help(error)
                    }
                }
            }
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
}

@MainActor
struct PullRequestRow: View {
    let item: PullRequestItem
    let accounts: [BitbucketAccount]
    let isBusy: Bool

    private var canApproveWith: [BitbucketAccount] { item.accountsThatCanApprove(from: accounts) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(item.pr.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 4)
                if isBusy {
                    ProgressView().controlSize(.mini)
                }
            }
            HStack(spacing: 6) {
                Text("\(item.repoDisplay) #\(item.pr.id)")
                    .foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text(item.pr.author.user.shownName)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let date = item.pr.updatedAt {
                    Text("·").foregroundStyle(.tertiary)
                    Text(date, format: .relative(presentation: .named))
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
            HStack(spacing: 6) {
                badge(
                    text: "\(item.pr.approvedCount)/\(item.pr.reviewers.count)",
                    systemImage: "person.2",
                    tint: item.pr.approvedCount == 0 ? .secondary : .green
                )
                if item.mergeStatus?.conflicted == true {
                    badge(text: "Çakışma", systemImage: "exclamationmark.triangle", tint: .red)
                } else if item.mergeStatus?.canMerge == true {
                    badge(text: "Hazır", systemImage: "checkmark.circle", tint: .green)
                }
                if !canApproveWith.isEmpty {
                    badge(text: "Onay: " + canApproveWith.map(\.label).joined(separator: ", "), systemImage: "hand.raised", tint: .orange)
                }
                if item.isAuthoredByAnyOfMine {
                    badge(text: "Benim", systemImage: "person", tint: .blue)
                }
            }
            .font(.caption2)
        }
        .padding(.vertical, 3)
    }

    private func badge(text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
