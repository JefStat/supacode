import ComposableArchitecture
import Foundation
import IdentifiedCollections
import Testing

@testable import supacode

@MainActor
struct RepositoriesFeatureFocusedPaneOverrideTests {
  private func makeWorktree(
    id: String,
    name: String,
    repoRoot: String = "/tmp/repo"
  ) -> Worktree {
    Worktree(
      id: WorktreeID(id),
      name: name,
      detail: "detail",
      workingDirectory: URL(fileURLWithPath: id),
      repositoryRootURL: URL(fileURLWithPath: repoRoot),
      createdAt: nil
    )
  }

  private func makeRepository(id: String, worktrees: [Worktree]) -> Repository {
    Repository(
      id: RepositoryID(id),
      rootURL: URL(fileURLWithPath: id),
      name: "repo",
      worktrees: IdentifiedArray(uniqueElements: worktrees)
    )
  }

  private func makeState(repositories: [Repository]) -> RepositoriesFeature.State {
    var state = RepositoriesFeature.State()
    state.repositories = IdentifiedArray(uniqueElements: repositories)
    state.repositoryRoots = repositories.map(\.rootURL)
    return state
  }

  private func makePullRequest(number: Int = 1) -> GithubPullRequest {
    GithubPullRequest(
      number: number,
      title: "PR",
      state: "OPEN",
      additions: 0,
      deletions: 0,
      isDraft: false,
      reviewDecision: nil,
      mergeable: nil,
      mergeStateStatus: nil,
      updatedAt: nil,
      url: "https://example.com/pull/\(number)",
      headRefName: "feature-x",
      baseRefName: "main",
      commitsCount: 1,
      authorLogin: "khoi",
      statusCheckRollup: nil,
      mergeQueueEntry: nil
    )
  }

  @Test func singlePaneNeverResolvesOverride() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let surfaceID = UUID()
    let store = TestStore(initialState: makeState(repositories: [repository])) {
      RepositoriesFeature()
    } withDependencies: {
      $0.terminalClient.surfaceCount = { _ in 1 }
      $0.terminalClient.selectedSurfaceID = { _ in surfaceID }
      $0.terminalClient.focusedSurfacePWD = { _ in
        Issue.record("focusedSurfacePWD should not be read when there's only one pane")
        return nil
      }
      $0.gitClient.repoRoot = { _ in
        Issue.record("gitClient.repoRoot should not run when there's only one pane")
        throw CancellationError()
      }
    }

    await store.send(.focusedSurfaceChanged(worktreeID: worktree.id, surfaceID: surfaceID))
    await store.receive(\.focusedPaneOverrideCleared)
    await store.finish()

