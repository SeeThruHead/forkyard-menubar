import Foundation

struct RunRef: Decodable, Hashable {
  let runId: Int
  let run: Int
  let pid: Int
}

struct ServiceState: Decodable, Hashable {
  let tag: String
  let run: RunRef?
  let reason: String?

  enum CodingKeys: String, CodingKey { case tag = "_tag", run, reason }
}

struct ServiceView: Decodable, Hashable {
  let kind: String
  let url: String?
  let state: ServiceState
  let sharedWith: String?

  enum CodingKeys: String, CodingKey { case kind = "_tag", url, state, sharedWith }

  var sharedLabel: String? { sharedWith.map { "via " + ($0.split(separator: ".").first.map(String.init) ?? $0) } }
}

struct InfraView: Decodable, Hashable {
  let tag: String
  let scope: String
  let url: String?
  let reason: String?

  enum CodingKeys: String, CodingKey { case tag = "_tag", scope, url, reason }
}

struct Worktree: Decodable, Hashable, Identifiable {
  let id: String
  let project: String
  let branch: String
  let root: String
  let services: [String: ServiceView]
  let infra: [String: InfraView]

  var serviceNames: [String] { services.keys.sorted() }
  var failed: [String] { serviceNames.filter { services[$0]?.state.tag == "Failed" } }
  var sharedCount: Int { services.values.filter { $0.sharedWith != nil }.count }
  var settledCount: Int { services.values.filter { ["Ready", "Done"].contains($0.state.tag) }.count }
  var allPids: [Int] { services.values.compactMap { $0.state.run?.pid } }
  var ownPids: [Int] { services.values.filter { $0.sharedWith == nil }.compactMap { $0.state.run?.pid } }

  var starting: Bool { services.values.contains { ["Waiting", "Preparing", "Starting", "Restarting"].contains($0.state.tag) } }
}

enum Health {
  case down, ok, starting, failing

  static func of(_ worktrees: [Worktree], connected: Bool) -> Health {
    if !connected { return .down }
    if worktrees.contains(where: { !$0.failed.isEmpty }) { return .failing }
    if worktrees.contains(where: { $0.starting }) { return .starting }
    return .ok
  }

  var symbol: String {
    switch self {
    case .down: "bolt.horizontal.circle"
    case .ok: "arrow.triangle.branch"
    case .starting: "hourglass"
    case .failing: "exclamationmark.triangle.fill"
    }
  }
}
