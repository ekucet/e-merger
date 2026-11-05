//
//  ActivityLog.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation
import Observation

/// One action the app performed on the user's behalf.
struct ActivityEntry: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var date: Date = Date()
    /// Which of the user's accounts acted (label + username).
    var accountLabel: String
    var username: String
    /// "approve", "unapprove", "needs-work", "merge", "comment", "ci-trigger"
    var action: String
    var prKey: String
    var prTitle: String
    var success: Bool
    var detail: String = ""

    var actionTitle: String {
        switch action {
        case "approve": return "Onayladı"
        case "unapprove": return "Onayı geri aldı"
        case "needs-work": return "Düzeltme istedi"
        case "merge": return "Merge etti"
        case "comment": return "Yorum yazdı"
        case "ci-trigger": return "CI tetikledi"
        case "open-pr": return "PR açtı"
        default: return action
        }
    }
}

/// Append-only local record of everything the app did, so the user can always
/// see which account did what, when. Stored as JSON Lines at
/// `~/Library/Application Support/E-Merger/activity.jsonl`.
@Observable
@MainActor
final class ActivityLog {
    private(set) var entries: [ActivityEntry] = []
    private let fileURL = AccountStore.supportDirectory.appendingPathComponent("activity.jsonl")
    private let maxEntries = 2000

    init() {
        load()
    }

    func record(_ entry: ActivityEntry) {
        entries.insert(entry, at: 0)
        if entries.count > maxEntries { entries.removeLast(entries.count - maxEntries) }
        append(entry)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let parsed = text.split(separator: "\n").compactMap { line -> ActivityEntry? in
            try? decoder.decode(ActivityEntry.self, from: Data(line.utf8))
        }
        entries = Array(parsed.reversed().prefix(maxEntries))
    }

    private func append(_ entry: ActivityEntry) {
        do {
            try FileManager.default.createDirectory(at: AccountStore.supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(entry)
            line.append(contentsOf: [0x0A])
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
                try handle.close()
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
        } catch {
            NSLog("E-Merger: işlem günlüğü yazılamadı: \(error.localizedDescription)")
        }
    }
}
