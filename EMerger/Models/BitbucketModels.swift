//
//  BitbucketModels.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

// Wire models for the Bitbucket Server / Data Center REST API (`/rest/api/1.0`).
// Only the fields the app uses are declared; unknown keys are ignored by `Decodable`.

struct BBPage<T: Decodable & Sendable>: Decodable, Sendable {
    let size: Int
    let limit: Int
    let isLastPage: Bool
    let values: [T]
    let start: Int?
    let nextPageStart: Int?
}

struct BBUser: Codable, Hashable, Sendable {
    let name: String
    let slug: String?
    let displayName: String?
    let emailAddress: String?
    let id: Int?
    let active: Bool?

    var effectiveSlug: String { slug ?? name.lowercased() }
    var shownName: String { displayName ?? name }
}

struct BBProject: Codable, Hashable, Sendable {
    let key: String
    let name: String?
    let id: Int?
}

struct BBRepository: Codable, Hashable, Sendable {
    let slug: String
    let name: String?
    let id: Int?
    let project: BBProject

    var display: String { "\(project.key)/\(slug)" }
}

struct BBRef: Codable, Hashable, Sendable {
    let id: String
    let displayId: String?
    let latestCommit: String?
    let repository: BBRepository

    var branchName: String {
        if let displayId { return displayId }
        return id.replacingOccurrences(of: "refs/heads/", with: "")
    }
}

enum BBParticipantStatus: String, Codable, Sendable {
    case approved = "APPROVED"
    case unapproved = "UNAPPROVED"
    case needsWork = "NEEDS_WORK"

    var title: String {
        switch self {
        case .approved: return "Onayladı"
        case .unapproved: return "Bekliyor"
        case .needsWork: return "Düzeltme istedi"
        }
    }

    var systemImage: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .unapproved: return "circle"
        case .needsWork: return "exclamationmark.triangle.fill"
        }
    }
}

struct BBParticipant: Codable, Hashable, Sendable {
    let user: BBUser
    let role: String?
    let approved: Bool
    let status: String?

    var participantStatus: BBParticipantStatus {
        if let status, let parsed = BBParticipantStatus(rawValue: status) { return parsed }
        return approved ? .approved : .unapproved
    }
}

struct BBProperties: Codable, Hashable, Sendable {
    let openTaskCount: Int?
    let resolvedTaskCount: Int?
    let commentCount: Int?
}

struct BBLink: Codable, Hashable, Sendable {
    let href: String?
}

struct BBLinks: Codable, Hashable, Sendable {
    let selfLinks: [BBLink]?

    enum CodingKeys: String, CodingKey {
        case selfLinks = "self"
    }
}

struct BBPullRequest: Codable, Hashable, Sendable, Identifiable {
    let id: Int
    let version: Int
    let title: String
    let description: String?
    let state: String
    let open: Bool?
    let closed: Bool?
    let createdDate: Int64?
    let updatedDate: Int64?
    let fromRef: BBRef
    let toRef: BBRef
    let author: BBParticipant
    let reviewers: [BBParticipant]
    let participants: [BBParticipant]?
    let properties: BBProperties?
    let links: BBLinks?

    /// Stable identity across accounts: `PROJECT/repo#id`.
    var key: String { "\(toRef.repository.project.key)/\(toRef.repository.slug)#\(id)" }

    var projectKey: String { toRef.repository.project.key }
    var repoSlug: String { toRef.repository.slug }

    var webURL: URL? {
        guard let href = links?.selfLinks?.first?.href else { return nil }
        return URL(string: href)
    }

