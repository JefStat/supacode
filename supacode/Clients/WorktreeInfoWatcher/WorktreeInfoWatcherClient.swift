import ComposableArchitecture
import Foundation

struct WorktreeInfoWatcherClient {
  var send: @MainActor @Sendable (Command) -> Void
  var events: @MainActor @Sendable () -> AsyncStream<Event>

  enum Command: Equatable {
    case setWorktrees([Worktree])
    case setSelectedWorktreeID(Worktree.ID?)
    case setPullRequestTrackingEnabled(Bool)
    case stop
  }

  enum Event: Equatable {
    case branchChanged(worktreeID: Worktree.ID)
    case filesChanged(worktreeID: Worktree.ID)
    case repositoryPullRequestRefresh(repositoryRootURL: URL, worktreeIDs: [Worktree.ID])
    /// Fired on the same cadence as `repositoryPullRequestRefresh`, but only for
    /// the currently selected worktree — catches an in-place `cd` in an
    /// already-focused pane, which doesn't emit a terminal focus-change event.
    case focusedPaneRecheckRequested(worktreeID: Worktree.ID)
  }
}

extension WorktreeInfoWatcherClient: DependencyKey {
  static let liveValue = WorktreeInfoWatcherClient(
    send: { _ in fatalError("WorktreeInfoWatcherClient.send not configured") },
    events: { fatalError("WorktreeInfoWatcherClient.events not configured") }
  )

  static let testValue = WorktreeInfoWatcherClient(
    send: { _ in },
    events: { AsyncStream { $0.finish() } }
  )
}

extension DependencyValues {
  var worktreeInfoWatcher: WorktreeInfoWatcherClient {
    get { self[WorktreeInfoWatcherClient.self] }
    set { self[WorktreeInfoWatcherClient.self] = newValue }
  }
}
