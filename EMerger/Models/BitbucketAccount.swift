//
//  BitbucketAccount.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

/// One of the user's **own** Bitbucket identities (e.g. "Müdür" and "Geliştirici"
/// accounts on the same server). The secret never lives here — it is stored in the
/// Keychain (`KeychainStore`), keyed on `id`, and is never exported or synced.
struct BitbucketAccount: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    /// Short name shown on buttons and badges, e.g. "Müdür".
    var label: String
    /// Bitbucket Server / Data Center base URL, e.g. `https://bitbucket.example.com`.
    var serverURL: String
    /// Resolved Bitbucket username (`name`) — filled by "Doğrula" or typed by hand.
    var username: String = ""
    /// Resolved display name (informational).
    var displayName: String = ""
    /// User slug used by the participants endpoint. Usually equals `username`
    /// lower-cased; the verify step fetches the real value.
    var userSlug: String = ""
    var isEnabled: Bool = true

    var baseURL: URL? {
        var text = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        guard !text.isEmpty else { return nil }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "https://" + text
        }
        return URL(string: text)
    }

    /// The slug to use on the participants endpoint.
    var effectiveSlug: String {
        userSlug.isEmpty ? username.lowercased() : userSlug
    }

    var isConfigured: Bool {
        baseURL != nil && !username.isEmpty
    }
}

/// How the account authenticates against Bitbucket.
enum AuthMode: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Bitbucket "HTTP access token" (personal access token) → `Authorization: Bearer`.
    case bearer
    /// Username + password (or token as password) → `Authorization: Basic`.
    case basic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bearer: return "HTTP access token"
        case .basic: return "Kullanıcı adı + şifre"
        }
    }
}

/// The secret half of an account. Lives only in the Keychain.
struct BitbucketCredential: Codable, Sendable {
    var mode: AuthMode
    /// Access token (bearer) or password (basic).
    var secret: String
    /// Username for basic auth (ignored for bearer).
    var basicUsername: String = ""

    var authorizationHeader: String? {
        switch mode {
        case .bearer:
            return secret.isEmpty ? nil : "Bearer \(secret)"
        case .basic:
            guard !basicUsername.isEmpty, !secret.isEmpty else { return nil }
            let raw = Data("\(basicUsername):\(secret)".utf8).base64EncodedString()
            return "Basic \(raw)"
        }
    }
}

/// A repository that is polled explicitly (in addition to each account's dashboard,
/// which only lists PRs the account participates in).
struct WatchedRepository: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var projectKey: String
    var slug: String

    var display: String { "\(projectKey)/\(slug)" }
}
