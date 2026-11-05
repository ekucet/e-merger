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

    var body: some View {
        Table(log.entries) {
            TableColumn("Zaman") { entry in
                Text(entry.date, format: .dateTime.day().month().hour().minute().second())
                    .monospacedDigit()
            }
            .width(min: 120, ideal: 140)
            TableColumn("Hesap") { entry in
                Text("\(entry.accountLabel) · \(entry.username)")
            }
            .width(min: 120, ideal: 160)
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
        .overlay {
            if log.entries.isEmpty {
                ContentUnavailableView("Henüz işlem yok", systemImage: "list.bullet.rectangle")
            }
        }
    }
}
