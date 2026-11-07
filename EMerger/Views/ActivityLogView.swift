//
//  ActivityLogView.swift
//  E-Merger
//
//  Created by Mr. t.
//

import SwiftUI

/// Every action the app performed, newest first: which account, what, on which PR.
@MainActor
struct ActivityLogView: View {
    @Bindable var log: ActivityLog
    @State private var searchText = ""
    @State private var onlyFailures = false

    private var visibleEntries: [ActivityEntry] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        return log.entries.filter { entry in
            if onlyFailures && entry.success { return false }
            guard !needle.isEmpty else { return true }
            return [entry.accountLabel, entry.username, entry.actionTitle, entry.prKey, entry.prTitle, entry.detail]
                .contains { $0.localizedCaseInsensitiveContains(needle) }
        }
    }

    var body: some View {
        Table(visibleEntries) {
            TableColumn("Zaman") { entry in
                Text(entry.date, format: .dateTime.day().month().hour().minute().second())
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 140)
            TableColumn("Hesap") { entry in
                HStack(spacing: 6) {
                    InitialsAvatar(name: entry.accountLabel, size: 18)
                    Text("\(entry.accountLabel) · \(entry.username)").lineLimit(1)
                }
            }
            .width(min: 140, ideal: 170)
            TableColumn("İşlem") { entry in
                Label(entry.actionTitle, systemImage: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(entry.success ? Color.green : Color.red)
            }
            .width(min: 120, ideal: 140)
            TableColumn("PR") { entry in
                Text("\(entry.prKey) — \(entry.prTitle)")
                    .lineLimit(1)
                    .help(entry.prTitle)
            }
            TableColumn("Detay") { entry in
                Text(entry.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(entry.detail)
            }
            .width(min: 120, ideal: 220)
        }
        .searchable(text: $searchText, prompt: "Hesap, işlem, PR…")
        .toolbar {
            Toggle(isOn: $onlyFailures) {
                Label("Yalnızca hatalar", systemImage: "exclamationmark.triangle")
            }
            .help("Yalnızca başarısız işlemleri göster")
        }
        .overlay {
            if log.entries.isEmpty {
                ContentUnavailableView("Henüz işlem yok", systemImage: "list.bullet.rectangle", description: Text("İlk onayını ver, burada görünsün."))
            } else if visibleEntries.isEmpty {
                ContentUnavailableView("Eşleşen işlem yok", systemImage: "magnifyingglass")
            }
        }
    }
}
