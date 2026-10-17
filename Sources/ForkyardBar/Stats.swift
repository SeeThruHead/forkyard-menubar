import Foundation

struct Usage: Hashable {
  let cpu: Double
  let rssKb: Int

  static let zero = Usage(cpu: 0, rssKb: 0)

  static func + (a: Usage, b: Usage) -> Usage { Usage(cpu: a.cpu + b.cpu, rssKb: a.rssKb + b.rssKb) }

  var cpuText: String { String(format: "%.0f%%", cpu) }

  var memoryText: String {
    let mb = Double(rssKb) / 1024
    return mb >= 1024 ? String(format: "%.1fG", mb / 1024) : String(format: "%.0fM", mb)
  }
}

private struct ProcessRow {
  let pid: Int
  let ppid: Int
  let usage: Usage
}

enum ProcessStats {
  static func sample(pids: [Int]) async -> [Int: Usage] {
    let rows = parse(await readProcesses())
    let children = Dictionary(grouping: rows, by: \.ppid)
    let byPid = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
    return Dictionary(pids.compactMap { pid in byPid[pid].map { (pid, tree($0, children)) } }, uniquingKeysWith: { first, _ in first })
  }

  private static func tree(_ row: ProcessRow, _ children: [Int: [ProcessRow]]) -> Usage {
    (children[row.pid] ?? []).reduce(row.usage) { total, child in total + tree(child, children) }
  }

  private static func parse(_ output: String) -> [ProcessRow] {
    output.split(separator: "\n").compactMap { line in
      let parts = line.split(separator: " ", omittingEmptySubsequences: true)
      guard parts.count == 4, let pid = Int(parts[0]), let ppid = Int(parts[1]), let cpu = Double(parts[2]), let rss = Int(parts[3]) else { return nil }
      return ProcessRow(pid: pid, ppid: ppid, usage: Usage(cpu: cpu, rssKb: rss))
    }
  }

  private static func readProcesses() async -> String {
    await withCheckedContinuation { continuation in
      let process = Process()
      let pipe = Pipe()
      process.executableURL = URL(fileURLWithPath: "/bin/ps")
      process.arguments = ["-A", "-o", "pid=,ppid=,%cpu=,rss="]
      process.standardOutput = pipe
      process.terminationHandler = { _ in
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        continuation.resume(returning: String(decoding: data, as: UTF8.self))
      }
      do { try process.run() } catch { continuation.resume(returning: "") }
    }
  }
}
