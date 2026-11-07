//
//  ReleaseSettingsView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

/// Settings › Yayın: the release chains "Yayına al" can run.
@MainActor
struct ReleasePipelinesSettingsView: View {
    @Bindable var accounts: AccountStore
    @State private var editorTarget: PipelineEditorTarget?
    @State private var pendingDelete: ReleasePipeline?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bir depo için dal zinciri ve iki hesap: ilk PR'ı **başlatan** açar, **ortak** onaylayıp merge eder; sonraki adımda roller yer değiştirir. Araç çubuğundaki **Yayına al** (⇧⌘R) zinciri seçtiğin aşamaya kadar yürütür.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                ForEach(accounts.releasePipelines) { pipeline in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(pipeline.name).bold()
                                Text(pipeline.repoDisplay)
                                    .font(.caption)
                                    .monospaced()
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(pipeline.chainDisplay) · \(MergeStrategy.title(for: pipeline.strategyId)) · \(label(pipeline.starterAccountID)) ⇄ \(label(pipeline.partnerAccountID))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        Button("Düzenle") { editorTarget = PipelineEditorTarget(pipeline: pipeline) }
                        Button(role: .destructive) {
                            pendingDelete = pipeline
                        } label: {
                            Image(systemName: "trash")
                        }
                        .help("Akışı sil")
                        .accessibilityLabel("\(pipeline.name) akışını sil")
                    }
                    .padding(.vertical, 2)
                }
                if accounts.releasePipelines.isEmpty {
                    Text("Yayın akışı yok").foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 160)

            HStack {
                Button {
                    editorTarget = PipelineEditorTarget(pipeline: nil)
                } label: {
                    Label("Akış ekle…", systemImage: "plus")
                }
                Spacer()
            }
        }
        .padding(20)
        .sheet(item: $editorTarget) { target in
            ReleasePipelineEditorView(accounts: accounts, existing: target.pipeline) {
                editorTarget = nil
            }
        }
        .confirmationDialog(
            pendingDelete.map { "\($0.name) akışı silinsin mi?" } ?? "",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { pipeline in
            Button("Akışı sil", role: .destructive) {
                accounts.removePipeline(id: pipeline.id)
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { pipeline in
            Text("\(pipeline.repoDisplay) · \(pipeline.chainDisplay). Bu geri alınamaz; depo ve dallara dokunulmaz.")
        }
    }

    private func label(_ accountID: String) -> String {
        accounts.account(id: accountID)?.label ?? "?"
    }
}

struct PipelineEditorTarget: Identifiable {
    let id = UUID()
    let pipeline: ReleasePipeline?
}

@MainActor
struct ReleasePipelineEditorView: View {
    @Bindable var accounts: AccountStore
    let existing: ReleasePipeline?
    let onDone: () -> Void

    @State private var pipeline: ReleasePipeline
    @State private var checking = false
    @State private var checkMessage: String?
    @State private var checkFailed = false

    init(accounts: AccountStore, existing: ReleasePipeline?, onDone: @escaping () -> Void) {
        self.accounts = accounts
        self.existing = existing
        self.onDone = onDone
        let template = accounts.releasePipelines.first
        let initial = existing ?? ReleasePipeline(
            name: "",
            projectKey: template?.projectKey ?? "",
            repoSlug: "",
            sourceBranch: template?.sourceBranch ?? "dev",
            stages: template?.stages.map { ReleaseStage(label: $0.label, branch: $0.branch) } ?? ReleaseStage.defaults,
            strategyId: template?.strategyId ?? MergeStrategy.ffOnly.id,
            starterAccountID: template?.starterAccountID ?? accounts.accounts.first?.id ?? "",
            partnerAccountID: template?.partnerAccountID ?? accounts.accounts.dropFirst().first?.id ?? ""
        )
        _pipeline = State(initialValue: initial)
    }

    private var canSave: Bool {
        pipeline.isValid && !pipeline.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(existing == nil ? "Yayın akışı ekle" : "Yayın akışını düzenle").font(.headline)

            Form {
                Section("Depo") {
                    TextField("Ad", text: $pipeline.name, prompt: Text("ios-app"))
                    TextField("Proje anahtarı", text: $pipeline.projectKey, prompt: Text("MOB"))
                        .autocorrectionDisabled()
                    TextField("Repo slug", text: $pipeline.repoSlug, prompt: Text("ios-app"))
                        .autocorrectionDisabled()
                }
                Section("Dal zinciri") {
                    TextField("Kaynak dal", text: $pipeline.sourceBranch, prompt: Text("dev"))
                        .autocorrectionDisabled()
                    ForEach($pipeline.stages) { $stage in
                        HStack(spacing: 8) {
                            TextField("Etiket", text: $stage.label, prompt: Text("TST"))
                                .frame(width: 90)
                            TextField("Dal", text: $stage.branch, prompt: Text("release/tst"))
                                .autocorrectionDisabled()
                            Button {
                                pipeline.stages.removeAll { $0.id == stage.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .disabled(pipeline.stages.count == 1)
                            .help("Aşamayı kaldır")
                        }
                    }
                    HStack {
                        Button {
                            pipeline.stages.append(ReleaseStage(label: "", branch: ""))
                        } label: {
                            Label("Aşama ekle", systemImage: "plus")
                        }
                        Button("Varsayılan zincir") {
                            pipeline.sourceBranch = "dev"
                            pipeline.stages = ReleaseStage.defaults.map { ReleaseStage(label: $0.label, branch: $0.branch) }
                        }
                        .help("dev → release/tst → release/uat → release/liv")
                    }
                }
                Section("Hesaplar") {
                    Picker("İlk PR'ı açan", selection: $pipeline.starterAccountID) {
                        Text("Seç…").tag("")
                        ForEach(accounts.accounts) { Text($0.label).tag($0.id) }
                    }
                    Picker("Onaylayıp merge eden", selection: $pipeline.partnerAccountID) {
                        Text("Seç…").tag("")
                        ForEach(accounts.accounts) { Text($0.label).tag($0.id) }
                    }
                    Toggle("Onaylayan hesabı PR'a gözden geçiren olarak ekle", isOn: $pipeline.addPartnerAsReviewer)
                    Text("Roller her adımda yer değiştirir: ikinci PR'ı onaylayan açar, açan onaylar. Yazar kendi PR'ını onaylayamadığı için iki farklı hesap gerekir.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Merge") {
                    Picker("Strateji", selection: $pipeline.strategyId) {
                        ForEach(MergeStrategy.all) { Text($0.title).tag($0.id) }
                    }
                    Picker("Merge kontrolü için en fazla bekle", selection: $pipeline.waitMinutes) {
                        Text("5 dakika").tag(5)
                        Text("15 dakika").tag(15)
                        Text("30 dakika").tag(30)
                        Text("1 saat").tag(60)
                        Text("2 saat").tag(120)
                    }
                    TextField("PR başlığı", text: $pipeline.titleTemplate, prompt: Text("Release {stage}: {from} → {to}"))
                    Text("Yer tutucular: " + ReleasePipeline.titlePlaceholders.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 10) {
                Button {
                    Task { await validate() }
                } label: {
                    if checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Sunucuda doğrula", systemImage: "checkmark.shield")
                    }
                }
                .disabled(checking || !pipeline.isValid)
                if let checkMessage {
                    Text(checkMessage)
                        .font(.caption)
                        .foregroundStyle(checkFailed ? .red : .green)
                        .lineLimit(3)
                }
                Spacer()
                Button("Vazgeç", action: onDone).keyboardShortcut(.cancelAction)
                Button("Kaydet", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 600)
    }

    /// Checks that every branch exists and the merge strategy is enabled, using the
    /// starter account's token.
    private func validate() async {
        checking = true
        checkFailed = false
        checkMessage = nil
        defer { checking = false }
        do {
            guard let account = accounts.account(id: pipeline.starterAccountID) else {
                throw EMergerError.release("Önce hesapları seç.")
            }
            let client = try accounts.client(for: account)
            let project = pipeline.projectKey.trimmingCharacters(in: .whitespaces)
            let repo = pipeline.repoSlug.trimmingCharacters(in: .whitespaces)
            var missing: [String] = []
            for name in [pipeline.sourceBranch] + pipeline.stages.map(\.branch) {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if try await client.branch(project: project, repo: repo, name: trimmed) == nil {
                    missing.append(trimmed)
                }
            }
            var notes: [String] = []
            if !missing.isEmpty {
                notes.append("Dal yok: " + missing.joined(separator: ", "))
            }
            if !pipeline.strategyId.isEmpty,
               let settings = try? await client.pullRequestSettings(project: project, repo: repo),
               let enabled = settings.enabledStrategyIDs,
               !enabled.contains(pipeline.strategyId) {
                notes.append("\(MergeStrategy.title(for: pipeline.strategyId)) bu depoda etkin değil (etkin: \(enabled.joined(separator: ", ")))")
            }
            checkFailed = !notes.isEmpty
            checkMessage = notes.isEmpty ? "Dallar ve merge stratejisi uygun." : notes.joined(separator: " · ")
        } catch {
            checkFailed = true
            checkMessage = error.localizedDescription
        }
    }

    private func save() {
        var copy = pipeline
        copy.name = copy.name.trimmingCharacters(in: .whitespaces)
        copy.projectKey = copy.projectKey.trimmingCharacters(in: .whitespaces)
        copy.repoSlug = copy.repoSlug.trimmingCharacters(in: .whitespaces)
        copy.sourceBranch = copy.sourceBranch.trimmingCharacters(in: .whitespaces)
        copy.stages = copy.stages.map {
            var stage = $0
            stage.branch = stage.branch.trimmingCharacters(in: .whitespaces)
            let label = stage.label.trimmingCharacters(in: .whitespaces)
            stage.label = label.isEmpty ? String(stage.branch.split(separator: "/").last ?? "").uppercased() : label
            return stage
        }
        accounts.upsert(copy)
        onDone()
    }
}
