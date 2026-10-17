import AppKit
import SwiftUI

@main
struct ForkyardBarApp: App {
  @StateObject private var daemon = Daemon()

  var body: some Scene {
    MenuBarExtra {
      MenuContent(daemon: daemon)
    } label: {
      MenuLabel(daemon: daemon)
    }
    .menuBarExtraStyle(.window)
  }
}

struct MenuLabel: View {
  @ObservedObject var daemon: Daemon

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: daemon.health.symbol)
      if daemon.connected { Text("\(daemon.worktrees.count)") }
    }
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
      StateDot(state: view.state.tag)
      Text(name).font(.system(size: 12))
      if let reason = view.state.reason {
        Text(reason).font(.system(size: 11)).foregroundStyle(.red).lineLimit(1)
      }
      Spacer()
      if let usage = daemon.usage(of: view) {
        Text("\(usage.cpuText)  \(usage.memoryText)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
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

struct MenuContent: View {
  @ObservedObject var daemon: Daemon

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
    let rows = daemon.worktrees.count * 30 + daemon.projects.count * 24
    return CGFloat(min(max(rows, 40), 560))
  }

  var footer: some View {
    HStack {
      Button("Dashboard") { NSWorkspace.shared.open(daemon.dashboard) }
      Button("Terminal UI") { openTerminalUI() }
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
            VStack(alignment: .leading, spacing: 6) {
              Text(project.name.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
              ForEach(project.worktrees) { worktree in WorktreeRow(daemon: daemon, worktree: worktree) }
            }
          }
        }
      }
      .frame(height: listHeight)
      Divider()
      footer
    }
    .padding(12)
    .frame(width: 520)
  }

  private func openTerminalUI() {
    let script = #"tell application "Terminal" to do script "forkyard attach""#
    NSAppleScript(source: script)?.executeAndReturnError(nil)
  }
}
