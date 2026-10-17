import Foundation

struct Usage: Hashable, Decodable {
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
