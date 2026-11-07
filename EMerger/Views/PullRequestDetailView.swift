//
//  PullRequestDetailView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

/// One PR: what it is, what stands between it and a merge, and — right there — what
/// each of my accounts can do about it.
@MainActor
struct PullRequestDetailView: View {
    let item: PullRequestItem
    @Bindable var accounts: AccountStore
    @Bindable var prs: PullRequestStore

    @AppStorage(AppSettings.confirmMergeKey) private var confirmMerge = true
    @State private var mergeAccountID: String = ""
    @State private var pendingMerge: PendingMerge?
    @State private var commentText = ""
    @State private var commentAccountID = ""
    @State private var showComment = false
    @FocusState private var commentFocused: Bool

    private struct PendingMerge: Identifiable {
        let id = UUID()
        let approveWith: BitbucketAccount?
        let mergeWith: BitbucketAccount
    }

    private var enabledAccounts: [BitbucketAccount] { accounts.enabledAccounts }
    private var canApproveWith: [BitbucketAccount] { item.accountsThatCanApprove(from: enabledAccounts) }
    private var mergeCandidates: [BitbucketAccount] { item.accountsThatCanMerge(from: enabledAccounts) }
    private var isBusy: Bool { prs.busy.contains(item.id) }
    private var canMerge: Bool { item.mergeStatus?.canMerge == true }
    private var isConflicted: Bool { item.mergeStatus?.conflicted == true }

    private var mergeAccount: BitbucketAccount? {
        mergeCandidates.first { $0.id == mergeAccountID } ?? prs.defaultMergeAccount(for: item)
    }

