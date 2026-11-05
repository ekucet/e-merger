//
//  AccountEditorView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

/// Add / edit one of the user's own Bitbucket accounts. "Doğrula" calls
/// `whoami` with the entered secret and fills in the username / display name.
@MainActor
struct AccountEditorView: View {
    @Bindable var accounts: AccountStore
    let existing: BitbucketAccount?
    let onDone: () -> Void

    @State private var account: BitbucketAccount
    @State private var mode: AuthMode = .bearer
    @State private var secret = ""
    @State private var basicUsername = ""
    @State private var hadStoredSecret = false
    @State private var verifying = false
    @State private var verifyMessage: String?
    @State private var verifyFailed = false
    @State private var saveError: String?

    init(accounts: AccountStore, existing: BitbucketAccount?, onDone: @escaping () -> Void) {
        self.accounts = accounts
        self.existing = existing
        self.onDone = onDone
        let initial = existing ?? BitbucketAccount(
            label: "",
            serverURL: accounts.accounts.first?.serverURL ?? ""
        )
        _account = State(initialValue: initial)
        if let existing, let stored = accounts.credential(for: existing) {
            _mode = State(initialValue: stored.mode)
            _basicUsername = State(initialValue: stored.basicUsername)
            _hadStoredSecret = State(initialValue: !stored.secret.isEmpty)
        }
    }

    private var credential: BitbucketCredential? {
        guard !secret.isEmpty else { return nil }
        return BitbucketCredential(mode: mode, secret: secret, basicUsername: mode == .basic ? basicUsername : "")
    }

    private var canSave: Bool {
        !account.label.trimmingCharacters(in: .whitespaces).isEmpty
            && account.baseURL != nil
            && !account.username.trimmingCharacters(in: .whitespaces).isEmpty
            && (credential != nil || hadStoredSecret)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "Hesap ekle" : "Hesabı düzenle").font(.headline)

            Form {
                Section {
                    TextField("Etiket", text: $account.label, prompt: Text("Müdür"))
                    TextField("Sunucu", text: $account.serverURL, prompt: Text("https://sunucu.sirket.com.tr/bitbucket"))
                        .autocorrectionDisabled()
                }
                Section("Kimlik doğrulama") {
                    Picker("Yöntem", selection: $mode) {
                        ForEach(AuthMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if mode == .basic {
                        TextField("Kullanıcı adı", text: $basicUsername)
                            .autocorrectionDisabled()
                    }
                    SecureField(mode == .bearer ? "HTTP access token" : "Şifre",
                                text: $secret,
                                prompt: Text(hadStoredSecret ? "Keychain'de kayıtlı — değiştirmek için yaz" : "Bitbucket › Hesap › HTTP access tokens"))
                    HStack {
                        Button {
                            Task { await verify() }
                        } label: {
                            if verifying {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Doğrula", systemImage: "checkmark.shield")
                            }
                        }
                        .disabled(verifying || account.baseURL == nil || (credential == nil && !hadStoredSecret))
                        if let verifyMessage {
                            Text(verifyMessage)
                                .font(.caption)
                                .foregroundStyle(verifyFailed ? .red : .green)
                                .lineLimit(2)
                        }
                    }
                }
                Section("Bitbucket kullanıcısı") {
                    TextField("Kullanıcı adı", text: $account.username, prompt: Text("Doğrula ile dolar; elle de yazılabilir"))
                        .autocorrectionDisabled()
                    TextField("Slug", text: $account.userSlug, prompt: Text("Genelde kullanıcı adının küçük harfli hali"))
                        .autocorrectionDisabled()
                    if !account.displayName.isEmpty {
                        LabeledContent("Görünen ad", value: account.displayName)
                    }
                }
            }
            .formStyle(.grouped)

            if let saveError {
                Text(saveError).foregroundStyle(.red).font(.caption)
            }

            HStack {
                Spacer()
                Button("Vazgeç", action: onDone).keyboardShortcut(.cancelAction)
                Button("Kaydet", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private func verify() async {
        verifying = true
        verifyFailed = false
        verifyMessage = nil
        defer { verifying = false }
        do {
            let cred: BitbucketCredential
            if let credential {
                cred = credential
            } else if let existing, let stored = accounts.credential(for: existing) {
                cred = stored
            } else {
                throw EMergerError.missingCredential(accountLabel: account.label)
            }
            // Many servers live under a context path (…/bitbucket) and answer 503
            // at the host root; find the real root before talking to it.
            var detectedNote = ""
            if let base = account.baseURL,
               let detected = await BitbucketClient.detectBaseURL(from: base),
               detected != base {
                account.serverURL = detected.absoluteString
                detectedNote = " · sunucu kökü: \(detected.path)"
            }
            let client = try BitbucketClient(account: account, credential: cred)
            let name = try await client.whoami()
            account.username = name
            var resolved = try? await client.user(slug: name)
            if resolved == nil, name.lowercased() != name {
                resolved = try? await client.user(slug: name.lowercased())
            }
            if let user = resolved {
                account.userSlug = user.effectiveSlug
                account.displayName = user.displayName ?? ""
                account.username = user.name
            } else if account.userSlug.isEmpty {
                account.userSlug = name.lowercased()
            }
            verifyMessage = "Bağlandı: \(account.displayName.isEmpty ? account.username : account.displayName) (\(account.username))" + detectedNote
        } catch {
            verifyFailed = true
            var message = error.localizedDescription
            if case EMergerError.http(let status, _) = error, status == 503 || status == 404 {
                message += " — Bu adreste Bitbucket yok gibi; adresin sonuna alt yolu ekleyin (örn. /bitbucket) veya VPN bağlantısını kontrol edin."
            }
            verifyMessage = message
        }
    }

    private func save() {
        var copy = account
        copy.label = copy.label.trimmingCharacters(in: .whitespaces)
        copy.serverURL = copy.baseURL?.absoluteString ?? copy.serverURL
        copy.username = copy.username.trimmingCharacters(in: .whitespaces)
        copy.userSlug = copy.userSlug.trimmingCharacters(in: .whitespaces)
        do {
            var cred = credential
            if cred == nil, let existing, var stored = accounts.credential(for: existing) {
                // Keep the stored secret, but honour a changed mode / basic username.
                stored.mode = mode
                stored.basicUsername = mode == .basic ? basicUsername : ""
                cred = stored
            }
            try accounts.upsert(copy, credential: cred)
            onDone()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
