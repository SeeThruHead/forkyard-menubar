import AppKit
import Combine
import SwiftUI

@main
enum ForkyardBar {
  @MainActor private static let controller = StatusBarController()

  @MainActor static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.delegate = controller
    app.run()
  }
}

@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
  private let daemon = Daemon()
  private let popover = NSPopover()
  private var item: NSStatusItem?
  private var watcher: AnyCancellable?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.target = self
    item.button?.action = #selector(toggle)
    item.button?.imagePosition = .imageLeading
    self.item = item

    let host = NSHostingController(rootView: MenuContent(daemon: daemon))
    host.sizingOptions = .preferredContentSize
    popover.contentViewController = host
    popover.behavior = .transient
    popover.animates = false

    watcher = daemon.objectWillChange.sink { [weak self] _ in
      DispatchQueue.main.async { self?.refreshButton() }
    }
    refreshButton()
  }

  private func refreshButton() {
    guard let button = item?.button else { return }
    button.image = NSImage(systemSymbolName: daemon.health.symbol, accessibilityDescription: "forkyard")
    button.title = daemon.connected ? " \(daemon.worktrees.count)" : ""
  }

  @objc private func toggle() {
    guard let button = item?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
      return
    }
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    popover.contentViewController?.view.window?.makeKey()
  }
}

struct StateDot: View {
  let state: String

  var color: Color {
    switch state {
    case "Ready", "InfraReady": .green
    case "Done": .teal
    case "Failed", "InfraFailed": .red
    case "Restarting": .purple
    case "Waiting": .gray
    default: .orange
    }
  }

  var body: some View { Circle().fill(color).frame(width: 7, height: 7) }
}

struct ServiceRow: View {
  let daemon: Daemon
  let worktree: Worktree
  let name: String
  let view: ServiceView

  var body: some View {
    HStack(spacing: 6) {
      if view.sharedWith != nil {
        Circle().fill(Color.cyan).frame(width: 7, height: 7)
      } else {
        StateDot(state: view.state.tag)
      }
      Text(name).font(.system(size: 12)).foregroundStyle(view.sharedWith != nil ? Color.cyan : Color.primary)
      if let shared = view.sharedLabel {
        Text(shared).font(.system(size: 11)).foregroundStyle(Color.cyan)
      }
      if let reason = view.state.reason {
        Text(reason).font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
      }
      Spacer()
      if let usage = daemon.usage(of: view) {
        Text("\(usage.cpuText)  \(usage.memoryText)").font(.system(size: 11, design: .monospaced))
          .foregroundStyle(view.sharedWith != nil ? Color.cyan.opacity(0.8) : Color.secondary)
      }
      if let url = view.url, let link = URL(string: url) {
        Button("Open") { NSWorkspace.shared.open(link) }.buttonStyle(.link).font(.system(size: 11))
      }
      if view.kind != "Task" {
        Button { daemon.restart(worktree, name) } label: { Image(systemName: "arrow.clockwise") }
          .buttonStyle(.borderless).help("Restart \(name)")
      }
    }
  }
}

struct WorktreeRow: View {
  let daemon: Daemon
  let worktree: Worktree
  @State private var expanded = false

  var summary: some View {
    HStack(spacing: 8) {
      Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
      Text(worktree.branch).font(.system(size: 13, weight: .semibold))
      Spacer()
      Text("\(daemon.usage(of: worktree).cpuText)  \(daemon.usage(of: worktree).memoryText)")
        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
      if !worktree.failed.isEmpty {
        Text("\(worktree.failed.count) failed").font(.system(size: 11, weight: .medium)).foregroundStyle(.red)
      }
      Text("\(worktree.settledCount)/\(worktree.services.count)")
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 6).padding(.vertical, 1)
        .background(worktree.failed.isEmpty ? (worktree.starting ? Color.orange : Color.green).opacity(0.2) : Color.red.opacity(0.2))
        .clipShape(Capsule())
      Button { daemon.stop(worktree) } label: { Image(systemName: "stop.circle") }
        .buttonStyle(.borderless).help("Stop this worktree")
    }
    .contentShape(Rectangle())
    .onTapGesture { expanded.toggle() }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      summary
      if expanded {
        VStack(alignment: .leading, spacing: 3) {
          ForEach(worktree.serviceNames, id: \.self) { name in
            if let view = worktree.services[name] {
              ServiceRow(daemon: daemon, worktree: worktree, name: name, view: view)
            }
          }
        }
        .padding(.leading, 16)
      }
    }
  }
}

struct RepoSection: View {
  let daemon: Daemon
  let name: String
  let worktrees: [Worktree]
  @State private var open = true

  var usage: Usage { daemon.usage(of: worktrees) }
  var settled: Int { worktrees.reduce(0) { $0 + $1.settledCount } }
  var total: Int { worktrees.reduce(0) { $0 + $1.services.count } }
  var failed: Int { worktrees.reduce(0) { $0 + $1.failed.count } }

  var header: some View {
    HStack(spacing: 8) {
      Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
      Text(name).font(.system(size: 12, weight: .bold))
      Text("\(worktrees.count) \(worktrees.count == 1 ? "branch" : "branches")").font(.system(size: 11)).foregroundStyle(.secondary)
      Spacer()
      Text(failed > 0 ? "\(settled)/\(total) · \(failed) failed" : "\(settled)/\(total)")
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(failed > 0 ? Color.red : Color.secondary)
      Text("\(usage.cpuText)  \(usage.memoryText)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
    }
    .contentShape(Rectangle())
    .onTapGesture { open.toggle() }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      if open {
        ForEach(worktrees) { worktree in WorktreeRow(daemon: daemon, worktree: worktree).padding(.leading, 12) }
      }
    }
  }
}

struct MenuContent: View {
  @ObservedObject var daemon: Daemon
  @State private var contentHeight: CGFloat = 40

  var header: some View {
    HStack {
      Image(systemName: daemon.health.symbol)
      Text("forkyard").font(.system(size: 14, weight: .bold))
      Spacer()
      if daemon.connected {
        Text("\(daemon.worktrees.count) worktrees · \(daemon.processCount) processes · CPU \(daemon.totalUsage.cpuText) · \(daemon.totalUsage.memoryText)")
          .font(.system(size: 11)).foregroundStyle(.secondary)
      } else {
        Text("daemon not running").font(.system(size: 11)).foregroundStyle(.red)
      }
    }
  }

  var listHeight: CGFloat {
    let tallest = (NSScreen.main?.visibleFrame.height ?? 800) * 0.75
    return min(max(contentHeight, 40), tallest)
  }

  var footer: some View {
    HStack {
      Button("Dashboard") { NSWorkspace.shared.open(daemon.dashboard) }
      Button("Terminal UI") { daemon.openTerminalUI() }
      Spacer()
      Button("Quit") { NSApplication.shared.terminate(nil) }
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(daemon.projects, id: \.name) { project in
            RepoSection(daemon: daemon, name: project.name, worktrees: project.worktrees)
          }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
      }
      .frame(height: listHeight)
      Divider()
      if let problem = daemon.problem {
        Text(problem).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
      }
      footer
    }
    .padding(12)
    .frame(width: 520)
  }


}
