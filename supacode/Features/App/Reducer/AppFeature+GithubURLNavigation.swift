import ComposableArchitecture
import Foundation

extension AppFeature {
  func handleGithubURLNavigation(
    _ url: GithubURL, isResume: Bool = false, state: inout State
  ) -> Effect<Action> {
    let candidates = state.repositories.repositories
      .filter(\.isGitRepository)
      .compactMap { repository in repository.localRootURL.map { (repository.id, $0) } }
    let gitClient = gitClient
    return .merge(
      .send(.repositories(.showToast(.inProgress("Resolving \(url.displaySlug)…")))),
      .run { send in
        let match = await Self.firstRepositoryMatch(
          url: url, candidates: candidates, gitClient: gitClient)
        await send(.githubURLRepositoryMatched(url, match, isResume: isResume))
      }
    )
  }

  func handleGithubURLRepositoryMatched(
    _ url: GithubURL, repositoryID: Repository.ID?, isResume: Bool, state: inout State
  ) -> Effect<Action> {
    let dismissToast: Effect<Action> = .send(.repositories(.dismissToast))
    guard let repositoryID,
      let repository = state.repositories.repositories[id: repositoryID]
    else {
      // Resume runs right after a clone; a still-unmatched URL means the user
      // cloned something else, so re-prompting would discard their choice.
      guard !isResume else { return dismissToast }
      state.pendingGithubNavigation = url
      return .merge(
        dismissToast,
        .send(.repositories(.requestCloneRepository(prefillURL: url.cloneURLString)))
      )
    }
    switch url {
    case .repo:
      guard
        let worktreeID = Self.targetWorktreeID(
          in: repository, mru: state.repositories.worktreeMRU)
      else { return dismissToast }
      return .merge(
        dismissToast,
        .send(.repositories(.selectWorktree(worktreeID, focusTerminal: true)))
      )
    case .pullRequest(let host, let owner, let repo, let number):
      let githubCLI = githubCLI
      return .run { send in
        do {
          let details = try await githubCLI.pullRequestDetails(host, owner, repo, number)
          await send(
            .githubPullRequestDetailsLoaded(url, repositoryID: repositoryID, .success(details)))
        } catch {
          await send(
            .githubPullRequestDetailsLoaded(url, repositoryID: repositoryID, .failure(error)))
        }
      }
    }
  }

  func handleGithubPullRequestDetailsLoaded(
    _ url: GithubURL,
    repositoryID: Repository.ID,
    result: Result<GithubPullRequestDetails, any Error>,
    state: inout State
  ) -> Effect<Action> {
    let dismissToast: Effect<Action> = .send(.repositories(.dismissToast))
    switch result {
    case .failure:
      state.alert = Self.githubURLNavigationAlert(
        title: "Pull request unavailable",
        message: "Couldn't load PR #\(url.pullRequestNumber.map(String.init) ?? "?") for \(url.displaySlug)."
      )
      return dismissToast
    case .success(let details):
      let isFork =
        details.isCrossRepository
        || details.headRepositoryOwner.map {
          $0.login.caseInsensitiveCompare(url.owner) != .orderedSame
        } ?? false
      guard !isFork else {
        state.alert = Self.githubURLNavigationAlert(
          title: "Fork pull requests not supported",
          message: "PR #\(details.number) comes from a fork. Checking out fork PRs isn't supported yet."
        )
        return dismissToast
      }
      guard let repository = state.repositories.repositories[id: repositoryID] else {
        return dismissToast
      }
      if let existing = repository.worktrees.first(where: { $0.name == details.headRefName }) {
        return .merge(
          dismissToast,
          .send(.repositories(.selectWorktree(existing.id, focusTerminal: true)))
        )
      }
      guard details.state == "OPEN" else {
        state.alert = Self.githubURLNavigationAlert(
          title: "Pull request is \(details.state.lowercased())",
          message:
            "PR #\(details.number) is \(details.state.lowercased()), so its branch may no longer exist."
        )
        return dismissToast
      }
      return .merge(
        dismissToast,
        .send(
          .repositories(
            .createWorktreeInRepository(
              repositoryID: repositoryID,
              nameSource: .explicit(details.headRefName),
              baseRefSource: .explicit("origin/\(details.headRefName)"),
              fetchOrigin: true
            )
          )
        )
      )
    }
  }

  static func firstRepositoryMatch(
    url: GithubURL,
    candidates: [(Repository.ID, URL)],
    gitClient: GitClientDependency
  ) async -> Repository.ID? {
    await withTaskGroup(of: Repository.ID?.self) { group in
      for (id, root) in candidates {
        group.addTask {
          guard let info = await gitClient.remoteInfo(root) else { return nil }
          return Self.remoteInfoMatches(info, url) ? id : nil
        }
      }
      var match: Repository.ID?
      for await candidate in group {
        if let candidate {
          match = candidate
          group.cancelAll()
          break
        }
      }
      return match
    }
  }

  static func remoteInfoMatches(_ info: GithubRemoteInfo, _ url: GithubURL) -> Bool {
    info.host.caseInsensitiveCompare(url.host) == .orderedSame
      && info.owner.caseInsensitiveCompare(url.owner) == .orderedSame
      && info.repo.caseInsensitiveCompare(url.repo) == .orderedSame
  }

  static func targetWorktreeID(in repository: Repository, mru: [Worktree.ID]) -> Worktree.ID? {
    mru.first { repository.worktrees[id: $0] != nil } ?? repository.worktrees.first?.id
  }

  static func githubURLNavigationAlert(title: String, message: String) -> AlertState<Alert> {
    AlertState {
      TextState(title)
    } actions: {
      ButtonState(role: .cancel, action: .dismiss) { TextState("OK") }
    } message: {
      TextState(message)
    }
  }
}
