//
//  Notifier.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation
import UserNotifications

/// Local macOS notifications ("a PR newly needs your approval").
enum Notifier {
    nonisolated(unsafe) private static var requested = false

    @MainActor
    static func requestAuthorizationIfNeeded() {
        guard !requested, Bundle.main.bundleIdentifier != nil else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func post(title: String, body: String, identifier: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
