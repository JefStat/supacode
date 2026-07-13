import Foundation

nonisolated enum GithubURL: Equatable, Hashable, Sendable {
  case repo(host: String, owner: String, repo: String)
  case pullRequest(host: String, owner: String, repo: String, number: Int)

  static func parse(_ query: String) -> GithubURL? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let withoutScheme: Substring
    if let range = trimmed.range(of: "://") {
      withoutScheme = trimmed[range.upperBound...]
    } else {
      withoutScheme = trimmed[...]
    }

    guard let slashIndex = withoutScheme.firstIndex(of: "/") else { return nil }
    let hostPart = withoutScheme[..<slashIndex].lowercased()
    guard hostPart == "github.com" || hostPart == "www.github.com" else { return nil }
    let host = "github.com"

    var rest = withoutScheme[withoutScheme.index(after: slashIndex)...]
    if let fragmentIndex = rest.firstIndex(of: "#") {
      rest = rest[..<fragmentIndex]
    }
    if let queryIndex = rest.firstIndex(of: "?") {
      rest = rest[..<queryIndex]
    }

    let segments = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    guard segments.count >= 2 else { return nil }

    let owner = segments[0]
    guard !Self.reservedOwnerSegments.contains(owner.lowercased()) else { return nil }
    var repo = segments[1]
    if repo.hasSuffix(".git") {
      repo.removeLast(4)
    }
    guard !owner.isEmpty, !repo.isEmpty else { return nil }

    guard segments.count > 2 else {
      return .repo(host: host, owner: owner, repo: repo)
    }

    guard segments[2] == "pull", segments.count > 3, let number = Int(segments[3]) else {
      return .repo(host: host, owner: owner, repo: repo)
    }

    return .pullRequest(host: host, owner: owner, repo: repo, number: number)
  }

  // GitHub routes where the first path segment is a product page, not a user
  // or organization; treating them as owners would offer nonsense clones.
  private static let reservedOwnerSegments: Set<String> = [
    "about", "apps", "codespaces", "collections", "dashboard", "explore",
    "features", "issues", "login", "marketplace", "new", "notifications",
    "orgs", "pricing", "pulls", "search", "settings", "sponsors", "topics",
    "trending",
  ]

  var host: String {
    switch self {
    case .repo(let host, _, _), .pullRequest(let host, _, _, _):
      host
    }
  }

  var owner: String {
    switch self {
    case .repo(_, let owner, _), .pullRequest(_, let owner, _, _):
      owner
    }
  }

  var repo: String {
    switch self {
    case .repo(_, _, let repo), .pullRequest(_, _, let repo, _):
      repo
    }
  }

  var pullRequestNumber: Int? {
    switch self {
    case .repo:
      nil
    case .pullRequest(_, _, _, let number):
      number
    }
  }

  var cloneURLString: String {
    "https://\(host)/\(owner)/\(repo).git"
  }

  var slug: String {
    "\(host)/\(owner)/\(repo)"
  }

  var displaySlug: String {
    "\(owner)/\(repo)"
  }
}
