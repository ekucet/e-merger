//
//  ReleaseFlowView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

/// "Yayına al" sheet: pick the repository chain and the stage to reach, see every
/// hop with the account that will act on it, press Başlat — then watch the hops
/// complete. The run keeps going if the sheet is hidden; reopening shows it.
@MainActor
struct ReleaseFlowView: View {
    @Bindable var accounts: AccountStore
    let runner: ReleaseRunner
    let onClose: () -> Void

    @AppStorage("EMerger.release.lastStage") private var lastStageIndex = 0
    @AppStorage(AppSettings.confirmMergeKey) private var confirmMerge = true
    @State private var pipelineID: String
    @State private var stageIndex: Int
    @State private var confirmFinalStage = false

    init(accounts: AccountStore, runner: ReleaseRunner, initialPipelineID: String?, onClose: @escaping () -> Void) {
        self.accounts = accounts
        self.runner = runner
        self.onClose = onClose
        let id = runner.pipeline?.id ?? initialPipelineID ?? accounts.releasePipelines.first?.id ?? ""
        _pipelineID = State(initialValue: id)
        let remembered = UserDefaults.standard.integer(forKey: "EMerger.release.lastStage")
        _stageIndex = State(initialValue: runner.pipeline != nil ? runner.targetStageIndex : remembered)
    }

    // MARK: Derived state

    private var pipeline: ReleasePipeline? {
        accounts.releasePipelines.first { $0.id == pipelineID }
    }

    private var stageCount: Int { pipeline?.stages.count ?? 0 }

    private var clampedStage: Int {
        min(max(stageIndex, 0), max(stageCount - 1, 0))
    }

    /// The runner's live steps when it is running / just ran this chain; otherwise the plan.
    private var showsRun: Bool {
        runner.pipeline?.id == pipelineID && (runner.isRunning || runner.outcome != nil)
    }

    private var displayedSteps: [ReleaseStepState] {
        if showsRun { return runner.steps }
        return pipeline?.plan(upTo: clampedStage).map { ReleaseStepState(step: $0) } ?? []
    }

    private var isFinalStage: Bool { stageCount > 0 && clampedStage == stageCount - 1 }

    private var accountsPresent: Bool {
        guard let pipeline else { return false }
        return accounts.account(id: pipeline.starterAccountID) != nil
            && accounts.account(id: pipeline.partnerAccountID) != nil
    }

    private var canStart: Bool {
        !runner.isRunning && (pipeline?.isValid ?? false) && accountsPresent
    }

    private var targetLabel: String {
        guard let pipeline, pipeline.stages.indices.contains(clampedStage) else { return "" }
        return pipeline.stages[clampedStage].label
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if accounts.releasePipelines.isEmpty {
                noPipelines
            } else {
                controls
                stepsList
                footer
            }
        }
        .padding(20)
        .frame(width: 600)
        .onChange(of: pipelineID) { _, _ in
            if !runner.isRunning { runner.reset() }
        }
        .onChange(of: stageIndex) { _, value in
            lastStageIndex = value
            if !runner.isRunning { runner.reset() }
        }
        .confirmationDialog(
            "\(targetLabel) aşamasına kadar yayınlanacak",
            isPresented: $confirmFinalStage,
            titleVisibility: .visible
        ) {
            Button("Yayınla") { start() }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            if let pipeline {
                Text("\(pipeline.repoDisplay) · \(pipeline.chainDisplay) · \(MergeStrategy.title(for: pipeline.strategyId)). Son aşama geri alınamaz.")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 30))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text("Yayına al")
                    .font(.title2.weight(.semibold))
                Text("Her adım bir PR: bir hesabın açar, diğeri onaylayıp merge eder. Adımlar sırayla, tek tuşla.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var controls: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Depo").gridColumnAlignment(.trailing)
                Picker("Depo", selection: $pipelineID) {
                    ForEach(accounts.releasePipelines) { pipeline in
                        Text("\(pipeline.name)  ·  \(pipeline.repoDisplay)").tag(pipeline.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 340, alignment: .leading)
            }
            GridRow {
                Text("Hedef")
                Picker("Hedef", selection: $stageIndex) {
                    ForEach(Array((pipeline?.stages ?? []).enumerated()), id: \.offset) { index, stage in
                        Text(stage.label).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 340)
            }
        }
        .disabled(runner.isRunning)
    }

