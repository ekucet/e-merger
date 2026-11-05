//
//  CITrigger.swift
//  E-Merger
//
//  Created by Mr. t.
//

import Foundation

/// A generic HTTP hook that starts a CI build for a PR (Jenkins `buildWithParameters`,
/// Bamboo queue, a webhook — anything reachable by URL). The URL and body are
/// templates; placeholders are substituted from the PR:
///
///   {project} {repo} {prId} {branch} {targetBranch} {commit} {title}
///
/// An optional secret header (e.g. `Authorization: Bearer …`) is stored in the
/// Keychain, keyed on the trigger id — never in the config file.
struct CITrigger: Codable, Identifiable, Hashable, Sendable {
    var id: String = UUID().uuidString
    var name: String
    var urlTemplate: String
    var method: String = "POST"
    var bodyTemplate: String = ""
    var contentType: String = "application/json"
    var secretHeaderName: String = ""
    /// Restrict to one repo (`PROJECT/repo`); empty = applies to every PR.
    var repoFilter: String = ""

    static let placeholders = ["{project}", "{repo}", "{prId}", "{branch}", "{targetBranch}", "{commit}", "{title}"]

    func applies(to pr: BBPullRequest) -> Bool {
        let filter = repoFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filter.isEmpty else { return true }
        return filter.caseInsensitiveCompare(pr.toRef.repository.display) == .orderedSame
    }

    func substitute(_ template: String, pr: BBPullRequest, urlEncode: Bool) -> String {
        func enc(_ s: String) -> String {
            guard urlEncode else { return s }
            return s.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? s
        }
        var out = template
        let map: [String: String] = [
            "{project}": pr.projectKey,
            "{repo}": pr.repoSlug,
            "{prId}": String(pr.id),
            "{branch}": pr.fromRef.branchName,
            "{targetBranch}": pr.toRef.branchName,
            "{commit}": pr.fromRef.latestCommit ?? "",
            "{title}": pr.title,
        ]
        for (k, v) in map {
            out = out.replacingOccurrences(of: k, with: enc(v))
        }
        return out
    }
}

extension CharacterSet {
    /// RFC 3986 unreserved + what is safe inside a query value.
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