    var updatedAt: Date? {
        updatedDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    var createdAt: Date? {
        createdDate.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    var approvedCount: Int { reviewers.filter(\.approved).count }

    var isOpen: Bool { state == "OPEN" }

    /// Every person attached to the PR (reviewers + extra participants), deduped.
    var allParticipants: [BBParticipant] {
        var seen = Set<String>()
        var out: [BBParticipant] = []
        for p in reviewers + (participants ?? []) {
            let slug = p.user.effectiveSlug
            if seen.insert(slug).inserted { out.append(p) }
        }
        return out
    }
}

struct BBVeto: Codable, Hashable, Sendable {
    let summaryMessage: String?
    let detailedMessage: String?

    var text: String { summaryMessage ?? detailedMessage ?? "Bilinmeyen engel" }
}

struct BBMergeStatus: Codable, Hashable, Sendable {
    let canMerge: Bool
    let conflicted: Bool?
    let outcome: String?
    let vetoes: [BBVeto]?

    var vetoTexts: [String] { (vetoes ?? []).map(\.text) }
}

enum BBBuildState: String, Codable, Sendable {
    case successful = "SUCCESSFUL"
    case failed = "FAILED"
    case inProgress = "INPROGRESS"
    case unknown = "UNKNOWN"

    var title: String {
        switch self {
        case .successful: return "Başarılı"
        case .failed: return "Başarısız"
        case .inProgress: return "Çalışıyor"
        case .unknown: return "Bilinmiyor"
        }
    }

    var systemImage: String {
        switch self {
        case .successful: return "checkmark.seal.fill"
        case .failed: return "xmark.octagon.fill"
        case .inProgress: return "clock.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

struct BBBuildStatus: Codable, Hashable, Sendable {
    let state: String
    let key: String?
    let name: String?
    let url: String?
    let description: String?
    let dateAdded: Int64?

    var buildState: BBBuildState { BBBuildState(rawValue: state) ?? .unknown }
    var shownName: String { name ?? key ?? "Build" }
}

struct BBComment: Codable, Hashable, Sendable {
    let id: Int
    let text: String?
}

struct BBBranch: Decodable, Hashable, Sendable {
    let id: String
    let displayId: String?
    let latestCommit: String?
    let isDefault: Bool?

    var name: String { displayId ?? id.replacingOccurrences(of: "refs/heads/", with: "") }
}

/// `GET …/settings/pull-requests`: merge strategies and approval rules of a repository.
struct BBPullRequestSettings: Decodable, Sendable {
    struct Strategy: Decodable, Sendable {
        let id: String
        let name: String?
        let enabled: Bool?
    }
    struct MergeConfig: Decodable, Sendable {
        let defaultStrategy: Strategy?
        let strategies: [Strategy]?
    }
    let mergeConfig: MergeConfig?
    let requiredApprovers: Int?
    let requiredSuccessfulBuilds: Int?

    var enabledStrategyIDs: [String]? {
        mergeConfig?.strategies?.filter { $0.enabled == true }.map(\.id)
    }
}

/// Bitbucket's error envelope: `{"errors":[{"message":…, "currentVersion":…, "vetoes":[…]}]}`.
struct BBErrorEnvelope: Decodable, Sendable {
    struct Item: Decodable, Sendable {
        let message: String?
        let exceptionName: String?
        let currentVersion: Int?
        let expectedVersion: Int?
        let vetoes: [BBVeto]?
        /// Sent with `DuplicatePullRequestException`: the PR already open between the branches.
        let existingPullRequest: BBPullRequest?

        private enum CodingKeys: String, CodingKey {
            case message, exceptionName, currentVersion, expectedVersion, vetoes, existingPullRequest
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            message = try c.decodeIfPresent(String.self, forKey: .message)
            exceptionName = try c.decodeIfPresent(String.self, forKey: .exceptionName)
            currentVersion = try c.decodeIfPresent(Int.self, forKey: .currentVersion)
            expectedVersion = try c.decodeIfPresent(Int.self, forKey: .expectedVersion)
            vetoes = try c.decodeIfPresent([BBVeto].self, forKey: .vetoes)
            // Never let an unexpected PR shape hide the actual error message.
            existingPullRequest = try? c.decodeIfPresent(BBPullRequest.self, forKey: .existingPullRequest)
        }
    }
    let errors: [Item]
}
