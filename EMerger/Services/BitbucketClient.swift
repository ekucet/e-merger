//
//  BitbucketClient.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

/// Thin client for the Bitbucket Server / Data Center REST API, bound to one
/// account's base URL + credential. Value type, `Sendable`, safe to use from any
/// task.
struct BitbucketClient: Sendable {
    let baseURL: URL
    let accountLabel: String
    private let authorization: String
    private let session: URLSession

    private static let apiRoot = "/rest/api/1.0"
    private static let pageLimit = 100
    private static let maxPages = 20

    init(account: BitbucketAccount, credential: BitbucketCredential) throws {
        guard let url = account.baseURL else {
            throw EMergerError.invalidServerURL(account.serverURL)
        }
        guard let header = credential.authorizationHeader else {
            throw EMergerError.missingCredential(accountLabel: account.label)
        }
        self.baseURL = url
        self.accountLabel = account.label
        self.authorization = header
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpAdditionalHeaders = [
            "Accept": "application/json",
            // Bitbucket's XSRF filter rejects state-changing requests from
            // non-browser clients without this header.
            "X-Atlassian-Token": "no-check",
            "User-Agent": "E-Merger/1.0 (macOS)",
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: Identity

    /// The username behind the credential (plain text from the applinks servlet).
    func whoami() async throws -> String {
        let (data, _) = try await request("GET", path: "/plugins/servlet/applinks/whoami", accept: "text/plain")
        let name = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("<") else {
            throw EMergerError.decoding("whoami boş veya HTML döndü (SSO yönlendirmesi olabilir)")
        }
        return name
    }

    func user(slug: String) async throws -> BBUser {
        try await getJSON(BBUser.self, path: "\(Self.apiRoot)/users/\(slug.pathEncoded)")
    }

    // MARK: Pull requests

    /// Open PRs where this account is author / reviewer / participant.
    func dashboardPullRequests(role: String? = nil) async throws -> [BBPullRequest] {
        var query = [URLQueryItem(name: "state", value: "OPEN")]
        if let role { query.append(URLQueryItem(name: "role", value: role)) }
        return try await paged(path: "\(Self.apiRoot)/dashboard/pull-requests", query: query)
    }

    /// Every open PR of one repository.
    func pullRequests(project: String, repo: String) async throws -> [BBPullRequest] {
        try await paged(
            path: "\(Self.apiRoot)/projects/\(project.pathEncoded)/repos/\(repo.pathEncoded)/pull-requests",
            query: [URLQueryItem(name: "state", value: "OPEN")]
        )
    }

    func pullRequest(project: String, repo: String, id: Int) async throws -> BBPullRequest {
        try await getJSON(BBPullRequest.self, path: prPath(project, repo, id))
    }

    func mergeStatus(project: String, repo: String, id: Int) async throws -> BBMergeStatus {
        try await getJSON(BBMergeStatus.self, path: prPath(project, repo, id) + "/merge")
    }

    /// Merge; `version` is Bitbucket's optimistic lock (the PR's current `version`).
    func merge(project: String, repo: String, id: Int, version: Int, message: String? = nil) async throws -> BBPullRequest {
        var body: [String: Any] = ["version": version]
        if let message, !message.isEmpty { body["message"] = message }
        let data = try await requestJSON(
            "POST",
            path: prPath(project, repo, id) + "/merge",
            query: [URLQueryItem(name: "version", value: String(version))],
            body: body
        )
        return try decode(BBPullRequest.self, from: data)
    }

    /// Approve / un-approve / needs-work as `userSlug` (must be the token's own user).
    @discardableResult
    func setParticipantStatus(project: String, repo: String, id: Int, userSlug: String, status: BBParticipantStatus) async throws -> BBParticipant {
        let data = try await requestJSON(
            "PUT",
            path: prPath(project, repo, id) + "/participants/\(userSlug.pathEncoded)",
            body: ["status": status.rawValue]
        )
        return try decode(BBParticipant.self, from: data)
    }

    @discardableResult
    func comment(project: String, repo: String, id: Int, text: String) async throws -> BBComment {
        let data = try await requestJSON("POST", path: prPath(project, repo, id) + "/comments", body: ["text": text])
        return try decode(BBComment.self, from: data)
    }

    // MARK: Builds

    func buildStatuses(commit: String) async throws -> [BBBuildStatus] {
        let (data, _) = try await request("GET", path: "/rest/build-status/1.0/commits/\(commit.pathEncoded)")
        return try decode(BBPage<BBBuildStatus>.self, from: data).values
    }

    // MARK: Internals

    private func prPath(_ project: String, _ repo: String, _ id: Int) -> String {
        "\(Self.apiRoot)/projects/\(project.pathEncoded)/repos/\(repo.pathEncoded)/pull-requests/\(id)"
    }

    private func paged<T: Decodable & Sendable>(path: String, query: [URLQueryItem]) async throws -> [T] {
        var out: [T] = []
        var start = 0
        for _ in 0..<Self.maxPages {
            var q = query
            q.append(URLQueryItem(name: "limit", value: String(Self.pageLimit)))
            q.append(URLQueryItem(name: "start", value: String(start)))
            let (data, _) = try await request("GET", path: path, query: q)
            let page = try decode(BBPage<T>.self, from: data)
            out.append(contentsOf: page.values)
            if page.isLastPage { break }
            guard let next = page.nextPageStart, next > start else { break }
            start = next
        }
        return out
    }

    private func getJSON<T: Decodable>(_ type: T.Type, path: String, query: [URLQueryItem] = []) async throws -> T {
        let (data, _) = try await request("GET", path: path, query: query)
        return try decode(type, from: data)
    }

    private func requestJSON(_ method: String, path: String, query: [URLQueryItem] = [], body: [String: Any]) async throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: body, options: [])
        let (data, _) = try await request(method, path: path, query: query, body: payload)
        return data
    }

    private func request(
        _ method: String,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        accept: String = "application/json"
    ) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw EMergerError.invalidServerURL(baseURL.absoluteString)
        }
        components.path = (components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path) + path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw EMergerError.invalidServerURL(baseURL.absoluteString + path)
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw EMergerError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw EMergerError.network("HTTP olmayan yanıt")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.mapError(status: http.statusCode, data: data, accountLabel: accountLabel)
        }
        return (data, http)
    }

    private static func mapError(status: Int, data: Data, accountLabel: String) -> EMergerError {
        if status == 401 { return .unauthorized(accountLabel: accountLabel) }
        if let envelope = try? JSONDecoder().decode(BBErrorEnvelope.self, from: data), let first = envelope.errors.first {
            if let vetoes = first.vetoes, !vetoes.isEmpty {
                return .vetoed(vetoes.map(\.text))
            }
            if status == 409, first.currentVersion != nil || (first.message ?? "").localizedCaseInsensitiveContains("out-of-date") {
                return .outOfDate(currentVersion: first.currentVersion)
            }
            let messages = envelope.errors.compactMap(\.message).joined(separator: " · ")
            return .http(status: status, message: messages.isEmpty ? "Açıklama yok" : messages)
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self)
        let cleaned = text.contains("<") ? "HTML yanıt (SSO / proxy yönlendirmesi olabilir)" : text
        return .http(status: status, message: cleaned.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : cleaned)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw EMergerError.decoding("\(T.self): \(error.localizedDescription)")
        }
    }
}

private extension String {
    var pathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? self
    }
}
