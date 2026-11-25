import SwiftUI
import AppKit
import DevHubCore

struct PortsView: View {
    @EnvironmentObject private var hub: Hub
    @State private var pendingStop: ListeningPort?
    @State private var showOnlyProjects = false

    private var visiblePorts: [ListeningPort] {
        showOnlyProjects ? hub.ports.filter { hub.portOwners[$0.pid] != nil } : hub.ports
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("רק של הפרויקטים שלי", isOn: $showOnlyProjects)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Spacer()
                if hub.portsLoading { ProgressView().controlSize(.mini) }
                Button {
                    Task { await hub.refreshPorts() }
                } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("רענן")
            }

            if visiblePorts.isEmpty {
                Text(hub.portsLoading ? "סורק…" : "אין פורטים פתוחים")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else if visiblePorts.count > 8 {
                // Explicit height: a bare ScrollView collapses inside a MenuBarExtra window.
                ScrollView { portList }.frame(height: 420)
            } else {
                portList
            }
        }
        .onAppear { hub.portsVisible = true }
        .onDisappear { hub.portsVisible = false }
        .confirmationDialog(
            pendingStop.map { "לעצור את \($0.command) (פורט \($0.port))?" } ?? "",
            isPresented: Binding(get: { pendingStop != nil }, set: { if !$0 { pendingStop = nil } }),
            presenting: pendingStop
        ) { port in
            Button("עצור (SIGTERM)") { hub.stopProcess(port) }
            Button("עצור בכוח (SIGKILL)", role: .destructive) { hub.stopProcess(port, force: true) }
            Button("ביטול", role: .cancel) {}
        } message: { port in
            Text("PID \(port.pid). שינויים שלא נשמרו בתהליך הזה עלולים ללכת לאיבוד.")
        }
    }
}

extension PortsView {
    private var portList: some View {
        VStack(spacing: 4) {
            ForEach(visiblePorts) { port in
                PortRow(port: port,
                        project: hub.portOwners[port.pid].flatMap { hub.store.project($0) }) {
                    pendingStop = port
                }
            }
        }
    }
}

struct PortRow: View {
    let port: ListeningPort
    let project: Project?
    let onStop: () -> Void

    private var isMine: Bool { port.user == nil || port.user == NSUserName() }

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(port.port)")
                .font(.system(.body, design: .monospaced).bold())
                .frame(minWidth: 52, alignment: .leading)
                .ltr()

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(port.command).lineLimit(1)
                    if let project {
                        Text(project.name)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text(verbatim: "PID \(port.pid)")
                    if !port.isLocalOnly {
                        // Bound to all interfaces: reachable from the local network (CWE-668).
                        Label("פתוח לרשת", systemImage: "network")
                            .foregroundStyle(.orange)
                            .help("השרת מאזין על כל הממשקים, ומכשירים אחרים ברשת יכולים להתחבר אליו. בשרת פיתוח עדיף להאזין רק ל-127.0.0.1.")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if port.isLocalOnly || port.addresses.contains("*") {
                Button {
                    if let url = URL(string: "http://localhost:\(port.port)") { NSWorkspace.shared.open(url) }
                } label: { Image(systemName: "safari") }
                .help("פתח בדפדפן")
            }

            Button(action: onStop) { Image(systemName: "xmark.circle.fill") }
                .foregroundStyle(isMine ? Color.red : Color.secondary)
                .disabled(!isMine)
                .help(isMine ? "עצור את התהליך" : "שייך למשתמש אחר")
        }
        .buttonStyle(.borderless)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}
