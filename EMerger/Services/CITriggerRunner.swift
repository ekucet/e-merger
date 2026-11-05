//
//  CITriggerRunner.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

/// Fires a `CITrigger` for a PR: substitutes placeholders into the URL/body,
/// attaches the Keychain-held secret header, and reports the HTTP status.
enum CITriggerRunner {
    struct Outcome: Sendable {
        let status: Int
        let url: String
    }

    static func fire(_ trigger: CITrigger, for pr: BBPullRequest, secret: String?) async throws -> Outcome {
        let urlText = trigger.substitute(trigger.urlTemplate.trimmingCharacters(in: .whitespacesAndNewlines), pr: pr, urlEncode: true)
        guard let url = URL(string: urlText), url.scheme != nil, url.host != nil else {
            throw EMergerError.ciTriggerFailed("Geçersiz URL: \(urlText)")
        }

        var req = URLRequest(url: url)
        req.httpMethod = trigger.method.uppercased()
        req.timeoutInterval = 30
        req.setValue("E-Merger/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        if let secret, !secret.isEmpty, !trigger.secretHeaderName.isEmpty {
            req.setValue(secret, forHTTPHeaderField: trigger.secretHeaderName)
        }
        let body = trigger.bodyTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !body.isEmpty, req.httpMethod != "GET" {
            let isJSON = trigger.contentType.lowercased().contains("json")
            req.httpBody = Data(trigger.substitute(body, pr: pr, urlEncode: !isJSON).utf8)
            req.setValue(trigger.contentType, forHTTPHeaderField: "Content-Type")
        }

        let session = URLSession(configuration: .ephemeral)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw EMergerError.ciTriggerFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw EMergerError.ciTriggerFailed("HTTP olmayan yanıt")
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(decoding: data.prefix(200), as: UTF8.self)
            throw EMergerError.ciTriggerFailed("HTTP \(http.statusCode) \(snippet)")
        }
        return Outcome(status: http.statusCode, url: urlText)
    }
}