    private var stepsList: some View {
        VStack(spacing: 0) {
            ForEach(displayedSteps) { state in
                stepRow(state)
                if state.id != displayedSteps.last?.id {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func stepRow(_ state: ReleaseStepState) -> some View {
        let step = state.step
        let opener = accounts.account(id: step.openerAccountID)?.label ?? "?"
        let approver = accounts.account(id: step.approverAccountID)?.label ?? "?"
        let note = state.status.message ?? (showsRun && runner.outcome != nil && state.status == .pending ? "Çalıştırılmadı" : nil)
        return HStack(alignment: .top, spacing: 12) {
            statusIcon(state.status)
                .frame(width: 20, height: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(step.fromBranch) → \(step.toBranch)")
                        .font(.body.weight(.medium))
                        .monospaced()
                    Text(step.stageLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text("\(opener) açar · \(approver) onaylar ve merge eder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(noteColor(state.status))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let id = state.pullRequestID {
                if let url = state.pullRequestURL {
                    Link("PR #\(id)", destination: url).font(.caption)
                } else {
                    Text("PR #\(id)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func statusIcon(_ status: ReleaseStepStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.quaternary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
        }
    }

    private func noteColor(_ status: ReleaseStepStatus) -> Color {
        switch status {
        case .failed: return .red
        case .cancelled: return .orange
        case .done: return .green
        default: return .secondary
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            summary
            Spacer()
            if runner.isRunning {
                Button("Gizle", action: onClose).keyboardShortcut(.cancelAction)
                Button("Durdur", role: .destructive) { runner.cancel() }
            } else if showsRun {
                Button("Kapat", action: onClose).keyboardShortcut(.cancelAction)
                if runner.outcome != .success {
                    Button("Yeniden dene") { start() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canStart)
                }
            } else {
                Button("Vazgeç", action: onClose).keyboardShortcut(.cancelAction)
                Button("Başlat · \(targetLabel)") { requestStart() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canStart)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if showsRun, let outcome = runner.outcome {
            switch outcome {
            case .success:
                Label("Tamamlandı · \(runner.finishedCount) adım", systemImage: "checkmark.seal.fill")
                    .font(.callout).foregroundStyle(.green)
            case .failed:
                Label("Durdu — hata adımın altında", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
            case .cancelled:
                Label("Durduruldu", systemImage: "stop.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        } else if runner.isRunning, let started = runner.startedAt {
            Text("Başladı \(started, format: .dateTime.hour().minute())")
                .font(.caption).foregroundStyle(.secondary)
        } else if let pipeline {
            Label(MergeStrategy.title(for: pipeline.strategyId), systemImage: "arrow.triangle.merge")
                .font(.caption).foregroundStyle(.secondary)
            if !accountsPresent {
                Text("Akıştaki hesaplar eksik — Ayarlar › Yayın")
                    .font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var noPipelines: some View {
        VStack(spacing: 12) {
            ContentUnavailableView {
                Label("Yayın akışı tanımlı değil", systemImage: "shippingbox")
            } description: {
                Text("Ayarlar › Yayın'dan depo, dal zinciri (dev → release/tst → release/uat → release/liv) ve iki hesabı bir kez tanımla.")
            } actions: {
                SettingsLink { Text("Ayarları aç…") }
                    .buttonStyle(.borderedProminent)
            }
            HStack {
                Spacer()
                Button("Kapat", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
    }

    // MARK: Actions

    private func requestStart() {
        if isFinalStage && confirmMerge {
            confirmFinalStage = true
        } else {
            start()
        }
    }

    private func start() {
        guard let pipeline, canStart else { return }
        runner.reset()
        runner.start(pipeline, upTo: clampedStage)
    }
}
