//
//  SettingsView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

/// Preferences window (⌘,): accounts, watched repositories, CI triggers, general.
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
            CITriggersSettingsView(accounts: accounts)
                .tabItem { Label("CI", systemImage: "play.circle") }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Her hesap senin kendi Bitbucket kimliğindir (örn. Müdür ve Geliştirici). Token yalnızca bu Mac'in Keychain'inde durur; dosyaya yazılmaz, dışa aktarılmaz.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(accounts.accounts) { account in
                    HStack(spacing: 10) {
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
                            accounts.remove(accountID: account.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Hesabı ve Keychain'deki token'ını sil")
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

// MARK: - CI triggers

@MainActor
struct CITriggersSettingsView: View {
    @Bindable var accounts: AccountStore
    @State private var editorTarget: TriggerEditorTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bir PR için CI'ı başlatan HTTP çağrısı (Jenkins `buildWithParameters`, Bamboo kuyruğu, webhook…). URL ve gövdede yer tutucular kullanılabilir: " + CITrigger.placeholders.joined(separator: " "))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(accounts.ciTriggers) { trigger in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(trigger.name).bold()
                                if !trigger.repoFilter.isEmpty {
                                    Text(trigger.repoFilter)
                                        .font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                            Text("\(trigger.method) \(trigger.urlTemplate)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Düzenle") { editorTarget = TriggerEditorTarget(trigger: trigger) }
                        Button(role: .destructive) {
                            accounts.removeTrigger(id: trigger.id)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                if accounts.ciTriggers.isEmpty {
                    Text("Tetikleyici yok — CI, Bitbucket'ın kendi webhook'larıyla başlıyorsa buna gerek yok.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160)

            HStack {
                Button {
                    editorTarget = TriggerEditorTarget(trigger: nil)
                } label: {
                    Label("Tetikleyici ekle…", systemImage: "plus")
                }
                Spacer()
            }
        }
        .padding(20)
        .sheet(item: $editorTarget) { target in
            CITriggerEditorView(accounts: accounts, existing: target.trigger) {
                editorTarget = nil
            }
        }
    }
}

struct TriggerEditorTarget: Identifiable {
    let id = UUID()
    let trigger: CITrigger?
}

@MainActor
struct CITriggerEditorView: View {
    @Bindable var accounts: AccountStore
    let existing: CITrigger?
    let onDone: () -> Void

    @State private var trigger: CITrigger
    @State private var secret = ""
    @State private var error: String?

    init(accounts: AccountStore, existing: CITrigger?, onDone: @escaping () -> Void) {
        self.accounts = accounts
        self.existing = existing
        self.onDone = onDone
        _trigger = State(initialValue: existing ?? CITrigger(name: "", urlTemplate: ""))
        if let existing, let saved = try? KeychainStore.loadCISecret(forTriggerID: existing.id) {
            _secret = State(initialValue: saved)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "Yeni CI tetikleyici" : "Tetikleyiciyi düzenle").font(.headline)
            Form {
                TextField("Ad", text: $trigger.name, prompt: Text("Jenkins iOS build"))
                TextField("URL", text: $trigger.urlTemplate, prompt: Text("https://jenkins.example.com/job/ios/buildWithParameters?token=…&BRANCH={branch}"))
                Picker("Yöntem", selection: $trigger.method) {
                    ForEach(["POST", "GET", "PUT"], id: \.self) { Text($0).tag($0) }
                }
                TextField("Repo filtresi", text: $trigger.repoFilter, prompt: Text("Boş = tüm PR'lar; ya da MOB/ios-app"))
                TextField("Content-Type", text: $trigger.contentType)
                VStack(alignment: .leading) {
                    Text("Gövde (opsiyonel)")
                    TextEditor(text: $trigger.bodyTemplate)
                        .font(.body.monospaced())
                        .frame(height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                }
                TextField("Gizli başlık adı", text: $trigger.secretHeaderName, prompt: Text("Authorization"))
                SecureField("Gizli başlık değeri (Keychain)", text: $secret, prompt: Text("Bearer … / Basic …"))
            }
            .formStyle(.grouped)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Vazgeç", action: onDone).keyboardShortcut(.cancelAction)
                Button("Kaydet") {
                    do {
                        try accounts.upsert(trigger, secret: secret)
                        onDone()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trigger.name.trimmingCharacters(in: .whitespaces).isEmpty || trigger.urlTemplate.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560)
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
    @AppStorage(AppSettings.triggerCIAfterApproveKey) private var triggerCIAfterApprove = false

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
            Section("CI") {
                Toggle("Onayladıktan sonra uygun CI tetikleyicilerini çalıştır", isOn: $triggerCIAfterApprove)
                Text("Bitbucket'ta CI onay/merge webhook'uyla zaten başlıyorsa kapalı bırak.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
