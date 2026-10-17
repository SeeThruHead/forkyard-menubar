import Foundation
import UserNotifications

struct Envelope: Decodable {
  let tag: String
  let requestId: String?

  enum CodingKeys: String, CodingKey { case tag = "_tag", requestId }
}

struct StatusChunk: Decodable {
  let values: [[String: Worktree]]
}

struct UsageChunk: Decodable {
  let values: [[String: Usage]]
}

@MainActor
final class Daemon: ObservableObject {
  @Published private(set) var worktrees: [Worktree] = []
  @Published private(set) var connected = false
  @Published private(set) var usage: [Int: Usage] = [:]

  let dashboard = URL(string: "http://forkyard.localhost")!
  private let endpoint: URL
  private var socket: URLSessionWebSocketTask?
  private var nextId = 100
  private var lastStates: [String: String] = [:]

  init(port: Int = Int(ProcessInfo.processInfo.environment["FORKYARD_HTTP_PORT"] ?? "") ?? 4949) {
    endpoint = URL(string: "ws://127.0.0.1:\(port)/rpc")!
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    connect()
  }

  func usage(of worktree: Worktree) -> Usage { worktree.pids.compactMap { usage[$0] }.reduce(.zero, +) }

  func usage(of view: ServiceView) -> Usage? { view.state.run.flatMap { usage[$0.pid] } }

  var totalUsage: Usage { worktrees.map { usage(of: $0) }.reduce(.zero, +) }

  var processCount: Int { worktrees.reduce(0) { $0 + $1.services.count } }



  var health: Health { Health.of(worktrees, connected: connected) }

  var projects: [(name: String, worktrees: [Worktree])] {
    Dictionary(grouping: worktrees, by: \.project)
      .map { (name: $0.key, worktrees: $0.value.sorted { a, b in a.branch == "main" || (b.branch != "main" && a.branch < b.branch) }) }
      .sorted { $0.name < $1.name }
  }

  func restart(_ worktree: Worktree, _ service: String) {
    send(tag: "Restart", payload: ["id": worktree.id, "service": service])
  }

  func stop(_ worktree: Worktree) {
    send(tag: "Down", payload: ["id": worktree.id])
  }

  private func connect() {
    let task = URLSession.shared.webSocketTask(with: endpoint)
    socket = task
    task.resume()
    send(tag: "Status", payload: nil, id: "1")
    send(tag: "Usage", payload: nil, id: "2")
    receive(task)
  }

  private func reconnectLater() {
    connected = false
    socket = nil
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      self.connect()
    }
  }

  private func send(tag: String, payload: [String: String]?, id: String? = nil) {
    let requestId = id ?? String(nextId)
    nextId += 1
    let body: [String: Any] = ["_tag": "Request", "id": requestId, "tag": tag, "payload": payload ?? NSNull(), "headers": []]
    guard let data = try? JSONSerialization.data(withJSONObject: body), let text = String(data: data, encoding: .utf8) else { return }
    socket?.send(.string(text)) { _ in }
  }

  private func receive(_ task: URLSessionWebSocketTask) {
    task.receive { [weak self] result in
      Task { @MainActor in
        guard let self, self.socket === task else { return }
        switch result {
        case .failure:
          self.reconnectLater()
        case .success(.string(let text)):
          self.handle(Data(text.utf8))
          self.receive(task)
        case .success(.data(let data)):
          self.handle(data)
          self.receive(task)
        case .success:
          self.receive(task)
        }
      }
    }
  }

  private func handle(_ data: Data) {
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
      return
    }
    guard envelope.tag == "Chunk", let requestId = envelope.requestId else { return }
    send(ack: requestId)
    if requestId == "2" {
      guard let chunk = try? JSONDecoder().decode(UsageChunk.self, from: data), let latest = chunk.values.last else { return }
      usage = Dictionary(latest.compactMap { key, value in Int(key).map { ($0, value) } }, uniquingKeysWith: { first, _ in first })
      return
    }
    guard requestId == "1" else { return }
    guard let chunk = try? JSONDecoder().decode(StatusChunk.self, from: data), let snapshot = chunk.values.last else { return }
    connected = true
    notifyFailures(Array(snapshot.values))
    worktrees = Array(snapshot.values)
  }

  private func send(ack requestId: String) {
    socket?.send(.string(#"{"_tag":"Ack","requestId":"\#(requestId)"}"#)) { _ in }
  }

  private func notifyFailures(_ next: [Worktree]) {
    let states = Dictionary(
      next.flatMap { worktree in worktree.services.map { ("\(worktree.id)/\($0.key)", $0.value.state.tag) } },
      uniquingKeysWith: { first, _ in first }
    )
    let newlyFailed = states.filter { $0.value == "Failed" && lastStates[$0.key] != nil && lastStates[$0.key] != "Failed" }.keys
    lastStates = states
    newlyFailed.sorted().forEach(notify)
  }

  private func notify(_ key: String) {
    let content = UNMutableNotificationContent()
    content.title = "forkyard: a service failed"
    content.body = key
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
  }
}
