//
//  PullRequestDetailView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

@MainActor
struct PullRequestDetailView: View {
    let item: PullRequestItem
    @Bindable var accounts: AccountStore
    @Bindable var prs: PullRequestStore

    @AppStorage(AppSettings.confirmMergeKey) private var confirmMerge = true
    @State private var mergeAccountID: String = ""
    @State private var pendingMerge: PendingMerge?
    @State private var commentText = ""
    @State private var showComment = false

    private struct PendingMerge: Identifiable {
        let id = UUID()
        let approveWith: BitbucketAccount?
        let mergeWith: BitbucketAccount
    }

    private var enabledAccounts: [BitbucketAccount] { accounts.enabledAccounts }
    private var canApproveWith: [BitbucketAccount] { item.accountsThatCanApprove(from: enabledAccounts) }
    private var approvedWith: [BitbucketAccount] { item.accountsThatApproved(from: enabledAccounts) }
    private var mergeCandidates: [BitbucketAccount] { item.accountsThatCanMerge(from: enabledAccounts) }
    private var isBusy: Bool { prs.busy.contains(item.id) }

    private var mergeAccount: BitbucketAccount? {
        mergeCandidates.first { $0.id == mergeAccountID } ?? prs.defaultMergeAccount(for: item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                actions
                metadata
                reviewers
                mergeSection
                if let description = item.pr.description, !description.isEmpty {
                    GroupBox("Açıklama") {
                        Text(description)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
        }
        .task(id: item.pr.version) {
            await prs.loadMergeStatus(for: item.id)
        }
        .onAppear {
            if mergeAccountID.isEmpty, let pick = prs.defaultMergeAccount(for: item) { mergeAccountID = pick.id }
        }
        .confirmationDialog(
            "Merge edilsin mi?",
            isPresented: Binding(get: { pendingMerge != nil }, set: { if !$0 { pendingMerge = nil } }),
            presenting: pendingMerge
        ) { pending in
            Button(pending.approveWith == nil
                   ? "Merge et · \(pending.mergeWith.label)"
                   : "Onayla (\(pending.approveWith!.label)) + Merge (\(pending.mergeWith.label))") {
                run(pending)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { pending in
            Text("\(item.repoDisplay) #\(item.pr.id)\n\(item.pr.fromRef.branchName) → \(item.pr.toRef.branchName)\n\(pending.mergeWith.label) (\(pending.mergeWith.username)) hesabıyla merge edilecek.")
        }
        .sheet(isPresented: $showComment) {
            commentSheet
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.pr.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text("\(item.repoDisplay) #\(item.pr.id)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let url = item.pr.webURL {
                    Link(destination: url) {
                        Label("Bitbucket'ta aç", systemImage: "safari")
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var actions: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    ForEach(canApproveWith) { account in
                        Button {
                            run { try await prs.approve(item.id, with: account) }
                        } label: {
                            Label("Onayla · \(account.label)", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if canApproveWith.isEmpty {
                        Label(item.isAuthoredByAnyOfMine && approvedWith.isEmpty
                              ? "Onaylayacak hesap yok (yazar kendini onaylayamaz)"
                              : "Onaylanacak hesap kalmadı",
                              systemImage: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(approvedWith) { account in
                        Menu {
                            Button("Onayı geri al") {
                                run { try await prs.setStatus(item.id, with: account, status: .unapproved) }
                            }
                            Button("Düzeltme iste") {
                                run { try await prs.setStatus(item.id, with: account, status: .needsWork) }
                            }
                        } label: {
                            Label("\(account.label) onayladı", systemImage: "checkmark.seal.fill")
                        }
                        .menuStyle(.borderedButton)
                        .fixedSize()
                    }
                    Spacer()
                    if isBusy {
                        ProgressView().controlSize(.small)
                    }
                }

                Divider()

                HStack(spacing: 8) {
                    if mergeCandidates.count > 1 {
                        Picker("Merge hesabı", selection: $mergeAccountID) {
                            ForEach(mergeCandidates) { account in
                                Text(account.label).tag(account.id)
                            }
                        }
                        .fixedSize()
                    }
                    Button {
                        guard let mergeWith = mergeAccount else { return }
                        request(PendingMerge(approveWith: nil, mergeWith: mergeWith))
                    } label: {
                        Label(mergeAccount.map { "Merge · \($0.label)" } ?? "Merge", systemImage: "arrow.triangle.merge")
                    }
                    .disabled(mergeAccount == nil || item.mergeStatus?.canMerge == false)
                    .help(item.mergeStatus?.canMerge == false ? "Bitbucket şu anda merge'e izin vermiyor (aşağıdaki engellere bak)." : "")

                    if let approver = canApproveWith.first, let mergeWith = mergeAccount {
                        Button {
                            request(PendingMerge(approveWith: approver, mergeWith: mergeWith))
                        } label: {
                            Label("Onayla + Merge", systemImage: "bolt.fill")
                        }
                        .help("\(approver.label) onaylar, merge mümkün olunca \(mergeWith.label) merge eder.")
                    }

                    Button {
                        showComment = true
                    } label: {
                        Label("Yorum", systemImage: "text.bubble")
                    }
                    .disabled(mergeCandidates.isEmpty)
                }
                .disabled(isBusy)

                if let message = prs.lastActionMessage {
                    Label(message, systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(4)
        }
    }

    private var metadata: some View {
        GroupBox("Bilgiler") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Branch") {
                    HStack(spacing: 6) {
                        Text(item.pr.fromRef.branchName).monospaced()
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        Text(item.pr.toRef.branchName).monospaced()
                    }
                }
                row("Yazar") { Text("\(item.pr.author.user.shownName) (\(item.pr.author.user.name))") }
                row("Oluşturma") {
                    if let date = item.pr.createdAt {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    } else { Text("—") }
                }
                row("Güncelleme") {
                    if let date = item.pr.updatedAt {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                            + Text("  (\(date.formatted(.relative(presentation: .named))))").foregroundStyle(.secondary)
                    } else { Text("—") }
                }
                if let commit = item.pr.fromRef.latestCommit {
                    row("Son commit") { Text(String(commit.prefix(10))).monospaced().textSelection(.enabled) }
                }
                if let props = item.pr.properties {
                    row("Yorum / görev") {
                        Text("\(props.commentCount ?? 0) yorum · \(props.openTaskCount ?? 0) açık görev")
                    }
                }
                row("Sürüm") { Text("v\(item.pr.version)").foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var reviewers: some View {
        GroupBox("Gözden geçirenler (\(item.pr.approvedCount)/\(item.pr.reviewers.count) onay)") {
            VStack(alignment: .leading, spacing: 6) {
                if item.pr.allParticipants.isEmpty {
                    Text("Atanmış gözden geçiren yok.").foregroundStyle(.secondary)
                }
                ForEach(item.pr.allParticipants, id: \.user.name) { p in
                    HStack(spacing: 8) {
                        Image(systemName: p.participantStatus.systemImage)
                            .foregroundStyle(tint(for: p.participantStatus))
                        Text(p.user.shownName)
                        Text(p.user.name).foregroundStyle(.secondary)
                        if let mine = myAccount(for: p.user) {
                            Text(mine.label)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                        }
                        Spacer()
                        Text(p.participantStatus.title)
                            .font(.caption)
                            .foregroundStyle(tint(for: p.participantStatus))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }


    private var mergeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if let status = item.mergeStatus {
                    if status.canMerge {
                        Label("Merge edilebilir", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label(status.conflicted == true ? "Çakışma var — Bitbucket'ta çözülmeli" : "Henüz merge edilemez",
                              systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        ForEach(status.vetoTexts, id: \.self) { veto in
                            Label(veto, systemImage: "minus.circle").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Merge durumu alınıyor…").foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            HStack {
                Text("Merge durumu")
                Spacer()
                Button {
                    Task { await prs.loadMergeStatus(for: item.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Merge durumunu yenile")
            }
        }
    }

    private var commentSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yorum ekle").font(.headline)
            TextEditor(text: $commentText)
                .font(.body)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            HStack {
                if let account = mergeAccount {
                    Text("\(account.label) (\(account.username)) olarak").foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button("Vazgeç") { showComment = false; commentText = "" }
                    .keyboardShortcut(.cancelAction)
                Button("Gönder") {
                    guard let account = mergeAccount else { return }
                    let text = commentText
                    showComment = false
                    commentText = ""
                    run { try await prs.comment(item.id, with: account, text: text) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || mergeAccount == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    // MARK: Helpers

    private func request(_ pending: PendingMerge) {
        if confirmMerge {
            pendingMerge = pending
        } else {
            run(pending)
        }
    }

    private func run(_ pending: PendingMerge) {
        run {
            if let approver = pending.approveWith {
                try await prs.approveAndMerge(item.id, approveWith: approver, mergeWith: pending.mergeWith)
            } else {
                try await prs.merge(item.id, with: pending.mergeWith)
            }
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        prs.lastActionMessage = nil
        Task {
            do {
                try await work()
            } catch {
                prs.lastActionError = error.localizedDescription
            }
        }
    }

    private func myAccount(for user: BBUser) -> BitbucketAccount? {
        enabledAccounts.first {
            $0.effectiveSlug.lowercased() == user.effectiveSlug.lowercased()
                || $0.username.lowercased() == user.name.lowercased()
        }
    }

    private func tint(for status: BBParticipantStatus) -> Color {
        switch status {
        case .approved: return .green
        case .unapproved: return .secondary
        case .needsWork: return .orange
        }
    }

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            content()
        }
    }
}