    #expect(store.state.focusedPaneOverride == nil)
  }

  @Test func focusedPaneStillInOwnRepoLeavesOverrideNil() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: "/tmp/repo")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let surfaceID = UUID()
    let store = TestStore(initialState: makeState(repositories: [repository])) {
      RepositoriesFeature()
    } withDependencies: {
      $0.terminalClient.surfaceCount = { _ in 2 }
      $0.terminalClient.selectedSurfaceID = { _ in surfaceID }
      $0.terminalClient.focusedSurfacePWD = { _ in "/tmp/repo/main" }
      $0.gitClient.repoRoot = { _ in URL(fileURLWithPath: "/tmp/repo") }
      $0.githubCLI.batchPullRequests = { _, _, _, _ in
        Issue.record("batchPullRequests should not run when the focused pane is still home")
        return [:]
      }
    }

    await store.send(.focusedSurfaceChanged(worktreeID: worktree.id, surfaceID: surfaceID))
    await store.receive(\.focusedPaneOverrideCleared)
    await store.finish()

    #expect(store.state.focusedPaneOverride == nil)
  }

  @Test func focusedPaneInForeignRepoResolvesOverride() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: "/tmp/repo")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let surfaceID = UUID()
    let foreignRoot = URL(fileURLWithPath: "/tmp/other-repo")
    let pullRequest = makePullRequest()
    let store = TestStore(initialState: makeState(repositories: [repository])) {
      RepositoriesFeature()
    } withDependencies: {
      $0.terminalClient.surfaceCount = { _ in 2 }
      $0.terminalClient.focusedSurfacePWD = { _ in "/tmp/other-repo" }
      $0.terminalClient.selectedSurfaceID = { _ in surfaceID }
      $0.gitClient.repoRoot = { _ in foreignRoot }
      $0.gitClient.branchName = { _ in "feature-x" }
      $0.githubCLI.resolveRemoteInfo = { _ in
        GithubRemoteInfo(host: "github.com", owner: "acme", repo: "other-repo")
      }
      $0.githubCLI.batchPullRequests = { _, _, _, branches in
        branches == ["feature-x"] ? ["feature-x": pullRequest] : [:]
      }
    }

    await store.send(.focusedSurfaceChanged(worktreeID: worktree.id, surfaceID: surfaceID))
    await store.receive(\.focusedPaneOverrideResolved) {
      $0.focusedPaneOverride = RepositoriesFeature.State.FocusedPaneOverride(
        worktreeID: worktree.id,
        surfaceID: surfaceID,
        repositoryRootURL: foreignRoot,
        pullRequest: pullRequest
      )
    }
    await store.finish()
  }

  @Test func focusMovingBackToOwnRepoClearsExistingOverride() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: "/tmp/repo")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let foreignSurfaceID = UUID()
    let homeSurfaceID = UUID()
    var initialState = makeState(repositories: [repository])
    initialState.focusedPaneOverride = RepositoriesFeature.State.FocusedPaneOverride(
      worktreeID: worktree.id,
      surfaceID: foreignSurfaceID,
      repositoryRootURL: URL(fileURLWithPath: "/tmp/other-repo"),
      pullRequest: makePullRequest()
    )
    let store = TestStore(initialState: initialState) {
      RepositoriesFeature()
    } withDependencies: {
      $0.terminalClient.surfaceCount = { _ in 2 }
      $0.terminalClient.selectedSurfaceID = { _ in homeSurfaceID }
      $0.terminalClient.focusedSurfacePWD = { _ in "/tmp/repo/main" }
      $0.gitClient.repoRoot = { _ in URL(fileURLWithPath: "/tmp/repo") }
    }

    await store.send(.focusedSurfaceChanged(worktreeID: worktree.id, surfaceID: homeSurfaceID))
    await store.receive(\.focusedPaneOverrideCleared) {
      $0.focusedPaneOverride = nil
    }
    await store.finish()
  }

  @Test func pollDrivenRecheckDetectsInPlaceCdWithoutFocusEvent() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: "/tmp/repo")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let surfaceID = UUID()
    let foreignRoot = URL(fileURLWithPath: "/tmp/other-repo")
    let pullRequest = makePullRequest()
    let store = TestStore(initialState: makeState(repositories: [repository])) {
      RepositoriesFeature()
    } withDependencies: {
      $0.terminalClient.selectedSurfaceID = { _ in surfaceID }
      $0.terminalClient.surfaceCount = { _ in 2 }
      $0.terminalClient.focusedSurfacePWD = { _ in "/tmp/other-repo" }
      $0.gitClient.repoRoot = { _ in foreignRoot }
      $0.gitClient.branchName = { _ in "feature-x" }
      $0.githubCLI.resolveRemoteInfo = { _ in
        GithubRemoteInfo(host: "github.com", owner: "acme", repo: "other-repo")
      }
      $0.githubCLI.batchPullRequests = { _, _, _, _ in ["feature-x": pullRequest] }
    }

    // No `.focusedSurfaceChanged` was ever sent — this simulates a `cd` inside
    // an already-focused pane, picked up only by the polling recheck event.
    await store.send(
      .worktreeInfoEvent(.focusedPaneRecheckRequested(worktreeID: worktree.id))
    )
    await store.receive(\.focusedPaneOverrideResolved) {
      $0.focusedPaneOverride = RepositoriesFeature.State.FocusedPaneOverride(
        worktreeID: worktree.id,
        surfaceID: surfaceID,
        repositoryRootURL: foreignRoot,
        pullRequest: pullRequest
      )
    }
    await store.finish()
  }

  @Test func staleResolutionForNoLongerFocusedSurfaceIsIgnored() async {
    let worktree = makeWorktree(id: "/tmp/repo/main", name: "main", repoRoot: "/tmp/repo")
    let repository = makeRepository(id: "/tmp/repo", worktrees: [worktree])
    let surfaceA = UUID()
    let surfaceC = UUID()
    let store = TestStore(initialState: makeState(repositories: [repository])) {
      RepositoriesFeature()
    } withDependencies: {
      // Focus has already moved on to a third surface by the time this
      // (stale) resolution for surface A lands.
      $0.terminalClient.selectedSurfaceID = { _ in surfaceC }
    }

    await store.send(
      .focusedPaneOverrideResolved(
        worktreeID: worktree.id,
        surfaceID: surfaceA,
        repositoryRootURL: URL(fileURLWithPath: "/tmp/other-repo"),
        pullRequest: makePullRequest()
      )
    )
    await store.finish()

    #expect(store.state.focusedPaneOverride == nil)
  }
}