    private var commentAccount: BitbucketAccount? {
        mergeCandidates.first { $0.id == commentAccountID } ?? mergeAccount
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                actionCard
                reviewers
                if let description = item.pr.description, !description.isEmpty {
                    SectionCard(title: "Açıklama", systemImage: "text.alignleft") {
                        Text(Self.markdown(description))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                metadata
            }
            .padding(22)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [Brand.signYellow.opacity(0.22), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 240)
                .ignoresSafeArea()
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.pr.title)
                    .font(.title.weight(.bold))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Button {
                        commentAccountID = mergeAccount?.id ?? ""
                        showComment = true
                    } label: {
                        Label("Yorum", systemImage: "bubble.left.fill")
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("Yorum yaz (⇧⌘C)")
                    .disabled(mergeCandidates.isEmpty)
                    if let url = item.pr.webURL {
                        Link(destination: url) {
                            Label("Aç", systemImage: "safari")
                        }
                        .help("Bitbucket'ta aç")
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .labelStyle(.titleAndIcon)
                .fixedSize()
            }
            HStack(spacing: 8) {
                Text("\(item.repoDisplay) #\(item.pr.id)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Brand.sky)
                BranchFlow(from: item.pr.fromRef.branchName, to: item.pr.toRef.branchName)
                    .font(.callout)
            }
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    InitialsAvatar(name: item.pr.author.user.shownName, size: 18)
                    Text(authorText)
                }
                if let date = item.pr.updatedAt {
                    Text(date, format: .relative(presentation: .named))
                }
                if let comments = item.pr.properties?.commentCount, comments > 0 {
                    CountLabel(text: "\(comments)", systemImage: "bubble.left.fill", help: "\(comments) yorum")
                }
                if let tasks = item.pr.properties?.openTaskCount, tasks > 0 {
                    CountLabel(text: "\(tasks) açık görev", systemImage: "checklist", help: "\(tasks) açık görev")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var authorText: String {
        let user = item.pr.author.user
        if let mine = myAccount(for: user) { return "\(user.shownName) · \(mine.label) hesabın" }
        return user.shownName
    }

    // MARK: Status + actions

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHero
            VStack(spacing: 8) {
                ForEach(enabledAccounts) { accountRow($0) }
            }
            .padding(14)
            Divider()
            mergeBar
                .padding(14)
        }
        .card()
        .disabled(isBusy)
    }

    private struct Hero {
        let colors: [Color]
        let systemImage: String
        let title: String
        let subtitle: String?
    }

    /// The answer to "where does this PR stand?", in one colored strip.
    private var hero: Hero {
        guard let status = item.mergeStatus else {
            return Hero(colors: [.gray, .gray.opacity(0.8)], systemImage: "ellipsis", title: "Merge durumu alınıyor…", subtitle: nil)
        }
        if status.canMerge {
            return Hero(colors: [Color(red: 0.05, green: 0.60, blue: 0.35), Color(red: 0.03, green: 0.58, blue: 0.56)],
                        systemImage: "paperplane.fill", title: "Merge'e hazır 🚀", subtitle: "Bütün kontroller geçti, son sözü sen söyle.")
        }
        if status.conflicted == true {
            return Hero(colors: [Color(red: 0.82, green: 0.15, blue: 0.20), Color(red: 0.86, green: 0.31, blue: 0.12)],
                        systemImage: "exclamationmark.triangle.fill", title: "Çakışma var 💥", subtitle: "Bitbucket'ta ya da yerelde çözülmesi gerekiyor.")
        }
        if item.awaitingMyApproval {
            return Hero(colors: [Brand.sky, Brand.skyDeep],
                        systemImage: "hand.wave.fill", title: "Sıra sende 👋", subtitle: "Bu PR onayını bekliyor.")
        }
        return Hero(colors: [Color(red: 0.80, green: 0.36, blue: 0.04), Color(red: 0.84, green: 0.50, blue: 0.02)],
                    systemImage: "hourglass", title: "Henüz hazır değil ⏳", subtitle: nil)
    }

    private var statusHero: some View {
        let hero = hero
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: hero.systemImage)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .symbolEffect(.bounce, value: hero.title)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(hero.title).font(.title3.weight(.bold))
                if let subtitle = hero.subtitle {
                    Text(subtitle).font(.callout).opacity(0.92)
                }
                ForEach(item.mergeStatus?.canMerge == true ? [] : item.mergeStatus?.vetoTexts ?? [], id: \.self) { veto in
                    Label(veto, systemImage: "minus.circle.fill")
                        .font(.callout)
                        .opacity(0.92)
                }
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                Button {
                    Task { await prs.loadMergeStatus(for: item.id) }
                } label: {
                    Image(systemName: "arrow.clockwise").fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .help("Merge durumunu yenile")
                .accessibilityLabel("Merge durumunu yenile")
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(colors: hero.colors, startPoint: .leading, endPoint: .trailing),
            in: UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.25), value: hero.title)
    }

    /// One row per account of mine: where it stands on this PR and what it can do.
    private func accountRow(_ account: BitbucketAccount) -> some View {
        let relation = item.relations[account.id]
        let sees = item.seenBy.contains(account.id)
        let isAuthor = relation?.isAuthor ?? item.isAuthoredBy(account)
        let canAct = sees && !isAuthor
        let status = relation?.status
        let isPrimaryApprove = !canMerge && !isConflicted && canApproveWith.first?.id == account.id

        return HStack(spacing: 10) {
            InitialsAvatar(name: account.label, size: 26)
            VStack(alignment: .leading, spacing: 0) {
                Text(account.label).fontWeight(.semibold)
                HStack(spacing: 4) {
                    if status == .approved || status == .needsWork, let status {
                        Image(systemName: status.systemImage).foregroundStyle(status.tint).imageScale(.small)
                    }
                    Text(accountStatusText(sees: sees, isAuthor: isAuthor, relation: relation))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
            Spacer()
            if canAct {
                if status != .approved {
                    let approve = Button {
                        run { try await prs.approve(item.id, with: account) }
                    } label: {
                        Label("Onayla", systemImage: "hand.thumbsup.fill")
                    }
                    .prominent(isPrimaryApprove)
                    .help(canApproveWith.first?.id == account.id ? "\(account.label) ile onayla (⇧⌘A)" : "\(account.label) ile onayla")

                    if canApproveWith.first?.id == account.id {
                        approve.keyboardShortcut("a", modifiers: [.command, .shift])
                    } else {
                        approve
                    }
                }
                Menu {
                    if status != .needsWork {
                        Button("Düzeltme iste") {
                            run { try await prs.setStatus(item.id, with: account, status: .needsWork) }
                        }
                    }
                    if status == .approved {
                        Button("Onayı geri al") {
                            run { try await prs.setStatus(item.id, with: account, status: .unapproved) }
                        }
                    }
                    if status == .needsWork {
                        Button("Düzeltme isteğini geri al") {
                            run { try await prs.setStatus(item.id, with: account, status: .unapproved) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("\(account.label) için diğer işlemler")
                .accessibilityLabel("\(account.label) için diğer işlemler")
            }
        }
    }

    private func accountStatusText(sees: Bool, isAuthor: Bool, relation: AccountRelation?) -> String {
        if !sees { return "Bu PR'ı göremiyor" }
        if isAuthor { return "Yazar · kendi PR'ını onaylayamaz" }
        switch relation?.status {
        case .approved: return "Onayladı"
        case .needsWork: return "Düzeltme istedi"
        default: return relation?.isReviewer == true ? "Gözden geçiren · bekliyor" : "Gözden geçiren değil · onaylayabilir"
        }
    }

    private var mergeBar: some View {
        HStack(spacing: 8) {
            if mergeCandidates.count > 1 {
                Picker("Merge hesabı", selection: $mergeAccountID) {
                    ForEach(mergeCandidates) { account in
                        Text(account.label).tag(account.id)
                    }
                }
                .fixedSize()
            }
            Spacer()
            if let approver = canApproveWith.first, let mergeWith = mergeAccount, !isConflicted {
                Button {
                    request(PendingMerge(approveWith: approver, mergeWith: mergeWith))
                } label: {
                    Label("Onayla + Merge", systemImage: "bolt.fill")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .help("\(approver.label) onaylar, merge mümkün olunca \(mergeWith.label) merge eder.")
            }
            Button {
                guard let mergeWith = mergeAccount else { return }
                request(PendingMerge(approveWith: nil, mergeWith: mergeWith))
            } label: {
                Label(mergeAccount.map { "Merge · \($0.label)" } ?? "Merge", systemImage: "arrow.triangle.merge")
            }
            .prominent(canMerge)
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(mergeAccount == nil || item.mergeStatus?.canMerge == false)
            .help(item.mergeStatus?.canMerge == false ? "Bitbucket şu anda merge'e izin vermiyor." : "Merge et (⇧⌘M)")
        }
    }

    // MARK: Sections

    private var reviewers: some View {
        SectionCard(title: "Gözden geçirenler · \(item.pr.approvalSummary)", systemImage: "person.2.fill") {
            if item.pr.allParticipants.isEmpty {
                Text("Henüz kimse atanmamış.").foregroundStyle(.secondary)
            }
            ForEach(item.pr.allParticipants, id: \.user.name) { p in
                HStack(spacing: 10) {
                    InitialsAvatar(name: p.user.shownName, size: 26)
                    Text(p.user.shownName)
                    if let mine = myAccount(for: p.user) {
                        Text(mine.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Brand.sky)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Brand.sky.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    Label(p.participantStatus.title, systemImage: p.participantStatus.systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(p.participantStatus.tint)
                }
            }
        }
    }

    private var metadata: some View {
        SectionCard(title: "Bilgiler", systemImage: "info.circle.fill") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Yazar") { Text("\(item.pr.author.user.shownName) (\(item.pr.author.user.name))") }
                row("Oluşturma") {
                    if let date = item.pr.createdAt {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    } else { Text("—") }
                }
                row("Güncelleme") {
                    if let date = item.pr.updatedAt {
                        Text(date, format: .dateTime.day().month().year().hour().minute())
                    } else { Text("—") }
                }
                if let commit = item.pr.fromRef.latestCommit {
                    row("Son commit") { Text(String(commit.prefix(10))).monospaced().textSelection(.enabled) }
                }
                row("Sürüm") { Text("v\(item.pr.version)").foregroundStyle(.secondary) }
            }
            .font(.callout)
        }
    }

    private var commentSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yorum yaz 💬").font(.title3.weight(.bold))
            TextEditor(text: $commentText)
                .font(.body)
                .focused($commentFocused)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 130)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                if mergeCandidates.count > 1 {
                    Picker("Hesap", selection: $commentAccountID) {
                        ForEach(mergeCandidates) { Text($0.label).tag($0.id) }
                    }
                    .fixedSize()
                } else if let account = commentAccount {
                    Text("\(account.label) olarak").foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button("Vazgeç") { showComment = false; commentText = "" }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                Button("Gönder") {
                    guard let account = commentAccount else { return }
                    let text = commentText
                    showComment = false
                    commentText = ""
                    run { try await prs.comment(item.id, with: account, text: text) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(BrandButtonStyle())
                .help("Gönder (⌘⏎)")
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || commentAccount == nil)
            }
        }
        .padding(20)
        .frame(width: 480)
        .fontDesign(.rounded)
        .onAppear { commentFocused = true }
    }

    // MARK: Helpers

    /// Bitbucket descriptions are Markdown; line breaks are kept, block syntax stays as written.
    private static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

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

    @ViewBuilder
    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            content()
        }
    }
}
