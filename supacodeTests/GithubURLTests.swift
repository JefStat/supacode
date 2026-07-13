import Foundation
import Testing

@testable import supacode

struct GithubURLTests {
  @Test func parsesPlainRepoURL() {
    let url = GithubURL.parse("https://github.com/octo/repo")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func stripsTrailingSlash() {
    let url = GithubURL.parse("https://github.com/octo/repo/")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func stripsGitSuffix() {
    let url = GithubURL.parse("https://github.com/octo/repo.git")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func parsesSchemeless() {
    let url = GithubURL.parse("github.com/octo/repo")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func parsesHTTP() {
    let url = GithubURL.parse("http://github.com/octo/repo")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func normalizesWWWHost() {
    let url = GithubURL.parse("https://www.github.com/octo/repo")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func parsesPullRequestURL() {
    let url = GithubURL.parse("https://github.com/octo/repo/pull/123")
    #expect(url == .pullRequest(host: "github.com", owner: "octo", repo: "repo", number: 123))
  }

  @Test func parsesPullRequestWithFilesTab() {
    let url = GithubURL.parse("https://github.com/octo/repo/pull/123/files")
    #expect(url == .pullRequest(host: "github.com", owner: "octo", repo: "repo", number: 123))
  }

  @Test func parsesPullRequestWithQueryString() {
    let url = GithubURL.parse("https://github.com/octo/repo/pull/123?tab=files")
    #expect(url == .pullRequest(host: "github.com", owner: "octo", repo: "repo", number: 123))
  }

  @Test func degradesTreeURLToRepo() {
    let url = GithubURL.parse("https://github.com/octo/repo/tree/branch")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func rejectsNonGithubHost() {
    let url = GithubURL.parse("https://gitlab.com/octo/repo")
    #expect(url == nil)
  }

  @Test func rejectsReservedFirstPathSegments() {
    #expect(GithubURL.parse("https://github.com/orgs/acme/repositories") == nil)
    #expect(GithubURL.parse("https://github.com/settings/profile") == nil)
    #expect(GithubURL.parse("https://github.com/topics/swift") == nil)
    #expect(GithubURL.parse("https://github.com/search?q=swift") == nil)
  }

  @Test func degradesNonIntegerPullSegmentToRepo() {
    let url = GithubURL.parse("https://github.com/octo/repo/pull/abc")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func trimsSurroundingWhitespace() {
    let url = GithubURL.parse("  https://github.com/octo/repo  ")
    #expect(url == .repo(host: "github.com", owner: "octo", repo: "repo"))
  }

  @Test func repoComputedProperties() {
    let url = GithubURL.parse("https://github.com/octo/repo")
    #expect(url?.slug == "github.com/octo/repo")
    #expect(url?.cloneURLString == "https://github.com/octo/repo.git")
    #expect(url?.displaySlug == "octo/repo")
  }

  @Test func pullRequestComputedProperties() {
    let url = GithubURL.parse("https://github.com/octo/repo/pull/123")
    #expect(url?.slug == "github.com/octo/repo")
    #expect(url?.cloneURLString == "https://github.com/octo/repo.git")
    #expect(url?.displaySlug == "octo/repo")
  }
}
