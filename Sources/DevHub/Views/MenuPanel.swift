import SwiftUI
import AppKit
import DevHubCore

enum PanelTab: String, CaseIterable {
    case projects = "פרויקטים"
    case ports = "פורטים"
}

struct MenuPanel: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.openWindow) private var openWindow
    @State private var tab: PanelTab = .projects

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DevHub").font(.headline)
                Spacer()
                if tab == .projects {
                    Button {
                        hub.editing = Project()
                        openWindow(id: WindowID.editor)
                        bringToFront()
                    } label: {
                        Label("פרויקט", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    openWindow(id: WindowID.settings)
                    bringToFront()
                } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("הגדרות")
            }

            Picker("", selection: $tab) {
                ForEach(PanelTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let notice = hub.notice {
                HStack(alignment: .top) {
                    Text(notice).font(.caption).textSelection(.enabled)
                    Spacer()
                    Button { hub.notice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if tab == .ports {
                PortsView()
            } else if hub.projects.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("אין עדיין פרויקטים").font(.subheadline.bold())
                    Text("לחץ על ״+ פרויקט״ ובחר את התיקייה של אפליקציה שאתה מפתח.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            } else {
                // A bare ScrollView can collapse to zero height inside a MenuBarExtra window,
                // so use the natural height and only scroll when the list is too tall.
                ViewThatFits(in: .vertical) {
                    projectList
                    ScrollView { projectList }
                        .frame(height: 480)
                }
            }

            Divider()
            HStack {
                if hub.anyRunning {
                    Button("עצור הכל") { hub.stopAll() }
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button("יציאה") {
                    hub.stopAll()
                    NSApp.terminate(nil)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        .rtl()
    }

    private var projectList: some View {
        VStack(spacing: 8) {
            ForEach(hub.projects) { project in
                if let runner = hub.runner(for: project.id) {
                    ProjectRow(project: project, runner: runner)
                } else {
                    HStack {
                        Text(project.name)
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                    .padding(10)
                }
            }
        }
    }
}

struct ProjectRow: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.openWindow) private var openWindow
    let project: Project
    @ObservedObject var runner: ProjectRunner

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(project.name).font(.system(.body, weight: .semibold))
                        Text(project.kind.label)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                    HStack(spacing: 4) {
                        Text(runner.status.label)
                        if runner.isRunning, let started = runner.startedAt {
                            Text("·")
                            ElapsedText(since: started)
                            if let usage = hub.usage[project.id] {
                                Text("·")
                                Text(verbatim: String(format: "CPU %.0f%%", usage.cpuPercent))
                                Text(ByteCountFormatter.string(fromByteCount: usage.residentBytes, countStyle: .memory))
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    runner.isRunning ? runner.stop() : runner.start()
                } label: {
                    Image(systemName: runner.isRunning ? "stop.fill" : "play.fill")
                }
                .help(runner.isRunning ? "עצור" : "הרץ")

                Menu {
                    Button("לוגים") { open(WindowID.logs) { hub.logsProjectID = project.id } }
                    Button("היסטוריית קריסות") { open(WindowID.history) { hub.historyProjectID = project.id } }
                    Button("פתח ב-Finder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: project.path))
                    }
                    Divider()
                    Button("הגדרות…") { open(WindowID.editor) { hub.editing = project } }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .buttonStyle(.borderless)

            if let crash = runner.crash {
                CrashCard(project: project, crash: crash)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func open(_ id: String, prepare: () -> Void) {
        prepare()
        openWindow(id: id)
        bringToFront()
    }

    private var statusColor: Color {
        switch runner.status {
        case .running: return .green
        case .crashed: return .red
        case .exited(let c): return c == 0 ? .gray : .orange
        case .stopped: return .gray
        }
    }
}

struct CrashCard: View {
    @EnvironmentObject private var hub: Hub
    let project: Project
    let crash: CrashReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("קריסה", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption.bold())
                Spacer()
                Text(crash.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            }

            Text(crash.triggerLine)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .ltr()

            if !crash.fileRefs.isEmpty {
                Text(crash.fileRefs.prefix(3).map(\.display).joined(separator: "  ·  "))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .ltr()
            }

            if let session = hub.fixes[project.id] {
                FixStatusView(project: project, session: session)
            } else {
                HStack {
                    Button {
                        hub.startFix(projectID: project.id)
                    } label: {
                        Label("תקן עם Claude Code", systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("התעלם") { hub.runner(for: project.id)?.clearCrash() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
        .padding(8)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct FixStatusView: View {
    @EnvironmentObject private var hub: Hub
    @Environment(\.openWindow) private var openWindow
    let project: Project
    @ObservedObject var session: FixSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch session.phase {
            case .snapshot, .claude, .building:
                HStack {
                    ProgressView().controlSize(.small)
                    Text(session.phase.label).font(.caption)
                    ElapsedText(since: session.startedAt)
                    Spacer()
                    Button("עצור") { hub.cancelFix(projectID: project.id) }
                        .controlSize(.small)
                        .help("עוצר את Claude ומחזיר את הקוד למצב שלפני")
                }

            case .needsGit(let state):
                Text(session.phase.label).font(.caption)
                Text(state == .notRepo
                     ? "DevHub יריץ git init, ייצור ‎.gitignore‎ שמחריג קבצי build וסודות (‎.env‎, מפתחות), ויעשה commit ראשון."
                     : "DevHub יעשה commit ראשון לקבצים הקיימים.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(state == .notRepo ? "אתחל git והמשך" : "צור commit והמשך") {
                        hub.initializeGitAndRetry(projectID: project.id)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("ביטול") { hub.dismissFix(projectID: project.id) }
                }

            case .review:
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(session.phase.label).font(.caption)
                    Spacer()
                    Button("פתח לבדיקה") {
                        hub.reviewProjectID = project.id
                        openWindow(id: WindowID.review)
                        bringToFront()
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .failed(let message, let details):
                ErrorDetails(message: message, details: details)
                HStack {
                    Button("נסה שוב") {
                        hub.dismissFix(projectID: project.id)
                        hub.startFix(projectID: project.id)
                    }
                    if !session.diff.isEmpty {
                        Button("בטל שינויים חלקיים") { hub.rejectFix(projectID: project.id) }
                    }
                    Spacer()
                    Button("סגור") { hub.dismissFix(projectID: project.id) }
                }
                .controlSize(.small)

            case .cancelled:
                HStack {
                    Text(session.phase.label).font(.caption)
                    Spacer()
                    Button("סגור") { hub.dismissFix(projectID: project.id) }.controlSize(.small)
                }

            case .idle:
                EmptyView()
            }
        }
    }
}
