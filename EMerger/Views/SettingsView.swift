//
//  SettingsView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

/// Preferences window (⌘,): accounts, watched repositories, release chains, general.
@MainActor
struct SettingsView: View {
    @Bindable var accounts: AccountStore
    @Bindable var prs: PullRequestStore

    var body: some View {
        TabView {
            AccountsSettingsView(accounts: accounts)
                .tabItem { Label("Hesaplar", systemImage: "person.2") }
            WatchedReposSettingsView(accounts: accounts)
                .tabItem { Label("Depolar", systemImage: "folder") }
            ReleasePipelinesSettingsView(accounts: accounts)
                .tabItem { Label("Yayın", systemImage: "shippingbox") }
            GeneralSettingsView(accounts: accounts)
                .tabItem { Label("Genel", systemImage: "gearshape") }
        }
        .frame(width: 620)
        .frame(minHeight: 420)
    }
}

// MARK: - Accounts

@MainActor
struct AccountsSettingsView: View {
    @Bindable var accounts: AccountStore
    @State private var editorTarget: AccountEditorTarget?
    @State private var pendingDelete: BitbucketAccount?

    /// Release chains that stop working if `account` goes away.
    private func pipelinesUsing(_ account: BitbucketAccount) -> Int {
        accounts.releasePipelines.filter {
            $0.starterAccountID == account.id || $0.partnerAccountID == account.id
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Her hesap senin kendi Bitbucket kimliğindir (örn. Müdür ve Geliştirici). Token yalnızca bu Mac'in Keychain'inde durur; dosyaya yazılmaz, dışa aktarılmaz.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                if accounts.accounts.isEmpty {
                    Text("Henüz hesap yok. İlkini aşağıdan ekle 👇").foregroundStyle(.secondary)
                }
                ForEach(accounts.accounts) { account in
                    HStack(spacing: 10) {
                        InitialsAvatar(name: account.label, size: 26)
                        Toggle("", isOn: Binding(
                            get: { account.isEnabled },
                            set: { value in
                                var copy = account
                                copy.isEnabled = value
                                try? accounts.upsert(copy, credential: nil)
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(account.label).bold()
                                if !accounts.hasCredential(account) {
                                    Label("Token yok", systemImage: "key.slash")
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                            Text("\(account.username.isEmpty ? "kullanıcı adı yok" : account.username) · \(account.serverURL)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Düzenle") { editorTarget = AccountEditorTarget(account: account) }
                        Button(role: .destructive) {
                            pendingDelete = account
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Hesabı ve Keychain'deki token'ını sil")
                        .accessibilityLabel("\(account.label) hesabını sil")
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 180)

            HStack {
                Button {
                    editorTarget = AccountEditorTarget(account: nil)
                } label: {
                    Label("Hesap ekle…", systemImage: "plus")
                }
                Spacer()
            }
        }
        .padding(20)
        .sheet(item: $editorTarget) { target in
            AccountEditorView(accounts: accounts, existing: target.account) {
                editorTarget = nil
            }
        }
        .confirmationDialog(
            pendingDelete.map { "\($0.label) hesabı silinsin mi?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { account in
            Button("Hesabı sil", role: .destructive) {
                accounts.remove(accountID: account.id)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { account in
            let used = pipelinesUsing(account)
            Text("Keychain'deki token da silinir, bu geri alınamaz."
                 + (used > 0 ? " \(used) yayın akışı bu hesabı kullanıyor ve yeniden ayarlanması gerekecek." : ""))
        }
    }
}

struct AccountEditorTarget: Identifiable {
    let id = UUID()
    let account: BitbucketAccount?
}

// MARK: - Watched repositories

@MainActor
struct WatchedReposSettingsView: View {
    @Bindable var accounts: AccountStore
    @State private var projectKey = ""
    @State private var slug = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Her hesabın dashboard'u yalnızca o hesabın yazar / gözden geçiren olduğu PR'ları listeler. Burada eklenen depoların **tüm** açık PR'ları da çekilir.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(accounts.watchedRepos) { repo in
                    HStack {
                        Text(repo.display).monospaced()
                        Spacer()
                        Button(role: .destructive) {
                            accounts.removeWatchedRepo(id: repo.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                if accounts.watchedRepos.isEmpty {
                    Text("İzlenen depo yok").foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160)

            HStack {
                TextField("Proje anahtarı (örn. MOB)", text: $projectKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                TextField("Repo slug (örn. ios-app)", text: $slug)
                    .textFieldStyle(.roundedBorder)
                Button("Ekle") {
                    accounts.addWatchedRepo(projectKey: projectKey, slug: slug)
                    projectKey = ""
                    slug = ""
                }
                .disabled(projectKey.trimmingCharacters(in: .whitespaces).isEmpty || slug.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

// MARK: - General

@MainActor
struct GeneralSettingsView: View {
    @Bindable var accounts: AccountStore
    @AppStorage(AppSettings.refreshIntervalKey) private var refreshInterval = AppSettings.defaultRefreshInterval
    @AppStorage(AppSettings.confirmMergeKey) private var confirmMerge = true
    @AppStorage(AppSettings.notifyNewApprovalsKey) private var notifyNewApprovals = true
    @AppStorage(AppSettings.preferredMergeAccountKey) private var preferredMergeAccount = ""

    var body: some View {
        Form {
            Section("Yenileme") {
                Picker("Otomatik yenileme", selection: $refreshInterval) {
                    Text("Kapalı").tag(0)
                    Text("30 saniye").tag(30)
                    Text("1 dakika").tag(60)
                    Text("2 dakika").tag(120)
                    Text("5 dakika").tag(300)
                }
                Toggle("Onayımı bekleyen yeni PR için bildirim göster", isOn: $notifyNewApprovals)
            }
            Section("Merge") {
                Toggle("Merge etmeden önce onay iste", isOn: $confirmMerge)
                Picker("Varsayılan merge hesabı", selection: $preferredMergeAccount) {
                    Text("Otomatik (yazar olmayan ilk hesap)").tag("")
                    ForEach(accounts.accounts) { account in
                        Text(account.label).tag(account.id)
                    }
                }
            }
            Section("Veri") {
                LabeledContent("Yapılandırma") {
                    Text(AccountStore.supportDirectory.path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                Text("Token'lar bu dosyada değil, macOS Keychain'de (yalnızca bu cihaz) saklanır.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
